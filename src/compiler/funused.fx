// Author: Karac V. Thweatt
//
// funused.fx - Flux unused variable warnings (port of funused.py)
//
// Runs on the AST produced by the parser before code generation and warns about
// local variables that are declared and never referenced.
//
// A reference is any use of the name: a read, an assignment target, an address-of,
// a call through it or a $name stringify. A name resolves to the innermost enclosing
// declaration. Not reported:
//   - names starting with an underscore
//   - globals and singinit variables
//   - object instances built by a constructor call (the constructor runs anyway)
//   - 'from' recasts (they invalidate their source)
//   - code that comes from the standard library

#ifndef FLUX_AST
#import "fast.fx";
#endif;

#ifndef FLUX_TYPES
#import "ftypesys.fx";
#endif;

#ifndef FLUX_ERRORS
#import "ferrors.fx";
#endif;

#ifndef FLUX_UNUSED
#def FLUX_UNUSED 1;

using flux::ast;
using flux::preprocessor;
using flux::types;

namespace flux
{
    namespace unused
    {
        struct FuEnt
        {
            byte* name;
            Node* node;
            bool used;
        };

        struct FuState
        {
            PtrVec* scopes;        // PtrVec* of FuEnt*, innermost last
            PtrVec* found;         // FuEnt* of unused variables
            byte* src;
            int n;
            int* lmap;
            int lmapn;
            byte** lfiles;
            bool color;
        };

        fu_push(FuState* st) -> void
        {
            pv_push(st.scopes, (void*)pv_new());
        };

        fu_pop(FuState* st) -> void
        {
            PtrVec* sc = (PtrVec*)st.scopes.items[st.scopes.len - 1];
            FuEnt* e;
            int i;
            st.scopes.len = st.scopes.len - 1;
            while (i < sc.len)
            {
                e = (FuEnt*)sc.items[i];
                // an unused entry moves to the report list, which owns it from here
                if (!e.used) { pv_push(st.found, (void*)e); }
                else { ffree((byte*)e); };
                i++;
            };
            pv_free(sc);
        };

        fu_use(FuState* st, byte* name) -> void
        {
            PtrVec* sc;
            FuEnt* e;
            int s = st.scopes.len - 1;
            int i;
            if (name == (byte*)0) { ->; };
            while (s >= 0)
            {
                sc = (PtrVec*)st.scopes.items[s];
                i = 0;
                while (i < sc.len)
                {
                    e = (FuEnt*)sc.items[i];
                    if (cstr_eq(e.name, name))
                    {
                        e.used = true;
                        ->;
                    };
                    i++;
                };
                s--;
            };
        };

        fu_ends_with(byte* s, byte* suffix) -> bool
        {
            int n = 0;
            int m = 0;
            int i;
            while (s[n] != 0) { n++; };
            while (suffix[m] != 0) { m++; };
            if (m > n) { -> false; };
            while (i < m)
            {
                if (s[n - m + i] != suffix[i]) { -> false; };
                i++;
            };
            -> true;
        };

        fu_declare(FuState* st, Node* d) -> void
        {
            PtrVec* sc;
            FuEnt* e;
            if (st.scopes.len == 0) { ->; };
            if ((d.flags `& NF_GLOBAL) != 0) { ->; };
            if (d.text == (byte*)0) { ->; };
            if (d.text[0] == 0 | d.text[0] == '_') { ->; };
            if (d.ts != (TypeSpec*)0)
            {
                if (d.ts.storage_class == StorageClass.GLOBAL | d.ts.storage_class == StorageClass.SINGINIT) { ->; };
            };
            if (d.a != (Node*)0)
            {
                if (d.a.kind == NodeKind.STRUCT_RECAST) { ->; };
                if (d.a.kind == NodeKind.FUNCTION_CALL)
                {
                    if (d.a.text != (byte*)0)
                    {
                        if (fu_ends_with(d.a.text, ".__init\0")) { ->; };
                    };
                };
            };
            e = (FuEnt*)fmalloc((u64)((sizeof(FuEnt) + 7) / 8));
            e.name = d.text;
            e.node = d;
            e.used = false;
            sc = (PtrVec*)st.scopes.items[st.scopes.len - 1];
            pv_push(sc, (void*)e);
            ->;
        };

        def fu_walk(FuState* st, Node* n) -> void;

        fu_walk_list(FuState* st, Node* n, int s) -> void
        {
            int c = node_count(n, s);
            int i;
            while (i < c)
            {
                fu_walk(st, node_child(n, s, i));
                i++;
            };
        };

        // Operands of inline asm are named only inside the constraint text: "r"(name)
        fu_asm_operands(FuState* st, byte* c) -> void
        {
            int i, a, b;
            byte sv;
            if (c == (byte*)0) { ->; };
            while (c[i] != (byte)0)
            {
                if (c[i] == (byte)34)
                {
                    i++;
                    while (c[i] != (byte)0 & c[i] != (byte)34) { i++; };
                    if (c[i] == (byte)34) { i++; };
                    while (c[i] == (byte)32) { i++; };
                    if (c[i] == (byte)40)
                    {
                        i++;
                        a = i;
                        while (c[i] != (byte)0 & c[i] != (byte)41) { i++; };
                        b = i;
                        while (a < b & c[a] == (byte)32) { a++; };
                        while (b > a & c[b - 1] == (byte)32) { b--; };
                        sv = c[b];
                        c[b] = (byte)0;
                        fu_use(st, @c[a]);
                        c[b] = sv;
                    };
                }
                else { i++; };
            };
            ->;
        };

        fu_walk(FuState* st, Node* n) -> void
        {
            int k, s;
            bool scoped;
            PtrVec* saved;
            if (n == (Node*)0) { ->; };
            k = n.kind;
            if (k == NodeKind.FUNCTION_DEF)
            {
                saved = st.scopes;
                st.scopes = pv_new();
                fu_push(st);
                fu_walk_list(st, n, 0);
                fu_walk(st, n.a);
                fu_pop(st);
                pv_free(st.scopes);
                st.scopes = saved;
                ->;
            };
            if (k == NodeKind.VARIABLE_DECLARATION)
            {
                fu_walk(st, n.a);
                fu_declare(st, n);
                ->;
            };
            if (k == NodeKind.IDENTIFIER | k == NodeKind.STRINGIFY)
            {
                fu_use(st, n.text);
                ->;
            };
            if (k == NodeKind.INLINE_ASM)
            {
                fu_asm_operands(st, n.text2);
                ->;
            };
            scoped = false;
            if (st.scopes.len > 0)
            {
                if (k == NodeKind.BLOCK | k == NodeKind.FOR_LOOP | k == NodeKind.FOR_IN_LOOP) { scoped = true; };
            };
            if (scoped) { fu_push(st); };
            if (k == NodeKind.FUNCTION_CALL) { fu_use(st, n.text); };
            fu_walk(st, n.a);
            fu_walk(st, n.b);
            fu_walk(st, n.c);
            fu_walk(st, n.d);
            fu_walk(st, n.e);
            s = 0;
            while (s < 6)
            {
                // a for-in loop's l0 names the loop variables, which are not references
                if (!(k == NodeKind.FOR_IN_LOOP & s == 0)) { fu_walk_list(st, n, s); };
                s++;
            };
            if (scoped) { fu_pop(st); };
            ->;
        };

        fu_is_stdlib(byte* path) -> bool
        {
            int i = 0;
            int seg = 0;
            int j;
            byte* want = "stdlib\0";
            if (path == (byte*)0) { -> false; };
            while (true)
            {
                // path[seg .. i) is one segment
                i = seg;
                while (path[i] != 0 & path[i] != '/' & path[i] != 92) { i++; };
                if (i - seg == 6)
                {
                    j = 0;
                    while (j < 6)
                    {
                        if (path[seg + j] != want[j]) { break; };
                        j++;
                    };
                    if (j == 6) { -> true; };
                };
                if (path[i] == 0) { break; };
                seg = i + 1;
            };
            -> false;
        };

        fu_ident_char(byte c) -> bool
        {
            -> (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z') | (c >= '0' & c <= '9') | c == '_';
        };

        // Column of the first standalone occurrence of name at or after col (1 based) on a line, else col
        fu_name_col(FuState* st, int line, int col, byte* name) -> int
        {
            int ls, le, nl, i, j;
            bool ok;
            if (!flux::errors::line_bounds(st.src, st.n, line, @ls, @le)) { -> col; };
            while (name[nl] != 0) { nl++; };
            i = ls;
            if (col > 1) { i = ls + col - 1; };
            while (i + nl <= le)
            {
                ok = true;
                j = 0;
                while (j < nl)
                {
                    if (st.src[i + j] != name[j]) { ok = false; break; };
                    j++;
                };
                if (ok)
                {
                    if (i > ls) { if (fu_ident_char(st.src[i - 1])) { ok = false; }; };
                    if (i + nl < le) { if (fu_ident_char(st.src[i + nl])) { ok = false; }; };
                };
                if (ok) { -> i - ls + 1; };
                i++;
            };
            -> col;
        };

        // Prints a warning for every unused local variable. Returns how many were reported.
        unused_warnings(Node* prog, byte* src, int n, int* lmap, int lmapn, byte** lfiles, bool color) -> int
        {
            FuState st;
            FuEnt* a;
            FuEnt* b;
            PtrVec* rep = pv_new();
            PtrVec* keys = pv_new();
            Buf mb, wb, kb;
            int i, j, col, ll, cnt;
            byte* fl;
            st.scopes = pv_new();
            st.found = pv_new();
            st.src = src;
            st.n = n;
            st.lmap = lmap;
            st.lmapn = lmapn;
            st.lfiles = lfiles;
            st.color = color;
            fu_walk_list(@st, prog, 0);
            // order by source position (insertion sort keeps equal positions in discovery order)
            i = 1;
            while (i < st.found.len)
            {
                a = (FuEnt*)st.found.items[i];
                j = i - 1;
                while (j >= 0)
                {
                    b = (FuEnt*)st.found.items[j];
                    if (b.node.line > a.node.line | (b.node.line == a.node.line & b.node.col > a.node.col))
                    {
                        st.found.items[j + 1] = st.found.items[j];
                        j--;
                    }
                    else { break; };
                };
                st.found.items[j + 1] = (void*)a;
                i++;
            };
            kb.__init();
            defer kb.__exit();
            i = 0;
            while (i < st.found.len)
            {
                a = (FuEnt*)st.found.items[i];
                i++;
                fl = (byte*)0;
                ll = a.node.line;
                if (lfiles != (byte**)0 & a.node.line >= 1 & a.node.line <= lmapn) { fl = lfiles[a.node.line - 1]; };
                if (lmap != (int*)0 & a.node.line >= 1 & a.node.line <= lmapn) { ll = lmap[a.node.line - 1]; };
                if (fu_is_stdlib(fl)) { continue; };
                kb.clear();
                if (fl != (byte*)0) { kb.put_str(fl); };
                kb.put_str("|\0");
                kb.put_int(ll);
                kb.put_str("|\0");
                kb.put_int(a.node.col);
                kb.put_str("|\0");
                kb.put_str(a.name);
                j = 0;
                cnt = 0;
                while (j < keys.len)
                {
                    if (cstr_eq((byte*)keys.items[j], kb.mem)) { cnt = 1; };
                    j++;
                };
                if (cnt == 1) { continue; };
                pv_push(keys, (void*)ts_dup(kb.mem));
                pv_push(rep, (void*)a);
            };
            i = 0;
            while (i < rep.len)
            {
                a = (FuEnt*)rep.items[i];
                i++;
                col = fu_name_col(@st, a.node.line, a.node.col, a.name);
                mb.__init();
                wb.__init();
                mb.put_str("Warning: unused variable '\0");
                mb.put_str(a.name);
                mb.put_str("'\0");
                flux::errors::render(@wb, color, flux::errors::SEV_WARNING, mb.mem, a.node.line, col, src, n, lmap, lmapn, lfiles, -1, 0, 0, 0, (byte*)0);
                println(wb.mem);
                mb.__exit();
                wb.__exit();
            };
            cnt = rep.len;
            i = 0;
            while (i < st.found.len)
            {
                ffree((byte*)st.found.items[i]);
                i++;
            };
            i = 0;
            while (i < keys.len)
            {
                ffree((byte*)keys.items[i]);
                i++;
            };
            pv_free(st.found);
            pv_free(st.scopes);
            pv_free(keys);
            pv_free(rep);
            -> cnt;
        };
    };
};

#endif;
