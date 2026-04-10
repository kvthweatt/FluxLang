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
    # Tier 1 — leaf expressions  [DONE]
    # ------------------------------------------------------------------

    # typeof() kind constants (migrated from TypeOf class attributes)
    _TYPEOF_KIND_UNKNOWN  = 0
    _TYPEOF_KIND_SINT     = 1
    _TYPEOF_KIND_UINT     = 2
    _TYPEOF_KIND_FLOAT    = 3
    _TYPEOF_KIND_DOUBLE   = 4
    _TYPEOF_KIND_BOOL     = 5
    _TYPEOF_KIND_CHAR     = 6
    _TYPEOF_KIND_BYTE     = 7
    _TYPEOF_KIND_SLONG    = 8
    _TYPEOF_KIND_ULONG    = 9
    _TYPEOF_KIND_POINTER  = 10
    _TYPEOF_KIND_ARRAY    = 11
    _TYPEOF_KIND_STRUCT   = 12
    _TYPEOF_KIND_OBJECT   = 13
    _TYPEOF_KIND_VOID     = 14
    _TYPEOF_KIND_FUNCTION = 15

    def visit_Literal(self, node, builder, module):
        from fast import Literal
        if node.type in (DataType.SINT, DataType.UINT):
            llvm_type = TypeSystem.get_llvm_type(node.type, module, node.value)
            normalized_val = LiteralTypeHandler.normalize_int_value(node.value, node.type, llvm_type.width)
            llvm_val = ir.Constant(llvm_type, normalized_val)
            return TypeSystem.attach_type_metadata(llvm_val, node.type)
        elif node.type == DataType.FLOAT:
            llvm_type = TypeSystem.get_llvm_type(node.type, module, node.value)
            return ir.Constant(llvm_type, float(node.value))
        elif node.type == DataType.DOUBLE:
            llvm_type = TypeSystem.get_llvm_type(node.type, module, node.value)
            return ir.Constant(llvm_type, float(node.value))
        elif node.type in (DataType.SLONG, DataType.ULONG):
            llvm_type = ir.IntType(64)
            normalized_val = LiteralTypeHandler.normalize_int_value(node.value, node.type, 64)
            return TypeSystem.attach_type_metadata(ir.Constant(llvm_type, normalized_val), node.type)
        elif node.type == DataType.BOOL:
            llvm_type = TypeSystem.get_llvm_type(node.type, module, node.value)
            return ir.Constant(llvm_type, bool(node.value))
        elif node.type == DataType.CHAR:
            llvm_type = TypeSystem.get_llvm_type(node.type, module, node.value)
            char_val = LiteralTypeHandler.normalize_char_value(node.value)
            return ir.Constant(llvm_type, char_val)
        elif node.type == DataType.VOID:
            return ir.Constant(ir.IntType(1), 0)
        elif node.type == DataType.DATA:
            if isinstance(node.value, list):
                raise ValueError(
                    f"Array literal reached visit_Literal directly — must be handled by "
                    f"ArrayLiteral or VariableDeclaration [{node.source_line}:{node.source_col}]")
            elif isinstance(node.value, dict):
                return self._literal_handle_struct(node, builder, module)
            llvm_type = TypeSystem.get_llvm_type(node.type, module, node.value)
            if isinstance(llvm_type, ir.IntType):
                return ir.Constant(llvm_type, int(node.value) if isinstance(node.value, str) else node.value)
            elif isinstance(llvm_type, (ir.FloatType, ir.DoubleType)):
                return ir.Constant(llvm_type, float(node.value))
            raise ValueError(f"Unsupported DATA literal: {node.value} [{node.source_line}:{node.source_col}]")
        else:
            llvm_type = TypeSystem.get_llvm_type(node.type, module, node.value)
            if isinstance(llvm_type, ir.IntType):
                return ir.Constant(llvm_type, int(node.value) if isinstance(node.value, str) else node.value)
            elif isinstance(llvm_type, (ir.FloatType, ir.DoubleType)):
                return ir.Constant(llvm_type, float(node.value))
            raise ValueError(
                f"Unsupported literal type: {node.type} [{node.source_line}:{node.source_col}]")

    def _literal_handle_struct(self, node, builder, module):
        """Handle struct literal initialization."""
        from fast import Literal
        if not isinstance(node.value, dict):
            raise ValueError(
                f"Expected dictionary for struct literal [{node.source_line}:{node.source_col}]")
        struct_type = LiteralTypeHandler.resolve_struct_type(node.value, module)
        if module.symbol_table.is_global_scope():
            field_values = []
            for member_name in struct_type.names:
                if member_name in node.value:
                    field_expr = node.value[member_name]
                    field_index = struct_type.names.index(member_name)
                    expected_type = struct_type.elements[field_index]
                    if (isinstance(field_expr, Literal) and
                            field_expr.type == DataType.CHAR and
                            LiteralTypeHandler.is_string_pointer_field(expected_type)):
                        string_bytes = field_expr.value.encode('ascii')
                        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                        gv = ir.GlobalVariable(module, str_val.type,
                                               name=f".str.struct_init_{member_name}")
                        gv.linkage = 'internal'
                        gv.global_constant = True
                        gv.initializer = str_val
                        zero = ir.Constant(ir.IntType(32), 0)
                        field_values.append(gv.gep([zero, zero]))
                    else:
                        field_value = self.visit(field_expr, builder, module)
                        if (isinstance(field_value, ir.Constant) and
                                isinstance(field_value.type, ir.IntType) and
                                field_value.type.width > 8):
                            w = field_value.type.width
                            nbytes = w // 8
                            v = int(field_value.constant) & ((1 << w) - 1)
                            swapped = int.from_bytes(v.to_bytes(nbytes, "big"), "little")
                            field_value = ir.Constant(field_value.type, swapped)
                        field_values.append(field_value)
                else:
                    field_type = LiteralTypeHandler.get_struct_field_type(struct_type, member_name)
                    field_values.append(ir.Constant(field_type, 0))
            return ir.Constant(struct_type, field_values)
        else:
            struct_ptr = builder.alloca(struct_type, name="struct_literal")
            for field_name, field_value_expr in node.value.items():
                field_index = struct_type.names.index(field_name)
                field_ptr = builder.gep(
                    struct_ptr,
                    [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), field_index)],
                    inbounds=True)
                expected_type = struct_type.elements[field_index]
                if (isinstance(field_value_expr, Literal) and
                        field_value_expr.type == DataType.CHAR and
                        LiteralTypeHandler.is_string_pointer_field(expected_type)):
                    string_bytes = field_value_expr.value.encode('ascii')
                    str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
                    str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
                    gv = ir.GlobalVariable(module, str_val.type,
                                           name=f".str.local_struct_init_{field_name}")
                    gv.linkage = 'internal'
                    gv.global_constant = True
                    gv.initializer = str_val
                    zero = ir.Constant(ir.IntType(32), 0)
                    field_value = builder.gep(gv, [zero, zero], name=f"{field_name}_str_ptr")
                else:
                    field_value = self.visit(field_value_expr, builder, module)
                    if field_value.type != expected_type:
                        if isinstance(field_value.type, ir.IntType) and isinstance(expected_type, ir.IntType):
                            if field_value.type.width > expected_type.width:
                                field_value = builder.trunc(field_value, expected_type)
                            elif field_value.type.width < expected_type.width:
                                field_value = builder.sext(field_value, expected_type)
                        elif isinstance(field_value.type, ir.IntType) and isinstance(expected_type, (ir.FloatType, ir.DoubleType)):
                            field_value = builder.sitofp(field_value, expected_type)
                        elif isinstance(field_value.type, (ir.FloatType, ir.DoubleType)) and isinstance(expected_type, ir.IntType):
                            field_value = builder.fptosi(field_value, expected_type)
                if isinstance(field_value.type, ir.IntType) and field_value.type.width > 8:
                    nbytes = field_value.type.width // 8
                    i8_ptr = builder.bitcast(field_ptr, ir.PointerType(ir.IntType(8)), name="be_ptr")
                    for byte_i in range(nbytes):
                        shift = (nbytes - 1 - byte_i) * 8
                        shifted = builder.lshr(field_value, ir.Constant(field_value.type, shift),
                                               name=f"be_shift_{byte_i}")
                        byte_val = builder.trunc(shifted, ir.IntType(8), name=f"be_byte_{byte_i}")
                        byte_ptr = builder.gep(i8_ptr, [ir.Constant(ir.IntType(32), byte_i)],
                                               inbounds=True, name=f"be_byteptr_{byte_i}")
                        builder.store(byte_val, byte_ptr)
                else:
                    builder.store(field_value, field_ptr)
            return builder.load(struct_ptr, name="struct_value")

    def visit_StringLiteral(self, node, builder, module):
        import fconfig as _fconfig
        _null_terminate = _fconfig.config.get('null_terminate_strings', '0').strip() == '1'
        value = node.value
        if _null_terminate and (not value or value[-1] != '\0'):
            value += '\0'
        string_bytes = value.encode('ascii')
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        str_val = ir.Constant(str_array_ty, bytearray(string_bytes))
        use_global = (
            node.storage_class == StorageClass.GLOBAL or
            module.symbol_table.is_global_scope()
        )
        use_heap = node.storage_class == StorageClass.HEAP
        use_stack = (
            node.storage_class in (StorageClass.STACK, StorageClass.LOCAL) or
            (not module.symbol_table.is_global_scope() and not use_global and not use_heap)
        )
        if use_heap:
            from fast import string_heap_allocation
            return string_heap_allocation(builder, module, str_val)
        if use_global or not use_stack:
            str_name = f".str.{id(node)}"
            gv = ir.GlobalVariable(module, str_val.type, name=str_name)
            gv.linkage = 'internal'
            gv.global_constant = True
            gv.initializer = str_val
            gv.type._is_array_pointer = True
            return gv
        stack_alloca = builder.alloca(str_array_ty, name="str_stack")
        for i, byte_val in enumerate(string_bytes):
            zero = ir.Constant(ir.IntType(32), 0)
            index = ir.Constant(ir.IntType(32), i)
            elem_ptr = builder.gep(stack_alloca, [zero, index], name=f"str_char_{i}")
            builder.store(ir.Constant(ir.IntType(8), byte_val), elem_ptr)
        stack_alloca.type._is_array_pointer = True
        return stack_alloca

    def visit_RangeExpression(self, node, builder, module, element_type=None):
        start_val = self.visit(node.start, builder, module)
        end_val = self.visit(node.end, builder, module)
        range_type = element_type if element_type is not None else ir.IntType(32)
        range_struct_type = ir.LiteralStructType([range_type, range_type])
        range_struct_type.names = ['start', 'end']
        range_ptr = builder.alloca(range_struct_type, name="range")
        if isinstance(start_val.type, ir.IntType) and isinstance(range_type, ir.IntType) and start_val.type.width != range_type.width:
            start_val = builder.trunc(start_val, range_type) if start_val.type.width > range_type.width else builder.sext(start_val, range_type)
        if isinstance(end_val.type, ir.IntType) and isinstance(range_type, ir.IntType) and end_val.type.width != range_type.width:
            end_val = builder.trunc(end_val, range_type) if end_val.type.width > range_type.width else builder.sext(end_val, range_type)
        start_ptr = builder.gep(range_ptr, [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 0)], inbounds=True)
        builder.store(start_val, start_ptr)
        end_ptr = builder.gep(range_ptr, [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 1)], inbounds=True)
        builder.store(end_val, end_ptr)
        return range_ptr

    def visit_TypeConvertExpression(self, node, builder, module):
        from fast import CastExpression
        return self.visit(CastExpression(node.target_type, node.expression), builder, module)

    def visit_TypeDeclaration(self, node, builder, module):
        llvm_type = TypeSystem.get_llvm_type(node.type_spec, module, include_array=True)
        if not hasattr(module, '_type_aliases'):
            module._type_aliases = {}
        module._type_aliases[node.name] = llvm_type
        if not hasattr(module, '_type_alias_specs'):
            module._type_alias_specs = {}
        module._type_alias_specs[node.name] = node.type_spec
        if hasattr(module, 'symbol_table'):
            module.symbol_table.define(
                node.name, SymbolKind.TYPE,
                type_spec=node.type_spec, llvm_type=llvm_type, llvm_value=None)
        if node.initial_value:
            init_val = self.visit(node.initial_value, builder, module)
            gvar = ir.GlobalVariable(module, llvm_type, node.name)
            gvar.linkage = 'internal'
            gvar.global_constant = True
            gvar.initializer = init_val
            return gvar
        return None

    def visit_PointerDeref(self, node, builder, module):
        ptr_val = self.visit(node.pointer, builder, module)
        if not isinstance(ptr_val.type, ir.PointerType):
            raise ValueError(
                f"Cannot dereference non-pointer type [{node.source_line}:{node.source_col}]")
        return builder.load(ptr_val, name="deref")

    def visit_AddressOf(self, node, builder, module):
        from fast import (Literal, Identifier, PointerDeref, MemberAccess,
                          ArrayAccess, FunctionCall)
        expr = node.expression
        if isinstance(expr, Literal):
            literal_val = self.visit(expr, builder, module)
            temp = builder.alloca(literal_val.type)
            builder.store(literal_val, temp)
            return temp
        if isinstance(expr, Identifier):
            var_name = expr.name
            if (not module.symbol_table.is_global_scope() and
                    module.symbol_table.get_llvm_value(var_name) is not None):
                ptr = module.symbol_table.get_llvm_value(var_name)
                if (isinstance(ptr.type, ir.PointerType) and
                        isinstance(ptr.type.pointee, ir.PointerType)):
                    return builder.load(ptr, name=f"{var_name}_ptr")
                return ptr
            if var_name in module.globals:
                gvar = module.globals[var_name]
                if isinstance(gvar, ir.Function):
                    return gvar
                if (isinstance(gvar.type, ir.PointerType) and
                        isinstance(gvar.type.pointee, ir.PointerType) and
                        not isinstance(gvar.type.pointee, ir.ArrayType)):
                    return builder.load(gvar, name=f"{var_name}_ptr")
                return gvar
            if hasattr(module, '_function_overloads') and var_name in module._function_overloads:
                overloads = module._function_overloads[var_name]
                if len(overloads) == 1:
                    return overloads[0]['function']
                zero_arg = next((o for o in overloads if o['param_count'] == 0), None)
                if zero_arg:
                    return zero_arg['function']
                raise ValueError(
                    f"Ambiguous function reference '@{var_name}': multiple overloads exist. "
                    f"[{node.source_line}:{node.source_col}]")
            if hasattr(module, '_using_namespaces'):
                for namespace in module._using_namespaces:
                    mangled_name = namespace.replace('::', '__') + '__' + var_name
                    if mangled_name in module.globals:
                        gvar = module.globals[mangled_name]
                        if isinstance(gvar, ir.Function):
                            return gvar
                        if (isinstance(gvar.type, ir.PointerType) and
                                isinstance(gvar.type.pointee, ir.PointerType) and
                                not isinstance(gvar.type.pointee, ir.ArrayType)):
                            return builder.load(gvar, name=f"{var_name}_ptr")
                        return gvar
                    if (hasattr(module, '_function_overloads') and
                            mangled_name in module._function_overloads):
                        overloads = module._function_overloads[mangled_name]
                        if len(overloads) == 1:
                            return overloads[0]['function']
                        zero_arg = next((o for o in overloads if o['param_count'] == 0), None)
                        if zero_arg:
                            return zero_arg['function']
            raise NameError(
                f"Unknown identifier: {var_name} [{node.source_line}:{node.source_col}]")
        if isinstance(expr, PointerDeref):
            return self.visit(expr.pointer, builder, module)
        if isinstance(expr, MemberAccess):
            return expr._get_member_ptr(builder, module)
        if isinstance(expr, ArrayAccess):
            if isinstance(expr.array, Identifier):
                var_name = expr.array.name
                if (not module.symbol_table.is_global_scope() and
                        module.symbol_table.get_llvm_value(var_name) is not None):
                    array_ptr = module.symbol_table.get_llvm_value(var_name)
                elif var_name in module.globals:
                    array_ptr = module.globals[var_name]
                else:
                    mangled = IdentifierTypeHandler.resolve_namespace_mangled_name(var_name, module)
                    if mangled and module.symbol_table.get_llvm_value(mangled) is not None:
                        array_ptr = module.symbol_table.get_llvm_value(mangled)
                    elif mangled and mangled in module.globals:
                        array_ptr = module.globals[mangled]
                    else:
                        raise NameError(
                            f"Unknown array identifier: {var_name} "
                            f"[{node.source_line}:{node.source_col}]")
            elif isinstance(expr.array, MemberAccess):
                array_ptr = expr.array._get_member_ptr(builder, module)
            else:
                array_ptr = self.visit(expr.array, builder, module)
            index = self.visit(expr.index, builder, module)
            if (isinstance(array_ptr.type, ir.PointerType) and
                    isinstance(array_ptr.type.pointee, ir.PointerType)):
                array_ptr = builder.load(array_ptr, name="array_param_ptr")
            if isinstance(array_ptr.type, ir.PointerType):
                if isinstance(array_ptr.type.pointee, ir.ArrayType):
                    zero = ir.Constant(ir.IntType(32), 0)
                    return builder.gep(array_ptr, [zero, index], inbounds=True)
                return builder.gep(array_ptr, [index], inbounds=True)
        if isinstance(expr, FunctionCall):
            func_result = self.visit(expr, builder, module)
            temp_alloca = builder.alloca(func_result.type, name="func_result_temp")
            builder.store(func_result, temp_alloca)
            return temp_alloca
        raise ValueError(
            f"Cannot take address of {type(expr).__name__} [{node.source_line}:{node.source_col}]")

    def visit_Stringify(self, node, builder, module):
        from fast import ComptimeError
        current_ns = (getattr(module, '_current_namespace', '') or
                      module.symbol_table.current_namespace)
        if node.member is None:
            if (module.symbol_table.get_llvm_value(node.name) is None and
                    node.name not in module.globals and
                    module.symbol_table.lookup_variable(node.name, current_ns) is None and
                    module.symbol_table.lookup_function(node.name, current_ns) is None):
                raise ComptimeError(
                    f"Cannot stringify undefined identifier '{node.name}' "
                    f"[{node.source_line}:{node.source_col}]")
            return self._stringify_emit(builder, module, node.name, node)
        if node.member == '_':
            var_entry = module.symbol_table.lookup_variable(node.name, current_ns)
            if var_entry is None:
                raise ComptimeError(
                    f"Cannot stringify: '{node.name}' is not a defined variable "
                    f"[{node.source_line}:{node.source_col}]")
            union_name = var_entry.type_spec.custom_typename if var_entry.type_spec else None
            if (union_name is None or not hasattr(module, '_union_member_info') or
                    union_name not in module._union_member_info):
                raise ComptimeError(
                    f"Cannot stringify '._': '{node.name}' is not a tagged union variable "
                    f"[{node.source_line}:{node.source_col}]")
            union_info = module._union_member_info[union_name]
            if not union_info.get('is_tagged'):
                raise ComptimeError(
                    f"Cannot stringify '._': union '{union_name}' has no tag "
                    f"[{node.source_line}:{node.source_col}]")
            tag_enum_name = union_info['tag_name']
            if not hasattr(module, '_enum_types') or tag_enum_name not in module._enum_types:
                raise ComptimeError(
                    f"Cannot stringify '._': enum '{tag_enum_name}' not found "
                    f"[{node.source_line}:{node.source_col}]")
            enum_values = module._enum_types[tag_enum_name]
            var_llvm = module.symbol_table.get_llvm_value(node.name)
            if var_llvm is None:
                raise ComptimeError(
                    f"Cannot stringify '._': no LLVM value for '{node.name}' "
                    f"[{node.source_line}:{node.source_col}]")
            tag_ptr = builder.gep(
                var_llvm,
                [ir.Constant(ir.IntType(32), 0), ir.Constant(ir.IntType(32), 0)],
                inbounds=True, name="tag_ptr")
            tag_val = builder.load(tag_ptr, name="tag_val")
            i8ptr = ir.PointerType(ir.IntType(8))
            result_slot = builder.alloca(i8ptr, name="stringify_result")
            after_bb = builder.append_basic_block("stringify_after")
            for enum_member, enum_int in sorted(enum_values.items(), key=lambda kv: kv[1]):
                match_bb = builder.append_basic_block(f"stringify_{enum_member}")
                next_bb = builder.append_basic_block(f"stringify_next_{enum_member}")
                cmp = builder.icmp_signed('==', tag_val, ir.Constant(ir.IntType(32), enum_int))
                builder.cbranch(cmp, match_bb, next_bb)
                builder.position_at_end(match_bb)
                str_ptr = self._stringify_emit(builder, module, f"{node.name}.{enum_member}", node)
                builder.store(str_ptr, result_slot)
                builder.branch(after_bb)
                builder.position_at_end(next_bb)
            unknown_ptr = self._stringify_emit(builder, module, f"{node.name}.<unknown>", node)
            builder.store(unknown_ptr, result_slot)
            builder.branch(after_bb)
            builder.position_at_end(after_bb)
            return builder.load(result_slot, name="stringify_tag")
        return self._stringify_emit(builder, module, f"{node.name}.{node.member}", node)

    def _stringify_emit(self, builder, module, text: str, node) -> ir.Value:
        """Emit a null-terminated string constant and return a pointer to it."""
        string_bytes = bytearray(text.encode('ascii')) + bytearray(1)
        str_array_ty = ir.ArrayType(ir.IntType(8), len(string_bytes))
        str_val = ir.Constant(str_array_ty, string_bytes)
        gv = ir.GlobalVariable(module, str_val.type, name=f".stringify.{text}.{id(node)}")
        gv.linkage = 'internal'
        gv.global_constant = True
        gv.initializer = str_val
        zero = ir.Constant(ir.IntType(32), 0)
        return builder.gep(gv, [zero, zero], inbounds=True, name=f"str_{text}")

    def visit_AlignOf(self, node, builder, module):
        align = AlignOfTypeHandler.alignof_bytes_for_target(node.target, builder, module)
        if align is not None:
            return ir.Constant(ir.IntType(32), align)
        val = self.visit(node.target, builder, module)
        val_type = val.type.pointee if isinstance(val.type, ir.PointerType) else val.type
        align2 = AlignOfTypeHandler.alignment_from_llvm_type(val_type, module)
        if align2 is None:
            raise ValueError(
                f"Cannot determine alignment of type: {val_type} "
                f"[{node.source_line}:{node.source_col}]")
        return ir.Constant(ir.IntType(32), align2)

    def visit_SizeOf(self, node, builder, module):
        bits = SizeOfTypeHandler.sizeof_bits_for_target(node.target, builder, module)
        if bits is not None:
            return ir.Constant(ir.IntType(32), bits)
        value = self.visit(node.target, builder, module)
        bits = SizeOfTypeHandler.bits_from_llvm_type(value.type, module)
        if bits is None:
            raise ValueError(
                f"Cannot determine size of type: {value.type} "
                f"[{node.source_line}:{node.source_col}]")
        return ir.Constant(ir.IntType(32), bits)

    def visit_EndianOf(self, node, builder, module):
        endian = EndianOfTypeHandler.endianof_for_target(node.target, builder, module)
        if endian is not None:
            return ir.Constant(ir.IntType(32), endian)
        value = self.visit(node.target, builder, module)
        spec = getattr(value, '_flux_type_spec', None)
        if spec is not None:
            endian = EndianSwapHandler.get_endianness(spec)
            if endian is not None:
                return ir.Constant(ir.IntType(32), endian)
        return ir.Constant(ir.IntType(32), 0)

    def visit_TypeOf(self, node, builder, module):
        from fast import Identifier, Literal
        expr = node.expression
        if isinstance(expr, Identifier):
            kind = self._typeof_resolve_identifier_kind(expr.name, module)
            if kind is not None:
                return ir.Constant(ir.IntType(32), kind)
        if isinstance(expr, Literal):
            kind = self._typeof_kind_from_datatype(expr.type)
            return ir.Constant(ir.IntType(32), kind)
        val = self.visit(expr, builder, module)
        return ir.Constant(ir.IntType(32), self._typeof_kind_from_llvm_type(val.type))

    def _typeof_resolve_identifier_kind(self, name: str, module) -> Optional[int]:
        current_ns = (getattr(module, '_current_namespace', '') or
                      module.symbol_table.current_namespace)
        if module.symbol_table.lookup_type(name, current_ns) is not None:
            return self._TYPEOF_KIND_STRUCT
        if hasattr(module, '_struct_types'):
            if name in module._struct_types:
                return self._TYPEOF_KIND_STRUCT
            namespaces = (list(getattr(module, '_namespaces', [])) +
                          list(getattr(module.symbol_table, 'registered_namespaces', [])) +
                          list(getattr(module.symbol_table, 'using_namespaces', [])))
            for ns in namespaces:
                if ns.replace('::', '__') + '__' + name in module._struct_types:
                    return self._TYPEOF_KIND_STRUCT
            if current_ns and current_ns.replace('::', '__') + '__' + name in module._struct_types:
                return self._TYPEOF_KIND_STRUCT
        if hasattr(module, '_struct_vtables') and name in module._struct_vtables:
            return self._TYPEOF_KIND_STRUCT
        var_entry = module.symbol_table.lookup_variable(name, current_ns)
        if var_entry is not None and var_entry.type_spec is not None:
            return self._typeof_kind_from_datatype(var_entry.type_spec.base_type)
        try:
            if module.context.get_identified_type(name) is not None:
                return self._TYPEOF_KIND_STRUCT
        except Exception:
            pass
        if hasattr(module, '_struct_types'):
            for key in module._struct_types:
                if key == name or key.endswith('__' + name) or key.endswith('.' + name):
                    return self._TYPEOF_KIND_STRUCT
        return None

    def _typeof_kind_from_datatype(self, dt) -> int:
        mapping = {
            DataType.SINT:   self._TYPEOF_KIND_SINT,
            DataType.UINT:   self._TYPEOF_KIND_UINT,
            DataType.FLOAT:  self._TYPEOF_KIND_FLOAT,
            DataType.DOUBLE: self._TYPEOF_KIND_DOUBLE,
            DataType.BOOL:   self._TYPEOF_KIND_BOOL,
            DataType.CHAR:   self._TYPEOF_KIND_CHAR,
            DataType.DATA:   self._TYPEOF_KIND_BYTE,
            DataType.SLONG:  self._TYPEOF_KIND_SLONG,
            DataType.ULONG:  self._TYPEOF_KIND_ULONG,
            DataType.STRUCT: self._TYPEOF_KIND_STRUCT,
            DataType.OBJECT: self._TYPEOF_KIND_OBJECT,
            DataType.VOID:   self._TYPEOF_KIND_VOID,
        }
        return mapping.get(dt, self._TYPEOF_KIND_UNKNOWN)

    def _typeof_kind_from_llvm_type(self, llvm_type) -> int:
        if isinstance(llvm_type, ir.IntType):
            if llvm_type.width == 1:
                return self._TYPEOF_KIND_BOOL
            if llvm_type.width == 8:
                return self._TYPEOF_KIND_BYTE
            return self._TYPEOF_KIND_SINT
        if isinstance(llvm_type, ir.FloatType):
            return self._TYPEOF_KIND_FLOAT
        if isinstance(llvm_type, ir.DoubleType):
            return self._TYPEOF_KIND_DOUBLE
        if isinstance(llvm_type, ir.PointerType):
            return self._TYPEOF_KIND_POINTER
        if isinstance(llvm_type, ir.ArrayType):
            return self._TYPEOF_KIND_ARRAY
        if isinstance(llvm_type, (ir.LiteralStructType, ir.IdentifiedStructType)):
            return self._TYPEOF_KIND_STRUCT
        if isinstance(llvm_type, ir.VoidType):
            return self._TYPEOF_KIND_VOID
        return self._TYPEOF_KIND_UNKNOWN

    # ------------------------------------------------------------------
    # Tier 2 — compound expressions  [DONE]
    # ------------------------------------------------------------------

    def visit_BinaryOp(self, node, builder, module):
        ctx = CoercionContext(builder)

        # Pointer-param overload check
        _ptr_overload_func = None
        if hasattr(module, '_function_overloads'):
            _op_sym = node.operator.value
            _op_fname = f"operator__{_mangle_builtin_op(_op_sym)}"
            if _op_fname in module._function_overloads:
                for _ov in module._function_overloads[_op_fname]:
                    if _ov['param_count'] != 2:
                        continue
                    _func = _ov['function']
                    _pts = [p.type for p in _func.args]
                    if len(_pts) != 2:
                        continue
                    if all(isinstance(pt, ir.PointerType) and
                           not isinstance(pt.pointee, (ir.ArrayType, ir.LiteralStructType, ir.IdentifiedStructType))
                           for pt in _pts):
                        _ptr_overload_func = _func
                        break

        if _ptr_overload_func is not None:
            from fast import Identifier
            def _get_alloca(n):
                if isinstance(n, Identifier) and not module.symbol_table.is_global_scope():
                    ptr = module.symbol_table.get_llvm_value(n.name)
                    if ptr is not None and isinstance(ptr.type, ir.PointerType):
                        return ptr
                return None
            _lhs_ptr = _get_alloca(node.left)
            _rhs_ptr = _get_alloca(node.right)
            _pts = [p.type for p in _ptr_overload_func.args]
            if (_lhs_ptr is not None and _rhs_ptr is not None and
                    _lhs_ptr.type == _pts[0] and _rhs_ptr.type == _pts[1]):
                return builder.call(_ptr_overload_func, [_lhs_ptr, _rhs_ptr],
                                    name="op_overload_result")

        lhs = self.visit(node.left, builder, module)
        rhs = self.visit(node.right, builder, module)

        # Built-in operator overload check
        if hasattr(module, '_function_overloads'):
            op_func_name = f"operator__{_mangle_builtin_op(node.operator.value)}"
            if op_func_name in module._function_overloads:
                overload_func = None
                for overload in module._function_overloads[op_func_name]:
                    if overload['param_count'] != 2:
                        continue
                    func = overload['function']
                    param_types = [p.type for p in func.args]
                    if len(param_types) != 2:
                        continue
                    types_match = True
                    for raw, pt in zip([lhs, rhs], param_types):
                        rt = raw.type
                        if rt == pt:
                            continue
                        if (isinstance(rt, ir.PointerType) and
                                not isinstance(rt.pointee, (ir.ArrayType, ir.LiteralStructType, ir.IdentifiedStructType)) and
                                rt.pointee == pt):
                            continue
                        if (isinstance(rt, ir.PointerType) and
                                isinstance(rt.pointee, ir.ArrayType) and
                                isinstance(pt, ir.PointerType) and
                                rt.pointee.element == pt.pointee):
                            continue
                        types_match = False
                        break
                    if types_match:
                        overload_func = func
                        break
                if overload_func is not None:
                    adapted = []
                    for i, (av, pt) in enumerate(zip([lhs, rhs], [p.type for p in overload_func.args])):
                        rt = av.type
                        if (isinstance(rt, ir.PointerType) and
                                not isinstance(rt.pointee, (ir.ArrayType, ir.LiteralStructType, ir.IdentifiedStructType)) and
                                rt.pointee == pt):
                            av = builder.load(av, name=f"op_deref_{i}")
                        else:
                            av = FunctionTypeHandler.convert_argument_to_parameter_type(
                                builder, module, av, pt, i)
                        adapted.append(av)
                    return builder.call(overload_func, adapted, name="op_overload_result")

        lhs_is_ptr_to_ptr = (isinstance(lhs.type, ir.PointerType) and
                             isinstance(lhs.type.pointee, ir.PointerType))
        rhs_is_ptr_to_ptr = (isinstance(rhs.type, ir.PointerType) and
                             isinstance(rhs.type.pointee, ir.PointerType))

        might_be_ptr_arithmetic = (
            node.operator in (Operator.ADD, Operator.SUB) and
            (lhs_is_ptr_to_ptr or rhs_is_ptr_to_ptr or
             (isinstance(lhs.type, ir.PointerType) and isinstance(rhs.type, ir.IntType)) or
             (isinstance(rhs.type, ir.PointerType) and isinstance(lhs.type, ir.IntType)))
        )

        is_comparison = node.operator in (Operator.EQUAL, Operator.NOT_EQUAL, Operator.LESS_THAN,
                                          Operator.GREATER_THAN, Operator.LESS_EQUAL, Operator.GREATER_EQUAL)
        rhs_is_int_zero = isinstance(rhs, ir.Constant) and isinstance(rhs.type, ir.IntType) and rhs.constant == 0
        lhs_is_int_zero = isinstance(lhs, ir.Constant) and isinstance(lhs.type, ir.IntType) and lhs.constant == 0
        lhs_is_ptr = isinstance(lhs.type, ir.PointerType)
        rhs_is_ptr = isinstance(rhs.type, ir.PointerType)

        if is_comparison and lhs_is_ptr and rhs_is_int_zero:
            rhs = ir.Constant(lhs.type, None)
        elif is_comparison and rhs_is_ptr and lhs_is_int_zero:
            lhs = ir.Constant(rhs.type, None)
        elif is_comparison and lhs_is_ptr and rhs_is_ptr:
            pass
        elif not might_be_ptr_arithmetic:
            if isinstance(lhs.type, ir.PointerType):
                pointee = lhs.type.pointee
                if not isinstance(pointee, (ir.ArrayType, ir.LiteralStructType, ir.IdentifiedStructType)):
                    lhs = builder.load(lhs, name="auto_deref_lhs")
            if isinstance(rhs.type, ir.PointerType):
                pointee = rhs.type.pointee
                if not isinstance(pointee, (ir.ArrayType, ir.LiteralStructType, ir.IdentifiedStructType)):
                    rhs = builder.load(rhs, name="auto_deref_rhs")
        else:
            lhs_is_int_type = isinstance(lhs.type, ir.IntType)
            rhs_is_int_type = isinstance(rhs.type, ir.IntType)
            if lhs_is_ptr_to_ptr and isinstance(lhs.type.pointee.pointee, ir.IntType) and not rhs_is_int_type:
                lhs = builder.load(lhs, name="deref_ptr_for_arithmetic")
            if rhs_is_ptr_to_ptr and isinstance(rhs.type.pointee.pointee, ir.IntType) and not lhs_is_int_type:
                rhs = builder.load(rhs, name="deref_ptr_for_arithmetic")

        # Array concatenation
        if node.operator in (Operator.ADD, Operator.SUB):
            if (ArrayTypeHandler.is_array_or_array_pointer(lhs) and
                    ArrayTypeHandler.is_array_or_array_pointer(rhs)):
                return ArrayTypeHandler.concatenate(builder, module, lhs, rhs, node.operator)

        # Pointer arithmetic
        lhs_ptr = isinstance(lhs.type, ir.PointerType)
        rhs_ptr = isinstance(rhs.type, ir.PointerType)
        lhs_int = isinstance(lhs.type, ir.IntType)
        rhs_int = isinstance(rhs.type, ir.IntType)

        if node.operator in (Operator.ADD, Operator.SUB):
            if lhs_ptr and rhs_int:
                offset = rhs
                if node.operator is Operator.SUB:
                    offset = builder.sub(ir.Constant(rhs.type, 0), rhs)
                base = lhs
                if isinstance(lhs.type.pointee, ir.ArrayType):
                    zero = ir.Constant(ir.IntType(32), 0)
                    base = builder.gep(lhs, [zero, zero], name="arr_base")
                result = builder.gep(base, [offset])
                if hasattr(lhs, '_flux_type_spec'):
                    result._flux_type_spec = lhs._flux_type_spec
                return result
            if rhs_ptr and lhs_int and node.operator is Operator.ADD:
                base = rhs
                if isinstance(rhs.type.pointee, ir.ArrayType):
                    zero = ir.Constant(ir.IntType(32), 0)
                    base = builder.gep(rhs, [zero, zero], name="arr_base")
                result = builder.gep(base, [lhs])
                if hasattr(rhs, '_flux_type_spec'):
                    result._flux_type_spec = rhs._flux_type_spec
                return result
            if lhs_ptr and rhs_ptr:
                a = builder.ptrtoint(lhs, ir.IntType(64))
                b = builder.ptrtoint(rhs, ir.IntType(64))
                return builder.sub(a, b)

        # Arithmetic
        if node.operator in (Operator.ADD, Operator.SUB, Operator.MUL, Operator.DIV,
                              Operator.MOD, Operator.POWER):
            if isinstance(lhs.type, ir.FloatType) and isinstance(rhs.type, ir.DoubleType):
                lhs = builder.fpext(lhs, ir.DoubleType(), name="float_to_double_lhs")
            elif isinstance(lhs.type, ir.DoubleType) and isinstance(rhs.type, ir.FloatType):
                rhs = builder.fpext(rhs, ir.DoubleType(), name="float_to_double_rhs")
            if isinstance(lhs.type, (ir.FloatType, ir.DoubleType)):
                if node.operator == Operator.POWER:
                    pow_fn_type = ir.FunctionType(lhs.type, [lhs.type, lhs.type])
                    pow_fn = ir.Function(module, pow_fn_type,
                                         name="llvm.pow.f64" if lhs.type == ir.DoubleType() else "llvm.pow.f32")
                    return builder.call(pow_fn, [lhs, rhs])
                return {
                    Operator.ADD: builder.fadd, Operator.SUB: builder.fsub,
                    Operator.MUL: builder.fmul, Operator.DIV: builder.fdiv,
                    Operator.MOD: builder.frem,
                }[node.operator](lhs, rhs)

            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            if isinstance(lhs.type, ir.IntType) and isinstance(rhs.type, ir.IntType):
                if lhs.type.width != rhs.type.width:
                    lhs, rhs = ctx.normalize_ints(lhs, rhs, unsigned=unsigned, promote=True)
            if node.operator == Operator.POWER:
                base_as_float = builder.sitofp(lhs, ir.DoubleType()) if not unsigned else builder.uitofp(lhs, ir.DoubleType())
                powi_fn_type = ir.FunctionType(ir.DoubleType(), [ir.DoubleType(), ir.IntType(32)])
                powi_fn = ir.Function(module, powi_fn_type, name="llvm.powi.f64.i32")
                if rhs.type.width > 32:
                    exp_i32 = builder.trunc(rhs, ir.IntType(32))
                elif rhs.type.width < 32:
                    exp_i32 = builder.sext(rhs, ir.IntType(32))
                else:
                    exp_i32 = rhs
                result_float = builder.call(powi_fn, [base_as_float, exp_i32])
                result = builder.fptoui(result_float, lhs.type) if unsigned else builder.fptosi(result_float, lhs.type)
            else:
                result = {
                    Operator.ADD: builder.add, Operator.SUB: builder.sub,
                    Operator.MUL: builder.mul,
                    Operator.DIV: builder.udiv if unsigned else builder.sdiv,
                    Operator.MOD: builder.urem if unsigned else builder.srem,
                }[node.operator](lhs, rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

        # Comparisons
        if node.operator in (Operator.EQUAL, Operator.NOT_EQUAL, Operator.LESS_THAN,
                              Operator.LESS_EQUAL, Operator.GREATER_THAN, Operator.GREATER_EQUAL):
            op_map = {
                Operator.EQUAL: "==", Operator.NOT_EQUAL: "!=",
                Operator.LESS_THAN: "<", Operator.LESS_EQUAL: "<=",
                Operator.GREATER_THAN: ">", Operator.GREATER_EQUAL: ">=",
            }
            op = op_map[node.operator]
            if isinstance(lhs.type, (ir.FloatType, ir.DoubleType)) and isinstance(rhs.type, (ir.FloatType, ir.DoubleType)):
                if isinstance(lhs.type, ir.FloatType) and isinstance(rhs.type, ir.DoubleType):
                    lhs = builder.fpext(lhs, ir.DoubleType(), name="float_to_double_lhs")
                elif isinstance(lhs.type, ir.DoubleType) and isinstance(rhs.type, ir.FloatType):
                    rhs = builder.fpext(rhs, ir.DoubleType(), name="float_to_double_rhs")
                return builder.fcmp_ordered(op, lhs, rhs)
            if isinstance(lhs.type, ir.PointerType) or isinstance(rhs.type, ir.PointerType):
                return ctx.emit_ptr_cmp(op, lhs, rhs)
            if isinstance(lhs.type, ir.IntType) and isinstance(rhs.type, ir.IntType):
                if lhs.type.width != rhs.type.width:
                    unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
                    lhs, rhs = ctx.normalize_ints(lhs, rhs, unsigned=unsigned, promote=True)
            return ctx.emit_int_cmp(op, lhs, rhs)

        # Bitwise
        if node.operator in (Operator.BITAND, Operator.BITOR, Operator.BITXOR):
            lhs, rhs = ctx.normalize_ints(lhs, rhs, unsigned=True, promote=True)
            result = {
                Operator.BITAND: builder.and_,
                Operator.BITOR:  builder.or_,
                Operator.BITXOR: builder.xor,
            }[node.operator](lhs, rhs)
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

        if node.operator in (Operator.AND, Operator.OR, Operator.XOR):
            if isinstance(lhs.type, ir.IntType) and isinstance(rhs.type, ir.IntType):
                if lhs.type.width != rhs.type.width:
                    lhs, rhs = ctx.normalize_ints(lhs, rhs, unsigned=True, promote=True)
            result = {
                Operator.AND: builder.and_,
                Operator.OR:  builder.or_,
                Operator.XOR: builder.xor,
            }[node.operator](lhs, rhs)
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

        # Shifts
        if node.operator in (Operator.BITSHIFT_LEFT, Operator.BITSHIFT_RIGHT):
            if lhs.type.width != rhs.type.width:
                if rhs.type.width < lhs.type.width:
                    rhs = builder.zext(rhs, lhs.type)
                else:
                    rhs = builder.trunc(rhs, lhs.type)
            if node.operator is Operator.BITSHIFT_LEFT:
                result = builder.shl(lhs, rhs)
                return TypeSystem.attach_type_metadata(result, DataType.UINT if ctx.is_unsigned(lhs) else DataType.SINT)
            result = (builder.lshr(lhs, rhs)
                      if ctx.is_unsigned(lhs) or not hasattr(lhs, '_flux_type_spec')
                      else builder.ashr(lhs, rhs))
            return TypeSystem.attach_type_metadata(result, DataType.UINT if ctx.is_unsigned(lhs) else DataType.SINT)

        # Boolean composites
        if node.operator is Operator.NOR:
            return builder.not_(builder.or_(lhs, rhs))
        if node.operator is Operator.NAND:
            return builder.not_(builder.and_(lhs, rhs))
        if node.operator is Operator.BITNAND:
            result = builder.not_(builder.and_(lhs, rhs))
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)
        if node.operator is Operator.BITNOR:
            result = builder.not_(builder.or_(lhs, rhs))
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)
        if node.operator is Operator.BITXNOR:
            result = builder.not_(builder.xor(lhs, rhs))
            unsigned = ctx.is_unsigned(lhs) or ctx.is_unsigned(rhs)
            return TypeSystem.attach_type_metadata(result, DataType.UINT if unsigned else DataType.SINT)

        raise ValueError(
            f"Unsupported operator: {node.operator} [{node.source_line}:{node.source_col}]")

    def visit_UnaryOp(self, node, builder, module):
        from fast import Identifier, AddressOf, MemberAccess
        if (node.operator in (Operator.INCREMENT, Operator.DECREMENT) and
                isinstance(node.operand, AddressOf)):
            return self._unary_increment_address_of(node, builder, module)

        operand_val = self.visit(node.operand, builder, module)

        if node.operator in (Operator.INCREMENT, Operator.DECREMENT):
            if isinstance(node.operand, Identifier):
                if (isinstance(operand_val.type, ir.PointerType) and
                        isinstance(operand_val.type.pointee, ir.PointerType)):
                    operand_val = builder.load(operand_val, name=f"{node.operand.name}_loaded")

        if node.operator == Operator.NOT:
            if module.symbol_table.is_global_scope() and isinstance(operand_val, ir.Constant):
                if isinstance(operand_val.type, ir.IntType):
                    return ir.Constant(operand_val.type, ~operand_val.constant)
            return builder.not_(operand_val)

        elif node.operator == Operator.SUB:
            if module.symbol_table.is_global_scope() and isinstance(operand_val, ir.Constant):
                if isinstance(operand_val.type, ir.IntType):
                    return ir.Constant(operand_val.type, -operand_val.constant)
                elif isinstance(operand_val.type, (ir.FloatType, ir.DoubleType)):
                    return ir.Constant(operand_val.type, -operand_val.constant)
            if isinstance(operand_val.type, (ir.FloatType, ir.DoubleType)):
                return builder.fsub(ir.Constant(operand_val.type, 0.0), operand_val)
            return builder.neg(operand_val)

        elif node.operator == Operator.INCREMENT:
            if isinstance(operand_val.type, ir.PointerType):
                new_val = builder.gep(operand_val, [ir.Constant(ir.IntType(32), 1)], name="ptr_inc")
            else:
                new_val = builder.add(operand_val, ir.Constant(operand_val.type, 1))
            if isinstance(node.operand, Identifier):
                ptr = self._unary_get_var_ptr(node.operand.name, node, builder, module)
                st = builder.store(new_val, ptr)
                if hasattr(builder, 'volatile_vars') and node.operand.name in builder.volatile_vars:
                    st.volatile = True
            elif isinstance(node.operand, MemberAccess):
                builder.store(new_val, node.operand._get_member_ptr(builder, module))
            return new_val if not node.is_postfix else operand_val

        elif node.operator == Operator.DECREMENT:
            if isinstance(operand_val.type, ir.PointerType):
                new_val = builder.gep(operand_val, [ir.Constant(ir.IntType(32), -1)], name="ptr_dec")
            else:
                new_val = builder.sub(operand_val, ir.Constant(operand_val.type, 1))
            if isinstance(node.operand, Identifier):
                ptr = self._unary_get_var_ptr(node.operand.name, node, builder, module)
                st = builder.store(new_val, ptr)
                if hasattr(builder, 'volatile_vars') and node.operand.name in builder.volatile_vars:
                    st.volatile = True
            elif isinstance(node.operand, MemberAccess):
                builder.store(new_val, node.operand._get_member_ptr(builder, module))
            return new_val if not node.is_postfix else operand_val

        elif node.operator == Operator.BITNOT:
            if module.symbol_table.is_global_scope() and isinstance(operand_val, ir.Constant):
                if isinstance(operand_val.type, ir.IntType):
                    return ir.Constant(operand_val.type, ~operand_val.constant)
            return builder.not_(operand_val)

        raise ValueError(
            f"Unsupported unary operator: {node.operator} [{node.source_line}:{node.source_col}]")

    def _unary_get_var_ptr(self, name, node, builder, module):
        if (not module.symbol_table.is_global_scope() and
                module.symbol_table.get_llvm_value(name) is not None):
            return module.symbol_table.get_llvm_value(name)
        if name in module.globals:
            return module.globals[name]
        mangled = IdentifierTypeHandler.resolve_namespace_mangled_name(name, module)
        if mangled and module.symbol_table.get_llvm_value(mangled) is not None:
            return module.symbol_table.get_llvm_value(mangled)
        if mangled and mangled in module.globals:
            return module.globals[mangled]
        raise NameError(
            f"Variable '{name}' not found in any scope [{node.source_line}:{node.source_col}]")

    def _unary_increment_address_of(self, node, builder, module):
        base_address = self.visit(node.operand, builder, module)
        if isinstance(base_address.type, ir.PointerType):
            if isinstance(base_address.type.pointee, ir.ArrayType):
                zero = ir.Constant(ir.IntType(32), 0)
                array_start = builder.gep(base_address, [zero, zero], name="array_start")
                offset = ir.Constant(ir.IntType(32), 1 if node.operator == Operator.INCREMENT else -1)
                return builder.gep(array_start, [offset],
                                   name="inc_addr" if node.operator == Operator.INCREMENT else "dec_addr")
            else:
                offset = ir.Constant(ir.IntType(32), 1 if node.operator == Operator.INCREMENT else -1)
                return builder.gep(base_address, [offset],
                                   name="inc_addr" if node.operator == Operator.INCREMENT else "dec_addr")
        raise ValueError(
            f"Cannot increment/decrement address of non-pointer type: {base_address.type} "
            f"[{node.source_line}:{node.source_col}]")

    def visit_CastExpression(self, node, builder, module):
        from fast import Literal, Identifier
        target_llvm_type = TypeSystem.get_llvm_type(node.target_type, module, include_array=True)

        if isinstance(target_llvm_type, ir.VoidType):
            return self._cast_handle_void(node, builder, module)

        if isinstance(node.expression, Literal) and node.expression.type == DataType.VOID:
            if isinstance(target_llvm_type, ir.PointerType):
                return ir.Constant(target_llvm_type, None)
            if isinstance(target_llvm_type, ir.IntType):
                return ir.Constant(target_llvm_type, 0)
            if isinstance(target_llvm_type, (ir.HalfType, ir.FloatType, ir.DoubleType)):
                return ir.Constant(target_llvm_type, 0.0)
            raise TypeError(
                f"cannot cast void-literal to {target_llvm_type} "
                f"[{node.source_line}:{node.source_col}]")

        source_val = self.visit(node.expression, builder, module)
        if source_val.type == target_llvm_type:
            return source_val

        void_ptr_type = ir.PointerType(ir.IntType(8))
        if target_llvm_type == void_ptr_type and isinstance(source_val.type, ir.PointerType):
            return builder.bitcast(source_val, void_ptr_type, name="to_void_ptr")
        if source_val.type == void_ptr_type and isinstance(target_llvm_type, ir.PointerType):
            return builder.bitcast(source_val, target_llvm_type, name="from_void_ptr")

        if (isinstance(source_val.type, ir.PointerType) and
                isinstance(source_val.type.pointee, ir.LiteralStructType) and
                isinstance(target_llvm_type, ir.LiteralStructType)):
            src_sz = sum(e.width for e in source_val.type.pointee.elements if hasattr(e, 'width'))
            tgt_sz = sum(e.width for e in target_llvm_type.elements if hasattr(e, 'width'))
            if src_sz != tgt_sz:
                raise ValueError(
                    f"Cannot cast struct of size {src_sz} to struct of size {tgt_sz} "
                    f"[{node.source_line}:{node.source_col}]")
            ptr = builder.bitcast(source_val, ir.PointerType(target_llvm_type), name="struct_reinterpret")
            return builder.load(ptr, name="reinterpreted_struct")

        elif (isinstance(source_val.type, ir.LiteralStructType) and
              isinstance(target_llvm_type, ir.LiteralStructType)):
            src_sz = sum(e.width for e in source_val.type.elements if hasattr(e, 'width'))
            tgt_sz = sum(e.width for e in target_llvm_type.elements if hasattr(e, 'width'))
            if src_sz != tgt_sz:
                raise ValueError(
                    f"Cannot cast struct of size {src_sz} to struct of size {tgt_sz} "
                    f"[{node.source_line}:{node.source_col}]")
            src_ptr = builder.alloca(source_val.type, name="temp_source")
            builder.store(source_val, src_ptr)
            ptr = builder.bitcast(src_ptr, ir.PointerType(target_llvm_type), name="struct_reinterpret")
            return builder.load(ptr, name="reinterpreted_struct")

        if isinstance(source_val.type, ir.IntType) and isinstance(target_llvm_type, ir.IntType):
            if source_val.type.width > target_llvm_type.width:
                result = builder.trunc(source_val, target_llvm_type)
            elif source_val.type.width < target_llvm_type.width:
                if isinstance(node.expression, Literal):
                    if node.expression.type == DataType.UINT:
                        result = builder.zext(source_val, target_llvm_type)
                    else:
                        result = builder.sext(source_val, target_llvm_type)
                else:
                    source_unsigned = CoercionContext.is_unsigned(source_val)
                    if not source_unsigned and isinstance(node.expression, Identifier):
                        expr_spec = TypeResolver.resolve_type_spec(node.expression.name, module)
                        if expr_spec is not None and hasattr(expr_spec, 'is_signed'):
                            source_unsigned = not expr_spec.is_signed
                    if source_unsigned or node.target_type.base_type == DataType.UINT or (
                            node.target_type.custom_typename and
                            node.target_type.custom_typename.startswith('u')):
                        result = builder.zext(source_val, target_llvm_type)
                    else:
                        result = builder.sext(source_val, target_llvm_type)
            else:
                result = source_val
            result._flux_type_spec = node.target_type
            return result

        elif isinstance(source_val.type, ir.IntType) and isinstance(target_llvm_type, (ir.FloatType, ir.DoubleType)):
            return builder.sitofp(source_val, target_llvm_type)
        elif isinstance(source_val.type, (ir.FloatType, ir.DoubleType)) and isinstance(target_llvm_type, ir.IntType):
            return builder.fptosi(source_val, target_llvm_type)
        elif isinstance(source_val.type, ir.FloatType) and isinstance(target_llvm_type, ir.DoubleType):
            return builder.fpext(source_val, target_llvm_type)
        elif isinstance(source_val.type, ir.DoubleType) and isinstance(target_llvm_type, ir.FloatType):
            return builder.fptrunc(source_val, target_llvm_type)
        elif (isinstance(source_val.type, ir.PointerType) and
              isinstance(target_llvm_type, ir.LiteralStructType)):
            ptr = builder.bitcast(source_val, ir.PointerType(target_llvm_type), name="ptr_to_struct")
            return builder.load(ptr, name="loaded_struct")
        elif (isinstance(source_val.type, ir.LiteralStructType) and
              isinstance(target_llvm_type, ir.PointerType)):
            if hasattr(source_val, 'name') and source_val.name and 'struct' in source_val.name:
                src_name = source_val.name.replace('_struct_load', '').replace('_load', '')
                if module.symbol_table.get_llvm_value(src_name) is not None:
                    return builder.bitcast(module.symbol_table.get_llvm_value(src_name),
                                           target_llvm_type, name="struct_to_ptr")
            src_ptr = builder.alloca(source_val.type, name="struct_for_cast")
            builder.store(source_val, src_ptr)
            return builder.bitcast(src_ptr, target_llvm_type, name="struct_to_ptr")
        elif isinstance(source_val.type, ir.PointerType) and isinstance(target_llvm_type, ir.PointerType):
            return builder.bitcast(source_val, target_llvm_type)
        elif isinstance(source_val.type, ir.IntType) and isinstance(target_llvm_type, ir.PointerType):
            if source_val.type.width < 64:
                source_val = builder.zext(source_val, ir.IntType(64), name="int_to_ptr_zext")
            return builder.inttoptr(source_val, target_llvm_type, name="int_to_ptr")
        elif isinstance(source_val.type, ir.PointerType) and isinstance(target_llvm_type, ir.IntType):
            if isinstance(source_val.type.pointee, ir.ArrayType):
                return ArrayTypeHandler.pack_array_pointer_to_integer(
                    builder, module, source_val, target_llvm_type)
            return builder.ptrtoint(source_val, target_llvm_type, name="ptr_to_int")
        elif (isinstance(source_val.type, ir.PointerType) and
              isinstance(target_llvm_type, (ir.FloatType, ir.DoubleType))):
            if isinstance(source_val.type.pointee, ir.ArrayType):
                return ArrayTypeHandler.pack_array_pointer_to_float(
                    builder, module, source_val, target_llvm_type)
        elif isinstance(target_llvm_type, ir.ArrayType):
            if (isinstance(source_val.type, ir.PointerType) and
                    isinstance(source_val.type.pointee, ir.ArrayType) and
                    source_val.type.pointee.element == target_llvm_type.element):
                count = target_llvm_type.count
                null_term_type = ir.ArrayType(target_llvm_type.element, count + 1)
                alloca = builder.alloca(null_term_type, name="arr_trunc")
                zero = ir.Constant(ir.IntType(32), 0)
                for i in range(count):
                    idx = ir.Constant(ir.IntType(32), i)
                    src_ptr = builder.gep(source_val, [zero, idx], inbounds=True, name=f"src_{i}")
                    src_val = builder.load(src_ptr, name=f"val_{i}")
                    dst_ptr = builder.gep(alloca, [zero, idx], inbounds=True, name=f"dst_{i}")
                    builder.store(src_val, dst_ptr)
                null_idx = ir.Constant(ir.IntType(32), count)
                null_ptr = builder.gep(alloca, [zero, null_idx], inbounds=True, name="null_term")
                builder.store(ir.Constant(target_llvm_type.element, 0), null_ptr)
                return alloca
            return ArrayTypeHandler.unpack_integer_to_array(builder, module, source_val, target_llvm_type)
        else:
            raise ValueError(
                f"Unsupported cast from {source_val.type} to {target_llvm_type} "
                f"[{node.source_line}:{node.source_col}]")

    def _cast_handle_void(self, node, builder, module):
        from fast import Identifier
        if isinstance(node.expression, Identifier):
            var_name = node.expression.name
            if (not module.symbol_table.is_global_scope() and
                    module.symbol_table.get_llvm_value(var_name) is not None):
                var_ptr = module.symbol_table.get_llvm_value(var_name)
                self._cast_runtime_free(builder, module, var_ptr, var_name)
                module.symbol_table.delete_variable(var_name)
            elif var_name in module.globals:
                self._cast_runtime_free(builder, module, module.globals[var_name], var_name)
            else:
                raise NameError(
                    f"Cannot void cast unknown variable: {var_name} "
                    f"[{node.source_line}:{node.source_col}]")
        else:
            expr_val = self.visit(node.expression, builder, module)
            if isinstance(expr_val.type, ir.PointerType):
                self._cast_runtime_free(builder, module, expr_val, "<expression>")
        return None

    def _cast_runtime_free(self, builder, module, ptr_value, var_name):
        i8_ptr = ir.PointerType(ir.IntType(8))
        void_ptr = builder.bitcast(ptr_value, i8_ptr, name=f"{var_name}_void_ptr") if ptr_value.type != i8_ptr else ptr_value
        is_windows = SymbolTable.is_macro_defined(module, '__WINDOWS__')
        is_linux   = SymbolTable.is_macro_defined(module, '__LINUX__')
        is_macos   = SymbolTable.is_macro_defined(module, '__MACOS__')
        if is_windows:
            asm_code = "\n                movq %rcx, %r10\n                movl $$0x1E, %eax\n                syscall\n            "
            constraints = "r,~{rax},~{r10},~{r11},~{memory}"
        elif is_linux:
            asm_code = "\n                movq $$11, %rax\n                syscall\n            "
            constraints = "r,~{rax},~{r11},~{memory}"
        elif is_macos:
            asm_code = "\n                movq $$0x2000049, %rax\n                syscall\n            "
            constraints = "r,~{rax},~{memory}"
        else:
            return
        asm_type = ir.FunctionType(ir.VoidType(), [i8_ptr])
        builder.call(ir.InlineAsm(asm_type, asm_code, constraints, side_effect=True), [void_ptr])

    def visit_TernaryOp(self, node, builder, module):
        cond_val = self.visit(node.condition, builder, module)
        if isinstance(cond_val.type, ir.IntType) and cond_val.type.width != 1:
            cond_val = builder.icmp_signed('!=', cond_val, ir.Constant(cond_val.type, 0))
        func = builder.block.function
        true_block  = func.append_basic_block('ternary_true')
        false_block = func.append_basic_block('ternary_false')
        merge_block = func.append_basic_block('ternary_merge')
        builder.cbranch(cond_val, true_block, false_block)

        builder.position_at_start(true_block)
        true_val = self.visit(node.true_expr, builder, module)
        if (isinstance(true_val.type, ir.PointerType) and
                not isinstance(true_val.type.pointee, ir.PointerType) and
                not isinstance(true_val.type.pointee, (ir.IdentifiedStructType, ir.LiteralStructType))):
            if isinstance(true_val.type.pointee, (ir.IntType, ir.FloatType, ir.DoubleType)):
                true_val = builder.load(true_val, name='ternary_true_load')
        true_end_block = builder.block
        builder.branch(merge_block)

        builder.position_at_start(false_block)
        false_val = self.visit(node.false_expr, builder, module)
        if (isinstance(false_val.type, ir.PointerType) and
                not isinstance(false_val.type.pointee, ir.PointerType) and
                not isinstance(false_val.type.pointee, (ir.IdentifiedStructType, ir.LiteralStructType))):
            if isinstance(false_val.type.pointee, (ir.IntType, ir.FloatType, ir.DoubleType)):
                false_val = builder.load(false_val, name='ternary_false_load')
        false_end_block = builder.block
        builder.branch(merge_block)

        builder.position_at_start(merge_block)
        if true_val.type != false_val.type:
            if isinstance(true_val.type, ir.IntType) and isinstance(false_val.type, ir.IntType):
                if true_val.type.width < false_val.type.width:
                    builder.position_at_end(true_end_block)
                    true_val = builder.sext(true_val, false_val.type)
                    builder.branch(merge_block)
                    builder.position_at_start(merge_block)
                elif false_val.type.width < true_val.type.width:
                    builder.position_at_end(false_end_block)
                    false_val = builder.sext(false_val, true_val.type)
                    builder.branch(merge_block)
                    builder.position_at_start(merge_block)
            elif isinstance(true_val.type, ir.PointerType) and isinstance(false_val.type, ir.PointerType):
                def _decay(val, end_block):
                    pt = val.type.pointee
                    if isinstance(pt, ir.ArrayType):
                        elem_ptr = ir.PointerType(pt.element)
                        term = end_block.terminator
                        builder.position_before(term) if term else builder.position_at_end(end_block)
                        return builder.bitcast(val, elem_ptr, name='ternary_decay')
                    return val
                true_val  = _decay(true_val,  true_end_block)
                false_val = _decay(false_val, false_end_block)
                if true_val.type != false_val.type:
                    same_struct = (
                        isinstance(true_val.type.pointee, ir.IdentifiedStructType) and
                        isinstance(false_val.type.pointee, ir.IdentifiedStructType) and
                        str(true_val.type.pointee) == str(false_val.type.pointee)
                    )
                    if not same_struct:
                        term = false_end_block.terminator
                        builder.position_before(term) if term else builder.position_at_end(false_end_block)
                        false_val = builder.bitcast(false_val, true_val.type, name='ternary_cast')
                builder.position_at_start(merge_block)
            else:
                raise TypeError(
                    f"Ternary operator branches have incompatible types: "
                    f"{true_val.type} vs {false_val.type} [{node.source_line}:{node.source_col}]")

        phi = builder.phi(true_val.type, name='ternary_result')
        phi.add_incoming(true_val,  true_end_block)
        phi.add_incoming(false_val, false_end_block)
        return phi

    def visit_NullCoalesce(self, node, builder, module):
        left_val = self.visit(node.left, builder, module)
        if isinstance(left_val.type, ir.PointerType):
            is_null = builder.icmp_unsigned('==', left_val, ir.Constant(left_val.type, None), name='is_null')
        elif isinstance(left_val.type, ir.IntType):
            is_null = builder.icmp_signed('==', left_val, ir.Constant(left_val.type, 0), name='is_zero')
        else:
            raise TypeError(
                f"Null coalesce not supported for type: {left_val.type} "
                f"[{node.source_line}:{node.source_col}]")
        func = builder.block.function
        right_block = func.append_basic_block('coalesce_right')
        merge_block = func.append_basic_block('coalesce_merge')
        left_block  = builder.block
        builder.cbranch(is_null, right_block, merge_block)
        builder.position_at_start(right_block)
        right_val = self.visit(node.right, builder, module)
        right_end_block = builder.block
        builder.branch(merge_block)
        builder.position_at_start(merge_block)
        if left_val.type != right_val.type:
            if isinstance(left_val.type, ir.IntType) and isinstance(right_val.type, ir.IntType):
                if left_val.type.width < right_val.type.width:
                    builder.position_at_end(left_block)
                    left_val = builder.sext(left_val, right_val.type)
                    builder.branch(merge_block)
                    builder.position_at_start(merge_block)
                elif right_val.type.width < left_val.type.width:
                    builder.position_at_end(right_end_block)
                    right_val = builder.sext(right_val, left_val.type)
                    builder.branch(merge_block)
                    builder.position_at_start(merge_block)
            else:
                raise TypeError(
                    f"Null coalesce operands have incompatible types: "
                    f"{left_val.type} vs {right_val.type} [{node.source_line}:{node.source_col}]")
        phi = builder.phi(left_val.type, name='coalesce_result')
        phi.add_incoming(left_val,  left_block)
        phi.add_incoming(right_val, right_end_block)
        return phi

    def visit_BitSlice(self, node, builder, module):
        val       = self.visit(node.value, builder, module)
        start_val = self.visit(node.start, builder, module)
        end_val   = self.visit(node.end,   builder, module)
        zero32 = ir.Constant(ir.IntType(32), 0)
        i8  = ir.IntType(8)
        i32 = ir.IntType(32)

        s_const      = int(start_val.constant) if hasattr(start_val, 'constant') else None
        e_const_rev  = int(end_val.constant)   if hasattr(end_val,   'constant') else None

        # Reverse bit slice
        if s_const is not None and e_const_rev is not None and s_const > e_const_rev:
            if isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType):
                rev_base = val
                def rev_gep(bidx): return builder.gep(rev_base, [zero32, ir.Constant(i32, bidx)], inbounds=True)
            elif isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, (ir.LiteralStructType, ir.IdentifiedStructType)):
                rev_base = builder.bitcast(val, ir.PointerType(i8), name="rev_struct_raw")
                def rev_gep(bidx): return builder.gep(rev_base, [ir.Constant(i32, bidx)], inbounds=True)
            elif isinstance(val.type, (ir.LiteralStructType, ir.IdentifiedStructType)):
                tmp = builder.alloca(val.type, name="rev_stmp"); builder.store(val, tmp)
                rev_base = builder.bitcast(tmp, ir.PointerType(i8), name="rev_struct_raw")
                def rev_gep(bidx): return builder.gep(rev_base, [ir.Constant(i32, bidx)], inbounds=True)
            elif isinstance(val.type, ir.IntType) and val.type.width >= 8:
                nbytes = val.type.width // 8
                tmp = builder.alloca(ir.ArrayType(i8, nbytes), name="rev_tmp")
                i8ptr = builder.bitcast(tmp, ir.PointerType(i8), name="rev_tmp_i8")
                wval = builder.zext(val, i32) if val.type.width < 32 else val
                for bi in range(nbytes):
                    sh = (nbytes - 1 - bi) * 8
                    bv = builder.trunc(builder.lshr(wval, ir.Constant(wval.type, sh)), i8)
                    builder.store(bv, builder.gep(i8ptr, [ir.Constant(i32, bi)], inbounds=True))
                rev_base = i8ptr
                def rev_gep(bidx): return builder.gep(rev_base, [ir.Constant(i32, bidx)], inbounds=True)
            else:
                tmp = builder.alloca(i8, name="rev_tmp")
                builder.store(val if val.type == i8 else builder.trunc(val, i8), tmp)
                rev_base = tmp
                def rev_gep(bidx): return builder.gep(rev_base, [ir.Constant(i32, bidx)], inbounds=True)
            num_bits = s_const - e_const_rev + 1
            result = ir.Constant(i8, 0)
            for i, bit_pos in enumerate(range(s_const, e_const_rev - 1, -1)):
                byte_i = bit_pos // 8; bit_in_byte = bit_pos % 8
                bval = builder.load(rev_gep(byte_i), name=f"rev_byte_{i}")
                extracted = builder.and_(
                    builder.lshr(bval, ir.Constant(i8, 7 - bit_in_byte), name=f"rev_ext_{i}"),
                    ir.Constant(i8, 1), name=f"rev_bit_{i}")
                placed = builder.shl(extracted, ir.Constant(i8, num_bits - 1 - i), name=f"rev_place_{i}")
                result = builder.or_(result, placed, name=f"rev_acc_{i}")
            if 1 <= num_bits < 8:
                return builder.trunc(result, ir.IntType(num_bits), name="rev_trunc")
            return result

        # Forward bit slice — build base_ptr
        if isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, ir.ArrayType):
            base_ptr = val
        elif isinstance(val.type, ir.PointerType) and isinstance(val.type.pointee, (ir.LiteralStructType, ir.IdentifiedStructType)):
            base_ptr = builder.bitcast(val, ir.PointerType(i8), name="bs_struct_raw")
        elif isinstance(val.type, ir.PointerType):
            base_ptr = val
        elif isinstance(val.type, (ir.LiteralStructType, ir.IdentifiedStructType)):
            tmp = builder.alloca(val.type, name="bs_tmp"); builder.store(val, tmp)
            base_ptr = builder.bitcast(tmp, ir.PointerType(i8), name="bs_struct_raw")
        elif isinstance(val.type, ir.ArrayType):
            tmp = builder.alloca(val.type, name="bs_tmp"); builder.store(val, tmp); base_ptr = tmp
        elif isinstance(val.type, ir.IntType) and val.type.width >= 8:
            nbytes = val.type.width // 8
            tmp = builder.alloca(ir.ArrayType(i8, nbytes), name="bs_tmp")
            i8ptr = builder.bitcast(tmp, ir.PointerType(i8), name="bs_tmp_i8")
            wval = val
            if val.type.width < 32:   wval = builder.zext(val, i32, name="bs_widen")
            elif val.type.width > 64: wval = builder.trunc(val, ir.IntType(64), name="bs_widen")
            wty = wval.type
            for byte_i in range(nbytes):
                shift = (nbytes - 1 - byte_i) * 8
                shifted = builder.lshr(wval, ir.Constant(wty, shift), name=f"bs_byteshift_{byte_i}")
                bval = builder.trunc(shifted, i8, name=f"bs_byte_{byte_i}")
                bptr = builder.gep(i8ptr, [ir.Constant(i32, byte_i)], inbounds=True, name=f"bs_bptr_{byte_i}")
                builder.store(bval, bptr)
            base_ptr = i8ptr
        elif isinstance(val.type, ir.IntType):
            widened = builder.zext(val, i8, name="bs_widen")
            aligned = builder.shl(widened, ir.Constant(i8, 8 - val.type.width), name="bs_prealign")
            tmp = builder.alloca(i8, name="bs_tmp"); builder.store(aligned, tmp); base_ptr = tmp
        else:
            raise ValueError(
                f"Bit-slice operator `` requires array/pointer operand, got {val.type} "
                f"[{node.source_line}:{node.source_col}]")

        def to_i32(v, name):
            if isinstance(v.type, ir.IntType):
                if v.type.width < 32: return builder.zext(v, i32, name=name)
                if v.type.width > 32: return builder.trunc(v, i32, name=name)
                return v
            raise ValueError(
                f"Bit-slice indices must be integers [{node.source_line}:{node.source_col}]")

        start_i32 = to_i32(start_val, "bs_start")
        end_i32   = to_i32(end_val,   "bs_end")
        eight     = ir.Constant(i32, 8)
        byte_idx  = builder.sdiv(start_i32, eight, name="bs_byte_idx")
        bit_start = builder.srem(start_i32, eight, name="bs_bit_start")
        bit_end   = builder.srem(end_i32,   eight, name="bs_bit_end")
        if isinstance(base_ptr.type.pointee, ir.ArrayType):
            byte_ptr = builder.gep(base_ptr, [zero32, byte_idx], inbounds=True, name="bs_byte_ptr")
        else:
            byte_ptr = builder.gep(base_ptr, [byte_idx], inbounds=True, name="bs_byte_ptr")
        byte_val     = builder.load(byte_ptr, name="bs_byte")
        bit_end_i8   = builder.trunc(bit_end,   i8, name="bs_bit_end_i8")
        bit_start_i8 = builder.trunc(bit_start, i8, name="bs_bit_start_i8")
        shift_amt    = builder.sub(ir.Constant(i8, 7), bit_end_i8, name="bs_shift_amt")
        shifted      = builder.lshr(byte_val, shift_amt, name="bs_shift")
        slice_w      = builder.add(builder.sub(bit_end_i8, bit_start_i8, name="bs_slen"),
                                   ir.Constant(i8, 1), name="bs_swidth")
        mask_raw     = builder.shl(ir.Constant(i8, 1), slice_w, name="bs_mask_raw")
        mask         = builder.sub(mask_raw, ir.Constant(i8, 1), name="bs_mask")
        masked       = builder.and_(shifted, mask, name="bs_result")
        try:
            sc = int(start_i32.constant) if hasattr(start_i32, 'constant') else None
            ec = int(end_i32.constant)   if hasattr(end_i32,   'constant') else None
            if sc is not None and ec is not None:
                width = (ec % 8) - (sc % 8) + 1
                if 1 <= width <= 8:
                    return builder.trunc(masked, ir.IntType(width), name="bs_trunc")
        except Exception:
            pass
        return masked

    def visit_VariadicAccess(self, node, builder, module):
        va_list_alloca = getattr(builder, '_flux_va_list', None)
        if va_list_alloca is None:
            raise RuntimeError(
                f"...[N] used outside of a variadic function "
                f"[{node.source_line}:{node.source_col}]")
        va_list_i8ptr = getattr(builder, '_flux_va_list_i8ptr')
        index_val = self.visit(node.index, builder, module)
        if isinstance(index_val.type, ir.IntType) and index_val.type.width != 32:
            index_val = (builder.trunc(index_val, ir.IntType(32), name="va_idx_trunc")
                         if index_val.type.width > 32
                         else builder.sext(index_val, ir.IntType(32), name="va_idx_ext"))
        va_list_type = ir.ArrayType(ir.IntType(8).as_pointer(), 1)
        va_copy_list = builder.alloca(va_list_type, name="va_copy")
        va_copy_i8ptr = builder.bitcast(va_copy_list, ir.IntType(8).as_pointer(), name="va_copy_ptr")
        va_copy_fn_type = ir.FunctionType(ir.VoidType(), [ir.IntType(8).as_pointer(), ir.IntType(8).as_pointer()])
        if 'llvm.va_copy' not in module.globals:
            va_copy_fn = ir.Function(module, va_copy_fn_type, 'llvm.va_copy')
        else:
            va_copy_fn = module.globals['llvm.va_copy']
        builder.call(va_copy_fn, [va_copy_i8ptr, va_list_i8ptr])
        va_end_fn_type = ir.FunctionType(ir.VoidType(), [ir.IntType(8).as_pointer()])
        if 'llvm.va_end' not in module.globals:
            va_end_fn = ir.Function(module, va_end_fn_type, 'llvm.va_end')
        else:
            va_end_fn = module.globals['llvm.va_end']
        arg_type = ir.IntType(64)
        result_alloca = builder.alloca(arg_type, name="va_result")
        current_fn = builder.block.parent
        loop_init_bb = current_fn.append_basic_block(name="va_loop_init")
        loop_cond_bb = current_fn.append_basic_block(name="va_loop_cond")
        loop_body_bb = current_fn.append_basic_block(name="va_loop_body")
        loop_end_bb  = current_fn.append_basic_block(name="va_loop_end")
        merge_bb     = current_fn.append_basic_block(name="va_merge")
        builder.branch(loop_init_bb)
        with builder.goto_block(loop_init_bb):
            counter_alloca = builder.alloca(ir.IntType(32), name="va_counter")
            builder.store(ir.Constant(ir.IntType(32), 0), counter_alloca)
            builder.branch(loop_cond_bb)
        with builder.goto_block(loop_cond_bb):
            counter_val = builder.load(counter_alloca, name="va_cnt_load")
            cond = builder.icmp_signed('<', counter_val, index_val, name="va_cond")
            builder.cbranch(cond, loop_body_bb, loop_end_bb)
        with builder.goto_block(loop_body_bb):
            _emit_va_arg(builder, va_copy_i8ptr, arg_type, name="va_discard")
            cnt = builder.load(counter_alloca, name="va_cnt_inc_load")
            builder.store(builder.add(cnt, ir.Constant(ir.IntType(32), 1), name="va_cnt_inc"), counter_alloca)
            builder.branch(loop_cond_bb)
        with builder.goto_block(loop_end_bb):
            result_val = _emit_va_arg(builder, va_copy_i8ptr, arg_type, name="va_result_val")
            builder.store(result_val, result_alloca)
            builder.call(va_end_fn, [va_copy_i8ptr])
            builder.branch(merge_bb)
        builder.position_at_end(merge_bb)
        return builder.load(result_alloca, name="va_arg_result")

    def visit_InlineAsm(self, node, builder, module):
        import re
        asm_lines = [l for l in node.body.split('\n')
                     if l.strip() and not l.strip().startswith('//')]
        asm = '\n'.join(asm_lines)
        output_operands, input_operands = [], []
        output_constraints, input_constraints, clobber_list = [], [], []
        if node.constraints:
            parts = node.constraints.split(':')
            while len(parts) < 3:
                parts.append('')
            output_part = parts[0].strip()
            if output_part:
                for constraint, var_name in re.findall(r'"([^"]+)"\s*\(([^)]+)\)', output_part):
                    if module.symbol_table.get_llvm_value(var_name) is not None:
                        output_operands.append(module.symbol_table.get_llvm_value(var_name))
                    elif var_name in module.globals:
                        output_operands.append(module.globals[var_name])
                    output_constraints.append(constraint)
            input_part = parts[1].strip()
            if input_part:
                for constraint, var_name in re.findall(r'"([^"]+)"\s*\(([^)]+)\)', input_part):
                    if module.symbol_table.get_llvm_value(var_name) is not None:
                        var_ptr = module.symbol_table.get_llvm_value(var_name)
                        if constraint == 'm' or (isinstance(var_ptr.type, ir.PointerType) and isinstance(var_ptr.type.pointee, ir.ArrayType)):
                            input_operands.append(var_ptr)
                        else:
                            input_operands.append(builder.load(var_ptr, name=f"{var_name}_load"))
                    elif var_name in module.globals:
                        var_ptr = module.globals[var_name]
                        if constraint == 'm' or isinstance(var_ptr.type.pointee, ir.ArrayType):
                            input_operands.append(var_ptr)
                        else:
                            input_operands.append(builder.load(var_ptr, name=f"{var_name}_load"))
                    input_constraints.append(constraint)
            clobber_part = parts[2].strip()
            if clobber_part:
                clobber_list = re.findall(r'"([^"]+)"', clobber_part)
        final_input_operands = input_operands[:]
        final_constraints    = input_constraints[:]
        for output_op, output_constraint in zip(output_operands, output_constraints):
            if output_constraint.startswith('=m'):
                final_input_operands.insert(0, output_op)
                final_constraints.insert(0, output_constraint.replace('=m', '+m'))
            else:
                final_constraints.insert(0, output_constraint)
        final_constraints.extend(f"~{{{c}}}" for c in clobber_list)
        constraint_str = ','.join(final_constraints)
        input_types = [op.type for op in final_input_operands]
        has_reg_out = any(c.startswith(('=r', '=a', '=b')) for c in output_constraints)
        if has_reg_out and output_operands:
            out_type = output_operands[0].type
            if isinstance(out_type, ir.PointerType):
                out_type = out_type.pointee
            fn_type = ir.FunctionType(out_type, input_types)
        else:
            fn_type = ir.FunctionType(ir.VoidType(), input_types)
        inline_asm = ir.InlineAsm(fn_type, asm, constraint_str, node.is_volatile)
        result = builder.call(inline_asm, final_input_operands)
        if has_reg_out and output_operands:
            builder.store(result, output_operands[0])
        return result

    # ------------------------------------------------------------------
    # [PENDING] — remaining tiers not yet migrated from fast.py.
    # ------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Module-level singleton — imported by ASTNode.codegen() thunks
# ---------------------------------------------------------------------------

visitor = CodegenVisitor()