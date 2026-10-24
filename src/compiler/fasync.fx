// Author: Karac V. Thweatt
//
// fasync.fx - Flux async lowering (port of fasync.py)
//
// Runs after parsing and DCE, before code generation. The lifetime and footprint
// analysis in fborrow.fx decides, for every async call it models as a task, whether
// the call may run concurrently with the code around it. This pass turns the approved
// calls into thread launches; everything else stays an ordinary call:
//
//     int i = f(a);        ->   int i;
//                               __af_0* __at1 = (__af_0*)fmalloc(...);
//                               __at1.joined = 0;  __at1.a0 = a;
//                               thread_create(@__af_0_run, (void*)__at1, @__at1.th);
//                               defer { ffree((u64)__at1); <join>; };
//                               ...                       other work runs meanwhile
//                               <join>                    before the first use of i
//
//     <join> = if (__at1.joined == 0) { thread_join(@__at1.th); i = __at1.r; __at1.joined = 1; };
//
// Relations declared in async tags are enforced here:
//     a > b   b waits for a: a join of a is inserted before the call to b
//     a ! b   a and b hold one mutex, locked on entry to every function of the group
//
// Flux runs the statements of a defer block in reverse order, so the block is
// written free first and join second: the join runs, then the free.

#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_LEXER
#import "flexer.fx";
#endif;

#ifndef FLUX_AST
#import "fast.fx";
#endif;

#ifndef FLUX_PARSER
#import "fparser.fx";
#endif;

#ifndef FLUX_BORROW
#import "fborrow.fx";
#endif;

#ifndef FLUX_ASYNC
#def FLUX_ASYNC 1;

using flux::lexer;
using flux::preprocessor;
using flux::ast;
using flux::parser;
using flux::types;
using flux::borrow;

namespace flux
{
    namespace asyncl
    {
        // synthetic code is parsed with these declarations in front so that the names
        // the lowered code mentions are known types
        def al_stubs() -> byte*
        {
            return g"unsigned data{64} as u64;\nstruct Thread { byte[8] handle; int alive; };\nstruct Mutex { byte[64] storage; };\n\0";
        };

        def al_th() -> byte* -> g"standard::threading::\0";

        // names the lowered code references; DCE must keep them (mangled with __)
        def al_roots() -> PtrVec*
        {
            PtrVec* r = pv_new();
            pv_push(r, (void*)g"standard__threading__thread_create\0");
            pv_push(r, (void*)g"standard__threading__thread_join\0");
            pv_push(r, (void*)g"standard__threading__mutex_init\0");
            pv_push(r, (void*)g"standard__threading__mutex_lock\0");
            pv_push(r, (void*)g"standard__threading__mutex_unlock\0");
            pv_push(r, (void*)g"standard__threading__Thread\0");
            pv_push(r, (void*)g"standard__threading__Mutex\0");
            pv_push(r, (void*)g"standard__memory__allocators__stdheap__fmalloc\0");
            pv_push(r, (void*)g"standard__memory__allocators__stdheap__ffree\0");
            return r;
        };

        // ------------------------------------------------------------------
        // parsing synthetic code
        // ------------------------------------------------------------------

        // Parses text and returns the program. The text, lexer data and parser strings
        // are never freed: the nodes borrow from them.
        def al_parse(byte* text, bool* ok) -> Node*
        {
            byte* src = ts_dup(text);
            int n;
            Node* prog;
            while (src[n] != 0) { n++; };
            Lexer lx(src, n);
            if (!lx.tokenize())
            {
                *ok = false;
                return (Node*)0;
            };
            Parser ps(@lx);
            ps.st = st_new();
            prog = ps.parse();
            if (ps.failed)
            {
                print(g"[ASYNC] internal error: synthetic code did not parse: \0");
                if (ps.err_msg != (byte*)0) { print(ps.err_msg); };
                println(g"\0");
                *ok = false;
                return (Node*)0;
            };
            return prog;
        };

        def al_unwrap(Node* n) -> Node*
        {
            if (n.kind == NodeKind.FUNCTION_DEF_STATEMENT) { return n.a; };
            if (n.kind == NodeKind.STRUCT_DEF_STATEMENT) { return n.a; };
            return n;
        };

        // body statements of the top level function called name, or null
        def al_body_of(Node* prog, byte* name) -> PtrVec*
        {
            int i, j;
            int c = node_count(prog, 0);
            Node* f;
            PtrVec* out;
            while (i < c)
            {
                f = al_unwrap(node_child(prog, 0, i));
                i++;
                if (f.kind == NodeKind.FUNCTION_DEF)
                {
                    if (cstr_eq(f.text, name))
                    {
                        out = pv_new();
                        j = 0;
                        while (j < node_count(f.a, 0))
                        {
                            pv_push(out, (void*)node_child(f.a, 0, j));
                            j++;
                        };
                        return out;
                    };
                };
            };
            return (PtrVec*)0;
        };

        def al_cat(PtrVec* a, PtrVec* b) -> PtrVec*
        {
            PtrVec* r = pv_new();
            int i;
            while (i < a.len) { pv_push(r, a.items[i]); i++; };
            i = 0;
            while (i < b.len) { pv_push(r, b.items[i]); i++; };
            return r;
        };

        // replaces the contents of list slot s with items
        def al_set_list(Node* n, int s, PtrVec* items) -> void
        {
            int i;
            NodeVec* v = node_list(n, s);
            v.len = 0;
            while (i < items.len)
            {
                node_push(n, s, (Node*)items.items[i]);
                i++;
            };
            return;
        };

        def al_block_items(Node* b) -> PtrVec*
        {
            PtrVec* r = pv_new();
            int i;
            int c = node_count(b, 0);
            while (i < c)
            {
                pv_push(r, (void*)node_child(b, 0, i));
                i++;
            };
            return r;
        };

        // true when a node of kind BLOCK
        def al_is_block(Node* n) -> bool -> n.kind == NodeKind.BLOCK;

        // does name occur as an identifier anywhere under node
        def al_mentions(Node* n, byte* name) -> bool
        {
            int s, c, i;
            if (n == (Node*)0) { return false; };
            if (n.kind == NodeKind.IDENTIFIER)
            {
                if (cstr_eq(n.text, name)) { return true; };
            };
            if (al_mentions(n.a, name)) { return true; };
            if (al_mentions(n.b, name)) { return true; };
            if (al_mentions(n.c, name)) { return true; };
            if (al_mentions(n.d, name)) { return true; };
            if (al_mentions(n.e, name)) { return true; };
            while (s < 6)
            {
                c = node_count(n, s);
                i = 0;
                while (i < c)
                {
                    if (al_mentions(node_child(n, s, i), name)) { return true; };
                    i++;
                };
                s++;
            };
            return false;
        };

        // calls reachable without entering a nested block
        def al_shallow_calls(Node* n, PtrVec* out) -> void
        {
            int s, c, i;
            if (n == (Node*)0) { return; };
            if (n.kind == NodeKind.FUNCTION_CALL) { pv_push(out, (void*)n); };
            if (n.a != (Node*)0) { if (!al_is_block(n.a)) { al_shallow_calls(n.a, out); }; };
            if (n.b != (Node*)0) { if (!al_is_block(n.b)) { al_shallow_calls(n.b, out); }; };
            if (n.c != (Node*)0) { if (!al_is_block(n.c)) { al_shallow_calls(n.c, out); }; };
            if (n.d != (Node*)0) { if (!al_is_block(n.d)) { al_shallow_calls(n.d, out); }; };
            if (n.e != (Node*)0) { if (!al_is_block(n.e)) { al_shallow_calls(n.e, out); }; };
            while (s < 6)
            {
                c = node_count(n, s);
                i = 0;
                while (i < c)
                {
                    if (!al_is_block(node_child(n, s, i))) { al_shallow_calls(node_child(n, s, i), out); };
                    i++;
                };
                s++;
            };
            return;
        };

        def al_str_lt(byte* a, byte* b) -> bool
        {
            int i;
            while (a[i] != 0 & b[i] != 0)
            {
                if (a[i] != b[i]) { return a[i] < b[i]; };
                i++;
            };
            return a[i] < b[i];
        };

        def al_sort(PtrVec* v) -> void
        {
            int i = 1;
            int j;
            void* t;
            while (i < v.len)
            {
                j = i;
                while (j > 0)
                {
                    if (!al_str_lt((byte*)v.items[j], (byte*)v.items[j - 1])) { break; };
                    t = v.items[j];
                    v.items[j] = v.items[j - 1];
                    v.items[j - 1] = t;
                    j--;
                };
                i++;
            };
            return;
        };

        // Synthetic nodes take the line of the code they stand in for: the typer hides
        // functions declared on later lines than the call, and the parsed text has lines
        // of its own.
        def al_relines(Node* n, int line) -> void
        {
            int s, c, i;
            if (n == (Node*)0) { return; };
            n.line = line;
            al_relines(n.a, line);
            al_relines(n.b, line);
            al_relines(n.c, line);
            al_relines(n.d, line);
            al_relines(n.e, line);
            while (s < 6)
            {
                c = node_count(n, s);
                i = 0;
                while (i < c)
                {
                    al_relines(node_child(n, s, i), line);
                    i++;
                };
                s++;
            };
            return;
        };

        // half of a pair key "a<0x1f>b" whose separator is at sep
        def al_pair_half(byte* key, int which, int sep) -> byte*
        {
            int n;
            byte* r;
            if (which == 0)
            {
                r = (byte*)fmalloc((u64)(sep + 1));
                while (n < sep) { r[n] = key[n]; n++; };
                r[sep] = (byte)0;
                return r;
            };
            return ts_dup(key + sep + 1);
        };

        // ------------------------------------------------------------------
        // the lowering
        // ------------------------------------------------------------------

        struct AlTask
        {
            byte* fv;           // frame variable name
            byte* rv;           // result variable name or null
            byte* sname;
            bool joined_at_use;
        };

        struct AlFrame
        {
            byte* sname, tname;
            bool has_ret;
        };

        object AsyncLowering
        {
            Node* program;
            CallGraph* cg;
            LifeChecker* life;
            OMap* tasks;        // node key to AlTask*
            OMap* frames;       // callee key to AlFrame*
            int counter, launched, nstub;
            bool failed;
            Buf tb;

            __init(Node* prog, CallGraph* g, LifeChecker* lc) -> this
            {
                bool ok = true;
                Node* sp;
                this.program = prog;
                this.cg = g;
                this.life = lc;
                this.tasks = om_new();
                this.frames = om_new();
                this.counter = 0;
                this.launched = 0;
                this.failed = false;
                this.tb.__init();
                sp = al_parse(al_stubs(), @ok);
                this.nstub = node_count(sp, 0);
                -> this;
            };

            __expr() -> AsyncLowering* -> this;

            __exit() -> void
            {
                -> this.tb.__exit();
            };

            is_ok(Node* call) -> bool
            {
                byte* k = lf_addr_key((void*)call);
                return om_has(this.life.async_launched, k) & !om_has(this.life.async_seq, k);
            };

            any_ok() -> bool
            {
                int i;
                while (i < this.life.async_launched.ks.len)
                {
                    if (!om_has(this.life.async_seq, (byte*)this.life.async_launched.ks.items[i])) { return true; };
                    i++;
                };
                return false;
            };

            // statements of a synthetic function, parsed behind the stubs
            parse_body(byte* text, byte* fname, int line) -> PtrVec*
            {
                bool ok = true;
                Node* prog = al_parse(text, @ok);
                PtrVec* b;
                if (!ok) { this.failed = true; return pv_new(); };
                al_relines(prog, line);
                b = al_body_of(prog, fname);
                if (b == (PtrVec*)0)
                {
                    print(g"[ASYNC] internal error: synthetic function '\0");
                    print(fname);
                    println(g"' was not produced\0");
                    this.failed = true;
                    return pv_new();
                };
                return b;
            };

            run() -> int
            {
                int i;
                bool has_thread;
                int c = node_count(this.program, 0);
                Node* s, fd;
                PtrVec* keys = pv_new();
                if (this.failed) { return -1; };
                i = 0;
                while (i < c)
                {
                    s = al_unwrap(node_child(this.program, 0, i));
                    i++;
                    if (s.kind == NodeKind.STRUCT_DEF)
                    {
                        if (cstr_eq(s.text, g"Thread\0")) { has_thread = true; };
                    };
                };
                if (!has_thread)
                {
                    if (this.any_ok() | this.groups().len > 0)
                    {
                        println(g"[ASYNC] error: async lowering needs the threading library; add #import <threading.fx>;\0");
                        return -1;
                    };
                };
                i = 0;
                while (i < this.life.summaries.count)
                {
                    if (this.life.summaries.vals[i] != (void*)0) { pv_push(keys, (void*)this.life.summaries.keys[i]); };
                    i++;
                };
                al_sort(keys);
                i = 0;
                while (i < keys.len)
                {
                    fd = (Node*)nm_get(this.cg.funcs, (byte*)keys.items[i]);
                    i++;
                    if (fd != (Node*)0)
                    {
                        if (fd.a != (Node*)0)
                        {
                            if (fd.a.kind == NodeKind.BLOCK) { this.block(fd.a); };
                        };
                    };
                };
                if (!this.mutexes()) { return -1; };
                if (this.failed) { return -1; };
                return this.launched;
            };

            // ----- frames: one struct and one trampoline per async callee -----

            frame(byte* key, byte* callee_name) -> AlFrame*
            {
                AlFrame* fr = (AlFrame*)om_get(this.frames, key);
                Node* fd, prog, sdef, tramp, st_, m, fn_;
                int np, i, n, c;
                bool has_ret;
                bool ok = true;
                byte* sname, tname;
                if (fr != (AlFrame*)0) { return fr; };
                fd = (Node*)nm_get(this.cg.funcs, key);
                n = this.frames.ks.len;
                np = node_count(fd, 0);
                has_ret = true;
                if (fd.ts.base_type == DataType.VOID & !bc_is_pointer_type(fd.ts)) { has_ret = false; };

                this.tb.clear();
                this.tb.put_str(f"{al_stubs()}struct __af_{n}\0");
                this.tb.put_str(g" { \0");
                i = 0;
                while (i < np)
                {
                    this.tb.put_str(f"int a{i}; \0");
                    i++;
                };
                if (has_ret) { this.tb.put_str(g"int r; \0"); };
                this.tb.put_str(g"int joined; Thread th; };\ndef __af_\0");
                this.tb.put_int(n);
                this.tb.put_str(g"_run(void* p) -> void*\n{\n    __af_\0");
                this.tb.put_str(f"{n}* fr = (__af_{n}*)p;\n    \0");
                if (has_ret) { this.tb.put_str(g"fr.r = \0"); };
                this.tb.put_str(f"{callee_name}(\0");
                i = 0;
                while (i < np)
                {
                    if (i > 0) { this.tb.put_str(g", \0"); };
                    this.tb.put_str(f"fr.a{i}\0");
                    i++;
                };
                this.tb.put_str(g");\n    return (void*)0;\n};\n\0");
                prog = al_parse(this.tb.mem, @ok);
                if (!ok) { this.failed = true; return (AlFrame*)0; };
                al_relines(prog, fd.line);
                this.tb.clear();
                this.tb.put_str(f"__af_{n}\0");
                sname = ts_dup(this.tb.mem);
                this.tb.put_str(g"_run\0");
                tname = ts_dup(this.tb.mem);
                sdef = (Node*)0;
                tramp = (Node*)0;
                c = node_count(prog, 0);
                i = 0;
                while (i < c)
                {
                    st_ = node_child(prog, 0, i);
                    fn_ = al_unwrap(st_);
                    i++;
                    if (fn_.kind == NodeKind.STRUCT_DEF)
                    {
                        if (cstr_eq(fn_.text, sname)) { sdef = st_; };
                    };
                    if (fn_.kind == NodeKind.FUNCTION_DEF)
                    {
                        if (cstr_eq(fn_.text, tname)) { tramp = st_; };
                    };
                };
                if (sdef == (Node*)0 | tramp == (Node*)0)
                {
                    print(g"[ASYNC] internal error: trampoline '\0");
                    print(tname);
                    println(g"' was not produced\0");
                    this.failed = true;
                    return (AlFrame*)0;
                };
                // member types come from the callee's signature
                c = node_count(al_unwrap(sdef), 0);
                i = 0;
                while (i < c)
                {
                    m = node_child(al_unwrap(sdef), 0, i);
                    i++;
                    if (m.text[0] == 'a' & m.text[1] >= '0' & m.text[1] <= '9')
                    {
                        m.ts = typespec_copy(node_child(fd, 0, lf_atoi(m.text + 1)).ts);
                    };
                    if (m.text[0] == 'r' & m.text[1] == 0)
                    {
                        m.ts = typespec_copy(fd.ts);
                    };
                };
                if (!this.insert_after_decl(callee_name, sdef, tramp)) { this.failed = true; return (AlFrame*)0; };
                fr = (AlFrame*)fmalloc((u64)((sizeof(AlFrame) + 7) / 8));
                fr
                {
                    .sname = sname;
                    .tname = tname;
                    .has_ret = has_ret;
                };
                om_put(this.frames, key, (void*)fr);
                return fr;
            };

            insert_after_decl(byte* fname, Node* a, Node* b) -> bool
            {
                int c = node_count(this.program, 0);
                int i, j;
                Node* f;
                NodeVec* v;
                while (i < c)
                {
                    f = al_unwrap(node_child(this.program, 0, i));
                    if (f.kind == NodeKind.FUNCTION_DEF)
                    {
                        if (cstr_eq(f.text, fname))
                        {
                            node_push(this.program, 0, a);
                            node_push(this.program, 0, b);
                            v = this.program.l0;
                            j = v.len - 1;
                            while (j > i + 2)
                            {
                                v.items[j] = v.items[j - 2];
                                j--;
                            };
                            v.items[i + 1] = a;
                            v.items[i + 2] = b;
                            return true;
                        };
                    };
                    i++;
                };
                print(g"[ASYNC] internal error: declaration of '\0");
                print(fname);
                println(g"' not found\0");
                return false;
            };

            // ----- statements -----

            // the call a statement launches, and how: 1 expression, 2 declaration, 3 assignment
            launch_of(Node* s, int* kind) -> Node*
            {
                Node* e;
                if (s.kind == NodeKind.EXPRESSION_STATEMENT)
                {
                    e = s.a;
                    if (e.kind == NodeKind.FUNCTION_CALL) { *kind = 1; return e; };
                    if (e.kind == NodeKind.ASSIGNMENT)
                    {
                        if (e.a.kind == NodeKind.IDENTIFIER & e.b.kind == NodeKind.FUNCTION_CALL)
                        {
                            *kind = 3;
                            return e.b;
                        };
                    };
                };
                if (s.kind == NodeKind.VARIABLE_DECLARATION)
                {
                    if (s.a != (Node*)0)
                    {
                        if (s.a.kind == NodeKind.FUNCTION_CALL)
                        {
                            if (s.ts == (TypeSpec*)0) { *kind = 2; return s.a; };
                            if ((s.ts.flags `& TS_ARRAY) == 0) { *kind = 2; return s.a; };
                        };
                    };
                };
                if (s.kind == NodeKind.ASSIGNMENT)
                {
                    if (s.a.kind == NodeKind.IDENTIFIER & s.b.kind == NodeKind.FUNCTION_CALL)
                    {
                        *kind = 3;
                        return s.b;
                    };
                };
                return (Node*)0;
            };

            lowerable(Node* call) -> byte*
            {
                byte* key;
                Node* fd;
                if (!this.is_ok(call)) { return (byte*)0; };
                if (call.text == (byte*)0) { return (byte*)0; };
                key = (byte*)om_get(this.life.async_target, lf_addr_key((void*)call));
                if (key == (byte*)0) { return (byte*)0; };
                if (!nm_has(this.life.summaries, key)) { return (byte*)0; };
                if (!cstr_eq(key, call.text)) { return (byte*)0; };
                fd = (Node*)nm_get(this.cg.funcs, key);
                if (fd == (Node*)0) { return (byte*)0; };
                if ((fd.flags `& NF_VARIADIC) != 0) { return (byte*)0; };
                if (fd.text2 != (byte*)0)
                {
                    if (fd.text2[0] != 0) { return (byte*)0; };
                };
                if (fd.ts2 != (TypeSpec*)0) { return (byte*)0; };
                if (node_count(call, 0) != node_count(fd, 0)) { return (byte*)0; };
                return key;
            };

            // statements that wait for a task
            join(AlTask* t, int line) -> PtrVec*
            {
                this.tb.clear();
                this.tb.put_str(al_stubs());
                this.tb.put_str(g"def __tj() -> void { if (\0");
                this.tb.put_str(t.fv);
                this.tb.put_str(g".joined == 0) { \0");
                this.tb.put_str(f"{al_th()}thread_join(@{t.fv}.th); \0");
                if (t.rv != (byte*)0)
                {
                    this.tb.put_str(f"{t.rv} = {t.fv}.r; \0");
                };
                this.tb.put_str(t.fv);
                this.tb.put_str(g".joined = 1; }; };\n\0");
                return this.parse_body(this.tb.mem, g"__tj\0", line);
            };

            block(Node* blk) -> void
            {
                PtrVec* old = al_block_items(blk);
                PtrVec* fresh = pv_new();
                PtrVec* pending = pv_new();
                PtrVec* pre, calls, stmts, waits;
                int si, i, j, kind;
                Node* s, call;
                byte* key;
                AlTask* t, u;
                while (si < old.len)
                {
                    s = (Node*)old.items[si];
                    si++;
                    if (s == (Node*)0) { pv_push(fresh, (void*)s); continue; };
                    pre = pv_new();
                    i = 0;
                    while (i < pending.len)
                    {
                        t = (AlTask*)pending.items[i];
                        i++;
                        if (t.rv != (byte*)0 & !t.joined_at_use)
                        {
                            if (al_mentions(s, t.rv))
                            {
                                pre = al_cat(pre, this.join(t, s.line));
                                t.joined_at_use = true;
                            };
                        };
                    };
                    calls = pv_new();
                    al_shallow_calls(s, calls);
                    i = 0;
                    while (i < calls.len)
                    {
                        call = (Node*)calls.items[i];
                        i++;
                        waits = (PtrVec*)om_get(this.life.async_waits, lf_addr_key((void*)call));
                        if (waits != (PtrVec*)0)
                        {
                            j = 0;
                            while (j < waits.len)
                            {
                                u = (AlTask*)om_get(this.tasks, (byte*)waits.items[j]);
                                j++;
                                if (u != (AlTask*)0) { pre = al_cat(pre, this.join(u, s.line)); };
                            };
                        };
                    };
                    kind = 0;
                    call = this.launch_of(s, @kind);
                    key = (byte*)0;
                    if (call != (Node*)0) { key = this.lowerable(call); };
                    if (key != (byte*)0)
                    {
                        stmts = pv_new();
                        t = this.launch(s, call, kind, key, stmts);
                        if (t == (AlTask*)0) { return; };
                        om_put(this.tasks, lf_addr_key((void*)call), (void*)t);
                        pv_push(pending, (void*)t);
                        fresh = al_cat(fresh, al_cat(pre, stmts));
                        this.launched++;
                    }
                    else
                    {
                        fresh = al_cat(fresh, pre);
                        pv_push(fresh, (void*)s);
                        this.descend_children(s);
                    };
                };
                al_set_list(blk, 0, fresh);
                return;
            };

            descend_children(Node* n) -> void
            {
                int s, c, i;
                if (n.a != (Node*)0) { this.descend(n.a); };
                if (n.b != (Node*)0) { this.descend(n.b); };
                if (n.c != (Node*)0) { this.descend(n.c); };
                if (n.d != (Node*)0) { this.descend(n.d); };
                if (n.e != (Node*)0) { this.descend(n.e); };
                while (s < 6)
                {
                    c = node_count(n, s);
                    i = 0;
                    while (i < c)
                    {
                        this.descend(node_child(n, s, i));
                        i++;
                    };
                    s++;
                };
                return;
            };

            descend(Node* n) -> void
            {
                if (n == (Node*)0) { return; };
                if (n.kind == NodeKind.BLOCK)
                {
                    this.block(n);
                    return;
                };
                this.descend_children(n);
                return;
            };

            // statements that start the call on a thread; returns the task
            launch(Node* s, Node* call, int kind, byte* key, PtrVec* out) -> AlTask*
            {
                AlFrame* fr = this.frame(key, call.text);
                AlTask* task;
                PtrVec* body, fs;
                byte* fv, rv;
                Node* tgt, st_, asg, defer_;
                int n = node_count(call, 0);
                int i;
                if (fr == (AlFrame*)0) { return (AlTask*)0; };
                this.counter++;
                this.tb.clear();
                this.tb.put_str(f"__at{this.counter}\0");
                fv = ts_dup(this.tb.mem);
                if (kind == 2)
                {
                    rv = s.text;
                    s.a = (Node*)0;
                    pv_push(out, (void*)s);
                };
                if (kind == 3)
                {
                    tgt = s.a;
                    if (s.kind == NodeKind.EXPRESSION_STATEMENT) { tgt = s.a.a; };
                    rv = tgt.text;
                };
                if (rv != (byte*)0 & !fr.has_ret) { rv = (byte*)0; };

                this.tb.clear();
                this.tb.put_str(f"{al_stubs()}struct {fr.sname}\0");
                this.tb.put_str(g" { int joined; Thread th; };\ndef __tl() -> void\n{\n    \0");
                this.tb.put_str(f"{fr.sname}* {fv} = ({fr.sname}*)fmalloc((u64)((sizeof({fr.sname}) + 7) / 8));\n    {fv}.joined = 0;\n\0");
                i = 0;
                while (i < n)
                {
                    this.tb.put_str(f"    {fv}.a{i} = 0;\n\0");
                    i++;
                };
                this.tb.put_str(f"    {al_th()}thread_create(@{fr.tname}, (void*){fv}, @{fv}\0");
                this.tb.put_str(g".th);\n    defer { __DEFER__; };\n};\n\0");
                body = this.parse_body(this.tb.mem, g"__tl\0", s.line);
                if (this.failed) { return (AlTask*)0; };
                // body: decl, joined, assigns..., thread_create, defer
                i = 0;
                while (i < n)
                {
                    st_ = (Node*)body.items[2 + i];
                    asg = st_;
                    if (st_.kind == NodeKind.EXPRESSION_STATEMENT) { asg = st_.a; };
                    asg.b = node_child(call, 0, i);
                    i++;
                };
                defer_ = (Node*)body.items[body.len - 1];
                task = (AlTask*)fmalloc((u64)((sizeof(AlTask) + 7) / 8));
                task
                {
                    .fv = fv;
                    .rv = rv;
                    .sname = fr.sname;
                    .joined_at_use = false;
                };
                this.tb.clear();
                this.tb.put_str(al_stubs());
                this.tb.put_str(g"def __tf() -> void { ffree((u64)\0");
                this.tb.put_str(fv);
                this.tb.put_str(g"); };\n\0");
                fs = this.parse_body(this.tb.mem, g"__tf\0", s.line);
                if (this.failed) { return (AlTask*)0; };
                al_set_list(defer_, 0, al_cat(fs, this.join(task, s.line)));
                i = 0;
                while (i < body.len) { pv_push(out, body.items[i]); i++; };
                return task;
            };

            // ----- mutual exclusion groups -----

            uf_find(OMap* parent, byte* x) -> byte*
            {
                byte* p;
                byte* cur = x;
                if (!om_has(parent, cur)) { om_put(parent, cur, (void*)cur); };
                p = (byte*)om_get(parent, cur);
                while (!cstr_eq(p, cur))
                {
                    cur = p;
                    p = (byte*)om_get(parent, cur);
                };
                return cur;
            };

            // groups of functions that exclude one another: PtrVec of PtrVec* of byte*, members sorted
            groups() -> PtrVec*
            {
                OMap* parent = om_new();
                OMap* bucket = om_new();
                PtrVec* out = pv_new();
                int i, sep;
                byte* a, b, key, r;
                PtrVec* lst;
                int* bits;
                OMap* rel = this.life.rel;
                while (i < rel.ks.len)
                {
                    key = (byte*)rel.ks.items[i];
                    bits = (int*)rel.vs.items[i];
                    i++;
                    if ((bits[0] `& LA_OP_EXCL) == 0) { continue; };
                    sep = 0;
                    while (key[sep] != 0 & key[sep] != 31) { sep++; };
                    a = al_pair_half(key, 0, sep);
                    b = al_pair_half(key, 1, sep);
                    if (!nm_has(this.cg.funcs, a) | !nm_has(this.cg.funcs, b)) { continue; };
                    r = this.uf_find(parent, b);
                    om_put(parent, this.uf_find(parent, a), (void*)r);
                };
                i = 0;
                while (i < parent.ks.len)
                {
                    r = this.uf_find(parent, (byte*)parent.ks.items[i]);
                    lst = (PtrVec*)om_get(bucket, r);
                    if (lst == (PtrVec*)0)
                    {
                        lst = pv_new();
                        om_put(bucket, r, (void*)lst);
                        pv_push(out, (void*)lst);
                    };
                    pv_push(lst, parent.ks.items[i]);
                    i++;
                };
                i = 0;
                while (i < out.len)
                {
                    al_sort((PtrVec*)out.items[i]);
                    i++;
                };
                return out;
            };

            mutexes() -> bool
            {
                PtrVec* grps = this.groups();
                PtrVec* decls = pv_new();
                PtrVec* inits = pv_new();
                PtrVec* members, lock;
                int gi, at, i, k, c, pos, pass;
                Node* s, fd, prog;
                bool ok = true;
                byte* m, nm_;
                bool placed;
                int mline = 1;
                int eline = 1;
                if (grps.len == 0) { return true; };
                c = node_count(this.program, 0);
                i = 0;
                while (i < c)
                {
                    s = al_unwrap(node_child(this.program, 0, i));
                    if (s.kind == NodeKind.STRUCT_DEF)
                    {
                        if (cstr_eq(s.text, g"Mutex\0")) { at = i + 1; mline = s.line; };
                    };
                    i++;
                };
                while (gi < grps.len)
                {
                    members = (PtrVec*)grps.items[gi];
                    this.tb.clear();
                    this.tb.put_str(f"__am_{gi}\0");
                    m = ts_dup(this.tb.mem);
                    // the global
                    this.tb.clear();
                    this.tb.put_str(f"{al_stubs()}Mutex {m};\n\0");
                    prog = al_parse(this.tb.mem, @ok);
                    if (!ok) { return false; };
                    al_relines(prog, mline);
                    i = this.nstub;
                    while (i < node_count(prog, 0))
                    {
                        pv_push(decls, (void*)node_child(prog, 0, i));
                        i++;
                    };
                    // the init
                    this.tb.clear();
                    this.tb.put_str(al_stubs());
                    this.tb.put_str(g"def __ti() -> void { \0");
                    this.tb.put_str(f"{al_th()}mutex_init(@{m}\0");
                    this.tb.put_str(g"); };\n\0");
                    inits = al_cat(inits, this.parse_body(this.tb.mem, g"__ti\0", eline));
                    k = 0;
                    while (k < members.len)
                    {
                        fd = (Node*)nm_get(this.cg.funcs, (byte*)members.items[k]);
                        k++;
                        if (fd == (Node*)0) { continue; };
                        if (fd.a == (Node*)0) { continue; };
                        this.tb.clear();
                        this.tb.put_str(al_stubs());
                        this.tb.put_str(g"def __tk() -> void { \0");
                        this.tb.put_str(f"{al_th()}mutex_lock(@{m}); defer {al_th()}mutex_unlock(@{m}\0");
                        this.tb.put_str(g"); };\n\0");
                        lock = this.parse_body(this.tb.mem, g"__tk\0", fd.line);
                        if (this.failed) { return false; };
                        al_set_list(fd.a, 0, al_cat(lock, al_block_items(fd.a)));
                    };
                    gi++;
                };
                // insert the globals after the Mutex struct
                {
                    NodeVec* v;
                    int n0 = node_count(this.program, 0);
                    int d;
                    d = 0;
                    while (d < decls.len)
                    {
                        node_push(this.program, 0, (Node*)decls.items[d]);
                        d++;
                    };
                    v = this.program.l0;
                    // rotate the appended globals into position at
                    {
                        int j = n0 - 1;
                        while (j >= at)
                        {
                            v.items[j + decls.len] = v.items[j];
                            j--;
                        };
                        d = 0;
                        while (d < decls.len)
                        {
                            v.items[at + d] = (Node*)decls.items[d];
                            d++;
                        };
                    };
                };
                // The init goes in the first candidate declared after the mutex globals:
                // the entry function may live in a library that precedes them
                // (FRTStartup), in which case the program's own main is used.
                pass = 0;
                while (pass < 2 & !placed)
                {
                    nm_ = this.life.entry;
                    if (pass == 1) { nm_ = g"main\0"; };
                    pass++;
                    fd = (Node*)nm_get(this.cg.funcs, nm_);
                    if (fd == (Node*)0) { continue; };
                    if (fd.a == (Node*)0) { continue; };
                    pos = -1;
                    i = 0;
                    c = node_count(this.program, 0);
                    while (i < c)
                    {
                        if (al_unwrap(node_child(this.program, 0, i)) == fd) { pos = i; };
                        i++;
                    };
                    if (pos >= 0 & pos >= at + decls.len)
                    {
                        i = 0;
                        while (i < inits.len)
                        {
                            al_relines((Node*)inits.items[i], fd.line);
                            i++;
                        };
                        al_set_list(fd.a, 0, al_cat(inits, al_block_items(fd.a)));
                        placed = true;
                    };
                };
                if (!placed)
                {
                    println(g"[ASYNC] error: cannot place mutex initialisation: no entry function is declared after the threading library\0");
                    return false;
                };
                return true;
            };
        };

        // Analyse, report and lower. Returns the number of calls turned into threads,
        // or -1 when the program is rejected.
        def lower_program(Node* prog, byte* entry, Preprocessor* pp, bool report) -> int
        {
            CallGraph cg;
            cg.__init();
            defer cg.__exit();
            cg.collect(prog);
            if (cg.async_names.count == 0) { return 0; };
            LifeChecker lc;
            lc.__init(@cg, entry, pp, true);
            defer lc.__exit();
            lc.run();
            PtrVec* mine = pv_new();
            PtrVec* fatal = pv_new();
            defer pv_free(mine);
            defer pv_free(fatal);
            int i;
            BVio* v;
            while (i < lc.violations.len)
            {
                v = (BVio*)lc.violations.items[i];
                if (bc_starts(v.kind, g"async_\0")) { pv_push(mine, (void*)v); };
                if (cstr_eq(v.kind, g"async_contradiction\0")) { pv_push(fatal, (void*)v); };
                i++;
            };
            if (report & mine.len > 0) { bc_print_violations(mine, true); };
            if (fatal.len > 0)
            {
                if (!report) { bc_print_violations(fatal, true); };
                return -1;
            };
            AsyncLowering al(prog, @cg, @lc);
            defer al.__exit();
            return al.run();
        };

        // true when some function in the program is declared async
        def program_has_async(Node* prog) -> bool
        {
            CallGraph cg;
            cg.__init();
            cg.collect(prog);
            return cg.async_names.count > 0;
        };
    };
};

#endif;
