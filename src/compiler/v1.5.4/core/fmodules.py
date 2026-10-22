"""
fmodules.py - module system.

A module is a named group of declarations with a build block:

    module Main
    {
        from "logging.fx";
        def main() -> int { ... };
    }
    # build
    {
        #[entrypoint] = this,
        #[target] = executable,
        !+#[effect_check] = true,
        #[override for {Logging}] = { #[borrow_check] = true },
    };

This pass runs after parsing. It pulls every module reachable through 'from'
clauses into one compilation unit, resolves each module's build settings, tags
every function with the module that owns it, and flattens the module bodies into
the program's statement list so the rest of the compiler sees an ordinary program.

Settings (tag, default):
    entrypoint   -  'this' marks the entry module of the target file
    name         module name     output name (entry module)
    target       executable      bootloader | executable | compact | library | driver
    debug        false           Debug instead of Release output folder
    borrow_check false           report borrow violations for this module's code
    effect_check false           report effect violations for this module's code
    dce          true            false keeps every declaration of the module alive
    using        {}              namespaces made visible to the module's code
    platform     {}              platforms the module builds for (empty = any)

A module's own entries set its settings. '#[override for {M}] = { ... }' in another
module overrides M's settings as M is built into this target, unless M locked the tag
with '!+'. The module closest to the entry wins when several override the same tag.
The command line can only switch checks on: --borrowcheck and --effects force the
check for every module, including modules that lock it to false.
"""

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

import fast
from fast import ModuleDef, NamespaceDef, FunctionDef, ObjectDef, UsingStatement

TARGETS = ('bootloader', 'executable', 'compact', 'library', 'driver')
_BOOL_TAGS = ('borrow_check', 'effect_check', 'dce', 'debug')
_KNOWN_TAGS = ('entrypoint', 'name', 'target', 'debug', 'borrow_check', 'effect_check',
               'dce', 'using', 'platform')
_DEFAULTS = {'borrow_check': False, 'effect_check': False, 'dce': True, 'debug': False,
             'target': 'executable', 'using': [], 'platform': []}


class ModuleError(Exception):
    pass


@dataclass
class ModuleInfo:
    node: ModuleDef
    file: str
    deps: list = field(default_factory=list)       # module names this module pulls with 'from'
    settings: dict = field(default_factory=dict)
    locked: set = field(default_factory=set)
    entry: bool = False

    @property
    def name(self):
        return self.node.name


@dataclass
class ModuleUnit:
    modules: dict                                   # name -> ModuleInfo
    order: list                                     # names, dependencies first
    entry: str = ''
    programs: list = field(default_factory=list)    # root modules that can be built as programs

    def entry_settings(self):
        return self.modules[self.entry].settings


def _has_modules(statements):
    return any(isinstance(s, ModuleDef) for s in statements if s is not None)


def _resolve_path(spec, from_file):
    """A 'from' path is relative to the file that names it, then to the working directory."""
    p = Path(spec)
    if p.is_absolute() and p.exists():
        return p.resolve()
    base = Path(from_file).resolve().parent
    for cand in (base / p, Path.cwd() / p):
        if cand.exists():
            return cand.resolve()
    raise ModuleError(f"from \"{spec}\": file not found (looked in {base} and {Path.cwd()})")


def _tag_value(entries, tag):
    """Last entry of the given tag, or None."""
    found = None
    for e in entries:
        if e.override_for is None and e.tag == tag:
            found = e
    return found


def _defines(mod, fn_name):
    for s in mod.body:
        fd = s if isinstance(s, FunctionDef) else getattr(s, 'function_def', None)
        if isinstance(fd, FunctionDef) and fd.name == fn_name:
            return True
    return False


def load(ast, root_file, parse_file, select=None, entry_fn='main'):
    """Collect the modules of the root file and everything they pull in with 'from'.

    parse_file(path) -> Program for another source file.
    Returns a ModuleUnit, or None when the program declares no modules."""
    root_mods = [s for s in ast.statements if isinstance(s, ModuleDef)]
    if not root_mods:
        return None
    root_abs = str(Path(root_file).resolve())
    infos = {}
    order = []
    loading = []
    file_modules = {root_abs: [m.name for m in root_mods]}

    def add(mod, file):
        if mod.name in infos:
            if infos[mod.name].file != file:
                raise ModuleError(f"module '{mod.name}' is declared in both "
                                  f"{infos[mod.name].file} and {file}")
            return
        mod.source_file = file
        infos[mod.name] = ModuleInfo(mod, file)

    def visit(name):
        info = infos[name]
        if name in loading:
            raise ModuleError("modules depend on each other: " + " -> ".join(loading + [name]))
        if name in order:
            return
        loading.append(name)
        for spec in info.node.froms:
            path = str(_resolve_path(spec, info.file))
            if path not in file_modules:
                prog = parse_file(path)
                mods = [s for s in prog.statements if isinstance(s, ModuleDef)]
                if not mods:
                    raise ModuleError(f"from \"{spec}\": the file declares no module")
                for m in mods:
                    add(m, path)
                file_modules[path] = [m.name for m in mods]
            for dep in file_modules[path]:
                if dep not in info.deps:
                    info.deps.append(dep)
                visit(dep)
        loading.pop()
        order.append(name)

    for m in root_mods:
        add(m, root_abs)
    marked = [m.name for m in root_mods if (_tag_value(m.build, 'entrypoint') is not None
                                            and _tag_value(m.build, 'entrypoint').value == 'this')]
    programs = [m.name for m in root_mods if m.name in marked or _defines(m, entry_fn)]
    if not programs:
        raise ModuleError("no module in " + os.path.basename(root_file)
                          + " defines " + entry_fn + "() or sets '#[entrypoint] = this'")
    if select is not None:
        if select not in programs:
            raise ModuleError(f"module '{select}' is not a program of this file")
        entry = select
    else:
        entry = (marked or programs)[0]
    infos[entry].entry = True
    for m in root_mods:                      # modules of the same file are visible to each other
        if m.name != entry:
            visit(m.name)
    visit(entry)
    return ModuleUnit(infos, order, entry, programs)


def resolve_settings(unit, cli_borrow=False, cli_effects=False, platform=''):
    """Fill in ModuleInfo.settings for every module of the unit."""
    for info in unit.modules.values():
        s = dict(_DEFAULTS)
        s['using'] = []
        s['platform'] = []
        s['name'] = info.name
        for e in info.node.build:
            if e.override_for is not None:
                continue
            if e.tag not in _KNOWN_TAGS:
                raise ModuleError(f"module '{info.name}': unknown build tag '#[{e.tag}]'")
            if e.tag == 'entrypoint':
                continue
            s[e.tag] = _coerce(info.name, e.tag, e.value)
            if e.locked:
                info.locked.add(e.tag)
        if s['target'] not in TARGETS:
            raise ModuleError(f"module '{info.name}': '#[target] = {s['target']}' is not one of "
                              + ", ".join(TARGETS))
        info.settings = s

    # overrides: breadth first from the entry, so the module nearest the entry wins
    applied = {}
    queue = [unit.entry]
    seen = set(queue)
    while queue:
        cur = queue.pop(0)
        for e in unit.modules[cur].node.build:
            if e.override_for is None:
                continue
            for target in e.override_for:
                if target not in unit.modules:
                    raise ModuleError(f"module '{cur}': '#[override for {{{target}}}]' names a module "
                                      f"that is not part of this build")
                t = unit.modules[target]
                for oe in e.value:
                    if oe.tag not in _KNOWN_TAGS or oe.tag == 'entrypoint':
                        raise ModuleError(f"module '{cur}': cannot override '#[{oe.tag}]'")
                    if oe.tag in t.locked or (target, oe.tag) in applied:
                        continue
                    t.settings[oe.tag] = _coerce(target, oe.tag, oe.value)
                    applied[(target, oe.tag)] = cur
        for d in unit.modules[cur].deps:
            if d not in seen:
                seen.add(d)
                queue.append(d)

    # Modules that are only visible because they share the entry's file are not part of
    # this program's module graph: their checks do not run in this build.
    members = {unit.entry}
    stack = [unit.entry]
    while stack:
        for d in unit.modules[stack.pop()].deps:
            if d not in members:
                members.add(d)
                stack.append(d)
    for name, info in unit.modules.items():
        if name not in members:
            info.settings['borrow_check'] = False
            info.settings['effect_check'] = False

    for info in unit.modules.values():
        if cli_borrow:
            info.settings['borrow_check'] = True
        if cli_effects:
            info.settings['effect_check'] = True
        plats = [p.lower() for p in info.settings['platform']]
        if plats and platform and platform.lower() not in plats:
            raise ModuleError(f"module '{info.name}' builds for {{{', '.join(info.settings['platform'])}}} "
                              f"but this build targets {platform}")


def _coerce(mod, tag, value):
    if tag in _BOOL_TAGS:
        if isinstance(value, str) and value in ('true', 'false'):
            return value == 'true'
        if not isinstance(value, bool):
            raise ModuleError(f"module '{mod}': '#[{tag}]' takes true or false")
        return value
    if tag in ('using', 'platform'):
        if not isinstance(value, list):
            raise ModuleError(f"module '{mod}': '#[{tag}]' takes a list: {{A, B}}")
        return list(value)
    if isinstance(value, (list, bool)):
        raise ModuleError(f"module '{mod}': '#[{tag}]' takes a single name")
    return str(value)


def _tag_functions(stmts, module, out):
    """Mark every function (including namespace functions and object methods) with its module."""
    for s in stmts:
        if s is None:
            continue
        fd = getattr(s, 'function_def', None) if not isinstance(s, FunctionDef) else s
        if isinstance(fd, FunctionDef):
            fd._module = module
            out.append(fd)
        elif isinstance(s, NamespaceDef):
            _tag_functions(s.functions, module, out)
            _tag_functions(s.nested_namespaces, module, out)
            for o in s.objects:
                _tag_functions(getattr(o, 'methods', []) or [], module, out)
        elif isinstance(s, ObjectDef):
            _tag_functions(s.methods or [], module, out)
        elif hasattr(s, 'namespace_def'):
            _tag_functions([s.namespace_def], module, out)
        elif hasattr(s, 'object_def'):
            _tag_functions([s.object_def], module, out)


def flatten(ast, unit, entry_fn='main'):
    """Replace the module declarations of the program by their contents, dependencies first.

    Statements that are not modules (the root file's imports and globals) stay in front.
    Each module's 'using' list becomes using statements in front of its body."""
    rest = [s for s in ast.statements if not isinstance(s, ModuleDef)]
    body = []
    funcs = []
    for name in unit.order:
        info = unit.modules[name]
        for ns in info.settings['using']:
            u = UsingStatement(ns.replace('.', '::'))
            u.set_location(info.node.source_line, info.node.source_col)
            body.append(u)
        if not info.entry:                  # only the entry module contributes the program's main
            info.node.body = [s for s in info.node.body if not (
                (s if isinstance(s, FunctionDef) else getattr(s, 'function_def', None)).__class__ is FunctionDef
                and (s if isinstance(s, FunctionDef) else s.function_def).name == entry_fn)]
        _tag_functions(info.node.body, name, funcs)
        body.extend(info.node.body)
    ast.statements = rest + body
    ast._modules = unit
    return funcs


def func_modules(ast):
    """(mangled name -> module, bare name -> module) for every tagged function."""
    full, bare = {}, {}

    def walk(stmts, prefix):
        for s in stmts:
            if s is None:
                continue
            if isinstance(s, FunctionDef):
                m = getattr(s, '_module', None)
                if m is not None:
                    full[f"{prefix}__{s.name}" if prefix else s.name] = m
                    bare.setdefault(s.name, m)
            elif isinstance(s, NamespaceDef):
                p = f"{prefix}__{s.name}" if prefix else s.name
                walk(s.functions, p)
                walk(s.nested_namespaces, p)
            elif hasattr(s, 'function_def'):
                walk([s.function_def], prefix)
            elif hasattr(s, 'namespace_def'):
                walk([s.namespace_def], prefix)
    walk(ast.statements, '')
    return full, bare


def dce_roots(ast, unit):
    """Mangled names of every function of a module that sets dce = false."""
    keep = {n for n, i in unit.modules.items() if not i.settings['dce']}
    if not keep:
        return ()
    full, _ = func_modules(ast)
    return tuple(k for k, m in full.items() if m in keep)


def filter_violations(violations, unit, ast, tag):
    """Keep the violations that fall in a module whose check (tag) is on. A violation
    is attributed through its function ('func'); one with no known function is kept."""
    on = checked(unit, tag)
    full, bare = func_modules(ast)
    out = []
    for v in violations:
        fn = getattr(v, 'func', '') or getattr(v, 'caller_name', '') or getattr(v, 'func_name', '')
        mod = full.get(fn) or bare.get(fn.split('__')[-1] if fn else '')
        if mod is None or mod in on:
            out.append(v)
    return out


def checked(unit, tag):
    """Names of the modules whose setting for tag is on."""
    return {n for n, i in unit.modules.items() if i.settings[tag]}