#!/usr/bin/env python3
"""
Flux unused variable warnings  (funused.py)

Runs on the AST produced by FluxParser before code generation and warns about
local variables that are declared and never referenced.

A reference is any use of the name: a read, an assignment target, an address-of,
a call through it or a $name stringify. A name is resolved to the innermost
enclosing declaration. Not reported:
  - names starting with an underscore
  - globals and singinit variables
  - object instances built by a constructor call (the constructor runs anyway)
  - 'from' recasts (they invalidate their source)
  - code that comes from the standard library
"""

import re
from dataclasses import fields, is_dataclass

import fast
from ferrors import emit_warning


class _Tok:
    """The minimum a diagnostic needs from a token."""
    def __init__(self, line, column):
        self.line = line
        self.column = column


def _is_stdlib(path) -> bool:
    return 'stdlib' in str(path).replace('\\', '/').split('/')


class UnusedVariables:
    def __init__(self, line_map, source_lines):
        self.line_map = line_map or []
        self.source_lines = source_lines or []
        self.scopes = []          # innermost last: dict name -> [node, used]
        self.found = []           # (node, name)
        self.seen = set()

    # -- entry -------------------------------------------------------
    def run(self, program):
        self._walk(program.statements)
        reported = []
        for node, name in sorted(self.found, key=lambda t: (t[0].source_line, t[0].source_col)):
            fl = self.line_map[node.source_line - 1][0] if (
                self.line_map and 1 <= node.source_line <= len(self.line_map)) else ''
            if _is_stdlib(fl):
                continue
            key = (fl, self.line_map[node.source_line - 1][1] if fl else node.source_line,
                   node.source_col, name)
            if key in self.seen:
                continue
            self.seen.add(key)
            reported.append((node, name))
        for node, name in reported:
            col = node.source_col
            if 1 <= node.source_line <= len(self.source_lines):
                m = re.compile(r'(?<![A-Za-z0-9_])' + re.escape(name) + r'(?![A-Za-z0-9_])').search(
                    self.source_lines[node.source_line - 1], max(0, col - 1))
                if m:
                    col = m.start() + 1
            emit_warning(f"unused variable '{name}'", _Tok(node.source_line, col),
                         self.source_lines, self.line_map)
        return len(reported)

    # -- scopes ------------------------------------------------------
    def _use(self, name):
        for sc in reversed(self.scopes):
            ent = sc.get(name)
            if ent is not None:
                ent[1] = True
                return

    def _push(self):
        self.scopes.append({})

    def _pop(self):
        sc = self.scopes.pop()
        for name, (node, used) in sc.items():
            if not used:
                self.found.append((node, name))

    def _declare(self, node):
        if not self.scopes or node.is_global or not node.name or node.name.startswith('_'):
            return
        sc = getattr(node.type_spec, 'storage_class', None)
        if sc is not None and getattr(sc, 'name', '') in ('GLOBAL', 'SINGINIT'):
            return
        iv = node.initial_value
        if isinstance(iv, fast.StructRecast):
            return
        if isinstance(iv, fast.FunctionCall) and isinstance(iv.name, str) and iv.name.endswith('.__init'):
            return
        self.scopes[-1][node.name] = [node, False]

    # -- walk --------------------------------------------------------
    def _walk(self, n):
        if isinstance(n, (list, tuple)):
            for x in n:
                self._walk(x)
            return
        if not isinstance(n, fast.ASTNode):
            return
        if isinstance(n, fast.FunctionDef):
            saved, self.scopes = self.scopes, []
            self._push()
            self._walk(n.parameters)
            self._walk(n.body)
            self._pop()
            self.scopes = saved
            return
        if isinstance(n, fast.VariableDeclaration):
            self._walk(n.initial_value)
            self._declare(n)
            return
        if isinstance(n, fast.Identifier):
            self._use(n.name)
            return
        if isinstance(n, fast.Stringify):
            self._use(n.name)
            return
        if isinstance(n, fast.InlineAsm):
            # operands are named only inside the constraint text: "r"(name)
            for nm in re.findall(r'"[^"]+"\s*\(([^)]+)\)', n.constraints or ''):
                self._use(nm.strip())
            return
        scoped = isinstance(n, (fast.Block, fast.ForLoop, fast.ForInLoop)) and self.scopes
        if scoped:
            self._push()
        if isinstance(n, fast.FunctionCall) and isinstance(n.name, str):
            self._use(n.name)
        if is_dataclass(n):
            for f in fields(n):
                self._walk(getattr(n, f.name, None))
        if scoped:
            self._pop()


def warn_unused(program, line_map, source_lines) -> int:
    """Print a warning for every unused local variable. Returns how many were reported."""
    return UnusedVariables(line_map, source_lines).run(program)