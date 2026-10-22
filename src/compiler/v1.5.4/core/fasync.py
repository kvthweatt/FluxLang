"""
fasync.py - async lowering.

Runs after parsing, DCE and (optionally) the borrow check, before code generation.

The lifetime/footprint analysis in fbc.py decides, for every async call it models as
a task, whether the call may run concurrently with the code around it. This pass turns
the approved calls into thread launches and everything else stays an ordinary call:

    int i = f(a);            ->   int i;
                                  __af_f* __atN = (__af_f*)fmalloc(...);
                                  __atN.joined = 0;  __atN.a0 = a;
                                  thread_create(@__af_f_run, (void*)__atN, @__atN.th);
                                  defer { ffree((u64)__atN); <join>; };   // defer blocks run in reverse: join, then free
                                  ...                       // other work runs meanwhile
                                  <join>                    // inserted before the first use of i

    <join>  =  if (__atN.joined == 0) { thread_join(@__atN.th); i = __atN.r; __atN.joined = 1; };

Relations declared in async tags are enforced here:
    a > b   b waits for a: a join of a is inserted before the call to b
    a ! b   a and b hold one mutex (every function in an exclusive group locks it on entry)
"""

import copy
import sys

import fast
from fast import *
from flexer import FluxLexer
from fparser import FluxParser

_STUBS = ("unsigned data{64} as u64;\n"
          "struct Thread { byte[8] handle; int alive; };\n"
          "struct Mutex { byte[64] storage; };\n")
_TH = "standard::threading::"

# Declarations the lowered code references. No source mentions them before
# lowering, so DCE is told to keep them alive.
RUNTIME_ROOTS = (
    "standard::threading::thread_create",
    "standard::threading::thread_join",
    "standard::threading::mutex_init",
    "standard::threading::mutex_lock",
    "standard::threading::mutex_unlock",
    "standard::threading::Thread",
    "standard::threading::Mutex",
    "standard::memory::allocators::stdheap::fmalloc",
    "standard::memory::allocators::stdheap::ffree",
)


def _parse(text):
    toks = FluxLexer(text).tokenize()
    parser = FluxParser(toks, source_lines=text.splitlines(keepends=True))
    prog = parser.parse()
    return prog.statements


_NSTUB = len(_parse(_STUBS))


def _body_of(stmts, name):
    for s in stmts:
        fd = s.function_def if isinstance(s, FunctionDefStatement) else s
        if isinstance(fd, FunctionDef) and fd.name == name:
            return fd.body.statements
    raise RuntimeError(f"async lowering: synthetic function '{name}' was not produced")


def _children(node):
    if not hasattr(node, '__dict__'):
        return
    for v in list(vars(node).values()):
        if isinstance(v, ASTNode):
            yield v
        elif isinstance(v, (list, tuple)):
            for x in v:
                if isinstance(x, ASTNode):
                    yield x
                elif isinstance(x, (list, tuple)):
                    for y in x:
                        if isinstance(y, ASTNode):
                            yield y


def _mentions(node, name):
    if isinstance(node, Identifier) and node.name == name:
        return True
    return any(_mentions(c, name) for c in _children(node))


def _shallow_calls(node, out):
    """Calls reachable without entering a nested block."""
    if isinstance(node, FunctionCall):
        out.append(node)
    for c in _children(node):
        if not isinstance(c, Block):
            _shallow_calls(c, out)
    return out


class _Task:
    def __init__(self, fv, rv, struct):
        self.fv = fv              # frame variable name
        self.rv = rv              # result variable name or None
        self.struct = struct
        self.joined_at_use = False


class AsyncLowering:
    def __init__(self, program, cg, life):
        self.program = program
        self.cg = cg
        self.life = life
        self.ok = life.async_launched - life.async_seq
        self.analyzed = set(life.summaries)
        self.tasks = {}            # id(call node) -> _Task
        self.frames = {}           # callee key -> (struct name, trampoline name)
        self.counter = 0
        self.launched = 0

    # ------------------------------------------------------------------
    def run(self):
        stmts = self.program.statements
        if not any(isinstance(s, StructDef) and s.name == 'Thread' for s in stmts):
            if self.ok or self._groups():
                sys.stderr.write("[ASYNC] error: async lowering needs the threading library; "
                                 "add #import <threading.fx>;\n")
                sys.exit(1)
        for key in sorted(self.analyzed):
            fd = self.cg.funcs.get(key)
            if fd is not None and fd.body is not None:
                self._block(fd.body)
        self._mutexes()

    # ------------------------------------------------------------------
    # frames: one struct and one trampoline per async callee
    # ------------------------------------------------------------------
    def _frame(self, key, callee_name):
        if key in self.frames:
            return self.frames[key]
        fd = self.cg.funcs[key]
        n = len(self.frames)
        S = f"__af_{n}"
        T = f"__af_{n}_run"
        params = [p for p in (fd.parameters or [])]
        has_ret = not (fd.return_type.base_type == DataType.VOID and not fd.return_type.is_pointer)
        fields = "".join(f"int a{i}; " for i in range(len(params)))
        if has_ret:
            fields += "int r; "
        text = (_STUBS + f"struct {S} {{ {fields}int joined; Thread th; }};\n"
                f"def {T}(void* p) -> void*\n{{\n    {S}* fr = ({S}*)p;\n    "
                + (f"fr.r = " if has_ret else "")
                + f"{callee_name}({', '.join(f'fr.a{i}' for i in range(len(params)))});\n"
                f"    return (void*)0;\n}};\n")
        parsed = _parse(text)
        sdef = next(s for s in parsed if isinstance(s, StructDef) and s.name == S)
        tramp = None
        for s_ in parsed:
            fd_ = s_.function_def if isinstance(s_, FunctionDefStatement) else s_
            if isinstance(fd_, FunctionDef) and fd_.name == T:
                tramp = s_
        if tramp is None:
            raise RuntimeError(f"async lowering: trampoline '{T}' was not produced")
        for m in sdef.members:
            if m.name.startswith('a') and m.name[1:].isdigit():
                m.type_spec = copy.deepcopy(params[int(m.name[1:])].type_spec)
            elif m.name == 'r':
                m.type_spec = copy.deepcopy(fd.return_type)
        self._insert_after_decl(callee_name, [sdef, tramp])
        self.frames[key] = (S, T, has_ret)
        return self.frames[key]

    def _insert_after_decl(self, fname, new):
        stmts = self.program.statements
        for i, s in enumerate(stmts):
            fd = s.function_def if isinstance(s, FunctionDefStatement) else s
            if isinstance(fd, FunctionDef) and fd.name == fname:
                stmts[i + 1:i + 1] = new
                return
        raise RuntimeError(f"async lowering: declaration of '{fname}' not found")

    # ------------------------------------------------------------------
    # statements
    # ------------------------------------------------------------------
    def _launch_of(self, s):
        """(call node, 'expr'|'decl'|'assign') when s launches a task."""
        if isinstance(s, ExpressionStatement):
            e = s.expression
            if isinstance(e, FunctionCall):
                return e, 'expr'
            if isinstance(e, Assignment) and isinstance(e.target, Identifier) \
                    and isinstance(e.value, FunctionCall):
                return e.value, 'assign'
        if isinstance(s, VariableDeclaration) and isinstance(s.initial_value, FunctionCall) \
                and not getattr(s.type_spec, 'is_array', False):
            return s.initial_value, 'decl'
        if isinstance(s, Assignment) and isinstance(s.target, Identifier) \
                and isinstance(s.value, FunctionCall):
            return s.value, 'assign'
        return None

    def _lowerable(self, call):
        if id(call) not in self.ok or not isinstance(call.name, str):
            return None
        key = self.life.async_target.get(id(call))
        if key is None or key not in self.analyzed or key != call.name:
            return None
        fd = self.cg.funcs.get(key)
        if fd is None or fd.is_variadic or fd.calling_conv or fd.error_type is not None:
            return None
        if len(call.arguments or []) != len(fd.parameters or []):
            return None
        return key

    def _join(self, task):
        rv = f"{task.rv} = {task.fv}.r; " if task.rv else ""
        text = (_STUBS + f"def __tj() -> void {{ if ({task.fv}.joined == 0) "
                f"{{ {_TH}thread_join(@{task.fv}.th); {rv}{task.fv}.joined = 1; }}; }};\n")
        return _body_of(_parse(text), '__tj')

    def _block(self, block):
        new = []
        pending = []
        for s in block.statements:
            if s is None:
                new.append(s)
                continue
            pre = []
            for t in pending:
                if t.rv and not t.joined_at_use and _mentions(s, t.rv):
                    pre += self._join(t)
                    t.joined_at_use = True
            for call in _shallow_calls(s, []):
                for uid in self.life.async_waits.get(id(call), ()):
                    u = self.tasks.get(uid)
                    if u is not None:
                        pre += self._join(u)
            launch = self._launch_of(s)
            key = self._lowerable(launch[0]) if launch else None
            if key is not None:
                call, kind = launch
                stmts, task = self._launch(s, call, kind, key)
                self.tasks[id(call)] = task
                pending.append(task)
                new += pre + stmts
                self.launched += 1
            else:
                new += pre + [s]
                for c in _children(s):
                    self._descend(c)
        block.statements = new

    def _descend(self, node):
        if isinstance(node, Block):
            self._block(node)
            return
        for c in _children(node):
            self._descend(c)

    def _launch(self, s, call, kind, key):
        S, T, has_ret = self._frame(key, call.name)
        self.counter += 1
        fv = f"__at{self.counter}"
        rv = None
        out = []
        if kind == 'decl':
            rv = s.name
            s.initial_value = None
            out.append(s)
        elif kind == 'assign':
            tgt = s.target if isinstance(s, Assignment) else s.expression.target
            rv = tgt.name
        if rv is not None and not has_ret:
            rv = None
        args = call.arguments or []
        assigns = "".join(f"    {fv}.a{i} = 0;\n" for i in range(len(args)))
        text = (_STUBS + f"struct {S} {{ int joined; Thread th; }};\n"
                f"def __tl() -> void\n{{\n"
                f"    {S}* {fv} = ({S}*)fmalloc((u64)((sizeof({S}) + 7) / 8));\n"
                f"    {fv}.joined = 0;\n{assigns}"
                f"    {_TH}thread_create(@{T}, (void*){fv}, @{fv}.th);\n"
                f"    defer {{ __DEFER__; }};\n}};\n")
        # the frame struct is only a stub here, the real one already exists
        body = _body_of(_parse(text), '__tl')
        # statements: decl, joined, assigns..., thread_create, defer
        k = 2
        for i, a in enumerate(args):
            st_ = body[k + i]
            (st_.expression if isinstance(st_, ExpressionStatement) else st_).value = a
        defer = body[-1]
        task = _Task(fv, rv, S)
        # Flux runs the statements of a defer block in reverse order, so the
        # free is listed first and the join second: join runs, then free.
        defer.body = _body_of(
            _parse(_STUBS + f"def __tf() -> void {{ ffree((u64){fv}); }};\n"), '__tf') + self._join(task)
        out += body
        return out, task

    # ------------------------------------------------------------------
    # mutual exclusion groups
    # ------------------------------------------------------------------
    def _groups(self):
        parent = {}
        def find(x):
            parent.setdefault(x, x)
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x
        for (a, b), ops in self.life.rel.items():
            if '!' in ops and a in self.cg.funcs and b in self.cg.funcs:
                parent[find(a)] = find(b)
        groups = {}
        for x in list(parent):
            groups.setdefault(find(x), []).append(x)
        return [sorted(v) for v in groups.values()]

    def _mutexes(self):
        groups = self._groups()
        if not groups:
            return
        stmts = self.program.statements
        at = 0
        for i, s in enumerate(stmts):
            if isinstance(s, StructDef) and s.name == 'Mutex':
                at = i + 1
        decls = []
        inits = []
        for gi, members in enumerate(groups):
            m = f"__am_{gi}"
            decls += _parse(_STUBS + f"Mutex {m};\n")[_NSTUB:]
            inits += _body_of(_parse(_STUBS + f"def __ti() -> void {{ {_TH}mutex_init(@{m}); }};\n"), '__ti')
            for key in members:
                fd = self.cg.funcs[key]
                if fd.body is None:
                    continue
                lock = _body_of(_parse(
                    _STUBS + f"def __tk() -> void {{ {_TH}mutex_lock(@{m}); "
                    f"defer {_TH}mutex_unlock(@{m}); }};\n"), '__tk')
                fd.body.statements = lock + fd.body.statements
        stmts[at:at] = decls
        # The init goes in the first candidate that is declared after the mutex
        # globals: the entry function may live in a library that precedes them
        # (FRTStartup), in which case the program's own main is used.
        placed = False
        for name in (self.life.entry, 'main'):
            fd = self.cg.funcs.get(name)
            if fd is None or fd.body is None:
                continue
            pos = next((i for i, s in enumerate(stmts) if s is fd), None)
            if pos is not None and pos >= at + len(decls):
                fd.body.statements = inits + fd.body.statements
                placed = True
                break
        if not placed:
            sys.stderr.write("[ASYNC] error: cannot place mutex initialisation: no entry function "
                             "is declared after the threading library\n")
            sys.exit(1)


def lower_program(ast, entry, line_map, report=True):
    """Analyse, report and lower. Returns the number of calls turned into threads."""
    import fbc
    from fbc_report import print_violations
    cg = fbc.CallGraph()
    cg.collect(ast)
    if not cg.async_names:
        return 0
    life = fbc._LifetimeAnalysis(cg, entry, line_map=line_map, warn_mode=True)
    life.run()
    mine = [v for v in life.violations if v.kind.startswith('async_')]
    if report and mine:
        print_violations(mine, mode='warn', use_color=sys.stderr.isatty(), file=sys.stderr)
    if any(v.kind in fbc.FATAL_KINDS for v in life.violations):
        if not report:
            print_violations([v for v in life.violations if v.kind in fbc.FATAL_KINDS],
                             mode='warn', use_color=sys.stderr.isatty(), file=sys.stderr)
        sys.exit(1)
    return AsyncLowering(ast, cg, life).run()