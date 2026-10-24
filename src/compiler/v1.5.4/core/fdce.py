#!/usr/bin/env python3
"""
Flux Dead Code Eliminator  (fdce.py)

Copyright (C) 2026 Karac Thweatt

Contributors:
    Piotr Bednarski

Runs on the AST produced by FluxParser *before* code generation.

Strategy
--------
All namespace-level declarations are candidates for elimination: functions,
structs, objects (and their methods), enums, unions, and traits. Any
declaration whose name is never referenced by live code is removed.

Liveness closure:
  1. Seed from non-namespace top-level code + entry points.
  2. Expand: for each live name, walk that function/method body and add its refs.
  3. Repeat until stable.
  4. Eliminate anything never reached.

Mangling
--------
Flux mangles  ns::func  ->  ns__func  at call sites, and nested namespaces
produce  outer__inner__func.  A call site may use any *suffix* of the full
mangled name (e.g. helpers__compare_ignore_case for a function that lives
at standard__strings__helpers__compare_ignore_case).

We therefore index every function under ALL suffix variants of its fully-
qualified mangled name, and the ref collector decomposes every __-name it
sees into all its suffix variants too.
"""

from __future__ import annotations

import sys
from typing import Any, Dict, List, Set

# ---------------------------------------------------------------------------
# Primitive / keyword names – never user-defined symbols
# ---------------------------------------------------------------------------

_PRIMITIVE_TYPES: frozenset = frozenset({
    'int', 'uint', 'float', 'double', 'bool', 'byte', 'char',
    'void', 'str', 'i8', 'i16', 'i32', 'i64', 'i128',
    'u8', 'u16', 'u32', 'u64', 'u128', 'f32', 'f64',
    'ptr', 'ref', 'null', 'nullptr', 'true', 'false',
})

# ---------------------------------------------------------------------------
# Entry-point / always-keep function names
# ---------------------------------------------------------------------------



# ---------------------------------------------------------------------------
# Mangling helpers
# ---------------------------------------------------------------------------

def _all_suffixes(mangled: str) -> List[str]:
    """
    Return every __-suffix of a mangled name, including the full name and
    the bare name.

    Example:
        'standard__strings__helpers__compare_ignore_case'
        -> ['standard__strings__helpers__compare_ignore_case',
            'strings__helpers__compare_ignore_case',
            'helpers__compare_ignore_case',
            'compare_ignore_case']
    """
    parts = mangled.split('__')
    results = []
    for i in range(len(parts)):
        results.append('__'.join(parts[i:]))
    return results


# ---------------------------------------------------------------------------
# Generic AST walker – collects every referenced name from a subtree
# ---------------------------------------------------------------------------

class _RefCollector:
    """
    Depth-first AST walker.  Uses id()-based visited set to handle cyclic
    / shared AST references.
    """

    def __init__(self) -> None:
        self.refs: Set[str] = set()
        self._visited: Set[int] = set()

    def collect(self, node: Any) -> None:
        self._walk(node)

    def _add(self, name: str) -> None:
        """Add a name and ALL its suffix variants."""
        if not name or name in _PRIMITIVE_TYPES:
            return
        # Handle :: qualified names (convert to __ form first)
        if '::' in name:
            name = name.replace('::', '__')
        # Handle object construction / method calls written as  TypeName.__init
        # or  TypeName.methodName  (dot-separated).  Convert the dot to __ so
        # the pruner's  cur_prefix__ObjName__methodName  pattern can match it.
        # We add BOTH the dot form and the __ form so nothing is lost.
        if '.' in name:
            name_dunder = name.replace('.', '__')
            for variant in _all_suffixes(name_dunder):
                if variant and variant not in _PRIMITIVE_TYPES:
                    self.refs.add(variant)
        for variant in _all_suffixes(name):
            if variant and variant not in _PRIMITIVE_TYPES:
                self.refs.add(variant)
        # If this is a fully-mangled call name (e.g. main__0__ret_intE1),
        # also emit the base__paramcount prefix so the toplevel_func_index
        # entry keyed by  name__N  is reached during fixed-point expansion.
        # The mangled form is  basename__N__<param types>__ret_<rettype>;
        # the prefix before '__ret_' contains everything we need.
        if '__ret_' in name:
            prefix = name[:name.index('__ret_')]
            for variant in _all_suffixes(prefix):
                if variant and variant not in _PRIMITIVE_TYPES:
                    self.refs.add(variant)
            # Also add the bare base name (first component of the prefix)
            # so the toplevel liveness check (_all_suffixes(stmt.name)) hits.
            bare_base = prefix.split('__')[0]
            if bare_base and bare_base not in _PRIMITIVE_TYPES:
                self.refs.add(bare_base)

    def _walk(self, node: Any) -> None:
        if node is None:
            return
        if isinstance(node, (int, float, bool, bytes)):
            return
        if isinstance(node, str):
            return
        if isinstance(node, (list, tuple)):
            for child in node:
                self._walk(child)
            return
        if isinstance(node, dict):
            for v in node.values():
                self._walk(v)
            return

        node_id = id(node)
        if node_id in self._visited:
            return
        self._visited.add(node_id)

        cls = type(node).__name__

        # An object names the traits it implements; those trait declarations must
        # stay alive for as long as the object does (templated objects are
        # instantiated outside their namespace, after trait declarations are pruned).
        if cls == 'ObjectDef':
            for _t in (getattr(node, 'traits', None) or []):
                if isinstance(_t, str) and _t:
                    self._add(_t)

        # ── Identifier ───────────────────────────────────────────────────
        if cls == 'Identifier':
            name = getattr(node, 'name', None)
            if isinstance(name, str):
                self._add(name)
            return

        # ── TypeSystem ───────────────────────────────────────────────────
        # TypeSystem nodes carry struct/object type names in custom_typename.
        # These are strings so the generic dataclass walker skips them; we
        # must collect them explicitly so named types (RECT, POINT, etc.) are
        # not eliminated as dead even when only used as parameter/return types.
        if cls == 'TypeSystem':
            custom = getattr(node, 'custom_typename', None)
            if isinstance(custom, str) and custom:
                self._add(custom)
            # Still walk array_size / array_dimensions which may be Expressions
            self._walk(getattr(node, 'array_size', None))
            self._walk(getattr(node, 'array_dimensions', None))
            self._walk(getattr(node, 'array_element_type', None))
            return

        # ── FunctionCall ──────────────────────────────────────────────────
        if cls == 'FunctionCall':
            name = getattr(node, 'name', None)
            if isinstance(name, str):
                self._add(name)
                # Also emit  basename__N  so that only the matching-arity overloads
                # are kept alive when multiple overloads share the same base name.
                # The name may be fully qualified with __ (e.g. standard__io__console__print)
                # or :: (e.g. standard::io::console::print); extract just the bare name.
                args = getattr(node, 'arguments', None)
                if args is None:
                    args = getattr(node, 'args', None)
                if isinstance(args, list):
                    bare = name.replace('::', '__').rsplit('__', 1)[-1]
                    if bare and bare not in _PRIMITIVE_TYPES:
                        self.refs.add(bare + '__' + str(len(args)))
            self._walk(getattr(node, 'arguments', None))
            self._walk(getattr(node, 'args', None))
            self._walk(getattr(node, 'type_args', None))
            return

        # ── MethodCall ────────────────────────────────────────────────────
        # MethodCall represents  obj.method(args)  *and* namespaced calls
        # like  helpers::compare_ignore_case(x, y)  which the parser may
        # represent as MethodCall(object=Identifier("helpers"),
        #                         method_name="compare_ignore_case", ...).
        # We must register both the bare method_name AND the qualified
        # object__method_name variant so the liveness index is hit.
        if cls == 'MethodCall':
            method_name = getattr(node, 'method_name', None)
            obj = getattr(node, 'object', None)
            if isinstance(method_name, str) and method_name:
                # Register the bare method name
                self._add(method_name)
                # Also emit  method_name__N  for arity-based narrowing.
                args = getattr(node, 'arguments', None)
                if args is None:
                    args = getattr(node, 'args', None)
                if isinstance(args, list):
                    self.refs.add(method_name + '__' + str(len(args)))
                # If the receiver is an Identifier (e.g. a namespace alias),
                # also register the qualified  obj__method  variant so that
                # partial-suffix matching in the liveness index can find it.
                if obj is not None:
                    obj_name = getattr(obj, 'name', None)
                    if isinstance(obj_name, str) and obj_name:
                        self._add(obj_name + '__' + method_name)
            self._walk(obj)
            self._walk(getattr(node, 'arguments', None))
            self._walk(getattr(node, 'args', None))
            return

        # ── FStringLiteral ────────────────────────────────────────────────
        # fstr_append overloads are chosen by fcodegen at IR emission time
        # based on the runtime type of each interpolated value. DCE cannot
        # know which overloads will be needed, so seed them all whenever any
        # f-string appears in the AST.
        if cls == 'FStringLiteral':
            _FSTR_OVERLOADS = (
                "standard__strings__fstr_append__3__floatE1__byteE1_ptr1__intE1_ptr1__ret_intE1",
                "standard__strings__fstr_append__3__doubleE1__byteE1_ptr1__intE1_ptr1__ret_intE1",
                "standard__strings__fstr_append__3__byteE1_ptr1__byteE1_ptr1__intE1_ptr1__ret_intE1",
                "standard__strings__fstr_append__3__dataE1_ubits16__byteE1_ptr1__intE1_ptr1__ret_intE1",
                "standard__strings__fstr_append__3__dataE1_ubits32__byteE1_ptr1__intE1_ptr1__ret_intE1",
                "standard__strings__fstr_append__3__dataE1_ubits64__byteE1_ptr1__intE1_ptr1__ret_intE1",
                "standard__strings__fstr_append__3__dataE1_sbits16__byteE1_ptr1__intE1_ptr1__ret_intE1",
                "standard__strings__fstr_append__3__dataE1_sbits32__byteE1_ptr1__intE1_ptr1__ret_intE1",
                "standard__strings__fstr_append__3__dataE1_sbits64__byteE1_ptr1__intE1_ptr1__ret_intE1",
            )
            for _fn in _FSTR_OVERLOADS:
                self._add(_fn)
            self._walk(getattr(node, 'parts', None))
            return

        # ── MemberAccess / StructFieldAccess ──────────────────────────────
        if cls in ('MemberAccess', 'StructFieldAccess'):
            self._walk(getattr(node, 'obj', None))
            self._walk(getattr(node, 'object', None))
            self._walk(getattr(node, 'arguments', None))
            self._walk(getattr(node, 'args', None))
            return

        # ── TypeSpec / TypeSystem ─────────────────────────────────────────
        if cls in ('TypeSpec', 'TypeSystem'):
            type_name = getattr(node, 'name', None)
            if isinstance(type_name, str):
                self._add(type_name)
            self._walk_all_fields(node)
            return

        # ── Generic dataclass / AST object ───────────────────────────────
        if hasattr(node, '__dataclass_fields__'):
            self._walk_all_fields(node)
            return

        # ── Fallback ──────────────────────────────────────────────────────
        if hasattr(node, '__dict__'):
            for v in vars(node).values():
                self._walk(v)

    def _walk_all_fields(self, node: Any) -> None:
        if hasattr(node, '__dataclass_fields__'):
            for fname in node.__dataclass_fields__:
                self._walk(getattr(node, fname, None))
        elif hasattr(node, '__dict__'):
            for v in vars(node).values():
                self._walk(v)


def _collect_refs(node: Any) -> Set[str]:
    c = _RefCollector()
    c.collect(node)
    return c.refs


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _is_str_name(node: Any) -> bool:
    return isinstance(getattr(node, 'name', None), str)


def _func_is_entry_point(func: Any, entry: str) -> bool:
    name = getattr(func, 'name', '')
    if not isinstance(name, str):
        return False
    return name == entry or name == '_start'


# ---------------------------------------------------------------------------
# Index all namespace declarations under ALL suffix variants of mangled name
# ---------------------------------------------------------------------------

def _index_namespace_functions(program) -> Dict[str, List[Any]]:
    """
    Index every namespace FunctionDef under all suffix variants of its
    fully-qualified mangled name so that partial-qualification call sites
    still hit the index.
    """
    from fast import NamespaceDef, NamespaceDefStatement, FunctionDef

    index: Dict[str, List[Any]] = {}

    def _index_ns(ns: Any, full_prefix: str) -> None:
        ns_name = getattr(ns, 'name', '') or ''
        cur_prefix = (full_prefix + '__' + ns_name) if full_prefix else ns_name

        for func in getattr(ns, 'functions', []):
            if not isinstance(func, FunctionDef) or not _is_str_name(func):
                continue
            full_mangled = (cur_prefix + '__' + func.name) if cur_prefix else func.name
            for variant in _all_suffixes(full_mangled):
                if variant:
                    index.setdefault(variant, []).append(func)
            # Also index under  name__N  (arg-count-qualified bare name) so that
            # call sites emitting  println__1  only keep the 1-parameter overloads.
            nparams = len(getattr(func, 'parameters', []) or [])
            count_key = func.name + '__' + str(nparams)
            index.setdefault(count_key, []).append(func)

        for nested in getattr(ns, 'nested_namespaces', []):
            _index_ns(nested, cur_prefix)

    for stmt in program.statements:
        ns = None
        if isinstance(stmt, NamespaceDef):
            ns = stmt
        elif isinstance(stmt, NamespaceDefStatement):
            ns = getattr(stmt, 'namespace_def', None)
        if ns is not None:
            _index_ns(ns, '')

    return index


def _index_namespace_types(program) -> Dict[str, Any]:
    """
    Index every namespace-level type declaration (StructDef, ObjectDef,
    TraitDef, EnumDef, UnionDef) under all suffix variants of its
    fully-qualified mangled name.

    Used during pruning to check type-name liveness.
    """
    from fast import NamespaceDef, NamespaceDefStatement

    index: Dict[str, Any] = {}

    def _add_type(cur_prefix: str, name: str, node: Any) -> None:
        full_mangled = (cur_prefix + '__' + name) if cur_prefix else name
        for variant in _all_suffixes(full_mangled):
            if variant:
                index[variant] = node

    def _index_ns(ns: Any, full_prefix: str) -> None:
        ns_name = getattr(ns, 'name', '') or ''
        cur_prefix = (full_prefix + '__' + ns_name) if full_prefix else ns_name

        for decl in getattr(ns, 'structs', []):
            name = getattr(decl, 'name', None)
            if isinstance(name, str) and name:
                _add_type(cur_prefix, name, decl)

        for decl in getattr(ns, 'objects', []):
            name = getattr(decl, 'name', None)
            if isinstance(name, str) and name:
                _add_type(cur_prefix, name, decl)

        for decl in getattr(ns, 'enums', []):
            name = getattr(decl, 'name', None)
            if isinstance(name, str) and name:
                _add_type(cur_prefix, name, decl)

        for decl in getattr(ns, 'unions', []):
            name = getattr(decl, 'name', None)
            if isinstance(name, str) and name:
                _add_type(cur_prefix, name, decl)

        for nested in getattr(ns, 'nested_namespaces', []):
            _index_ns(nested, cur_prefix)

    for stmt in program.statements:
        ns = None
        if isinstance(stmt, NamespaceDef):
            ns = stmt
        elif isinstance(stmt, NamespaceDefStatement):
            ns = getattr(stmt, 'namespace_def', None)
        if ns is not None:
            _index_ns(ns, '')

    return index


# ---------------------------------------------------------------------------
# Fixed-point liveness closure
# ---------------------------------------------------------------------------

def _compute_live_functions(program, ns_func_index: Dict[str, List[Any]],
                             used_ns_prefixes: set,
                             entry: str = 'FRTStartup',
                             verbose: bool = False,
                             extra_roots: tuple = ()) -> Set[str]:
    from fast import NamespaceDef, NamespaceDefStatement, UsingStatement

    from fast import ObjectDef

    # Step 1: Seed from the named entrypoint.
    # All suffix variants of the entrypoint name are added so that regardless
    # of what namespace it lives in, the fixed-point expansion will find it.
    seed: Set[str] = set()
    for variant in _all_suffixes(entry.replace('::', '__')):
        if variant:
            seed.add(variant)

    # Declarations that a later compiler pass (such as async lowering) will
    # reference but that no source code mentions yet.
    for _r in extra_roots:
        for _v in _all_suffixes(_r.replace('::', '__')):
            if _v:
                seed.add(_v)

    # fstr_append overloads are selected by codegen at IR emit time based on
    # value types -- DCE cannot see these references. Always keep them live.
    # Seed both the bare name and all param-qualified variants so _prune_namespace
    # keeps them regardless of which suffix variant it checks liveness against.
    _FSTR_BASE = "standard__strings__fstr_append"
    for _v in _all_suffixes(_FSTR_BASE):
        if _v:
            seed.add(_v)
    # Also add the arity key so overload narrowing keeps all 3-param variants.
    seed.add("fstr_append__3")
    _FSTR_OVERLOADS = (
        "standard__strings__fstr_append__3__floatE1__byteE1_ptr1__intE1_ptr1__ret_intE1",
        "standard__strings__fstr_append__3__doubleE1__byteE1_ptr1__intE1_ptr1__ret_intE1",
        "standard__strings__fstr_append__3__byteE1_ptr1__byteE1_ptr1__intE1_ptr1__ret_intE1",
        "standard__strings__fstr_append__3__dataE1_ubits16__byteE1_ptr1__intE1_ptr1__ret_intE1",
        "standard__strings__fstr_append__3__dataE1_ubits32__byteE1_ptr1__intE1_ptr1__ret_intE1",
        "standard__strings__fstr_append__3__dataE1_ubits64__byteE1_ptr1__intE1_ptr1__ret_intE1",
        "standard__strings__fstr_append__3__dataE1_sbits16__byteE1_ptr1__intE1_ptr1__ret_intE1",
        "standard__strings__fstr_append__3__dataE1_sbits32__byteE1_ptr1__intE1_ptr1__ret_intE1",
        "standard__strings__fstr_append__3__dataE1_sbits64__byteE1_ptr1__intE1_ptr1__ret_intE1",
    )
    for _fn in _FSTR_OVERLOADS:
        for _v in _all_suffixes(_fn):
            if _v:
                seed.add(_v)
    # memset is emitted by code generation itself (llvm.memset for zero initialization),
    # so no source reference to it exists for DCE to see
    for _v in _all_suffixes("memset"):
        if _v:
            seed.add(_v)

    # Step 1b: Seed from non-namespace, non-using top-level statements.
    # Global variable initializers and top-level expressions can reference
    # functions that must remain live even if the entrypoint does not call them
    # directly. Using statements are excluded -- they carry namespace path
    # strings that are not function names.
    # Top-level FunctionDef nodes (e.g. no-mangle wrappers like realloc, malloc)
    # are NOT seeded here -- their bodies are only walked if they are themselves
    # live (i.e. called from live code or are a named entrypoint). Walking them
    # unconditionally seeds their callees (e.g. memcpy from realloc) even when
    # nothing in live code ever calls realloc.
    from fast import FunctionDef as _FunctionDef
    for stmt in program.statements:
        if isinstance(stmt, (NamespaceDef, NamespaceDefStatement)):
            continue
        if isinstance(stmt, UsingStatement):
            continue
        if isinstance(stmt, _FunctionDef):
            # Only seed entrypoint functions; skip all others.
            if _func_is_entry_point(stmt, entry):
                seed |= _collect_refs(stmt)
            continue
        seed |= _collect_refs(stmt)

    # Step 1c: Operator functions. A use of an overloaded built-in operator
    # (a + b on two structs, a pointer overload, an alias overload) is a BinaryOp
    # or UnaryOp node, not a call, and codegen picks the overload by operand types
    # at IR emit time, so DCE cannot see the reference. Keep every operator function
    # from the program itself and from namespaces that are in use.
    from fast import NamespaceDef as _OpNs, NamespaceDefStatement as _OpNsStmt
    for stmt in program.statements:
        if isinstance(stmt, _FunctionDef) and _is_str_name(stmt) and stmt.name.startswith('operator__'):
            for _v in _all_suffixes(stmt.name):
                if _v:
                    seed.add(_v)
            seed.add(stmt.name + '__' + str(len(getattr(stmt, 'parameters', []) or [])))

    def _seed_ns_operators(ns: Any, full_prefix: str) -> None:
        ns_name = getattr(ns, 'name', '') or ''
        cur_prefix = (full_prefix + '__' + ns_name) if full_prefix else ns_name
        if _ns_is_used(cur_prefix, used_ns_prefixes):
            for func in getattr(ns, 'functions', []):
                if (isinstance(func, _FunctionDef) and _is_str_name(func)
                        and func.name.startswith('operator__')):
                    full_mangled = (cur_prefix + '__' + func.name) if cur_prefix else func.name
                    for _v in _all_suffixes(full_mangled):
                        if _v:
                            seed.add(_v)
                    seed.add(func.name + '__' + str(len(getattr(func, 'parameters', []) or [])))
        for nested in getattr(ns, 'nested_namespaces', []):
            _seed_ns_operators(nested, cur_prefix)

    for stmt in program.statements:
        if isinstance(stmt, _OpNs):
            _seed_ns_operators(stmt, '')
        elif isinstance(stmt, _OpNsStmt):
            _ns = getattr(stmt, 'namespace_def', None)
            if _ns is not None:
                _seed_ns_operators(_ns, '')

    # Step 2: Seed named entrypoint top-level functions and build an index of
    # all top-level FunctionDefs so they can be walked in the fixed-point when
    # their name is live. Top-level functions (no-mangle wrappers, CRT shims,
    # etc.) are not in ns_func_index; without this index their bodies would never
    # be walked even if something live calls them.
    toplevel_func_index: Dict[str, List[Any]] = {}
    for stmt in program.statements:
        if not isinstance(stmt, _FunctionDef) or not _is_str_name(stmt):
            continue
        for variant in _all_suffixes(stmt.name):
            if variant:
                toplevel_func_index.setdefault(variant, []).append(stmt)
        # A template instance ('name__tmpl__T') is reached by calls to the template's
        # own name, so index it under that name as well.
        if '__tmpl__' in stmt.name:
            for variant in _all_suffixes(stmt.name.split('__tmpl__')[0]):
                if variant:
                    toplevel_func_index.setdefault(variant, []).append(stmt)
        nparams = len(getattr(stmt, 'parameters', []) or [])
        count_key = stmt.name + '__' + str(nparams)
        toplevel_func_index.setdefault(count_key, []).append(stmt)
        if _func_is_entry_point(stmt, entry):
            seed.add(stmt.name)

    # Step 3: Object methods are NOT pre-seeded into the liveness set.
    #
    # Object methods are only reachable via explicit call sites in live code -
    # the fixed-point expansion in Step 4 discovers them naturally when walking
    # the bodies of live namespace functions.
    #
    # Pre-seeding method names caused a cascade: bare names like 'split_lines'
    # and 'count_lines' collide with same-named namespace-level functions in
    # ns_func_index, marking those functions live and pulling in all their
    # callees even when the methods were never called from user code.
    #
    # Special methods (__init__, __exit__, __copy__, __move__) for objects in
    # used namespaces are handled conservatively in _prune_namespace: they are
    # preserved whenever the object has any live regular method.


    # Step 3b: Collect object methods that are directly live (their mangled name
    # variant appears in seed) so we can walk their bodies in Step 5.
    # We build a map: live_method_name_variant -> [ObjectMethod, ...] across all
    # namespaces.  This is separate from ns_func_index (which is functions only).
    from fast import NamespaceDef, NamespaceDefStatement, ObjectDef

    obj_method_index: Dict[str, List[Any]] = {}
    # obj_method_index_qualified only maps variants that still contain the object
    # name as a qualifier. Used during fixed-point expansion so that bare names
    # like 'println' or 'len' never cause unrelated object methods to be walked.
    obj_method_index_qualified: Dict[str, List[Any]] = {}
    # Maps method node id -> bare object type name, for use in the bare-name
    # second pass to gate body walking on object type liveness.
    obj_method_owner: Dict[int, str] = {}

    def _index_obj_methods(ns: Any, full_prefix: str) -> None:
        ns_name = getattr(ns, 'name', '') or ''
        cur_prefix = (full_prefix + '__' + ns_name) if full_prefix else ns_name
        for obj in getattr(ns, 'objects', []):
            if not isinstance(obj, ObjectDef):
                continue
            obj_name = getattr(obj, 'name', '') or ''
            for method in getattr(obj, 'methods', []):
                method_name = getattr(method, 'name', None)
                if not isinstance(method_name, str):
                    continue
                full_method = (cur_prefix + '__' + obj_name + '__' + method_name
                               if cur_prefix else obj_name + '__' + method_name)
                obj_anchor = obj_name + '__' + method_name
                obj_method_owner[id(method)] = obj_name
                for variant in _all_suffixes(full_method):
                    if variant:
                        obj_method_index.setdefault(variant, []).append(method)
                        # Qualified index: only variants that contain the object name
                        if obj_anchor in variant or variant == full_method:
                            obj_method_index_qualified.setdefault(variant, []).append(method)
        for nested in getattr(ns, 'nested_namespaces', []):
            _index_obj_methods(nested, cur_prefix)

    for stmt in program.statements:
        ns = None
        if isinstance(stmt, NamespaceDef):
            ns = stmt
        elif isinstance(stmt, NamespaceDefStatement):
            ns = getattr(stmt, 'namespace_def', None)
        if ns is not None:
            _index_obj_methods(ns, '')

    # Step 3b(ii): Seed methods of trait-implementing objects into the frontier,
    # but ONLY if the object type name is actually referenced in the current seed.
    # Trait objects are preserved unconditionally by _prune_namespace, but their
    # method bodies should only be walked (and their callees kept alive) if the
    # object type is actually constructed or referenced in live code. Seeding all
    # trait objects unconditionally causes massive false liveness chains when e.g.
    # a file or allocator object implements a trait but is never used.
    def _seed_trait_obj_methods(ns: Any, full_prefix: str) -> None:
        ns_name = getattr(ns, 'name', '') or ''
        cur_prefix = (full_prefix + '__' + ns_name) if full_prefix else ns_name
        for obj in getattr(ns, 'objects', []):
            if not isinstance(obj, ObjectDef):
                continue
            if not getattr(obj, 'traits', None):
                continue
            obj_name = getattr(obj, 'name', '') or ''
            # Only walk this trait object's methods if the object type name appears
            # in any already-seeded name (i.e. something constructs or passes it).
            obj_referenced = any(obj_name in s for s in seed if obj_name)
            if not obj_referenced:
                continue
            for method in getattr(obj, 'methods', []):
                method_name = getattr(method, 'name', None)
                if not isinstance(method_name, str):
                    continue
                full_method = (cur_prefix + '__' + obj_name + '__' + method_name
                               if cur_prefix else obj_name + '__' + method_name)
                obj_anchor = obj_name + '__' + method_name
                # Only seed qualified variants to avoid bare-name collisions
                for variant in _all_suffixes(full_method):
                    if variant and (obj_anchor in variant or variant == full_method):
                        seed.add(variant)
        for nested in getattr(ns, 'nested_namespaces', []):
            _seed_trait_obj_methods(nested, cur_prefix)

    for stmt in program.statements:
        ns = None
        if isinstance(stmt, NamespaceDef):
            ns = stmt
        elif isinstance(stmt, NamespaceDefStatement):
            ns = getattr(stmt, 'namespace_def', None)
        if ns is not None:
            _seed_trait_obj_methods(ns, '')

    # Step 3b(iii): Seed type names from extern block parameter and return types.
    # Extern blocks are never pruned (they're FFI declarations), so any type they
    # reference must be kept alive. Walk all extern block function prototypes and
    # collect their TypeSystem refs into the seed.
    def _seed_extern_type_refs(ns: Any) -> None:
        from fast import ExternBlock
        for block in getattr(ns, 'extern_blocks', []):
            if not isinstance(block, ExternBlock):
                continue
            for decl in getattr(block, 'declarations', []):
                for ref in _collect_refs(decl):
                    seed.add(ref)
        for nested in getattr(ns, 'nested_namespaces', []):
            _seed_extern_type_refs(nested)

    for stmt in program.statements:
        ns = None
        if isinstance(stmt, NamespaceDef):
            ns = stmt
        elif isinstance(stmt, NamespaceDefStatement):
            ns = getattr(stmt, 'namespace_def', None)
        if ns is not None:
            _seed_extern_type_refs(ns)

    # Step 4: Fixed-point expansion.
    #
    # For each newly-live name we walk two indexes:
    #   ns_func_index             -- namespace-level FunctionDefs
    #   obj_method_index_qualified -- object methods, keyed only by qualified
    #                                 variants (those containing the object name)
    #
    # We deliberately use obj_method_index_qualified and NOT the full
    # obj_method_index here. The full index contains bare-name keys like
    # 'println', 'len', 'val', 'append', which collide with same-named
    # namespace functions and live name variants, causing unrelated object
    # methods to be walked and their transitive callees to be falsely kept alive.
    # By using only qualified keys (e.g. 'string__println', 'string__len'),
    # we only walk a method body when the method was explicitly reached via a
    # qualified call site. This is consistent with how liveness is checked in
    # _prune_namespace (the obj_anchor check there).
    live: Set[str] = set()
    frontier: Set[str] = seed

    while frontier:
        new_frontier: Set[str] = set()
        for name in frontier:
            if name in live:
                continue
            live.add(name)
            # Walk namespace function bodies.
            # When multiple overloads share a bare name (e.g. 'println'),
            # we try to restrict walking to only the arity-matching overloads:
            # if any count-qualified key (funcname__N) for this function is live,
            # skip overloads whose arity key is NOT live. This avoids walking
            # every println overload just because one of them was called.
            # If no count-qualified key is live for any function in the list
            # (e.g. the name was reached via a non-call path), fall back to
            # walking all of them conservatively.
            funcs = ns_func_index.get(name)
            if funcs:
                # Check if any arity-qualified key for these functions is live.
                has_count_key_live = any(
                    (f.name + '__' + str(len(getattr(f, 'parameters', []) or []))) in live
                    for f in funcs
                )
                for func in funcs:
                    nparams = len(getattr(func, 'parameters', []) or [])
                    count_key = func.name + '__' + str(nparams)
                    # If count-qualified filtering is available and this overload's
                    # arity key is not live, skip it.
                    if has_count_key_live and count_key not in live:
                        continue
                    for ref in _collect_refs(func):
                        if ref not in live:
                            new_frontier.add(ref)
            # Walk top-level function bodies (no-mangle wrappers, CRT shims, etc.)
            # These are not in ns_func_index but must be walked when live.
            tl_funcs = toplevel_func_index.get(name)
            if tl_funcs:
                for func in tl_funcs:
                    for ref in _collect_refs(func):
                        if ref not in live:
                            new_frontier.add(ref)
            # Walk object method bodies only when reached via a qualified name
            # variant (one containing the object name), to avoid bare-name
            # collisions that cascade false liveness across unrelated objects.
            methods = obj_method_index_qualified.get(name)
            if methods:
                for method in methods:
                    for ref in _collect_refs(method):
                        if ref not in live:
                            new_frontier.add(ref)
        frontier = new_frontier

    # Second pass: walk method bodies reachable via bare method name when the
    # object type is confirmed live. This handles obj.method() call sites where
    # the receiver is a variable -- the ref collector emits only the bare method
    # name since type is unknown at DCE time. Without this, functions called from
    # within live method bodies (e.g. gl_load_extensions from load_extensions)
    # are never seen and get eliminated.
    #
    # Guard: only walk a method body if BOTH:
    #   (a) the bare method name is in live, AND
    #   (b) the object type name (from obj_method_owner) is in live
    # This prevents dead objects from having their method bodies walked.
    def _expand_frontier(frontier: Set[str]) -> None:
        while frontier:
            new_frontier: Set[str] = set()
            for name in frontier:
                if name in live:
                    continue
                live.add(name)
                funcs = ns_func_index.get(name)
                if funcs:
                    for func in funcs:
                        for ref in _collect_refs(func):
                            if ref not in live:
                                new_frontier.add(ref)
                tl_funcs = toplevel_func_index.get(name)
                if tl_funcs:
                    for func in tl_funcs:
                        for ref in _collect_refs(func):
                            if ref not in live:
                                new_frontier.add(ref)
                methods = obj_method_index_qualified.get(name)
                if methods:
                    for method in methods:
                        for ref in _collect_refs(method):
                            if ref not in live:
                                new_frontier.add(ref)
            frontier = new_frontier

    # The scan repeats until no further method body is walked: a method reached
    # only through a bare name that became live during an earlier scan (for
    # example a helper called from another object's method) must be walked too.
    # Third pass: walk field type specs of live struct and object definitions.
    # A struct like MSG contains a field of type POINT. When MSG is live, POINT
    # must also be live. But struct field types are TypeSystem nodes inside
    # StructDef/ObjectDef -- not function call sites -- so the main fixed-point
    # never sees them. Walk all live structs/objects, collect their field type
    # refs, and expand the live set.
    def _collect_type_field_refs(ns: Any, full_prefix: str) -> Set[str]:
        ns_name = getattr(ns, 'name', '') or ''
        cur_prefix = (full_prefix + '__' + ns_name) if full_prefix else ns_name
        refs: Set[str] = set()
        for decl in list(getattr(ns, 'structs', [])) + list(getattr(ns, 'objects', [])):
            name = getattr(decl, 'name', None)
            if not isinstance(name, str) or not name:
                continue
            full_mangled = (cur_prefix + '__' + name) if cur_prefix else name
            if not any(v in live for v in _all_suffixes(full_mangled)):
                continue
            for ref in _collect_refs(decl):
                if ref not in live:
                    refs.add(ref)
        for nested in getattr(ns, 'nested_namespaces', []):
            refs |= _collect_type_field_refs(nested, cur_prefix)
        return refs

    while True:
        live_before = len(live)
        walked_methods: Set[int] = set()
        progressed = True
        while progressed:
            progressed = False
            bare_frontier: Set[str] = set()
            for bare_name, methods in obj_method_index.items():
                if '__' in bare_name:
                    continue  # qualified key, already handled
                if bare_name not in live:
                    continue
                for method in methods:
                    if id(method) in walked_methods:
                        continue
                    obj_name = obj_method_owner.get(id(method))
                    if obj_name and obj_name not in live:
                        continue  # object type not live, skip
                    walked_methods.add(id(method))
                    progressed = True
                    for ref in _collect_refs(method):
                        if ref not in live:
                            bare_frontier.add(ref)
            _expand_frontier(bare_frontier)

        type_frontier: Set[str] = set()
        for stmt in program.statements:
            ns = None
            if isinstance(stmt, NamespaceDef):
                ns = stmt
            elif isinstance(stmt, NamespaceDefStatement):
                ns = getattr(stmt, 'namespace_def', None)
            if ns is not None:
                type_frontier |= _collect_type_field_refs(ns, '')

        _expand_frontier(type_frontier)

        if len(live) == live_before:
            break

    return live, obj_method_index


# ---------------------------------------------------------------------------
# Prune dead functions from a namespace (mutates in place)
# ---------------------------------------------------------------------------

def _ns_is_used(full_prefix: str, used_ns_prefixes: set) -> bool:
    """True if the namespace is equal to or deeper than any used:: path."""
    for used in used_ns_prefixes:
        if full_prefix == used or full_prefix.startswith(used + '__'):
            return True
    return False


def _type_is_live(cur_prefix: str, name: str, live: Set[str]) -> bool:
    """Return True if any qualified suffix variant of cur_prefix__name is live."""
    full_mangled = (cur_prefix + '__' + name) if cur_prefix else name
    return any(v in live for v in _all_suffixes(full_mangled))


def _prune_namespace(ns_node: Any, live: Set[str], full_prefix: str,
                     verbose: bool, used_ns_prefixes: set,
                     obj_method_index: dict, entry: str = '') -> int:
    from fast import FunctionDef, ObjectDef

    eliminated = 0
    ns_name = getattr(ns_node, 'name', '') or ''
    cur_prefix = (full_prefix + '__' + ns_name) if full_prefix else ns_name

    # Prune dead functions
    if hasattr(ns_node, 'functions'):
        # Precompute which base names have at least one count-qualified key live.
        # This enables arity narrowing: when println__1 is live but println__0
        # and println__2 are not, only the 1-parameter overload survives.
        names_with_count_live: Set[str] = set()
        for func in ns_node.functions:
            if not isinstance(func, FunctionDef) or not _is_str_name(func):
                continue
            nparams = len(getattr(func, 'parameters', []) or [])
            if (func.name + '__' + str(nparams)) in live:
                names_with_count_live.add(func.name)

        kept = []
        for func in ns_node.functions:
            if not isinstance(func, FunctionDef) or not _is_str_name(func):
                kept.append(func)
                continue

            full_mangled = (cur_prefix + '__' + func.name) if cur_prefix else func.name
            name_live = any(v in live for v in _all_suffixes(full_mangled))
            if name_live and func.name in names_with_count_live:
                # Arity narrowing: at least one count-qualified key for this base
                # name is live, so only keep overloads whose arity key is also live.
                nparams = len(getattr(func, 'parameters', []) or [])
                name_live = (func.name + '__' + str(nparams)) in live
            is_live = _func_is_entry_point(func, entry) or name_live

            if is_live:
                kept.append(func)
            else:
                eliminated += 1
                if verbose:
                    print(f"[DCE] Eliminated unreferenced FunctionDef "
                          f"(in namespace '{ns_name}'): '{func.name}'",
                          file=sys.stdout)
        ns_node.functions = kept

    # Prune dead namespace variables (globals/constants)
    if hasattr(ns_node, 'variables'):
        kept = []
        for decl in ns_node.variables:
            name = getattr(decl, 'name', None)
            if not isinstance(name, str) or not name:
                kept.append(decl)
                continue
            if _type_is_live(cur_prefix, name, live):
                kept.append(decl)
            else:
                eliminated += 1
                if verbose:
                    print(f"[DCE] Eliminated unreferenced variable "
                          f"(in namespace '{ns_name}'): '{name}'",
                          file=sys.stdout)
        ns_node.variables = kept

    # Prune dead structs
    if hasattr(ns_node, 'structs'):
        kept = []
        for decl in ns_node.structs:
            name = getattr(decl, 'name', None)
            if not isinstance(name, str) or not name:
                kept.append(decl)
                continue
            if _type_is_live(cur_prefix, name, live):
                kept.append(decl)
            else:
                eliminated += 1
                if verbose:
                    print(f"[DCE] Eliminated unreferenced StructDef "
                          f"(in namespace '{ns_name}'): '{name}'",
                          file=sys.stdout)
        ns_node.structs = kept

    # Prune dead enums
    if hasattr(ns_node, 'enums'):
        kept = []
        for decl in ns_node.enums:
            name = getattr(decl, 'name', None)
            if not isinstance(name, str) or not name:
                kept.append(decl)
                continue
            if _type_is_live(cur_prefix, name, live):
                kept.append(decl)
            else:
                eliminated += 1
                if verbose:
                    print(f"[DCE] Eliminated unreferenced EnumDef "
                          f"(in namespace '{ns_name}'): '{name}'",
                          file=sys.stdout)
        ns_node.enums = kept

    # Prune dead unions
    if hasattr(ns_node, 'unions'):
        kept = []
        for decl in ns_node.unions:
            name = getattr(decl, 'name', None)
            if not isinstance(name, str) or not name:
                kept.append(decl)
                continue
            if _type_is_live(cur_prefix, name, live):
                kept.append(decl)
            else:
                eliminated += 1
                if verbose:
                    print(f"[DCE] Eliminated unreferenced UnionDef "
                          f"(in namespace '{ns_name}'): '{name}'",
                          file=sys.stdout)
        ns_node.unions = kept

    # Prune dead objects and their methods.
    #
    # An object is live if its type name appears in the live set (e.g. it is
    # constructed or passed somewhere in live code).  A dead object is removed
    # entirely.  A live object has its methods pruned individually: only methods
    # whose qualified name (containing the object name) appears in the live set
    # are kept.  Special methods (__exit__, __copy__, __move__) are kept
    # implicitly whenever the object itself is live because codegen may emit
    # implicit calls to them.
    #
    # Trait-implementing objects are subject to the same liveness rule. They
    # are NOT unconditionally preserved; if nothing in live code references the
    # type, it is eliminated along with everything else.
    if hasattr(ns_node, 'objects'):
        kept_objs = []
        for obj in ns_node.objects:
            if not isinstance(obj, ObjectDef):
                # TraitDef and other non-ObjectDef nodes: apply name liveness.
                name = getattr(obj, 'name', None)
                if not isinstance(name, str) or not name:
                    kept_objs.append(obj)
                    continue
                if _type_is_live(cur_prefix, name, live):
                    kept_objs.append(obj)
                else:
                    eliminated += 1
                    if verbose:
                        kind = type(obj).__name__
                        print(f"[DCE] Eliminated unreferenced {kind} "
                              f"(in namespace '{ns_name}'): '{name}'",
                              file=sys.stdout)
                continue

            obj_name = getattr(obj, 'name', '') or ''

            # Check object-level liveness by type name.
            if not _type_is_live(cur_prefix, obj_name, live):
                eliminated += 1
                if verbose:
                    print(f"[DCE] Eliminated unreferenced ObjectDef "
                          f"(in namespace '{ns_name}'): '{obj_name}'",
                          file=sys.stdout)
                continue

            # Object is live: prune dead methods individually.
            kept_methods = []
            for method in getattr(obj, 'methods', []):
                method_name = getattr(method, 'name', None)
                if not isinstance(method_name, str):
                    kept_methods.append(method)
                    continue

                full_method = (cur_prefix + '__' + obj_name + '__' + method_name
                               if cur_prefix else obj_name + '__' + method_name)
                obj_anchor = obj_name + '__' + method_name
                # Primary check: qualified variant containing the object name is live.
                # This catches TypeName.__init and TypeName.method() call sites.
                method_live = any(
                    v in live
                    for v in _all_suffixes(full_method)
                    if obj_anchor in v or v == full_method
                )
                # Fallback: bare method name is live. This catches obj.method() call
                # sites where the receiver is a variable (type unknown at DCE time),
                # which only emit the bare method name into refs. The object is
                # already confirmed live above, so this cannot cause a dead object
                # to survive -- it may conservatively keep some dead methods on a
                # live object, which is safe.
                if not method_live and method_name in live:
                    method_live = True

                if method_live:
                    kept_methods.append(method)
                else:
                    eliminated += 1
                    if verbose:
                        print(f"[DCE] Eliminated unreferenced ObjectMethod "
                              f"(object '{obj_name}' in namespace '{ns_name}'): "
                              f"'{method_name}'",
                              file=sys.stdout)

            obj.methods = kept_methods
            kept_objs.append(obj)

        ns_node.objects = kept_objs

    for nested in getattr(ns_node, 'nested_namespaces', []):
        eliminated += _prune_namespace(nested, live, cur_prefix, verbose, used_ns_prefixes, obj_method_index, entry)

    return eliminated


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def eliminate(program, *, entry: str = 'FRTStartup', verbose: bool = False,
              extra_roots: tuple = ()):
    """
    Run dead code elimination on a parsed Flux *Program* AST node.

    All namespace-level declarations are candidates for elimination: functions,
    structs, objects (and their methods individually), enums, unions, and
    traits.  Any declaration whose name is never referenced by live code is
    removed.

    Parameters
    ----------
    program : fast.Program
        Root AST node from FluxParser.parse().
    entry : str
        Name of the program entrypoint function. Liveness is seeded from this
        name. Defaults to 'FRTStartup'. Override via --entrypoint on the CLI
        or 'entrypoint' in flux_config.cfg.
    verbose : bool
        Print a line for each eliminated declaration when True.

    Returns
    -------
    fast.Program
        The same node, mutated in place.
    """
    from fast import NamespaceDef, NamespaceDefStatement

    if verbose:
        print(f"[DCE] Starting dead code elimination "
              f"(entrypoint: '{entry}', "
              f"{len(program.statements)} top-level statement(s))...",
              file=sys.stdout)

    ns_func_index = _index_namespace_functions(program)
    unique_funcs = len(set(id(f) for funcs in ns_func_index.values() for f in funcs))

    if verbose:
        print(f"[DCE] Indexed {unique_funcs} unique namespace function(s) "
              f"under {len(ns_func_index)} name variant(s).",
              file=sys.stdout)

    from fast import UsingStatement
    used_ns_prefixes: set = set()
    for stmt in program.statements:
        if isinstance(stmt, UsingStatement):
            used_ns_prefixes.add(stmt.namespace_path.replace('::', '__'))

    live, obj_method_index = _compute_live_functions(program, ns_func_index, used_ns_prefixes,
                                                        entry=entry, verbose=verbose,
                                                        extra_roots=extra_roots)

    if verbose:
        print(f"[DCE] Live set: {len(live)} name variant(s).", file=sys.stdout)

    from fast import FunctionDef as _FunctionDef
    total_eliminated = 0

    # Prune dead top-level functions (no-mangle wrappers, CRT shims, etc.).
    # These live in program.statements directly, not inside any namespace, so
    # _prune_namespace never sees them. Apply the same liveness rule: a function
    # is kept only if its name appears in the live set or it is a named entrypoint.
    kept_stmts = []
    for stmt in program.statements:
        if isinstance(stmt, _FunctionDef) and _is_str_name(stmt):
            is_live = _func_is_entry_point(stmt, entry) or any(
                v in live for v in _all_suffixes(stmt.name)
            )
            if not is_live:
                total_eliminated += 1
                if verbose:
                    print(f"[DCE] Eliminated unreferenced top-level FunctionDef: "
                          f"'{stmt.name}'", file=sys.stdout)
                continue
        kept_stmts.append(stmt)
    program.statements = kept_stmts

    for stmt in program.statements:
        ns = None
        if isinstance(stmt, NamespaceDef):
            ns = stmt
        elif isinstance(stmt, NamespaceDefStatement):
            ns = getattr(stmt, 'namespace_def', None)
        if ns is not None:
            total_eliminated += _prune_namespace(ns, live, '', verbose, used_ns_prefixes, obj_method_index, entry)

    if total_eliminated == 0:
        print("[DCE] No dead namespace declarations found.", file=sys.stdout)
    else:
        print(f"[DCE] Eliminated {total_eliminated} unreferenced namespace "
              f"declaration(s).", file=sys.stdout)

    if verbose:
        print(f"[DCE] Done. {len(program.statements)} top-level statement(s) remain.",
              file=sys.stdout)

    return program