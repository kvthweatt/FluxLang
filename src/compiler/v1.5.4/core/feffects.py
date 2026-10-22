#!/usr/bin/env python3
"""
Flux Effect System -- feffects.py

Copyright (C) 2026 Karac V. Thweatt

Compile-time effect propagation, conflict resolution, and boundary enforcement.
Zero runtime cost -- effects are erased before codegen. Only two annotation
points: origin (# effect {}) on a function, and boundary (# attenuate {}) on
an interface.

Operator semantics (inside effect {} blocks and qualifiers only):
    *X      implies X, propagates upward through call chain
    ~X      requires X to be present
    !X      excludes X, cannot coexist
    ?X      weak propagation, can be suppressed
    @X      attenuatable at a boundary
    !@X     cannot be attenuated -- permanent in binary
    X -> Y  if X present then Y must be present
    X ^| Y  exactly one of X or Y
    X > Y   X takes priority over Y at conflict boundaries
    X <-> Y mutual implication -- both or neither
    ..X     propagates exactly one level up, stops
    ...X    propagates indefinitely (default)
    ^X      suppresses X even if something else implies it  (operator: ^suppress)
    &       both must hold
    |       at least one must hold
"""

from __future__ import annotations
from typing import Dict, List, Optional, Set, Tuple
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Effect set -- a resolved set of effect names with their operator flags
# ---------------------------------------------------------------------------

@dataclass
class EffectEntry:
    name: str
    implies: bool = False      # *X
    requires: bool = False     # ~X
    excludes: bool = False     # !X
    weak: bool = False         # ?X
    attenuatable: bool = True  # @X -- default; False means !@ (permanent)
    one_level: bool = False    # ..X
    suppress: bool = False     # ^X (suppression marker)
    caller_prop: bool = False  # <*X

    def is_permanent(self) -> bool:
        return not self.attenuatable


class EffectSet:
    """A resolved, flat set of EffectEntry objects for one function or boundary."""

    def __init__(self):
        self._entries: Dict[str, EffectEntry] = {}

    def add(self, entry: EffectEntry):
        if entry.name in self._entries:
            # merge flags; permanent wins
            existing = self._entries[entry.name]
            existing.implies |= entry.implies
            existing.requires |= entry.requires
            existing.excludes |= entry.excludes
            existing.weak |= entry.weak
            if not entry.attenuatable:
                existing.attenuatable = False
            existing.one_level |= entry.one_level
            existing.suppress |= entry.suppress
            existing.caller_prop |= entry.caller_prop
        else:
            self._entries[entry.name] = entry

    def has(self, name: str) -> bool:
        return name in self._entries

    def get(self, name: str) -> Optional[EffectEntry]:
        return self._entries.get(name)

    def names(self) -> Set[str]:
        return set(self._entries.keys())

    def entries(self):
        return self._entries.values()

    def copy(self) -> 'EffectSet':
        es = EffectSet()
        for name, e in self._entries.items():
            es._entries[name] = EffectEntry(
                name=e.name, implies=e.implies, requires=e.requires,
                excludes=e.excludes, weak=e.weak, attenuatable=e.attenuatable,
                one_level=e.one_level, suppress=e.suppress, caller_prop=e.caller_prop,
            )
        return es

    def __repr__(self) -> str:
        return f"EffectSet({list(self._entries.keys())})"


# ---------------------------------------------------------------------------
# Built-in effect hierarchy
# Parent effect name -> set of child effect names
# ---------------------------------------------------------------------------

_BUILTIN_CHILDREN: Dict[str, Set[str]] = {
    'IO':           {'IO.Console', 'IO.File', 'IO.Socket', 'IO.Pipe', 'IO.Device', 'IO.Serial', 'IO.USB', 'IO.GPU'},
    'Alloc':        {'Alloc.Heap', 'Alloc.Pool', 'Alloc.Stack', 'Alloc.Virtual', 'Alloc.Shared'},
    'Unsafe':       {'Unsafe.Ptr', 'Unsafe.Cast', 'Unsafe.ASM', 'Unsafe.FFI', 'Unsafe.Uninit'},
    'Mem':          {'Mem.Read', 'Mem.Write', 'Mem.Exec'},
    'Mem.Read':     {'Mem.Read.Process', 'Mem.Read.Kernel', 'Mem.Read.Mapped'},
    'Mem.Write':    {'Mem.Write.Process', 'Mem.Write.Kernel', 'Mem.Write.Exec', 'Mem.Write.Mapped'},
    'Mem.Exec':     {'Mem.Exec.JIT', 'Mem.Exec.Shellcode'},
    'Sync':         {'Sync.Lock', 'Sync.Atomic', 'Sync.Signal', 'Sync.Wait'},
    'Crypto':       {'Crypto.Hash', 'Crypto.Encrypt', 'Crypto.Decrypt', 'Crypto.Random', 'Crypto.Key'},
    'Process':      {'Process.Spawn', 'Process.Kill', 'Process.Inject', 'Process.Suspend', 'Process.Token'},
    'Hook':         {'Hook.Detour', 'Hook.IAT', 'Hook.SSDT', 'Hook.Vtable', 'Hook.Exception'},
    'Privilege':    {'Privilege.Elevate', 'Privilege.Drop', 'Privilege.Check'},
    'Time':         {'Time.RealTime', 'Time.Sleep', 'Time.Timer'},
}

# Reverse map: child -> parent
_BUILTIN_PARENT: Dict[str, str] = {}
for _parent, _children in _BUILTIN_CHILDREN.items():
    for _child in _children:
        _BUILTIN_PARENT[_child] = _parent

# Effects that are permanently non-attenuatable (!@) by default
_PERMANENT_EFFECTS: Set[str] = {
    'Unsafe', 'Unsafe.Ptr', 'Unsafe.Cast', 'Unsafe.ASM', 'Unsafe.FFI', 'Unsafe.Uninit',
}

# Built-in implication rules: if name present, also add these
_BUILTIN_IMPLIES: Dict[str, List[str]] = {
    'Hook.Detour':    ['Hook', 'Unsafe', 'Mem.Write.Exec'],
    'Hook.IAT':       ['Hook', 'Mem.Write'],
    'Hook.SSDT':      ['Hook', 'Privilege', 'Mem.Write.Kernel', 'Unsafe'],
    'Hook.Vtable':    ['Hook', 'Mem.Write'],
    'Process.Inject': ['Process', 'Alloc.Virtual', 'Mem.Write.Exec', 'Hook', 'Unsafe'],
    'Crypto.Key':     ['Crypto'],
    'Time.RealTime':  [],
    # Pure is handled specially (exclusive anchor)
    'Pure':           [],
}

# Pure implies exclusion of these
_PURE_EXCLUDES: Set[str] = {'IO', 'Alloc', 'Mem.Write', 'Throw'}

# All known built-in effect names (flat)
_ALL_BUILTINS: Set[str] = set(_BUILTIN_CHILDREN.keys()) | set(_BUILTIN_PARENT.keys())
_ALL_BUILTINS |= {'Pure', 'Throw'}


# ---------------------------------------------------------------------------
# Diagnostic types
# ---------------------------------------------------------------------------

@dataclass
class EffectViolation:
    """Effect crosses a boundary without attenuation (--effects strict mode)."""
    func_name: str
    effect_name: str
    boundary_name: str

    def __str__(self) -> str:
        return (f"Effect '{self.effect_name}' in '{self.func_name}' "
                f"crosses boundary '{self.boundary_name}' without attenuation")


@dataclass
class EffectConflict:
    """Two effects conflict and no priority resolution is defined."""
    effect_a: str
    effect_b: str
    site: str

    def __str__(self) -> str:
        return (f"Effects '{self.effect_a}' and '{self.effect_b}' conflict "
                f"at '{self.site}' with no priority resolution")


@dataclass
class AttenuationViolation:
    """Attempt to attenuate a !@ (permanent) effect."""
    effect_name: str
    boundary_name: str

    def __str__(self) -> str:
        return (f"Cannot attenuate permanent effect '{self.effect_name}' "
                f"at boundary '{self.boundary_name}' (!@ prevents attenuation)")


@dataclass
class EffectWarning:
    """Violation in --effects-warn mode (advisory only)."""
    message: str

    def __str__(self) -> str:
        return f"Effect warning: {self.message}"


@dataclass
class EffectUndefined:
    """Reference to an unknown effect name."""
    name: str
    site: str

    def __str__(self) -> str:
        return f"Undefined effect '{self.name}' at '{self.site}'"


@dataclass
class EffectCycle:
    """Circular effect definition detected."""
    names: List[str]

    def __str__(self) -> str:
        return f"Circular effect definition: {' -> '.join(self.names)}"


# ---------------------------------------------------------------------------
# Effect algebra evaluator
# Converts an EffectExpr / EffectName AST subtree into an EffectSet.
# ---------------------------------------------------------------------------

def _eval_effect_expr(node, registry: 'EffectRegistry') -> EffectSet:
    """
    Recursively evaluate an effect algebra AST expression into an EffectSet.
    Imports fast AST types locally to avoid circular imports at module load.
    """
    from fast import EffectExpr, EffectName

    if isinstance(node, EffectName):
        es = EffectSet()
        name = node.name

        # Wildcard expansion: *.*  -> all known effects
        #                     Foo.* -> all effects whose name starts with Foo. (plus Foo itself)
        if name == '*.*':
            all_names = set(_ALL_BUILTINS)
            for uname in registry._user_effects:
                all_names.add(uname)
            for n in all_names:
                resolved = registry.resolve(n)
                for e in resolved.entries():
                    es.add(e)
            return es

        if name.endswith('.*'):
            ns = name[:-2]  # strip .*
            all_names = set(_ALL_BUILTINS) | set(registry._user_effects.keys())
            matching = {n for n in all_names if n == ns or n.startswith(ns + '.')}
            for n in matching:
                resolved = registry.resolve(n)
                for e in resolved.entries():
                    es.add(e)
            return es

        # Look up in registry to expand user-defined effects
        resolved = registry.resolve(name)
        for e in resolved.entries():
            es.add(e)
        # Apply !@ for known permanent built-ins
        if name in _PERMANENT_EFFECTS:
            entry = es.get(name)
            if entry:
                entry.attenuatable = False
        return es

    if isinstance(node, EffectExpr):
        op = node.operator

        # Unary operators
        if op == '*':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.implies = True
            return inner

        if op == '~':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.requires = True
            return inner

        if op == '!':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.excludes = True
            return inner

        if op == '?':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.weak = True
            return inner

        if op == '@':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.attenuatable = True
            return inner

        if op == '!@':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.attenuatable = False
                e.excludes = True
            return inner

        if op == '..':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.one_level = True
            return inner

        if op == '...':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.one_level = False
            return inner

        if op == '^suppress':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.suppress = True
            return inner

        if op == '<*':
            inner = _eval_effect_expr(node.left, registry)
            for e in inner.entries():
                e.caller_prop = True
            return inner

        # Binary operators
        if op == '&':
            left = _eval_effect_expr(node.left, registry)
            right = _eval_effect_expr(node.right, registry)
            result = left.copy()
            for e in right.entries():
                result.add(e)
            return result

        if op == '|':
            # OR: include both sides (conservative union)
            left = _eval_effect_expr(node.left, registry)
            right = _eval_effect_expr(node.right, registry)
            result = left.copy()
            for e in right.entries():
                result.add(e)
            return result

        if op == '>':
            # Priority: both present, left has priority over right at conflicts
            left = _eval_effect_expr(node.left, registry)
            right = _eval_effect_expr(node.right, registry)
            result = left.copy()
            for e in right.entries():
                result.add(e)
            return result

        if op == '->':
            # Implication: if left present, right must be present
            # Evaluated conservatively: add both
            left = _eval_effect_expr(node.left, registry)
            right = _eval_effect_expr(node.right, registry)
            result = left.copy()
            for e in right.entries():
                result.add(e)
            return result

        if op == '^|':
            # Exactly one of left or right -- constraint only, not an introduction.
            # Conflict detection handles this; don't poison the effect set.
            return EffectSet()

        if op == '<->':
            # Mutual implication -- constraint only, not an introduction.
            # Conflict detection handles this; don't poison the effect set.
            return EffectSet()

    # Fallback -- unknown node type
    return EffectSet()


# ---------------------------------------------------------------------------
# EffectRegistry
# ---------------------------------------------------------------------------

class EffectRegistry:
    """
    Central registry for user-defined effects and built-in effect relationships.
    Provides resolve(), propagate(), and check_boundary().
    """

    def __init__(self):
        # user_effects: name -> EffectDef AST node
        self._user_effects: Dict[str, object] = {}
        # cached resolved EffectSet per name
        self._cache: Dict[str, EffectSet] = {}
        # function name -> EffectSet (from # effect {} annotation)
        self._func_effects: Dict[str, EffectSet] = {}
        # interface name -> EffectSet (from # attenuate {} annotation)
        self._iface_attenuate: Dict[str, EffectSet] = {}
        # priority table: effect_name -> list of effect names it beats
        self._priority: Dict[str, List[str]] = {}

    def register_user_effect(self, effect_def):
        """Register a user-defined EffectDef node."""
        self._user_effects[effect_def.name] = effect_def
        # Invalidate cache for this name
        self._cache.pop(effect_def.name, None)

    def register_func_effects(self, func_name: str, effect_set: EffectSet):
        self._func_effects[func_name] = effect_set

    def register_iface_attenuate(self, iface_name: str, effect_set: EffectSet):
        self._iface_attenuate[iface_name] = effect_set

    def resolve(self, name: str) -> EffectSet:
        """
        Resolve a named effect to an EffectSet.
        Built-ins produce a single-entry set with appropriate flags.
        User-defined effects are expanded by evaluating their body expression.
        """
        if name in self._cache:
            return self._cache[name].copy()

        es = EffectSet()

        if name in self._user_effects:
            defn = self._user_effects[name]
            if defn.body is not None:
                es = _eval_effect_expr(defn.body, self)
            # Also add the effect name itself
            permanent = name in _PERMANENT_EFFECTS
            entry = EffectEntry(name=name, attenuatable=not permanent)
            es.add(entry)
        else:
            # Built-in or unknown -- create a basic entry
            permanent = name in _PERMANENT_EFFECTS
            es.add(EffectEntry(name=name, attenuatable=not permanent))
            # Apply built-in implications
            for implied in _BUILTIN_IMPLIES.get(name, []):
                impl_es = self.resolve(implied)
                for e in impl_es.entries():
                    es.add(e)

        self._cache[name] = es
        return es.copy()

    def is_child_of(self, child: str, parent: str) -> bool:
        """True if child is a descendant of parent in the built-in or dotted hierarchy."""
        current = child
        # Walk static hierarchy first
        visited = set()
        while current in _BUILTIN_PARENT:
            if current in visited:
                break
            visited.add(current)
            current = _BUILTIN_PARENT[current]
            if current == parent:
                return True
        # Walk dotted name hierarchy: IO.Console.Output -> IO.Console -> IO
        current = child
        while '.' in current:
            current = current.rsplit('.', 1)[0]
            if current == parent:
                return True
        return False

    def propagate(self, effect_set: EffectSet, depth: int = 0) -> EffectSet:
        """
        Apply propagation rules to an effect set for one call-chain level.
        depth=0 means we are at the origin; higher values are callers.
        Removes one_level effects after the first hop.
        """
        if depth == 0:
            return effect_set.copy()

        result = EffectSet()
        for e in effect_set.entries():
            if e.suppress:
                continue
            if e.weak and depth > 0:
                # Weak propagation can be suppressed -- include but mark
                result.add(e)
                continue
            if e.one_level and depth > 1:
                # ..X -- stops after one level
                continue
            if e.caller_prop:
                # <*X -- propagates to caller only, not further up
                if depth == 1:
                    result.add(e)
                continue
            result.add(e)

        # Apply built-in implications transitively
        new_names = list(result.names())
        for name in new_names:
            for implied in _BUILTIN_IMPLIES.get(name, []):
                if not result.has(implied):
                    impl_es = self.resolve(implied)
                    for ie in impl_es.entries():
                        result.add(ie)

        return result

    def check_boundary(
        self,
        func_name: str,
        effect_set: EffectSet,
        boundary_name: str,
        attenuation: EffectSet,
    ) -> List:
        """
        Check whether effect_set is valid crossing boundary_name with the given
        attenuation set. Returns a list of violation objects.
        """
        violations = []
        for e in effect_set.entries():
            if e.excludes:
                continue
            # Check if this effect is attenuated
            if attenuation.has(e.name):
                # Permanent effect cannot be attenuated
                if not e.attenuatable:
                    violations.append(AttenuationViolation(
                        effect_name=e.name,
                        boundary_name=boundary_name,
                    ))
                # Otherwise: attenuation is valid, skip
                continue
            # Check if parent is attenuated (parent attenuation covers children)
            parent = _BUILTIN_PARENT.get(e.name)
            if parent and attenuation.has(parent):
                if not e.attenuatable:
                    violations.append(AttenuationViolation(
                        effect_name=e.name,
                        boundary_name=boundary_name,
                    ))
                continue
            # Effect crosses boundary without attenuation
            violations.append(EffectViolation(
                func_name=func_name,
                effect_name=e.name,
                boundary_name=boundary_name,
            ))

        return violations

    def check_permanent(self, effect_name: str) -> bool:
        """True if this effect is !@ (cannot be attenuated)."""
        es = self.resolve(effect_name)
        entry = es.get(effect_name)
        if entry:
            return not entry.attenuatable
        return effect_name in _PERMANENT_EFFECTS

    def resolve_conflict(self, e1: str, e2: str) -> Optional[str]:
        """
        Return the winner if e1 and e2 have a defined priority ordering.
        Returns None if no ordering is defined (conflict).
        """
        if e2 in self._priority.get(e1, []):
            return e1
        if e1 in self._priority.get(e2, []):
            return e2
        return None

    def register_priority(self, winner: str, loser: str):
        self._priority.setdefault(winner, []).append(loser)


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

COLORS = {
    'red':     '\033[91m',
    'yellow':  '\033[93m',
    'cyan':    '\033[96m',
    'magenta': '\033[95m',
    'orange':  '\033[38;5;214m',
    'dim':     '\033[2m',
    'bold':    '\033[1m',
    'reset':   '\033[0m',
}

KIND_COLOR = {
    'exclusion':           'red',
    'boundary':            'red',
    'attenuation':         'red',
    'conflict':            'yellow',
    'warning':             'yellow',
}


def _c(key: str, text: str, use_color: bool) -> str:
    if not use_color:
        return text
    return f"{COLORS.get(key, '')}{text}{COLORS['reset']}"


def _violation_kind(v) -> str:
    if isinstance(v, EffectExclusionViolation):
        return 'exclusion'
    if isinstance(v, EffectViolation):
        return 'boundary'
    if isinstance(v, AttenuationViolation):
        return 'attenuation'
    if isinstance(v, EffectConflict):
        return 'conflict'
    if isinstance(v, EffectWarning):
        return 'warning'
    return 'violation'


def _violation_location(v) -> str:
    if isinstance(v, EffectExclusionViolation) and v.line:
        return f"{v.line}:{v.col}"
    return ''


def _violation_message(v, use_color: bool = True) -> str:
    if isinstance(v, EffectExclusionViolation):
        return (f"Function {_c('magenta', v.caller_name, use_color)} excludes effect {_c('orange', v.effect_name, use_color)} "
                f"but calls function {_c('magenta', v.callee_name, use_color)} which introduces it")
    if isinstance(v, EffectViolation):
        return (f"{_c('magenta', v.func_name, use_color)} introduces effect {_c('orange', v.effect_name, use_color)} "
                f"which crosses boundary {_c('magenta', v.boundary_name, use_color)} without attenuation")
    if isinstance(v, AttenuationViolation):
        return (f"Cannot attenuate permanent effect {_c('orange', v.effect_name, use_color)} "
                f"at boundary {_c('magenta', v.boundary_name, use_color)} -- !@ prevents attenuation")
    if isinstance(v, EffectConflict):
        return f"Effects {_c('orange', v.effect_a, use_color)} and {_c('orange', v.effect_b, use_color)} conflict at {_c('magenta', v.site, use_color)} with no priority resolution"
    if isinstance(v, EffectWarning):
        return v.message
    return str(v)


def _violation_detail(v, use_color: bool = True) -> List[str]:
    detail = []
    if isinstance(v, EffectExclusionViolation):
        detail.append(f"caller {_c('magenta', v.caller_name, use_color)} declared effect !{_c('orange', v.effect_name, use_color)}")
        detail.append(f"callee {_c('magenta', v.callee_name, use_color)} declared effect {_c('orange', v.effect_name, use_color)}")
    elif isinstance(v, EffectViolation):
        detail.append(f"add `# attenuate {{v.effect_name}}` to boundary {_c('magenta', v.boundary_name, use_color)} to suppress")
    elif isinstance(v, AttenuationViolation):
        detail.append(f"effect {_c('orange', v.effect_name, use_color)} is marked !@ and can never be stripped")
    return detail


def print_violations(violations: list, mode: str = 'error',
                     use_color: bool = True, file=None):
    import sys as _sys
    if file is None:
        file = _sys.stderr
    if not violations:
        return

    level_str = 'error' if mode == 'error' else 'warning'

    for v in violations:
        kind = _violation_kind(v)
        loc  = _violation_location(v)
        msg  = _violation_message(v, use_color)
        detail = _violation_detail(v, use_color)
        color = KIND_COLOR.get(kind, 'red')

        loc_part = f"  {_c('cyan', loc, use_color)}  " if loc else '  '
        print(
            f"{_c('bold', f'[{level_str}]', use_color)} "
            f"{_c(color, kind, use_color)}",
            file=file,
        )
        print(f"{loc_part}{msg}", file=file)
        for d in detail:
            print(f"  {_c('dim', d, use_color)}", file=file)
        print(file=file)


def print_summary(violations: list, use_color: bool = True, file=None):
    import sys as _sys
    if file is None:
        file = _sys.stdout
    n = len(violations)
    if n == 0:
        print(
            _c('bold', '[Effects] ', use_color) +
            _c('cyan', 'OK', use_color) +
            ' -- no violations found.',
            file=file,
        )
    else:
        kinds: Dict[str, int] = {}
        for v in violations:
            k = _violation_kind(v)
            kinds[k] = kinds.get(k, 0) + 1
        kind_str = ', '.join(f"{k}: {c}" for k, c in sorted(kinds.items()))
        print(
            _c('bold', '[Effects] ', use_color) +
            _c('red', f'{n} violation(s)', use_color) +
            f'  {kind_str}',
            file=file,
        )


# ---------------------------------------------------------------------------
# Effect propagation pass
# Runs after DCE, before codegen. Mutates no AST nodes -- only populates the
# registry and returns a list of violations.
# ---------------------------------------------------------------------------

@dataclass
class EffectExclusionViolation:
    """A callee introduces an effect that the caller explicitly excludes (!X)."""
    caller_name: str
    callee_name: str
    effect_name: str
    line: int
    col: int

    def __str__(self) -> str:
        loc = f"{self.line}:{self.col}" if self.line else "?"
        return (f"Effect violation at {loc}: '{self.caller_name}' excludes effect "
                f"'{self.effect_name}' but calls '{self.callee_name}' which introduces it")


def _collect_calls(node) -> List:
    """
    Recursively walk an AST subtree and return all FunctionCall nodes found.
    """
    from fast import FunctionCall, Block, Statement, Expression, ASTNode
    results = []
    if node is None:
        return results
    if isinstance(node, FunctionCall):
        results.append(node)
    # Walk all dataclass fields that are ASTNode, list, or tuple
    for field_val in vars(node).values() if hasattr(node, '__dataclass_fields__') else []:
        if isinstance(field_val, ASTNode):
            results.extend(_collect_calls(field_val))
        elif isinstance(field_val, (list, tuple)):
            for item in field_val:
                if isinstance(item, ASTNode):
                    results.extend(_collect_calls(item))
    return results


def run_effect_pass(
    program,
    registry: EffectRegistry,
    strict: bool = False,
    warn: bool = False,
) -> List:
    """
    Walk the program AST, register all effect annotations, propagate effects
    through the call graph, and check boundaries.

    strict=True  -> violations are errors (--effects)
    warn=True    -> violations are warnings (--effects-warn)
    default      -> transparent mode, no checks, annotations stored only

    Returns list of violation/warning objects.
    """
    from fast import (FunctionDef, InterfaceDef, EffectDef,
                      EffectAnnotation, AttenuateAnnotation, NamespaceDef,
                      EffectExpr, EffectName, InlineAsm)

    violations = []

    # Pass 1: register user-defined effect declarations
    def _collect_effect_defs(stmts):
        for stmt in stmts:
            if stmt is None:
                continue
            if isinstance(stmt, EffectDef):
                registry.register_user_effect(stmt)
            elif isinstance(stmt, NamespaceDef):
                _collect_effect_defs(stmt.functions)
                for _nested in stmt.nested_namespaces:
                    _collect_effect_defs([_nested])

    _collect_effect_defs(program.statements)

    # Pass 2: collect all function effect sets.
    # Prototype annotations are the declaration -- definitions inherit from them
    # if they don't have their own annotation.
    proto_effects: Dict[str, EffectSet] = {}
    proto_attenuate: Dict[str, EffectSet] = {}

    def _collect_annotations(stmts):
        for stmt in stmts:
            if stmt is None:
                continue
            if isinstance(stmt, FunctionDef):
                ann = getattr(stmt, 'effect_annotation', None)
                att_ann = getattr(stmt, 'attenuate_annotation', None)
                if getattr(stmt, 'is_prototype', False):
                    if ann is not None:
                        es = _eval_effect_expr(ann.effects, registry)
                        proto_effects[stmt.name] = es
                        registry.register_func_effects(stmt.name, es)
                    if att_ann is not None:
                        es = _eval_effect_expr(att_ann.effects, registry)
                        proto_attenuate[stmt.name] = es
                        registry.register_iface_attenuate(stmt.name, es)
                else:
                    if ann is not None:
                        es = _eval_effect_expr(ann.effects, registry)
                        registry.register_func_effects(stmt.name, es)
                    elif stmt.name in proto_effects:
                        registry.register_func_effects(stmt.name, proto_effects[stmt.name])
                    if att_ann is not None:
                        es = _eval_effect_expr(att_ann.effects, registry)
                        registry.register_iface_attenuate(stmt.name, es)
                    elif stmt.name in proto_attenuate:
                        registry.register_iface_attenuate(stmt.name, proto_attenuate[stmt.name])
            if isinstance(stmt, InterfaceDef):
                att_ann = getattr(stmt, 'attenuate_annotation', None)
                if att_ann is not None:
                    es = _eval_effect_expr(att_ann.effects, registry)
                    registry.register_iface_attenuate(stmt.name, es)
            if isinstance(stmt, NamespaceDef):
                _collect_annotations(stmt.functions)
                for nested in stmt.nested_namespaces:
                    _collect_annotations([nested])

    _collect_annotations(program.statements)

    # Pass 2b: infer Unsafe.ASM for any function whose body contains inline assembly.
    # This runs after explicit annotation collection so it can merge into existing sets.
    def _body_has_asm(node) -> bool:
        if node is None:
            return False
        if isinstance(node, InlineAsm):
            return True
        for field in node.__dataclass_fields__ if hasattr(node, '__dataclass_fields__') else []:
            val = getattr(node, field, None)
            if isinstance(val, list):
                if any(_body_has_asm(item) for item in val if hasattr(item, '__dataclass_fields__')):
                    return True
            elif hasattr(val, '__dataclass_fields__'):
                if _body_has_asm(val):
                    return True
        return False

    def _infer_asm_effects(stmts):
        for stmt in stmts:
            if stmt is None:
                continue
            if isinstance(stmt, FunctionDef) and not getattr(stmt, 'is_prototype', False):
                body = getattr(stmt, 'body', None)
                if body is not None and _body_has_asm(body):
                    existing = registry._func_effects.get(stmt.name)
                    if existing is None:
                        existing = EffectSet()
                    asm_entry = EffectEntry('Unsafe.ASM')
                    asm_entry.requires = True
                    existing.add(asm_entry)
                    unsafe_entry = EffectEntry('Unsafe')
                    unsafe_entry.requires = True
                    existing.add(unsafe_entry)
                    registry.register_func_effects(stmt.name, existing)
            if isinstance(stmt, NamespaceDef):
                _infer_asm_effects(stmt.functions)
                for nested in stmt.nested_namespaces:
                    _infer_asm_effects([nested])

    _infer_asm_effects(program.statements)

    # Build a bare-name -> list of EffectSet index so that calls resolved via
    # 'using' (bare name 'println') can still find the registry entry stored
    # under the mangled name 'standard__io__console__println'.
    _bare_name_effects: Dict[str, List] = {}
    for mangled, es in registry._func_effects.items():
        bare = mangled.rsplit('__', 1)[-1]
        _bare_name_effects.setdefault(bare, []).append(es)
        # Also index by the full mangled name itself
        _bare_name_effects.setdefault(mangled, []).append(es)

    def _callee_requires_effects(callee_name: str) -> Set[str]:
        """Return all effect names that callee declares it requires (~) or introduces (*).
        A function annotated ~IO.Console is asserting it performs IO.Console."""
        result: Set[str] = set()
        candidates = _bare_name_effects.get(callee_name, [])
        for es in candidates:
            for e in es.entries():
                # ~ (requires) means the function performs this effect
                # * (implies) and plain introduction also count
                if e.requires or e.implies or (not e.excludes):
                    result.add(e.name)
                    # Walk static parent hierarchy
                    parent = _BUILTIN_PARENT.get(e.name)
                    while parent:
                        result.add(parent)
                        parent = _BUILTIN_PARENT.get(parent)
                    # Walk dotted name ancestors dynamically (IO.Console -> IO)
                    parts = e.name
                    while '.' in parts:
                        parts = parts.rsplit('.', 1)[0]
                        result.add(parts)
                    for child in _BUILTIN_CHILDREN.get(e.name, set()):
                        result.add(child)
        return result

    if not (strict or warn):
        # Transparent mode -- annotations stored, no enforcement
        return violations

    # -------------------------------------------------------------------------
    # Pass 3: Build call graph.
    # func_name -> set of callee names (direct calls from that function's body).
    # Only definitions (not prototypes) contribute edges.
    # -------------------------------------------------------------------------
    call_graph: Dict[str, Set[str]] = {}

    def _build_call_graph(stmts):
        for stmt in stmts:
            if stmt is None:
                continue
            if isinstance(stmt, FunctionDef) and not getattr(stmt, 'is_prototype', False):
                body = getattr(stmt, 'body', None)
                if body is not None:
                    callees = {c.name for c in _collect_calls(body)}
                    call_graph.setdefault(stmt.name, set()).update(callees)
            elif isinstance(stmt, NamespaceDef):
                _build_call_graph(stmt.functions)
                for _nested in stmt.nested_namespaces:
                    _build_call_graph([_nested])

    _build_call_graph(program.statements)

    # -------------------------------------------------------------------------
    # Pass 4: Fixed-point transitive effect propagation.
    #
    # transitive[func] = the full set of effect names introduced by func and
    # everything it transitively calls, minus effects that are attenuated at
    # the func's own boundary.
    #
    # Cycles (mutual recursion) are handled naturally by the fixed-point loop:
    # we keep iterating until no set changes.
    # -------------------------------------------------------------------------
    transitive: Dict[str, Set[str]] = {}

    def _direct_introduced(func_name: str) -> Set[str]:
        """Introduced effects from the function's own annotation only."""
        es = registry._func_effects.get(func_name)
        if es is None:
            return set()
        result = set()
        for e in es.entries():
            if not e.excludes:
                result.add(e.name)
                user_def = registry._user_effects.get(e.name)
                if user_def is not None and user_def.body is not None:
                    expanded = _eval_effect_expr(user_def.body, registry)
                    for exp_e in expanded.entries():
                        if not exp_e.excludes:
                            result.add(exp_e.name)
                            parent = _BUILTIN_PARENT.get(exp_e.name)
                            while parent:
                                result.add(parent)
                                parent = _BUILTIN_PARENT.get(parent)
                parent = _BUILTIN_PARENT.get(e.name)
                while parent:
                    result.add(parent)
                    parent = _BUILTIN_PARENT.get(parent)
        return result

    def _attenuated_effects(func_name: str) -> Set[str]:
        """Effects that are attenuated at this function's own boundary."""
        es = registry._iface_attenuate.get(func_name)
        if es is None:
            return set()
        att = set()
        for e in es.entries():
            att.add(e.name)
            for child in _BUILTIN_CHILDREN.get(e.name, set()):
                att.add(child)
        return att

    # Seed: every function starts with its own direct introduced effects
    all_funcs: Set[str] = set(call_graph.keys()) | set(registry._func_effects.keys())
    for fn in all_funcs:
        transitive[fn] = _direct_introduced(fn)

    # Fixed-point iteration
    changed = True
    while changed:
        changed = False
        for fn in all_funcs:
            old_size = len(transitive[fn])
            callees = call_graph.get(fn, set())
            att = _attenuated_effects(fn)
            for callee in callees:
                callee_effects = transitive.get(callee, _direct_introduced(callee))
                # Add callee effects that are not attenuated at this boundary
                for eff in callee_effects:
                    if eff not in att:
                        # Also skip if a parent is attenuated
                        parent = _BUILTIN_PARENT.get(eff)
                        parent_attenuated = False
                        while parent:
                            if parent in att:
                                parent_attenuated = True
                                break
                            parent = _BUILTIN_PARENT.get(parent)
                        if not parent_attenuated:
                            transitive[fn].add(eff)
            if len(transitive[fn]) != old_size:
                changed = True

    # -------------------------------------------------------------------------
    # Pass 5: Extract excluded effects from a function's own annotation only.
    # User-defined effect bodies are NOT expanded into exclusions here --
    # their internal constraints are handled by conflict detection (Pass 8).
    # -------------------------------------------------------------------------
    def _excluded_effects(func_name: str) -> Set[str]:
        es = registry._func_effects.get(func_name)
        if es is None:
            return set()
        excluded = set()
        for e in es.entries():
            if e.excludes:
                excluded.add(e.name)
                for child in _BUILTIN_CHILDREN.get(e.name, set()):
                    excluded.add(child)
        return excluded

    # -------------------------------------------------------------------------
    # Pass 6: Violation checking using transitive sets.
    #
    # For each function with exclusions, check its transitive effect set --
    # not just its direct callees. Report violations at the call site where
    # the excluded effect first enters the transitive set (direct callee that
    # introduces it, whether directly or transitively).
    # -------------------------------------------------------------------------
    def _most_specific(matching: Set[str]) -> Set[str]:
        """Keep only effects with no child also in the matching set."""
        result = set()
        for eff in matching:
            children = _BUILTIN_CHILDREN.get(eff, set())
            user_def = registry._user_effects.get(eff)
            if user_def is not None and user_def.body is not None:
                expanded = _eval_effect_expr(user_def.body, registry)
                for exp_e in expanded.entries():
                    children = children | {exp_e.name}
            if not any(child in matching for child in children):
                result.add(eff)
        return result

    def _check_caller(func_def):
        if getattr(func_def, 'is_prototype', False):
            return
        excluded = _excluded_effects(func_def.name)
        if not excluded:
            return
        body = getattr(func_def, 'body', None)
        if body is None:
            return
        calls = _collect_calls(body)
        # Track which effects have already been reported for this caller
        # to avoid duplicate violations from multiple call paths.
        reported: Set[str] = set()
        for call in calls:
            # Use the transitive set of the callee -- this catches chains.
            # Also fall back to the registry's declared effects for imported/external
            # functions whose bodies are not in this compilation unit.
            callee_transitive = transitive.get(call.name, _direct_introduced(call.name))
            if not callee_transitive:
                # Fall back to declared effects (handles imported/external functions).
                # Include both introduced effects and required (~) effects -- a function
                # declaring ~IO.Console is asserting it performs IO.Console.
                callee_transitive = _callee_requires_effects(call.name)
            # Also subtract effects that the callee attenuates at its boundary.
            callee_att = _attenuated_effects(call.name)
            visible = callee_transitive - callee_att
            for eff in callee_att:
                for child in _BUILTIN_CHILDREN.get(eff, set()):
                    visible.discard(child)
            # Match excluded effects against visible effects using hierarchy:
            # excluded IO.Console.Output matches visible IO.Console (parent covers child)
            # excluded IO.Console matches visible IO.Console.Output (child of excluded)
            def _effect_matches(excl: str, vis_set: Set[str]) -> bool:
                if excl in vis_set:
                    return True
                # A visible effect is a descendant of excl: excluding IO.Console catches IO.Console.Output
                for v in vis_set:
                    cur = v
                    while '.' in cur:
                        cur = cur.rsplit('.', 1)[0]
                        if cur == excl:
                            return True
                return False
            matching = {eff for eff in excluded if _effect_matches(eff, visible) and eff not in reported}
            if not matching:
                continue
            for eff in _most_specific(matching):
                reported.add(eff)
                v = EffectExclusionViolation(
                    caller_name=func_def.name,
                    callee_name=call.name,
                    effect_name=eff,
                    line=call.source_line,
                    col=call.source_col,
                )
                if strict:
                    violations.append(v)
                elif warn:
                    violations.append(EffectWarning(str(v)))

    def _check_all_callers(stmts):
        for stmt in stmts:
            if stmt is None:
                continue
            if isinstance(stmt, FunctionDef):
                _check_caller(stmt)
            elif isinstance(stmt, NamespaceDef):
                _check_all_callers(stmt.functions)
                for _nested in stmt.nested_namespaces:
                    _check_all_callers([_nested])

    _check_all_callers(program.statements)

    # -------------------------------------------------------------------------
    # Pass 7: Pure enforcement.
    #
    # Any function declaring Pure must not transitively introduce any of the
    # anchor exclusions: IO, Alloc, Mem.Write, Throw.
    # -------------------------------------------------------------------------
    _PURE_FORBIDDEN: Set[str] = {'IO', 'Alloc', 'Mem.Write', 'Throw'}
    # Expand to children too
    _PURE_FORBIDDEN_EXPANDED: Set[str] = set(_PURE_FORBIDDEN)
    for _pf in list(_PURE_FORBIDDEN):
        for _child in _BUILTIN_CHILDREN.get(_pf, set()):
            _PURE_FORBIDDEN_EXPANDED.add(_child)

    def _declares_pure(func_name: str) -> bool:
        es = registry._func_effects.get(func_name)
        if es is None:
            return False
        for e in es.entries():
            if e.name == 'Pure' and not e.excludes:
                return True
        return False

    def _check_pure(func_def):
        if getattr(func_def, 'is_prototype', False):
            return
        if not _declares_pure(func_def.name):
            return
        trans = transitive.get(func_def.name, set())
        impure = trans & _PURE_FORBIDDEN_EXPANDED
        if not impure:
            return
        # Report the most specific impure effects
        for eff in _most_specific(impure):
            body = getattr(func_def, 'body', None)
            # Find the first call in the body that introduces this effect
            call_site_line, call_site_col = 0, 0
            if body is not None:
                for call in _collect_calls(body):
                    if eff in transitive.get(call.name, _direct_introduced(call.name)):
                        call_site_line = call.source_line
                        call_site_col = call.source_col
                        break
            v = EffectExclusionViolation(
                caller_name=func_def.name,
                callee_name='(Pure violation)',
                effect_name=eff,
                line=call_site_line or func_def.source_line,
                col=call_site_col or func_def.source_col,
            )
            if strict:
                violations.append(v)
            elif warn:
                violations.append(EffectWarning(str(v)))

    def _check_pure_all(stmts):
        for stmt in stmts:
            if stmt is None:
                continue
            if isinstance(stmt, FunctionDef):
                _check_pure(stmt)
            elif isinstance(stmt, NamespaceDef):
                _check_pure_all(stmt.functions)
                for _nested in stmt.nested_namespaces:
                    _check_pure_all([_nested])

    _check_pure_all(program.statements)

    # -------------------------------------------------------------------------
    # Pass 8: Conflict detection.
    #
    # Walk user-defined effect definitions for ^ (exactly-one) and <->
    # (mutual implication) constraints. Only check functions whose annotation
    # directly references the effect that defines the constraint -- not every
    # function in the program.
    # -------------------------------------------------------------------------

    @dataclass
    class XorConstraint:
        left: str
        right: str
        source: str  # effect name where this was declared

    @dataclass
    class MutualConstraint:
        # For X <-> Y: both must be present, or neither.
        # For X <-> !Y: if X present then Y must be absent, and vice versa.
        left: str
        right: str          # effect name (plain)
        right_negated: bool # True if right side was !Y
        source: str

    xor_constraints: List[XorConstraint] = []
    mutual_constraints: List[MutualConstraint] = []

    def _effect_name_str(node) -> Optional[str]:
        """Return the effect name string, unwrapping unary operators if needed."""
        from fast import EffectName as EN, EffectExpr as EE
        if isinstance(node, EN):
            return node.name
        # Unwrap unary operators: *X, ~X, ?X, @X, !@X, ..X, ...X, <*X
        if isinstance(node, EE) and node.right is None and node.left is not None:
            return _effect_name_str(node.left)
        return None

    def _collect_constraints_from_expr(expr, source_name: str):
        from fast import EffectExpr, EffectName as EN
        if expr is None:
            return
        if isinstance(expr, EffectExpr):
            if expr.operator == '^|':
                left_name = _effect_name_str(expr.left)
                right_name = _effect_name_str(expr.right)
                if left_name and right_name:
                    xor_constraints.append(XorConstraint(left_name, right_name, source_name))
            elif expr.operator == '<->':
                left_name = _effect_name_str(expr.left)
                # Right side may be plain EffectName or !EffectName
                right_name = None
                right_negated = False
                if (isinstance(expr.right, EffectExpr) and expr.right.operator == '!'
                      and _effect_name_str(expr.right.left) is not None):
                    right_name = _effect_name_str(expr.right.left)
                    right_negated = True
                elif _effect_name_str(expr.right) is not None:
                    right_name = _effect_name_str(expr.right)
                if left_name and right_name:
                    mutual_constraints.append(MutualConstraint(
                        left_name, right_name, right_negated, source_name))
            _collect_constraints_from_expr(expr.left, source_name)
            _collect_constraints_from_expr(expr.right, source_name)

    for eff_name, eff_def in registry._user_effects.items():
        if eff_def.body is not None:
            _collect_constraints_from_expr(eff_def.body, eff_name)

    # Deduplicate constraints
    seen_xor: Set[tuple] = set()
    deduped_xor = []
    for xc in xor_constraints:
        key = (xc.left, xc.right, xc.source)
        if key not in seen_xor:
            seen_xor.add(key)
            deduped_xor.append(xc)
    xor_constraints[:] = deduped_xor

    seen_mutual: Set[tuple] = set()
    deduped_mutual = []
    for mc in mutual_constraints:
        key = (mc.left, mc.right, mc.right_negated, mc.source)
        if key not in seen_mutual:
            seen_mutual.add(key)
            deduped_mutual.append(mc)
    mutual_constraints[:] = deduped_mutual

    def _func_declares_effect(func_name: str, effect_name: str) -> bool:
        """True if the function's own annotation directly references effect_name."""
        es = registry._func_effects.get(func_name)
        if es is None:
            return False
        return es.has(effect_name)

    def _check_conflicts(func_def):
        if getattr(func_def, 'is_prototype', False):
            return
        trans = transitive.get(func_def.name, set())
        if not trans:
            return
        reported_conflicts: Set[tuple] = set()
        for xc in xor_constraints:
            # Only check functions that declare the effect containing this constraint
            if not _func_declares_effect(func_def.name, xc.source):
                continue
            left_present = xc.left in trans or any(
                c in trans for c in _BUILTIN_CHILDREN.get(xc.left, set()))
            right_present = xc.right in trans or any(
                c in trans for c in _BUILTIN_CHILDREN.get(xc.right, set()))
            if left_present and right_present:
                key = ('xor', xc.left, xc.right, func_def.name)
                if key in reported_conflicts:
                    continue
                reported_conflicts.add(key)
                v = EffectConflict(
                    effect_a=xc.left,
                    effect_b=xc.right,
                    site=func_def.name,
                )
                if strict:
                    violations.append(v)
                elif warn:
                    violations.append(EffectWarning(str(v)))
        for mc in mutual_constraints:
            if not _func_declares_effect(func_def.name, mc.source):
                continue
            left_present = mc.left in trans or any(
                c in trans for c in _BUILTIN_CHILDREN.get(mc.left, set()))
            right_present = mc.right in trans or any(
                c in trans for c in _BUILTIN_CHILDREN.get(mc.right, set()))
            if mc.right_negated:
                # X <-> !Y: if X present then Y must be absent, and vice versa
                conflict = (left_present and right_present) or (not left_present and not right_present and False)
                # Actually: violation if X present AND Y present, or X absent AND Y absent
                # The meaningful check is: X present XOR Y present must hold
                # i.e. exactly one of {X, Y} in transitive
                conflict = left_present and right_present  # both present or both absent = violation
            else:
                # X <-> Y: both present or both absent -- violation if only one present
                conflict = left_present != right_present
            if conflict:
                key = ('mutual', mc.left, mc.right, func_def.name)
                if key in reported_conflicts:
                    continue
                reported_conflicts.add(key)
                if mc.right_negated:
                    # X <-> !Y: both present = violation
                    msg_b = f'(excludes {mc.right} via <->)'
                else:
                    missing = mc.right if left_present and not right_present else mc.left
                    msg_b = f'(requires {missing} via <->)'
                v = EffectConflict(
                    effect_a=mc.left,
                    effect_b=msg_b,
                    site=func_def.name,
                )
                if strict:
                    violations.append(v)
                elif warn:
                    violations.append(EffectWarning(str(v)))

    def _check_conflicts_all(stmts):
        for stmt in stmts:
            if stmt is None:
                continue
            if isinstance(stmt, FunctionDef):
                _check_conflicts(stmt)
            elif isinstance(stmt, NamespaceDef):
                _check_conflicts_all(stmt.functions)
                for _nested in stmt.nested_namespaces:
                    _check_conflicts_all([_nested])

    _check_conflicts_all(program.statements)

    # -------------------------------------------------------------------------
    # Pass 9: Interface boundary checking.
    # -------------------------------------------------------------------------
    def _check_boundaries(stmts, active_boundaries: List[Tuple[str, EffectSet]]):
        for stmt in stmts:
            if stmt is None:
                continue
            if isinstance(stmt, InterfaceDef):
                att_ann = getattr(stmt, 'attenuate_annotation', None)
                if att_ann is not None:
                    att_es = _eval_effect_expr(att_ann.effects, registry)
                    new_boundaries = active_boundaries + [(stmt.name, att_es)]
                else:
                    new_boundaries = active_boundaries
                for protocol in getattr(stmt, 'protocols', []):
                    for method in getattr(protocol, 'methods', []):
                        func_es = registry._func_effects.get(method.name)
                        if func_es is None:
                            continue
                        for bname, att_es in new_boundaries:
                            vs = registry.check_boundary(method.name, func_es, bname, att_es)
                            for v in vs:
                                if strict:
                                    violations.append(v)
                                elif warn:
                                    violations.append(EffectWarning(str(v)))
            elif isinstance(stmt, NamespaceDef):
                _check_boundaries(stmt.functions, active_boundaries)
                for _nested in stmt.nested_namespaces:
                    _check_boundaries([_nested], active_boundaries)

    _check_boundaries(program.statements, [])

    return violations