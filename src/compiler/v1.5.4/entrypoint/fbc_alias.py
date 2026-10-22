"""
fbc_alias.py -- Alias map and violation detection for the Flux Borrow Checker.

Copyright (C) 2026 Karac V. Thweatt

The alias map tracks every live pointer variable and what allocation site it
refers to. On each assignment, declaration, and scope exit it is updated.
Violations are collected (never raised) so the full program is always walked.

Allocation site identity strings:
  "stack:<func>:<varname>@<line>"   -- stack-allocated variable
  "heap:<func>:<line>"              -- fmalloc call site
  "param:<func>:<paramname>"        -- pointer parameter (borrowed, no owned site)
  "derived:<base_site>"             -- pointer arithmetic result
  "unknown"                         -- could not resolve (extern, etc.)
"""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class PtrInfo:
    """Tracks one live pointer variable."""
    var_name: str
    site: str           # allocation site identity
    mutable: bool       # is this a mutable view of the site
    scope_depth: int    # scope depth at which this pointer was declared
    func_name: str      # enclosing function name
    file: str
    line: int


@dataclass
class Violation:
    kind: str           # 'mutable_alias' | 'scope_escape' | 'use_after_scope' | 'heap_leak' | 'use_after_free' | 'buffer_overflow' | 'out_of_bounds'
    message: str
    file: str
    line: int
    detail: list = field(default_factory=list)  # extra context lines
    func: str = ''      # function the violation was found in (for per-module reporting)

    def format(self) -> str:
        lines = [f"[FBC] {self.kind}"]
        lines.append(f"  {self.file}:{self.line}  {self.message}")
        for d in self.detail:
            lines.append(f"  {d}")
        return '\n'.join(lines)


class ScopeFrame:
    """One scope level's worth of pointer tracking."""
    def __init__(self, depth: int, func_name: str):
        self.depth = depth
        self.func_name = func_name
        # var_name -> PtrInfo
        self.ptrs: dict[str, PtrInfo] = {}
        # allocation sites that are owned at this scope (stack vars)
        self.owned_sites: set[str] = set()
        # var_name -> site string for all stack variables (for address-of resolution)
        self.var_sites: dict[str, str] = {}

    def declare_stack_site(self, var_name: str, site: str, line: int, file: str):
        """Register a new stack allocation site owned by this scope."""
        self.owned_sites.add(site)

    def add_ptr(self, info: PtrInfo):
        self.ptrs[info.var_name] = info

    def remove_ptr(self, var_name: str):
        self.ptrs.pop(var_name, None)

    def all_ptrs(self) -> list[PtrInfo]:
        return list(self.ptrs.values())


class AliasMap:
    """
    Maintains the full stack of scope frames for the current execution path.
    Collects all violations without stopping.
    """

    def __init__(self):
        self.frames: list[ScopeFrame] = []
        self.violations: list[Violation] = []
        self.func_name = '<global>'
        self.file = '<unknown>'
        # heap allocation sites that have been fmalloc'd but not ffree'd
        # site -> (file, line)
        self.heap_sites: dict[str, tuple[str, int]] = {}
        # sites that have been freed via ffree -- any subsequent dereference
        # or array access through a pointer whose site is in here is a violation
        # site -> (file, line) of the ffree call
        self.freed_sites: dict[str, tuple[str, int]] = {}
        # known byte-sizes of allocations; -1 means unknown
        # site -> byte count
        self.alloc_sizes: dict[str, int] = {}
        # sites that have been passed to a spawned thread -- any subsequent
        # mutable access to these sites is a race condition
        # site -> (thread_file, thread_line)
        self.thread_escaped_sites: dict[str, tuple[str, int]] = {}

    # ------------------------------------------------------------------
    # Scope management
    # ------------------------------------------------------------------

    def push_scope(self):
        depth = len(self.frames)
        self.frames.append(ScopeFrame(depth, self.func_name))

    def pop_scope(self, check_leaks: bool = False):
        if not self.frames:
            return
        frame = self.frames.pop()
        # any pointer at this scope depth that pointed into this scope's
        # owned sites now dangles -- check all surviving frames for them
        if frame.owned_sites:
            self._check_escape_after_pop(frame.owned_sites, frame)
        # remove ptrs declared at this depth from all frames
        for f in self.frames:
            dead = [n for n, p in f.ptrs.items() if p is not None and p.scope_depth == frame.depth]
            for n in dead:
                f.ptrs.pop(n)

    def _check_escape_after_pop(self, dead_sites: set[str], dead_frame: ScopeFrame):
        """
        After a scope exits, check if any surviving pointer still references
        one of the now-dead stack sites.
        """
        for frame in self.frames:
            for ptr in frame.all_ptrs():
                if ptr.site in dead_sites:
                    self.violations.append(Violation(
                        kind='scope_escape',
                        message=(
                            f"pointer '{ptr.var_name}' outlives its stack allocation "
                            f"'{ptr.site}' (allocation scope exited)"
                        ),
                        file=ptr.file,
                        line=ptr.line,
                    ))

    # ------------------------------------------------------------------
    # Pointer declaration / assignment
    # ------------------------------------------------------------------

    def declare_ptr(self, var_name: str, site: str, mutable: bool,
                    file: str, line: int, is_stack_owner: bool = False,
                    source_var: str = None):
        """
        Register a new pointer variable in the current scope.
        is_stack_owner=True means this var IS the stack allocation (its address
        may be taken later -- we track the site now).
        source_var: the name of the pointer variable whose site was copied to
        produce this one (e.g. the RHS of `byte* p = q`).  That variable is
        excluded from the alias check so that a plain pointer copy does not
        produce a false-positive violation.
        """
        if not self.frames:
            return
        frame = self.frames[-1]
        if is_stack_owner:
            frame.declare_stack_site(var_name, site, line, file)

        info = PtrInfo(
            var_name=var_name,
            site=site,
            mutable=mutable,
            scope_depth=frame.depth,
            func_name=self.func_name,
            file=file,
            line=line,
        )
        frame.add_ptr(info)
        # alias check deferred to call sites -- checking at declaration time
        # produces false positives when a pointer is copied from another live pointer

    def assign_ptr(self, var_name: str, site: str, mutable: bool,
                   file: str, line: int, source_var: str = None):
        """Update an existing pointer variable to point to a new site.
        source_var: excluded from the alias check (see declare_ptr).
        When a pointer is reassigned to a fresh allocation, its old freed
        site is no longer reachable through this variable -- remove it so
        accesses after the reassignment are not falsely flagged.
        """
        info = self._find_ptr(var_name)
        if info is None:
            # new pointer introduced via assignment without prior declaration
            self.declare_ptr(var_name, site, mutable, file, line, source_var=source_var)
            return
        old_site = info.site
        info.site = site
        info.mutable = mutable
        info.file = file
        info.line = line
        # if reassigned to a fresh non-freed site, the old freed record is
        # no longer reachable through this variable -- only remove it if no
        # other tracked pointer still points to that site
        if (old_site and old_site in self.freed_sites
                and site != old_site
                and not site.startswith('freed:')):
            still_used = any(
                p.site == old_site
                for frame in self.frames
                for p in frame.all_ptrs()
                if p.var_name != var_name
            )
            if not still_used:
                self.freed_sites.pop(old_site, None)
        # alias check deferred to call sites

    def _find_ptr(self, var_name: str) -> Optional[PtrInfo]:
        """Search all frames top-down for a pointer variable."""
        for frame in reversed(self.frames):
            if var_name in frame.ptrs:
                return frame.ptrs[var_name]
        return None

    # ------------------------------------------------------------------
    # Heap tracking
    # ------------------------------------------------------------------

    def record_malloc(self, site: str, file: str, line: int):
        self.heap_sites[site] = (file, line)

    def record_free(self, site: str):
        self.heap_sites.pop(site, None)

    @staticmethod
    def _base_site(site: str) -> str:
        """Strip a single derived: prefix to get the base allocation site."""
        if site.startswith('derived:'):
            return site[len('derived:'):]
        return site

    def mark_freed(self, site: str, file: str, line: int):
        """Record that a heap site has been passed to ffree."""
        if site and site != 'unknown' and not site.startswith('derived:'):
            self.freed_sites[site] = (file, line)

    def check_use_after_free(self, var_name: str, file: str, line: int):
        """
        Check if the pointer named var_name points to a freed site.
        Also checks the base site for derived pointers (e.g. p+10 after ffree(p)).
        Called at every dereference, array access, and pointer-target assignment.
        """
        info = self._find_ptr(var_name)
        if info is None:
            return
        site = info.site
        base = self._base_site(site)
        matched = None
        if site in self.freed_sites:
            matched = site
        elif base != site and base in self.freed_sites:
            matched = base
        if matched is not None:
            free_file, free_line = self.freed_sites[matched]
            self.violations.append(Violation(
                kind='use_after_free',
                message=(
                    f"pointer '{var_name}' used after its allocation site "
                    f"'{matched}' was passed to ffree"
                ),
                file=file,
                line=line,
                detail=[
                    f"ffree called at {free_file}:{free_line}",
                    f"'{var_name}' -> {site} at {file}:{line}",
                ]
            ))

    def record_alloc_size(self, site: str, size: int):
        """Associate a known byte size with an allocation site."""
        if site and site != 'unknown' and not site.startswith('derived:'):
            self.alloc_sizes[site] = size

    def check_bounds(self, var_name: str, index: int, file: str, line: int, write: bool = False):
        """
        Check if a concrete array index is out of bounds for a known site.
        Also checks the base site for derived pointers.
        Reports buffer_overflow for out-of-bounds writes, out_of_bounds for reads.
        """
        info = self._find_ptr(var_name)
        if info is None:
            return
        site = info.site
        base = self._base_site(site)
        # prefer the direct site, fall back to base for derived pointers
        if site in self.alloc_sizes:
            lookup = site
        elif base != site and base in self.alloc_sizes:
            lookup = base
        else:
            return
        size = self.alloc_sizes[lookup]
        if size < 0:
            return
        if index < 0 or index >= size:
            kind = 'buffer_overflow' if write else 'out_of_bounds'
            self.violations.append(Violation(
                kind=kind,
                message=(
                    f"array {'write' if write else 'access'} through '{var_name}' at index {index} is "
                    f"out of bounds for site '{lookup}' (size {size})"
                ),
                file=file,
                line=line,
                detail=[
                    f"'{var_name}' -> {site} (size {size}) at {file}:{line}",
                    f"index {index} {'< 0' if index < 0 else '>= size'}",
                ]
            ))

    def check_heap_leaks(self):
        """Call at function exit to report unfreed heap allocations."""
        for site, (file, line) in self.heap_sites.items():
            self.violations.append(Violation(
                kind='heap_leak',
                message=f"heap allocation '{site}' has no reachable ffree on all paths",
                file=file,
                line=line,
            ))
        self.heap_sites.clear()
        self.freed_sites.clear()
        self.alloc_sizes.clear()

    # ------------------------------------------------------------------
    # Alias checking
    # ------------------------------------------------------------------

    def _all_live_ptrs(self) -> list[PtrInfo]:
        result = []
        for frame in self.frames:
            result.extend(frame.all_ptrs())
        return result

    def _check_mutable_alias(self, new_ptr: PtrInfo, exclude_var: str = None):
        """
        Check if new_ptr creates a mutable aliasing violation with any
        currently live pointer pointing to the same site.
        Compares base sites so that a derived pointer (p+10) is caught as an
        alias of the original pointer (p) into the same allocation.

        exclude_var: name of the source pointer whose site was copied to
        produce new_ptr (e.g. the RHS of an assignment).  Excluded from the
        check so that a plain pointer copy does not produce a false positive.
        """
        if new_ptr.site == 'unknown':
            return
        new_base = self._base_site(new_ptr.site)
        for existing in self._all_live_ptrs():
            if existing.var_name == new_ptr.var_name:
                continue
            if exclude_var and existing.var_name == exclude_var:
                continue
            if existing.site == 'unknown':
                continue
            existing_base = self._base_site(existing.site)
            if existing_base != new_base:
                continue
            # same base site -- violation if either is mutable
            if new_ptr.mutable or existing.mutable:
                is_derived = new_ptr.site != new_base or existing.site != existing_base
                detail_suffix = ' (derived pointer into same allocation)' if is_derived else ''
                self.violations.append(Violation(
                    kind='mutable_alias',
                    message=(
                        f"mutable alias violation on site '{new_base}'{detail_suffix}"
                    ),
                    file=new_ptr.file,
                    line=new_ptr.line,
                    detail=[
                        f"'{new_ptr.var_name}' -> {new_ptr.site} "
                        f"({'mutable' if new_ptr.mutable else 'immutable'}) "
                        f"at {new_ptr.file}:{new_ptr.line}",
                        f"'{existing.var_name}' -> {existing.site} "
                        f"({'mutable' if existing.mutable else 'immutable'}) "
                        f"at {existing.file}:{existing.line}",
                    ]
                ))

    def check_write_alias(self, var_name: str, file: str, line: int):
        """
        Called when a write occurs through pointer var_name (*p = x or p[i] = x).
        Checks if any other live pointer shares the same base site -- if so,
        that is a mutable alias: two pointers can write into the same allocation.
        Only fires for derived pointers (base site differs from site) to avoid
        duplicating the declaration-time alias check for plain copies.
        """
        info = self._find_ptr(var_name)
        if info is None:
            return
        site = info.site
        base = self._base_site(site)
        for existing in self._all_live_ptrs():
            if existing.var_name == var_name:
                continue
            if existing.site == 'unknown':
                continue
            # skip pointers whose site has been freed -- no longer a live alias
            existing_base = self._base_site(existing.site)
            if existing.site in self.freed_sites or existing_base in self.freed_sites:
                continue
            if existing_base != base:
                continue
            if not (info.mutable or existing.mutable):
                continue
            self.violations.append(Violation(
                kind='mutable_alias',
                message=(
                    f"mutable alias violation on site '{base}' "
                    f"(write through derived pointer into same allocation)"
                ),
                file=file,
                line=line,
                detail=[
                    f"'{var_name}' -> {site} "
                    f"({'mutable' if info.mutable else 'immutable'}) "
                    f"at {file}:{line}",
                    f"'{existing.var_name}' -> {existing.site} "
                    f"({'mutable' if existing.mutable else 'immutable'}) "
                    f"at {existing.file}:{existing.line}",
                ]
            ))
            break  # one report per write is enough

    def check_call_args(self, arg_sites: list, file: str, line: int):
        """
        Check pointer arguments at an opaque call site (unresolved callee,
        extern, function pointer, or unresolved method) for mutable aliasing.

        arg_sites is a list of (name_hint, site) pairs -- one per pointer
        argument expression at the call site.  Only argument pairs are checked
        against each other -- checking arguments against all live caller pointers
        would produce false positives when a local pointer variable was copied
        from a live pointer and both are passed as arguments.

        unknown and derived: sites are skipped per the standard rules.
        """
        # check argument pairs against each other only
        for i in range(len(arg_sites)):
            name_a, site_a = arg_sites[i]
            if site_a == 'unknown' or site_a.startswith('derived:'):
                continue
            for j in range(i + 1, len(arg_sites)):
                name_b, site_b = arg_sites[j]
                if site_b == 'unknown' or site_b.startswith('derived:'):
                    continue
                if site_a == site_b:
                    self.violations.append(Violation(
                        kind='mutable_alias',
                        message=f"mutable alias violation on site '{site_a}'",
                        file=file,
                        line=line,
                        detail=[
                            f"argument '{name_a}' -> {site_a} (mutable) at {file}:{line}",
                            f"argument '{name_b}' -> {site_b} (mutable) at {file}:{line}",
                        ]
                    ))

    # ------------------------------------------------------------------
    # Thread safety
    # ------------------------------------------------------------------

    def check_thread_escape(self, ptr_var: str, file: str, line: int):
        """
        Called when a pointer is passed to a spawned thread.
        Phase 1: check for existing mutable aliases at spawn time.
        Phase 2: mark the site as thread-escaped so any subsequent
                 mutable access in the caller is flagged as a race.
        """
        info = self._find_ptr(ptr_var)
        if info is None:
            return

        # Phase 1 -- alias already exists at spawn time
        for existing in self._all_live_ptrs():
            if existing.var_name == ptr_var:
                continue
            if existing.site != info.site:
                continue
            if existing.site == 'unknown' or existing.site.startswith('derived:'):
                continue
            if existing.mutable or info.mutable:
                self.violations.append(Violation(
                    kind='thread_escape',
                    message=(
                        f"pointer '{ptr_var}' passed to thread while mutable "
                        f"alias '{existing.var_name}' exists on site '{info.site}'"
                    ),
                    file=file,
                    line=line,
                    detail=[
                        f"'{existing.var_name}' -> {existing.site} "
                        f"at {existing.file}:{existing.line}",
                    ]
                ))

        # Phase 2 -- mark site as escaped so future accesses are flagged
        # skip unknown sites to avoid false positives from unresolved pointers
        if info.mutable and info.site != 'unknown' and not info.site.startswith('derived:'):
            self.thread_escaped_sites[info.site] = (file, line)

    def check_use_after_escape(self, ptr_var: str, file: str, line: int):
        """
        Call this when a pointer is read or written after a spawn.
        Flags if the pointer's site (or its base site for derived pointers)
        was passed to a thread.
        """
        info = self._find_ptr(ptr_var)
        if info is None:
            return
        site = info.site
        base = self._base_site(site)
        matched = None
        if site in self.thread_escaped_sites:
            matched = site
        elif base != site and base in self.thread_escaped_sites:
            matched = base
        if matched is None:
            return
        spawn_file, spawn_line = self.thread_escaped_sites[matched]
        if spawn_line == line:
            return
        self.violations.append(Violation(
            kind='thread_race',
            message=(
                f"pointer '{ptr_var}' accessed after its site '{matched}' "
                f"was passed to a thread (potential data race)"
            ),
            file=file,
            line=line,
            detail=[
                f"site escaped to thread at {spawn_file}:{spawn_line}",
                f"'{ptr_var}' -> {site} (mutable) at {file}:{line}",
            ]
        ))