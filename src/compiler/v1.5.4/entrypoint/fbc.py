#!/usr/bin/env python3
"""
fbc.py -- Flux Borrow Checker

Copyright (C) 2026 Karac V. Thweatt

Performs a call-graph walk from the program entry point (FRTStartup by default)
and checks for pointer aliasing violations, scope escapes, and optionally
thread safety and heap leaks.

Usage:
    python fbc.py <file_or_dir> [options]

Options:
    --entry NAME      Entry point function name (default: FRTStartup)
    --warn            Treat violations as warnings instead of errors
    --threads         Also check thread safety (pointer escape across spawns)
    --leaks           Also check for heap leaks (unmatched fmalloc/ffree)
    --json            Machine-readable JSON output (for CI)
    --no-color        Disable ANSI color output

Exit codes:
    0   No violations (or --warn mode)
    1   One or more violations found (in default error mode)
"""

import sys
import os
import argparse
from pathlib import Path

# fbc modules
from fbc_alias import AliasMap, Violation
from fbc_report import print_violations, print_summary

# Flux compiler modules
# fbc.py lives at the project root alongside fxc.py.
# Compiler source is in src/compiler/ -- add that to the path.
_root = Path(__file__).parent
for _candidate in [
    _root / 'src' / 'compiler',
    _root / 'compiler',
    _root,
]:
    if (_candidate / 'fparser.py').exists():
        sys.path.insert(0, str(_candidate))
        break

try:
    from fparser import FluxParser
    from flexer import FluxLexer
    from fpreprocess import FXPreprocessor
    from fmacros import build_compiler_macros
    import fast
    from ftypesys import TypeSystem, Operator
except ImportError as e:
    print(f"[FBC] Error: could not import Flux compiler modules: {e}")
    print("      Looked for fparser.py in src/compiler/, compiler/, and project root.")
    sys.exit(2)

try:
    from fvm import FluxVM, VMError, Op, TTag, Instr, Val
    from fvmcodegen import FVMCodegen
    _FVM_AVAILABLE = True
except ImportError:
    _FVM_AVAILABLE = False

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _is_pointer_type(type_spec) -> bool:
    """Return True if a TypeSystem represents a pointer type."""
    if type_spec is None:
        return False
    return getattr(type_spec, 'is_pointer', False) or getattr(type_spec, 'pointer_depth', 0) > 0

def _node_file(node) -> str:
    return getattr(node, 'source_file', '<unknown>')

def _node_line(node) -> int:
    return getattr(node, 'source_line', 0)

def _make_stack_site(func_name: str, var_name: str, line: int) -> str:
    return f"stack:{func_name}:{var_name}@{line}"

def _make_heap_site(func_name: str, line: int) -> str:
    return f"heap:{func_name}:{line}"

def _make_param_site(func_name: str, param_name: str) -> str:
    return f"param:{func_name}:{param_name}"

def _is_fmalloc(node) -> bool:
    if isinstance(node, fast.FunctionCall):
        return node.name == 'fmalloc'
    return False

def _is_ffree(node) -> bool:
    if isinstance(node, fast.FunctionCall):
        return node.name == 'ffree'
    return False

def _is_thread_spawn(node) -> bool:
    """Heuristic: function calls that look like thread spawns."""
    if isinstance(node, fast.FunctionCall):
        return 'spawn' in node.name.lower() or 'thread' in node.name.lower()
    if isinstance(node, fast.MethodCall):
        name = getattr(node, 'name', '') or ''
        return 'spawn' in name.lower() or 'thread' in name.lower()
    return False

# ---------------------------------------------------------------------------
# Call graph builder
# ---------------------------------------------------------------------------

class CallGraph:
    """Collects all FunctionDef nodes keyed by name for call resolution."""

    def __init__(self):
        # name -> FunctionDef
        self.funcs: dict[str, fast.FunctionDef] = {}
        # short name -> mangled name, for intra-namespace call resolution
        self.short_names: dict[str, str] = {}
        # base name -> list of mangled names (for overload resolution at call sites)
        self.overloads: dict[str, list] = {}
        # func_name -> set of call-context tuples already analysed (main context)
        self.visited_main: dict[str, set[tuple]] = {}
        # func_name -> set of call-context tuples already analysed (thread context)
        self.visited_thread: dict[str, set[tuple]] = {}
        # how many times each function has been passed to a thread spawn
        # name -> int
        self.spawn_count: dict[str, int] = {}
        # async metadata: function keys declared async (prototype or definition),
        # tag definitions by name, and (carrier key, FunctionDef, AsyncTagUse) clauses
        self.async_names: set[str] = set()
        self.async_tags: dict = {}
        self.async_uses: list = []

    # kept as a property so existing code that reads cg.visited still compiles
    # returns the set of function names that have been analysed in at least one context
    @property
    def visited(self) -> set[str]:
        return set(self.visited_main.keys())

    def is_visited(self, name: str, ctx: tuple, thread: bool) -> bool:
        """Return True if this (name, ctx) pair has already been analysed."""
        table = self.visited_thread if thread else self.visited_main
        return ctx in table.get(name, set())

    def mark_visited(self, name: str, ctx: tuple, thread: bool):
        """Record that (name, ctx) has been analysed."""
        table = self.visited_thread if thread else self.visited_main
        table.setdefault(name, set()).add(ctx)

    def collect(self, program: fast.Program):
        """Walk the top-level program and collect all function definitions."""
        for node in program.statements:
            self._collect_node(node)
        # build short name index and overload index
        short_count: dict[str, int] = {}
        for mangled in self.funcs:
            short = mangled.split('__')[-1]
            short_count[short] = short_count.get(short, 0) + 1
        for mangled in self.funcs:
            short = mangled.split('__')[-1]
            if short_count[short] == 1:
                self.short_names[short] = mangled
            # overload index: base name is everything before the __N__ arity segment
            # split on __ and find the first all-digit segment; base is parts before it
            # e.g. main__0__ret_intE1 -> parts=['main','0','ret_intE1'] -> base='main'
            parts = mangled.split('__')
            base = mangled
            for idx, part in enumerate(parts):
                if part.isdigit():
                    base = '__'.join(parts[:idx])
                    break
            self.overloads.setdefault(base, []).append(mangled)

    def _note_async(self, func, key):
        if getattr(func, 'is_async', False):
            self.async_names.add(key)
        for use in (getattr(func, 'async_uses', None) or []):
            self.async_uses.append((key, func, use))

    def _collect_node(self, node, ns_prefix: str = ''):
        if isinstance(node, fast.AsyncTagDef):
            self.async_tags[node.name] = node
        elif isinstance(node, fast.FunctionDef):
            self._note_async(node, node.name)
            if not node.is_prototype:
                self.funcs[node.name] = node
        elif isinstance(node, fast.FunctionDefStatement):
            self._collect_node(node.function_def, ns_prefix)
        elif isinstance(node, fast.NamespaceDefStatement):
            self._collect_node(node.namespace_def, ns_prefix)
        elif isinstance(node, fast.NamespaceDef):
            prefix = f"{ns_prefix}__{node.name}" if ns_prefix else node.name
            for func in node.functions:
                self._note_async(func, f"{prefix}__{func.name}")
                if not func.is_prototype:
                    mangled = f"{prefix}__{func.name}"
                    self.funcs[mangled] = func
            for obj in node.objects:
                self._collect_object(obj, prefix=prefix)
            for ns in node.nested_namespaces:
                self._collect_node(ns, ns_prefix=prefix)
        elif isinstance(node, fast.ObjectDef):
            self._collect_object(node, prefix=ns_prefix)
        elif isinstance(node, fast.ObjectDefStatement):
            self._collect_object(node.object_def, prefix=ns_prefix)
        elif isinstance(node, fast.StructDef):
            pass
        elif isinstance(node, fast.StructDefStatement):
            pass
        elif isinstance(node, fast.ExternBlock):
            pass
        elif isinstance(node, fast.ExportBlock):
            for func in node.definitions:
                if not func.is_prototype:
                    self.funcs[func.name] = func

    def _collect_object(self, obj, prefix: str):
        # guard: only ObjectDef has methods we can walk; TraitDef/InterfaceDef do not
        if not isinstance(obj, fast.ObjectDef):
            return
        for method in obj.methods:
            if method.name and method.body:
                mangled = f"{prefix}__{obj.name}__{method.name}" if prefix else f"{obj.name}__{method.name}"
                self.funcs[mangled] = method
        for nested in obj.nested_objects:
            self._collect_object(nested, prefix=f"{prefix}__{obj.name}" if prefix else obj.name)

# ---------------------------------------------------------------------------
# AST Walker
# ---------------------------------------------------------------------------

class _SyntheticCall:
    """Minimal stand-in for a FunctionCall node used when resolving MethodCall targets."""
    def __init__(self, name, arguments, source_file, source_line):
        self.name = name
        self.arguments = arguments
        self.source_file = source_file
        self.source_line = source_line


class BorrowChecker:

    def __init__(self, call_graph: CallGraph, entry: str,
                 check_threads: bool = False,
                 check_leaks: bool = False,
                 line_map: list = None,
                 warn_mode: bool = False):
        self.warn_mode = warn_mode
        self.cg = call_graph
        self.entry = entry
        self.check_threads = check_threads
        self.check_leaks = check_leaks
        self.line_map = line_map or []
        self.alias = AliasMap()
        self.violations: list[Violation] = []
        self.funcs_checked = 0
        # True while walking a function that was invoked from a thread spawn
        self._in_thread_context: bool = False
        # set of function names currently on the active call stack -- prevents
        # infinite recursion when context-sensitive re-entry produces a new
        # call_ctx tuple for an already-active recursive function
        self._call_stack: set[str] = set()
        self._current_func_node: fast.FunctionDef | None = None
        # cache for FVM expression evaluation -- keyed by id(ast_node)
        # stores the result (int, str, or None) so each node is only executed once
        self._fvm_cache: dict[int, object] = {}
        # tracks which heap sites have been stored into arrays:
        # array variable name -> set of heap site strings
        # used to resolve ffree(arr[i]) back to the original heap site
        self._array_heap_sites: dict[str, set] = {}

    def _remap(self, merged_line: int) -> tuple:
        """Map a merged-source line number back to (original_file, original_line)."""
        idx = merged_line - 1
        if self.line_map and 0 <= idx < len(self.line_map):
            fname, orig_line = self.line_map[idx]
            return fname, orig_line
        return '<unknown>', merged_line

    def run(self):
        """Start walk from entry point."""
        if self.entry not in self.cg.funcs:
            print(f"[FBC] Warning: entry point '{self.entry}' not found as a non-prototype function.")
            print(f"      This usually means the entry point body is inside an unresolved #ifdef block.")
            print(f"      Checking all reachable functions instead.")
            for name, func in self.cg.funcs.items():
                if not self.cg.is_visited(name, (), False):
                    self._check_function(func)
        else:
            self._check_function(self.cg.funcs[self.entry])
        # lifetime kinds come from the lifetime analysis, not the alias walk
        _own = ('scope_escape', 'use_after_scope', 'use_after_free', 'heap_leak',
                'mutable_alias')
        self.violations = [v for v in self.violations if v.kind not in _own]
        life = _LifetimeAnalysis(self.cg, self.entry, line_map=self.line_map,
                                 warn_mode=self.warn_mode)
        life.run()
        self.violations = life.violations + self.violations

    # Functions whose job is to allocate and return -- fmalloc inside them
    # that reaches a return statement transfers ownership to the caller, not a leak.
    _ALLOCATOR_FUNCS = {
        'fmalloc', 'ffree',
    }

    def _func_returns_allocation(self, func) -> bool:
        """True if this function is a known allocator wrapper -- fmalloc result returned directly."""
        if func.name in self._ALLOCATOR_FUNCS:
            return True
        if not func.body:
            return False
        # heuristic: single-statement body that returns an fmalloc call or calls fmalloc
        stmts = func.body.statements
        if len(stmts) == 1:
            s = stmts[0]
            if isinstance(s, fast.ReturnStatement) and s.value:
                if _is_fmalloc(s.value):
                    return True
                if isinstance(s.value, fast.CastExpression) and _is_fmalloc(s.value.expression):
                    return True
                if isinstance(s.value, fast.FunctionCall) and isinstance(s.value.name, str):
                    if 'malloc' in s.value.name.lower() or 'alloc' in s.value.name.lower():
                        return True
            if isinstance(s, fast.ExpressionStatement):
                expr = s.expression
                if isinstance(expr, fast.ReturnStatement) and expr.value:
                    if _is_fmalloc(expr.value):
                        return True
        return False

    def _check_function(self, func: fast.FunctionDef, thread_context: bool = False,
                        call_ctx: tuple = ()):
        """
        Analyse one function body.

        call_ctx is a tuple of site strings, one per pointer parameter in
        declaration order, derived from the actual argument expressions at the
        call site.  When a positional site is available it replaces the opaque
        param:<func>:<name> site so alias checking operates on real identities
        across the call boundary.  An empty tuple means the caller could not
        resolve any argument sites (e.g. the call target was not in the call
        graph) and the opaque fallback is used for every parameter.
        """
        if self.cg.is_visited(func.name, call_ctx, thread_context):
            return
        # guard against re-entrant recursion: a recursive function called with a
        # new call_ctx would pass the visited check but is already active on the
        # call stack -- analysing it again would loop forever
        if func.name in self._call_stack:
            return
        self.cg.mark_visited(func.name, call_ctx, thread_context)
        self._call_stack.add(func.name)
        self.funcs_checked += 1

        prev_func = self.alias.func_name
        prev_thread_ctx = self._in_thread_context
        prev_func_node = self._current_func_node
        # isolate callee from caller's live pointer frames so that
        # _check_mutable_alias only sees pointers declared inside this
        # function, not the caller's scope chain
        prev_frames = self.alias.frames
        self.alias.frames = []
        prev_heap_sites = dict(self.alias.heap_sites)
        self.alias.heap_sites = {}
        prev_freed_sites = dict(self.alias.freed_sites)
        self.alias.freed_sites = {}
        prev_alloc_sizes = dict(self.alias.alloc_sizes)
        self.alias.alloc_sizes = {}
        prev_array_heap_sites = self._array_heap_sites
        self._array_heap_sites = {}
        self.alias.func_name = func.name
        self._in_thread_context = thread_context
        self._current_func_node = func

        self.alias.push_scope()

        # register pointer parameters
        # if a positional site was supplied by the caller, use it; otherwise
        # fall back to the opaque param: site
        ptr_params = [p for p in (func.parameters or []) if p.name and _is_pointer_type(p.type_spec)]
        param_sites = []
        for idx, param in enumerate(ptr_params):
            if idx < len(call_ctx) and call_ctx[idx] not in ('unknown', ''):
                site = call_ctx[idx]
                # propagate the caller's known allocation size for this site
                # so bounds checks inside the callee have the size available
                if site in prev_alloc_sizes:
                    self.alias.alloc_sizes[site] = prev_alloc_sizes[site]
            else:
                site = _make_param_site(func.name, param.name)
            self.alias.declare_ptr(
                var_name=param.name,
                site=site,
                mutable=True,  # conservative: treat all pointer params as mutable
                file=_node_file(func),
                line=_node_line(func),
            )
            param_sites.append((param.name, site))
        # check parameter pairs for aliasing -- this is the interprocedural catch:
        # two parameters with the same caller-propagated site are mutable aliases
        self.alias.check_call_args(param_sites, _node_file(func), _node_line(func))

        if func.body:
            self._walk_block(func.body)

        if self.check_leaks and not self._func_returns_allocation(func):
            self.alias.check_heap_leaks()
        else:
            self.alias.heap_sites.clear()
            self.alias.freed_sites.clear()
            self.alias.alloc_sizes.clear()

        self.alias.pop_scope()
        self._call_stack.discard(func.name)
        # restore caller's frame state
        self.alias.frames = prev_frames
        self.alias.heap_sites = prev_heap_sites
        self.alias.freed_sites = prev_freed_sites
        self.alias.alloc_sizes = prev_alloc_sizes
        self._array_heap_sites = prev_array_heap_sites
        self.alias.func_name = prev_func
        self._current_func_node = prev_func_node
        self._in_thread_context = prev_thread_ctx

        # collect violations -- remap merged line numbers to original source locations
        for v in self.alias.violations:
            fname, orig_line = self._remap(v.line)
            v.file = fname
            v.line = orig_line
            # remap detail lines that contain "at <unknown>:N" patterns
            remapped_detail = []
            for d in v.detail:
                parts = d.split(' at ')
                if len(parts) == 2:
                    loc = parts[1]
                    colon = loc.rfind(':')
                    if colon != -1:
                        try:
                            merged = int(loc[colon+1:])
                            df, dl = self._remap(merged)
                            d = parts[0] + f' at {df}:{dl}'
                        except ValueError:
                            pass
                remapped_detail.append(d)
            v.detail = remapped_detail
        seen = {self._violation_key(v) for v in self.violations}
        for v in self.alias.violations:
            if self._violation_key(v) not in seen:
                self.violations.append(v)
                seen.add(self._violation_key(v))
        self.alias.violations.clear()

    def _violation_key(self, v) -> tuple:
        return (v.kind, v.file, v.line, v.message)

    def _walk_block(self, block: fast.Block):
        self.alias.push_scope()
        for stmt in block.statements:
            if stmt is not None:
                self._walk_stmt(stmt)
        self.alias.pop_scope(check_leaks=self.check_leaks)

    def _walk_stmt(self, node):
        file = _node_file(node)
        line = _node_line(node)

        if isinstance(node, fast.VariableDeclaration):
            self._on_var_decl(node)

        elif isinstance(node, fast.Assignment):
            self._on_assign(node)

        elif isinstance(node, fast.CompoundAssignment):
            self._walk_expr(node.value)

        elif isinstance(node, fast.ExpressionStatement):
            self._walk_expr(node.expression)

        elif isinstance(node, fast.Block):
            self._walk_block(node)

        elif isinstance(node, fast.IfStatement):
            self._walk_expr(node.condition)
            # snapshot freed_sites and heap_sites before each branch
            pre_freed = dict(self.alias.freed_sites)
            pre_heap  = dict(self.alias.heap_sites)
            if node.then_block:
                self._walk_block(node.then_block)
            then_freed = dict(self.alias.freed_sites)
            then_heap  = dict(self.alias.heap_sites)
            # restore to pre-branch state before walking else
            self.alias.freed_sites = dict(pre_freed)
            self.alias.heap_sites  = dict(pre_heap)
            if node.else_block:
                self._walk_block(node.else_block)
            else_freed = dict(self.alias.freed_sites)
            else_heap  = dict(self.alias.heap_sites)
            # freed_sites intersection: only keep sites freed on ALL paths
            if node.else_block:
                self.alias.freed_sites = {s: v for s, v in then_freed.items() if s in else_freed}
                # heap_sites union: keep sites that might not be freed on all paths
                merged_heap = dict(then_heap)
                merged_heap.update(else_heap)
                # only drop a site if it was freed on both paths (not in either heap snapshot)
                self.alias.heap_sites = {s: v for s, v in merged_heap.items()
                                         if s in then_heap or s in else_heap}
            else:
                self.alias.freed_sites = dict(pre_freed)
                # no else -- then-branch allocs may or may not have been freed
                merged_heap = dict(pre_heap)
                merged_heap.update(then_heap)
                self.alias.heap_sites = merged_heap

        elif isinstance(node, fast.WhileLoop):
            self._walk_expr(node.condition)
            if node.body:
                pre_freed = dict(self.alias.freed_sites)
                pre_heap  = dict(self.alias.heap_sites)
                self._walk_block(node.body)
                # restore freed_sites -- loop may not execute (UAF tracking)
                self.alias.freed_sites = dict(pre_freed)
                # loop_heap is the post-walk state: sites freed inside the loop
                # body have already been removed from heap_sites by record_free.
                # Merge: keep post-walk state (respects in-loop frees) but also
                # retain any pre-existing sites that were not touched by the loop.
                loop_heap = dict(self.alias.heap_sites)
                # Sites in pre_heap that are also absent from loop_heap were freed
                # inside the loop body -- keep them absent (freed).
                # Sites in loop_heap that were not in pre_heap are new allocations
                # from inside the loop body -- keep them present (may leak).
                merged_heap = {s: v for s, v in pre_heap.items() if s in loop_heap}
                merged_heap.update({s: v for s, v in loop_heap.items() if s not in pre_heap})
                self.alias.heap_sites = merged_heap

        elif isinstance(node, fast.DoWhileLoop):
            if node.body:
                pre_freed = dict(self.alias.freed_sites)
                pre_heap  = dict(self.alias.heap_sites)
                self._walk_block(node.body)
                self.alias.freed_sites = dict(pre_freed)
                loop_heap = dict(self.alias.heap_sites)
                merged_heap = {s: v for s, v in pre_heap.items() if s in loop_heap}
                merged_heap.update({s: v for s, v in loop_heap.items() if s not in pre_heap})
                self.alias.heap_sites = merged_heap
            self._walk_expr(node.condition)

        elif isinstance(node, fast.ForLoop):
            if node.init:
                self._walk_stmt(node.init)
            if node.condition:
                self._walk_expr(node.condition)
            if node.update:
                self._walk_stmt(node.update)
            if node.body:
                pre_freed = dict(self.alias.freed_sites)
                pre_heap  = dict(self.alias.heap_sites)
                self._walk_block(node.body)
                self.alias.freed_sites = dict(pre_freed)
                loop_heap = dict(self.alias.heap_sites)
                merged_heap = {s: v for s, v in pre_heap.items() if s in loop_heap}
                merged_heap.update({s: v for s, v in loop_heap.items() if s not in pre_heap})
                self.alias.heap_sites = merged_heap

        elif isinstance(node, fast.ForInLoop):
            if node.body:
                pre_freed = dict(self.alias.freed_sites)
                pre_heap  = dict(self.alias.heap_sites)
                self._walk_block(node.body)
                self.alias.freed_sites = dict(pre_freed)
                loop_heap = dict(self.alias.heap_sites)
                merged_heap = {s: v for s, v in pre_heap.items() if s in loop_heap}
                merged_heap.update({s: v for s, v in loop_heap.items() if s not in pre_heap})
                self.alias.heap_sites = merged_heap

        elif isinstance(node, fast.SwitchStatement):
            self._walk_expr(node.expression)
            pre_freed = dict(self.alias.freed_sites)
            pre_heap  = dict(self.alias.heap_sites)
            case_freeds = []
            case_heaps  = []
            for case in node.cases:
                self.alias.freed_sites = dict(pre_freed)
                self.alias.heap_sites  = dict(pre_heap)
                if case.body:
                    self._walk_block(case.body)
                case_freeds.append(dict(self.alias.freed_sites))
                case_heaps.append(dict(self.alias.heap_sites))
            if case_freeds:
                intersection = dict(case_freeds[0])
                for cf in case_freeds[1:]:
                    intersection = {s: v for s, v in intersection.items() if s in cf}
                self.alias.freed_sites = intersection
                merged_heap = {}
                for ch in case_heaps:
                    merged_heap.update(ch)
                self.alias.heap_sites = merged_heap
            else:
                self.alias.freed_sites = dict(pre_freed)
                self.alias.heap_sites  = dict(pre_heap)

        elif isinstance(node, fast.ReturnStatement):
            if node.value:
                self._walk_expr(node.value)

        elif isinstance(node, fast.DeferStatement):
            # deferred code executes at function exit, not at this point in
            # control flow -- snapshot freed_sites so any ffree inside the
            # defer body does not falsely mark sites as freed for UAF purposes.
            # heap_sites is NOT snapshotted -- a deferred ffree genuinely removes
            # the site from leak tracking, same as an immediate ffree would.
            pre_freed = dict(self.alias.freed_sites)
            if node.expression:
                self._walk_expr(node.expression)
            if node.body:
                for s in node.body:
                    self._walk_stmt(s)
            self.alias.freed_sites = dict(pre_freed)

        elif isinstance(node, fast.TryBlock):
            if node.try_body:
                pre_freed = dict(self.alias.freed_sites)
                pre_heap  = dict(self.alias.heap_sites)
                self._walk_block(node.try_body)
                try_freed = dict(self.alias.freed_sites)
                try_heap  = dict(self.alias.heap_sites)
            else:
                pre_freed = dict(self.alias.freed_sites)
                pre_heap  = dict(self.alias.heap_sites)
                try_freed = dict(pre_freed)
                try_heap  = dict(pre_heap)
            catch_freeds = []
            catch_heaps  = []
            for _, _, catch_body in (node.catch_blocks or []):
                self.alias.freed_sites = dict(pre_freed)
                self.alias.heap_sites  = dict(pre_heap)
                self._walk_block(catch_body)
                catch_freeds.append(dict(self.alias.freed_sites))
                catch_heaps.append(dict(self.alias.heap_sites))
            # intersection of try and all catch paths for freed_sites
            all_paths = [try_freed] + catch_freeds
            intersection = dict(all_paths[0])
            for pf in all_paths[1:]:
                intersection = {s: v for s, v in intersection.items() if s in pf}
            self.alias.freed_sites = intersection
            # union of heap_sites across all paths
            all_heaps = [try_heap] + catch_heaps
            merged_heap = {}
            for h in all_heaps:
                merged_heap.update(h)
            self.alias.heap_sites = merged_heap

        elif isinstance(node, fast.FunctionDefStatement):
            # nested function def -- walk it under current context
            self._check_function(node.function_def, thread_context=self._in_thread_context)

        # other statement types (break, continue, label, goto, assert etc.)
        # don't introduce pointers so we skip them

    @staticmethod
    def _rhs_is_heap_alloc(expr) -> bool:
        """Return True if expr is fmalloc() or a cast/type-convert wrapping fmalloc()."""
        if expr is None:
            return False
        if _is_fmalloc(expr):
            return True
        if isinstance(expr, (fast.CastExpression, fast.TypeConvertExpression)):
            return BorrowChecker._rhs_is_heap_alloc(expr.expression)
        return False

    def _on_var_decl(self, node: fast.VariableDeclaration):
        file = _node_file(node)
        line = _node_line(node)
        is_ptr = _is_pointer_type(node.type_spec)

        # A variable that stores an fmalloc result must be tracked as a heap
        # pointer regardless of its declared type (e.g. long addr = fmalloc(n)).
        # Without this, ffree(addr) cannot resolve the site and the allocation
        # appears to leak.
        if not is_ptr and self.check_leaks and self._rhs_is_heap_alloc(node.initial_value):
            is_ptr = True

        # Always register the stack site for this variable so its address
        # can be tracked if taken later
        site = _make_stack_site(self.alias.func_name, node.name, line)

        if is_ptr:
            # it's a pointer variable -- what does it point to?
            ptr_site = self._resolve_site(node.initial_value, node.name, file, line)
            # if the RHS is a plain identifier, exclude it from the alias check
            # so that a pointer copy (byte* q = p) does not self-report as an alias --
            # q IS p, they're the same pointer, not a genuine alias.
            # pointer arithmetic (byte* q = p + 8) is a different view into the same
            # allocation -- that IS a genuine alias and must not be excluded.
            rhs = node.initial_value
            if isinstance(rhs, fast.Identifier):
                source_var = rhs.name
            elif isinstance(rhs, (fast.CastExpression, fast.TypeConvertExpression)):
                inner = rhs.expression
                if isinstance(inner, fast.Identifier):
                    source_var = inner.name
                else:
                    source_var = None
            else:
                source_var = None
            #import sys as _sys; _sys.stderr.write(f'[FBC DEBUG] declare_ptr: name={node.name!r} site={ptr_site!r} func={self.alias.func_name!r}\n'); _sys.stderr.flush()
            self.alias.declare_ptr(
                var_name=node.name,
                site=ptr_site,
                mutable=True,
                file=file,
                line=line,
                is_stack_owner=False,
                source_var=source_var,
            )
        else:
            # non-pointer stack variable -- register its site so @node.name can be resolved
            if self.alias.frames:
                frame = self.alias.frames[-1]
                frame.owned_sites.add(site)
                frame.var_sites[node.name] = site
            # if this is a fixed-size stack array, record the element count as
            # the allocation size so bounds checks can use it
            ts = node.type_spec
            if ts is not None and getattr(ts, 'array_size', None) is not None:
                arr_sz = ts.array_size
                if isinstance(arr_sz, int):
                    self.alias.record_alloc_size(site, arr_sz)
                elif hasattr(arr_sz, 'value') and isinstance(arr_sz.value, int):
                    self.alias.record_alloc_size(site, int(arr_sz.value))
                else:
                    # non-constant array size -- try FVM evaluation
                    evaled = self._eval_size_via_fvm(arr_sz)
                    if evaled is not None:
                        self.alias.record_alloc_size(site, evaled)

        if node.initial_value:
            self._walk_expr(node.initial_value)

    def _on_assign(self, node: fast.Assignment):
        file = _node_file(node)
        line = _node_line(node)
        self._walk_expr(node.value)

        # is the target a pointer variable?
        if isinstance(node.target, fast.Identifier):
            var_name = node.target.name
            # check if we know this var as a pointer
            existing = self.alias._find_ptr(var_name)
            if existing is not None:
                new_site = self._resolve_site(node.value, var_name, file, line)
                source_var = node.value.name if isinstance(node.value, fast.Identifier) else None
                self.alias.assign_ptr(var_name, new_site, True, file, line, source_var=source_var)
            elif self.check_leaks and self._rhs_is_heap_alloc(node.value):
                # non-pointer-typed variable being assigned an fmalloc result --
                # register it so ffree(var) can resolve the site later
                new_site = self._resolve_site(node.value, var_name, file, line)
                self.alias.declare_ptr(
                    var_name=var_name,
                    site=new_site,
                    mutable=True,
                    file=file,
                    line=line,
                    is_stack_owner=False,
                    source_var=None,
                )

        # arr[i] = ptr -- record that arr contains heap sites so ffree(arr[j])
        # can be resolved back to a valid heap site
        if self.check_leaks and isinstance(node.target, fast.ArrayAccess):
            base = node.target.array
            if isinstance(base, fast.Identifier):
                arr_name = base.name
                rhs_site = None
                if isinstance(node.value, fast.Identifier):
                    info = self.alias._find_ptr(node.value.name)
                    if info and info.site in self.alias.heap_sites:
                        rhs_site = info.site
                if rhs_site:
                    if arr_name not in self._array_heap_sites:
                        self._array_heap_sites[arr_name] = set()
                    self._array_heap_sites[arr_name].add(rhs_site)

    _SPAWN_IMPL_FUNCS = {'thread_create', 'thread_create_stack', 'pthread_create', 'CreateThread'}

    def _in_spawn_impl(self) -> bool:
        return any(impl in self.alias.func_name for impl in self._SPAWN_IMPL_FUNCS)

    def _check_ident_escape(self, name: str, file: str, line: int):
        """Check if using this identifier touches a thread-escaped site."""
        if self.check_threads and not self._in_spawn_impl():
            self.alias.check_use_after_escape(name, file, line)

    def _unwrap_ptr_ident(self, expr) -> str:
        """Unwrap casts/address-of to find the underlying pointer variable name, if any."""
        if isinstance(expr, fast.Identifier):
            return expr.name
        if isinstance(expr, (fast.CastExpression, fast.TypeConvertExpression)):
            return self._unwrap_ptr_ident(expr.expression)
        if isinstance(expr, fast.AddressOf):
            return self._unwrap_ptr_ident(expr.expression)
        if isinstance(expr, fast.FunctionCall) and expr.arguments:
            return self._unwrap_ptr_ident(expr.arguments[0])
        return None

    def _resolve_fptr_expr(self, expr) -> str | None:
        """
        Compile and execute an arbitrary expression through the FVM to resolve
        a function pointer value to a callee name.

        The FVM represents function pointers as Val(TTag.BYTES, func_name_bytes).
        Executing the expression leaves that value on the stack; we decode it
        and look it up in the call graph.

        Returns the resolved mangled function name, or None if the expression
        cannot be executed or does not resolve to a known function.
        """
        if not _FVM_AVAILABLE:
            return None
        try:
            cg = FVMCodegen()
            cg._visit_expr(expr)
            cg._emit(Instr(Op.HALT, [], 0))
            vm = FluxVM()
            for name, instrs in cg.compiled_functions.items():
                vm.register_function(name, instrs)
            vm.execute(cg._instructions, cg._local_count)
            if not vm.stack:
                return None
            top = vm.stack[-1]
            if top.tag == TTag.BYTES:
                name = top.data.decode('utf-8') if isinstance(top.data, (bytes, bytearray)) else str(top.data)
            elif top.tag == TTag.PTR:
                # PTR may carry a meta dict with a function name when used as a func ptr slot
                meta = getattr(top, 'meta', {}) or {}
                name = meta.get('func_name') or str(top.data)
            else:
                return None
            name = name.strip()
            if name in self.cg.funcs:
                return name
            if name in self.cg.short_names:
                return self.cg.short_names[name]
            return None
        except Exception:
            return None

    def _collect_arg_sites(self, args: list, file: str, line: int) -> list:
        """
        Resolve each argument expression to a (name_hint, site) pair using the
        caller's current alias state.  Used to check aliasing at opaque call sites
        where the callee body is unavailable.
        """
        result = []
        for arg in args:
            hint = self._unwrap_ptr_ident(arg) or '<arg>'
            site = self._resolve_site(arg, hint, file, line)
            result.append((hint, site))
        return result

    def _build_call_ctx(self, func: fast.FunctionDef, call_node: fast.FunctionCall) -> tuple:
        """
        Build a call context tuple for a call site.

        For each pointer parameter of the callee (in declaration order), resolve
        the corresponding argument expression to a site string using the caller's
        current alias state.  Parameters with no corresponding argument (variadics,
        missing args) get 'unknown'.  Non-pointer parameters are skipped so the
        tuple length equals the number of pointer parameters only.

        The tuple is used as a cache key: the callee is re-analysed only when a
        new distinct context (different set of argument sites) is seen.
        """
        ptr_params = [p for p in (func.parameters or []) if p.name and _is_pointer_type(p.type_spec)]
        if not ptr_params:
            return ()

        args = list(call_node.arguments or [])

        # build a positional index: callee param index -> argument expression
        # we need to map pointer-param position back to the full parameter list
        # position so we can select the right argument by index
        full_params = list(func.parameters or [])
        ctx = []
        for ptr_param in ptr_params:
            # find this param's position in the full parameter list
            full_idx = next((i for i, p in enumerate(full_params) if p.name == ptr_param.name), None)
            if full_idx is not None and full_idx < len(args):
                site = self._resolve_site(args[full_idx], ptr_param.name,
                                          _node_file(call_node), _node_line(call_node))
            else:
                site = 'unknown'
            ctx.append(site)
        return tuple(ctx)

    def _resolve_ffree_arg(self, arg) -> str:
        """
        Resolve the argument to ffree() to a heap site string.
        Handles: plain Identifier, @x (AddressOf), cast(x), long(x), u64(x).
        ffree takes a numeric address -- the pointer is often cast before passing.
        """
        # plain identifier: ffree(ptr)
        if isinstance(arg, fast.Identifier):
            info = self.alias._find_ptr(arg.name)
            return info.site if info else 'unknown'
        # cast: ffree(long(argv)) or ffree((u64)argv)
        if isinstance(arg, fast.CastExpression):
            return self._resolve_ffree_arg(arg.expression)
        # function call cast like long(argv) -- FunctionCall with type name
        if isinstance(arg, fast.FunctionCall) and isinstance(arg.name, str):
            if arg.arguments:
                return self._resolve_ffree_arg(arg.arguments[0])
        # address-of: ffree(@argv) -- @argv gives address of the pointer variable
        # the pointer itself is what was malloc'd
        if isinstance(arg, fast.AddressOf):
            inner = arg.expression
            if isinstance(inner, fast.Identifier):
                info = self.alias._find_ptr(inner.name)
                #import sys as _sys; _sys.stderr.write(f'[FBC DEBUG] resolve_ffree_arg @{inner.name!r}: info={info!r}\n'); _sys.stderr.flush()
                return info.site if info else 'unknown'
        # type convert: long(argv), u64(argv) etc.
        if isinstance(arg, fast.TypeConvertExpression):
            return self._resolve_ffree_arg(arg.expression)
        # arr[i] -- if arr is known to hold heap sites, return and remove one
        # This handles the pattern: argv[k] = fmalloc(...) then ffree(argv[k])
        if isinstance(arg, fast.ArrayAccess):
            base = arg.array
            if isinstance(base, fast.Identifier):
                arr_name = base.name
                sites = self._array_heap_sites.get(arr_name)
                if sites:
                    site = next(iter(sites))
                    sites.discard(site)
                    return site
        return 'unknown'

    def _resolve_site_via_fvm(self, expr, var_name: str, file: str, line: int) -> str | None:
        """
        Compile and execute expr through the FVM to recover a site string.
        Results are cached by AST node id.
        """
        if expr is None:
            return None
        key = id(expr)
        if key in self._fvm_cache:
            result = self._fvm_cache[key]
            return result if isinstance(result, str) else None
        if not _FVM_AVAILABLE:
            self._fvm_cache[key] = None
            return None
        try:
            cg = FVMCodegen()
            if self._current_func_node is not None:
                func = self._current_func_node
                for param in (func.parameters or []):
                    cg._alloc_local(param.name)
                body = func.body
                stmts = body.statements if isinstance(body, fast.Block) else ([body] if body else [])
                for stmt in stmts:
                    if isinstance(stmt, fast.VariableDeclaration):
                        cg._alloc_local(stmt.name)
            start = len(cg._instructions)
            cg._visit_expr(expr)
            cg._emit(Instr(Op.HALT, [], 0))
            vm = FluxVM()
            for name, instrs in cg.compiled_functions.items():
                vm.register_function(name, instrs)
            vm.execute(cg._instructions[start:], cg._local_count)
            if not vm.stack:
                self._fvm_cache[key] = None
                return None
            top = vm.stack[-1]
            if top.tag == TTag.PTR:
                slot = int(top.data)
                if slot < cg._local_count:
                    slot_to_name = {v: k for k, v in cg._locals.items()}
                    var = slot_to_name.get(slot)
                    if var:
                        for frame in reversed(self.alias.frames):
                            if var in frame.var_sites:
                                result = frame.var_sites[var]
                                self._fvm_cache[key] = result
                                return result
                        result = _make_stack_site(self.alias.func_name, var, line)
                        self._fvm_cache[key] = result
                        return result
                else:
                    result = f"heap:fvm:{slot}"
                    self._fvm_cache[key] = result
                    return result
            if top.tag == TTag.BYTES:
                name = top.data.decode('utf-8') if isinstance(top.data, (bytes, bytearray)) else str(top.data)
                name = name.strip()
                result = _make_param_site(self.alias.func_name, name)
                self._fvm_cache[key] = result
                return result
            self._fvm_cache[key] = None
            return None
        except Exception:
            self._fvm_cache[key] = None
            return None

    def _resolve_site(self, expr, var_name: str, file: str, line: int) -> str:
        """
        Try to determine what allocation site an expression refers to.
        Returns a site identity string.  Falls back to FVM execution before
        giving up and returning 'unknown'.
        """
        if expr is None:
            return 'unknown'

        # @someVar or @someArray[i] -- address of a stack variable or element
        if isinstance(expr, fast.AddressOf):
            inner = expr.expression
            if isinstance(inner, fast.Identifier):
                target_name = inner.name
                for frame in reversed(self.alias.frames):
                    if target_name in frame.var_sites:
                        return frame.var_sites[target_name]
                return _make_stack_site(self.alias.func_name, target_name, line)
            # @arr[i] -- treat as address of the base array
            if isinstance(inner, fast.ArrayAccess):
                base = inner.array
                if isinstance(base, fast.Identifier):
                    target_name = base.name
                    for frame in reversed(self.alias.frames):
                        if target_name in frame.var_sites:
                            return frame.var_sites[target_name]
                    return _make_stack_site(self.alias.func_name, target_name, line)
            return self._resolve_site_via_fvm(expr, var_name, file, line) or 'unknown'

        # fmalloc() call
        if _is_fmalloc(expr):
            return _make_heap_site(self.alias.func_name, _node_line(expr))

        # ffree() -- site resolution returns unknown; side effect handled in _walk_expr
        if _is_ffree(expr):
            return 'unknown'

        # pointer arithmetic -- derived from base
        if isinstance(expr, fast.BinaryOp) and expr.operator in (Operator.ADD, Operator.SUB):
            base_site = self._resolve_site(expr.left, var_name, file, line)
            if base_site != 'unknown':
                return f"derived:{base_site}"
            right_site = self._resolve_site(expr.right, var_name, file, line)
            if right_site != 'unknown':
                return right_site
            return self._resolve_site_via_fvm(expr, var_name, file, line) or 'unknown'

        # identifier -- copy the site from the existing pointer
        if isinstance(expr, fast.Identifier):
            info = self.alias._find_ptr(expr.name)
            if info:
                site = info.site
                if site in self.alias.freed_sites:
                    return f"freed:{site}"
                return site
            # not a tracked pointer -- check var_sites for stack arrays
            for frame in reversed(self.alias.frames):
                if expr.name in frame.var_sites:
                    return frame.var_sites[expr.name]
            return self._resolve_site_via_fvm(expr, var_name, file, line) or 'unknown'

        # cast / type convert -- mark as derived to avoid false alias with original
        # exception: a cast directly wrapping fmalloc is a fresh allocation and
        # must keep the raw heap: site so ffree can match it
        if isinstance(expr, fast.CastExpression):
            if _is_fmalloc(expr.expression):
                return _make_heap_site(self.alias.func_name, _node_line(expr.expression))
            inner = self._resolve_site(expr.expression, var_name, file, line)
            if inner != 'unknown':
                return f"derived:{inner}"
            return self._resolve_site_via_fvm(expr, var_name, file, line) or 'unknown'
        if isinstance(expr, fast.TypeConvertExpression):
            if _is_fmalloc(expr.expression):
                return _make_heap_site(self.alias.func_name, _node_line(expr.expression))
            inner = self._resolve_site(expr.expression, var_name, file, line)
            if inner != 'unknown':
                return f"derived:{inner}"
            return self._resolve_site_via_fvm(expr, var_name, file, line) or 'unknown'

        # deref -- try FVM before giving up
        if isinstance(expr, fast.PointerDeref):
            return self._resolve_site_via_fvm(expr, var_name, file, line) or 'unknown'

        return self._resolve_site_via_fvm(expr, var_name, file, line) or 'unknown'

    def _eval_index_via_fvm(self, expr) -> int | None:
        """
        Evaluate an expression to a concrete integer via the FVM.
        Results are cached by AST node id so each expression is only executed once.
        """
        if expr is None:
            return None
        # fast path: plain integer literal
        if isinstance(expr, fast.Literal) and isinstance(expr.value, int):
            return expr.value
        # cache check
        key = id(expr)
        if key in self._fvm_cache:
            result = self._fvm_cache[key]
            return result if isinstance(result, int) else None
        if not _FVM_AVAILABLE:
            self._fvm_cache[key] = None
            return None
        try:
            cg = FVMCodegen()
            if self._current_func_node is not None:
                func = self._current_func_node
                for param in (func.parameters or []):
                    cg._alloc_local(param.name)
                body = func.body
                stmts = body.statements if isinstance(body, fast.Block) else ([body] if body else [])
                for stmt in stmts:
                    if isinstance(stmt, fast.VariableDeclaration):
                        cg._alloc_local(stmt.name)
            start = len(cg._instructions)
            cg._visit_expr(expr)
            cg._emit(Instr(Op.HALT, [], 0))
            vm = FluxVM()
            for name, instrs in cg.compiled_functions.items():
                vm.register_function(name, instrs)
            vm.execute(cg._instructions[start:], cg._local_count)
            if not vm.stack:
                self._fvm_cache[key] = None
                return None
            top = vm.stack[-1]
            if top.tag in (TTag.INT, TTag.UINT):
                result = int(top.data)
                self._fvm_cache[key] = result
                return result
            self._fvm_cache[key] = None
            return None
        except Exception:
            self._fvm_cache[key] = None
            return None

    def _eval_size_via_fvm(self, expr) -> int | None:
        """
        Evaluate a size/count expression to a concrete integer via the FVM.
        Unwraps casts and type conversions to reach the underlying value.
        """
        inner = expr
        while isinstance(inner, (fast.CastExpression, fast.TypeConvertExpression)):
            inner = inner.expression
        return self._eval_index_via_fvm(inner)

    def _check_bounds_at_access(self, var_name: str, index_expr, file: str, line: int, write: bool = False):
        """
        Evaluate index_expr to a concrete integer and call alias.check_bounds.
        Silently skips if the index is not statically determinable.
        For stack arrays, var_name is not in ptrs -- look it up via var_sites.
        """
        idx = self._eval_index_via_fvm(index_expr)
        if idx is None:
            return
        # try pointer tracking first (heap allocations)
        info = self.alias._find_ptr(var_name)
        if info is not None:
            self.alias.check_bounds(var_name, idx, file, line, write=write)
            return
        # fall back to var_sites for stack arrays and pointer params with known sizes
        for frame in reversed(self.alias.frames):
            if var_name in frame.var_sites:
                site = frame.var_sites[var_name]
                if site in self.alias.alloc_sizes:
                    size = self.alias.alloc_sizes[site]
                    if size >= 0 and (idx < 0 or idx >= size):
                        kind = 'buffer_overflow' if write else 'out_of_bounds'
                        self.alias.violations.append(Violation(
                            kind=kind,
                            message=(
                                f"array {'write' if write else 'access'} on '{var_name}' at index {idx} is "
                                f"out of bounds (size {size})"
                            ),
                            file=file,
                            line=line,
                            detail=[
                                f"'{var_name}' -> {site} (size {size})",
                                f"index {idx} {'< 0' if idx < 0 else '>= size'}",
                            ]
                        ))
                return

    def _walk_expr(self, node):
        """Walk an expression for side effects (calls, thread spawns, ffree)."""
        if node is None:
            return

        file = _node_file(node)
        line = _node_line(node)

        # fmalloc may be wrapped in a cast: (byte**)fmalloc(...)
        _fmalloc_node = node
        if isinstance(node, (fast.CastExpression, fast.TypeConvertExpression)):
            _fmalloc_node = node.expression
        if _is_fmalloc(_fmalloc_node) and self.check_leaks:
            site = _make_heap_site(self.alias.func_name, _node_line(_fmalloc_node))
            self.alias.record_malloc(site, _node_file(_fmalloc_node), _node_line(_fmalloc_node))
            #import sys as _sys; _sys.stderr.write(f'[FBC DEBUG] record_malloc: site={site!r} func={self.alias.func_name!r}\n'); _sys.stderr.flush()
            # record the allocation size if the argument is statically determinable
            if isinstance(_fmalloc_node, fast.FunctionCall) and _fmalloc_node.arguments:
                size = self._eval_size_via_fvm(_fmalloc_node.arguments[0])
                if size is not None:
                    self.alias.record_alloc_size(site, size)

        if _is_ffree(node) and self.check_leaks:
            if isinstance(node, fast.FunctionCall) and node.arguments:
                arg = node.arguments[0]
                # resolve the argument to a site -- handles Identifier, @x, cast(x), etc.
                freed_site = self._resolve_ffree_arg(arg)
                #import sys as _sys; _sys.stderr.write(f'[FBC DEBUG] ffree: arg type={type(arg).__name__!r} freed_site={freed_site!r} func={self.alias.func_name!r} heap_sites={list(self.alias.heap_sites.keys())!r}\n'); _sys.stderr.flush()
                if freed_site and freed_site != 'unknown':
                    self.alias.record_free(freed_site)
                    self.alias.mark_freed(freed_site, file, line)

        if self.check_threads and _is_thread_spawn(node):
            # look for pointer arguments being passed -- unwrap casts to find identifiers
            args = getattr(node, 'arguments', []) or []

            # find the function-pointer argument -- typically the first arg
            # that resolves to a known function name
            spawned_func_name = None
            for arg in args:
                cand = self._unwrap_ptr_ident(arg)
                if cand and cand in self.cg.funcs:
                    spawned_func_name = cand
                    break
                if cand and cand in self.cg.short_names:
                    spawned_func_name = self.cg.short_names[cand]
                    break

            for arg in args:
                name = self._unwrap_ptr_ident(arg)
                if name:
                    self.alias.check_thread_escape(name, file, line)

            if spawned_func_name and spawned_func_name in self.cg.funcs:
                prev_count = self.cg.spawn_count.get(spawned_func_name, 0)
                self.cg.spawn_count[spawned_func_name] = prev_count + 1

                # walk spawned function under thread context if not done yet under this context
                spawned_func = self.cg.funcs[spawned_func_name]
                spawn_ctx = self._build_call_ctx(spawned_func, node)
                if not self.cg.is_visited(spawned_func_name, spawn_ctx, True):
                    self._check_function(spawned_func, thread_context=True, call_ctx=spawn_ctx)

                # if this function is spawned more than once, its mutable pointer
                # params can race with themselves across concurrent instances
                if prev_count >= 1:
                    spawned_func = self.cg.funcs[spawned_func_name]
                    mutable_ptr_params = [
                        p for p in (spawned_func.parameters or [])
                        if p.name and _is_pointer_type(p.type_spec)
                    ]
                    if mutable_ptr_params:
                        param_names = ', '.join(p.name for p in mutable_ptr_params)
                        self.violations.append(Violation(
                            kind='thread_self_race',
                            message=(
                                f"function '{spawned_func_name}' is spawned as a thread "
                                f"{prev_count + 1} times -- concurrent instances share "
                                f"mutable pointer parameter(s): {param_names}"
                            ),
                            file=file,
                            line=line,
                            detail=[
                                f"each spawn receives a separate pointer value but if "
                                f"those values alias the same allocation site, a data "
                                f"race exists between the concurrent instances"
                            ]
                        ))

        # check any identifier use against thread-escaped sites
        if self.check_threads and isinstance(node, fast.Identifier):
            self._check_ident_escape(node.name, file, line)

        # resolve calls into the call graph
        if isinstance(node, fast.FunctionCall):
            callee_name = node.name if isinstance(node.name, str) else None
            # if the callee is an expression (function pointer), try FVM to resolve it
            if callee_name is None and node.name is not None:
                callee_name = self._resolve_fptr_expr(node.name)
            if callee_name:
                cur_ctx = self._in_thread_context
                resolved = callee_name if callee_name in self.cg.funcs else self.cg.short_names.get(callee_name)
                # never walk into allocator bodies -- their internal heap management
                # would pollute freed_sites and heap_sites with false entries
                base_name = (resolved or callee_name or '').split('__')[-1]
                is_allocator = base_name in self._ALLOCATOR_FUNCS or callee_name in self._ALLOCATOR_FUNCS
                if resolved and not is_allocator:
                    ctx_tuple = self._build_call_ctx(self.cg.funcs[resolved], node)
                    if not self.cg.is_visited(resolved, ctx_tuple, cur_ctx):
                        self._check_function(self.cg.funcs[resolved], thread_context=cur_ctx,
                                             call_ctx=ctx_tuple)
                elif not is_allocator:
                    # try overload index -- call site uses base name, codegen adds arity suffix
                    for mangled in self.cg.overloads.get(callee_name, []):
                        ctx_tuple = self._build_call_ctx(self.cg.funcs[mangled], node)
                        if not self.cg.is_visited(mangled, ctx_tuple, cur_ctx):
                            self._check_function(self.cg.funcs[mangled], thread_context=cur_ctx,
                                                 call_ctx=ctx_tuple)
                    # callee not in call graph (extern, truly-runtime function pointer)
                    # check argument aliasing at the call site in the caller scope
                    if not self.cg.overloads.get(callee_name):
                        arg_sites = self._collect_arg_sites(list(node.arguments or []), file, line)
                        self.alias.check_call_args(arg_sites, file, line)
                    # DEBUG
                    #if not self.cg.overloads.get(callee_name):
                    #    print(f"[FBC DEBUG] unresolved call in {self.alias.func_name!r}: {callee_name!r}")
                # DEBUG
                #elif not resolved:
                #    print(f"[FBC DEBUG] unresolved call: {callee_name!r} -- likely extern or intra-namespace (caller scope not tracked)")
            else:
                # name expression could not be resolved even with FVM -- check args for aliasing
                arg_sites = self._collect_arg_sites(list(node.arguments or []), file, line)
                self.alias.check_call_args(arg_sites, file, line)
                # DEBUG
                #print(f"[FBC DEBUG] unresolvable call expr in {self.alias.func_name!r}: {type(node.name).__name__}")
            for arg in (node.arguments or []):
                self._walk_expr(arg)

        elif isinstance(node, fast.MethodCall):
            self._walk_expr(node.object)
            for arg in (node.arguments or []):
                self._walk_expr(arg)
            # attempt to resolve the method to a known function body
            method_name = getattr(node, 'method_name', None) or getattr(node, 'name', None)
            if method_name:
                obj_hint = self._unwrap_ptr_ident(node.object) or ''
                resolved_method = None
                # try <obj_hint>__<method> (variable name), then short name lookup,
                # then scan all functions whose name ends with __<method>
                candidates = []
                if obj_hint:
                    candidates.append(f"{obj_hint}__{method_name}")
                candidates.append(method_name)
                for candidate in candidates:
                    if candidate in self.cg.funcs:
                        resolved_method = candidate
                        break
                    if candidate in self.cg.short_names:
                        resolved_method = self.cg.short_names[candidate]
                        break
                # scan all functions whose mangled name ends with __<method_name>
                # this covers Type__method when obj_hint is a variable name not the type
                if not resolved_method:
                    suffix = f"__{method_name}"
                    for mangled in self.cg.funcs:
                        if mangled.endswith(suffix):
                            resolved_method = mangled
                            break
                #import sys as _sys; _sys.stderr.write(f'[FBC DEBUG] MethodCall obj={obj_hint!r} method={method_name!r} resolved={resolved_method!r}\n'); _sys.stderr.flush()
                # if static name lookup failed, try FVM on the full method expression
                if not resolved_method:
                    resolved_method = self._resolve_fptr_expr(node)
                if resolved_method:
                    synth = _SyntheticCall(resolved_method, list(node.arguments or []),
                                           _node_file(node), _node_line(node))
                    ctx_tuple = self._build_call_ctx(self.cg.funcs[resolved_method], synth)
                    cur_ctx = self._in_thread_context
                    if not self.cg.is_visited(resolved_method, ctx_tuple, cur_ctx):
                        self._check_function(self.cg.funcs[resolved_method],
                                             thread_context=cur_ctx, call_ctx=ctx_tuple)
                else:
                    # callee not resolvable -- check argument aliasing at the call site
                    arg_sites = self._collect_arg_sites(list(node.arguments or []), file, line)
                    self.alias.check_call_args(arg_sites, file, line)

        elif isinstance(node, fast.BinaryOp):
            self._walk_expr(node.left)
            self._walk_expr(node.right)

        elif isinstance(node, fast.UnaryOp):
            self._walk_expr(node.operand)

        elif isinstance(node, fast.AddressOf):
            self._walk_expr(node.expression)

        elif isinstance(node, fast.PointerDeref):
            # check for use-after-thread-escape
            if self.check_threads and isinstance(node.pointer, fast.Identifier):
                self.alias.check_use_after_escape(node.pointer.name, file, line)
            # check for use-after-free
            if isinstance(node.pointer, fast.Identifier):
                #import sys as _sys; _sys.stderr.write(f'[FBC DEBUG] PointerDeref: ptr={node.pointer.name!r} freed_sites={list(self.alias.freed_sites.keys())!r}\n'); _sys.stderr.flush()
                self.alias.check_use_after_free(node.pointer.name, file, line)
            self._walk_expr(node.pointer)

        elif isinstance(node, fast.MemberAccess):
            self._walk_expr(node.object)

        elif isinstance(node, fast.ArrayAccess):
            # check for access to thread-escaped pointer
            if self.check_threads and isinstance(node.array, fast.Identifier):
                self.alias.check_use_after_escape(node.array.name, file, line)
            # check for use-after-free
            if isinstance(node.array, fast.Identifier):
                self.alias.check_use_after_free(node.array.name, file, line)
            # check for statically-determinable out-of-bounds index
            if isinstance(node.array, fast.Identifier):
                self._check_bounds_at_access(node.array.name, node.index, file, line)
            self._walk_expr(node.array)
            self._walk_expr(node.index)

        elif isinstance(node, fast.CastExpression):
            self._walk_expr(node.expression)

        elif isinstance(node, fast.TypeConvertExpression):
            self._walk_expr(node.expression)

        elif isinstance(node, fast.IfExpression):
            self._walk_expr(node.condition)
            self._walk_expr(node.then_expr)
            self._walk_expr(node.else_expr)

        elif isinstance(node, fast.TernaryOp):
            self._walk_expr(node.condition)
            self._walk_expr(node.true_expr)
            self._walk_expr(node.false_expr)

        elif isinstance(node, fast.Assignment):
            self._walk_expr(node.value)
            # check lvalue target for escaped site access
            if self.check_threads:
                if isinstance(node.target, fast.Identifier):
                    self._check_ident_escape(node.target.name, file, line)
                elif isinstance(node.target, fast.ArrayAccess):
                    arr = node.target.array
                    if isinstance(arr, fast.Identifier):
                        self._check_ident_escape(arr.name, file, line)
            # check lvalue target for use-after-free
            if isinstance(node.target, fast.PointerDeref):
                inner = node.target.pointer
                if isinstance(inner, fast.Identifier):
                    self.alias.check_use_after_free(inner.name, file, line)
                    self.alias.check_write_alias(inner.name, file, line)
            elif isinstance(node.target, fast.ArrayAccess):
                arr = node.target.array
                if isinstance(arr, fast.Identifier):
                    self.alias.check_use_after_free(arr.name, file, line)
                    self.alias.check_write_alias(arr.name, file, line)
                    self._check_bounds_at_access(arr.name, node.target.index, file, line, write=True)
                    # arr[i] = ptr -- track heap sites stored into arrays so
                    # ffree(arr[j]) can resolve back to the original heap site
                    if self.check_leaks and isinstance(node.value, fast.Identifier):
                        info = self.alias._find_ptr(node.value.name)
                        if info and info.site in self.alias.heap_sites:
                            if arr.name not in self._array_heap_sites:
                                self._array_heap_sites[arr.name] = set()
                            self._array_heap_sites[arr.name].add(info.site)
            # if target is a known pointer, update its site
            if isinstance(node.target, fast.Identifier):
                existing = self.alias._find_ptr(node.target.name)
                if existing is not None:
                    new_site = self._resolve_site(node.value, node.target.name,
                                                  _node_file(node), _node_line(node))
                    source_var = node.value.name if isinstance(node.value, fast.Identifier) else None
                    self.alias.assign_ptr(node.target.name, new_site, True,
                                          _node_file(node), _node_line(node), source_var=source_var)

        elif isinstance(node, fast.CompoundAssignment):
            self._walk_expr(node.value)

# ---------------------------------------------------------------------------
# File parsing
# ---------------------------------------------------------------------------

def parse_file(path: str):
    """Returns (Program, line_map) where line_map[i] = (filename, orig_line) for merged line i+1."""
    platform_macros = build_compiler_macros()
    preprocessor = FXPreprocessor(path, compiler_constants=platform_macros)
    source = preprocessor.process()
    line_map = preprocessor.line_map  # list of (filename, orig_line_1based)
    lexer = FluxLexer(source)
    tokens = lexer.tokenize()
    parser = FluxParser(tokens)
    return parser.parse(), line_map

def collect_fx_files(path: str) -> list[str]:
    p = Path(path)
    if p.is_file():
        return [str(p)]
    return sorted(str(f) for f in p.rglob('*.fx'))

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Lifetime and ownership analysis (part of the borrow checker)
#
# Tracks, flow-sensitively and across calls via function summaries, where each
# pointer may point (stack block, parameter pointee, heap site, static,
# dangling) and whether each heap allocation is owned, freed or maybe freed.
# Owns: scope_escape, use_after_scope, use_after_free, maybe_use_after_free,
# double_free, invalid_free, heap_leak.  No FVM dependence.
# ---------------------------------------------------------------------------
from dataclasses import dataclass

FN = 'fn'   # block id for the function-level scope


def _line(node, default=0):
    ln = getattr(node, 'source_line', 0)
    return ln if ln else default


class State:
    """Abstract state at one program point."""
    __slots__ = ('env', 'held', 'status', 'esc', 'dead', 'free_at', 'active', 'tasks', 'terms')

    def __init__(self):
        self.env = {}        # var -> frozenset(regions)
        self.held = {}       # cell-owning region -> frozenset(regions)
        self.status = {}     # heap/param region -> frozenset of 'O','F'
        self.esc = set()     # heap regions that were handed off
        self.dead = False
        self.free_at = {}    # region -> (line)
        self.active = ()     # tuple of active block ids
        self.tasks = {}      # id(call node) -> _Task live at this point
        self.terms = {}      # integer var -> (param index or -1, constant): param + constant

    def copy(self):
        s = State()
        s.env = dict(self.env)
        s.held = dict(self.held)
        s.status = dict(self.status)
        s.esc = set(self.esc)
        s.dead = self.dead
        s.free_at = dict(self.free_at)
        s.active = self.active
        s.tasks = dict(self.tasks)
        s.terms = dict(self.terms)
        return s

    def key(self):
        return (frozenset(self.env.items()), frozenset(self.held.items()),
                frozenset(self.status.items()), frozenset(self.esc), self.dead,
                frozenset(self.tasks), frozenset(self.terms.items()))


def _join_dict(a, b):
    out = dict(a)
    for k, v in b.items():
        out[k] = out[k] | v if k in out else v
    return out


def join(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if a.dead:
        return b.copy()
    if b.dead:
        return a.copy()
    s = State()
    s.env = _join_dict(a.env, b.env)
    s.held = _join_dict(a.held, b.held)
    s.status = _join_dict(a.status, b.status)
    s.esc = a.esc | b.esc
    s.free_at = dict(a.free_at)
    s.free_at.update(b.free_at)
    s.active = a.active if len(a.active) <= len(b.active) else b.active
    s.tasks = dict(a.tasks)
    s.tasks.update(b.tasks)
    s.terms = {k: v for k, v in a.terms.items() if b.terms.get(k) == v}
    return s


@dataclass
class Summary:
    ret: frozenset = frozenset()
    param_status: dict = None     # idx -> frozenset of statuses at exit
    param_held: dict = None       # idx -> frozenset of regions (callee terms)
    heap_status: dict = None      # heap region -> statuses at exit
    esc: frozenset = frozenset()
    free_at: dict = None
    wr: frozenset = frozenset()    # parameter indices written through
    fp: dict = None                # footprint: ('p', i) | ('g', name) -> [(bits, atomic_only, range)]


# footprint access bits
A_R, A_W, A_F = 1, 2, 4
FATAL_KINDS = frozenset(('async_contradiction',))
_ATOMIC_NS = 'standard__atomic__'


class _Task:
    """An async call that may still be running: its footprint is in caller terms."""
    __slots__ = ('fn', 'fp', 'line', 'result_var', 'bid', 'node')

    def __init__(self, fn, fp, line, bid, node):
        self.fn = fn
        self.fp = fp            # root region -> [(bits, atomic_only, range)]
        self.line = line
        self.result_var = None
        self.bid = bid
        self.node = node


def _modes_conflict(a, b):
    bits = a[0] | b[0]
    if bits & A_F:
        return True
    if bits & A_W:
        return not (a[1] and b[1])
    return False


def _term_le(a, b):
    """a <= b provably, for terms (param index or -1, constant)."""
    if a[0] == b[0]:
        return a[1] <= b[1]
    return False


def _ranges_overlap(r1, r2):
    """Half-open index ranges; None means the whole object."""
    if r1 is None or r2 is None:
        return True
    if _term_le(r1[1], r1[0]) or _term_le(r2[1], r2[0]):
        return False                      # empty
    if _term_le(r1[1], r2[0]) or _term_le(r2[1], r1[0]):
        return False
    return True


def _mode_name(m):
    if m[0] & A_F:
        return 'free'
    if m[0] & A_W:
        return 'atomic write' if m[1] else 'write'
    return 'atomic read' if m[1] else 'read'


class _AliasCtx:
    """Per-function facts for the readers/writer rule."""
    def __init__(self):
        self.ix = {}            # id(Identifier node) -> (seq, path, loops)
        self.uses = {}          # name -> [(seq, path, loops)]
        self.first = {}         # name -> sequence number of its declaration
        self.writers = set()    # names written through somewhere in the function
        self.loop_start = {}    # loop id -> sequence number where it starts
        self.loop_end = {}      # loop id -> sequence number where it ends
        self.defs = {}          # name -> [(seq, path, loops)] unconditional-or-not definitions
        self.ptr_vars = set()   # names declared with a pointer type
        self.deriv = {}         # name -> names it was derived from
        self.wr_params = set()  # parameter indices written through
        self.seq = 0


class _LifetimeAnalysis:

    def __init__(self, call_graph, entry, line_map=None, warn_mode=False):
        self.cg = call_graph
        self.entry = entry
        self.warn_mode = warn_mode
        self.line_map = line_map or []
        self.violations = []
        self._seen = set()
        self.summaries = {}
        self._active_summ = set()
        self.funcs_checked = 0
        self.multi = set()
        # per-function walk context
        self._fn = None
        self._locals = {}
        self._loops = []
        self._defers = []
        self._returns = []
        self._cur_line = 0
        self._al = _AliasCtx()
        self._fp = {}
        self._async_node = None
        self._last_task = None
        self._ivars = {}
        self._no_access = False
        self._ivars = {}
        self.rel = {}
        # decisions handed to the async lowering
        self.async_launched = set()   # id(call node) of every call modelled as a task
        self.async_seq = set()        # id(call node) that must run sequentially
        self.async_waits = {}         # id(call node) -> [id(task node) it must wait for]
        self.async_target = {}        # id(call node) -> resolved callee key (async calls only)

    # ------------------------------------------------------------------
    # reporting
    # ------------------------------------------------------------------
    def _remap(self, merged_line):
        idx = merged_line - 1
        if self.line_map and 0 <= idx < len(self.line_map):
            return self.line_map[idx]
        return '<unknown>', merged_line

    def _report(self, kind, message, line, detail=None):
        f, l = self._remap(line)
        k = (kind, f, l, message)
        if k in self._seen:
            return
        self._seen.add(k)
        self.violations.append(Violation(kind=kind, message=message, file=f,
                                         line=l, detail=detail or [], func=self._fn or ''))

    def _where(self, line):
        f, l = self._remap(line)
        return f"{f}:{l}"

    @staticmethod
    def _origin(r):
        """Innermost (func, line) of a heap region."""
        while r[0] == 'heap' and len(r) == 4:
            r = r[3]
        return r

    def _rdesc(self, r):
        if r[0] == 'heap':
            o = self._origin(r)
            return f"heap:{o[1]}:{self._remap(o[2])[1]}"
        if r[0] == 'stack':
            return f"stack:{r[1]}:{r[2]}"
        if r[0] == 'param':
            return f"param:{r[1]}:{r[2]}"
        if r[0] == 'dangling':
            return f"stack:{r[1]}:{r[2]}"
        return str(r[1]) if len(r) > 1 else r[0]

    # ------------------------------------------------------------------
    # driver
    # ------------------------------------------------------------------
    def run(self):
        self._build_relations()
        if self.entry in self.cg.funcs:
            self._summary(self.entry)
        else:
            for name in list(self.cg.funcs):
                self._summary(name)

    # ------------------------------------------------------------------
    # call resolution
    # ------------------------------------------------------------------
    def _resolve(self, name, nargs):
        if not isinstance(name, str):
            return None
        if name in self.cg.funcs:
            return name
        if name in self.cg.short_names:
            return self.cg.short_names[name]
        cands = self.cg.overloads.get(name, [])
        if len(cands) == 1:
            return cands[0]
        for c in cands:
            if len(self.cg.funcs[c].parameters or []) == nargs:
                return c
        return None

    # ------------------------------------------------------------------
    # function summary (walk once, context-insensitive)
    # ------------------------------------------------------------------
    def _summary(self, name):
        if name in self.summaries:
            return self.summaries[name]
        if name in self._active_summ:
            return Summary(param_status={}, param_held={}, heap_status={},
                           free_at={}, fp={})
        self._active_summ.add(name)
        saved = (self._fn, self._locals, self._loops, self._defers,
                 self._returns, self._cur_line, self._al, self._fp,
                 self._async_node, self._last_task, self._ivars)
        func = self.cg.funcs[name]
        self.funcs_checked += 1
        self._al = _AliasCtx()
        self._fp = {}
        self._async_node = None
        self._last_task = None
        self._ivars = {}
        self._index_function(func)
        self._fn = name
        self._locals = {}
        self._loops = []
        self._defers = [[]]
        self._returns = []
        self._cur_line = _line(func)

        st = State()
        st.active = (FN,)
        for i, p in enumerate(func.parameters or []):
            if p.name is None:
                continue
            reg = ('stack', name, p.name, FN)
            self._locals[p.name] = ('val', reg)
            ts = p.type_spec
            if getattr(ts, 'is_pointer', False):
                self._al.ptr_vars.add(p.name)
            self._al.first[p.name] = -1
            if self._may_carry_pointer(ts):
                st.env[p.name] = frozenset([('param', name, i)])
            else:
                st.env[p.name] = frozenset()
            if not getattr(ts, 'is_pointer', False) and not getattr(ts, 'is_array', False):
                st.terms[p.name] = (i, 0)
        if func.body is not None:
            self._block(func.body, st, new_scope=False)
        if not st.dead:
            self._run_defers_all(st)
            self._exit(st, frozenset(), self._cur_line)
            self._returns.append((st.copy(), frozenset()))
        # join exits
        exit_state = None
        ret = frozenset()
        for s, r in self._returns:
            exit_state = join(exit_state, s)
            ret = ret | r
        summ = Summary(ret=ret, param_status={}, param_held={}, heap_status={},
                       free_at={}, fp={})
        if exit_state is not None:
            n = len(func.parameters or [])
            for i in range(n):
                pr = ('param', name, i)
                if pr in exit_state.status:
                    summ.param_status[i] = exit_state.status[pr]
                for k, v in exit_state.held.items():
                    path = []
                    c = k
                    while c[0] == 'fld':
                        path.append(c[2])
                        c = c[1]
                    if c == pr and v:
                        summ.param_held.setdefault(i, []).append((tuple(reversed(path)), v))
            for r, v in exit_state.status.items():
                if r[0] == 'heap':
                    summ.heap_status[r] = v
            summ.esc = frozenset(exit_state.esc)
            summ.free_at = dict(exit_state.free_at)
            # held contents of static cells escape the function too
            summ.heap_status = summ.heap_status
        summ.wr = frozenset(self._al.wr_params)
        summ.fp = {k: list(v) for k, v in self._fp.items()}
        (self._fn, self._locals, self._loops, self._defers,
         self._returns, self._cur_line, self._al, self._fp,
         self._async_node, self._last_task, self._ivars) = saved
        self._active_summ.discard(name)
        self.summaries[name] = summ
        return summ

    # ------------------------------------------------------------------
    # statements
    # ------------------------------------------------------------------
    def _block(self, block, st, new_scope=True):
        bid = id(block)
        if new_scope:
            st.active = st.active + (bid,)
        self._defers.append([])
        for stmt in block.statements:
            if stmt is None:
                continue
            if st.dead:
                break
            self._stmt(stmt, st, bid if new_scope else FN)
        if not st.dead:
            self._run_defers_top(st)
        self._defers.pop()
        if new_scope:
            st.active = tuple(b for b in st.active if b != bid)
            for tid in [k for k, t in st.tasks.items() if t.bid == bid]:
                del st.tasks[tid]

    def _run_defers_top(self, st):
        for d in reversed(self._defers[-1]):
            self._run_defer(d, st)
        self._defers[-1] = []

    def _run_defers_all(self, st):
        for lvl in reversed(self._defers):
            for d in reversed(lvl):
                self._run_defer(d, st)

    def _run_defer(self, d, st):
        if d.body is not None:
            for s in d.body:
                self._stmt(s, st, FN)
        elif d.expression is not None:
            self._eval(d.expression, st)

    def _stmt(self, node, st, bid):
        ln = _line(node, self._cur_line)
        self._cur_line = ln

        if isinstance(node, fast.VariableDeclaration):
            self._decl(node, st, bid)
        elif isinstance(node, fast.ExpressionStatement):
            self._async_node = node.expression
            self._eval(node.expression, st)
        elif isinstance(node, fast.Assignment):
            self._assign(node.target, node.value, st)
        elif isinstance(node, fast.CompoundAssignment):
            self._compound(node, st)
        elif isinstance(node, fast.Block):
            self._block(node, st)
        elif isinstance(node, fast.ReturnStatement):
            self._return(node, st)
        elif isinstance(node, fast.IfStatement):
            self._if(node, st)
        elif isinstance(node, fast.WhileLoop):
            self._loop(st, cond=node.condition, body=node.body, check_first=True)
        elif isinstance(node, fast.DoWhileLoop):
            self._loop(st, cond=node.condition, body=node.body, check_first=False)
        elif isinstance(node, fast.DoLoop):
            self._loop(st, cond=None, body=node.body, check_first=False, once=True)
        elif isinstance(node, fast.ForLoop):
            st.active = st.active + (id(node),)
            if node.init is not None:
                self._stmt(node.init, st, id(node))
            self._loop(st, cond=node.condition, body=node.body,
                       check_first=True, update=node.update)
            st.active = tuple(b for b in st.active if b != id(node))
        elif isinstance(node, fast.ForInLoop):
            self._eval(node.iterable, st)
            for v in (node.variables or []):
                st.env[v] = frozenset()
                self._locals[v] = ('val', ('stack', self._fn, v, id(node.body)))
            self._loop(st, cond=None, body=node.body, check_first=True)
        elif isinstance(node, fast.SwitchStatement):
            self._switch(node, st)
        elif isinstance(node, fast.BreakStatement):
            if self._loops:
                self._loops[-1]['breaks'].append(st.copy())
            st.dead = True
        elif isinstance(node, fast.ContinueStatement):
            if self._loops:
                self._loops[-1]['conts'].append(st.copy())
            st.dead = True
        elif isinstance(node, fast.DeferStatement):
            self._defers[-1].append(node)
        elif isinstance(node, fast.TryBlock):
            pre = st.copy()
            self._block(node.try_body, st)
            res = join(pre, st)
            for c in node.catch_blocks:
                s2 = pre.copy()
                self._block(c[2], s2)
                res = join(res, s2)
            self._assign_state(st, res)
        else:
            self._generic(node, st)

    @staticmethod
    def _assign_state(dst, src):
        for f in State.__slots__:
            setattr(dst, f, getattr(src, f))

    def _generic(self, node, st):
        """Unknown statement: evaluate its expressions, walk nested blocks."""
        if not hasattr(node, '__dict__'):
            return
        for v in list(vars(node).values()):
            if isinstance(v, fast.Block):
                self._block(v, st)
            elif isinstance(v, fast.ASTNode):
                if isinstance(v, fast.Statement):
                    self._stmt(v, st, FN)
                else:
                    self._eval(v, st)
            elif isinstance(v, list):
                for x in v:
                    if isinstance(x, fast.Block):
                        self._block(x, st)
                    elif isinstance(x, fast.Statement):
                        self._stmt(x, st, FN)
                    elif isinstance(x, fast.ASTNode):
                        self._eval(x, st)

    # -- declarations ---------------------------------------------------
    def _decl(self, node, st, bid):
        ts = node.type_spec
        reg = ('stack', self._fn, node.name, bid)
        if getattr(node, 'is_global', False):
            reg = ('static', node.name)
        is_arr = bool(getattr(ts, 'is_array', False))
        self._locals[node.name] = ('array' if is_arr else 'val', reg)
        st.env[node.name] = frozenset()
        st.terms.pop(node.name, None)
        if getattr(ts, 'is_pointer', False) and not is_arr:
            self._al.ptr_vars.add(node.name)
        iv = node.initial_value
        if iv is not None and not isinstance(iv, (list, tuple)):
            self._al.deriv.setdefault(node.name, set()).update(self._rhs_vars(iv, node.name))
        if iv is not None:
            if isinstance(iv, (list, tuple)):
                for e in iv:
                    self._store_cells(frozenset([reg]), self._eval(e, st), st, False, node)
                return
            elems = getattr(iv, 'elements', None)
            if elems is not None and not isinstance(iv, fast.FunctionCall):
                for e in elems:
                    self._store_cells(frozenset([reg]), self._eval(e, st), st, False, node)
                return
            self._async_node = iv
            self._last_task = None
            tm = None if (is_arr or getattr(ts, 'is_pointer', False)) else self._term_of(iv, st)
            v = self._eval(iv, st)
            if tm is not None:
                st.terms[node.name] = tm
            if self._last_task is not None and self._last_task.node is iv:
                self._last_task.result_var = node.name
                self._last_task = None
            if not is_arr:
                st.env[node.name] = v

    # -- assignment -------------------------------------------------------
    def _assign(self, target, value, st):
        self._async_node = value
        self._last_task = None
        v = self._eval(value, st)
        if self._last_task is not None and self._last_task.node is value:
            if isinstance(target, fast.Identifier):
                self._last_task.result_var = target.name
            self._last_task = None
        if isinstance(target, fast.Identifier):
            n = target.name
            if n in self._locals and self._locals[n][1][0] != 'static':
                self._al.deriv.setdefault(n, set()).update(self._rhs_vars(value, n))
                self._access(frozenset([self._locals[n][1]]), A_W, st)
                tm = self._term_of(value, st)
                if tm is not None:
                    st.terms[n] = tm
                else:
                    st.terms.pop(n, None)
                st.env[n] = v
                return
            # global
            reg = ('static', n)
            self._access(frozenset([reg]), A_W, st)
            self._escape_check(frozenset([reg]), v, st, target)
            st.held[reg] = v
            self._mark_esc(v, st)
            return
        cells, dr = self._cells_of(target, st)
        if dr:
            self._deref_check(dr, target, st)
            self._alias_check(target, dr, st, True)
        self._access(frozenset(self._root(c) for c in cells), A_W, st,
                     rng=self._acc_range(target, st))
        if isinstance(target, fast.ArrayAccess) and not isinstance(target.index, fast.Literal):
            for r in v:
                if r[0] in ('heap', 'param'):
                    self.multi.add(r)
        self._store_cells(cells, v, st, True, target)

    _NON_VALUE_OPS = frozenset((
        'EQUAL', 'NOT_EQUAL', 'LESS_THAN', 'LESS_EQUAL', 'GREATER_THAN',
        'GREATER_EQUAL', 'AND', 'OR', 'NAND', 'NOR', 'XOR', 'NOT'))

    _NON_CARRIER = frozenset(('FLOAT', 'DOUBLE', 'STRUCT', 'UNION', 'OBJECT',
                              'ENUM', 'VOID', 'FUNC_PTR', 'DICT', 'THIS', 'BOOL'))

    def _may_carry_pointer(self, ts):
        """A pointer, or an integer that can hold an address."""
        if ts is None:
            return False
        if getattr(ts, 'is_pointer', False):
            return True
        if getattr(ts, 'is_array', False) or getattr(ts, 'custom_typename', None):
            return False
        bt = getattr(ts, 'base_type', None)
        return bt is not None and getattr(bt, 'name', '') not in self._NON_CARRIER

    # ------------------------------------------------------------------
    # many readers or one writer
    # ------------------------------------------------------------------
    def _root_ident(self, e):
        while True:
            if isinstance(e, fast.Identifier):
                return e
            if isinstance(e, fast.PointerDeref):
                e = e.pointer
            elif isinstance(e, fast.ArrayAccess):
                e = e.array
            elif isinstance(e, fast.MemberAccess):
                e = e.object
            elif isinstance(e, fast.CastExpression):
                e = e.expression
            else:
                return None

    def _rhs_vars(self, e, exclude):
        out = set()
        def walk(n):
            if isinstance(n, fast.Identifier):
                if n.name != exclude and n.name in self._locals:
                    out.add(n.name)
                return
            if isinstance(n, (list, tuple)):
                for x in n:
                    walk(x)
                return
            if isinstance(n, fast.ASTNode):
                for v in vars(n).values():
                    walk(v)
        walk(e)
        return out

    def _index_function(self, func):
        al = self._al
        def record(n, path, loops):
            seq = al.seq
            al.seq += 1
            al.ix[id(n)] = (seq, path, loops)
            al.uses.setdefault(n.name, []).append((seq, path, loops))

        def note_writer(target):
            r = self._root_ident(target)
            if r is not None:
                al.writers.add(r.name)

        def walk(n, path, loops):
            if n is None:
                return
            if isinstance(n, (list, tuple)):
                for x in n:
                    walk(x, path, loops)
                return
            if not isinstance(n, fast.ASTNode) or isinstance(n, fast.FunctionDef):
                return
            if isinstance(n, fast.Identifier):
                record(n, path, loops)
                return
            if isinstance(n, fast.IfStatement):
                walk(n.condition, path, loops)
                walk(n.then_block, path + ((id(n), 0),), loops)
                for i, (c, b) in enumerate(n.elif_blocks or []):
                    p2 = path + ((id(n), i + 1),)
                    walk(c, p2, loops)
                    walk(b, p2, loops)
                if n.else_block is not None:
                    walk(n.else_block, path + ((id(n), len(n.elif_blocks or []) + 1),), loops)
                return
            if isinstance(n, fast.SwitchStatement):
                walk(n.expression, path, loops)
                for i, c in enumerate(n.cases):
                    walk(c.value, path, loops)
                    walk(c.body, path + ((id(n), i),), loops)
                return
            if isinstance(n, (fast.WhileLoop, fast.DoWhileLoop, fast.DoLoop,
                              fast.ForLoop, fast.ForInLoop)):
                if isinstance(n, fast.ForLoop):
                    walk(n.init, path, loops)
                if isinstance(n, fast.ForInLoop):
                    walk(n.iterable, path, loops)
                lid = id(n)
                al.loop_start[lid] = al.seq
                l2 = loops + (lid,)
                if isinstance(n, fast.ForLoop):
                    walk(n.condition, path, l2)
                    walk(n.body, path, l2)
                    walk(n.update, path, l2)
                elif isinstance(n, fast.ForInLoop):
                    walk(n.body, path, l2)
                else:
                    walk(getattr(n, 'condition', None), path, l2)
                    walk(n.body, path, l2)
                al.loop_end[lid] = al.seq
                return
            if isinstance(n, fast.Assignment):
                walk(n.value, path, loops)
                if isinstance(n.target, fast.Identifier):
                    al.defs.setdefault(n.target.name, []).append((al.seq, path, loops))
                    al.seq += 1
                    return
                walk(n.target, path, loops)
                note_writer(n.target)
                return
            if isinstance(n, fast.CompoundAssignment):
                walk(n.value, path, loops)
                walk(n.target, path, loops)
                if not isinstance(n.target, fast.Identifier):
                    note_writer(n.target)
                return
            if (isinstance(n, fast.UnaryOp)
                    and getattr(n.operator, 'name', '') in ('INCREMENT', 'DECREMENT')):
                walk(n.operand, path, loops)
                if not isinstance(n.operand, fast.Identifier):
                    note_writer(n.operand)
                return
            if isinstance(n, fast.VariableDeclaration):
                walk(n.initial_value, path, loops)
                al.first[n.name] = al.seq
                al.defs.setdefault(n.name, []).append((al.seq, path, loops))
                al.seq += 1
                return
            for v in list(vars(n).values()):
                walk(v, path, loops)

        walk(func.body, (), ())

    @staticmethod
    def _exclusive(pa, pb):
        for ia, ba in pa:
            for ib, bb in pb:
                if ia == ib and ba != bb:
                    return True
        return False

    @staticmethod
    def _prefix(p, q):
        return len(p) <= len(q) and q[:len(p)] == p

    def _live_after(self, name, pos):
        """Will the value the variable holds at pos be used again?"""
        al = self._al
        seq, path, loops = pos
        defs = al.defs.get(name, ())
        # a definition that runs on every path from pos onward kills the value
        kill_after = [d for d in defs if d[0] > seq and self._prefix(d[1], path)]
        for (s, pth, lps) in al.uses.get(name, ()):
            if s > seq and not self._exclusive(pth, path):
                if not any(d[0] < s and self._prefix(d[1], pth) for d in kill_after):
                    return True
            for L in set(lps) & set(loops):
                if al.first.get(name, -1) >= al.loop_start.get(L, 0):
                    continue
                # carried around the loop: killed by a later definition at this
                # level, or by an earlier one in the iteration before the use
                end = al.loop_end.get(L, 1 << 30)
                if any(d[0] < end for d in kill_after if L in d[2]):
                    continue
                st_ = al.loop_start.get(L, 0)
                if any(st_ <= d[0] < s and self._prefix(d[1], pth) and L in d[2]
                       for d in defs):
                    continue
                return True
        return False

    def _ancestors(self, name):
        seen = set()
        todo = [name]
        d = self._al.deriv
        while todo:
            x = todo.pop()
            for y in d.get(x, ()):
                if y not in seen:
                    seen.add(y)
                    todo.append(y)
        return seen

    def _note_write(self, dr):
        for r in dr:
            if r[0] == 'param' and r[1] == self._fn:
                self._al.wr_params.add(r[2])

    def _alias_check(self, e, dr, st, is_write):
        if is_write:
            self._note_write(dr)
        rn = self._root_ident(e)
        if rn is None:
            return
        p = rn.name
        if p not in self._al.ptr_vars or frozenset(dr) != st.env.get(p, frozenset()):
            return
        pos = self._al.ix.get(id(rn))
        if pos is None:
            return
        self._alias_vs_live(p, pos, dr, is_write, st, ())

    def _alias_vs_live(self, p, pos, regs, is_write, st, skip):
        al = self._al
        anc = self._ancestors(p)
        for y, yregs in list(st.env.items()):
            if y == p or y in skip or y not in al.ptr_vars or not yregs:
                continue
            both = regs & yregs
            if not both:
                continue
            if y in anc:
                continue
            if not self._live_after(y, pos):
                continue
            if not (is_write or y in al.writers or p in al.writers):
                continue
            site = sorted(both, key=str)[0]
            self._report(
                'mutable_alias',
                f"pointer '{p}' is {'written' if is_write else 'read'} through while "
                f"pointer '{y}' to the same allocation '{self._rdesc(site)}' is still live "
                f"(many readers or one writer)",
                self._cur_line,
                [f"'{p}' accessed at {self._where(self._cur_line)}",
                 f"'{y}' is used again after this point"])

    def _arg_ident(self, a):
        while True:
            if isinstance(a, fast.Identifier):
                return a
            if isinstance(a, (fast.CastExpression, fast.AddressOf)):
                a = a.expression
            else:
                return None

    def _check_call_alias(self, args, arg_regs, wr, st):
        """Arguments that overlap while the callee may write through one."""
        al = self._al
        n = len(arg_regs)
        roots = [self._arg_ident(a) for a in args]
        def writes(i):
            return wr is None or i in wr
        names = set(r.name for r in roots if r is not None)
        for i in range(n):
            for j in range(i + 1, n):
                if roots[i] is None or roots[j] is None:
                    continue
                both = arg_regs[i] & arg_regs[j]
                if not both:
                    continue
                if not (writes(i) or writes(j)):
                    continue
                site = sorted(both, key=str)[0]
                self._report(
                    'mutable_alias',
                    f"arguments '{roots[i].name}' and '{roots[j].name}' alias the same "
                    f"allocation '{self._rdesc(site)}' and the callee may write through one "
                    f"of them (many readers or one writer)",
                    self._cur_line,
                    [f"call at {self._where(self._cur_line)}"])
        for i in range(n):
            r = roots[i]
            if r is None or isinstance(args[i], fast.AddressOf):
                continue
            if r.name not in al.ptr_vars or not arg_regs[i]:
                continue
            if frozenset(arg_regs[i]) != st.env.get(r.name, frozenset()):
                continue
            pos = al.ix.get(id(r))
            if pos is None:
                continue
            self._alias_vs_live(r.name, pos, arg_regs[i], writes(i), st, names)

    def _tie(self, e, st):
        """~x moves the value out of x: x holds null afterwards."""
        op = e.operand
        if not isinstance(op, fast.Identifier):
            return self._eval(op, st)
        info = self._locals.get(op.name)
        v = self._eval(op, st)
        if info is not None and info[0] == 'array':
            return v
        st.env[op.name] = frozenset()
        if info is not None:
            # a tied struct carries its contents with it
            self._mark_esc(self._load(frozenset([info[1]]), st), st)
        return v

    def _compound(self, node, st):
        t = node.target
        if not isinstance(t, fast.Identifier):
            cells, dr = self._cells_of(t, st)
            if dr:
                self._deref_check(dr, t, st)
                self._alias_check(t, dr, st, True)
            self._access(frozenset(self._root(c) for c in cells), A_R | A_W, st,
                         rng=self._acc_range(t, st))
        elif t.name in self._locals:
            st.terms.pop(t.name, None)
            self._access(frozenset([self._locals[t.name][1]]), A_R | A_W, st)
        else:
            self._access(frozenset([('static', t.name)]), A_R | A_W, st)
        v = self._eval(node.value, st)
        if isinstance(t, fast.Identifier) and t.name in self._locals:
            st.env[t.name] = st.env.get(t.name, frozenset()) | v

    def _store_cells(self, cells, v, st, check, node):
        if not v:
            return
        if check:
            self._escape_check(cells, v, st, node)
        for c in cells:
            st.held[c] = st.held[c] | v if c in st.held else v
        # a handed-off allocation is no longer the local pointer's to free
        self._mark_esc(v, st)

    def _mark_esc(self, v, st):
        for r in v:
            if r[0] == 'heap':
                st.esc.add(r)

    def _escape_check(self, cells, v, st, node):
        """R1: storing a pointer to a local into a longer-lived place."""
        locs = [r for r in v if r[0] == 'stack' and r[1] == self._fn]
        if not locs:
            return
        for c0 in cells:
            c = self._root(c0)
            outlives = (c[0] in ('param', 'heap', 'static') or
                        (c[0] == 'stack' and c[1] != self._fn))
            if not outlives:
                continue
            for r in locs:
                what = {'param': 'a parameter pointee', 'heap': 'a heap cell',
                        'static': 'a global'}.get(c[0], 'an outer cell')
                self._report(
                    'scope_escape',
                    f"pointer to local '{r[2]}' stored in {what} and outlives its stack allocation "
                    f"'{self._rdesc(r)}' (allocation scope exited)",
                    self._cur_line,
                    [f"stored at {self._where(self._cur_line)}"])

    # -- return -----------------------------------------------------------
    def _return(self, node, st):
        v = frozenset()
        if node.value is not None:
            v = self._eval(node.value, st)
        for r in v:
            if r[0] == 'stack' and r[1] == self._fn:
                self._report(
                    'scope_escape',
                    f"pointer to local '{r[2]}' returned and outlives its stack allocation "
                    f"'{self._rdesc(r)}' (allocation scope exited)",
                    self._cur_line,
                    [f"returned at {self._where(self._cur_line)}"])
        self._run_defers_all(st)
        self._exit(st, v, self._cur_line)
        self._returns.append((st.copy(), v))
        st.dead = True

    def _exit(self, st, ret, line):
        """R5: leak check at one exit path."""
        for r, stat in st.status.items():
            if r[0] != 'heap' or r in ret or r in st.esc:
                continue
            if stat == frozenset('O'):
                # only report allocations made by this function (not mapped callee sites
                # that were already reported there)
                o = self._origin(r)
                self._report(
                    'heap_leak',
                    f"heap allocation '{self._rdesc(r)}' has no reachable ffree on all paths",
                    r[2],
                    [f"allocated at {self._where(o[2])}",
                     f"never freed or handed off on the path ending at {self._where(line)}"])

    # -- control flow ---------------------------------------------------
    def _if(self, node, st):
        self._eval(node.condition, st)
        outs = []
        s1 = st.copy()
        self._block(node.then_block, s1)
        outs.append(s1)
        rest = st.copy()
        for cond, blk in (node.elif_blocks or []):
            self._eval(cond, rest)
            s = rest.copy()
            self._block(blk, s)
            outs.append(s)
        if node.else_block is not None:
            s = rest.copy()
            self._block(node.else_block, s)
            outs.append(s)
        else:
            outs.append(rest)
        res = None
        for o in outs:
            res = join(res, o)
        self._assign_state(st, res if res is not None else st)

    def _switch(self, node, st):
        self._eval(node.expression, st)
        outs = []
        has_default = False
        for c in node.cases:
            if c.value is None:
                has_default = True
            else:
                self._eval(c.value, st.copy())
            s = st.copy()
            if c.body is not None:
                if isinstance(c.body, fast.Block):
                    self._block(c.body, s)
                else:
                    self._stmt(c.body, s, FN)
            outs.append(s)
        if not has_default:
            outs.append(st.copy())
        res = None
        for o in outs:
            res = join(res, o)
        self._assign_state(st, res if res is not None else st)

    def _loop(self, st, cond, body, check_first, update=None, once=False):
        pat = self._loop_pattern(cond, body, update, st) if (check_first and not once) else None
        ctx = {'breaks': [], 'conts': []}
        entry = st.copy()
        cur = entry
        for _ in range(4):
            ctx['breaks'] = []
            ctx['conts'] = []
            self._loops.append(ctx)
            s = cur.copy()
            if cond is not None and check_first:
                self._eval(cond, s)
            if pat is not None:
                prev_iv = self._ivars.get(pat[0])
                self._ivars[pat[0]] = (pat[1], pat[2])
            self._block(body, s)
            if pat is not None:
                if prev_iv is None:
                    self._ivars.pop(pat[0], None)
                else:
                    self._ivars[pat[0]] = prev_iv
            self._loops.pop()
            back = s
            for cs in ctx['conts']:
                back = join(back, cs)
            if update is not None and not back.dead:
                self._stmt(update, back, FN)
            if cond is not None and not check_first and not back.dead:
                self._eval(cond, back)
            nxt = join(entry, back) if not once else entry
            if nxt.key() == cur.key():
                break
            cur = nxt
        # exit state: loop condition false at the head, or break
        if once:
            out = back
        elif check_first:
            out = cur.copy()
            if cond is not None:
                self._eval(cond, out)
        else:
            out = back if not back.dead else cur
        for b in ctx['breaks']:
            out = join(out, b)
        if pat is not None:
            out.terms.pop(pat[0], None)
        self._assign_state(st, out)

    # ------------------------------------------------------------------
    # expressions
    # ------------------------------------------------------------------
    @staticmethod
    def _root(c):
        while c[0] == 'fld':
            c = c[1]
        return c

    def _load(self, cells, st):
        out = frozenset()
        for c in cells:
            if c in st.held:
                out = out | st.held[c]
        return out

    def _loc_info(self, name):
        return self._locals.get(name)

    def _cells_of(self, e, st):
        """Cells an lvalue-like expression addresses, plus the set of regions that
        are dereferenced to reach them (empty when no pointer is followed)."""
        E = frozenset()
        if isinstance(e, fast.Identifier):
            info = self._loc_info(e.name)
            if info is None:
                return frozenset([('static', e.name)]), E
            kind, reg = info
            if kind == 'array':
                return frozenset([reg]), E
            vals = st.env.get(e.name, E)
            if vals:
                return vals, vals
            return frozenset([reg]), E
        if isinstance(e, (fast.MemberAccess, fast.ArrayAccess)):
            is_m = isinstance(e, fast.MemberAccess)
            base = e.object if is_m else e.array
            if not is_m:
                self._eval(e.index, st)
            if isinstance(base, fast.Identifier):
                bc, dr = self._cells_of(base, st)
                if base.name in self._locals and self._locals[base.name][0] != 'array':
                    # plain variable: pointer when it holds regions, value otherwise
                    pass
            else:
                inner, dr0 = self._cells_of(base, st)
                loaded = self._load(inner, st)
                if loaded:
                    bc, dr = loaded, loaded
                else:
                    bc, dr = inner, E
                    dr = dr0 if False else E
            if is_m:
                return frozenset(('fld', c, e.member) for c in bc), dr
            return bc, dr
        if isinstance(e, fast.PointerDeref):
            v = self._eval(e.pointer, st)
            return v, v
        v = self._eval(e, st)
        return v, v

    def _deref_check(self, regs, node, st):
        name = self._hint(node)
        hp = [r for r in regs if r[0] in ('heap', 'param') and r not in self.multi]
        allf = bool(hp) and all('F' in (st.status.get(r) or ()) for r in hp)
        for r in regs:
            k = r[0]
            if k in ('heap', 'param'):
                if not allf or r not in hp:
                    continue
                stat = st.status.get(r)
                if stat and 'F' in stat:
                    when = st.free_at.get(r)
                    det = [f"ffree called at {self._where(when)}"] if when else []
                    if (stat - frozenset('W')) == frozenset('F'):
                        self._report(
                            'use_after_free',
                            f"pointer '{name}' used after its allocation site "
                            f"'{self._rdesc(r)}' was passed to ffree",
                            self._cur_line, det)
                    else:
                        self._report(
                            'maybe_use_after_free',
                            f"pointer '{name}' used but its allocation site "
                            f"'{self._rdesc(r)}' may already have been passed to ffree",
                            self._cur_line, det)
            elif k == 'stack':
                if r[3] not in st.active:
                    self._report(
                        'use_after_scope',
                        f"pointer '{name}' used after its stack allocation "
                        f"'{self._rdesc(r)}' went out of scope",
                        self._cur_line)
            elif k == 'dangling':
                self._report(
                    'use_after_scope',
                    f"pointer '{name}' used after the stack allocation "
                    f"'{self._rdesc(r)}' it points to was returned from a callee",
                    self._cur_line)

    def _hint(self, e):
        while True:
            if isinstance(e, fast.Identifier):
                return e.name
            if isinstance(e, fast.PointerDeref):
                e = e.pointer
            elif isinstance(e, fast.MemberAccess):
                e = e.object
            elif isinstance(e, fast.ArrayAccess):
                e = e.array
            elif isinstance(e, (fast.CastExpression, fast.AddressOf)):
                e = e.expression
            else:
                return '<expr>'

    def _eval(self, e, st):
        if e is None:
            return frozenset()
        ln = getattr(e, 'source_line', 0)
        if ln:
            self._cur_line = ln

        if isinstance(e, fast.Literal):
            return frozenset()
        if isinstance(e, fast.Assignment):
            self._assign(e.target, e.value, st)
            return self._eval(e.target, st) if isinstance(e.target, fast.Identifier) else frozenset()
        if isinstance(e, fast.CompoundAssignment):
            self._compound(e, st)
            return frozenset()
        if isinstance(e, fast.Identifier):
            self._join_result(e.name, st)
            info = self._loc_info(e.name)
            if info is None:
                self._access(frozenset([('static', e.name)]), A_R, st)
                return self._load(frozenset([('static', e.name)]), st)
            kind, reg = info
            if kind == 'array':
                return frozenset([reg])
            self._access(frozenset([reg]), A_R, st)
            return st.env.get(e.name, frozenset())
        if isinstance(e, fast.AddressOf):
            return self._addr_of(e.expression, st)
        if isinstance(e, (fast.PointerDeref, fast.ArrayAccess, fast.MemberAccess)):
            cells, dr = self._cells_of(e, st)
            if dr:
                self._deref_check(dr, e, st)
                self._alias_check(e, dr, st, False)
            self._access(frozenset(self._root(c) for c in cells), A_R, st,
                         rng=self._acc_range(e, st))
            return self._load(cells, st)
        if isinstance(e, fast.CastExpression):
            ts = e.target_type
            if (isinstance(e.expression, fast.TieExpression)
                    and getattr(ts, 'base_type', None) is not None
                    and getattr(ts.base_type, 'name', '') == 'VOID'
                    and not getattr(ts, 'is_pointer', False)):
                # (void)~x releases the tied value
                self._do_free(self._eval(e.expression, st), st, definite=True)
                return frozenset()
            return self._eval(e.expression, st)
        if isinstance(e, fast.BinaryOp):
            l = self._eval(e.left, st)
            r = self._eval(e.right, st)
            op = getattr(e.operator, 'name', str(e.operator))
            if op in self._NON_VALUE_OPS:
                return frozenset()
            return l | r
        if (isinstance(e, fast.UnaryOp)
                and getattr(e.operator, 'name', '') in ('INCREMENT', 'DECREMENT')
                and isinstance(e.operand, (fast.PointerDeref, fast.ArrayAccess,
                                           fast.MemberAccess))):
            cells, dr = self._cells_of(e.operand, st)
            if dr:
                self._deref_check(dr, e.operand, st)
                self._alias_check(e.operand, dr, st, True)
            self._access(frozenset(self._root(c) for c in cells), A_R | A_W, st,
                         rng=self._acc_range(e.operand, st))
            return self._load(cells, st)
        if isinstance(e, fast.UnaryOp):
            v = self._eval(e.operand, st)
            if (getattr(e.operator, 'name', '') in ('INCREMENT', 'DECREMENT')
                    and isinstance(e.operand, fast.Identifier)):
                st.terms.pop(e.operand.name, None)
            if getattr(e.operator, 'name', '') == 'NOT':
                return frozenset()
            return v
        if isinstance(e, fast.TieExpression):
            return self._tie(e, st)
        if isinstance(e, fast.TypeConvertExpression):
            return self._eval(e.expression, st)
        if isinstance(e, fast.NullCoalesce):
            return self._eval(e.left, st) | self._eval(e.right, st)
        if isinstance(e, fast.NotNull):
            self._eval(e.operand, st)
            return frozenset()
        if isinstance(e, fast.TernaryOp):
            self._eval(e.condition, st)
            return self._eval(e.true_expr, st) | self._eval(e.false_expr, st)
        if isinstance(e, fast.IfExpression):
            self._eval(e.condition, st)
            v = self._eval(e.value_expr, st)
            if e.else_expr is not None and not isinstance(e.else_expr, str):
                v = v | self._eval(e.else_expr, st)
            return v
        if isinstance(e, fast.FunctionCall):
            return self._call(e, st)
        if isinstance(e, fast.MethodCall):
            return self._method(e, st)
        # generic expression: evaluate children for their effects
        if hasattr(e, '__dict__'):
            out = frozenset()
            for v in list(vars(e).values()):
                if isinstance(v, fast.ASTNode):
                    out = out | self._eval(v, st)
                elif isinstance(v, (list, tuple)):
                    for x in v:
                        if isinstance(x, fast.ASTNode):
                            out = out | self._eval(x, st)
            return frozenset() if not isinstance(e, fast.Expression) else frozenset()
        return frozenset()

    def _addr_of(self, e, st):
        if isinstance(e, fast.Identifier):
            info = self._loc_info(e.name)
            if info is None:
                return frozenset([('static', e.name)])
            return frozenset([info[1]])
        if isinstance(e, (fast.MemberAccess, fast.ArrayAccess)):
            cells, dr = self._cells_of(e, st)
            return frozenset(self._root(c) for c in cells)
        if isinstance(e, fast.PointerDeref):
            return self._eval(e.pointer, st)
        return self._eval(e, st)

    # ------------------------------------------------------------------
    # async: footprints, relations and the task solver
    # ------------------------------------------------------------------
    def _is_async(self, fname):
        if fname in self.cg.async_names:
            return True
        fd = self.cg.funcs.get(fname)
        return bool(fd is not None and getattr(fd, 'is_async', False))

    def _merge_fp(self, d, key, bits, atomic, rng=None):
        lst = d.setdefault(key, [])
        t = (bits, atomic, rng)
        if t in lst:
            return
        lst.append(t)
        if len(lst) > 8:
            b = 0
            at = True
            for x in lst:
                b |= x[0]
                at = at and x[1]
            d[key] = [(b, at, None)]

    def _fp_key(self, r):
        r = self._root(r)
        if r[0] == 'param' and r[1] == self._fn:
            return ('p', r[2])
        if r[0] == 'static':
            return ('g', r[1])
        return None

    def _merge_fp_roots(self, tfp):
        """Fold a task footprint (caller regions) into this function's own footprint."""
        for r, lst in tfp.items():
            key = self._fp_key(r)
            if key is not None:
                for (b, at, rng) in lst:
                    self._merge_fp(self._fp, key, b, at, rng)

    @staticmethod
    def _fp_conflict(la, lb):
        for a in la:
            for b in lb:
                if _modes_conflict(a, b) and _ranges_overlap(a[2], b[2]):
                    return a, b
        return None

    # -- index terms and ranges -------------------------------------------
    def _term_of(self, e, st):
        """e as param + constant, or None."""
        if isinstance(e, fast.Literal):
            v = e.value
            if isinstance(v, bool):
                return None
            if isinstance(v, int):
                return (-1, v)
            try:
                return (-1, int(str(v)))
            except ValueError:
                return None
        if isinstance(e, fast.Identifier):
            return st.terms.get(e.name)
        if isinstance(e, fast.CastExpression):
            return self._term_of(e.expression, st)
        if isinstance(e, fast.BinaryOp):
            op = getattr(e.operator, 'name', '')
            if op in ('ADD', 'SUB'):
                l = self._term_of(e.left, st)
                r = self._term_of(e.right, st)
                if l is None or r is None:
                    return None
                if r[0] == -1:
                    return (l[0], l[1] + (r[1] if op == 'ADD' else -r[1]))
                if op == 'ADD' and l[0] == -1:
                    return (r[0], r[1] + l[1])
        return None

    def _mentions_ivar(self, e):
        names = set()
        self._idents_in(e, names)
        return any(n in self._ivars for n in names)

    def _index_range(self, idx, st):
        if isinstance(idx, fast.Identifier) and idx.name in self._ivars:
            return self._ivars[idx.name]
        if isinstance(idx, fast.CastExpression):
            return self._index_range(idx.expression, st)
        if isinstance(idx, fast.BinaryOp) and getattr(idx.operator, 'name', '') in ('ADD', 'SUB'):
            op = idx.operator.name
            for var_side, const_side, ok in ((idx.left, idx.right, True),
                                              (idx.right, idx.left, op == 'ADD')):
                if not ok:
                    continue
                r = self._index_range(var_side, st) if self._mentions_ivar(var_side) else None
                if r is None:
                    continue
                if self._mentions_ivar(const_side):
                    continue
                c = self._term_of(const_side, st)
                if c is not None and c[0] == -1:
                    d = c[1] if op == 'ADD' else -c[1]
                    lo, hi = r
                    return ((lo[0], lo[1] + d), (hi[0], hi[1] + d))
        if self._mentions_ivar(idx):
            # Any other use of a loop variable has no tracked range; the value it
            # held on entry to the loop is not its value in the body.
            return None
        t = self._term_of(idx, st)
        if t is not None:
            return (t, (t[0], t[1] + 1))
        return None

    def _acc_range(self, e, st):
        """Element range of an lvalue expression, in the pointee's element units."""
        via_member = False
        while isinstance(e, fast.MemberAccess):
            e = e.object
            via_member = True
        if isinstance(e, fast.ArrayAccess):
            if isinstance(e.array, fast.Identifier):
                return self._index_range(e.index, st)
            return None
        if isinstance(e, fast.PointerDeref):
            return ((-1, 0), (-1, 1))
        if isinstance(e, fast.Identifier) and via_member:
            return ((-1, 0), (-1, 1))
        return None

    def _count_mods(self, node, name):
        n = 0
        if isinstance(node, fast.Assignment) and isinstance(node.target, fast.Identifier) \
                and node.target.name == name:
            n += 1
        elif isinstance(node, fast.CompoundAssignment) and isinstance(node.target, fast.Identifier) \
                and node.target.name == name:
            n += 1
        elif isinstance(node, fast.UnaryOp) and getattr(node.operator, 'name', '') in \
                ('INCREMENT', 'DECREMENT') and isinstance(node.operand, fast.Identifier) \
                and node.operand.name == name:
            n += 1
        elif isinstance(node, fast.VariableDeclaration) and node.name == name:
            n += 1
        if hasattr(node, '__dict__'):
            for v in list(vars(node).values()):
                if isinstance(v, fast.ASTNode):
                    n += self._count_mods(v, name)
                elif isinstance(v, (list, tuple)):
                    for x in v:
                        if isinstance(x, fast.ASTNode):
                            n += self._count_mods(x, name)
        return n

    def _idents_in(self, e, out):
        if isinstance(e, fast.Identifier):
            out.add(e.name)
        elif hasattr(e, '__dict__'):
            for v in list(vars(e).values()):
                if isinstance(v, fast.ASTNode):
                    self._idents_in(v, out)
        return out

    @staticmethod
    def _is_inc(stmt, name):
        s = stmt.expression if isinstance(stmt, fast.ExpressionStatement) else stmt
        if isinstance(s, fast.UnaryOp):
            return (getattr(s.operator, 'name', '') == 'INCREMENT'
                    and isinstance(s.operand, fast.Identifier) and s.operand.name == name)
        if isinstance(s, fast.CompoundAssignment):
            tn = getattr(s.op_token, 'name', str(s.op_token))
            return (isinstance(s.target, fast.Identifier) and s.target.name == name
                    and ('PLUS' in tn or 'ADD' in tn)
                    and isinstance(s.value, fast.Literal) and s.value.value in (1, '1'))
        if isinstance(s, fast.Assignment):
            v = s.value
            return (isinstance(s.target, fast.Identifier) and s.target.name == name
                    and isinstance(v, fast.BinaryOp) and getattr(v.operator, 'name', '') == 'ADD'
                    and isinstance(v.left, fast.Identifier) and v.left.name == name
                    and isinstance(v.right, fast.Literal) and v.right.value in (1, '1'))
        return False

    def _loop_pattern(self, cond, body, update, st):
        """Counting loop: i starts at a known term, steps by one at the end of every
        iteration, and runs while i < bound (bound unchanged by the loop)."""
        if not isinstance(cond, fast.BinaryOp):
            return None
        op = getattr(cond.operator, 'name', '')
        if op not in ('LESS_THAN', 'LESS_EQUAL') or not isinstance(cond.left, fast.Identifier):
            return None
        name = cond.left.name
        lo = st.terms.get(name)
        hi = self._term_of(cond.right, st)
        if lo is None or hi is None:
            return None
        if op == 'LESS_EQUAL':
            hi = (hi[0], hi[1] + 1)
        for b in self._idents_in(cond.right, set()):
            if self._count_mods(body, b) or (update is not None and self._count_mods(update, b)):
                return None
        mods = self._count_mods(body, name)
        stmts = body.statements if body is not None else []
        if update is not None:
            if mods != 0 or not self._is_inc(update, name):
                return None
        else:
            if mods != 1 or not stmts or not self._is_inc(stmts[-1], name):
                return None
        return name, lo, hi

    def _fmt_rng(self, rng):
        if rng is None:
            return "[whole object]"
        fn = self.cg.funcs.get(self._fn)
        def t(x):
            if x[0] == -1:
                return str(x[1])
            pn = None
            if fn is not None and x[0] < len(fn.parameters or []):
                pn = fn.parameters[x[0]].name
            pn = pn or f"arg{x[0]}"
            return pn if x[1] == 0 else f"{pn}{x[1]:+d}"
        return f"[{t(rng[0])}, {t(rng[1])})"

    def _translate_fp(self, summ, fname, arg_regs, args, st):
        """Callee footprint in caller terms: root region -> [(bits, atomic, range)]."""
        out = {}
        aterms = [self._term_of(a, st) for a in args]
        def subst(t):
            if t[0] == -1:
                return t
            j = t[0]
            if j >= len(aterms) or aterms[j] is None:
                return None
            at = aterms[j]
            return (at[0], at[1] + t[1])
        def subst_rng(rng):
            if rng is None:
                return None
            lo = subst(rng[0])
            hi = subst(rng[1])
            if lo is None or hi is None:
                return None
            return (lo, hi)
        for key, lst in (summ.fp or {}).items():
            if key[0] == 'p':
                i = key[1]
                regs = arg_regs[i] if i < len(arg_regs) else frozenset()
                off0 = i < len(args) and self._offset_zero(args[i])
            else:
                regs = frozenset([('static', key[1])])
                off0 = True
            for r in regs:
                for (b, at, rng) in lst:
                    rr = subst_rng(rng) if off0 else None
                    self._merge_fp(out, self._root(r), b, at, rr)
        return out

    def _offset_zero(self, a):
        """The argument points at element 0 of the object it names."""
        while isinstance(a, fast.CastExpression):
            a = a.expression
        if isinstance(a, fast.Identifier):
            return True
        if isinstance(a, fast.AddressOf):
            x = a.expression
            if isinstance(x, fast.Identifier):
                return True
            if isinstance(x, fast.ArrayAccess):
                if isinstance(x.index, fast.Literal) and x.index.value in (0, '0'):
                    return isinstance(x.array, fast.Identifier)
            return False
        return False

    def _access(self, regs, bits, st, atomic=False, what=None, rng=None):
        """The current function touches these regions: record the footprint and
        check the access against every async task that may still be running."""
        if not regs or self._no_access:
            return
        for r in regs:
            key = self._fp_key(r)
            if key is not None:
                self._merge_fp(self._fp, key, bits, atomic, rng)
        if not st.tasks:
            return
        mine = [(bits, atomic, rng)]
        for t in list(st.tasks.values()):
            for r in regs:
                tl = t.fp.get(self._root(r))
                if tl is None:
                    continue
                hit = self._fp_conflict(mine, tl)
                if hit is None:
                    continue
                self.async_seq.add(id(t.node))
                kind = what or {A_R: 'read', A_W: 'write', A_F: 'free'}.get(bits, 'access')
                self._report(
                    'async_conflict',
                    f"{kind} of '{self._rdesc(r)}' conflicts with async call "
                    f"'{t.fn.split('__')[-1]}' still running ({_mode_name(hit[0])} "
                    f"{self._fmt_rng(hit[0][2])} vs {_mode_name(hit[1])} "
                    f"{self._fmt_rng(hit[1][2])}); the call has no relation to this code"
                    f"{self._outcome(t.fn)}",
                    self._cur_line,
                    [f"async call launched at {self._where(t.line)}",
                     "use the call's result, or relate the two with an async tag, to order them"])

    def _outcome(self, fn):
        """What happens to the call: downgraded in warn mode, rejected otherwise."""
        short = fn.split('__')[-1]
        if self.warn_mode:
            return f"; '{short}' runs sequentially"
        return f"; '{short}' cannot be proven safe to run concurrently"

    def _check_launch(self, task, st):
        """A new async call against the tasks already running. Declared relations
        are claims: '!' and '>' are enforced by the compiler, '#' and '~' must
        agree with the derived footprints or the program is rejected."""
        for u in list(st.tasks.values()):
            hit = None
            for r, lst in task.fp.items():
                ul = u.fp.get(r)
                if ul is None:
                    continue
                h = self._fp_conflict(lst, ul)
                if h is not None:
                    hit = (r, h)
                    break
            if hit is None:
                continue
            r, (ma, mb) = hit
            ops = self.rel.get((task.fn, u.fn), set())
            if ops & {'!', '>', '<'}:
                continue
            self.async_seq.add(id(task.node))
            a = task.fn.split('__')[-1]
            b = u.fn.split('__')[-1]
            what = (f"'{self._rdesc(r)}' ({_mode_name(ma)} {self._fmt_rng(ma[2])} vs "
                    f"{_mode_name(mb)} {self._fmt_rng(mb[2])})")
            det = [f"first call launched at {self._where(u.line)}"]
            if '#' in ops:
                self._report(
                    'async_contradiction',
                    f"relation '#' between '{a}' and '{b}' is contradicted by the code: "
                    f"both reach {what}",
                    self._cur_line, det + ["the derived footprint is the truth, the tag claim is wrong"])
            elif '~' in ops:
                self._report(
                    'async_contradiction',
                    f"relation '~' between '{a}' and '{b}' is contradicted by the code: "
                    f"the accesses to {what} are not all atomic",
                    self._cur_line, det + ["the derived footprint is the truth, the tag claim is wrong"])
            else:
                self._report(
                    'async_conflict',
                    f"async calls '{a}' and '{b}' both reach {what} and no relation "
                    f"orders or separates them{self._outcome(task.fn)}",
                    self._cur_line,
                    det + ["declare #<Tag>(...) with ! or > between them if that is intended"])

    def _apply_quiet(self, fname, arg_regs, st):
        """Apply a callee summary; its accesses are already covered by the
        translated footprint, so they are not recorded or checked twice."""
        prev = self._no_access
        self._no_access = True
        try:
            return self._apply(fname, arg_regs, st)
        finally:
            self._no_access = prev

    def _join_result(self, name, st):
        """First use of an async call's result waits for it."""
        if not st.tasks:
            return
        for tid in [k for k, t in st.tasks.items() if t.result_var == name]:
            del st.tasks[tid]

    # -- relations --------------------------------------------------------
    def _resolve_target(self, tgt, carrier):
        if tgt.name == 'this':
            return [carrier]
        name = tgt.name
        cands = []
        if name in self.cg.funcs:
            cands = [name]
        else:
            cands = list(self.cg.overloads.get(name, []))
            if not cands and name in self.cg.short_names:
                cands = [self.cg.short_names[name]]
            if not cands:
                cands = sorted(k for k in self.cg.async_names
                               if k == name or k.endswith('__' + name))
        if tgt.param_types is not None:
            want = [repr(t) for t in tgt.param_types]
            keep = []
            for c in cands:
                fd = self.cg.funcs.get(c)
                if fd is None:
                    continue
                have = [repr(p.type_spec) for p in (fd.parameters or [])]
                if have == want:
                    keep.append(c)
            cands = keep
        return cands

    def _build_relations(self):
        """rel[(a, b)] is the set of operators declared between async functions a and b."""
        rel = {}
        def add(a, b, op):
            rel.setdefault((a, b), set()).add(op)
        flip = {'>': '<'}
        for carrier, fd, use in self.cg.async_uses:
            tag = self.cg.async_tags.get(use.tag)
            if tag is None or len(use.targets) != len(tag.params):
                continue
            bind = {p: self._resolve_target(t, carrier)
                    for p, t in zip(tag.params, use.targets)}
            for rr in tag.relations:
                for k, op in enumerate(rr.ops):
                    for a in bind.get(rr.operands[k], []):
                        for b in bind.get(rr.operands[k + 1], []):
                            add(a, b, op)
                            add(b, a, flip.get(op, op))
        self.rel = rel

    def _rel_allows(self, a, b):
        return bool(self.rel.get((a, b)))

    # -- calls ------------------------------------------------------------
    def _call(self, e, st):
        name = e.name if isinstance(e.name, str) else None
        args = list(e.arguments or [])
        if name is None and e.name is not None:
            self._eval(e.name, st)
        base = (name or '').split('__')[-1]

        if base == 'frealloc' and len(args) >= 1:
            old = self._eval(args[0], st)
            for a in args[1:]:
                self._eval(a, st)
            self._mark_esc(old, st)
            site = ('heap', self._fn, self._cur_line)
            st.status[site] = frozenset('O')
            st.esc.discard(site)
            st.free_at.pop(site, None)
            return frozenset([site])
        if base == 'fmalloc' or base == 'fcalloc':
            for a in args:
                self._eval(a, st)
            site = ('heap', self._fn, self._cur_line)
            st.status[site] = frozenset('O')
            st.esc.discard(site)
            st.free_at.pop(site, None)
            return frozenset([site])
        if base == 'ffree' and len(args) == 1:
            v = self._eval(args[0], st)
            self._do_free(v, st, definite=True)
            return frozenset()

        arg_regs = [self._eval(a, st) for a in args]
        resolved = self._resolve(name, len(args)) if name else None
        if resolved is None:
            self._check_call_alias(args, arg_regs, None, st)
            for v in arg_regs:
                self._mark_esc(v, st)
            return frozenset()
        summ = self._summary(resolved)
        self._check_call_alias(args, arg_regs, summ.wr, st)
        launch = (self._is_async(resolved) and e is self._async_node)
        self._async_node = None
        if self._is_async(resolved):
            self.async_target[id(e)] = resolved
        if self._is_async(resolved) and st.tasks:
            # a task the callee is declared to follow ('>') must finish first
            for tid, u in list(st.tasks.items()):
                if '>' in self.rel.get((u.fn, resolved), ()):
                    self.async_waits.setdefault(id(e), [])
                    if id(u.node) not in self.async_waits[id(e)]:
                        self.async_waits[id(e)].append(id(u.node))
                    del st.tasks[tid]
        if resolved.startswith(_ATOMIC_NS):
            # the atomic primitives are atomic by definition: every pointer they
            # are given is read and written atomically
            for v in arg_regs:
                if v:
                    self._access(frozenset(self._root(r) for r in v), A_R | A_W, st,
                                 atomic=True)
            return self._apply_quiet(resolved, arg_regs, st)
        tfp = self._translate_fp(summ, resolved, arg_regs, args, st)
        if launch:
            task = _Task(resolved, tfp, self._cur_line,
                         st.active[-1] if st.active else FN, e)
            self.async_launched.add(id(e))
            self._check_launch(task, st)
            self._merge_fp_roots(tfp)
            ret = self._apply_quiet(resolved, arg_regs, st)
            st.tasks[id(e)] = task
            self._last_task = task
            return ret
        for r, lst in tfp.items():
            for (b, at, rng) in lst:
                self._access(frozenset([r]), b, st, atomic=at, rng=rng,
                             what=f"call to '{resolved.split('__')[-1]}'")
        return self._apply_quiet(resolved, arg_regs, st)

    def _method(self, e, st):
        obj = self._eval(e.object, st)
        arg_regs = [self._eval(a, st) for a in (e.arguments or [])]
        self._mark_esc(obj, st)
        for v in arg_regs:
            self._mark_esc(v, st)
        return frozenset()

    def _do_free(self, regs, st, definite):
        single = len(regs) == 1
        hp = [r for r in regs if r[0] in ('heap', 'param') and r not in self.multi]
        allf = bool(hp) and all('F' in (st.status.get(r) or ()) for r in hp)
        self._access(frozenset(self._root(r) for r in regs if r[0] in ('heap', 'param')),
                     A_F, st)
        for r in regs:
            k = r[0]
            if k in ('heap', 'param'):
                if r in self.multi:
                    continue
                stat = st.status.get(r)
                if k == 'param' and stat is None:
                    stat = frozenset('O')
                if stat is not None and 'F' in stat and allf:
                    when = st.free_at.get(r)
                    det = [f"first ffree at {self._where(when)}"] if when else []
                    self._report(
                        'double_free',
                        f"allocation site '{self._rdesc(r)}' passed to ffree again"
                        + ("" if (stat - frozenset('W')) == frozenset('F') else " (it may already have been freed)"),
                        self._cur_line, det)
                if definite and single:
                    st.status[r] = frozenset('F')
                elif single:
                    st.status[r] = (stat or frozenset()) | frozenset('F')
                else:
                    # freed through a pointer that may point elsewhere: it may be
                    # freed, which neither proves nor excludes a later free or use
                    st.status[r] = (stat or frozenset()) | frozenset('W')
                    continue
                st.free_at[r] = self._cur_line
            elif k in ('stack', 'dangling'):
                self._report(
                    'invalid_free',
                    f"ffree called on stack address '{self._rdesc(r)}'",
                    self._cur_line)
            elif k == 'static':
                self._report(
                    'invalid_free',
                    f"ffree called on static address '{r[1]}'",
                    self._cur_line)

    def _apply(self, fname, arg_regs, st):
        summ = self._summary(fname)
        call_line = self._cur_line
        cache = {}

        def m(r):
            if r in cache:
                return cache[r]
            if r[0] == 'param':
                i = r[2]
                out = arg_regs[i] if i < len(arg_regs) and r[1] == fname else frozenset()
            elif r[0] == 'heap':
                ns = ('heap', self._fn, call_line, r)
                stat = summ.heap_status.get(r)
                if stat is not None:
                    st.status[ns] = stat
                    if r in (summ.esc or ()):
                        st.esc.add(ns)
                    if r in summ.free_at:
                        st.free_at[ns] = summ.free_at[r]
                out = frozenset([ns])
            elif r[0] == 'stack':
                out = frozenset([('dangling', r[1], r[2])])
            else:
                out = frozenset([r])
            cache[r] = out
            return out

        def mset(s):
            o = frozenset()
            for r in s:
                o = o | m(r)
            return o

        # writes through parameters the caller passed on
        for i in (summ.wr or ()):
            if i < len(arg_regs):
                self._note_write(arg_regs[i])
        # frees performed by the callee on pointer parameters
        for i, stat in (summ.param_status or {}).items():
            if 'F' in stat and i < len(arg_regs):
                self._do_free_mapped(arg_regs[i], st, stat == frozenset('F'),
                                     summ.free_at.get(('param', fname, i)), call_line)
        # stores into parameter pointees
        for i, items in (summ.param_held or {}).items():
            if i < len(arg_regs):
                for path, held in items:
                    mapped = mset(held)
                    for c in arg_regs[i]:
                        for m_ in path:
                            c = ('fld', c, m_)
                        st.held[c] = st.held[c] | mapped if c in st.held else mapped
                    self._mark_esc(mapped, st)
        return mset(summ.ret)

    def _do_free_mapped(self, regs, st, definite, when, call_line):
        saved = self._cur_line
        self._cur_line = call_line
        self._do_free(regs, st, definite)
        self._cur_line = saved


def main():
    parser = argparse.ArgumentParser(
        description='Flux Borrow Checker -- static pointer safety analysis'
    )
    parser.add_argument('target', help='File or directory to check')
    parser.add_argument('--entry',    default='FRTStartup',
                        help='Entry point function name (default: FRTStartup)')
    parser.add_argument('--warn',     action='store_true',
                        help='Treat violations as warnings instead of errors')
    parser.add_argument('--threads',  action='store_true',
                        help='Check thread safety (pointer escape across spawns)')
    parser.add_argument('--leaks',    action='store_true',
                        help='Check for heap leaks (unmatched fmalloc/ffree)')
    parser.add_argument('--json',     action='store_true',
                        help='Machine-readable JSON output')
    parser.add_argument('--no-color', action='store_true',
                        help='Disable ANSI color output')
    args = parser.parse_args()

    use_color = not args.no_color and sys.stderr.isatty()

    # --- collect and parse files ---
    fx_files = collect_fx_files(args.target)
    if not fx_files:
        print(f"[FBC] No .fx files found in: {args.target}")
        sys.exit(2)

    if not args.json:
        print(f"[FBC] Checking {len(fx_files)} file(s), entry: {args.entry}")

    programs = []
    line_maps = []
    parse_errors = []
    for fx in fx_files:
        try:
            prog, line_map = parse_file(fx)
            programs.append((fx, prog))
            line_maps.append(line_map)
        except Exception as e:
            parse_errors.append((fx, str(e)))
            if not args.json:
                print(f"[FBC] Parse error in {fx}: {e}", file=sys.stderr)

    if not programs:
        print("[FBC] No files could be parsed.")
        sys.exit(2)

    # merge line maps -- since we parse one file at a time (preprocessor merges imports)
    # we only have one line_map per input file
    combined_line_map = line_maps[0] if line_maps else []

    # --- build call graph ---
    cg = CallGraph()
    for fx, prog in programs:
        cg.collect(prog)

    if not args.json:
        print(f"[FBC] {len(cg.funcs)} function(s) found")

    # --- run borrow checker ---
    checker = BorrowChecker(
        call_graph=cg,
        entry=args.entry,
        check_threads=args.threads,
        check_leaks=args.leaks,
        line_map=combined_line_map,
        warn_mode=args.warn,
    )
    checker.run()

    all_violations = checker.violations

    # --- report ---
    mode = 'warn' if args.warn else 'error'
    print_violations(all_violations, mode=mode, use_color=use_color,
                     json_out=args.json)
    print_summary(all_violations, files_checked=len(fx_files),
                  funcs_checked=checker.funcs_checked,
                  use_color=use_color, json_out=args.json)

    if all_violations and not args.warn:
        sys.exit(1)
    sys.exit(0)


if __name__ == '__main__':
    main()