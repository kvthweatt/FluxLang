#!/usr/bin/env python3
"""
Flux Code Generator

Copyright (C) 2026 Karac Thweatt

Separates IR emission from AST node definitions.  All LLVM IR generation
that previously lived as .codegen() methods on AST node classes is being
migrated here, one node at a time.

Migration status
----------------
Nodes whose codegen has been moved here are marked [DONE].
Nodes still delegating back to their own .codegen() are marked [PENDING].

Once every node is [DONE], fast.py will no longer import llvmlite and
ASTNode.codegen() will be removed entirely.

Usage
-----
    from fcodegen import visitor
    ir_module = visitor.compile(program_node, module)   # top-level entry point

    # Or for individual nodes during transition:
    result = visitor.visit(node, builder, module)
"""

import sys
import inspect
import traceback
from typing import Any, Optional

from llvmlite import ir

# All AST node classes and type-system helpers are imported via fast.py's
# wildcard re-export of ftypesys.  We import fast lazily inside methods that
# need concrete node types to avoid circular-import issues during the
# transition (fast.py still imports from ftypesys, which may import fcodegen).
#
# ftypesys symbols (TypeSystem, DataType, SymbolKind, …) are safe to import
# at module level because ftypesys does NOT import fcodegen.
from ftypesys import *

# ---------------------------------------------------------------------------
# Calling-convention map (migrated from FunctionDef._CALLING_CONV_MAP)
# ---------------------------------------------------------------------------

CALLING_CONV_MAP: dict = {
    'cdecl':      'ccc',
    'stdcall':    'x86_stdcallcc',
    'fastcall':   'fastcc',
    'thiscall':   'x86_thiscallcc',
    'vectorcall': 'x86_vectorcallcc',
}

# ---------------------------------------------------------------------------
# Module-level helpers (migrated from fast.py module scope)
# These still exist in fast.py during the transition; they will be removed
# from there once every caller has been updated.
# ---------------------------------------------------------------------------

_BUILTIN_OP_SYMBOL_MANGLE: dict = {
    '+': 'plus', '-': 'minus', '*': 'mul', '/': 'div', '%': 'mod',
    '!': 'not', '^': 'pow', '&': 'and', '|': 'or',
    '<': 'lt', '>': 'gt', '=': 'eq', '~': 'tilde', '`': 'tick',
}


def _mangle_builtin_op(symbol: str) -> str:
    """Reproduce the parser's _mangle_op_symbol logic for built-in operator names."""
    multi = sorted(
        ['^^!&', '^^!|', '^^!', '^^', '!&', '!|', '<=', '>=', '==', '!=',
         '++', '--', '<<', '>>', '`!&', '`!|', '`^^'],
        key=len, reverse=True)
    parts = []
    i = 0
    while i < len(symbol):
        matched = False
        for m in multi:
            if symbol[i:i + len(m)] == m:
                parts.append(m)
                i += len(m)
                matched = True
                break
        if not matched:
            parts.append(symbol[i])
            i += 1
    mangled_parts = []
    for part in parts:
        mangled_parts.append(
            '_'.join(_BUILTIN_OP_SYMBOL_MANGLE.get(c, hex(ord(c))) for c in part))
    return '_'.join(mangled_parts)


def _collect_label_names(stmts) -> list:
    """Recursively walk a statement list and collect all LabelStatement names."""
    # Import lazily to avoid circular imports during transition.
    from fast import LabelStatement, Block
    names = []
    for stmt in stmts:
        if stmt is None:
            continue
        if isinstance(stmt, LabelStatement):
            names.append(stmt.name)
        if isinstance(stmt, Block):
            names.extend(_collect_label_names(stmt.statements))
        elif hasattr(stmt, 'body') and isinstance(getattr(stmt, 'body', None), Block):
            names.extend(_collect_label_names(stmt.body.statements))
        elif hasattr(stmt, 'then_block') and isinstance(getattr(stmt, 'then_block', None), Block):
            names.extend(_collect_label_names(stmt.then_block.statements))
        if hasattr(stmt, 'else_block') and isinstance(getattr(stmt, 'else_block', None), Block):
            names.extend(_collect_label_names(stmt.else_block.statements))
    return names


def _emit_va_arg(builder: ir.IRBuilder, va_list_i8ptr: ir.Value,
                 arg_type: ir.Type, name: str = '') -> ir.Value:
    """Emit a va_arg instruction using llvmlite's low-level instruction API."""
    from llvmlite.ir import instructions as _insns

    class _VaArgInstr(_insns.Instruction):
        def __init__(self, parent, typ, ptr, name=''):
            super().__init__(parent, typ, 'va_arg', [ptr], name)
            self._va_type = typ

        def descr(self, buf):
            buf.append(
                f'va_arg {self.operands[0].type} '
                f'{self.operands[0].get_reference()}, {self._va_type}\n')

    instr = _VaArgInstr(builder.block, arg_type, va_list_i8ptr, name)
    builder._insert(instr)
    return instr


def _get_fp_cconv(pointer_expr, module) -> Optional[str]:
    """Look up the LLVM calling convention for an indirect call through a named function pointer."""
    from fast import Identifier
    name = None
    if isinstance(pointer_expr, Identifier):
        name = pointer_expr.name
    if name and hasattr(module, '_flux_fp_calling_convs'):
        return module._flux_fp_calling_convs.get(name)
    return None


def register_struct_type(module: ir.Module, type_name: str,
                         bit_width: int, alignment: int) -> None:
    """Register a custom data type in the module's type registry."""
    if not hasattr(module, '_custom_types'):
        module._custom_types = {}
    module._custom_types[type_name] = {
        'bit_width': bit_width,
        'alignment': alignment,
    }


def get_struct_vtable(module: ir.Module, struct_name: str):
    """Get vtable for a struct type."""
    if not hasattr(module, '_struct_vtables'):
        return None
    return module._struct_vtables.get(struct_name)


# ---------------------------------------------------------------------------
# CodegenVisitor
# ---------------------------------------------------------------------------

class CodegenVisitor:
    """
    Visitor that drives LLVM IR generation for every Flux AST node.

    Dispatch
    --------
    visit(node, builder, module)
        Looks up visit_<ClassName> on self and calls it.
        Falls back to node.codegen(builder, module) for nodes that have not
        yet been migrated (PENDING nodes).  This lets us migrate one node at
        a time while keeping the compiler runnable throughout.

    Entry point
    -----------
    compile(program, module=None) -> ir.Module
        Drives the 4-pass compilation sequence currently in Program.codegen().
        Migrated in Phase 3 once all other nodes are done.
    """

    # ------------------------------------------------------------------
    # Core dispatcher
    # ------------------------------------------------------------------

    def visit(self, node, builder: ir.IRBuilder, module: ir.Module) -> Any:
        """
        Dispatch to visit_<ClassName>(node, builder, module).

        If no such method exists, the node has not been migrated yet.
        Delegate to node.codegen() so the compiler keeps working.
        """
        if node is None:
            return None

        method_name = f'visit_{type(node).__name__}'
        method = getattr(self, method_name, None)

        if method is not None:
            return method(node, builder, module)

        # PENDING: node not yet migrated — fall back to the node's own codegen.
        if hasattr(node, 'codegen'):
            return node.codegen(builder, module)

        raise NotImplementedError(
            f"CodegenVisitor: no visit method for {type(node).__name__} "
            f"and node has no codegen() [{getattr(node, 'source_line', '?')}:"
            f"{getattr(node, 'source_col', '?')}]"
        )

    # ------------------------------------------------------------------
    # Top-level compilation entry point  [PENDING — migrated in Phase 3]
    # ------------------------------------------------------------------

    def compile(self, program, module: ir.Module = None) -> ir.Module:
        """
        Compile a Program node to an ir.Module.

        Currently delegates to Program.codegen() — the 4-pass driver will be
        moved here in Phase 3 once all individual nodes are migrated.
        """
        return program.codegen(module)

    # ------------------------------------------------------------------
    # Tier 0 — trivial / leaf nodes  [DONE]
    # ------------------------------------------------------------------

    def visit_NoInit(self, node, builder, module):
        raise RuntimeError(
            f"noinit is a compile-time marker and should not generate code directly. "
            f"It should only be used as an initializer in variable declarations. "
            f"[{node.source_line}:{node.source_col}]"
        )

    def visit_IRStore(self, node, builder, module):
        return node.ir_value

    def visit_ExpressionStatement(self, node, builder, module):
        return self.visit(node.expression, builder, module)

    # -- using / !using --------------------------------------------------

    def visit_UsingStatement(self, node, builder, module):
        if not hasattr(module, '_using_namespaces'):
            module._using_namespaces = []
        node.namespace_path = node.namespace_path.replace("::", "__")
        module._using_namespaces.append(node.namespace_path)
        if hasattr(module, 'symbol_table'):
            module.symbol_table.add_using_namespace(node.namespace_path)

    def visit_NotUsingStatement(self, node, builder, module):
        if not hasattr(module, '_excluded_namespaces'):
            module._excluded_namespaces = set()
        node.namespace_path = node.namespace_path.replace("::", "__")
        module._excluded_namespaces.add(node.namespace_path)

    # -- loop/switch control flow ----------------------------------------

    def visit_BreakStatement(self, node, builder, module):
        if not hasattr(builder, 'break_block'):
            raise SyntaxError(
                f"'break' outside of loop or switch [{node.source_line}:{node.source_col}]")
        if builder.block.is_terminated:
            return None
        builder.branch(builder.break_block)
        return None

    def visit_ContinueStatement(self, node, builder, module):
        if not hasattr(builder, 'continue_block'):
            raise SyntaxError(
                f"'continue' outside of loop [{node.source_line}:{node.source_col}]")
        if builder.block.is_terminated:
            return None
        builder.branch(builder.continue_block)
        return None

    def visit_DeferStatement(self, node, builder, module):
        if not hasattr(builder, '_flux_defer_stack'):
            builder._flux_defer_stack = []
        builder._flux_defer_stack.append(node.expression)
        return None

    def visit_NoreturnStatement(self, node, builder, module):
        if not builder.block.is_terminated:
            builder.unreachable()
        return None

    def visit_EscapeStatement(self, node, builder, module):
        if builder.block.is_terminated:
            return None
        if not getattr(builder, '_flux_is_recursive_func', False):
            raise SyntaxError(
                f"'escape' is only valid inside a <~ recursive function "
                f"[{node.source_line}:{node.source_col}]")
        result = self.visit(node.call, builder, module)
        func = builder.block.function
        ret_type = (func.type.return_type
                    if hasattr(func.type, 'return_type')
                    else func.type.pointee.return_type)
        if isinstance(ret_type, ir.VoidType):
            builder.ret_void()
        else:
            if result is None:
                builder.ret(ir.Constant(ret_type, 0))
            else:
                result = CoercionContext.coerce_return_value(builder, result, ret_type)
                builder.ret(result)
        return None

    # -- labels / goto / jump --------------------------------------------

    def visit_LabelStatement(self, node, builder, module):
        target_block = builder._flux_label_blocks[node.name]
        if not builder.block.is_terminated:
            builder.branch(target_block)
        builder.position_at_start(target_block)
        return None

    def visit_GotoStatement(self, node, builder, module):
        if node.target not in builder._flux_label_blocks:
            raise SyntaxError(
                f"'goto' to undefined label '{node.target}' "
                f"[{node.source_line}:{node.source_col}]")
        if builder.block.is_terminated:
            return None
        builder.branch(builder._flux_label_blocks[node.target])
        return None

    def visit_JumpStatement(self, node, builder, module):
        if builder.block.is_terminated:
            return None
        addr_val = self.visit(node.target, builder, module)
        i64 = ir.IntType(64)
        if isinstance(addr_val.type, ir.PointerType):
            addr_i64 = builder.ptrtoint(addr_val, i64, name="jump_addr")
        elif addr_val.type != i64:
            if addr_val.type.width < 64:
                addr_i64 = builder.zext(addr_val, i64, name="jump_addr")
            else:
                addr_i64 = builder.trunc(addr_val, i64, name="jump_addr")
        else:
            addr_i64 = addr_val
        ftype = ir.FunctionType(ir.VoidType(), [i64])
        asm = ir.InlineAsm(ftype, "addq $$8, %rsp\njmp *%rax", "{rax}", side_effect=True)
        builder.call(asm, [addr_i64])
        builder.unreachable()
        return None

    # -- compile-time declarations ---------------------------------------

    def visit_TraitDef(self, node, builder, module):
        if hasattr(module, 'symbol_table'):
            module.symbol_table.define(
                node.name,
                SymbolKind.TRAIT,
                type_spec=None,
                llvm_type=None,
                llvm_value=None,
            )
            module.symbol_table._trait_registry[node.name] = node.prototypes
        return None

    def visit_DeprecateStatement(self, node, builder, module):
        from fast import Identifier, FunctionCall, ASTNode
        mangled = node.namespace_path.replace("::", "__")
        statements = getattr(module, '_program_statements', [])
        references = []

        def walk(n, path="<top>"):
            if n is None:
                return
            if isinstance(n, Identifier):
                if n.name == mangled or n.name.startswith(mangled + "__"):
                    references.append(f"Identifier {n.name}")
            elif isinstance(n, FunctionCall):
                if n.name == mangled or n.name.startswith(mangled + "__"):
                    references.append(f"Function call {n.name}()")
                for i, arg in enumerate(n.arguments):
                    walk(arg, f"{path} -> call arg {i}")
            if hasattr(n, '__dataclass_fields__'):
                for field_name in n.__dataclass_fields__:
                    child = getattr(n, field_name, None)
                    child_path = f"{path}.{field_name}"
                    if isinstance(child, list):
                        for item in child:
                            walk(item, child_path)
                    elif isinstance(child, ASTNode):
                        walk(child, child_path)

        for stmt in statements:
            walk(stmt, type(stmt).__name__)

        if references:
            from fast import ComptimeError
            ref_list = "\n".join(references)
            raise ComptimeError(
                f"Deprecated namespace '{node.namespace_path}' is still referenced:\n"
                f"{ref_list} [{node.source_line}:{node.source_col}]"
            )

    # -- def/struct/union/object/namespace statement wrappers ------------

    def visit_FunctionDefStatement(self, node, builder, module):
        self.visit(node.function_def, builder, module)
        return None

    def visit_EnumDefStatement(self, node, builder, module):
        self.visit(node.enum_def, builder, module)
        return None

    def visit_UnionDefStatement(self, node, builder, module):
        self.visit(node.union_def, builder, module)
        return None

    def visit_StructDefStatement(self, node, builder, module):
        self.visit(node.struct_def, builder, module)
        return None

    def visit_ObjectDefStatement(self, node, builder, module):
        self.visit(node.object_def, builder, module)
        return None

    def visit_NamespaceDefStatement(self, node, builder, module):
        if (hasattr(module, '_excluded_namespaces') and
                node.namespace_def.name in module._excluded_namespaces):
            return None
        self.visit(node.namespace_def, builder, module)
        return None

    # ------------------------------------------------------------------
    # [PENDING] — remaining tiers not yet migrated from fast.py.
    # ------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Module-level singleton — imported by ASTNode.codegen() thunks
# ---------------------------------------------------------------------------

visitor = CodegenVisitor()