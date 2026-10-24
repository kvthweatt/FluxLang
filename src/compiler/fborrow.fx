// Author: Karac V. Thweatt
//
// fborrow.fx - Flux borrow checker (port of fbc.py, fbc_alias.py and fbc_report.py)
//
// Runs on the parsed, DCE pruned AST. Pointer variables are tracked with the
// allocation site they refer to; violations are collected, never raised, so the
// whole program is always walked. The walk, the site naming and the violation
// texts follow fbc.py exactly. Behaviour that fbc.py gets from the FVM
// (_resolve_site_via_fvm, _eval_index_via_fvm, _resolve_fptr_expr) takes the same
// path fbc.py takes when the FVM is not available: the result is "unknown" or
// not determinable. Only integer literal sizes and indices are evaluated.
//
// Site names:
//   stack:<func>:<var>@<line>   stack variable
//   heap:<func>:<line>          fmalloc call site
//   param:<func>:<param>        pointer parameter without a caller supplied site
//   derived:<site>              pointer arithmetic or cast result
//   freed:<site>                pointer read after its site was freed
//   unknown                     could not be resolved

#ifndef FLUX_AST
#import g"fast.fx";
#endif;

#ifndef FLUX_TYPES
#import g"ftypesys.fx";
#endif;

#ifndef FLUX_LEXER
#import g"flexer.fx";
#endif;

#ifndef FLUX_BORROW
#def FLUX_BORROW 1;

using flux::ast;
using flux::preprocessor;
using flux::types;
using flux::lexer;

namespace flux
{
    namespace borrow
    {
        // ------------------------------------------------------------------
        // String helpers
        // ------------------------------------------------------------------

        def bc_len(byte* s) -> int
        {
            int n = 0;
            while (s[n] != 0) { n++; };
            return n;
        };

        def bc_starts(byte* s, byte* p) -> bool
        {
            int i = 0;
            while (p[i] != 0)
            {
                if (s[i] != p[i]) { return false; };
                i++;
            };
            return true;
        };

        def bc_ends(byte* s, byte* suf) -> bool
        {
            int ls = bc_len(s);
            int lf = bc_len(suf);
            if (lf > ls) { return false; };
            return cstr_eq(s + (ls - lf), suf);
        };

        def bc_lower(int c) -> int
        {
            if (c >= 65 & c <= 90) { return c + 32; };
            return c;
        };

        // Case insensitive substring test, needle is lower case
        def bc_has_ci(byte* s, byte* needle) -> bool
        {
            int i = 0;
            int j;
            bool hit;
            while (s[i] != 0)
            {
                j = 0;
                hit = true;
                while (needle[j] != 0)
                {
                    if (bc_lower((int)s[i + j]) != (int)needle[j])
                    {
                        hit = false;
                        break;
                    };
                    j++;
                };
                if (hit) { return true; };
                i++;
            };
            return false;
        };

        // Text after the last "__" found scanning left to right, as str.split('__')[-1]
        def bc_last_seg(byte* s) -> byte*
        {
            int i = 0;
            int start = 0;
            while (s[i] != 0)
            {
                if (s[i] == '_' & s[i + 1] == '_')
                {
                    start = i + 2;
                    i = i + 2;
                }
                else
                {
                    i++;
                };
            };
            return ts_dup(s + start);
        };

        // Text before the first all digit "__" part, the whole string when there is none.
        // Mirrors the base name computation of CallGraph.collect.
        def bc_overload_base(byte* s) -> byte*
        {
            int start = 0;
            int j;
            bool digits;
            int pend;
            byte* r;
            // parts are s[start .. end) separated by "__"
            while (true)
            {
                pend = start;
                while (s[pend] != 0)
                {
                    if (s[pend] == '_' & s[pend + 1] == '_') { break; };
                    pend++;
                };
                digits = pend > start;
                j = start;
                while (j < pend)
                {
                    if (s[j] < '0' | s[j] > '9') { digits = false; };
                    j++;
                };
                if (digits)
                {
                    if (start == 0) { return ts_dup(g"\0"); };
                    r = (byte*)fmalloc((u64)(start - 2 + 1));
                    j = 0;
                    while (j < start - 2)
                    {
                        r[j] = s[j];
                        j++;
                    };
                    r[start - 2] = (byte)0;
                    return r;
                };
                if (s[pend] == 0) { break; };
                start = pend + 2;
            };
            return ts_dup(s);
        };

        // The number in the first all-digit "__" segment of a mangled name, -1 when absent
        def bc_mangled_arity(byte* s) -> int
        {
            int start = 0;
            int pend;
            int j;
            int v;
            bool digits;
            while (true)
            {
                pend = start;
                while (s[pend] != 0)
                {
                    if (s[pend] == '_' & s[pend + 1] == '_') { break; };
                    pend++;
                };
                digits = pend > start;
                v = 0;
                j = start;
                while (j < pend)
                {
                    if (s[j] < '0' | s[j] > '9') { digits = false; };
                    v = v * 10 + (int)(s[j] - '0');
                    j++;
                };
                if (digits) { return v; };
                if (s[pend] == 0) { break; };
                start = pend + 2;
            };
            return -1;
        };

        def bx_new(int v) -> int*
        {
            int* p = (int*)fmalloc((u64)((sizeof(int) + 7) / 8));
            p[0] = v;
            return p;
        };

        // ------------------------------------------------------------------
        // Ordered string keyed map. Insertion order is kept and a removed key that
        // is added again goes to the end, as a Python dict does.
        // ------------------------------------------------------------------

        struct OMap
        {
            PtrVec* ks;
            PtrVec* vs;
        };

        def om_new() -> OMap*
        {
            OMap* m = (OMap*)fmalloc((u64)((sizeof(OMap) + 7) / 8));
            m.ks = pv_new();
            m.vs = pv_new();
            return m;
        };

        // Frees the map. The keys and values belong to the caller.
        def om_free(OMap* m) -> void
        {
            if (m == (OMap*)0) { return; };
            pv_free(m.ks);
            pv_free(m.vs);
            ffree((byte*)m);
            return;
        };

        def om_find(OMap* m, byte* key) -> int
        {
            int i = 0;
            while (i < m.ks.len)
            {
                if (cstr_eq((byte*)m.ks.items[i], key)) { return i; };
                i++;
            };
            return -1;
        };

        def om_has(OMap* m, byte* key) -> bool -> om_find(m, key) >= 0;

        def om_get(OMap* m, byte* key) -> void*
        {
            int i = om_find(m, key);
            if (i < 0) { return (void*)0; };
            return m.vs.items[i];
        };

        def om_put(OMap* m, byte* key, void* v) -> void
        {
            int i = om_find(m, key);
            if (i >= 0)
            {
                m.vs.items[i] = v;
                return;
            };
            pv_push(m.ks, (void*)key);
            pv_push(m.vs, v);
            return;
        };

        def om_remove_at(OMap* m, int at) -> void
        {
            int j = at;
            while (j < m.ks.len - 1)
            {
                m.ks.items[j] = m.ks.items[j + 1];
                m.vs.items[j] = m.vs.items[j + 1];
                j++;
            };
            m.ks.len--;
            m.vs.len--;
            return;
        };

        def om_del(OMap* m, byte* key) -> void
        {
            int i = om_find(m, key);
            if (i >= 0) { om_remove_at(m, i); };
            return;
        };

        def om_clear(OMap* m) -> void
        {
            m.ks.len = 0;
            m.vs.len = 0;
            return;
        };

        def om_copy(OMap* m) -> OMap*
        {
            OMap* r = om_new();
            int i = 0;
            while (i < m.ks.len)
            {
                pv_push(r.ks, m.ks.items[i]);
                pv_push(r.vs, m.vs.items[i]);
                i++;
            };
            return r;
        };

        // ------------------------------------------------------------------
        // Records
        // ------------------------------------------------------------------

        struct BPtr
        {
            byte* var_name;
            byte* site;
            byte* func_name;
            byte* file;
            bool mut;
            int depth;
            int line;
        };

        struct BPos
        {
            byte* file;
            int line;
        };

        struct BVio
        {
            byte* kind;
            byte* msg;
            byte* file;
            int line;
            PtrVec* detail;     // byte*
            byte* func;         // mangled name of the function the violation was found in, or null
        };

        struct ScopeFrame
        {
            int depth;
            byte* func_name;
            OMap* ptrs;         // var name to BPtr*
            OMap* owned;        // owned stack sites
            OMap* var_sites;    // stack variable name to site
        };

        def bpos_new(byte* file, int line) -> BPos*
        {
            BPos* p = (BPos*)fmalloc((u64)((sizeof(BPos) + 7) / 8));
            p.file = file;
            p.line = line;
            return p;
        };

        def frame_new(int depth, byte* func_name) -> ScopeFrame*
        {
            ScopeFrame* f = (ScopeFrame*)fmalloc((u64)((sizeof(ScopeFrame) + 7) / 8));
            f.depth = depth;
            f.func_name = func_name;
            f.ptrs = om_new();
            f.owned = om_new();
            f.var_sites = om_new();
            return f;
        };

        // ------------------------------------------------------------------
        // AliasMap
        // ------------------------------------------------------------------

        object AliasMap
        {
            PtrVec* frames;         // ScopeFrame*
            PtrVec* violations;     // BVio*
            byte* func_name;
            OMap* heap_sites;       // site to BPos*
            OMap* freed_sites;      // site to BPos*
            OMap* alloc_sizes;      // site to int*
            OMap* escaped_sites;    // site to BPos*
            Buf sb;

            __init() -> this
            {
                this.frames = pv_new();
                this.violations = pv_new();
                this.func_name = g"<global>\0";
                this.heap_sites = om_new();
                this.freed_sites = om_new();
                this.alloc_sizes = om_new();
                this.escaped_sites = om_new();
                this.sb.__init();
                -> this;
            };

            __expr() -> AliasMap* -> this;

            __exit() -> void
            {
                -> this.sb.__exit();
            };

            // Finishes the text collected in sb as a heap string
            take() -> byte* -> ts_dup(this.sb.mem);

            add_vio(byte* kind, byte* msg, byte* file, int line, PtrVec* detail) -> void
            {
                BVio* v = (BVio*)fmalloc((u64)((sizeof(BVio) + 7) / 8));
                v.kind = kind;
                v.msg = msg;
                v.file = file;
                v.line = line;
                v.detail = detail;
                v.func = this.func_name;
                switch (detail == (PtrVec*)0)
                {
                    case (true) { v.detail = pv_new(); }
                    default {};
                };
                -> pv_push(this.violations, (void*)v);
            };

            // Text "<a>:<line>"
            loc_text(byte* file, int line) -> byte*
            {
                this.sb.clear();
                this.sb.put_str(f"{file}:{line}\0");
                -> this.take();
            };

            // ----- scope management -----

            push_scope() -> void
            {
                -> pv_push(this.frames, (void*)frame_new(this.frames.len, this.func_name));
            };

            pop_scope() -> void
            {
                int fi;
                int k;
                ScopeFrame* f;
                BPtr* p;
                ScopeFrame* frame;
                switch (this.frames.len == 0)
                {
                    case (true) { ->; }
                    default
                    {
                        frame = (ScopeFrame*)this.frames.items[this.frames.len - 1];
                        this.frames.len--;
                        switch (frame.owned.ks.len > 0)
                        {
                            case (true) { this.check_escape_after_pop(frame.owned); }
                            default {};
                        };
                        while (fi < this.frames.len)
                        {
                            f = (ScopeFrame*)this.frames.items[fi];
                            k = 0;
                            while (k < f.ptrs.ks.len)
                            {
                                p = (BPtr*)f.ptrs.vs.items[k];
                                switch (p.depth == frame.depth)
                                {
                                    case (true) { om_remove_at(f.ptrs, k); }
                                    default { k++; };
                                };
                            };
                            fi++;
                        };
                        ->;
                    };
                };
            };

            check_escape_after_pop(OMap* dead) -> void
            {
                int fi;
                int k;
                ScopeFrame* f;
                BPtr* p;
                byte* msg;
                while (fi < this.frames.len)
                {
                    f = (ScopeFrame*)this.frames.items[fi];
                    k = 0;
                    while (k < f.ptrs.ks.len)
                    {
                        p = (BPtr*)f.ptrs.vs.items[k];
                        switch (om_has(dead, p.site))
                        {
                            case (true) {
                            this.sb.clear();
                            this.sb.put_str(f"pointer '{p.var_name}' outlives its stack allocation '{p.site}' (allocation scope exited)\0");
                            msg = this.take();
                            this.add_vio(g"scope_escape\0", msg, p.file, p.line, (PtrVec*)0);
                        }
                            default {};
                        };
                        k++;
                    };
                    fi++;
                };
                ->;
            };

            // ----- pointer declaration and assignment -----

            find_ptr(byte* var_name) -> BPtr*
            {
                int fi = this.frames.len - 1;
                ScopeFrame* f;
                int k;
                while (fi >= 0)
                {
                    f = (ScopeFrame*)this.frames.items[fi];
                    k = om_find(f.ptrs, var_name);
                    switch (k >= 0)
                    {
                        case (true) { -> (BPtr*)f.ptrs.vs.items[k]; }
                        default
                        {
                            fi--;
                        };
                    };
                };
                -> (BPtr*)0;
            };

            declare_ptr(byte* var_name, byte* site, bool mutable, byte* file, int line,
                        bool is_stack_owner) -> void
            {
                ScopeFrame* frame;
                BPtr* info;
                switch (this.frames.len == 0)
                {
                    case (true) { ->; }
                    default
                    {
                        frame = (ScopeFrame*)this.frames.items[this.frames.len - 1];
                        switch (is_stack_owner)
                        {
                            case (true) { om_put(frame.owned, site, (void*)1); }
                            default {};
                        };
                        info = (BPtr*)fmalloc((u64)((sizeof(BPtr) + 7) / 8));
                        info.var_name = var_name;
                        info.site = site;
                        info.mut = mutable;
                        info.depth = frame.depth;
                        info.func_name = this.func_name;
                        info.file = file;
                        info.line = line;
                        -> om_put(frame.ptrs, var_name, (void*)info);
                    };
                };
            };

            assign_ptr(byte* var_name, byte* site, bool mutable, byte* file, int line) -> void
            {
                BPtr* info = this.find_ptr(var_name);
                byte* old_site;
                bool still_used;
                int fi;
                int k;
                ScopeFrame* f;
                BPtr* p;
                switch (info == (BPtr*)0)
                {
                    case (true) {
                    this.declare_ptr(var_name, site, mutable, file, line, false);
                    ->;
                }
                    default
                    {
                        old_site = info.site;
                        info.site = site;
                        info.mut = mutable;
                        info.file = file;
                        info.line = line;
                        switch (old_site[0] != 0 & om_has(this.freed_sites, old_site) & !cstr_eq(site, old_site)
                                & !bc_starts(site, g"freed:\0"))
                        {
                            case (true) {
                            still_used = false;
                            fi = 0;
                            while (fi < this.frames.len)
                            {
                                f = (ScopeFrame*)this.frames.items[fi];
                                k = 0;
                                while (k < f.ptrs.ks.len)
                                {
                                    p = (BPtr*)f.ptrs.vs.items[k];
                                    switch (cstr_eq(p.site, old_site) & !cstr_eq(p.var_name, var_name))
                                    {
                                        case (true) { still_used = true; }
                                        default {};
                                    };
                                    k++;
                                };
                                fi++;
                            };
                            switch (!still_used)
                            {
                                case (true) { om_del(this.freed_sites, old_site); }
                                default {};
                            };
                        }
                            default {};
                        };
                        ->;
                    };
                };
            };

            // ----- heap tracking -----

            record_malloc(byte* site, byte* file, int line) -> void
            {
                -> om_put(this.heap_sites, site, (void*)bpos_new(file, line));
            };

            record_free(byte* site) -> void
            {
                -> om_del(this.heap_sites, site);
            };

            // Base allocation site, one derived: prefix stripped
            base_site(byte* site) -> byte*
            {
                switch (bc_starts(site, g"derived:\0"))
                {
                    case (true) { -> site + 8; }
                    default
                    {
                        -> site;
                    };
                };
            };

            mark_freed(byte* site, byte* file, int line) -> void
            {
                switch (site[0] != 0 & !cstr_eq(site, g"unknown\0") & !bc_starts(site, g"derived:\0"))
                {
                    case (true) { om_put(this.freed_sites, site, (void*)bpos_new(file, line)); }
                    default {};
                };
                ->;
            };

            check_use_after_free(byte* var_name, byte* file, int line) -> void
            {
                BPtr* info = this.find_ptr(var_name);
                byte* site;
                byte* base;
                byte* matched = (byte*)0;
                BPos* fp;
                PtrVec* det;
                switch (info == (BPtr*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        site = info.site;
                        base = this.base_site(site);
                        switch (om_has(this.freed_sites, site))
                        {
                            case (true) { matched = site; }
                            default {
                            switch (!cstr_eq(base, site))
                            {
                                case (true) {
                                switch (om_has(this.freed_sites, base))
                                {
                                    case (true) { matched = base; }
                                    default {};
                                };
                            }
                                default {};
                            };
                        };
                        };
                        switch (matched == (byte*)0)
                        {
                            case (true) { ->; }
                            default
                            {
                                fp = (BPos*)om_get(this.freed_sites, matched);
                                det = pv_new();
                                this.sb.clear();
                                this.sb.put_str(f"ffree called at {fp.file}:{fp.line}\0");
                                pv_push(det, (void*)this.take());
                                this.sb.clear();
                                this.sb.put_str(f"'{var_name}' -> {site} at {file}:{line}\0");
                                pv_push(det, (void*)this.take());
                                this.sb.clear();
                                this.sb.put_str(f"pointer '{var_name}' used after its allocation site '{matched}' was passed to ffree\0");
                                -> this.add_vio(g"use_after_free\0", this.take(), file, line, det);
                            };
                        };
                    };
                };
            };

            record_alloc_size(byte* site, int size) -> void
            {
                switch (site[0] != 0 & !cstr_eq(site, g"unknown\0") & !bc_starts(site, g"derived:\0"))
                {
                    case (true) { om_put(this.alloc_sizes, site, (void*)bx_new(size)); }
                    default {};
                };
                ->;
            };

            // Reports a concrete out of bounds index. what_text is the message tail after the index.
            check_bounds(byte* var_name, int index, byte* file, int line, bool write) -> void
            {
                BPtr* info = this.find_ptr(var_name);
                byte* site;
                byte* base;
                byte* lookup;
                int size;
                PtrVec* det;
                switch (info == (BPtr*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        site = info.site;
                        base = this.base_site(site);
                        switch (om_has(this.alloc_sizes, site))
                        {
                            case (true) { lookup = site; }
                            default {
                            switch (!cstr_eq(base, site) & om_has(this.alloc_sizes, base))
                            {
                                case (true) { lookup = base; }
                                default { ->; };
                            };
                        };
                        };
                        size = ((int*)om_get(this.alloc_sizes, lookup))[0];
                        switch (size < 0)
                        {
                            case (true) { ->; }
                            default
                            {
                                switch (index < 0 | index >= size)
                                {
                                    case (true) {
                                    det = pv_new();
                                    this.sb.clear();
                                    this.sb.put_str(f"'{var_name}' -> {site} (size {size}) at {file}:{line}\0");
                                    pv_push(det, (void*)this.take());
                                    this.sb.clear();
                                    this.sb.put_str(f"index {index}\0");
                                    switch (index < 0)
                                    {
                                        case (true) { this.sb.put_str(g" < 0\0"); }
                                        default { this.sb.put_str(g" >= size\0"); };
                                    };
                                    pv_push(det, (void*)this.take());
                                    this.sb.clear();
                                    this.sb.put_str(g"array \0");
                                    switch (write)
                                    {
                                        case (true) { this.sb.put_str(g"write\0"); }
                                        default { this.sb.put_str(g"access\0"); };
                                    };
                                    this.sb.put_str(f" through '{var_name}' at index {index} is out of bounds for site '{lookup}' (size {size})\0");
                                    switch (write)
                                    {
                                        case (true) { this.add_vio(g"buffer_overflow\0", this.take(), file, line, det); }
                                        default { this.add_vio(g"out_of_bounds\0", this.take(), file, line, det); };
                                    };
                                }
                                    default {};
                                };
                                ->;
                            };
                        };
                    };
                };
            };

            // Reports every heap site still held, then clears the per function state
            check_heap_leaks() -> void
            {
                int i;
                BPos* p;
                while (i < this.heap_sites.ks.len)
                {
                    p = (BPos*)this.heap_sites.vs.items[i];
                    this.sb.clear();
                    this.sb.put_str(g"heap allocation '\0");
                    this.sb.put_str((byte*)this.heap_sites.ks.items[i]);
                    this.sb.put_str(g"' has no reachable ffree on all paths\0");
                    this.add_vio(g"heap_leak\0", this.take(), p.file, p.line, (PtrVec*)0);
                    i++;
                };
                om_clear(this.heap_sites);
                om_clear(this.freed_sites);
                -> om_clear(this.alloc_sizes);
            };

            // ----- alias checking -----

            mut_text(bool m) -> byte*
            {
                switch (m)
                {
                    case (true) { -> g"mutable\0"; }
                    default
                    {
                        -> g"immutable\0";
                    };
                };
            };

            // One detail line "'<name>' -> <site> (<mut>) at <file>:<line>"
            alias_line(byte* name, byte* site, bool m, byte* file, int line) -> byte*
            {
                this.sb.clear();
                this.sb.put_str(f"'{name}' -> {site} ({this.mut_text(m)}) at {file}:{line}\0");
                -> this.take();
            };

            // A write through var_name while another live pointer shares its base site
            check_write_alias(byte* var_name, byte* file, int line) -> void
            {
                BPtr* info = this.find_ptr(var_name);
                BPtr* ex;
                byte* site;
                byte* base;
                byte* ex_base;
                int fi;
                int k;
                ScopeFrame* f;
                PtrVec* det;
                switch (info == (BPtr*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        site = info.site;
                        base = this.base_site(site);
                        while (fi < this.frames.len)
                        {
                            f = (ScopeFrame*)this.frames.items[fi];
                            k = 0;
                            while (k < f.ptrs.ks.len)
                            {
                                ex = (BPtr*)f.ptrs.vs.items[k];
                                k++;
                                switch (cstr_eq(ex.var_name, var_name))
                                {
                                    case (true) { continue; }
                                    default
                                    {
                                        switch (cstr_eq(ex.site, g"unknown\0"))
                                        {
                                            case (true) { continue; }
                                            default
                                            {
                                                ex_base = this.base_site(ex.site);
                                                switch (om_has(this.freed_sites, ex.site) | om_has(this.freed_sites, ex_base))
                                                {
                                                    case (true) { continue; }
                                                    default
                                                    {
                                                        switch (!cstr_eq(ex_base, base))
                                                        {
                                                            case (true) { continue; }
                                                            default
                                                            {
                                                                switch (!(info.mut | ex.mut))
                                                                {
                                                                    case (true) { continue; }
                                                                    default
                                                                    {
                                                                        det = pv_new();
                                                                        pv_push(det, (void*)this.alias_line(var_name, site, info.mut, file, line));
                                                                        pv_push(det, (void*)this.alias_line(ex.var_name, ex.site, ex.mut, ex.file, ex.line));
                                                                        this.sb.clear();
                                                                        this.sb.put_str(f"mutable alias violation on site '{base}' (write through derived pointer into same allocation)\0");
                                                                        -> this.add_vio(g"mutable_alias\0", this.take(), file, line, det);
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                            fi++;
                        };
                        ->;
                    };
                };
            };

            // Pointer arguments at an opaque call: only argument pairs are compared.
            // names and sites are parallel PtrVecs of byte*.
            check_call_args(PtrVec* names, PtrVec* sites, byte* file, int line) -> void
            {
                int i;
                int j;
                byte* sa;
                byte* sb2;
                PtrVec* det;
                while (i < sites.len)
                {
                    sa = (byte*)sites.items[i];
                    switch (cstr_eq(sa, g"unknown\0") | bc_starts(sa, g"derived:\0"))
                    {
                        case (true) { i++; continue; }
                        default
                        {
                            j = i + 1;
                            while (j < sites.len)
                            {
                                sb2 = (byte*)sites.items[j];
                                switch (cstr_eq(sb2, g"unknown\0") | bc_starts(sb2, g"derived:\0"))
                                {
                                    case (true) { j++; continue; }
                                    default
                                    {
                                        switch (cstr_eq(sa, sb2))
                                        {
                                            case (true) {
                                            det = pv_new();
                                            this.sb.clear();
                                            this.sb.put_str(g"argument '\0");
                                            this.sb.put_str((byte*)names.items[i]);
                                            this.sb.put_str(f"' -> {sa} (mutable) at {file}:{line}\0");
                                            pv_push(det, (void*)this.take());
                                            this.sb.clear();
                                            this.sb.put_str(g"argument '\0");
                                            this.sb.put_str((byte*)names.items[j]);
                                            this.sb.put_str(f"' -> {sb2} (mutable) at {file}:{line}\0");
                                            pv_push(det, (void*)this.take());
                                            this.sb.clear();
                                            this.sb.put_str(f"mutable alias violation on site '{sa}'\0");
                                            this.add_vio(g"mutable_alias\0", this.take(), file, line, det);
                                        }
                                            default {};
                                        };
                                        j++;
                                    };
                                };
                            };
                            i++;
                        };
                    };
                };
                ->;
            };

            // ----- thread safety -----

            check_thread_escape(byte* ptr_var, byte* file, int line) -> void
            {
                BPtr* info = this.find_ptr(ptr_var);
                BPtr* ex;
                int fi;
                int k;
                ScopeFrame* f;
                PtrVec* det;
                switch (info == (BPtr*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        // Phase 1: an alias already exists at spawn time
                        while (fi < this.frames.len)
                        {
                            f = (ScopeFrame*)this.frames.items[fi];
                            k = 0;
                            while (k < f.ptrs.ks.len)
                            {
                                ex = (BPtr*)f.ptrs.vs.items[k];
                                k++;
                                switch (cstr_eq(ex.var_name, ptr_var))
                                {
                                    case (true) { continue; }
                                    default
                                    {
                                        switch (!cstr_eq(ex.site, info.site))
                                        {
                                            case (true) { continue; }
                                            default
                                            {
                                                switch (cstr_eq(ex.site, g"unknown\0") | bc_starts(ex.site, g"derived:\0"))
                                                {
                                                    case (true) { continue; }
                                                    default
                                                    {
                                                        switch (ex.mut | info.mut)
                                                        {
                                                            case (true) {
                                                            det = pv_new();
                                                            this.sb.clear();
                                                            this.sb.put_str(f"'{ex.var_name}' -> {ex.site} at {ex.file}:{ex.line}\0");
                                                            pv_push(det, (void*)this.take());
                                                            this.sb.clear();
                                                            this.sb.put_str(f"pointer '{ptr_var}' passed to thread while mutable alias '{ex.var_name}' exists on site '{info.site}'\0");
                                                            this.add_vio(g"thread_escape\0", this.take(), file, line, det);
                                                        }
                                                            default {};
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                            fi++;
                        };
                        // Phase 2: later mutable access in the caller is a race
                        switch (info.mut & !cstr_eq(info.site, g"unknown\0") & !bc_starts(info.site, g"derived:\0"))
                        {
                            case (true) { om_put(this.escaped_sites, info.site, (void*)bpos_new(file, line)); }
                            default {};
                        };
                        ->;
                    };
                };
            };

            check_use_after_escape(byte* ptr_var, byte* file, int line) -> void
            {
                BPtr* info = this.find_ptr(ptr_var);
                byte* site;
                byte* base;
                byte* matched = (byte*)0;
                BPos* sp;
                PtrVec* det;
                switch (info == (BPtr*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        site = info.site;
                        base = this.base_site(site);
                        switch (om_has(this.escaped_sites, site))
                        {
                            case (true) { matched = site; }
                            default {
                            switch (!cstr_eq(base, site) & om_has(this.escaped_sites, base))
                            {
                                case (true) { matched = base; }
                                default {};
                            };
                        };
                        };
                        switch (matched == (byte*)0)
                        {
                            case (true) { ->; }
                            default
                            {
                                sp = (BPos*)om_get(this.escaped_sites, matched);
                                switch (sp.line == line)
                                {
                                    case (true) { ->; }
                                    default
                                    {
                                        det = pv_new();
                                        this.sb.clear();
                                        this.sb.put_str(f"site escaped to thread at {sp.file}:{sp.line}\0");
                                        pv_push(det, (void*)this.take());
                                        this.sb.clear();
                                        this.sb.put_str(f"'{ptr_var}' -> {site} (mutable) at {file}:{line}\0");
                                        pv_push(det, (void*)this.take());
                                        this.sb.clear();
                                        this.sb.put_str(f"pointer '{ptr_var}' accessed after its site '{matched}' was passed to a thread (potential data race)\0");
                                        -> this.add_vio(g"thread_race\0", this.take(), file, line, det);
                                    };
                                };
                            };
                        };
                    };
                };
            };
        };

        // ------------------------------------------------------------------
        // Helpers over the AST
        // ------------------------------------------------------------------

        def bc_unk() -> byte* -> g"<unknown>\0";

        def bc_contains(byte* hay, byte* needle) -> bool
        {
            int i = 0;
            int j;
            bool hit;
            while (hay[i] != 0)
            {
                j = 0;
                hit = true;
                while (needle[j] != 0)
                {
                    if (hay[i + j] != needle[j])
                    {
                        hit = false;
                        break;
                    };
                    j++;
                };
                if (hit) { return true; };
                i++;
            };
            return false;
        };

        def bc_count(Node* n, int s) -> int
        {
            if (n == (Node*)0) { return 0; };
            return node_count(n, s);
        };

        def bc_is_pointer_type(TypeSpec* t) -> bool
        {
            if (t == (TypeSpec*)0) { return false; };
            if ((t.flags `& TS_POINTER) != 0) { return true; };
            return t.pointer_depth > 0;
        };

        def bc_stack_site(byte* func_name, byte* var_name, int line) -> byte*
        {
            Buf b;
            b.__init();
            b.put_str(f"stack:{func_name}:{var_name}@{line}\0");
            byte* r = ts_dup(b.mem);
            b.__exit();
            return r;
        };

        def bc_heap_site(byte* func_name, int line) -> byte*
        {
            Buf b;
            b.__init();
            b.put_str(f"heap:{func_name}:{line}\0");
            byte* r = ts_dup(b.mem);
            b.__exit();
            return r;
        };

        def bc_param_site(byte* func_name, byte* param_name) -> byte*
        {
            Buf b;
            b.__init();
            b.put_str(f"param:{func_name}:{param_name}\0");
            byte* r = ts_dup(b.mem);
            b.__exit();
            return r;
        };

        def bc_prefixed(byte* prefix, byte* s) -> byte*
        {
            Buf b;
            b.__init();
            b.put_str(f"{prefix}{s}\0");
            byte* r = ts_dup(b.mem);
            b.__exit();
            return r;
        };

        def bc_is_call_named(Node* n, byte* name) -> bool
        {
            if (n == (Node*)0) { return false; };
            if (n.kind != NodeKind.FUNCTION_CALL) { return false; };
            if (n.text == (byte*)0) { return false; };
            return cstr_eq(n.text, name);
        };

        def bc_is_fmalloc(Node* n) -> bool -> bc_is_call_named(n, g"fmalloc\0");

        def bc_is_ffree(Node* n) -> bool -> bc_is_call_named(n, g"ffree\0");

        def bc_is_thread_spawn(Node* n) -> bool
        {
            if (n.kind != NodeKind.FUNCTION_CALL & n.kind != NodeKind.METHOD_CALL) { return false; };
            if (n.text == (byte*)0) { return false; };
            return bc_has_ci(n.text, g"spawn\0") | bc_has_ci(n.text, g"thread\0");
        };

        def bc_is_cast(Node* n) -> bool
        {
            return n.kind == NodeKind.CAST_EXPRESSION | n.kind == NodeKind.TYPE_CONVERT_EXPRESSION;
        };

        // Function definition behind a statement wrapper
        def bc_unwrap_fn(Node* n) -> Node*
        {
            if (n.kind == NodeKind.FUNCTION_DEF_STATEMENT) { return n.a; };
            return n;
        };

        def bc_is_proto(Node* f) -> bool -> (f.flags `& NF_PROTOTYPE) != 0;

        // ------------------------------------------------------------------
        // Call graph
        // ------------------------------------------------------------------

        // one "#<Tag>(...)" clause: the function key that carries it
        struct AUse
        {
            byte* key;
            Node* fd, use;
        };

        object CallGraph
        {
            NameMap* funcs;             // name to Node*
            NameMap* short_names;       // short name to mangled name (byte*)
            NameMap* overloads;         // base name to PtrVec* of mangled names
            NameMap* visited_main;      // context key set
            NameMap* visited_thread;
            NameMap* spawn_count;       // name to int*
            NameMap* async_names;       // function keys declared async
            NameMap* async_tags;        // tag name to ASYNC_TAG_DEF
            PtrVec* async_uses;         // AUse* clauses
            Buf kb;

            __init() -> this
            {
                this.funcs = nm_new();
                this.short_names = nm_new();
                this.overloads = nm_new();
                this.visited_main = nm_new();
                this.visited_thread = nm_new();
                this.spawn_count = nm_new();
                this.async_names = nm_new();
                this.async_tags = nm_new();
                this.async_uses = pv_new();
                this.kb.__init();
                -> this;
            };

            __expr() -> CallGraph* -> this;

            __exit() -> void
            {
                nm_free(this.funcs);
                nm_free(this.short_names);
                nm_free(this.overloads);
                nm_free(this.visited_main);
                nm_free(this.visited_thread);
                nm_free(this.spawn_count);
                nm_free(this.async_names);
                nm_free(this.async_tags);
                -> this.kb.__exit();
            };

            // Key of (name, context): name, 0x1e, then the sites joined by 0x1f
            ctx_key(byte* name, PtrVec* ctx) -> byte*
            {
                int i;
                this.kb.clear();
                this.kb.put_str(f"{name}\x1e\0");
                while (i < ctx.len)
                {
                    switch (i > 0)
                    {
                        case (true) { this.kb.put_str(g"\x1f\0"); }
                        default {};
                    };
                    this.kb.put_str((byte*)ctx.items[i]);
                    i++;
                };
                -> this.kb.mem;
            };

            is_visited(byte* name, PtrVec* ctx, bool thread) -> bool
            {
                byte* k = this.ctx_key(name, ctx);
                switch (thread)
                {
                    case (true) { -> nm_has(this.visited_thread, k); }
                    default
                    {
                        -> nm_has(this.visited_main, k);
                    };
                };
            };

            mark_visited(byte* name, PtrVec* ctx, bool thread) -> void
            {
                byte* k = this.ctx_key(name, ctx);
                switch (thread)
                {
                    case (true) { nm_put(this.visited_thread, k, (void*)1); }
                    default { nm_put(this.visited_main, k, (void*)1); };
                };
                ->;
            };

            note_async(Node* f, byte* key) -> void
            {
                int c = bc_count(f, 1);
                int i;
                AUse* u;
                if ((f.flags `& NF_ASYNC) != 0) { nm_put(this.async_names, key, (void*)1); };
                while (i < c)
                {
                    u = (AUse*)fmalloc((u64)((sizeof(AUse) + 7) / 8));
                    u
                    {
                        .key = key;
                        .fd = f;
                        .use = node_child(f, 1, i);
                    };
                    pv_push(this.async_uses, (void*)u);
                    i++;
                };
                ->;
            };

            add_func(byte* name, Node* f) -> void
            {
                -> nm_put(this.funcs, name, (void*)f);
            };

            collect(Node* program) -> void
            {
                int c = bc_count(program, 0);
                int i;
                byte* mangled;
                byte* short_name;
                byte* base;
                NameMap* short_count = nm_new();
                int* cnt;
                PtrVec* lst;
                while (i < c)
                {
                    this.collect_node(node_child(program, 0, i), (byte*)0);
                    i++;
                };
                // short name index and overload index
                i = 0;
                while (i < this.funcs.count)
                {
                    switch (this.funcs.vals[i] != (void*)0)
                    {
                        case (true) {
                        short_name = bc_last_seg(this.funcs.keys[i]);
                        cnt = (int*)nm_get(short_count, short_name);
                        switch (cnt == (int*)0)
                        {
                            case (true) { nm_put(short_count, short_name, (void*)bx_new(1)); }
                            default { cnt[0] = cnt[0] + 1; };
                        };
                    }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < this.funcs.count)
                {
                    switch (this.funcs.vals[i] != (void*)0)
                    {
                        case (true) {
                        mangled = this.funcs.keys[i];
                        short_name = bc_last_seg(mangled);
                        cnt = (int*)nm_get(short_count, short_name);
                        switch (cnt[0] == 1)
                        {
                            case (true) { nm_put(this.short_names, short_name, (void*)mangled); }
                            default {};
                        };
                        base = bc_overload_base(mangled);
                        lst = (PtrVec*)nm_get(this.overloads, base);
                        switch (lst == (PtrVec*)0)
                        {
                            case (true) {
                            lst = pv_new();
                            nm_put(this.overloads, base, (void*)lst);
                        }
                            default {};
                        };
                        pv_push(lst, (void*)mangled);
                    }
                        default {};
                    };
                    i++;
                };
                -> nm_free(short_count);
            };

            join_prefix(byte* prefix, byte* name) -> byte*
            {
                switch (prefix == (byte*)0)
                {
                    case (true) { -> ts_dup(name); }
                    default
                    {
                        switch (prefix[0] == 0)
                        {
                            case (true) { -> ts_dup(name); }
                            default
                            {
                                -> join3(prefix, g"__\0", name);
                            };
                        };
                    };
                };
            };

            collect_node(Node* node, byte* ns_prefix) -> void
            {
                int k;
                int i;
                int c;
                Node* f;
                byte* prefix;
                switch (node == (Node*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        k = node.kind;
                        switch (k == NodeKind.ASYNC_TAG_DEF)
                        {
                            case (true) { -> nm_put(this.async_tags, node.text, (void*)node); }
                            default
                            {
                                switch (k == NodeKind.FUNCTION_DEF)
                                {
                                    case (true) {
                                    this.note_async(node, node.text);
                                    switch (!bc_is_proto(node))
                                    {
                                        case (true) { this.add_func(node.text, node); }
                                        default {};
                                    };
                                    ->;
                                }
                                    default
                                    {
                                        switch (k == NodeKind.FUNCTION_DEF_STATEMENT)
                                        {
                                            case (true) { -> this.collect_node(node.a, ns_prefix); }
                                            default
                                            {
                                                switch (k == NodeKind.NAMESPACE_DEF_STATEMENT)
                                                {
                                                    case (true) { -> this.collect_node(node.a, ns_prefix); }
                                                    default
                                                    {
                                                        switch (k == NodeKind.NAMESPACE_DEF)
                                                        {
                                                            case (true) {
                                                            prefix = this.join_prefix(ns_prefix, node.text);
                                                            c = bc_count(node, 0);
                                                            i = 0;
                                                            while (i < c)
                                                            {
                                                                f = bc_unwrap_fn(node_child(node, 0, i));
                                                                i++;
                                                                switch (f.kind == NodeKind.FUNCTION_DEF)
                                                                {
                                                                    case (true) {
                                                                    this.note_async(f, this.join_prefix(prefix, f.text));
                                                                    switch (!bc_is_proto(f))
                                                                    {
                                                                        case (true) { this.add_func(this.join_prefix(prefix, f.text), f); }
                                                                        default {};
                                                                    };
                                                                }
                                                                    default {};
                                                                };
                                                            };
                                                            c = bc_count(node, 2);
                                                            i = 0;
                                                            while (i < c)
                                                            {
                                                                this.collect_object(node_child(node, 2, i), prefix);
                                                                i++;
                                                            };
                                                            switch (node.b != (Node*)0)
                                                            {
                                                                case (true) {
                                                                c = bc_count(node.b, 0);
                                                                i = 0;
                                                                while (i < c)
                                                                {
                                                                    this.collect_node(node_child(node.b, 0, i), prefix);
                                                                    i++;
                                                                };
                                                            }
                                                                default {};
                                                            };
                                                            ->;
                                                        }
                                                            default
                                                            {
                                                                switch (k == NodeKind.OBJECT_DEF)
                                                                {
                                                                    case (true) { -> this.collect_object(node, ns_prefix); }
                                                                    default
                                                                    {
                                                                        switch (k == NodeKind.OBJECT_DEF_STATEMENT)
                                                                        {
                                                                            case (true) { -> this.collect_object(node.a, ns_prefix); }
                                                                            default
                                                                            {
                                                                                switch (k == NodeKind.EXPORT_BLOCK)
                                                                                {
                                                                                    case (true) {
                                                                                    c = bc_count(node, 0);
                                                                                    i = 0;
                                                                                    while (i < c)
                                                                                    {
                                                                                        f = bc_unwrap_fn(node_child(node, 0, i));
                                                                                        i++;
                                                                                        switch (f.kind == NodeKind.FUNCTION_DEF)
                                                                                        {
                                                                                            case (true) {
                                                                                            switch (!bc_is_proto(f))
                                                                                            {
                                                                                                case (true) { this.add_func(f.text, f); }
                                                                                                default {};
                                                                                            };
                                                                                        }
                                                                                            default {};
                                                                                        };
                                                                                    };
                                                                                }
                                                                                    default {};
                                                                                };
                                                                                ->;
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };

            collect_object(Node* obj, byte* prefix) -> void
            {
                int c;
                int i;
                Node* m;
                byte* mangled;
                byte* inner;
                switch (obj == (Node*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        switch (obj.kind != NodeKind.OBJECT_DEF)
                        {
                            case (true) { ->; }
                            default
                            {
                                c = bc_count(obj, 1);
                                i = 0;
                                while (i < c)
                                {
                                    m = node_child(obj, 1, i);
                                    i++;
                                    switch (m.text != (byte*)0 & m.a != (Node*)0)
                                    {
                                        case (true) {
                                        switch (m.text[0] != 0)
                                        {
                                            case (true) {
                                            mangled = this.join_prefix(this.join_prefix(prefix, obj.text), m.text);
                                            this.add_func(mangled, m);
                                        }
                                            default {};
                                        };
                                    }
                                        default {};
                                    };
                                };
                                inner = this.join_prefix(prefix, obj.text);
                                c = bc_count(obj, 3);
                                i = 0;
                                while (i < c)
                                {
                                    this.collect_object(node_child(obj, 3, i), inner);
                                    i++;
                                };
                                ->;
                            };
                        };
                    };
                };
            };
        };

        // ------------------------------------------------------------------
        // Borrow checker
        // ------------------------------------------------------------------

        object BorrowChecker
        {
            CallGraph* cg;
            byte* entry;
            bool check_threads;
            bool check_leaks;
            Preprocessor* pp;
            AliasMap alias;
            PtrVec* violations;         // BVio*
            NameMap* seen;
            int funcs_checked;
            bool in_thread;
            NameMap* call_stack;
            Node* cur_func;
            OMap* array_heap;           // array name to PtrVec* of byte* heap sites
            i64 lit_val;
            Buf sb;

            __init(CallGraph* g, byte* entry_name, bool threads, bool leaks, Preprocessor* p) -> this
            {
                this.cg = g;
                this.entry = entry_name;
                this.check_threads = threads;
                this.check_leaks = leaks;
                this.pp = p;
                this.alias.__init();
                this.violations = pv_new();
                this.seen = nm_new();
                this.funcs_checked = 0;
                this.in_thread = false;
                this.call_stack = nm_new();
                this.cur_func = (Node*)0;
                this.array_heap = om_new();
                this.sb.__init();
                -> this;
            };

            __expr() -> BorrowChecker* -> this;

            __exit() -> void
            {
                this.alias.__exit();
                nm_free(this.seen);
                nm_free(this.call_stack);
                -> this.sb.__exit();
            };

            // ----- line map -----

            remap_file(int merged) -> byte*
            {
                int idx = merged - 1;
                switch (this.pp != (Preprocessor*)0)
                {
                    case (true) {
                    switch (idx >= 0 & idx < this.pp.map_line.len)
                    {
                        case (true) { -> this.pp.map_path(idx); }
                        default {};
                    };
                }
                    default {};
                };
                -> bc_unk();
            };

            remap_line(int merged) -> int
            {
                int idx = merged - 1;
                switch (this.pp != (Preprocessor*)0)
                {
                    case (true) {
                    switch (idx >= 0 & idx < this.pp.map_line.len)
                    {
                        case (true) { -> this.pp.map_lineno(idx); }
                        default {};
                    };
                }
                    default {};
                };
                -> merged;
            };

            // A detail line with exactly one " at " and a trailing ":<line>" gets the
            // location remapped. Anything else is returned unchanged.
            remap_detail(byte* d) -> byte*
            {
                int n = bc_len(d);
                int first = -1;
                int i = 0;
                int colon = -1;
                int j;
                int merged;
                bool digits;
                // find the first " at "
                while (i + 4 <= n)
                {
                    switch (bc_starts(d + i, g" at \0"))
                    {
                        case (true) {
                        switch (first < 0)
                        {
                            case (true) { first = i; i = i + 4; }
                            default { -> d; };
                        };
                    }
                        default { i++; };
                    };
                };
                switch (first < 0)
                {
                    case (true) { -> d; }
                    default
                    {
                        // last ':' of the text after the separator
                        j = first + 4;
                        while (j < n)
                        {
                            switch (d[j] == ':')
                            {
                                case (true) { colon = j; }
                                default {};
                            };
                            j++;
                        };
                        switch (colon < 0)
                        {
                            case (true) { -> d; }
                            default
                            {
                                digits = colon + 1 < n;
                                merged = 0;
                                j = colon + 1;
                                while (j < n)
                                {
                                    switch (d[j] < '0' | d[j] > '9')
                                    {
                                        case (true) { digits = false; }
                                        default { merged = merged * 10 + ((int)d[j] - 48); };
                                    };
                                    j++;
                                };
                                switch (!digits)
                                {
                                    case (true) { -> d; }
                                    default
                                    {
                                        this.sb.clear();
                                        j = 0;
                                        while (j < first)
                                        {
                                            this.sb.put((int)d[j]);
                                            j++;
                                        };
                                        this.sb.put_str(f" at {this.remap_file(merged)}:{this.remap_line(merged)}\0");
                                        -> ts_dup(this.sb.mem);
                                    };
                                };
                            };
                        };
                    };
                };
            };

            viol_key(BVio* v) -> byte*
            {
                this.sb.clear();
                this.sb.put_str(f"{v.kind}\x1f{v.file}\x1f{v.line}\x1f{v.msg}\0");
                -> this.sb.mem;
            };

            // ----- entry -----

            run() -> void
            {
                int i;
                Node* f;
                switch (!nm_has(this.cg.funcs, this.entry))
                {
                    case (true) {
                    print(g"[FBC] Warning: entry point '\0");
                    print(this.entry);
                    println(g"' not found as a non-prototype function.\0");
                    println(g"      This usually means the entry point body is inside an unresolved #ifdef block.\0");
                    println(g"      Checking all reachable functions instead.\0");
                    while (i < this.cg.funcs.count)
                    {
                        f = (Node*)this.cg.funcs.vals[i];
                        switch (f != (Node*)0)
                        {
                            case (true) {
                            switch (!this.cg.is_visited(this.cg.funcs.keys[i], pv_new(), false))
                            {
                                case (true) { this.check_function(f, false, pv_new()); }
                                default {};
                            };
                        }
                            default {};
                        };
                        i++;
                    };
                }
                    default {
                    this.check_function((Node*)nm_get(this.cg.funcs, this.entry), false, pv_new());
                };
                };
                ->;
            };

            // Known allocator wrapper whose fmalloc result is returned to the caller
            func_returns_allocation(Node* func) -> bool
            {
                Node* s;
                Node* e;
                switch (cstr_eq(func.text, g"fmalloc\0") | cstr_eq(func.text, g"ffree\0"))
                {
                    case (true) { -> true; }
                    default
                    {
                        switch (func.a == (Node*)0)
                        {
                            case (true) { -> false; }
                            default
                            {
                                switch (func.a.kind != NodeKind.BLOCK)
                                {
                                    case (true) { -> false; }
                                    default
                                    {
                                        switch (bc_count(func.a, 0) != 1)
                                        {
                                            case (true) { -> false; }
                                            default
                                            {
                                                s = node_child(func.a, 0, 0);
                                                switch (s.kind == NodeKind.RETURN_STATEMENT & s.a != (Node*)0)
                                                {
                                                    case (true) {
                                                    switch (bc_is_fmalloc(s.a))
                                                    {
                                                        case (true) { -> true; }
                                                        default
                                                        {
                                                            switch (s.a.kind == NodeKind.CAST_EXPRESSION)
                                                            {
                                                                case (true) {
                                                                switch (bc_is_fmalloc(s.a.a))
                                                                {
                                                                    case (true) { -> true; }
                                                                    default {};
                                                                };
                                                            }
                                                                default {};
                                                            };
                                                            switch (s.a.kind == NodeKind.FUNCTION_CALL & s.a.text != (byte*)0)
                                                            {
                                                                case (true) {
                                                                switch (bc_has_ci(s.a.text, g"malloc\0") | bc_has_ci(s.a.text, g"alloc\0"))
                                                                {
                                                                    case (true) { -> true; }
                                                                    default {};
                                                                };
                                                            }
                                                                default {};
                                                            };
                                                        };
                                                    };
                                                }
                                                    default {};
                                                };
                                                switch (s.kind == NodeKind.EXPRESSION_STATEMENT)
                                                {
                                                    case (true) {
                                                    e = s.a;
                                                    switch (e != (Node*)0)
                                                    {
                                                        case (true) {
                                                        switch (e.kind == NodeKind.RETURN_STATEMENT & e.a != (Node*)0)
                                                        {
                                                            case (true) {
                                                            switch (bc_is_fmalloc(e.a))
                                                            {
                                                                case (true) { -> true; }
                                                                default {};
                                                            };
                                                        }
                                                            default {};
                                                        };
                                                    }
                                                        default {};
                                                    };
                                                }
                                                    default {};
                                                };
                                                -> false;
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // ----- function walk -----

            ptr_params(Node* func) -> PtrVec*
            {
                PtrVec* r = pv_new();
                int c = bc_count(func, 0);
                int i;
                Node* p;
                while (i < c)
                {
                    p = node_child(func, 0, i);
                    switch (p.text != (byte*)0 & bc_is_pointer_type(p.ts))
                    {
                        case (true) {
                        switch (p.text[0] != 0)
                        {
                            case (true) { pv_push(r, (void*)p); }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> r;
            };

            check_function(Node* func, bool thread_context, PtrVec* call_ctx) -> void
            {
                byte* prev_func;
                bool prev_thread;
                Node* prev_node;
                PtrVec* prev_frames;
                OMap* prev_heap;
                OMap* prev_freed;
                OMap* prev_alloc;
                OMap* prev_array;
                PtrVec* params;
                PtrVec* names;
                PtrVec* sites;
                Node* param;
                byte* site;
                int idx;
                int i;
                BVio* v;
                int merged;
                PtrVec* nd;
                byte* key;

                switch (this.cg.is_visited(func.text, call_ctx, thread_context))
                {
                    case (true) { ->; }
                    default
                    {
                        // a recursive function re-entered with a new context is already active
                        switch (nm_has(this.call_stack, func.text))
                        {
                            case (true) { ->; }
                            default
                            {
                                this.cg.mark_visited(func.text, call_ctx, thread_context);
                                nm_put(this.call_stack, func.text, (void*)1);
                                this.funcs_checked++;

                                prev_func = this.alias.func_name;
                                prev_thread = this.in_thread;
                                prev_node = this.cur_func;
                                // isolate the callee from the caller's live pointer frames
                                prev_frames = this.alias.frames;
                                this.alias.frames = pv_new();
                                prev_heap = this.alias.heap_sites;
                                this.alias.heap_sites = om_new();
                                prev_freed = this.alias.freed_sites;
                                this.alias.freed_sites = om_new();
                                prev_alloc = this.alias.alloc_sizes;
                                this.alias.alloc_sizes = om_new();
                                prev_array = this.array_heap;
                                this.array_heap = om_new();
                                this.alias.func_name = func.text;
                                this.in_thread = thread_context;
                                this.cur_func = func;

                                this.alias.push_scope();

                                params = this.ptr_params(func);
                                names = pv_new();
                                sites = pv_new();
                                idx = 0;
                                while (idx < params.len)
                                {
                                    param = (Node*)params.items[idx];
                                    site = (byte*)0;
                                    switch (idx < call_ctx.len)
                                    {
                                        case (true) {
                                        key = (byte*)call_ctx.items[idx];
                                        switch (!cstr_eq(key, g"unknown\0") & key[0] != 0)
                                        {
                                            case (true) {
                                            site = key;
                                            switch (om_has(prev_alloc, site))
                                            {
                                                case (true) { om_put(this.alias.alloc_sizes, site, om_get(prev_alloc, site)); }
                                                default {};
                                            };
                                        }
                                            default {};
                                        };
                                    }
                                        default {};
                                    };
                                    switch (site == (byte*)0)
                                    {
                                        case (true) { site = bc_param_site(func.text, param.text); }
                                        default {};
                                    };
                                    this.alias.declare_ptr(param.text, site, true, bc_unk(), func.line, false);
                                    pv_push(names, (void*)param.text);
                                    pv_push(sites, (void*)site);
                                    idx++;
                                };
                                this.alias.check_call_args(names, sites, bc_unk(), func.line);

                                switch (func.a != (Node*)0)
                                {
                                    case (true) {
                                    switch (func.a.kind == NodeKind.BLOCK)
                                    {
                                        case (true) { this.walk_block(func.a); }
                                        default { this.walk_expr(func.a); };
                                    };
                                }
                                    default {};
                                };

                                switch (this.check_leaks & !this.func_returns_allocation(func))
                                {
                                    case (true) { this.alias.check_heap_leaks(); }
                                    default {
                                    om_clear(this.alias.heap_sites);
                                    om_clear(this.alias.freed_sites);
                                    om_clear(this.alias.alloc_sizes);
                                };
                                };

                                this.alias.pop_scope();
                                nm_del(this.call_stack, func.text);
                                this.alias.frames = prev_frames;
                                this.alias.heap_sites = prev_heap;
                                this.alias.freed_sites = prev_freed;
                                this.alias.alloc_sizes = prev_alloc;
                                this.array_heap = prev_array;
                                this.alias.func_name = prev_func;
                                this.cur_func = prev_node;
                                this.in_thread = prev_thread;

                                // map merged lines back to the original files, then keep new violations
                                i = 0;
                                while (i < this.alias.violations.len)
                                {
                                    v = (BVio*)this.alias.violations.items[i];
                                    merged = v.line;
                                    v.file = this.remap_file(merged);
                                    v.line = this.remap_line(merged);
                                    nd = pv_new();
                                    idx = 0;
                                    while (idx < v.detail.len)
                                    {
                                        pv_push(nd, (void*)ts_dup(this.remap_detail((byte*)v.detail.items[idx])));
                                        idx++;
                                    };
                                    v.detail = nd;
                                    i++;
                                };
                                i = 0;
                                while (i < this.alias.violations.len)
                                {
                                    v = (BVio*)this.alias.violations.items[i];
                                    key = ts_dup(this.viol_key(v));
                                    switch (!nm_has(this.seen, key))
                                    {
                                        case (true) {
                                        pv_push(this.violations, (void*)v);
                                        nm_put(this.seen, key, (void*)1);
                                    }
                                        default {};
                                    };
                                    i++;
                                };
                                this.alias.violations.len = 0;
                                ->;
                            };
                        };
                    };
                };
            };

            walk_block(Node* block) -> void
            {
                int c = bc_count(block, 0);
                int i;
                Node* s;
                this.alias.push_scope();
                while (i < c)
                {
                    s = node_child(block, 0, i);
                    switch (s != (Node*)0)
                    {
                        case (true) { this.walk_stmt(s); }
                        default {};
                    };
                    i++;
                };
                -> this.alias.pop_scope();
            };

            // Branch state helpers. A site is in the result when it is in a (and, for
            // intersect, also in b).
            om_intersect(OMap* a, OMap* b) -> OMap*
            {
                OMap* r = om_new();
                int i;
                while (i < a.ks.len)
                {
                    switch (om_has(b, (byte*)a.ks.items[i]))
                    {
                        case (true) { om_put(r, (byte*)a.ks.items[i], a.vs.items[i]); }
                        default {};
                    };
                    i++;
                };
                -> r;
            };

            om_update(OMap* dst, OMap* src) -> void
            {
                int i;
                while (i < src.ks.len)
                {
                    om_put(dst, (byte*)src.ks.items[i], src.vs.items[i]);
                    i++;
                };
                ->;
            };

            // Loop exit state for heap_sites: pre sites that survive the body, then new ones
            loop_merge_heap(OMap* pre_heap) -> void
            {
                OMap* loop_heap = om_copy(this.alias.heap_sites);
                OMap* merged = om_new();
                int i;
                while (i < pre_heap.ks.len)
                {
                    switch (om_has(loop_heap, (byte*)pre_heap.ks.items[i]))
                    {
                        case (true) { om_put(merged, (byte*)pre_heap.ks.items[i], pre_heap.vs.items[i]); }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < loop_heap.ks.len)
                {
                    switch (!om_has(pre_heap, (byte*)loop_heap.ks.items[i]))
                    {
                        case (true) { om_put(merged, (byte*)loop_heap.ks.items[i], loop_heap.vs.items[i]); }
                        default {};
                    };
                    i++;
                };
                this.alias.heap_sites = merged;
                ->;
            };

            // A loop body that may run zero times
            walk_loop_body(Node* body) -> void
            {
                OMap* pre_freed = om_copy(this.alias.freed_sites);
                OMap* pre_heap = om_copy(this.alias.heap_sites);
                this.walk_block(body);
                this.alias.freed_sites = om_copy(pre_freed);
                -> this.loop_merge_heap(pre_heap);
            };

            walk_stmt(Node* node) -> void
            {
                int k = node.kind;
                OMap* pre_freed;
                OMap* pre_heap;
                OMap* then_freed;
                OMap* then_heap;
                OMap* else_freed;
                OMap* else_heap;
                OMap* merged;
                OMap* inter;
                PtrVec* case_freeds;
                PtrVec* case_heaps;
                Node* cs;
                int i;
                int c;

                switch (k == NodeKind.VARIABLE_DECLARATION)
                {
                    case (true) { -> this.on_var_decl(node); }
                    default
                    {
                        switch (k == NodeKind.ASSIGNMENT)
                        {
                            case (true) { -> this.on_assign(node); }
                            default
                            {
                                switch (k == NodeKind.COMPOUND_ASSIGNMENT)
                                {
                                    case (true) { -> this.walk_expr(node.b); }
                                    default
                                    {
                                        switch (k == NodeKind.EXPRESSION_STATEMENT)
                                        {
                                            case (true) { -> this.walk_expr(node.a); }
                                            default
                                            {
                                                switch (k == NodeKind.BLOCK)
                                                {
                                                    case (true) { -> this.walk_block(node); }
                                                    default
                                                    {
                                                        switch (k == NodeKind.IF_STATEMENT)
                                                        {
                                                            case (true) {
                                                            this.walk_expr(node.a);
                                                            pre_freed = om_copy(this.alias.freed_sites);
                                                            pre_heap = om_copy(this.alias.heap_sites);
                                                            switch (node.b != (Node*)0)
                                                            {
                                                                case (true) { this.walk_block(node.b); }
                                                                default {};
                                                            };
                                                            then_freed = om_copy(this.alias.freed_sites);
                                                            then_heap = om_copy(this.alias.heap_sites);
                                                            this.alias.freed_sites = om_copy(pre_freed);
                                                            this.alias.heap_sites = om_copy(pre_heap);
                                                            switch (node.c != (Node*)0)
                                                            {
                                                                case (true) { this.walk_block(node.c); }
                                                                default {};
                                                            };
                                                            else_freed = om_copy(this.alias.freed_sites);
                                                            else_heap = om_copy(this.alias.heap_sites);
                                                            switch (node.c != (Node*)0)
                                                            {
                                                                case (true) {
                                                                // freed on both paths only; heap is the union of both paths
                                                                this.alias.freed_sites = this.om_intersect(then_freed, else_freed);
                                                                merged = om_copy(then_heap);
                                                                this.om_update(merged, else_heap);
                                                                this.alias.heap_sites = merged;
                                                            }
                                                                default {
                                                                this.alias.freed_sites = om_copy(pre_freed);
                                                                merged = om_copy(pre_heap);
                                                                this.om_update(merged, then_heap);
                                                                this.alias.heap_sites = merged;
                                                            };
                                                            };
                                                            ->;
                                                        }
                                                            default
                                                            {
                                                                switch (k == NodeKind.WHILE_LOOP)
                                                                {
                                                                    case (true) {
                                                                    this.walk_expr(node.a);
                                                                    switch (node.b != (Node*)0)
                                                                    {
                                                                        case (true) { this.walk_loop_body(node.b); }
                                                                        default {};
                                                                    };
                                                                    ->;
                                                                }
                                                                    default
                                                                    {
                                                                        switch (k == NodeKind.DO_WHILE_LOOP)
                                                                        {
                                                                            case (true) {
                                                                            switch (node.b != (Node*)0)
                                                                            {
                                                                                case (true) { this.walk_loop_body(node.b); }
                                                                                default {};
                                                                            };
                                                                            -> this.walk_expr(node.a);
                                                                        }
                                                                            default
                                                                            {
                                                                                switch (k == NodeKind.FOR_LOOP)
                                                                                {
                                                                                    case (true) {
                                                                                    switch (node.a != (Node*)0) { case (true) { this.walk_stmt(node.a); } default {}; };
                                                                                    switch (node.b != (Node*)0) { case (true) { this.walk_expr(node.b); } default {}; };
                                                                                    switch (node.c != (Node*)0) { case (true) { this.walk_stmt(node.c); } default {}; };
                                                                                    switch (node.d != (Node*)0) { case (true) { this.walk_loop_body(node.d); } default {}; };
                                                                                    ->;
                                                                                }
                                                                                    default
                                                                                    {
                                                                                        switch (k == NodeKind.FOR_IN_LOOP)
                                                                                        {
                                                                                            case (true) {
                                                                                            switch (node.b != (Node*)0) { case (true) { this.walk_loop_body(node.b); } default {}; };
                                                                                            ->;
                                                                                        }
                                                                                            default
                                                                                            {
                                                                                                switch (k == NodeKind.SWITCH_STATEMENT)
                                                                                                {
                                                                                                    case (true) {
                                                                                                    this.walk_expr(node.a);
                                                                                                    pre_freed = om_copy(this.alias.freed_sites);
                                                                                                    pre_heap = om_copy(this.alias.heap_sites);
                                                                                                    case_freeds = pv_new();
                                                                                                    case_heaps = pv_new();
                                                                                                    c = bc_count(node, 0);
                                                                                                    i = 0;
                                                                                                    while (i < c)
                                                                                                    {
                                                                                                        cs = node_child(node, 0, i);
                                                                                                        i++;
                                                                                                        this.alias.freed_sites = om_copy(pre_freed);
                                                                                                        this.alias.heap_sites = om_copy(pre_heap);
                                                                                                        switch (cs.b != (Node*)0)
                                                                                                        {
                                                                                                            case (true) { this.walk_block(cs.b); }
                                                                                                            default {};
                                                                                                        };
                                                                                                        pv_push(case_freeds, (void*)om_copy(this.alias.freed_sites));
                                                                                                        pv_push(case_heaps, (void*)om_copy(this.alias.heap_sites));
                                                                                                    };
                                                                                                    switch (case_freeds.len > 0)
                                                                                                    {
                                                                                                        case (true) {
                                                                                                        inter = om_copy((OMap*)case_freeds.items[0]);
                                                                                                        i = 1;
                                                                                                        while (i < case_freeds.len)
                                                                                                        {
                                                                                                            inter = this.om_intersect(inter, (OMap*)case_freeds.items[i]);
                                                                                                            i++;
                                                                                                        };
                                                                                                        this.alias.freed_sites = inter;
                                                                                                        merged = om_new();
                                                                                                        i = 0;
                                                                                                        while (i < case_heaps.len)
                                                                                                        {
                                                                                                            this.om_update(merged, (OMap*)case_heaps.items[i]);
                                                                                                            i++;
                                                                                                        };
                                                                                                        this.alias.heap_sites = merged;
                                                                                                    }
                                                                                                        default {
                                                                                                        this.alias.freed_sites = om_copy(pre_freed);
                                                                                                        this.alias.heap_sites = om_copy(pre_heap);
                                                                                                    };
                                                                                                    };
                                                                                                    ->;
                                                                                                }
                                                                                                    default
                                                                                                    {
                                                                                                        switch (k == NodeKind.RETURN_STATEMENT)
                                                                                                        {
                                                                                                            case (true) {
                                                                                                            switch (node.a != (Node*)0) { case (true) { this.walk_expr(node.a); } default {}; };
                                                                                                            ->;
                                                                                                        }
                                                                                                            default
                                                                                                            {
                                                                                                                switch (k == NodeKind.DEFER_STATEMENT)
                                                                                                                {
                                                                                                                    case (true) {
                                                                                                                    // deferred code runs at function exit: an ffree in it must not mark
                                                                                                                    // sites freed for use-after-free purposes; leak tracking still sees it
                                                                                                                    pre_freed = om_copy(this.alias.freed_sites);
                                                                                                                    switch (node.a != (Node*)0) { case (true) { this.walk_expr(node.a); } default {}; };
                                                                                                                    c = bc_count(node, 0);
                                                                                                                    i = 0;
                                                                                                                    while (i < c)
                                                                                                                    {
                                                                                                                        this.walk_stmt(node_child(node, 0, i));
                                                                                                                        i++;
                                                                                                                    };
                                                                                                                    this.alias.freed_sites = om_copy(pre_freed);
                                                                                                                    ->;
                                                                                                                }
                                                                                                                    default
                                                                                                                    {
                                                                                                                        switch (k == NodeKind.TRY_BLOCK)
                                                                                                                        {
                                                                                                                            case (true) {
                                                                                                                            pre_freed = om_copy(this.alias.freed_sites);
                                                                                                                            pre_heap = om_copy(this.alias.heap_sites);
                                                                                                                            switch (node.a != (Node*)0)
                                                                                                                            {
                                                                                                                                case (true) { this.walk_block(node.a); }
                                                                                                                                default {};
                                                                                                                            };
                                                                                                                            then_freed = om_copy(this.alias.freed_sites);
                                                                                                                            then_heap = om_copy(this.alias.heap_sites);
                                                                                                                            case_freeds = pv_new();
                                                                                                                            case_heaps = pv_new();
                                                                                                                            c = bc_count(node, 0);
                                                                                                                            i = 0;
                                                                                                                            while (i < c)
                                                                                                                            {
                                                                                                                                cs = node_child(node, 0, i);
                                                                                                                                i++;
                                                                                                                                this.alias.freed_sites = om_copy(pre_freed);
                                                                                                                                this.alias.heap_sites = om_copy(pre_heap);
                                                                                                                                switch (cs.a != (Node*)0)
                                                                                                                                {
                                                                                                                                    case (true) { this.walk_block(cs.a); }
                                                                                                                                    default {};
                                                                                                                                };
                                                                                                                                pv_push(case_freeds, (void*)om_copy(this.alias.freed_sites));
                                                                                                                                pv_push(case_heaps, (void*)om_copy(this.alias.heap_sites));
                                                                                                                            };
                                                                                                                            inter = om_copy(then_freed);
                                                                                                                            i = 0;
                                                                                                                            while (i < case_freeds.len)
                                                                                                                            {
                                                                                                                                inter = this.om_intersect(inter, (OMap*)case_freeds.items[i]);
                                                                                                                                i++;
                                                                                                                            };
                                                                                                                            this.alias.freed_sites = inter;
                                                                                                                            merged = om_copy(then_heap);
                                                                                                                            i = 0;
                                                                                                                            while (i < case_heaps.len)
                                                                                                                            {
                                                                                                                                this.om_update(merged, (OMap*)case_heaps.items[i]);
                                                                                                                                i++;
                                                                                                                            };
                                                                                                                            this.alias.heap_sites = merged;
                                                                                                                            ->;
                                                                                                                        }
                                                                                                                            default
                                                                                                                            {
                                                                                                                                switch (k == NodeKind.FUNCTION_DEF_STATEMENT)
                                                                                                                                {
                                                                                                                                    case (true) {
                                                                                                                                    // nested function definition, walked under the current context
                                                                                                                                    -> this.check_function(node.a, this.in_thread, pv_new());
                                                                                                                                }
                                                                                                                                    default
                                                                                                                                    {
                                                                                                                                        // other statements (break, continue, label, goto, assert) introduce no pointers
                                                                                                                                        ->;
                                                                                                                                    };
                                                                                                                                };
                                                                                                                            };
                                                                                                                        };
                                                                                                                    };
                                                                                                                };
                                                                                                            };
                                                                                                        };
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // ----- declarations and assignments -----

            // Value of a constant integer expression, as the FVM folds it. Sets lit_val.
            // Literals, casts, unary minus and the arithmetic and bit operators of constants.
            const_int(Node* e) -> bool
            {
                i64 lv;
                i64 rv;
                switch (e == (Node*)0)
                {
                    case (true) { -> false; }
                    default
                    {
                        switch (e.kind == NodeKind.LITERAL)
                        {
                            case (true) {
                            switch (e.op == DataType.SINT | e.op == DataType.UINT | e.op == DataType.SLONG | e.op == DataType.ULONG)
                            {
                                case (true) {
                                this.lit_val = e.ival;
                                -> true;
                            }
                                default {};
                            };
                            -> false;
                        }
                            default
                            {
                                switch (bc_is_cast(e))
                                {
                                    case (true) { -> this.const_int(e.a); }
                                    default
                                    {
                                        switch (e.kind == NodeKind.UNARY_OP)
                                        {
                                            case (true) {
                                            switch (e.op == Operator.SUB)
                                            {
                                                case (true) {
                                                switch (this.const_int(e.a))
                                                {
                                                    case (true) { this.lit_val = (i64)0 - this.lit_val; -> true; }
                                                    default {};
                                                };
                                            }
                                                default {};
                                            };
                                            -> false;
                                        }
                                            default
                                            {
                                                switch (e.kind == NodeKind.BINARY_OP)
                                                {
                                                    case (true) {
                                                    switch (!this.const_int(e.a)) { case (true) { -> false; } default {}; };
                                                    lv = this.lit_val;
                                                    switch (!this.const_int(e.b)) { case (true) { -> false; } default {}; };
                                                    rv = this.lit_val;
                                                    switch (e.op == Operator.ADD) { case (true) { this.lit_val = lv + rv; -> true; } default {}; };
                                                    switch (e.op == Operator.SUB) { case (true) { this.lit_val = lv - rv; -> true; } default {}; };
                                                    switch (e.op == Operator.MUL) { case (true) { this.lit_val = lv * rv; -> true; } default {}; };
                                                    switch (e.op == Operator.DIV & rv > (i64)0 & lv >= (i64)0) { case (true) { this.lit_val = lv / rv; -> true; } default {}; };
                                                    switch (e.op == Operator.MOD & rv > (i64)0 & lv >= (i64)0) { case (true) { this.lit_val = lv % rv; -> true; } default {}; };
                                                    switch (e.op == Operator.BITSHIFT_LEFT & rv >= (i64)0 & rv < (i64)63) { case (true) { this.lit_val = lv << (int)rv; -> true; } default {}; };
                                                    switch (e.op == Operator.BITSHIFT_RIGHT & rv >= (i64)0 & rv < (i64)63 & lv >= (i64)0) { case (true) { this.lit_val = lv >> (int)rv; -> true; } default {}; };
                                                    switch (e.op == Operator.BITAND) { case (true) { this.lit_val = lv `& rv; -> true; } default {}; };
                                                    switch (e.op == Operator.BITOR) { case (true) { this.lit_val = lv `| rv; -> true; } default {}; };
                                                    switch (e.op == Operator.BITXOR) { case (true) { this.lit_val = lv `^| rv; -> true; } default {}; };
                                                    -> false;
                                                }
                                                    default
                                                    {
                                                        -> false;
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };

            rhs_is_heap_alloc(Node* e) -> bool
            {
                switch (e == (Node*)0)
                {
                    case (true) { -> false; }
                    default
                    {
                        switch (bc_is_fmalloc(e))
                        {
                            case (true) { -> true; }
                            default
                            {
                                switch (bc_is_cast(e))
                                {
                                    case (true) { -> this.rhs_is_heap_alloc(e.a); }
                                    default
                                    {
                                        -> false;
                                    };
                                };
                            };
                        };
                    };
                };
            };

            on_var_decl(Node* node) -> void
            {
                byte* file = bc_unk();
                int line = node.line;
                bool is_ptr = bc_is_pointer_type(node.ts);
                byte* site;
                byte* ptr_site;
                ScopeFrame* frame;
                switch (!is_ptr & this.check_leaks & this.rhs_is_heap_alloc(node.a))
                {
                    case (true) { is_ptr = true; }
                    default {};
                };
                site = bc_stack_site(this.alias.func_name, node.text, line);
                switch (is_ptr)
                {
                    case (true) {
                    ptr_site = this.resolve_site(node.a, node.text, file, line);
                    this.alias.declare_ptr(node.text, ptr_site, true, file, line, false);
                }
                    default {
                    // non-pointer stack variable: register its site so @name resolves
                    switch (this.alias.frames.len > 0)
                    {
                        case (true) {
                        frame = (ScopeFrame*)this.alias.frames.items[this.alias.frames.len - 1];
                        om_put(frame.owned, site, (void*)1);
                        om_put(frame.var_sites, node.text, site);
                    }
                        default {};
                    };
                    // a fixed size stack array records its element count for bounds checks
                    switch (node.ts != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (node.ts.array_size != (Node*)0)
                        {
                            case (true) {
                            switch (this.const_int(node.ts.array_size))
                            {
                                case (true) { this.alias.record_alloc_size(site, (int)this.lit_val); }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                };
                };
                switch (node.a != (Node*)0)
                {
                    case (true) { this.walk_expr(node.a); }
                    default {};
                };
                ->;
            };

            // Remembers that array arr holds the heap site of pointer variable ptr_name
            note_array_store(byte* arr_name, byte* ptr_name) -> void
            {
                BPtr* info = this.alias.find_ptr(ptr_name);
                PtrVec* lst;
                int i;
                bool dup;
                switch (info == (BPtr*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        switch (!om_has(this.alias.heap_sites, info.site))
                        {
                            case (true) { ->; }
                            default
                            {
                                lst = (PtrVec*)om_get(this.array_heap, arr_name);
                                switch (lst == (PtrVec*)0)
                                {
                                    case (true) {
                                    lst = pv_new();
                                    om_put(this.array_heap, arr_name, (void*)lst);
                                }
                                    default {};
                                };
                                while (i < lst.len)
                                {
                                    switch (cstr_eq((byte*)lst.items[i], info.site)) { case (true) { dup = true; } default {}; };
                                    i++;
                                };
                                switch (!dup)
                                {
                                    case (true) { pv_push(lst, (void*)info.site); }
                                    default {};
                                };
                                ->;
                            };
                        };
                    };
                };
            };

            on_assign(Node* node) -> void
            {
                byte* file = bc_unk();
                int line = node.line;
                byte* var_name;
                byte* new_site;
                this.walk_expr(node.b);
                switch (node.a.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    var_name = node.a.text;
                    switch (this.alias.find_ptr(var_name) != (BPtr*)0)
                    {
                        case (true) {
                        new_site = this.resolve_site(node.b, var_name, file, line);
                        this.alias.assign_ptr(var_name, new_site, true, file, line);
                    }
                        default {
                        switch (this.check_leaks & this.rhs_is_heap_alloc(node.b))
                        {
                            case (true) {
                            // a non pointer typed variable assigned an fmalloc result
                            new_site = this.resolve_site(node.b, var_name, file, line);
                            this.alias.declare_ptr(var_name, new_site, true, file, line, false);
                        }
                            default {};
                        };
                    };
                    };
                }
                    default {};
                };
                // arr[i] = ptr: record heap sites stored into arrays
                switch (this.check_leaks & node.a.kind == NodeKind.ARRAY_ACCESS)
                {
                    case (true) {
                    switch (node.a.a.kind == NodeKind.IDENTIFIER & node.b.kind == NodeKind.IDENTIFIER)
                    {
                        case (true) { this.note_array_store(node.a.a.text, node.b.text); }
                        default {};
                    };
                }
                    default {};
                };
                ->;
            };

            in_spawn_impl() -> bool
            {
                byte* f = this.alias.func_name;
                -> bc_contains(f, g"thread_create\0") | bc_contains(f, g"pthread_create\0") | bc_contains(f, g"CreateThread\0");
            };

            check_ident_escape(byte* name, byte* file, int line) -> void
            {
                switch (this.check_threads & !this.in_spawn_impl())
                {
                    case (true) { this.alias.check_use_after_escape(name, file, line); }
                    default {};
                };
                ->;
            };

            // Name of the variable behind casts, address-of and the first argument of a call
            unwrap_ptr_ident(Node* e) -> byte*
            {
                switch (e == (Node*)0)
                {
                    case (true) { -> (byte*)0; }
                    default
                    {
                        switch (e.kind == NodeKind.IDENTIFIER)
                        {
                            case (true) { -> e.text; }
                            default
                            {
                                switch (bc_is_cast(e) | e.kind == NodeKind.ADDRESS_OF)
                                {
                                    case (true) { -> this.unwrap_ptr_ident(e.a); }
                                    default
                                    {
                                        switch (e.kind == NodeKind.FUNCTION_CALL & bc_count(e, 0) > 0)
                                        {
                                            case (true) { -> this.unwrap_ptr_ident(node_child(e, 0, 0)); }
                                            default
                                            {
                                                -> (byte*)0;
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // ----- argument and context helpers -----

            collect_arg_sites(NodeVec* args, byte* file, int line, PtrVec* names, PtrVec* sites) -> void
            {
                int i;
                byte* hint;
                Node* a;
                switch (args == (NodeVec*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        while (i < args.len)
                        {
                            a = args.items[i];
                            hint = this.unwrap_ptr_ident(a);
                            switch (hint == (byte*)0)
                            {
                                case (true) { hint = g"<arg>\0"; }
                                default {
                                switch (hint[0] == 0) { case (true) { hint = g"<arg>\0"; } default {}; };
                            };
                            };
                            pv_push(names, (void*)hint);
                            pv_push(sites, (void*)this.resolve_site(a, hint, file, line));
                            i++;
                        };
                        ->;
                    };
                };
            };

            // Sites of the pointer arguments, in parameter order, as the cache key of a call
            build_call_ctx(Node* func, NodeVec* args, byte* file, int line) -> PtrVec*
            {
                PtrVec* r = pv_new();
                PtrVec* pp2 = this.ptr_params(func);
                int c = bc_count(func, 0);
                int i;
                int j;
                int full_idx;
                Node* p;
                Node* q;
                int nargs;
                switch (pp2.len == 0)
                {
                    case (true) { -> r; }
                    default
                    {
                        nargs = 0;
                        switch (args != (NodeVec*)0) { case (true) { nargs = args.len; } default {}; };
                        while (i < pp2.len)
                        {
                            p = (Node*)pp2.items[i];
                            full_idx = -1;
                            j = 0;
                            while (j < c)
                            {
                                q = node_child(func, 0, j);
                                switch (full_idx < 0 & q.text != (byte*)0)
                                {
                                    case (true) {
                                    switch (cstr_eq(q.text, p.text)) { case (true) { full_idx = j; } default {}; };
                                }
                                    default {};
                                };
                                j++;
                            };
                            switch (full_idx >= 0 & full_idx < nargs)
                            {
                                case (true) { pv_push(r, (void*)this.resolve_site(args.items[full_idx], p.text, file, line)); }
                                default { pv_push(r, (void*)g"unknown\0"); };
                            };
                            i++;
                        };
                        -> r;
                    };
                };
            };

            // Argument of ffree resolved to a heap site
            resolve_ffree_arg(Node* arg) -> byte*
            {
                BPtr* info;
                PtrVec* lst;
                byte* s;
                int j;
                switch (arg.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    info = this.alias.find_ptr(arg.text);
                    switch (info != (BPtr*)0) { case (true) { -> info.site; } default {}; };
                    -> g"unknown\0";
                }
                    default
                    {
                        switch (arg.kind == NodeKind.CAST_EXPRESSION)
                        {
                            case (true) { -> this.resolve_ffree_arg(arg.a); }
                            default
                            {
                                switch (arg.kind == NodeKind.FUNCTION_CALL & arg.text != (byte*)0 & bc_count(arg, 0) > 0)
                                {
                                    case (true) { -> this.resolve_ffree_arg(node_child(arg, 0, 0)); }
                                    default
                                    {
                                        switch (arg.kind == NodeKind.ADDRESS_OF)
                                        {
                                            case (true) {
                                            switch (arg.a.kind == NodeKind.IDENTIFIER)
                                            {
                                                case (true) {
                                                info = this.alias.find_ptr(arg.a.text);
                                                switch (info != (BPtr*)0) { case (true) { -> info.site; } default
                                                    {
                                                        -> g"unknown\0";
                                                    }; };
                                            }
                                                default {};
                                            };
                                        }
                                            default {};
                                        };
                                        switch (arg.kind == NodeKind.TYPE_CONVERT_EXPRESSION)
                                        {
                                            case (true) { -> this.resolve_ffree_arg(arg.a); }
                                            default
                                            {
                                                // arr[i]: take and remove one heap site recorded for arr
                                                switch (arg.kind == NodeKind.ARRAY_ACCESS)
                                                {
                                                    case (true) {
                                                    switch (arg.a.kind == NodeKind.IDENTIFIER)
                                                    {
                                                        case (true) {
                                                        lst = (PtrVec*)om_get(this.array_heap, arg.a.text);
                                                        switch (lst != (PtrVec*)0)
                                                        {
                                                            case (true) {
                                                            switch (lst.len > 0)
                                                            {
                                                                case (true) {
                                                                s = (byte*)lst.items[0];
                                                                j = 0;
                                                                while (j < lst.len - 1)
                                                                {
                                                                    lst.items[j] = lst.items[j + 1];
                                                                    j++;
                                                                };
                                                                lst.len--;
                                                                -> s;
                                                            }
                                                                default {};
                                                            };
                                                        }
                                                            default {};
                                                        };
                                                    }
                                                        default {};
                                                    };
                                                }
                                                    default {};
                                                };
                                                -> g"unknown\0";
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // ----- allocation site resolution -----

            var_site_of(byte* name) -> byte*
            {
                int fi = this.alias.frames.len - 1;
                ScopeFrame* f;
                int k;
                while (fi >= 0)
                {
                    f = (ScopeFrame*)this.alias.frames.items[fi];
                    k = om_find(f.var_sites, name);
                    switch (k >= 0) { case (true) { -> (byte*)f.var_sites.vs.items[k]; } default
                        {
                            fi--;
                        }; };
                };
                -> (byte*)0;
            };

            // param:<func>:<literal text stripped of surrounding whitespace>
            str_site(Node* e) -> byte*
            {
                int n = (int)e.ival;
                int a = 0;
                int b;
                int c;
                bool going = true;
                switch (n <= 0) { case (true) { n = bc_len(e.text); } default {}; };
                while (a < n & going)
                {
                    c = (int)e.text[a];
                    if ((c >= 9 & c <= 13) | (c >= 28 & c <= 32)) { a++; } else { going = false; };
                };
                b = n;
                going = true;
                while (b > a & going)
                {
                    c = (int)e.text[b - 1];
                    if ((c >= 9 & c <= 13) | (c >= 28 & c <= 32)) { b--; } else { going = false; };
                };
                this.sb.clear();
                this.sb.put_str(f"param:{this.alias.func_name}:\0");
                c = a;
                while (c < b)
                {
                    if (e.text[c] == 0) { break; };
                    this.sb.put((int)e.text[c]);
                    c++;
                };
                -> ts_dup(this.sb.mem);
            };

            resolve_site(Node* expr, byte* var_name, byte* file, int line) -> byte*
            {
                Node* inner;
                byte* s;
                byte* t;
                BPtr* info;
                switch (expr == (Node*)0)
                {
                    case (true) { -> g"unknown\0"; }
                    default
                    {
                        // @var or @arr[i]: address of a stack variable or element
                        switch (expr.kind == NodeKind.ADDRESS_OF)
                        {
                            case (true) {
                            inner = expr.a;
                            switch (inner.kind == NodeKind.IDENTIFIER)
                            {
                                case (true) {
                                s = this.var_site_of(inner.text);
                                switch (s != (byte*)0) { case (true) { -> s; } default {}; };
                                -> bc_stack_site(this.alias.func_name, inner.text, line);
                            }
                                default {};
                            };
                            switch (inner.kind == NodeKind.ARRAY_ACCESS)
                            {
                                case (true) {
                                switch (inner.a.kind == NodeKind.IDENTIFIER)
                                {
                                    case (true) {
                                    s = this.var_site_of(inner.a.text);
                                    switch (s != (byte*)0) { case (true) { -> s; } default {}; };
                                    -> bc_stack_site(this.alias.func_name, inner.a.text, line);
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                            -> g"unknown\0";
                        }
                            default
                            {
                                switch (bc_is_fmalloc(expr))
                                {
                                    case (true) { -> bc_heap_site(this.alias.func_name, expr.line); }
                                    default
                                    {
                                        switch (bc_is_ffree(expr))
                                        {
                                            case (true) { -> g"unknown\0"; }
                                            default
                                            {
                                                // pointer arithmetic: derived from the base
                                                switch (expr.kind == NodeKind.BINARY_OP)
                                                {
                                                    case (true) {
                                                    switch (expr.op == Operator.ADD | expr.op == Operator.SUB)
                                                    {
                                                        case (true) {
                                                        s = this.resolve_site(expr.a, var_name, file, line);
                                                        switch (!cstr_eq(s, g"unknown\0")) { case (true) { -> bc_prefixed(g"derived:\0", s); } default
                                                            {
                                                                t = this.resolve_site(expr.b, var_name, file, line);
                                                                switch (!cstr_eq(t, g"unknown\0")) { case (true) { -> t; } default
                                                                    {
                                                                        -> g"unknown\0";
                                                                    }; };
                                                            }; };
                                                    }
                                                        default {};
                                                    };
                                                }
                                                    default {};
                                                };
                                                // identifier: copy the site of the tracked pointer
                                                switch (expr.kind == NodeKind.IDENTIFIER)
                                                {
                                                    case (true) {
                                                    info = this.alias.find_ptr(expr.text);
                                                    switch (info != (BPtr*)0)
                                                    {
                                                        case (true) {
                                                        switch (om_has(this.alias.freed_sites, info.site))
                                                        {
                                                            case (true) { -> bc_prefixed(g"freed:\0", info.site); }
                                                            default {};
                                                        };
                                                        -> info.site;
                                                    }
                                                        default {};
                                                    };
                                                    s = this.var_site_of(expr.text);
                                                    switch (s != (byte*)0) { case (true) { -> s; } default {}; };
                                                    -> g"unknown\0";
                                                }
                                                    default
                                                    {
                                                        // string literal: the FVM leaves its bytes on the stack, which fbc.py names as a param site
                                                        switch (expr.kind == NodeKind.STRING_LITERAL)
                                                        {
                                                            case (true) { -> this.str_site(expr); }
                                                            default
                                                            {
                                                                // cast: a derived view, except directly around fmalloc, which stays a fresh allocation
                                                                switch (bc_is_cast(expr))
                                                                {
                                                                    case (true) {
                                                                    switch (bc_is_fmalloc(expr.a))
                                                                    {
                                                                        case (true) { -> bc_heap_site(this.alias.func_name, expr.a.line); }
                                                                        default {};
                                                                    };
                                                                    s = this.resolve_site(expr.a, var_name, file, line);
                                                                    switch (!cstr_eq(s, g"unknown\0")) { case (true) { -> bc_prefixed(g"derived:\0", s); } default {}; };
                                                                    -> g"unknown\0";
                                                                }
                                                                    default
                                                                    {
                                                                        -> g"unknown\0";
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // ----- bounds -----

            check_bounds_at_access(byte* var_name, Node* index_expr, byte* file, int line, bool write) -> void
            {
                int idx;
                int fi;
                int k;
                ScopeFrame* f;
                byte* site;
                int size;
                PtrVec* det;
                switch (index_expr == (Node*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        // only a constant integer index is determinable without the FVM
                        switch (!this.const_int(index_expr))
                        {
                            case (true) { ->; }
                            default
                            {
                                idx = (int)this.lit_val;
                                switch (this.alias.find_ptr(var_name) != (BPtr*)0)
                                {
                                    case (true) {
                                    -> this.alias.check_bounds(var_name, idx, file, line, write);
                                }
                                    default
                                    {
                                        // stack arrays and pointer parameters with known sizes
                                        fi = this.alias.frames.len - 1;
                                        while (fi >= 0)
                                        {
                                            f = (ScopeFrame*)this.alias.frames.items[fi];
                                            k = om_find(f.var_sites, var_name);
                                            switch (k >= 0)
                                            {
                                                case (true) {
                                                site = (byte*)f.var_sites.vs.items[k];
                                                switch (om_has(this.alias.alloc_sizes, site))
                                                {
                                                    case (true) {
                                                    size = ((int*)om_get(this.alias.alloc_sizes, site))[0];
                                                    switch (size >= 0 & (idx < 0 | idx >= size))
                                                    {
                                                        case (true) {
                                                        det = pv_new();
                                                        this.sb.clear();
                                                        this.sb.put_str(f"'{var_name}' -> {site} (size {size})\0");
                                                        pv_push(det, (void*)ts_dup(this.sb.mem));
                                                        this.sb.clear();
                                                        this.sb.put_str(f"index {idx}\0");
                                                        switch (idx < 0)
                                                        {
                                                            case (true) { this.sb.put_str(g" < 0\0"); }
                                                            default { this.sb.put_str(g" >= size\0"); };
                                                        };
                                                        pv_push(det, (void*)ts_dup(this.sb.mem));
                                                        this.sb.clear();
                                                        this.sb.put_str(g"array \0");
                                                        switch (write)
                                                        {
                                                            case (true) { this.sb.put_str(g"write\0"); }
                                                            default { this.sb.put_str(g"access\0"); };
                                                        };
                                                        this.sb.put_str(f" on '{var_name}' at index {idx} is out of bounds (size {size})\0");
                                                        switch (write)
                                                        {
                                                            case (true) { this.alias.add_vio(g"buffer_overflow\0", ts_dup(this.sb.mem), file, line, det); }
                                                            default { this.alias.add_vio(g"out_of_bounds\0", ts_dup(this.sb.mem), file, line, det); };
                                                        };
                                                    }
                                                        default {};
                                                    };
                                                }
                                                    default {};
                                                };
                                                ->;
                                            }
                                                default
                                                {
                                                    fi--;
                                                };
                                            };
                                        };
                                        ->;
                                    };
                                };
                            };
                        };
                    };
                };
            };

            // ----- expression walk -----

            walk_args(NodeVec* args) -> void
            {
                int i;
                switch (args == (NodeVec*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        while (i < args.len)
                        {
                            this.walk_expr(args.items[i]);
                            i++;
                        };
                        ->;
                    };
                };
            };

            // Calls into the callee body if its context was not analysed yet
            enter_callee(byte* name, NodeVec* args, byte* file, int line) -> void
            {
                Node* f = (Node*)nm_get(this.cg.funcs, name);
                PtrVec* ctx = this.build_call_ctx(f, args, file, line);
                switch (!this.cg.is_visited(name, ctx, this.in_thread))
                {
                    case (true) { this.check_function(f, this.in_thread, ctx); }
                    default {};
                };
                ->;
            };

            handle_spawn(Node* node, byte* file, int line) -> void
            {
                NodeVec* args = node.l0;
                byte* spawned = (byte*)0;
                byte* cand;
                int i;
                Node* sf;
                PtrVec* ctx;
                PtrVec* mp;
                int* sc;
                int prev_count;
                PtrVec* det;
                byte* shortn;
                Node* mpn;
                int na = 0;
                switch (args != (NodeVec*)0) { case (true) { na = args.len; } default {}; };
                while (i < na & spawned == (byte*)0)
                {
                    cand = this.unwrap_ptr_ident(args.items[i]);
                    i++;
                    switch (cand != (byte*)0)
                    {
                        case (true) {
                        switch (cand[0] != 0)
                        {
                            case (true) {
                            switch (nm_has(this.cg.funcs, cand))
                            {
                                case (true) { spawned = cand; }
                                default {
                                shortn = (byte*)nm_get(this.cg.short_names, cand);
                                switch (shortn != (byte*)0)
                                {
                                    case (true) { spawned = shortn; }
                                    default {};
                                };
                            };
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                };
                i = 0;
                while (i < na)
                {
                    cand = this.unwrap_ptr_ident(args.items[i]);
                    i++;
                    switch (cand != (byte*)0)
                    {
                        case (true) {
                        switch (cand[0] != 0) { case (true) { this.alias.check_thread_escape(cand, file, line); } default {}; };
                    }
                        default {};
                    };
                };
                switch (spawned != (byte*)0)
                {
                    case (true) {
                    switch (nm_has(this.cg.funcs, spawned))
                    {
                        case (true) {
                        sc = (int*)nm_get(this.cg.spawn_count, spawned);
                        prev_count = 0;
                        switch (sc != (int*)0) { case (true) { prev_count = sc[0]; } default {}; };
                        nm_put(this.cg.spawn_count, spawned, (void*)bx_new(prev_count + 1));
                        sf = (Node*)nm_get(this.cg.funcs, spawned);
                        ctx = this.build_call_ctx(sf, args, file, line);
                        switch (!this.cg.is_visited(spawned, ctx, true))
                        {
                            case (true) { this.check_function(sf, true, ctx); }
                            default {};
                        };
                        // spawned more than once: mutable pointer params can race with themselves
                        switch (prev_count >= 1)
                        {
                            case (true) {
                            mp = this.ptr_params(sf);
                            switch (mp.len > 0)
                            {
                                case (true) {
                                this.sb.clear();
                                this.sb.put_str(f"function '{spawned}' is spawned as a thread \0");
                                this.sb.put_int(prev_count + 1);
                                this.sb.put_str(g" times -- concurrent instances share mutable pointer parameter(s): \0");
                                i = 0;
                                while (i < mp.len)
                                {
                                    switch (i > 0) { case (true) { this.sb.put_str(g", \0"); } default {}; };
                                    mpn = (Node*)mp.items[i];
                                    this.sb.put_str(mpn.text);
                                    i++;
                                };
                                det = pv_new();
                                pv_push(det, (void*)g"each spawn receives a separate pointer value but if those values alias the same allocation site, a data race exists between the concurrent instances\0");
                                this.add_direct(g"thread_self_race\0", ts_dup(this.sb.mem), file, line, det);
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                ->;
            };

            // Violation appended to the checker list as is, without the line map
            add_direct(byte* kind, byte* msg, byte* file, int line, PtrVec* det) -> void
            {
                BVio* v = (BVio*)fmalloc((u64)((sizeof(BVio) + 7) / 8));
                v.kind = kind;
                v.msg = msg;
                v.file = file;
                v.line = line;
                v.detail = det;
                v.func = this.alias.func_name;
                -> pv_push(this.violations, (void*)v);
            };

            handle_call(Node* node, byte* file, int line) -> void
            {
                byte* callee = node.text;
                byte* resolved;
                byte* base_name;
                bool is_alloc;
                PtrVec* ov;
                PtrVec* names;
                PtrVec* sites;
                int i;
                switch (callee != (byte*)0)
                {
                    case (true) { switch (callee[0] == 0) { case (true) { callee = (byte*)0; } default {}; }; }
                    default {};
                };
                switch (callee != (byte*)0)
                {
                    case (true) {
                    resolved = (byte*)0;
                    switch (nm_has(this.cg.funcs, callee))
                    {
                        case (true) { resolved = callee; }
                        default { resolved = (byte*)nm_get(this.cg.short_names, callee); };
                    };
                    // never walk into allocator bodies: their internals would pollute the site tables
                    switch (resolved != (byte*)0)
                    {
                        case (true) { base_name = bc_last_seg(resolved); }
                        default { base_name = bc_last_seg(callee); };
                    };
                    is_alloc = cstr_eq(base_name, g"fmalloc\0") | cstr_eq(base_name, g"ffree\0")
                               | cstr_eq(callee, g"fmalloc\0") | cstr_eq(callee, g"ffree\0");
                    switch (resolved != (byte*)0 & !is_alloc)
                    {
                        case (true) { this.enter_callee(resolved, node.l0, file, line); }
                        default {
                        switch (!is_alloc)
                        {
                            case (true) {
                            ov = (PtrVec*)nm_get(this.cg.overloads, callee);
                            switch (ov != (PtrVec*)0)
                            {
                                case (true) {
                                i = 0;
                                while (i < ov.len)
                                {
                                    this.enter_callee((byte*)ov.items[i], node.l0, file, line);
                                    i++;
                                };
                            }
                                default {};
                            };
                            // callee not in the call graph (extern or runtime function pointer)
                            switch (ov == (PtrVec*)0)
                            {
                                case (true) {
                                names = pv_new();
                                sites = pv_new();
                                this.collect_arg_sites(node.l0, file, line, names, sites);
                                this.alias.check_call_args(names, sites, file, line);
                            }
                                default {
                                switch (ov.len == 0)
                                {
                                    case (true) {
                                    names = pv_new();
                                    sites = pv_new();
                                    this.collect_arg_sites(node.l0, file, line, names, sites);
                                    this.alias.check_call_args(names, sites, file, line);
                                }
                                    default {};
                                };
                            };
                            };
                        }
                            default {};
                        };
                    };
                    };
                }
                    default {
                    names = pv_new();
                    sites = pv_new();
                    this.collect_arg_sites(node.l0, file, line, names, sites);
                    this.alias.check_call_args(names, sites, file, line);
                };
                };
                -> this.walk_args(node.l0);
            };

            handle_method_call(Node* node, byte* file, int line) -> void
            {
                byte* method = node.text;
                byte* hint;
                byte* resolved = (byte*)0;
                byte* cand;
                byte* sfx;
                byte* shortn;
                int pass;
                int i;
                PtrVec* names;
                PtrVec* sites;
                this.walk_expr(node.a);
                this.walk_args(node.l0);
                switch (method == (byte*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        switch (method[0] == 0)
                        {
                            case (true) { ->; }
                            default
                            {
                                hint = this.unwrap_ptr_ident(node.a);
                                switch (hint == (byte*)0) { case (true) { hint = g"\0"; } default {}; };
                                // candidates: <obj>__<method> when there is an object variable, then the bare method name
                                pass = 0;
                                while (pass < 2 & resolved == (byte*)0)
                                {
                                    cand = (byte*)0;
                                    switch (pass == 0)
                                    {
                                        case (true) {
                                        switch (hint[0] != 0) { case (true) { cand = join3(hint, g"__\0", method); } default {}; };
                                    }
                                        default { cand = method; };
                                    };
                                    switch (cand != (byte*)0)
                                    {
                                        case (true) {
                                        switch (nm_has(this.cg.funcs, cand))
                                        {
                                            case (true) { resolved = cand; }
                                            default {
                                            shortn = (byte*)nm_get(this.cg.short_names, cand);
                                            switch (shortn != (byte*)0) { case (true) { resolved = shortn; } default {}; };
                                        };
                                        };
                                    }
                                        default {};
                                    };
                                    pass++;
                                };
                                // any function whose mangled name ends with __<method>
                                switch (resolved == (byte*)0)
                                {
                                    case (true) {
                                    sfx = join3(g"__\0", method, g"\0");
                                    i = 0;
                                    while (i < this.cg.funcs.count & resolved == (byte*)0)
                                    {
                                        switch (this.cg.funcs.vals[i] != (void*)0)
                                        {
                                            case (true) {
                                            switch (bc_ends(this.cg.funcs.keys[i], sfx))
                                            {
                                                case (true) { resolved = this.cg.funcs.keys[i]; }
                                                default {};
                                            };
                                        }
                                            default {};
                                        };
                                        i++;
                                    };
                                }
                                    default {};
                                };
                                switch (resolved != (byte*)0)
                                {
                                    case (true) { this.enter_callee(resolved, node.l0, file, line); }
                                    default {
                                    names = pv_new();
                                    sites = pv_new();
                                    this.collect_arg_sites(node.l0, file, line, names, sites);
                                    this.alias.check_call_args(names, sites, file, line);
                                };
                                };
                                ->;
                            };
                        };
                    };
                };
            };

            // Assignment met inside an expression
            handle_assign_expr(Node* node, byte* file, int line) -> void
            {
                Node* arr;
                byte* new_site;
                this.walk_expr(node.b);
                switch (this.check_threads)
                {
                    case (true) {
                    switch (node.a.kind == NodeKind.IDENTIFIER)
                    {
                        case (true) { this.check_ident_escape(node.a.text, file, line); }
                        default {
                        switch (node.a.kind == NodeKind.ARRAY_ACCESS)
                        {
                            case (true) {
                            switch (node.a.a.kind == NodeKind.IDENTIFIER)
                            {
                                case (true) { this.check_ident_escape(node.a.a.text, file, line); }
                                default {};
                            };
                        }
                            default {};
                        };
                    };
                    };
                }
                    default {};
                };
                switch (node.a.kind == NodeKind.POINTER_DEREF)
                {
                    case (true) {
                    arr = node.a.a;
                    switch (arr.kind == NodeKind.IDENTIFIER)
                    {
                        case (true) {
                        this.alias.check_use_after_free(arr.text, file, line);
                        this.alias.check_write_alias(arr.text, file, line);
                    }
                        default {};
                    };
                }
                    default {
                    switch (node.a.kind == NodeKind.ARRAY_ACCESS)
                    {
                        case (true) {
                        arr = node.a.a;
                        switch (arr.kind == NodeKind.IDENTIFIER)
                        {
                            case (true) {
                            this.alias.check_use_after_free(arr.text, file, line);
                            this.alias.check_write_alias(arr.text, file, line);
                            this.check_bounds_at_access(arr.text, node.a.b, file, line, true);
                            switch (this.check_leaks & node.b.kind == NodeKind.IDENTIFIER)
                            {
                                case (true) { this.note_array_store(arr.text, node.b.text); }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                };
                };
                switch (node.a.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (this.alias.find_ptr(node.a.text) != (BPtr*)0)
                    {
                        case (true) {
                        new_site = this.resolve_site(node.b, node.a.text, bc_unk(), node.line);
                        this.alias.assign_ptr(node.a.text, new_site, true, bc_unk(), node.line);
                    }
                        default {};
                    };
                }
                    default {};
                };
                ->;
            };

            walk_expr(Node* node) -> void
            {
                byte* file;
                int line;
                int k;
                Node* fnode;
                byte* site;
                Node* arg;
                byte* freed_site;
                switch (node == (Node*)0)
                {
                    case (true) { ->; }
                    default
                    {
                        file = bc_unk();
                        line = node.line;
                        k = node.kind;

                        // fmalloc may be wrapped in a cast
                        fnode = node;
                        switch (bc_is_cast(node))
                        {
                            case (true) { fnode = node.a; }
                            default {};
                        };
                        switch (fnode != (Node*)0 & this.check_leaks)
                        {
                            case (true) {
                            switch (bc_is_fmalloc(fnode))
                            {
                                case (true) {
                                site = bc_heap_site(this.alias.func_name, fnode.line);
                                this.alias.record_malloc(site, file, fnode.line);
                                // the size is recorded when the argument is an integer literal
                                switch (bc_count(fnode, 0) > 0)
                                {
                                    case (true) {
                                    switch (this.const_int(node_child(fnode, 0, 0)))
                                    {
                                        case (true) { this.alias.record_alloc_size(site, (int)this.lit_val); }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                        }
                            default {};
                        };

                        switch (bc_is_ffree(node) & this.check_leaks)
                        {
                            case (true) {
                            switch (bc_count(node, 0) > 0)
                            {
                                case (true) {
                                arg = node_child(node, 0, 0);
                                freed_site = this.resolve_ffree_arg(arg);
                                switch (freed_site[0] != 0 & !cstr_eq(freed_site, g"unknown\0"))
                                {
                                    case (true) {
                                    this.alias.record_free(freed_site);
                                    this.alias.mark_freed(freed_site, file, line);
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                        }
                            default {};
                        };

                        switch (this.check_threads)
                        {
                            case (true) {
                            switch (bc_is_thread_spawn(node))
                            {
                                case (true) { this.handle_spawn(node, file, line); }
                                default {};
                            };
                            switch (k == NodeKind.IDENTIFIER)
                            {
                                case (true) { this.check_ident_escape(node.text, file, line); }
                                default {};
                            };
                        }
                            default {};
                        };

                        switch (k == NodeKind.FUNCTION_CALL)
                        {
                            case (true) { -> this.handle_call(node, file, line); }
                            default
                            {
                                switch (k == NodeKind.METHOD_CALL)
                                {
                                    case (true) { -> this.handle_method_call(node, file, line); }
                                    default
                                    {
                                        switch (k == NodeKind.BINARY_OP)
                                        {
                                            case (true) { this.walk_expr(node.a); this.walk_expr(node.b); ->; }
                                            default
                                            {
                                                switch (k == NodeKind.UNARY_OP | k == NodeKind.ADDRESS_OF | bc_is_cast(node))
                                                {
                                                    case (true) { -> this.walk_expr(node.a); }
                                                    default
                                                    {
                                                        switch (k == NodeKind.POINTER_DEREF)
                                                        {
                                                            case (true) {
                                                            switch (node.a.kind == NodeKind.IDENTIFIER)
                                                            {
                                                                case (true) {
                                                                switch (this.check_threads)
                                                                {
                                                                    case (true) { this.alias.check_use_after_escape(node.a.text, file, line); }
                                                                    default {};
                                                                };
                                                                this.alias.check_use_after_free(node.a.text, file, line);
                                                            }
                                                                default {};
                                                            };
                                                            -> this.walk_expr(node.a);
                                                        }
                                                            default
                                                            {
                                                                switch (k == NodeKind.MEMBER_ACCESS)
                                                                {
                                                                    case (true) { -> this.walk_expr(node.a); }
                                                                    default
                                                                    {
                                                                        switch (k == NodeKind.ARRAY_ACCESS)
                                                                        {
                                                                            case (true) {
                                                                            switch (node.a.kind == NodeKind.IDENTIFIER)
                                                                            {
                                                                                case (true) {
                                                                                switch (this.check_threads)
                                                                                {
                                                                                    case (true) { this.alias.check_use_after_escape(node.a.text, file, line); }
                                                                                    default {};
                                                                                };
                                                                                this.alias.check_use_after_free(node.a.text, file, line);
                                                                                this.check_bounds_at_access(node.a.text, node.b, file, line, false);
                                                                            }
                                                                                default {};
                                                                            };
                                                                            this.walk_expr(node.a);
                                                                            -> this.walk_expr(node.b);
                                                                        }
                                                                            default
                                                                            {
                                                                                switch (k == NodeKind.IF_EXPRESSION)
                                                                                {
                                                                                    case (true) {
                                                                                    // condition, value, else (fbc.py reads then_expr, which IfExpression does not have)
                                                                                    this.walk_expr(node.b);
                                                                                    this.walk_expr(node.a);
                                                                                    -> this.walk_expr(node.c);
                                                                                }
                                                                                    default
                                                                                    {
                                                                                        switch (k == NodeKind.TERNARY_OP)
                                                                                        {
                                                                                            case (true) {
                                                                                            this.walk_expr(node.a);
                                                                                            this.walk_expr(node.b);
                                                                                            -> this.walk_expr(node.c);
                                                                                        }
                                                                                            default
                                                                                            {
                                                                                                switch (k == NodeKind.ASSIGNMENT)
                                                                                                {
                                                                                                    case (true) { -> this.handle_assign_expr(node, file, line); }
                                                                                                    default
                                                                                                    {
                                                                                                        switch (k == NodeKind.COMPOUND_ASSIGNMENT)
                                                                                                        {
                                                                                                            case (true) { this.walk_expr(node.b); }
                                                                                                            default {};
                                                                                                        };
                                                                                                        ->;
                                                                                                    };
                                                                                                };
                                                                                            };
                                                                                        };
                                                                                    };
                                                                                };
                                                                            };
                                                                        };
                                                                    };
                                                                };
                                                            };
                                                        };
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
            };
        };

        // ------------------------------------------------------------------
        // Report
        // ------------------------------------------------------------------

        def bc_str_lt(byte* a, byte* b) -> bool
        {
            int i = 0;
            while (a[i] != 0 & b[i] != 0)
            {
                if (a[i] != b[i]) { return a[i] < b[i]; };
                i++;
            };
            return a[i] < b[i];
        };

        def bc_print_violations(PtrVec* vs, bool warn) -> void
        {
            int i;
            int j;
            BVio* v;
            switch (vs.len == 0)
            {
                case (true) { ->; }
                default
                {
                    while (i < vs.len)
                    {
                        v = (BVio*)vs.items[i];
                        if (warn & !cstr_eq(v.kind, g"async_contradiction\0")) { print(g"[FBC warning] \0"); }
                        else { print(g"[FBC error] \0"); };
                        println(v.kind);
                        print(g"  \0");
                        print(v.file);
                        print(g":\0");
                        print(v.line);
                        print(g"  \0");
                        println(v.msg);
                        j = 0;
                        while (j < v.detail.len)
                        {
                            print(g"  \0");
                            println((byte*)v.detail.items[j]);
                            j++;
                        };
                        println(g"\0");
                        i++;
                    };
                    ->;
                };
            };
        };

        def bc_print_summary(PtrVec* vs, int files_checked, int funcs_checked) -> void
        {
            int i;
            int j;
            int n = vs.len;
            BVio* v;
            OMap* kinds;
            int* cnt;
            PtrVec* order;
            byte* tmp;
            if (n == 0)
            {
                print(g"[FBC] OK -- \0");
                print(files_checked);
                print(g" file(s), \0");
                print(funcs_checked);
                println(g" function(s) checked, no violations found.\0");
                return;
            };
            kinds = om_new();
            order = pv_new();
            while (i < n)
            {
                v = (BVio*)vs.items[i];
                cnt = (int*)om_get(kinds, v.kind);
                switch (cnt == (int*)0)
                {
                    case (true) {
                    om_put(kinds, v.kind, (void*)bx_new(1));
                    pv_push(order, (void*)v.kind);
                }
                    default { cnt[0] = cnt[0] + 1; };
                };
                i++;
            };
            // sorted by kind name
            i = 1;
            while (i < order.len)
            {
                j = i;
                while (j > 0)
                {
                    if (!bc_str_lt((byte*)order.items[j], (byte*)order.items[j - 1])) { break; };
                    tmp = (byte*)order.items[j];
                    order.items[j] = order.items[j - 1];
                    order.items[j - 1] = (void*)tmp;
                    j--;
                };
                i++;
            };
            print(g"[FBC] \0");
            print(n);
            print(g" violation(s) -- \0");
            print(files_checked);
            print(g" file(s), \0");
            print(funcs_checked);
            println(g" function(s) checked\0");
            print(g"  \0");
            i = 0;
            while (i < order.len)
            {
                switch (i > 0) { case (true) { print(g", \0"); } default {}; };
                print((byte*)order.items[i]);
                print(g": \0");
                cnt = (int*)om_get(kinds, (byte*)order.items[i]);
                print(cnt[0]);
                i++;
            };
            println(g"\0");
            i = 0;
            while (i < kinds.vs.len)
            {
                ffree((byte*)kinds.vs.items[i]);
                i++;
            };
            om_free(kinds);
            pv_free(order);
            return;
        };

        // Runs the checker on a parsed, DCE pruned program. Returns the violation count.
        // ------------------------------------------------------------------
        // Lifetime and ownership analysis (port of _LifetimeAnalysis in fbc.py)
        //
        // Tracks, flow-sensitively and across calls through function summaries,
        // where each pointer may point and whether each heap allocation is owned,
        // freed or maybe freed. Owns scope_escape, use_after_scope, use_after_free,
        // maybe_use_after_free, double_free, invalid_free and heap_leak.
        //
        // Regions are strings:
        //   S|<func>|<var>|<block>     stack variable, block is a number or "fn"
        //   H|<func>|<line>[|<inner>]  heap site, inner is the callee site it maps
        //   P|<func>|<index>           pointee of a pointer parameter
        //   G|<name>                   static
        //   D|<func>|<var>             dangling (stack of a returned callee frame)
        //   F|<cell>|<member>          struct field cell of another cell
        // A set of regions is a sorted PtrVec of byte*. Sets are never changed once
        // stored, only replaced.
        // ------------------------------------------------------------------

        #def LF_O 1;
        #def LF_F 2;
        #def LF_W 4;

        // ------------------------------------------------------------------
        // Async: access modes, index ranges and per-function footprints
        //
        // A footprint maps a root region to the accesses a function makes through
        // it. Parameter regions are keyed "p|<index>", statics "g|<name>". Each
        // access is a mode (read, write, free), whether it is atomic, and the
        // half open index range it covers (null range = the whole object). Range
        // ends are terms: a parameter index (or -1) plus a constant.
        // ------------------------------------------------------------------

        #def LA_R 1;
        #def LA_W 2;
        #def LA_F 4;

        // relation operators between two async functions, as bits
        #def LA_OP_INDEP 1;      // #
        #def LA_OP_AFTER 2;      // >
        #def LA_OP_COMMUTE 4;    // ~
        #def LA_OP_EXCL 8;       // !
        #def LA_OP_BEFORE 16;    // <, the reverse of >

        struct LTerm
        {
            int p;              // parameter index, or -1 for a constant
            int c;
        };

        struct LRng
        {
            LTerm* lo, hi;
        };

        struct LAcc
        {
            int bits;
            bool atomic;
            LRng* rng;          // null = whole object
        };

        // an async call that may still be running: its footprint is in caller terms
        struct LTask
        {
            byte* fn;
            OMap* fp;           // root region to PtrVec of LAcc*
            int line;
            byte* result_var, bid;
            Node* node;
        };

        // counting loop facts: name runs over [lo, hi)
        struct LPat
        {
            byte* name;
            LTerm* lo, hi;
        };

        def lf_term(int p, int c) -> LTerm*
        {
            LTerm* t = (LTerm*)fmalloc((u64)((sizeof(LTerm) + 7) / 8));
            t
            {
                .p = p;
                .c = c;
            };
            return t;
        };

        def lf_term_eq(LTerm* a, LTerm* b) -> bool
        {
            if (a == (LTerm*)0) { return b == (LTerm*)0; };
            if (b == (LTerm*)0) { return false; };
            return a.p == b.p & a.c == b.c;
        };

        def lf_rng(LTerm* lo, LTerm* hi) -> LRng*
        {
            LRng* r = (LRng*)fmalloc((u64)((sizeof(LRng) + 7) / 8));
            r
            {
                .lo = lo;
                .hi = hi;
            };
            return r;
        };

        def lf_rng_eq(LRng* a, LRng* b) -> bool
        {
            if (a == (LRng*)0) { return b == (LRng*)0; };
            if (b == (LRng*)0) { return false; };
            return lf_term_eq(a.lo, b.lo) & lf_term_eq(a.hi, b.hi);
        };

        def lf_acc(int bits, bool atomic, LRng* rng) -> LAcc*
        {
            LAcc* a = (LAcc*)fmalloc((u64)((sizeof(LAcc) + 7) / 8));
            a
            {
                .bits = bits;
                .atomic = atomic;
                .rng = rng;
            };
            return a;
        };

        def lf_acc_eq(LAcc* a, LAcc* b) -> bool
        {
            return a.bits == b.bits & a.atomic == b.atomic & lf_rng_eq(a.rng, b.rng);
        };

        // two accesses to the same object conflict unless both only read, or both are atomic
        def lf_modes_conflict(LAcc* a, LAcc* b) -> bool
        {
            int bits = a.bits `| b.bits;
            if ((bits `& LA_F) != 0) { return true; };
            if ((bits `& LA_W) != 0) { return !(a.atomic & b.atomic); };
            return false;
        };

        // a <= b provably
        def lf_term_le(LTerm* a, LTerm* b) -> bool
        {
            if (a.p == b.p) { return a.c <= b.c; };
            return false;
        };

        // half open index ranges; a null range is the whole object
        def lf_ranges_overlap(LRng* r1, LRng* r2) -> bool
        {
            if (r1 == (LRng*)0 | r2 == (LRng*)0) { return true; };
            if (lf_term_le(r1.hi, r1.lo) | lf_term_le(r2.hi, r2.lo)) { return false; };
            if (lf_term_le(r1.hi, r2.lo) | lf_term_le(r2.hi, r1.lo)) { return false; };
            return true;
        };

        def lf_mode_name(LAcc* m) -> byte*
        {
            if ((m.bits `& LA_F) != 0) { return g"free\0"; };
            if ((m.bits `& LA_W) != 0)
            {
                if (m.atomic) { return g"atomic write\0"; };
                return g"write\0";
            };
            if (m.atomic) { return g"atomic read\0"; };
            return g"read\0";
        };

        // bit of a relation operator written as text
        def lf_op_bit(byte* op) -> int
        {
            if (op[0] == '#') { return LA_OP_INDEP; };
            if (op[0] == '>') { return LA_OP_AFTER; };
            if (op[0] == '~') { return LA_OP_COMMUTE; };
            if (op[0] == '!') { return LA_OP_EXCL; };
            return LA_OP_BEFORE;
        };

        // key of the ordered pair (a, b) in a relation map
        def lf_pair_key(byte* a, byte* b) -> byte*
        {
            return join3(a, g"\x1f\0", b);
        };

        // accesses recorded for key in a footprint, created on first use
        def lf_fp_list(OMap* d, byte* key) -> PtrVec*
        {
            PtrVec* lst = (PtrVec*)om_get(d, key);
            if (lst == (PtrVec*)0)
            {
                lst = pv_new();
                om_put(d, key, (void*)lst);
            };
            return lst;
        };

        // records an access, collapsing to one whole-object entry past 8 distinct ones
        def lf_merge_fp(OMap* d, byte* key, int bits, bool atomic, LRng* rng) -> void
        {
            PtrVec* lst = lf_fp_list(d, key);
            LAcc* t = lf_acc(bits, atomic, rng);
            int i, b;
            bool at;
            PtrVec* one;
            while (i < lst.len)
            {
                if (lf_acc_eq((LAcc*)lst.items[i], t)) { return; };
                i++;
            };
            pv_push(lst, (void*)t);
            if (lst.len > 8)
            {
                b = 0;
                at = true;
                i = 0;
                while (i < lst.len)
                {
                    b = b `| ((LAcc*)lst.items[i]).bits;
                    at = at & ((LAcc*)lst.items[i]).atomic;
                    i++;
                };
                one = pv_new();
                pv_push(one, (void*)lf_acc(b, at, (LRng*)0));
                om_put(d, key, (void*)one);
            };
            return;
        };

        struct LocInfo
        {
            int kind;           // 0 value, 1 array
            byte* reg;
        };

        struct LState
        {
            OMap* env;          // var to set
            OMap* held;         // cell to set
            OMap* status;       // region to int* flags (LF_O, LF_F)
            OMap* esc;          // region to 1
            OMap* free_at;      // region to int* line
            PtrVec* active;     // byte* block ids
            bool dead;
            OMap* tasks;        // node key to LTask* live at this point
            OMap* terms;        // integer var to LTerm*: parameter + constant
        };

        struct LHeld
        {
            int idx;
            PtrVec* path;       // byte* members, outermost first
            PtrVec* regs;
        };

        struct LPos
        {
            int seq;
            PtrVec* path;       // byte* "<node>:<branch>"
            PtrVec* loops;      // byte* loop node keys
        };

        // facts for the readers/writer rule, per function
        struct LAl
        {
            OMap* ix;           // identifier node key to LPos*
            OMap* uses;         // name to PtrVec* of LPos*
            OMap* defs;         // name to PtrVec* of LPos*
            OMap* first;        // name to int* declaration sequence
            OMap* writers;
            OMap* loop_start;   // loop key to int*
            OMap* loop_end, ptr_vars;
            OMap* deriv;        // name to OMap* of names
            OMap* wr_params;    // index text
            int seq;
        };

        struct LSumm
        {
            OMap* wr;           // index text of parameters written through
            PtrVec* ret;
            int nparams;
            OMap* param_status; // index text to int* flags
            PtrVec* param_held; // LHeld*
            OMap* heap_status;  // heap region to int* flags
            OMap* esc, free_at;
            OMap* fp;           // footprint: region key to PtrVec* of LAcc*
        };

        struct LRet
        {
            LState* st;
            PtrVec* regs;
        };

        struct LLoop
        {
            PtrVec* breaks, conts;
        };

        // ----- region sets -----

        def lf_rs_new() -> PtrVec* -> pv_new();

        def lf_rs_has(PtrVec* s, byte* r) -> bool
        {
            int i;
            while (i < s.len)
            {
                if (cstr_eq((byte*)s.items[i], r)) { return true; };
                i++;
            };
            return false;
        };

        // insert into a set this caller still owns
        def lf_rs_add(PtrVec* s, byte* r) -> void
        {
            int i, at;
            if (lf_rs_has(s, r)) { return; };
            at = s.len;
            while (i < s.len)
            {
                if (bc_str_lt(r, (byte*)s.items[i]))
                {
                    at = i;
                    break;
                };
                i++;
            };
            pv_push(s, (void*)r);
            i = s.len - 1;
            while (i > at)
            {
                s.items[i] = s.items[i - 1];
                i--;
            };
            s.items[at] = (void*)r;
            return;
        };

        def lf_rs_one(byte* r) -> PtrVec*
        {
            PtrVec* s = pv_new();
            pv_push(s, (void*)r);
            return s;
        };

        def lf_rs_union(PtrVec* a, PtrVec* b) -> PtrVec*
        {
            int i;
            PtrVec* r;
            if (a.len == 0) { return b; };
            if (b.len == 0) { return a; };
            r = pv_new();
            while (i < a.len) { lf_rs_add(r, (byte*)a.items[i]); i++; };
            i = 0;
            while (i < b.len) { lf_rs_add(r, (byte*)b.items[i]); i++; };
            return r;
        };

        def lf_rs_eq(PtrVec* a, PtrVec* b) -> bool
        {
            int i;
            if (a.len != b.len) { return false; };
            while (i < a.len)
            {
                if (!cstr_eq((byte*)a.items[i], (byte*)b.items[i])) { return false; };
                i++;
            };
            return true;
        };

        // ----- region keys -----

        def lf_key(byte* tag, byte* a, byte* b, byte* c) -> byte*
        {
            Buf k;
            byte* out;
            k.__init();
            k.put_str(tag);
            if (a != (byte*)0) { k.put_str(g"|\0"); k.put_str(a); };
            if (b != (byte*)0) { k.put_str(g"|\0"); k.put_str(b); };
            if (c != (byte*)0) { k.put_str(g"|\0"); k.put_str(c); };
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        def lf_itoa(int n) -> byte*
        {
            Buf k;
            byte* out;
            k.__init();
            k.put_int(n);
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        def lf_atoi(byte* s) -> int
        {
            int v, i;
            while (s[i] >= '0' & s[i] <= '9')
            {
                v = v * 10 + ((int)s[i] - 48);
                i++;
            };
            return v;
        };

        // n-th (0 based) '|' separated segment, ended by the next '|' or the end
        def lf_seg(byte* r, int n) -> byte*
        {
            int i, seg, start, j;
            Buf k;
            byte* out;
            while (r[i] != 0 & seg < n)
            {
                if (r[i] == '|') { seg++; start = i + 1; };
                i++;
            };
            j = start;
            k.__init();
            while (r[j] != 0 & r[j] != '|')
            {
                k.put((int)r[j]);
                j++;
            };
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        // text after the n-th '|' (n counted from 1), or null
        def lf_after(byte* r, int n) -> byte*
        {
            int i, seen;
            while (r[i] != 0)
            {
                if (r[i] == '|')
                {
                    seen++;
                    if (seen == n) { return r + i + 1; };
                };
                i++;
            };
            return (byte*)0;
        };

        def lf_stack(byte* func, byte* name, byte* bid) -> byte*
        {
            Buf k;
            byte* out;
            k.__init();
            k.put_str(f"S|{func}|{name}|{bid}\0");
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        def lf_param(byte* func, int idx) -> byte*
        {
            byte* t = lf_itoa(idx);
            return lf_key(g"P\0", func, t, (byte*)0);
        };

        def lf_static(byte* name) -> byte* -> lf_key(g"G\0", name, (byte*)0, (byte*)0);

        def lf_dangling(byte* func, byte* name) -> byte* -> lf_key(g"D\0", func, name, (byte*)0);

        def lf_heap(byte* func, int line, byte* inner) -> byte*
        {
            Buf k;
            byte* out;
            k.__init();
            k.put_str(f"H|{func}|{line}\0");
            if (inner != (byte*)0)
            {
                k.put_str(f"|{inner}\0");
            };
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        // mapped call site: the call column keeps two calls on one line apart
        def lf_heap_c(byte* func, int line, int col, byte* inner) -> byte*
        {
            Buf k;
            byte* out;
            k.__init();
            k.put_str(f"H|{func}|{line}@{col}|{inner}\0");
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        def lf_fld(byte* cell, byte* member) -> byte*
        {
            Buf k;
            byte* out;
            k.__init();
            k.put_str(f"F|{cell}|{member}\0");
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        // cell part and member part of an F key
        def lf_fld_cell(byte* c) -> byte*
        {
            int n = bc_len(c);
            int last, i;
            Buf k;
            byte* out;
            while (i < n)
            {
                if (c[i] == '|') { last = i; };
                i++;
            };
            k.__init();
            i = 2;
            while (i < last)
            {
                k.put((int)c[i]);
                i++;
            };
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        def lf_fld_member(byte* c) -> byte*
        {
            int n = bc_len(c);
            int last, i;
            while (i < n)
            {
                if (c[i] == '|') { last = i; };
                i++;
            };
            return ts_dup(c + last + 1);
        };

        def lf_root(byte* c) -> byte*
        {
            byte* r = c;
            while (r[0] == 'F')
            {
                r = lf_fld_cell(r);
            };
            return r;
        };

        // innermost heap site of a mapped one
        def lf_origin(byte* r) -> byte*
        {
            byte* cur = r;
            byte* inner;
            while (cur[0] == 'H')
            {
                inner = lf_after(cur, 3);
                if (inner == (byte*)0) { break; };
                cur = inner;
            };
            return cur;
        };

        // ----- states -----

        def lf_state_new() -> LState*
        {
            LState* s = (LState*)fmalloc((u64)((sizeof(LState) + 7) / 8));
            s
            {
                .env = om_new();
                .held = om_new();
                .status = om_new();
                .esc = om_new();
                .free_at = om_new();
                .active = pv_new();
                .dead = false;
                .tasks = om_new();
                .terms = om_new();
            };
            return s;
        };

        def lf_state_copy(LState* a) -> LState*
        {
            LState* s = (LState*)fmalloc((u64)((sizeof(LState) + 7) / 8));
            int i;
            s
            {
                .env = om_copy(a.env);
                .held = om_copy(a.held);
                .status = om_copy(a.status);
                .esc = om_copy(a.esc);
                .free_at = om_copy(a.free_at);
                .active = pv_new();
            };
            while (i < a.active.len) { pv_push(s.active, a.active.items[i]); i++; };
            s
            {
                .dead = a.dead;
                .tasks = om_copy(a.tasks);
                .terms = om_copy(a.terms);
            };
            return s;
        };

        def lf_state_set(LState* dst, LState* src) -> void
        {
            dst
            {
                .env = src.env;
                .held = src.held;
                .status = src.status;
                .esc = src.esc;
                .free_at = src.free_at;
                .active = src.active;
                .dead = src.dead;
                .tasks = src.tasks;
                .terms = src.terms;
            };
            return;
        };

        // union of two maps of sets
        def lf_join_sets(OMap* a, OMap* b) -> OMap*
        {
            OMap* out = om_copy(a);
            int i;
            byte* k;
            while (i < b.ks.len)
            {
                k = (byte*)b.ks.items[i];
                if (om_has(out, k))
                {
                    om_put(out, k, (void*)lf_rs_union((PtrVec*)om_get(out, k), (PtrVec*)b.vs.items[i]));
                }
                else
                {
                    om_put(out, k, b.vs.items[i]);
                };
                i++;
            };
            return out;
        };

        def lf_join_flags(OMap* a, OMap* b) -> OMap*
        {
            OMap* out = om_copy(a);
            int i;
            byte* k;
            int* x, y;
            while (i < b.ks.len)
            {
                k = (byte*)b.ks.items[i];
                if (om_has(out, k))
                {
                    x = (int*)om_get(out, k);
                    y = (int*)b.vs.items[i];
                    om_put(out, k, (void*)bx_new(x[0] `| y[0]));
                }
                else
                {
                    om_put(out, k, b.vs.items[i]);
                };
                i++;
            };
            return out;
        };

        def lf_join(LState* a, LState* b) -> LState*
        {
            LState* s;
            int i;
            if (a == (LState*)0) { return b; };
            if (b == (LState*)0) { return a; };
            if (a.dead) { return lf_state_copy(b); };
            if (b.dead) { return lf_state_copy(a); };
            s = (LState*)fmalloc((u64)((sizeof(LState) + 7) / 8));
            s
            {
                .env = lf_join_sets(a.env, b.env);
                .held = lf_join_sets(a.held, b.held);
                .status = lf_join_flags(a.status, b.status);
                .esc = om_copy(a.esc);
            };
            i = 0;
            while (i < b.esc.ks.len)
            {
                om_put(s.esc, (byte*)b.esc.ks.items[i], b.esc.vs.items[i]);
                i++;
            };
            s.free_at = om_copy(a.free_at);
            i = 0;
            while (i < b.free_at.ks.len)
            {
                om_put(s.free_at, (byte*)b.free_at.ks.items[i], b.free_at.vs.items[i]);
                i++;
            };
            s.dead = false;
            if (a.active.len <= b.active.len) { s.active = a.active; } else { s.active = b.active; };
            s.tasks = om_copy(a.tasks);
            i = 0;
            while (i < b.tasks.ks.len)
            {
                om_put(s.tasks, (byte*)b.tasks.ks.items[i], b.tasks.vs.items[i]);
                i++;
            };
            s.terms = om_new();
            i = 0;
            while (i < a.terms.ks.len)
            {
                if (om_has(b.terms, (byte*)a.terms.ks.items[i]))
                {
                    if (lf_term_eq((LTerm*)a.terms.vs.items[i], (LTerm*)om_get(b.terms, (byte*)a.terms.ks.items[i])))
                    {
                        om_put(s.terms, (byte*)a.terms.ks.items[i], a.terms.vs.items[i]);
                    };
                };
                i++;
            };
            return s;
        };

        def lf_eq_sets(OMap* a, OMap* b) -> bool
        {
            int i;
            if (a.ks.len != b.ks.len) { return false; };
            while (i < a.ks.len)
            {
                if (!om_has(b, (byte*)a.ks.items[i])) { return false; };
                if (!lf_rs_eq((PtrVec*)a.vs.items[i], (PtrVec*)om_get(b, (byte*)a.ks.items[i]))) { return false; };
                i++;
            };
            return true;
        };

        def lf_eq_flags(OMap* a, OMap* b) -> bool
        {
            int i;
            int* x, y;
            if (a.ks.len != b.ks.len) { return false; };
            while (i < a.ks.len)
            {
                if (!om_has(b, (byte*)a.ks.items[i])) { return false; };
                x = (int*)a.vs.items[i];
                y = (int*)om_get(b, (byte*)a.ks.items[i]);
                if (x[0] != y[0]) { return false; };
                i++;
            };
            return true;
        };

        def lf_eq_keys(OMap* a, OMap* b) -> bool
        {
            int i;
            if (a.ks.len != b.ks.len) { return false; };
            while (i < a.ks.len)
            {
                if (!om_has(b, (byte*)a.ks.items[i])) { return false; };
                i++;
            };
            return true;
        };

        def lf_eq_terms(OMap* a, OMap* b) -> bool
        {
            int i;
            if (a.ks.len != b.ks.len) { return false; };
            while (i < a.ks.len)
            {
                if (!om_has(b, (byte*)a.ks.items[i])) { return false; };
                if (!lf_term_eq((LTerm*)a.vs.items[i], (LTerm*)om_get(b, (byte*)a.ks.items[i]))) { return false; };
                i++;
            };
            return true;
        };

        def lf_state_eq(LState* a, LState* b) -> bool
        {
            if (a.dead != b.dead) { return false; };
            if (!lf_eq_sets(a.env, b.env)) { return false; };
            if (!lf_eq_sets(a.held, b.held)) { return false; };
            if (!lf_eq_flags(a.status, b.status)) { return false; };
            if (!lf_eq_keys(a.esc, b.esc)) { return false; };
            if (!lf_eq_keys(a.tasks, b.tasks)) { return false; };
            if (!lf_eq_terms(a.terms, b.terms)) { return false; };
            return true;
        };

        def lf_active_has(PtrVec* act, byte* bid) -> bool
        {
            int i;
            while (i < act.len)
            {
                if (cstr_eq((byte*)act.items[i], bid)) { return true; };
                i++;
            };
            return false;
        };

        def lf_flags(OMap* m, byte* k) -> int
        {
            int* p;
            if (!om_has(m, k)) { return 0; };
            p = (int*)om_get(m, k);
            return p[0];
        };

        def lf_is_stmt_kind(int k) -> bool
        {
            return k == NodeKind.EXPRESSION_STATEMENT | k == NodeKind.ASSIGNMENT
                | k == NodeKind.COMPOUND_ASSIGNMENT | k == NodeKind.RANGE_ASSIGNMENT
                | k == NodeKind.TERNARY_ASSIGN | k == NodeKind.BLOCK
                | k == NodeKind.IF_STATEMENT | k == NodeKind.WHILE_LOOP
                | k == NodeKind.DO_LOOP | k == NodeKind.DO_WHILE_LOOP
                | k == NodeKind.FOR_LOOP | k == NodeKind.FOR_IN_LOOP
                | k == NodeKind.RETURN_STATEMENT | k == NodeKind.ERROR_RETURN_STATEMENT
                | k == NodeKind.BREAK_STATEMENT | k == NodeKind.BREAK_SWITCH_STATEMENT
                | k == NodeKind.CONTINUE_STATEMENT | k == NodeKind.DEFER_STATEMENT
                | k == NodeKind.NORETURN_STATEMENT | k == NodeKind.ESCAPE_STATEMENT
                | k == NodeKind.LABEL_STATEMENT | k == NodeKind.GOTO_STATEMENT
                | k == NodeKind.JUMP_STATEMENT | k == NodeKind.SWITCH_STATEMENT
                | k == NodeKind.TRY_BLOCK | k == NodeKind.THROW_STATEMENT
                | k == NodeKind.ASSERT_STATEMENT;
        };

        def lf_al_new() -> LAl*
        {
            LAl* a = (LAl*)fmalloc((u64)((sizeof(LAl) + 7) / 8));
            a
            {
                .ix = om_new();
                .uses = om_new();
                .defs = om_new();
                .first = om_new();
                .writers = om_new();
                .loop_start = om_new();
                .loop_end = om_new();
                .ptr_vars = om_new();
                .deriv = om_new();
                .wr_params = om_new();
                .seq = 0;
            };
            return a;
        };

        def lf_addr_key(void* p) -> byte*
        {
            u64 a = (u64)p;
            Buf k;
            byte* out;
            k.__init();
            k.put_int((int)(a >> 32));
            k.put_str(g"_\0");
            k.put_int((int)(a `& 4294967295));
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        def lf_pos_new(int seq, PtrVec* path, PtrVec* loops) -> LPos*
        {
            LPos* p = (LPos*)fmalloc((u64)((sizeof(LPos) + 7) / 8));
            p
            {
                .seq = seq;
                .path = path;
                .loops = loops;
            };
            return p;
        };

        def lf_pv_add(PtrVec* v, byte* e) -> PtrVec*
        {
            PtrVec* r = pv_new();
            int i;
            while (i < v.len) { pv_push(r, v.items[i]); i++; };
            pv_push(r, (void*)e);
            return r;
        };

        def lf_pv_has(PtrVec* v, byte* e) -> bool
        {
            int i;
            while (i < v.len)
            {
                if (cstr_eq((byte*)v.items[i], e)) { return true; };
                i++;
            };
            return false;
        };

        // path entry "<node>:<branch>"
        def lf_pe(byte* node_key, int branch) -> byte*
        {
            Buf k;
            byte* out;
            k.__init();
            k.put_str(f"{node_key}:{branch}\0");
            out = ts_dup(k.mem);
            k.__exit();
            return out;
        };

        def lf_pe_split(byte* e) -> int
        {
            int i;
            while (e[i] != 0)
            {
                if (e[i] == ':') { return i; };
                i++;
            };
            return i;
        };

        def lf_exclusive(PtrVec* a, PtrVec* b) -> bool
        {
            int i, j, ca, cb;
            byte* x, y;
            int q;
            bool same;
            while (i < a.len)
            {
                x = (byte*)a.items[i];
                ca = lf_pe_split(x);
                j = 0;
                while (j < b.len)
                {
                    y = (byte*)b.items[j];
                    cb = lf_pe_split(y);
                    if (ca == cb)
                    {
                        // same node when the text before ':' matches
                        q = 0;
                        same = true;
                        while (q < ca)
                        {
                            if (x[q] != y[q]) { same = false; };
                            q++;
                        };
                        if (same)
                        {
                            if (!cstr_eq(x + ca, y + cb)) { return true; };
                        };
                    };
                    j++;
                };
                i++;
            };
            return false;
        };

        def lf_prefix(PtrVec* p, PtrVec* q) -> bool
        {
            int i;
            if (p.len > q.len) { return false; };
            while (i < p.len)
            {
                if (!cstr_eq((byte*)p.items[i], (byte*)q.items[i])) { return false; };
                i++;
            };
            return true;
        };

        def lf_int_get(OMap* m, byte* k, int dflt) -> int
        {
            int* p;
            if (!om_has(m, k)) { return dflt; };
            p = (int*)om_get(m, k);
            return p[0];
        };

        def lf_rs_inter(PtrVec* a, PtrVec* b) -> PtrVec*
        {
            PtrVec* r = pv_new();
            int i;
            while (i < a.len)
            {
                if (lf_rs_has(b, (byte*)a.items[i])) { lf_rs_add(r, (byte*)a.items[i]); };
                i++;
            };
            return r;
        };

        def lf_loc_put(OMap* m, byte* name, int kind, byte* reg) -> void
        {
            LocInfo* li = (LocInfo*)fmalloc((u64)((sizeof(LocInfo) + 7) / 8));
            li
            {
                .kind = kind;
                .reg = reg;
            };
            om_put(m, name, (void*)li);
            return;
        };

        def lf_loc_get(OMap* m, byte* name) -> LocInfo*
        {
            return (LocInfo*)om_get(m, name);
        };

        def lf_env_get(OMap* env, byte* name) -> PtrVec*
        {
            PtrVec* v = (PtrVec*)om_get(env, name);
            if (v == (PtrVec*)0) { return lf_rs_new(); };
            return v;
        };

        object LifeChecker
        {
            CallGraph* cg;
            byte* entry;
            Preprocessor* pp;
            PtrVec* violations;     // BVio*
            NameMap* seen;
            NameMap* summaries;     // function name to LSumm*
            NameMap* active_summ;
            OMap* multi;            // regions stored through a non constant index
            int funcs_checked;
            byte* fn;
            OMap* locals;           // var name to LocInfo*
            OMap* heapvars;         // names of heap T x locals
            PtrVec* loops;          // LLoop*
            PtrVec* defers;         // PtrVec* of DEFER nodes
            PtrVec* returns;        // LRet*
            PtrVec* blks;           // Node* seen as block ids
            int cur_line;
            int call_col;
            LAl* al;
            bool warn_mode;
            OMap* fp;               // footprint of the function being walked
            Node* async_node;       // call expression that would be a launch
            LTask* last_task;
            OMap* ivars;            // counting loop variable to LRng*
            bool no_access;
            OMap* rel;              // pair key to relation bits
            OMap* async_launched;   // node key to 1
            OMap* async_seq;        // node key to 1
            OMap* async_waits;      // node key to PtrVec* of node keys
            OMap* async_target;     // node key to resolved callee name
            LAcc* hit_a, hit_b;
            Buf xb, mb;
            PtrVec* cells_r;        // results of cells_of
            PtrVec* deref_r;
            Buf sb, tb;

            __init(CallGraph* g, byte* entry_name, Preprocessor* p, bool warn) -> this
            {
                this.cg = g;
                this.entry = entry_name;
                this.pp = p;
                this.warn_mode = warn;
                this.fp = om_new();
                this.async_node = (Node*)0;
                this.last_task = (LTask*)0;
                this.ivars = om_new();
                this.no_access = false;
                this.rel = om_new();
                this.async_launched = om_new();
                this.async_seq = om_new();
                this.async_waits = om_new();
                this.async_target = om_new();
                this.xb.__init();
                this.mb.__init();
                this.violations = pv_new();
                this.seen = nm_new();
                this.summaries = nm_new();
                this.active_summ = nm_new();
                this.multi = om_new();
                this.funcs_checked = 0;
                this.fn = (byte*)0;
                this.locals = om_new();
                this.heapvars = om_new();
                this.loops = pv_new();
                this.defers = pv_new();
                this.returns = pv_new();
                this.blks = pv_new();
                this.cur_line = 0;
                this.al = lf_al_new();
                this.cells_r = pv_new();
                this.deref_r = pv_new();
                this.sb.__init();
                this.tb.__init();
                -> this;
            };

            __expr() -> LifeChecker* -> this;

            __exit() -> void
            {
                nm_free(this.seen);
                nm_free(this.summaries);
                nm_free(this.active_summ);
                -> this.sb.__exit();
            };

            // ----- reporting -----

            remap_file(int merged) -> byte*
            {
                int idx = merged - 1;
                if (this.pp != (Preprocessor*)0)
                {
                    if (idx >= 0 & idx < this.pp.map_line.len)
                    {
                        -> this.pp.map_path(idx);
                    };
                };
                -> bc_unk();
            };

            remap_line(int merged) -> int
            {
                int idx = merged - 1;
                if (this.pp != (Preprocessor*)0)
                {
                    if (idx >= 0 & idx < this.pp.map_line.len)
                    {
                        -> this.pp.map_lineno(idx);
                    };
                };
                -> merged;
            };

            take() -> byte* -> ts_dup(this.sb.mem);

            where(int line) -> byte*
            {
                this.tb.clear();
                this.tb.put_str(f"{this.remap_file(line)}:{this.remap_line(line)}\0");
                -> ts_dup(this.tb.mem);
            };

            report(byte* kind, byte* msg, int line, PtrVec* detail) -> void
            {
                byte* file = this.remap_file(line);
                int l = this.remap_line(line);
                byte* key;
                BVio* v;
                this.sb.clear();
                this.sb.put_str(f"{kind}\x1f{file}\x1f{l}\x1f{msg}\0");
                key = this.take();
                if (nm_has(this.seen, key)) { ->; };
                nm_put(this.seen, key, (void*)1);
                v = (BVio*)fmalloc((u64)((sizeof(BVio) + 7) / 8));
                v
                {
                    .kind = kind;
                    .msg = msg;
                    .file = file;
                    .line = l;
                    .detail = detail;
                    .func = this.fn;
                };
                if (detail == (PtrVec*)0) { v.detail = pv_new(); };
                -> pv_push(this.violations, (void*)v);
            };

            det1(byte* a, byte* loc) -> PtrVec*
            {
                PtrVec* d = pv_new();
                this.sb.clear();
                this.sb.put_str(f"{a}{loc}\0");
                pv_push(d, (void*)this.take());
                -> d;
            };

            // description of a region used in messages
            rdesc(byte* r) -> byte*
            {
                byte* o, f, n, t;
                this.tb.clear();
                if (r[0] == 'H')
                {
                    o = lf_origin(r);
                    f = lf_seg(o, 1);
                    t = lf_seg(o, 2);
                    this.tb.put_str(f"heap:{f}:\0");
                    this.tb.put_int(this.remap_line(lf_atoi(t)));
                    -> ts_dup(this.tb.mem);
                };
                if (r[0] == 'S' | r[0] == 'D')
                {
                    f = lf_seg(r, 1);
                    n = lf_seg(r, 2);
                    this.tb.put_str(f"stack:{f}:{n}\0");
                    -> ts_dup(this.tb.mem);
                };
                if (r[0] == 'P')
                {
                    f = lf_seg(r, 1);
                    n = lf_seg(r, 2);
                    this.tb.put_str(f"param:{f}:{n}\0");
                    -> ts_dup(this.tb.mem);
                };
                -> lf_seg(r, 1);
            };

            // ------------------------------------------------------------------
            // async: footprints, relations and the task solver
            // ------------------------------------------------------------------

            is_async(byte* fname) -> bool
            {
                Node* fd;
                if (nm_has(this.cg.async_names, fname)) { -> true; };
                fd = (Node*)nm_get(this.cg.funcs, fname);
                if (fd != (Node*)0)
                {
                    if ((fd.flags `& NF_ASYNC) != 0) { -> true; };
                };
                -> false;
            };

            // a call's region roots, as a set
            roots_of(PtrVec* cells) -> PtrVec*
            {
                PtrVec* out = lf_rs_new();
                int i;
                while (i < cells.len)
                {
                    lf_rs_add(out, lf_root((byte*)cells.items[i]));
                    i++;
                };
                -> out;
            };

            // footprint key of a root region: "p|<index>" or "g|<name>", null for anything else
            fp_key(byte* r0) -> byte*
            {
                byte* r = lf_root(r0);
                if (r[0] == 'P')
                {
                    if (cstr_eq(lf_seg(r, 1), this.fn)) { -> join3(g"p|\0", lf_seg(r, 2), g"\0"); };
                    -> (byte*)0;
                };
                if (r[0] == 'G') { -> join3(g"g|\0", lf_seg(r, 1), g"\0"); };
                -> (byte*)0;
            };

            // folds a task footprint (caller regions) into this function's own footprint
            merge_fp_roots(OMap* tfp) -> void
            {
                int i, j;
                byte* key;
                PtrVec* lst;
                LAcc* a;
                while (i < tfp.ks.len)
                {
                    key = this.fp_key((byte*)tfp.ks.items[i]);
                    if (key != (byte*)0)
                    {
                        lst = (PtrVec*)tfp.vs.items[i];
                        j = 0;
                        while (j < lst.len)
                        {
                            a = (LAcc*)lst.items[j];
                            lf_merge_fp(this.fp, key, a.bits, a.atomic, a.rng);
                            j++;
                        };
                    };
                    i++;
                };
                ->;
            };

            // first conflicting pair of accesses between two lists, left in hit_a and hit_b
            fp_conflict(PtrVec* la, PtrVec* lb) -> bool
            {
                int i, j;
                LAcc* a, b;
                while (i < la.len)
                {
                    a = (LAcc*)la.items[i];
                    j = 0;
                    while (j < lb.len)
                    {
                        b = (LAcc*)lb.items[j];
                        if (lf_modes_conflict(a, b) & lf_ranges_overlap(a.rng, b.rng))
                        {
                            this.hit_a = a;
                            this.hit_b = b;
                            -> true;
                        };
                        j++;
                    };
                    i++;
                };
                -> false;
            };

            // ----- index terms and ranges -----

            // e as parameter + constant, or null
            term_of(Node* e, LState* st) -> LTerm*
            {
                LTerm* l, r;
                if (e == (Node*)0) { -> (LTerm*)0; };
                if (e.kind == NodeKind.LITERAL)
                {
                    if (e.op == DataType.SINT | e.op == DataType.UINT | e.op == DataType.SLONG | e.op == DataType.ULONG)
                    {
                        -> lf_term(-1, (int)e.ival);
                    };
                    -> (LTerm*)0;
                };
                if (e.kind == NodeKind.IDENTIFIER) { -> (LTerm*)om_get(st.terms, e.text); };
                if (bc_is_cast(e)) { -> this.term_of(e.a, st); };
                if (e.kind == NodeKind.BINARY_OP)
                {
                    if (e.op == Operator.ADD | e.op == Operator.SUB)
                    {
                        l = this.term_of(e.a, st);
                        r = this.term_of(e.b, st);
                        if (l == (LTerm*)0 | r == (LTerm*)0) { -> (LTerm*)0; };
                        if (r.p == -1)
                        {
                            if (e.op == Operator.ADD) { -> lf_term(l.p, l.c + r.c); };
                            -> lf_term(l.p, l.c - r.c);
                        };
                        if (e.op == Operator.ADD & l.p == -1) { -> lf_term(r.p, r.c + l.c); };
                    };
                };
                -> (LTerm*)0;
            };

            idents_in(Node* e, OMap* out) -> void
            {
                int s, c, i;
                if (e == (Node*)0) { ->; };
                if (e.kind == NodeKind.IDENTIFIER)
                {
                    if (e.text != (byte*)0) { om_put(out, e.text, (void*)1); };
                    ->;
                };
                this.idents_in(e.a, out);
                this.idents_in(e.b, out);
                this.idents_in(e.c, out);
                this.idents_in(e.d, out);
                this.idents_in(e.e, out);
                while (s < 6)
                {
                    c = bc_count(e, s);
                    i = 0;
                    while (i < c)
                    {
                        this.idents_in(node_child(e, s, i), out);
                        i++;
                    };
                    s++;
                };
                ->;
            };

            mentions_ivar(Node* e) -> bool
            {
                OMap* names = om_new();
                int i;
                this.idents_in(e, names);
                while (i < names.ks.len)
                {
                    if (om_has(this.ivars, (byte*)names.ks.items[i])) { -> true; };
                    i++;
                };
                -> false;
            };

            index_range(Node* idx, LState* st) -> LRng*
            {
                LRng* r;
                LTerm* c, t;
                Node* var_side, const_side;
                bool ok;
                int pass, d;
                if (idx.kind == NodeKind.IDENTIFIER)
                {
                    if (om_has(this.ivars, idx.text)) { -> (LRng*)om_get(this.ivars, idx.text); };
                };
                if (bc_is_cast(idx)) { -> this.index_range(idx.a, st); };
                if (idx.kind == NodeKind.BINARY_OP)
                {
                    if (idx.op == Operator.ADD | idx.op == Operator.SUB)
                    {
                        while (pass < 2)
                        {
                            if (pass == 0) { var_side = idx.a; const_side = idx.b; ok = true; }
                            else { var_side = idx.b; const_side = idx.a; ok = idx.op == Operator.ADD; };
                            pass++;
                            if (!ok) { continue; };
                            r = (LRng*)0;
                            if (this.mentions_ivar(var_side)) { r = this.index_range(var_side, st); };
                            if (r == (LRng*)0) { continue; };
                            if (this.mentions_ivar(const_side)) { continue; };
                            c = this.term_of(const_side, st);
                            if (c != (LTerm*)0)
                            {
                                if (c.p == -1)
                                {
                                    d = c.c;
                                    if (idx.op == Operator.SUB) { d = 0 - c.c; };
                                    -> lf_rng(lf_term(r.lo.p, r.lo.c + d), lf_term(r.hi.p, r.hi.c + d));
                                };
                            };
                        };
                    };
                };
                // Any other use of a loop variable has no tracked range; the value it
                // held on entry to the loop is not its value in the body.
                if (this.mentions_ivar(idx)) { -> (LRng*)0; };
                t = this.term_of(idx, st);
                if (t != (LTerm*)0) { -> lf_rng(t, lf_term(t.p, t.c + 1)); };
                -> (LRng*)0;
            };

            // element range of an lvalue expression, in the pointee's element units
            acc_range(Node* e0, LState* st) -> LRng*
            {
                Node* e = e0;
                bool via_member;
                while (e.kind == NodeKind.MEMBER_ACCESS)
                {
                    e = e.a;
                    via_member = true;
                };
                if (e.kind == NodeKind.ARRAY_ACCESS)
                {
                    if (e.a.kind == NodeKind.IDENTIFIER) { -> this.index_range(e.b, st); };
                    -> (LRng*)0;
                };
                if (e.kind == NodeKind.POINTER_DEREF) { -> lf_rng(lf_term(-1, 0), lf_term(-1, 1)); };
                if (e.kind == NodeKind.IDENTIFIER & via_member) { -> lf_rng(lf_term(-1, 0), lf_term(-1, 1)); };
                -> (LRng*)0;
            };

            count_mods(Node* node, byte* name) -> int
            {
                int n, s, c, i;
                if (node == (Node*)0) { -> 0; };
                if (node.kind == NodeKind.ASSIGNMENT | node.kind == NodeKind.COMPOUND_ASSIGNMENT)
                {
                    if (node.a != (Node*)0)
                    {
                        if (node.a.kind == NodeKind.IDENTIFIER)
                        {
                            if (cstr_eq(node.a.text, name)) { n++; };
                        };
                    };
                }
                else
                {
                    if (node.kind == NodeKind.UNARY_OP)
                    {
                        if (node.op == Operator.INCREMENT | node.op == Operator.DECREMENT)
                        {
                            if (node.a != (Node*)0)
                            {
                                if (node.a.kind == NodeKind.IDENTIFIER)
                                {
                                    if (cstr_eq(node.a.text, name)) { n++; };
                                };
                            };
                        };
                    }
                    else
                    {
                        if (node.kind == NodeKind.VARIABLE_DECLARATION)
                        {
                            if (cstr_eq(node.text, name)) { n++; };
                        };
                    };
                };
                n = n + this.count_mods(node.a, name);
                n = n + this.count_mods(node.b, name);
                n = n + this.count_mods(node.c, name);
                n = n + this.count_mods(node.d, name);
                n = n + this.count_mods(node.e, name);
                while (s < 6)
                {
                    c = bc_count(node, s);
                    i = 0;
                    while (i < c)
                    {
                        n = n + this.count_mods(node_child(node, s, i), name);
                        i++;
                    };
                    s++;
                };
                -> n;
            };

            is_one(Node* e) -> bool
            {
                if (e == (Node*)0) { -> false; };
                if (e.kind != NodeKind.LITERAL) { -> false; };
                if (e.op == DataType.SINT | e.op == DataType.UINT | e.op == DataType.SLONG | e.op == DataType.ULONG)
                {
                    -> e.ival == (i64)1;
                };
                -> false;
            };

            is_inc(Node* stmt, byte* name) -> bool
            {
                Node* s = stmt;
                Node* v;
                if (s.kind == NodeKind.EXPRESSION_STATEMENT) { s = s.a; };
                if (s.kind == NodeKind.UNARY_OP)
                {
                    -> s.op == Operator.INCREMENT & s.a.kind == NodeKind.IDENTIFIER & cstr_eq(s.a.text, name);
                };
                if (s.kind == NodeKind.COMPOUND_ASSIGNMENT)
                {
                    -> s.a.kind == NodeKind.IDENTIFIER & cstr_eq(s.a.text, name)
                       & s.op == TokenType.PLUS_ASSIGN & this.is_one(s.b);
                };
                if (s.kind == NodeKind.ASSIGNMENT)
                {
                    v = s.b;
                    if (s.a.kind != NodeKind.IDENTIFIER) { -> false; };
                    if (!cstr_eq(s.a.text, name)) { -> false; };
                    if (v.kind != NodeKind.BINARY_OP) { -> false; };
                    if (v.op != Operator.ADD) { -> false; };
                    if (v.a.kind != NodeKind.IDENTIFIER) { -> false; };
                    if (!cstr_eq(v.a.text, name)) { -> false; };
                    -> this.is_one(v.b);
                };
                -> false;
            };

            // Counting loop: i starts at a known term, steps by one at the end of every
            // iteration, and runs while i < bound (bound unchanged by the loop).
            loop_pattern(Node* cond, Node* body, Node* update, LState* st) -> LPat*
            {
                LPat* pat;
                LTerm* lo, hi;
                OMap* names;
                byte* name;
                int mods, i, c;
                if (cond == (Node*)0) { -> (LPat*)0; };
                if (cond.kind != NodeKind.BINARY_OP) { -> (LPat*)0; };
                if (cond.op != Operator.LESS_THAN & cond.op != Operator.LESS_EQUAL) { -> (LPat*)0; };
                if (cond.a.kind != NodeKind.IDENTIFIER) { -> (LPat*)0; };
                name = cond.a.text;
                lo = (LTerm*)om_get(st.terms, name);
                hi = this.term_of(cond.b, st);
                if (lo == (LTerm*)0 | hi == (LTerm*)0) { -> (LPat*)0; };
                if (cond.op == Operator.LESS_EQUAL) { hi = lf_term(hi.p, hi.c + 1); };
                names = om_new();
                this.idents_in(cond.b, names);
                i = 0;
                while (i < names.ks.len)
                {
                    if (this.count_mods(body, (byte*)names.ks.items[i]) != 0) { -> (LPat*)0; };
                    if (update != (Node*)0)
                    {
                        if (this.count_mods(update, (byte*)names.ks.items[i]) != 0) { -> (LPat*)0; };
                    };
                    i++;
                };
                mods = this.count_mods(body, name);
                c = bc_count(body, 0);
                if (update != (Node*)0)
                {
                    if (mods != 0) { -> (LPat*)0; };
                    if (!this.is_inc(update, name)) { -> (LPat*)0; };
                }
                else
                {
                    if (mods != 1 | c == 0) { -> (LPat*)0; };
                    if (!this.is_inc(node_child(body, 0, c - 1), name)) { -> (LPat*)0; };
                };
                pat = (LPat*)fmalloc((u64)((sizeof(LPat) + 7) / 8));
                pat
                {
                    .name = name;
                    .lo = lo;
                    .hi = hi;
                };
                -> pat;
            };

            fmt_term(LTerm* t) -> void
            {
                Node* fd, pn;
                byte* nm;
                if (t.p == -1)
                {
                    -> this.xb.put_int(t.c);
                };
                fd = (Node*)nm_get(this.cg.funcs, this.fn);
                if (fd != (Node*)0)
                {
                    if (t.p < bc_count(fd, 0))
                    {
                        pn = node_child(fd, 0, t.p);
                        nm = pn.text;
                    };
                };
                if (nm != (byte*)0)
                {
                    if (nm[0] == 0) { nm = (byte*)0; };
                };
                if (nm == (byte*)0)
                {
                    this.xb.put_str(f"arg{t.p}\0");
                }
                else
                {
                    this.xb.put_str(nm);
                };
                if (t.c != 0)
                {
                    if (t.c > 0) { this.xb.put_str(g"+\0"); };
                    this.xb.put_int(t.c);
                };
                ->;
            };

            fmt_rng(LRng* rng) -> byte*
            {
                if (rng == (LRng*)0) { -> g"[whole object]\0"; };
                this.xb.clear();
                this.xb.put_str(g"[\0");
                this.fmt_term(rng.lo);
                this.xb.put_str(g", \0");
                this.fmt_term(rng.hi);
                this.xb.put_str(g")\0");
                -> ts_dup(this.xb.mem);
            };

            // the argument points at element 0 of the object it names
            offset_zero(Node* a0) -> bool
            {
                Node* a = a0;
                Node* x;
                while (bc_is_cast(a)) { a = a.a; };
                if (a.kind == NodeKind.IDENTIFIER) { -> true; };
                if (a.kind == NodeKind.ADDRESS_OF)
                {
                    x = a.a;
                    if (x.kind == NodeKind.IDENTIFIER) { -> true; };
                    if (x.kind == NodeKind.ARRAY_ACCESS)
                    {
                        if (x.b.kind == NodeKind.LITERAL)
                        {
                            if (x.b.ival == (i64)0) { -> x.a.kind == NodeKind.IDENTIFIER; };
                        };
                    };
                    -> false;
                };
                -> false;
            };

            subst_term(LTerm* t, PtrVec* aterms) -> LTerm*
            {
                LTerm* at;
                if (t.p == -1) { -> t; };
                if (t.p >= aterms.len) { -> (LTerm*)0; };
                at = (LTerm*)aterms.items[t.p];
                if (at == (LTerm*)0) { -> (LTerm*)0; };
                -> lf_term(at.p, at.c + t.c);
            };

            subst_rng(LRng* rng, PtrVec* aterms) -> LRng*
            {
                LTerm* lo, hi;
                if (rng == (LRng*)0) { -> (LRng*)0; };
                lo = this.subst_term(rng.lo, aterms);
                hi = this.subst_term(rng.hi, aterms);
                if (lo == (LTerm*)0 | hi == (LTerm*)0) { -> (LRng*)0; };
                -> lf_rng(lo, hi);
            };

            // callee footprint in caller terms: root region to PtrVec* of LAcc*
            translate_fp(LSumm* summ, PtrVec* arg_regs, Node* call, LState* st) -> OMap*
            {
                OMap* out = om_new();
                PtrVec* aterms = pv_new();
                int n = bc_count(call, 0);
                int i, j, k;
                byte* key;
                PtrVec* lst, regs;
                bool off0;
                LAcc* a;
                LRng* rr;
                while (i < n)
                {
                    pv_push(aterms, (void*)this.term_of(node_child(call, 0, i), st));
                    i++;
                };
                i = 0;
                while (i < summ.fp.ks.len)
                {
                    key = (byte*)summ.fp.ks.items[i];
                    lst = (PtrVec*)summ.fp.vs.items[i];
                    i++;
                    if (key[0] == 'p')
                    {
                        j = lf_atoi(lf_seg(key, 1));
                        regs = lf_rs_new();
                        if (j < arg_regs.len) { regs = (PtrVec*)arg_regs.items[j]; };
                        off0 = false;
                        if (j < n) { off0 = this.offset_zero(node_child(call, 0, j)); };
                    }
                    else
                    {
                        regs = lf_rs_one(lf_static(lf_seg(key, 1)));
                        off0 = true;
                    };
                    k = 0;
                    while (k < regs.len)
                    {
                        j = 0;
                        while (j < lst.len)
                        {
                            a = (LAcc*)lst.items[j];
                            rr = (LRng*)0;
                            if (off0) { rr = this.subst_rng(a.rng, aterms); };
                            lf_merge_fp(out, lf_root((byte*)regs.items[k]), a.bits, a.atomic, rr);
                            j++;
                        };
                        k++;
                    };
                };
                -> out;
            };

            outcome(byte* fn0) -> byte*
            {
                byte* sh = bc_last_seg(fn0);
                this.mb.clear();
                this.mb.put_str(f"; '{sh}\0");
                if (this.warn_mode) { this.mb.put_str(g"' runs sequentially\0"); }
                else { this.mb.put_str(g"' cannot be proven safe to run concurrently\0"); };
                -> ts_dup(this.mb.mem);
            };

            // The current function touches these regions: record the footprint and check
            // the access against every async task that may still be running.
            access(PtrVec* regs, int bits, LState* st, bool atomic, byte* what, LRng* rng) -> void
            {
                int i, j, q;
                byte* key, kind, r, msg, oc;
                LTask* t;
                PtrVec* tl, mine, det;
                LAcc* m;
                if (regs.len == 0 | this.no_access) { ->; };
                while (i < regs.len)
                {
                    key = this.fp_key((byte*)regs.items[i]);
                    if (key != (byte*)0) { lf_merge_fp(this.fp, key, bits, atomic, rng); };
                    i++;
                };
                if (st.tasks.ks.len == 0) { ->; };
                m = lf_acc(bits, atomic, rng);
                mine = pv_new();
                pv_push(mine, (void*)m);
                q = 0;
                while (q < st.tasks.vs.len)
                {
                    t = (LTask*)st.tasks.vs.items[q];
                    q++;
                    j = 0;
                    while (j < regs.len)
                    {
                        r = (byte*)regs.items[j];
                        j++;
                        tl = (PtrVec*)om_get(t.fp, lf_root(r));
                        if (tl == (PtrVec*)0) { continue; };
                        if (!this.fp_conflict(mine, tl)) { continue; };
                        om_put(this.async_seq, lf_addr_key((void*)t.node), (void*)1);
                        kind = what;
                        if (kind == (byte*)0)
                        {
                            kind = g"access\0";
                            if (bits == LA_R) { kind = g"read\0"; };
                            if (bits == LA_W) { kind = g"write\0"; };
                            if (bits == LA_F) { kind = g"free\0"; };
                        };
                        oc = this.outcome(t.fn);
                        this.mb.clear();
                        this.mb.put_str(f"{kind} of '{this.rdesc(r)}' conflicts with async call '{bc_last_seg(t.fn)}' still running ({lf_mode_name(this.hit_a)} {this.fmt_rng(this.hit_a.rng)} vs {lf_mode_name(this.hit_b)} {this.fmt_rng(this.hit_b.rng)}); the call has no relation to this code{oc}\0");
                        msg = ts_dup(this.mb.mem);
                        det = pv_new();
                        pv_push(det, (void*)join3(g"async call launched at \0", this.where(t.line), g"\0"));
                        pv_push(det, (void*)g"use the call's result, or relate the two with an async tag, to order them\0");
                        this.report(g"async_conflict\0", msg, this.cur_line, det);
                    };
                };
                ->;
            };

            rel_bits(byte* a, byte* b) -> int
            {
                int* p = (int*)om_get(this.rel, lf_pair_key(a, b));
                if (p == (int*)0) { -> 0; };
                -> p[0];
            };

            // A new async call against the tasks already running. Declared relations are
            // claims: '!' and '>' are enforced by the compiler, '#' and '~' must agree
            // with the derived footprints or the program is rejected.
            check_launch(LTask* task, LState* st) -> void
            {
                int q, i, ops;
                LTask* u;
                PtrVec* ul, lst, det;
                byte* r, what, a, b, oc;
                LAcc* ma, mb2;
                bool found;
                while (q < st.tasks.vs.len)
                {
                    u = (LTask*)st.tasks.vs.items[q];
                    q++;
                    found = false;
                    r = (byte*)0;
                    i = 0;
                    while (i < task.fp.ks.len)
                    {
                        ul = (PtrVec*)om_get(u.fp, (byte*)task.fp.ks.items[i]);
                        if (ul != (PtrVec*)0)
                        {
                            lst = (PtrVec*)task.fp.vs.items[i];
                            if (this.fp_conflict(lst, ul))
                            {
                                r = (byte*)task.fp.ks.items[i];
                                found = true;
                                break;
                            };
                        };
                        i++;
                    };
                    if (!found) { continue; };
                    ma = this.hit_a;
                    mb2 = this.hit_b;
                    ops = this.rel_bits(task.fn, u.fn);
                    if ((ops `& (LA_OP_EXCL `| LA_OP_AFTER `| LA_OP_BEFORE)) != 0) { continue; };
                    om_put(this.async_seq, lf_addr_key((void*)task.node), (void*)1);
                    a = bc_last_seg(task.fn);
                    b = bc_last_seg(u.fn);
                    this.mb.clear();
                    this.mb.put_str(f"'{this.rdesc(r)}' ({lf_mode_name(ma)} {this.fmt_rng(ma.rng)} vs {lf_mode_name(mb2)} {this.fmt_rng(mb2.rng)})\0");
                    what = ts_dup(this.mb.mem);
                    det = pv_new();
                    pv_push(det, (void*)join3(g"first call launched at \0", this.where(u.line), g"\0"));
                    if ((ops `& LA_OP_INDEP) != 0)
                    {
                        pv_push(det, (void*)g"the derived footprint is the truth, the tag claim is wrong\0");
                        this.mb.clear();
                        this.mb.put_str(f"relation '#' between '{a}' and '{b}' is contradicted by the code: both reach {what}\0");
                        this.report(g"async_contradiction\0", ts_dup(this.mb.mem), this.cur_line, det);
                    }
                    else
                    {
                        if ((ops `& LA_OP_COMMUTE) != 0)
                        {
                            pv_push(det, (void*)g"the derived footprint is the truth, the tag claim is wrong\0");
                            this.mb.clear();
                            this.mb.put_str(f"relation '~' between '{a}' and '{b}' is contradicted by the code: the accesses to {what} are not all atomic\0");
                            this.report(g"async_contradiction\0", ts_dup(this.mb.mem), this.cur_line, det);
                        }
                        else
                        {
                            oc = this.outcome(task.fn);
                            pv_push(det, (void*)g"declare #<Tag>(...) with ! or > between them if that is intended\0");
                            this.mb.clear();
                            this.mb.put_str(f"async calls '{a}' and '{b}' both reach {what} and no relation orders or separates them{oc}\0");
                            this.report(g"async_conflict\0", ts_dup(this.mb.mem), this.cur_line, det);
                        };
                    };
                };
                ->;
            };

            // Apply a callee summary; its accesses are already covered by the translated
            // footprint, so they are not recorded or checked twice.
            apply_quiet(byte* fname, PtrVec* arg_regs, LState* st, Node* call) -> PtrVec*
            {
                bool prev = this.no_access;
                PtrVec* r;
                this.no_access = true;
                this.call_col = 0;
                if (call != (Node*)0) { this.call_col = call.col; };
                r = this.apply(fname, arg_regs, st);
                this.no_access = prev;
                -> r;
            };

            // first use of an async call's result waits for it
            join_result(byte* name, LState* st) -> void
            {
                int i;
                LTask* t;
                if (st.tasks.ks.len == 0) { ->; };
                while (i < st.tasks.vs.len)
                {
                    t = (LTask*)st.tasks.vs.items[i];
                    if (t.result_var != (byte*)0)
                    {
                        if (cstr_eq(t.result_var, name))
                        {
                            om_remove_at(st.tasks, i);
                            continue;
                        };
                    };
                    i++;
                };
                ->;
            };

            // ----- relations -----

            resolve_target(Node* tgt, byte* carrier) -> PtrVec*
            {
                PtrVec* cands = pv_new();
                PtrVec* lst, keep;
                byte* name = tgt.text;
                byte* k;
                Node* fd;
                int i, j, n;
                bool ok;
                if (cstr_eq(name, g"this\0"))
                {
                    pv_push(cands, (void*)carrier);
                    -> cands;
                };
                if (nm_has(this.cg.funcs, name))
                {
                    pv_push(cands, (void*)name);
                }
                else
                {
                    lst = (PtrVec*)nm_get(this.cg.overloads, name);
                    if (lst != (PtrVec*)0)
                    {
                        i = 0;
                        while (i < lst.len) { pv_push(cands, lst.items[i]); i++; };
                    };
                    if (cands.len == 0)
                    {
                        if (nm_has(this.cg.short_names, name))
                        {
                            pv_push(cands, nm_get(this.cg.short_names, name));
                        };
                    };
                    if (cands.len == 0)
                    {
                        i = 0;
                        while (i < this.cg.async_names.count)
                        {
                            k = this.cg.async_names.keys[i];
                            if (this.cg.async_names.vals[i] != (void*)0)
                            {
                                if (cstr_eq(k, name) | bc_ends(k, join3(g"__\0", name, g"\0")))
                                {
                                    pv_push(cands, (void*)k);
                                };
                            };
                            i++;
                        };
                    };
                };
                if (tgt.ival == (i64)1)
                {
                    keep = pv_new();
                    n = bc_count(tgt, 0);
                    i = 0;
                    while (i < cands.len)
                    {
                        fd = (Node*)nm_get(this.cg.funcs, (byte*)cands.items[i]);
                        i++;
                        if (fd == (Node*)0) { continue; };
                        if (bc_count(fd, 0) != n) { continue; };
                        ok = true;
                        j = 0;
                        while (j < n)
                        {
                            if (!typespec_equal(node_child(fd, 0, j).ts, node_child(tgt, 0, j).ts)) { ok = false; };
                            j++;
                        };
                        if (ok) { pv_push(keep, cands.items[i - 1]); };
                    };
                    cands = keep;
                };
                -> cands;
            };

            rel_add(byte* a, byte* b, int bit) -> void
            {
                byte* key = lf_pair_key(a, b);
                int* p = (int*)om_get(this.rel, key);
                if (p == (int*)0)
                {
                    -> om_put(this.rel, key, (void*)bx_new(bit));
                };
                p[0] = p[0] `| bit;
                ->;
            };

            // rel[(a, b)] is the set of operators declared between async functions a and b
            build_relations() -> void
            {
                int ui, pi, ri, k, x, y, bit, flip;
                AUse* u;
                Node* tag, rr;
                PtrVec* ba, bb;
                OMap* bind;
                byte* op;
                while (ui < this.cg.async_uses.len)
                {
                    u = (AUse*)this.cg.async_uses.items[ui];
                    ui++;
                    tag = (Node*)nm_get(this.cg.async_tags, u.use.text);
                    if (tag == (Node*)0) { continue; };
                    if (bc_count(u.use, 0) != bc_count(tag, 0)) { continue; };
                    bind = om_new();
                    pi = 0;
                    while (pi < bc_count(tag, 0))
                    {
                        om_put(bind, node_child(tag, 0, pi).text, (void*)this.resolve_target(node_child(u.use, 0, pi), u.key));
                        pi++;
                    };
                    ri = 0;
                    while (ri < bc_count(tag, 1))
                    {
                        rr = node_child(tag, 1, ri);
                        ri++;
                        k = 0;
                        while (k < bc_count(rr, 1))
                        {
                            op = node_child(rr, 1, k).text;
                            bit = lf_op_bit(op);
                            flip = bit;
                            if (bit == LA_OP_AFTER) { flip = LA_OP_BEFORE; };
                            ba = (PtrVec*)om_get(bind, node_child(rr, 0, k).text);
                            bb = (PtrVec*)om_get(bind, node_child(rr, 0, k + 1).text);
                            if (ba != (PtrVec*)0 & bb != (PtrVec*)0)
                            {
                                x = 0;
                                while (x < ba.len)
                                {
                                    y = 0;
                                    while (y < bb.len)
                                    {
                                        this.rel_add((byte*)ba.items[x], (byte*)bb.items[y], bit);
                                        this.rel_add((byte*)bb.items[y], (byte*)ba.items[x], flip);
                                        y++;
                                    };
                                    x++;
                                };
                            };
                            k++;
                        };
                    };
                };
                ->;
            };

            // A call to a resolved function: async launches become tasks, other calls are
            // accesses made through the callee's translated footprint.
            call_resolved(Node* e, byte* resolved, LSumm* summ, PtrVec* arg_regs, LState* st) -> PtrVec*
            {
                bool launch;
                bool is_as = this.is_async(resolved);
                int q, i;
                LTask* u, task;
                PtrVec* w, ret, v, lst;
                OMap* tfp;
                LAcc* a;
                byte* nk;
                if (is_as & e == this.async_node) { launch = true; };
                this.async_node = (Node*)0;
                if (is_as) { om_put(this.async_target, lf_addr_key((void*)e), (void*)resolved); };
                if (is_as & st.tasks.ks.len > 0)
                {
                    // a task the callee is declared to follow ('>') must finish first
                    q = 0;
                    while (q < st.tasks.vs.len)
                    {
                        u = (LTask*)st.tasks.vs.items[q];
                        if ((this.rel_bits(u.fn, resolved) `& LA_OP_AFTER) != 0)
                        {
                            w = (PtrVec*)om_get(this.async_waits, lf_addr_key((void*)e));
                            if (w == (PtrVec*)0)
                            {
                                w = pv_new();
                                om_put(this.async_waits, lf_addr_key((void*)e), (void*)w);
                            };
                            nk = lf_addr_key((void*)u.node);
                            if (!lf_pv_has(w, nk)) { pv_push(w, (void*)nk); };
                            om_remove_at(st.tasks, q);
                            continue;
                        };
                        q++;
                    };
                };
                if (bc_starts(resolved, g"standard__atomic__\0"))
                {
                    // the atomic primitives are atomic by definition: every pointer they
                    // are given is read and written atomically
                    i = 0;
                    while (i < arg_regs.len)
                    {
                        v = (PtrVec*)arg_regs.items[i];
                        if (v.len > 0)
                        {
                            this.access(this.roots_of(v), LA_R `| LA_W, st, true, (byte*)0, (LRng*)0);
                        };
                        i++;
                    };
                    -> this.apply_quiet(resolved, arg_regs, st, e);
                };
                tfp = this.translate_fp(summ, arg_regs, e, st);
                if (launch)
                {
                    task = (LTask*)fmalloc((u64)((sizeof(LTask) + 7) / 8));
                    task
                    {
                        .fn = resolved;
                        .fp = tfp;
                        .line = this.cur_line;
                        .result_var = (byte*)0;
                        .bid = g"fn\0";
                    };
                    if (st.active.len > 0) { task.bid = (byte*)st.active.items[st.active.len - 1]; };
                    task.node = e;
                    om_put(this.async_launched, lf_addr_key((void*)e), (void*)1);
                    this.check_launch(task, st);
                    this.merge_fp_roots(tfp);
                    ret = this.apply_quiet(resolved, arg_regs, st, e);
                    om_put(st.tasks, lf_addr_key((void*)e), (void*)task);
                    this.last_task = task;
                    -> ret;
                };
                i = 0;
                while (i < tfp.ks.len)
                {
                    lst = (PtrVec*)tfp.vs.items[i];
                    q = 0;
                    while (q < lst.len)
                    {
                        a = (LAcc*)lst.items[q];
                        this.mb.clear();
                        this.mb.put_str(f"call to '{bc_last_seg(resolved)}'\0");
                        this.access(lf_rs_one((byte*)tfp.ks.items[i]), a.bits, st, a.atomic, ts_dup(this.mb.mem), a.rng);
                        q++;
                    };
                    i++;
                };
                -> this.apply_quiet(resolved, arg_regs, st, e);
            };

            // ----- driver -----

            run() -> void
            {
                int i;
                this.build_relations();
                if (nm_has(this.cg.funcs, this.entry))
                {
                    this.summary(this.entry);
                }
                else
                {
                    while (i < this.cg.funcs.count)
                    {
                        this.summary(this.cg.funcs.keys[i]);
                        i++;
                    };
                };
                ->;
            };

            // ----- call resolution -----

            resolve(byte* name, int nargs) -> byte*
            {
                PtrVec* cands;
                int i;
                byte* c;
                byte* base;
                Node* f;
                if (name == (byte*)0) { -> (byte*)0; };
                if (name[0] == 0) { -> (byte*)0; };
                if (nm_has(this.cg.funcs, name)) { -> name; };
                if (nm_has(this.cg.short_names, name)) { -> (byte*)nm_get(this.cg.short_names, name); };
                cands = (PtrVec*)nm_get(this.cg.overloads, name);
                if (cands == (PtrVec*)0)
                {
                    // a mangled call target (main__0__ret_intE1): resolve its source name
                    base = bc_overload_base(name);
                    if (base[0] != 0)
                    {
                        cands = (PtrVec*)nm_get(this.cg.overloads, base);
                        if (cands == (PtrVec*)0)
                        {
                            if (nm_has(this.cg.funcs, base))
                            {
                                cands = pv_new();
                                pv_push(cands, (void*)base);
                            };
                        };
                        nargs = bc_mangled_arity(name);
                    };
                };
                if (cands == (PtrVec*)0) { -> (byte*)0; };
                if (cands.len == 1) { -> (byte*)cands.items[0]; };
                i = 0;
                while (i < cands.len)
                {
                    c = (byte*)cands.items[i];
                    f = (Node*)nm_get(this.cg.funcs, c);
                    if (f != (Node*)0)
                    {
                        if (bc_count(f, 0) == nargs) { -> c; };
                    };
                    i++;
                };
                -> (byte*)0;
            };

            // ----- block ids -----

            blk_id(Node* n) -> byte*
            {
                int i;
                while (i < this.blks.len)
                {
                    if ((Node*)this.blks.items[i] == n) { -> lf_itoa(i); };
                    i++;
                };
                pv_push(this.blks, (void*)n);
                -> lf_itoa(this.blks.len - 1);
            };

            active_push(LState* st, byte* bid) -> void
            {
                PtrVec* a = pv_new();
                int i;
                while (i < st.active.len) { pv_push(a, st.active.items[i]); i++; };
                pv_push(a, (void*)bid);
                st.active = a;
                ->;
            };

            active_pop(LState* st, byte* bid) -> void
            {
                PtrVec* a = pv_new();
                int i;
                while (i < st.active.len)
                {
                    if (!cstr_eq((byte*)st.active.items[i], bid)) { pv_push(a, st.active.items[i]); };
                    i++;
                };
                st.active = a;
                ->;
            };

            // ----- function summary -----

            summary(byte* name) -> LSumm*
            {
                Node* func, p;
                LState* st, exit_state;
                int i, n, j;
                byte* reg, pr, k, c;
                LSumm* sm;
                PtrVec* ret, path, v;
                LRet* lr;
                LHeld* lh;
                // saved walk context
                byte* s_fn;
                OMap* s_locals, s_fp, s_ivars, s_heapvars;
                PtrVec* s_loops, s_defers, s_returns;
                int s_line;
                LAl* s_al;
                Node* s_async_node;
                LTask* s_last_task;

                if (nm_has(this.summaries, name)) { -> (LSumm*)nm_get(this.summaries, name); };
                sm = (LSumm*)fmalloc((u64)((sizeof(LSumm) + 7) / 8));
                sm
                {
                    .ret = pv_new();
                    .nparams = 0;
                    .param_status = om_new();
                    .wr = om_new();
                    .param_held = pv_new();
                    .heap_status = om_new();
                    .esc = om_new();
                    .free_at = om_new();
                    .fp = om_new();
                };
                if (nm_has(this.active_summ, name)) { -> sm; };
                nm_put(this.active_summ, name, (void*)1);
                s_fn = this.fn;
                s_locals = this.locals;
                s_heapvars = this.heapvars;
                s_loops = this.loops;
                s_defers = this.defers;
                s_returns = this.returns;
                s_line = this.cur_line;
                s_al = this.al;
                s_fp = this.fp;
                s_async_node = this.async_node;
                s_last_task = this.last_task;
                s_ivars = this.ivars;
                this.fp = om_new();
                this.async_node = (Node*)0;
                this.last_task = (LTask*)0;
                this.ivars = om_new();

                func = (Node*)nm_get(this.cg.funcs, name);
                this.funcs_checked++;
                this.al = lf_al_new();
                this.index_function(func);
                this.fn = name;
                this.locals = om_new();
                this.heapvars = om_new();
                this.loops = pv_new();
                this.defers = pv_new();
                pv_push(this.defers, (void*)pv_new());
                this.returns = pv_new();
                this.cur_line = func.line;

                st = lf_state_new();
                pv_push(st.active, (void*)g"fn\0");
                n = bc_count(func, 0);
                i = 0;
                while (i < n)
                {
                    p = node_child(func, 0, i);
                    if (p.text != (byte*)0)
                    {
                        if (p.text[0] != 0)
                        {
                            reg = lf_stack(name, p.text, g"fn\0");
                            lf_loc_put(this.locals, p.text, 0, reg);
                            if (bc_is_pointer_type(p.ts)) { om_put(this.al.ptr_vars, p.text, (void*)1); };
                            om_put(this.al.first, p.text, (void*)bx_new(-1));
                            if (this.may_carry_pointer(p.ts))
                            {
                                om_put(st.env, p.text, (void*)lf_rs_one(lf_param(name, i)));
                            }
                            else
                            {
                                om_put(st.env, p.text, (void*)lf_rs_new());
                            };
                            if (!bc_is_pointer_type(p.ts))
                            {
                                if (p.ts == (TypeSpec*)0) { om_put(st.terms, p.text, (void*)lf_term(i, 0)); }
                                else
                                {
                                    if ((p.ts.flags `& TS_ARRAY) == 0) { om_put(st.terms, p.text, (void*)lf_term(i, 0)); };
                                };
                            };
                        };
                    };
                    i++;
                };
                if (func.a != (Node*)0)
                {
                    if (func.a.kind == NodeKind.BLOCK)
                    {
                        this.block(func.a, st, false);
                    }
                    else
                    {
                        this.eval(func.a, st);
                    };
                };
                if (!st.dead)
                {
                    this.run_defers_all(st);
                    this.exit_path(st, lf_rs_new(), this.cur_line);
                    lr = (LRet*)fmalloc((u64)((sizeof(LRet) + 7) / 8));
                    lr
                    {
                        .st = lf_state_copy(st);
                        .regs = lf_rs_new();
                    };
                    pv_push(this.returns, (void*)lr);
                };
                exit_state = (LState*)0;
                ret = lf_rs_new();
                i = 0;
                while (i < this.returns.len)
                {
                    lr = (LRet*)this.returns.items[i];
                    exit_state = lf_join(exit_state, lr.st);
                    ret = lf_rs_union(ret, lr.regs);
                    i++;
                };
                sm
                {
                    .ret = ret;
                    .nparams = n;
                };
                if (exit_state != (LState*)0)
                {
                    int q, along;
                    int* fl;
                    bool seen_any;
                    i = 0;
                    while (i < n)
                    {
                        pr = lf_param(name, i);
                        if (om_has(exit_state.status, pr))
                        {
                            om_put(sm.param_status, lf_itoa(i), om_get(exit_state.status, pr));
                        };
                        j = 0;
                        while (j < exit_state.held.ks.len)
                        {
                            k = (byte*)exit_state.held.ks.items[j];
                            v = (PtrVec*)exit_state.held.vs.items[j];
                            path = pv_new();
                            c = k;
                            while (c[0] == 'F')
                            {
                                pv_push(path, (void*)lf_fld_member(c));
                                c = lf_fld_cell(c);
                            };
                            if (cstr_eq(c, pr) & v.len > 0)
                            {
                                lh = (LHeld*)fmalloc((u64)((sizeof(LHeld) + 7) / 8));
                                lh
                                {
                                    .idx = i;
                                    .regs = v;
                                };
                                // outermost member first
                                lh.path = pv_new();
                                {
                                    q = path.len - 1;
                                    while (q >= 0)
                                    {
                                        pv_push(lh.path, path.items[q]);
                                        q--;
                                    };
                                };
                                pv_push(sm.param_held, (void*)lh);
                            };
                            j++;
                        };
                        i++;
                    };
                    j = 0;
                    while (j < exit_state.status.ks.len)
                    {
                        k = (byte*)exit_state.status.ks.items[j];
                        if (k[0] == 'H') { om_put(sm.heap_status, k, exit_state.status.vs.items[j]); };
                        j++;
                    };
                    // a returned region carries the status it had along the paths that return it
                    j = 0;
                    while (j < ret.len)
                    {
                        k = (byte*)ret.items[j];
                        j++;
                        if (k[0] != 'H') { continue; };
                        along = 0;
                        seen_any = false;
                        q = 0;
                        while (q < this.returns.len)
                        {
                            lr = (LRet*)this.returns.items[q];
                            q++;
                            if (!lf_rs_has(lr.regs, k)) { continue; };
                            fl = (int*)om_get(lr.st.status, k);
                            if (fl == (int*)0) { continue; };
                            along = along `| fl[0];
                            seen_any = true;
                        };
                        if (seen_any)
                        {
                            om_put(sm.heap_status, k, (void*)bx_new(along));
                        };
                    };
                    sm
                    {
                        .esc = om_copy(exit_state.esc);
                        .free_at = om_copy(exit_state.free_at);
                    };
                };
                this.fn = s_fn;
                this.locals = s_locals;
                this.heapvars = s_heapvars;
                this.loops = s_loops;
                this.defers = s_defers;
                this.returns = s_returns;
                sm.fp = this.fp;
                this.fp = s_fp;
                this.async_node = s_async_node;
                this.last_task = s_last_task;
                this.ivars = s_ivars;
                sm.wr = om_copy(this.al.wr_params);
                this.al = s_al;
                this.cur_line = s_line;
                nm_del(this.active_summ, name);
                nm_put(this.summaries, name, (void*)sm);
                -> sm;
            };

            // ----- statements -----

            block(Node* b, LState* st, bool new_scope) -> void
            {
                byte* bid = g"fn\0";
                int c = bc_count(b, 0);
                int i;
                Node* s;
                if (new_scope)
                {
                    bid = this.blk_id(b);
                    this.active_push(st, bid);
                };
                pv_push(this.defers, (void*)pv_new());
                while (i < c)
                {
                    s = node_child(b, 0, i);
                    if (s != (Node*)0)
                    {
                        if (st.dead) { break; };
                        this.stmt(s, st, bid);
                    };
                    i++;
                };
                if (!st.dead) { this.run_defers_top(st); };
                this.defers.len--;
                if (new_scope)
                {
                    this.active_pop(st, bid);
                    i = 0;
                    while (i < st.tasks.vs.len)
                    {
                        if (cstr_eq(((LTask*)st.tasks.vs.items[i]).bid, bid)) { om_remove_at(st.tasks, i); continue; };
                        i++;
                    };
                };
                ->;
            };

            run_defers_top(LState* st) -> void
            {
                PtrVec* top = (PtrVec*)this.defers.items[this.defers.len - 1];
                int i = top.len - 1;
                while (i >= 0)
                {
                    this.run_defer((Node*)top.items[i], st);
                    i--;
                };
                this.defers.items[this.defers.len - 1] = (void*)pv_new();
                ->;
            };

            run_defers_all(LState* st) -> void
            {
                int lv = this.defers.len - 1;
                PtrVec* top;
                int i;
                while (lv >= 0)
                {
                    top = (PtrVec*)this.defers.items[lv];
                    i = top.len - 1;
                    while (i >= 0)
                    {
                        this.run_defer((Node*)top.items[i], st);
                        i--;
                    };
                    lv--;
                };
                ->;
            };

            run_defer(Node* d, LState* st) -> void
            {
                int c = bc_count(d, 0);
                int i;
                if ((d.flags `& NF_HAS_BODY) != 0)
                {
                    while (i < c)
                    {
                        this.stmt(node_child(d, 0, i), st, g"fn\0");
                        i++;
                    };
                }
                else
                {
                    if (d.a != (Node*)0) { this.eval(d.a, st); };
                };
                ->;
            };

            stmt(Node* node, LState* st, byte* bid) -> void
            {
                int k = node.kind;
                int ln = node.line;
                Node* cc;
                LState* pre, s2, res;
                int i, c;
                if (ln != 0) { this.cur_line = ln; };

                if (k == NodeKind.VARIABLE_DECLARATION) { -> this.decl(node, st, bid); };
                if (k == NodeKind.EXPRESSION_STATEMENT)
                {
                    this.async_node = node.a;
                    this.eval(node.a, st);
                    ->;
                };
                if (k == NodeKind.ASSIGNMENT) { -> this.assign(node.a, node.b, st); };
                if (k == NodeKind.COMPOUND_ASSIGNMENT) { -> this.compound(node, st); };
                if (k == NodeKind.BLOCK) { this.block(node, st, true); ->; };
                if (k == NodeKind.RETURN_STATEMENT) { -> this.do_return(node, st); };
                if (k == NodeKind.IF_STATEMENT) { -> this.do_if(node, st); };
                if (k == NodeKind.WHILE_LOOP)
                {
                    -> this.loop(st, node.a, node.b, true, (Node*)0, false);
                };
                if (k == NodeKind.DO_WHILE_LOOP)
                {
                    -> this.loop(st, node.a, node.b, false, (Node*)0, false);
                };
                if (k == NodeKind.DO_LOOP)
                {
                    -> this.loop(st, (Node*)0, node.b, false, (Node*)0, true);
                };
                if (k == NodeKind.FOR_LOOP)
                {
                    cc = node;
                    this.active_push(st, this.blk_id(cc));
                    if (node.a != (Node*)0) { this.stmt(node.a, st, this.blk_id(cc)); };
                    this.loop(st, node.b, node.d, true, node.c, false);
                    -> this.active_pop(st, this.blk_id(cc));
                };
                if (k == NodeKind.FOR_IN_LOOP)
                {
                    this.eval(node.a, st);
                    c = bc_count(node, 0);
                    i = 0;
                    while (i < c)
                    {
                        cc = node_child(node, 0, i);
                        om_put(st.env, cc.text, (void*)lf_rs_new());
                        lf_loc_put(this.locals, cc.text, 0, lf_stack(this.fn, cc.text, this.blk_id(node.b)));
                        i++;
                    };
                    -> this.loop(st, (Node*)0, node.b, true, (Node*)0, false);
                };
                if (k == NodeKind.SWITCH_STATEMENT) { -> this.do_switch(node, st); };
                if (k == NodeKind.BREAK_STATEMENT)
                {
                    if (this.loops.len > 0)
                    {
                        LLoop* lp = (LLoop*)this.loops.items[this.loops.len - 1];
                        pv_push(lp.breaks, (void*)lf_state_copy(st));
                    };
                    st.dead = true;
                    ->;
                };
                if (k == NodeKind.CONTINUE_STATEMENT)
                {
                    if (this.loops.len > 0)
                    {
                        LLoop* lp2 = (LLoop*)this.loops.items[this.loops.len - 1];
                        pv_push(lp2.conts, (void*)lf_state_copy(st));
                    };
                    st.dead = true;
                    ->;
                };
                if (k == NodeKind.DEFER_STATEMENT)
                {
                    -> pv_push((PtrVec*)this.defers.items[this.defers.len - 1], (void*)node);
                };
                if (k == NodeKind.TRY_BLOCK)
                {
                    pre = lf_state_copy(st);
                    this.block(node.a, st, true);
                    res = lf_join(pre, st);
                    c = bc_count(node, 0);
                    i = 0;
                    while (i < c)
                    {
                        cc = node_child(node, 0, i);
                        s2 = lf_state_copy(pre);
                        if (cc.a != (Node*)0) { this.block(cc.a, s2, true); };
                        res = lf_join(res, s2);
                        i++;
                    };
                    -> lf_state_set(st, res);
                };
                -> this.generic(node, st);
            };

            generic_child(Node* v, LState* st) -> void
            {
                if (v == (Node*)0) { ->; };
                if (v.kind == NodeKind.BLOCK) { this.block(v, st, true); ->; };
                if (lf_is_stmt_kind(v.kind)) { -> this.stmt(v, st, g"fn\0"); };
                this.eval(v, st);
                ->;
            };

            // unknown statement: evaluate its expressions, walk nested blocks
            generic(Node* node, LState* st) -> void
            {
                int s, c, i;
                this.generic_child(node.a, st);
                this.generic_child(node.b, st);
                this.generic_child(node.c, st);
                this.generic_child(node.d, st);
                while (s < 6)
                {
                    c = bc_count(node, s);
                    i = 0;
                    while (i < c)
                    {
                        this.generic_child(node_child(node, s, i), st);
                        i++;
                    };
                    s++;
                };
                ->;
            };

            // ----- declarations -----

            decl(Node* node, LState* st, byte* bid) -> void
            {
                TypeSpec* ts = node.ts;
                byte* reg = lf_stack(this.fn, node.text, bid);
                bool is_arr;
                Node* iv = node.a;
                PtrVec* v;
                int c, i;
                LTerm* tm;
                byte* hsite;
                bool is_heap;
                if ((node.flags `& NF_GLOBAL) != 0) { reg = lf_static(node.text); };
                if (ts != (TypeSpec*)0)
                {
                    if ((ts.flags `& TS_ARRAY) != 0) { is_arr = true; };
                };
                if (is_arr) { lf_loc_put(this.locals, node.text, 1, reg); }
                else { lf_loc_put(this.locals, node.text, 0, reg); };
                om_put(st.env, node.text, (void*)lf_rs_new());
                om_del(st.terms, node.text);
                if (bc_is_pointer_type(ts) & !is_arr) { om_put(this.al.ptr_vars, node.text, (void*)1); };
                // heap T x: x is a T* into a fresh allocation (codegen _vardecl_heap)
                if (ts != (TypeSpec*)0 & (node.flags `& NF_GLOBAL) == 0)
                {
                    if (ts.storage_class == StorageClass.HEAP)
                    {
                        hsite = lf_heap(this.fn, this.cur_line, (byte*)0);
                        om_put(st.status, hsite, (void*)bx_new(LF_O));
                        om_del(st.esc, hsite);
                        om_del(st.free_at, hsite);
                        om_put(this.heapvars, node.text, (void*)1);
                        om_put(this.al.ptr_vars, node.text, (void*)1);
                        om_put(st.env, node.text, (void*)lf_rs_one(hsite));
                        is_heap = true;
                    };
                };
                if (!is_heap) { om_del(this.heapvars, node.text); };
                if (iv != (Node*)0) { this.add_deriv(node.text, iv); };
                if (iv != (Node*)0)
                {
                    if (iv.kind == NodeKind.ARRAY_LITERAL)
                    {
                        c = bc_count(iv, 0);
                        i = 0;
                        while (i < c)
                        {
                            v = this.eval(node_child(iv, 0, i), st);
                            this.store_cells(lf_rs_one(reg), v, st, false, node);
                            i++;
                        };
                        ->;
                    };
                    this.async_node = iv;
                    this.last_task = (LTask*)0;
                    tm = (LTerm*)0;
                    if (!is_arr & !bc_is_pointer_type(ts)) { tm = this.term_of(iv, st); };
                    v = this.eval(iv, st);
                    if (tm != (LTerm*)0) { om_put(st.terms, node.text, (void*)tm); };
                    if (this.last_task != (LTask*)0)
                    {
                        if (this.last_task.node == iv)
                        {
                            this.last_task.result_var = node.text;
                            this.last_task = (LTask*)0;
                        };
                    };
                    if (!is_arr) { om_put(st.env, node.text, (void*)v); };
                };
                if (is_heap) { om_put(st.env, node.text, (void*)lf_rs_one(hsite)); };
                ->;
            };

            // ----- assignment -----

            assign(Node* target, Node* value, LState* st) -> void
            {
                PtrVec* v, cells, dr;
                LocInfo* info;
                byte* reg;
                int i;
                LTerm* tm;
                this.async_node = value;
                this.last_task = (LTask*)0;
                v = this.eval(value, st);
                if (this.last_task != (LTask*)0)
                {
                    if (this.last_task.node == value)
                    {
                        if (target.kind == NodeKind.IDENTIFIER) { this.last_task.result_var = target.text; };
                        this.last_task = (LTask*)0;
                    };
                };
                if (target.kind == NodeKind.IDENTIFIER)
                {
                    info = lf_loc_get(this.locals, target.text);
                    if (info != (LocInfo*)0)
                    {
                        if (info.reg[0] != 'G')
                        {
                            this.add_deriv(target.text, value);
                            this.access(lf_rs_one(info.reg), LA_W, st, false, (byte*)0, (LRng*)0);
                            tm = this.term_of(value, st);
                            if (tm != (LTerm*)0) { om_put(st.terms, target.text, (void*)tm); }
                            else { om_del(st.terms, target.text); };
                            -> om_put(st.env, target.text, (void*)v);
                        };
                    };
                    reg = lf_static(target.text);
                    this.access(lf_rs_one(reg), LA_W, st, false, (byte*)0, (LRng*)0);
                    this.escape_check(lf_rs_one(reg), v, st, target);
                    om_put(st.held, reg, (void*)v);
                    -> this.mark_esc(v, st);
                };
                this.cells_of(target, st);
                cells = this.cells_r;
                dr = this.deref_r;
                if (dr.len > 0)
                {
                    this.deref_check(dr, target, st);
                    this.alias_check(target, dr, st, true);
                };
                this.access(this.roots_of(cells), LA_W, st, false, (byte*)0, this.acc_range(target, st));
                if (target.kind == NodeKind.ARRAY_ACCESS)
                {
                    if (target.b.kind != NodeKind.LITERAL & target.b.kind != NodeKind.STRING_LITERAL)
                    {
                        i = 0;
                        while (i < v.len)
                        {
                            if (((byte*)v.items[i])[0] == 'H' | ((byte*)v.items[i])[0] == 'P')
                            {
                                om_put(this.multi, (byte*)v.items[i], (void*)1);
                            };
                            i++;
                        };
                    };
                };
                -> this.store_cells(cells, v, st, true, target);
            };

            compound(Node* node, LState* st) -> void
            {
                Node* t = node.a;
                PtrVec* v, cells;
                LocInfo* info;
                if (t.kind != NodeKind.IDENTIFIER)
                {
                    this.cells_of(t, st);
                    cells = this.cells_r;
                    if (this.deref_r.len > 0)
                    {
                        this.deref_check(this.deref_r, t, st);
                        this.alias_check(t, this.deref_r, st, true);
                    };
                    this.access(this.roots_of(cells), LA_R `| LA_W, st, false, (byte*)0, this.acc_range(t, st));
                }
                else
                {
                    info = lf_loc_get(this.locals, t.text);
                    if (info != (LocInfo*)0)
                    {
                        om_del(st.terms, t.text);
                        this.access(lf_rs_one(info.reg), LA_R `| LA_W, st, false, (byte*)0, (LRng*)0);
                    }
                    else
                    {
                        this.access(lf_rs_one(lf_static(t.text)), LA_R `| LA_W, st, false, (byte*)0, (LRng*)0);
                    };
                };
                v = this.eval(node.b, st);
                if (t.kind == NodeKind.IDENTIFIER)
                {
                    if (lf_loc_get(this.locals, t.text) != (LocInfo*)0)
                    {
                        om_put(st.env, t.text, (void*)lf_rs_union(lf_env_get(st.env, t.text), v));
                    };
                };
                ->;
            };

            store_cells(PtrVec* cells, PtrVec* v, LState* st, bool check, Node* node) -> void
            {
                int i;
                byte* c;
                if (v.len == 0) { ->; };
                if (check) { this.escape_check(cells, v, st, node); };
                while (i < cells.len)
                {
                    c = (byte*)cells.items[i];
                    if (om_has(st.held, c))
                    {
                        om_put(st.held, c, (void*)lf_rs_union((PtrVec*)om_get(st.held, c), v));
                    }
                    else
                    {
                        om_put(st.held, c, (void*)v);
                    };
                    i++;
                };
                -> this.mark_esc(v, st);
            };

            mark_esc(PtrVec* v, LState* st) -> void
            {
                int i;
                byte* r;
                while (i < v.len)
                {
                    r = (byte*)v.items[i];
                    if (r[0] == 'H' | r[0] == 'P') { om_put(st.esc, r, (void*)1); };
                    i++;
                };
                ->;
            };

            // storing a pointer to a local into a longer lived place
            escape_check(PtrVec* cells, PtrVec* v, LState* st, Node* node) -> void
            {
                PtrVec* locs = pv_new();
                int i, j;
                byte* r, c, cf, what, nm;
                bool outlives;
                while (i < v.len)
                {
                    r = (byte*)v.items[i];
                    if (r[0] == 'S')
                    {
                        if (cstr_eq(lf_seg(r, 1), this.fn)) { pv_push(locs, (void*)r); };
                    };
                    i++;
                };
                if (locs.len == 0) { ->; };
                i = 0;
                while (i < cells.len)
                {
                    c = lf_root((byte*)cells.items[i]);
                    outlives = c[0] == 'P' | c[0] == 'H' | c[0] == 'G';
                    if (c[0] == 'S')
                    {
                        cf = lf_seg(c, 1);
                        if (!cstr_eq(cf, this.fn)) { outlives = true; };
                    };
                    if (outlives)
                    {
                        what = g"an outer cell\0";
                        if (c[0] == 'P') { what = g"a parameter pointee\0"; };
                        if (c[0] == 'H') { what = g"a heap cell\0"; };
                        if (c[0] == 'G') { what = g"a global\0"; };
                        j = 0;
                        while (j < locs.len)
                        {
                            r = (byte*)locs.items[j];
                            nm = lf_seg(r, 2);
                            this.sb.clear();
                            this.sb.put_str(f"pointer to local '{nm}' stored in {what} and outlives its stack allocation '{this.rdesc(r)}' (allocation scope exited)\0");
                            this.report(g"scope_escape\0", this.take(), this.cur_line,
                                        this.det1(g"stored at \0", this.where(this.cur_line)));
                            j++;
                        };
                    };
                    i++;
                };
                ->;
            };

            // ----- return -----

            do_return(Node* node, LState* st) -> void
            {
                PtrVec* v = lf_rs_new();
                int i;
                byte* r;
                LRet* lr;
                if (node.a != (Node*)0) { v = this.eval(node.a, st); };
                while (i < v.len)
                {
                    r = (byte*)v.items[i];
                    if (r[0] == 'S')
                    {
                        if (cstr_eq(lf_seg(r, 1), this.fn))
                        {
                            this.sb.clear();
                            this.sb.put_str(f"pointer to local '{lf_seg(r, 2)}' returned and outlives its stack allocation '{this.rdesc(r)}' (allocation scope exited)\0");
                            this.report(g"scope_escape\0", this.take(), this.cur_line,
                                        this.det1(g"returned at \0", this.where(this.cur_line)));
                        };
                    };
                    i++;
                };
                this.run_defers_all(st);
                this.exit_path(st, v, this.cur_line);
                lr = (LRet*)fmalloc((u64)((sizeof(LRet) + 7) / 8));
                lr
                {
                    .st = lf_state_copy(st);
                    .regs = v;
                };
                pv_push(this.returns, (void*)lr);
                st.dead = true;
                ->;
            };

            // leak check at one exit path
            exit_path(LState* st, PtrVec* ret, int line) -> void
            {
                int i;
                byte* r, o;
                int* fl;
                PtrVec* d;
                while (i < st.status.ks.len)
                {
                    r = (byte*)st.status.ks.items[i];
                    fl = (int*)st.status.vs.items[i];
                    i++;
                    if (r[0] != 'H') { continue; };
                    if (lf_rs_has(ret, r)) { continue; };
                    if (om_has(st.esc, r)) { continue; };
                    if (fl[0] != LF_O) { continue; };
                    o = lf_origin(r);
                    this.sb.clear();
                    this.sb.put_str(f"heap allocation '{this.rdesc(r)}' has no reachable ffree on all paths\0");
                    d = pv_new();
                    this.sb.clear();
                    this.sb.put_str(g"allocated at \0");
                    this.sb.put_str(this.where(lf_atoi(lf_seg(o, 2))));
                    pv_push(d, (void*)this.take());
                    this.sb.clear();
                    this.sb.put_str(f"never freed or handed off on the path ending at {this.where(line)}\0");
                    pv_push(d, (void*)this.take());
                    this.sb.clear();
                    this.sb.put_str(f"heap allocation '{this.rdesc(r)}' has no reachable ffree on all paths\0");
                    this.report(g"heap_leak\0", this.take(), lf_atoi(lf_seg(r, 2)), d);
                };
                ->;
            };

            // ----- control flow -----

            // ----- null narrowing -----

            nf_bare(Node* e) -> Node*
            {
                while (e != (Node*)0 & bc_is_cast(e)) { e = e.a; };
                return e;
            };

            nf_zero(Node* e) -> bool
            {
                if (e == (Node*)0) { return false; };
                if (e.kind != NodeKind.LITERAL) { return false; };
                if (e.op == DataType.SINT | e.op == DataType.UINT | e.op == DataType.SLONG | e.op == DataType.ULONG | e.op == DataType.BOOL)
                {
                    return e.ival == 0;
                };
                return false;
            };

            // variables known to be null when cond evaluates to truth
            null_facts(Node* cond, bool truth, PtrVec* out) -> void
            {
                Node* c = this.nf_bare(cond);
                Node* l, r, t;
                bool is_eq;
                if (c == (Node*)0) { ->; };
                if (c.kind == NodeKind.UNARY_OP)
                {
                    if (c.op == Operator.NOT & ((c.flags `& 1) == 0))
                    {
                        this.null_facts(c.a, !truth, out);
                    };
                    ->;
                };
                if (c.kind == NodeKind.IDENTIFIER)
                {
                    if (!truth) { pv_push(out, (void*)c.text); };
                    ->;
                };
                if (c.kind == NodeKind.BINARY_OP)
                {
                    if (c.op == Operator.EQUAL | c.op == Operator.NOT_EQUAL)
                    {
                        l = this.nf_bare(c.a);
                        r = this.nf_bare(c.b);
                        if (r != (Node*)0 & l != (Node*)0)
                        {
                            if (r.kind == NodeKind.IDENTIFIER & l.kind == NodeKind.LITERAL)
                            {
                                t = l;
                                l = r;
                                r = t;
                            };
                        };
                        if (l != (Node*)0 & r != (Node*)0)
                        {
                            if (l.kind == NodeKind.IDENTIFIER & this.nf_zero(r))
                            {
                                is_eq = c.op == Operator.EQUAL;
                                if (is_eq == truth) { pv_push(out, (void*)l.text); };
                            };
                        };
                        ->;
                    };
                    if (c.op == Operator.AND & truth)
                    {
                        this.null_facts(c.a, true, out);
                        this.null_facts(c.b, true, out);
                        ->;
                    };
                    if (c.op == Operator.OR & !truth)
                    {
                        this.null_facts(c.a, false, out);
                        this.null_facts(c.b, false, out);
                    };
                };
                ->;
            };

            // on a branch where a pointer variable is null it owns no allocation
            narrow(LState* st, Node* cond, bool truth) -> void
            {
                PtrVec* names = pv_new();
                PtrVec* regs;
                int i, j;
                byte* r;
                this.null_facts(cond, truth, names);
                while (i < names.len)
                {
                    regs = (PtrVec*)om_get(st.env, (byte*)names.items[i]);
                    if (regs != (PtrVec*)0)
                    {
                        if (regs.len > 0)
                        {
                            j = 0;
                            while (j < regs.len)
                            {
                                r = (byte*)regs.items[j];
                                if (r[0] == 'H') { om_del(st.status, r); };
                                j++;
                            };
                            om_put(st.env, (byte*)names.items[i], (void*)lf_rs_new());
                        };
                    };
                    i++;
                };
                pv_free(names);
                ->;
            };

            // true or false for 'case (true)' / 'case (false)' of a boolean switch, else -1
            case_truth(Node* c) -> int
            {
                Node* v = c.a;
                if (v == (Node*)0) { return -1; };
                if (v.kind == NodeKind.LITERAL & v.op == DataType.BOOL)
                {
                    if (v.ival != 0) { return 1; };
                    return 0;
                };
                return -1;
            };

            do_if(Node* node, LState* st) -> void
            {
                PtrVec* outs = pv_new();
                LState* s1, rest, s, res;
                int c, i;
                this.eval(node.a, st);
                s1 = lf_state_copy(st);
                this.narrow(s1, node.a, true);
                this.block(node.b, s1, true);
                pv_push(outs, (void*)s1);
                rest = lf_state_copy(st);
                this.narrow(rest, node.a, false);
                c = bc_count(node, 0);
                i = 0;
                while (i < c)
                {
                    this.eval(node_child(node, 0, i), rest);
                    s = lf_state_copy(rest);
                    this.narrow(s, node_child(node, 0, i), true);
                    this.block(node_child(node, 1, i), s, true);
                    pv_push(outs, (void*)s);
                    this.narrow(rest, node_child(node, 0, i), false);
                    i++;
                };
                if (node.c != (Node*)0)
                {
                    s = lf_state_copy(rest);
                    this.block(node.c, s, true);
                    pv_push(outs, (void*)s);
                }
                else
                {
                    pv_push(outs, (void*)rest);
                };
                res = (LState*)0;
                i = 0;
                while (i < outs.len)
                {
                    res = lf_join(res, (LState*)outs.items[i]);
                    i++;
                };
                if (res != (LState*)0) { lf_state_set(st, res); };
                ->;
            };

            do_switch(Node* node, LState* st) -> void
            {
                PtrVec* outs = pv_new();
                bool has_default;
                int c = bc_count(node, 0);
                int i, tv, nseen, seen0, k;
                Node* cs, o;
                LState* s, res;
                this.eval(node.a, st);
                while (i < c)
                {
                    cs = node_child(node, 0, i);
                    if (cs.a == (Node*)0) { has_default = true; }
                    else { this.eval(cs.a, lf_state_copy(st)); };
                    s = lf_state_copy(st);
                    tv = this.case_truth(cs);
                    if ((tv < 0) & (cs.a == (Node*)0))
                    {
                        nseen = 0;
                        k = 0;
                        while (k < c)
                        {
                            o = node_child(node, 0, k);
                            if (o.a != (Node*)0)
                            {
                                nseen++;
                                seen0 = this.case_truth(o);
                            };
                            k++;
                        };
                        if ((nseen == 1) & (seen0 >= 0)) { tv = 1 - seen0; };
                    };
                    if (tv >= 0) { this.narrow(s, node.a, tv == 1); };
                    if (cs.b != (Node*)0)
                    {
                        if (cs.b.kind == NodeKind.BLOCK) { this.block(cs.b, s, true); }
                        else { this.stmt(cs.b, s, g"fn\0"); };
                    };
                    pv_push(outs, (void*)s);
                    i++;
                };
                if (!has_default) { pv_push(outs, (void*)lf_state_copy(st)); };
                res = (LState*)0;
                i = 0;
                while (i < outs.len)
                {
                    res = lf_join(res, (LState*)outs.items[i]);
                    i++;
                };
                if (res != (LState*)0) { lf_state_set(st, res); };
                ->;
            };

            loop(LState* st, Node* cond, Node* body, bool check_first, Node* update, bool once) -> void
            {
                LLoop* ctx = (LLoop*)fmalloc((u64)((sizeof(LLoop) + 7) / 8));
                LState* entry = lf_state_copy(st);
                LState* cur = entry;
                LState* s, nxt, out;
                LState* back = entry;
                int pass, i;
                LPat* pat;
                LRng* prev_iv;
                if (check_first & !once) { pat = this.loop_pattern(cond, body, update, st); };
                ctx
                {
                    .breaks = pv_new();
                    .conts = pv_new();
                };
                while (pass < 4)
                {
                    ctx
                    {
                        .breaks = pv_new();
                        .conts = pv_new();
                    };
                    pv_push(this.loops, (void*)ctx);
                    s = lf_state_copy(cur);
                    if (cond != (Node*)0 & check_first) { this.eval(cond, s); };
                    if (pat != (LPat*)0)
                    {
                        prev_iv = (LRng*)om_get(this.ivars, pat.name);
                        om_put(this.ivars, pat.name, (void*)lf_rng(pat.lo, pat.hi));
                    };
                    this.block(body, s, true);
                    if (pat != (LPat*)0)
                    {
                        if (prev_iv == (LRng*)0) { om_del(this.ivars, pat.name); }
                        else { om_put(this.ivars, pat.name, (void*)prev_iv); };
                    };
                    this.loops.len--;
                    back = s;
                    i = 0;
                    while (i < ctx.conts.len)
                    {
                        back = lf_join(back, (LState*)ctx.conts.items[i]);
                        i++;
                    };
                    if (update != (Node*)0)
                    {
                        if (!back.dead) { this.stmt(update, back, g"fn\0"); };
                    };
                    if (cond != (Node*)0 & !check_first)
                    {
                        if (!back.dead) { this.eval(cond, back); };
                    };
                    if (once) { nxt = entry; } else { nxt = lf_join(entry, back); };
                    if (lf_state_eq(nxt, cur)) { break; };
                    cur = nxt;
                    pass++;
                };
                if (once)
                {
                    out = back;
                }
                else
                {
                    if (check_first)
                    {
                        out = lf_state_copy(cur);
                        if (cond != (Node*)0) { this.eval(cond, out); };
                    }
                    else
                    {
                        if (!back.dead) { out = back; } else { out = cur; };
                    };
                };
                i = 0;
                while (i < ctx.breaks.len)
                {
                    out = lf_join(out, (LState*)ctx.breaks.items[i]);
                    i++;
                };
                if (pat != (LPat*)0) { om_del(out.terms, pat.name); };
                -> lf_state_set(st, out);
            };

            // ----- expressions -----

            load(PtrVec* cells, LState* st) -> PtrVec*
            {
                PtrVec* out = lf_rs_new();
                int i;
                byte* c;
                while (i < cells.len)
                {
                    c = (byte*)cells.items[i];
                    if (om_has(st.held, c))
                    {
                        out = lf_rs_union(out, (PtrVec*)om_get(st.held, c));
                    };
                    i++;
                };
                -> out;
            };

            // Cells an lvalue-like expression addresses, in cells_r, and the regions
            // dereferenced to reach them, in deref_r (empty when no pointer is followed).
            cells_of(Node* e, LState* st) -> void
            {
                LocInfo* info;
                PtrVec* vals, bc, dr, inner, loaded, out, v;
                Node* base;
                bool is_m;
                int i;
                if (e.kind == NodeKind.IDENTIFIER)
                {
                    info = lf_loc_get(this.locals, e.text);
                    if (info == (LocInfo*)0)
                    {
                        this.cells_r = lf_rs_one(lf_static(e.text));
                        this.deref_r = lf_rs_new();
                        ->;
                    };
                    if (info.kind == 1)
                    {
                        this.cells_r = lf_rs_one(info.reg);
                        this.deref_r = lf_rs_new();
                        ->;
                    };
                    vals = lf_env_get(st.env, e.text);
                    if (vals.len > 0)
                    {
                        this.cells_r = vals;
                        this.deref_r = vals;
                        ->;
                    };
                    this.cells_r = lf_rs_one(info.reg);
                    this.deref_r = lf_rs_new();
                    ->;
                };
                if (e.kind == NodeKind.MEMBER_ACCESS | e.kind == NodeKind.ARRAY_ACCESS)
                {
                    is_m = e.kind == NodeKind.MEMBER_ACCESS;
                    base = e.a;
                    if (!is_m) { this.eval(e.b, st); };
                    if (base.kind == NodeKind.IDENTIFIER)
                    {
                        this.cells_of(base, st);
                        bc = this.cells_r;
                        dr = this.deref_r;
                    }
                    else
                    {
                        this.cells_of(base, st);
                        inner = this.cells_r;
                        loaded = this.load(inner, st);
                        if (loaded.len > 0)
                        {
                            bc = loaded;
                            dr = loaded;
                        }
                        else
                        {
                            bc = inner;
                            dr = lf_rs_new();
                        };
                    };
                    if (is_m)
                    {
                        out = lf_rs_new();
                        i = 0;
                        while (i < bc.len)
                        {
                            lf_rs_add(out, lf_fld((byte*)bc.items[i], e.text));
                            i++;
                        };
                        this.cells_r = out;
                        this.deref_r = dr;
                        ->;
                    };
                    this.cells_r = bc;
                    this.deref_r = dr;
                    ->;
                };
                if (e.kind == NodeKind.POINTER_DEREF)
                {
                    v = this.eval(e.a, st);
                    this.cells_r = v;
                    this.deref_r = v;
                    ->;
                };
                v = this.eval(e, st);
                this.cells_r = v;
                this.deref_r = v;
                ->;
            };

            hint(Node* e) -> byte*
            {
                Node* x = e;
                while (true)
                {
                    if (x.kind == NodeKind.IDENTIFIER) { -> x.text; };
                    if (x.kind == NodeKind.POINTER_DEREF) { x = x.a; }
                    else
                    {
                        if (x.kind == NodeKind.MEMBER_ACCESS) { x = x.a; }
                        else
                        {
                            if (x.kind == NodeKind.ARRAY_ACCESS) { x = x.a; }
                            else
                            {
                                if (x.kind == NodeKind.CAST_EXPRESSION | x.kind == NodeKind.ADDRESS_OF) { x = x.a; }
                                else { -> g"<expr>\0"; };
                            };
                        };
                    };
                    if (x == (Node*)0) { -> g"<expr>\0"; };
                };
                -> g"<expr>\0";
            };

            deref_check(PtrVec* regs, Node* node, LState* st) -> void
            {
                byte* name = this.hint(node);
                PtrVec* hp = pv_new();
                bool allf;
                int i, fl;
                byte* r;
                int* wp;
                PtrVec* det;
                while (i < regs.len)
                {
                    r = (byte*)regs.items[i];
                    if (r[0] == 'H' | r[0] == 'P')
                    {
                        if (!om_has(this.multi, r)) { pv_push(hp, (void*)r); };
                    };
                    i++;
                };
                if (hp.len > 0)
                {
                    allf = true;
                    i = 0;
                    while (i < hp.len)
                    {
                        if ((lf_flags(st.status, (byte*)hp.items[i]) `& LF_F) == 0) { allf = false; };
                        i++;
                    };
                };
                i = 0;
                while (i < regs.len)
                {
                    r = (byte*)regs.items[i];
                    i++;
                    if (r[0] == 'H' | r[0] == 'P')
                    {
                        if (!allf) { continue; };
                        if (!lf_rs_has(hp, r)) { continue; };
                        fl = lf_flags(st.status, r);
                        if ((fl `& LF_F) != 0)
                        {
                            det = pv_new();
                            if (om_has(st.free_at, r))
                            {
                                wp = (int*)om_get(st.free_at, r);
                                this.sb.clear();
                                this.sb.put_str(g"ffree called at \0");
                                this.sb.put_str(this.where(wp[0]));
                                pv_push(det, (void*)this.take());
                            };
                            if ((fl `& 3) == LF_F)
                            {
                                this.sb.clear();
                                this.sb.put_str(f"pointer '{name}' used after its allocation site '{this.rdesc(r)}' was passed to ffree\0");
                                this.report(g"use_after_free\0", this.take(), this.cur_line, det);
                            }
                            else
                            {
                                this.sb.clear();
                                this.sb.put_str(f"pointer '{name}' used but its allocation site '{this.rdesc(r)}' may already have been passed to ffree\0");
                                this.report(g"maybe_use_after_free\0", this.take(), this.cur_line, det);
                            };
                        };
                        continue;
                    };
                    if (r[0] == 'S')
                    {
                        if (!lf_active_has(st.active, lf_seg(r, 3)))
                        {
                            this.sb.clear();
                            this.sb.put_str(f"pointer '{name}' used after its stack allocation '{this.rdesc(r)}' went out of scope\0");
                            this.report(g"use_after_scope\0", this.take(), this.cur_line, (PtrVec*)0);
                        };
                        continue;
                    };
                    if (r[0] == 'D')
                    {
                        this.sb.clear();
                        this.sb.put_str(f"pointer '{name}' used after the stack allocation '{this.rdesc(r)}' it points to was returned from a callee\0");
                        this.report(g"use_after_scope\0", this.take(), this.cur_line, (PtrVec*)0);
                    };
                };
                ->;
            };

            eval(Node* e, LState* st) -> PtrVec*
            {
                int k;
                LocInfo* info;
                PtrVec* l, r, cells, dr;
                if (e == (Node*)0) { -> lf_rs_new(); };
                k = e.kind;
                if (e.line != 0) { this.cur_line = e.line; };

                if (k == NodeKind.LITERAL | k == NodeKind.STRING_LITERAL) { -> lf_rs_new(); };
                if (k == NodeKind.ASSIGNMENT)
                {
                    this.assign(e.a, e.b, st);
                    if (e.a.kind == NodeKind.IDENTIFIER) { -> this.eval(e.a, st); };
                    -> lf_rs_new();
                };
                if (k == NodeKind.COMPOUND_ASSIGNMENT)
                {
                    this.compound(e, st);
                    -> lf_rs_new();
                };
                if (k == NodeKind.IDENTIFIER)
                {
                    this.join_result(e.text, st);
                    info = lf_loc_get(this.locals, e.text);
                    if (info == (LocInfo*)0)
                    {
                        this.access(lf_rs_one(lf_static(e.text)), LA_R, st, false, (byte*)0, (LRng*)0);
                        -> this.load(lf_rs_one(lf_static(e.text)), st);
                    };
                    if (info.kind == 1) { -> lf_rs_one(info.reg); };
                    this.access(lf_rs_one(info.reg), LA_R, st, false, (byte*)0, (LRng*)0);
                    -> lf_env_get(st.env, e.text);
                };
                if (k == NodeKind.ADDRESS_OF) { -> this.addr_of(e.a, st); };
                if (k == NodeKind.POINTER_DEREF | k == NodeKind.ARRAY_ACCESS | k == NodeKind.MEMBER_ACCESS)
                {
                    this.cells_of(e, st);
                    cells = this.cells_r;
                    dr = this.deref_r;
                    if (dr.len > 0)
                    {
                        this.deref_check(dr, e, st);
                        this.alias_check(e, dr, st, false);
                    };
                    this.access(this.roots_of(cells), LA_R, st, false, (byte*)0, this.acc_range(e, st));
                    -> this.load(cells, st);
                };
                if (k == NodeKind.CAST_EXPRESSION)
                {
                    if (e.a != (Node*)0 & e.ts != (TypeSpec*)0)
                    {
                        if (e.a.kind == NodeKind.TIE_EXPRESSION & e.ts.base_type == DataType.VOID & !bc_is_pointer_type(e.ts))
                        {
                            // (void)~x releases the tied value
                            this.do_free(this.eval(e.a, st), st, true);
                            -> lf_rs_new();
                        };
                        if (e.a.kind == NodeKind.IDENTIFIER & e.ts.base_type == DataType.VOID & !bc_is_pointer_type(e.ts))
                        {
                            if (om_has(this.heapvars, e.a.text) | om_has(this.al.ptr_vars, e.a.text))
                            {
                                // (void)p on a heap variable or a pointer variable releases what it points to
                                this.do_free(this.eval(e.a, st), st, true);
                                -> lf_rs_new();
                            };
                        };
                    };
                    -> this.eval(e.a, st);
                };
                if (k == NodeKind.BINARY_OP)
                {
                    l = this.eval(e.a, st);
                    r = this.eval(e.b, st);
                    if (e.op == Operator.EQUAL | e.op == Operator.NOT_EQUAL | e.op == Operator.LESS_THAN
                        | e.op == Operator.LESS_EQUAL | e.op == Operator.GREATER_THAN
                        | e.op == Operator.GREATER_EQUAL | e.op == Operator.AND | e.op == Operator.OR
                        | e.op == Operator.NAND | e.op == Operator.NOR | e.op == Operator.XOR
                        | e.op == Operator.NOT)
                    {
                        -> lf_rs_new();
                    };
                    -> lf_rs_union(l, r);
                };
                if (k == NodeKind.UNARY_OP)
                {
                    if (e.op == Operator.INCREMENT | e.op == Operator.DECREMENT)
                    {
                        if (e.a.kind == NodeKind.POINTER_DEREF | e.a.kind == NodeKind.ARRAY_ACCESS | e.a.kind == NodeKind.MEMBER_ACCESS)
                        {
                            this.cells_of(e.a, st);
                            cells = this.cells_r;
                            dr = this.deref_r;
                            if (dr.len > 0)
                            {
                                this.deref_check(dr, e.a, st);
                                this.alias_check(e.a, dr, st, true);
                            };
                            this.access(this.roots_of(cells), LA_R `| LA_W, st, false, (byte*)0, this.acc_range(e.a, st));
                            -> this.load(cells, st);
                        };
                    };
                    l = this.eval(e.a, st);
                    if (e.op == Operator.INCREMENT | e.op == Operator.DECREMENT)
                    {
                        if (e.a.kind == NodeKind.IDENTIFIER) { om_del(st.terms, e.a.text); };
                    };
                    if (e.op == Operator.NOT) { -> lf_rs_new(); };
                    -> l;
                };
                if (k == NodeKind.TIE_EXPRESSION) { -> this.tie(e, st); };
                if (k == NodeKind.TYPE_CONVERT_EXPRESSION) { -> this.eval(e.a, st); };
                if (k == NodeKind.NULL_COALESCE)
                {
                    l = this.eval(e.a, st);
                    r = this.eval(e.b, st);
                    -> lf_rs_union(l, r);
                };
                if (k == NodeKind.NOT_NULL)
                {
                    this.eval(e.a, st);
                    -> lf_rs_new();
                };
                if (k == NodeKind.TERNARY_OP)
                {
                    this.eval(e.a, st);
                    l = this.eval(e.b, st);
                    r = this.eval(e.c, st);
                    -> lf_rs_union(l, r);
                };
                if (k == NodeKind.IF_EXPRESSION)
                {
                    this.eval(e.b, st);
                    l = this.eval(e.a, st);
                    if (e.c != (Node*)0) { l = lf_rs_union(l, this.eval(e.c, st)); };
                    -> l;
                };
                if (k == NodeKind.FUNCTION_CALL) { -> this.call(e, st); };
                if (k == NodeKind.METHOD_CALL) { -> this.method(e, st); };
                // generic expression: evaluate children for their effects
                this.generic_expr(e, st);
                -> lf_rs_new();
            };

            generic_expr(Node* e, LState* st) -> void
            {
                int s, c, i;
                if (e.a != (Node*)0) { this.eval(e.a, st); };
                if (e.b != (Node*)0) { this.eval(e.b, st); };
                if (e.c != (Node*)0) { this.eval(e.c, st); };
                if (e.d != (Node*)0) { this.eval(e.d, st); };
                while (s < 6)
                {
                    c = bc_count(e, s);
                    i = 0;
                    while (i < c)
                    {
                        this.eval(node_child(e, s, i), st);
                        i++;
                    };
                    s++;
                };
                ->;
            };

            addr_of(Node* e, LState* st) -> PtrVec*
            {
                LocInfo* info;
                PtrVec* out, cells;
                int i;
                if (e.kind == NodeKind.IDENTIFIER)
                {
                    info = lf_loc_get(this.locals, e.text);
                    if (info == (LocInfo*)0) { -> lf_rs_one(lf_static(e.text)); };
                    -> lf_rs_one(info.reg);
                };
                if (e.kind == NodeKind.MEMBER_ACCESS | e.kind == NodeKind.ARRAY_ACCESS)
                {
                    this.cells_of(e, st);
                    cells = this.cells_r;
                    out = lf_rs_new();
                    i = 0;
                    while (i < cells.len)
                    {
                        lf_rs_add(out, lf_root((byte*)cells.items[i]));
                        i++;
                    };
                    -> out;
                };
                if (e.kind == NodeKind.POINTER_DEREF) { -> this.eval(e.a, st); };
                -> this.eval(e, st);
            };

            // ----- many readers or one writer -----

            may_carry_pointer(TypeSpec* ts) -> bool
            {
                int bt;
                if (ts == (TypeSpec*)0) { -> false; };
                if (bc_is_pointer_type(ts)) { -> true; };
                if ((ts.flags `& TS_ARRAY) != 0) { -> false; };
                if (ts.custom_typename != (byte*)0)
                {
                    if (ts.custom_typename[0] != 0) { -> false; };
                };
                bt = ts.base_type;
                if (bt == DataType.FLOAT | bt == DataType.DOUBLE | bt == DataType.STRUCT | bt == DataType.UNION
                    | bt == DataType.OBJECT | bt == DataType.ENUM | bt == DataType.VOID | bt == DataType.FUNC_PTR
                    | bt == DataType.DICT | bt == DataType.THIS | bt == DataType.BOOL)
                {
                    -> false;
                };
                -> true;
            };

            // ~x moves the value out of x: x holds null afterwards
            tie(Node* e, LState* st) -> PtrVec*
            {
                Node* op = e.a;
                LocInfo* info;
                PtrVec* v;
                if (op.kind != NodeKind.IDENTIFIER) { -> this.eval(op, st); };
                info = lf_loc_get(this.locals, op.text);
                v = this.eval(op, st);
                if (info != (LocInfo*)0)
                {
                    if (info.kind == 1) { -> v; };
                };
                om_put(st.env, op.text, (void*)lf_rs_new());
                if (info != (LocInfo*)0)
                {
                    // a tied struct carries its contents with it
                    this.mark_esc(this.load(lf_rs_one(info.reg), st), st);
                };
                -> v;
            };

            root_ident(Node* e) -> Node*
            {
                Node* x = e;
                while (x != (Node*)0)
                {
                    if (x.kind == NodeKind.IDENTIFIER) { -> x; };
                    if (x.kind == NodeKind.POINTER_DEREF | x.kind == NodeKind.ARRAY_ACCESS
                        | x.kind == NodeKind.MEMBER_ACCESS | x.kind == NodeKind.CAST_EXPRESSION)
                    {
                        x = x.a;
                    }
                    else { -> (Node*)0; };
                };
                -> (Node*)0;
            };

            arg_ident(Node* a) -> Node*
            {
                Node* x = a;
                while (x != (Node*)0)
                {
                    if (x.kind == NodeKind.IDENTIFIER) { -> x; };
                    if (x.kind == NodeKind.CAST_EXPRESSION | x.kind == NodeKind.ADDRESS_OF) { x = x.a; }
                    else { -> (Node*)0; };
                };
                -> (Node*)0;
            };

            rhs_vars(Node* n, byte* exclude, OMap* out) -> void
            {
                int s, c, i;
                if (n == (Node*)0) { ->; };
                if (n.kind == NodeKind.IDENTIFIER)
                {
                    if (!cstr_eq(n.text, exclude))
                    {
                        if (lf_loc_get(this.locals, n.text) != (LocInfo*)0) { om_put(out, n.text, (void*)1); };
                    };
                    ->;
                };
                this.rhs_vars(n.a, exclude, out);
                this.rhs_vars(n.b, exclude, out);
                this.rhs_vars(n.c, exclude, out);
                this.rhs_vars(n.d, exclude, out);
                while (s < 6)
                {
                    c = bc_count(n, s);
                    i = 0;
                    while (i < c)
                    {
                        this.rhs_vars(node_child(n, s, i), exclude, out);
                        i++;
                    };
                    s++;
                };
                ->;
            };

            add_deriv(byte* name, Node* rhs) -> void
            {
                OMap* cur = (OMap*)om_get(this.al.deriv, name);
                int i;
                OMap* tmp = om_new();
                if (cur == (OMap*)0)
                {
                    cur = om_new();
                    om_put(this.al.deriv, name, (void*)cur);
                };
                this.rhs_vars(rhs, name, tmp);
                while (i < tmp.ks.len)
                {
                    om_put(cur, (byte*)tmp.ks.items[i], (void*)1);
                    i++;
                };
                ->;
            };

            uses_add(OMap* m, byte* name, LPos* p) -> void
            {
                PtrVec* v = (PtrVec*)om_get(m, name);
                if (v == (PtrVec*)0)
                {
                    v = pv_new();
                    om_put(m, name, (void*)v);
                };
                -> pv_push(v, (void*)p);
            };

            note_writer(Node* target) -> void
            {
                Node* r = this.root_ident(target);
                if (r != (Node*)0) { om_put(this.al.writers, r.text, (void*)1); };
                ->;
            };

            ix_walk(Node* n, PtrVec* path, PtrVec* loops) -> void
            {
                int k, s, c, i;
                byte* nk;
                LPos* p;
                PtrVec* p2, l2;
                if (n == (Node*)0) { ->; };
                k = n.kind;
                if (k == NodeKind.FUNCTION_DEF) { ->; };
                if (k == NodeKind.IDENTIFIER)
                {
                    p = lf_pos_new(this.al.seq, path, loops);
                    this.al.seq++;
                    om_put(this.al.ix, lf_addr_key((void*)n), (void*)p);
                    -> this.uses_add(this.al.uses, n.text, p);
                };
                if (k == NodeKind.IF_STATEMENT)
                {
                    nk = lf_addr_key((void*)n);
                    this.ix_walk(n.a, path, loops);
                    this.ix_walk(n.b, lf_pv_add(path, lf_pe(nk, 0)), loops);
                    c = bc_count(n, 0);
                    i = 0;
                    while (i < c)
                    {
                        p2 = lf_pv_add(path, lf_pe(nk, i + 1));
                        this.ix_walk(node_child(n, 0, i), p2, loops);
                        this.ix_walk(node_child(n, 1, i), p2, loops);
                        i++;
                    };
                    if (n.c != (Node*)0) { this.ix_walk(n.c, lf_pv_add(path, lf_pe(nk, c + 1)), loops); };
                    ->;
                };
                if (k == NodeKind.SWITCH_STATEMENT)
                {
                    nk = lf_addr_key((void*)n);
                    this.ix_walk(n.a, path, loops);
                    c = bc_count(n, 0);
                    i = 0;
                    while (i < c)
                    {
                        this.ix_walk(node_child(n, 0, i).a, path, loops);
                        this.ix_walk(node_child(n, 0, i).b, lf_pv_add(path, lf_pe(nk, i)), loops);
                        i++;
                    };
                    ->;
                };
                if (k == NodeKind.WHILE_LOOP | k == NodeKind.DO_WHILE_LOOP | k == NodeKind.DO_LOOP
                    | k == NodeKind.FOR_LOOP | k == NodeKind.FOR_IN_LOOP)
                {
                    nk = lf_addr_key((void*)n);
                    if (k == NodeKind.FOR_LOOP) { this.ix_walk(n.a, path, loops); };
                    if (k == NodeKind.FOR_IN_LOOP) { this.ix_walk(n.a, path, loops); };
                    om_put(this.al.loop_start, nk, (void*)bx_new(this.al.seq));
                    l2 = lf_pv_add(loops, nk);
                    if (k == NodeKind.FOR_LOOP)
                    {
                        this.ix_walk(n.b, path, l2);
                        this.ix_walk(n.d, path, l2);
                        this.ix_walk(n.c, path, l2);
                    };
                    if (k == NodeKind.FOR_IN_LOOP) { this.ix_walk(n.b, path, l2); };
                    if (k == NodeKind.WHILE_LOOP)
                    {
                        this.ix_walk(n.a, path, l2);
                        this.ix_walk(n.b, path, l2);
                    };
                    if (k == NodeKind.DO_WHILE_LOOP)
                    {
                        this.ix_walk(n.a, path, l2);
                        this.ix_walk(n.b, path, l2);
                    };
                    if (k == NodeKind.DO_LOOP) { this.ix_walk(n.b, path, l2); };
                    -> om_put(this.al.loop_end, nk, (void*)bx_new(this.al.seq));
                };
                if (k == NodeKind.ASSIGNMENT)
                {
                    this.ix_walk(n.b, path, loops);
                    if (n.a.kind == NodeKind.IDENTIFIER)
                    {
                        this.uses_add(this.al.defs, n.a.text, lf_pos_new(this.al.seq, path, loops));
                        this.al.seq++;
                        ->;
                    };
                    this.ix_walk(n.a, path, loops);
                    -> this.note_writer(n.a);
                };
                if (k == NodeKind.COMPOUND_ASSIGNMENT)
                {
                    this.ix_walk(n.b, path, loops);
                    this.ix_walk(n.a, path, loops);
                    if (n.a.kind != NodeKind.IDENTIFIER) { this.note_writer(n.a); };
                    ->;
                };
                if (k == NodeKind.UNARY_OP)
                {
                    if (n.op == Operator.INCREMENT | n.op == Operator.DECREMENT)
                    {
                        this.ix_walk(n.a, path, loops);
                        if (n.a.kind != NodeKind.IDENTIFIER) { this.note_writer(n.a); };
                        ->;
                    };
                };
                if (k == NodeKind.VARIABLE_DECLARATION)
                {
                    this.ix_walk(n.a, path, loops);
                    om_put(this.al.first, n.text, (void*)bx_new(this.al.seq));
                    this.uses_add(this.al.defs, n.text, lf_pos_new(this.al.seq, path, loops));
                    this.al.seq++;
                    ->;
                };
                this.ix_walk(n.a, path, loops);
                this.ix_walk(n.b, path, loops);
                this.ix_walk(n.c, path, loops);
                this.ix_walk(n.d, path, loops);
                s = 0;
                while (s < 6)
                {
                    c = bc_count(n, s);
                    i = 0;
                    while (i < c)
                    {
                        this.ix_walk(node_child(n, s, i), path, loops);
                        i++;
                    };
                    s++;
                };
                ->;
            };

            index_function(Node* func) -> void
            {
                -> this.ix_walk(func.a, pv_new(), pv_new());
            };

            // will the value the variable holds at pos be used again?
            live_after(byte* name, LPos* pos) -> bool
            {
                PtrVec* defs = (PtrVec*)om_get(this.al.defs, name);
                PtrVec* uses = (PtrVec*)om_get(this.al.uses, name);
                int ui, di, li, first, lstart, lend;
                LPos* u, d;
                bool killed, k1, k2;
                byte* L;
                if (uses == (PtrVec*)0) { -> false; };
                if (defs == (PtrVec*)0) { defs = pv_new(); };
                while (ui < uses.len)
                {
                    u = (LPos*)uses.items[ui];
                    ui++;
                    if (u.seq > pos.seq & !lf_exclusive(u.path, pos.path))
                    {
                        killed = false;
                        di = 0;
                        while (di < defs.len)
                        {
                            d = (LPos*)defs.items[di];
                            di++;
                            if (d.seq > pos.seq & lf_prefix(d.path, pos.path) & d.seq < u.seq & lf_prefix(d.path, u.path))
                            {
                                killed = true;
                            };
                        };
                        if (!killed) { -> true; };
                    };
                    li = 0;
                    while (li < u.loops.len)
                    {
                        L = (byte*)u.loops.items[li];
                        li++;
                        if (!lf_pv_has(pos.loops, L)) { continue; };
                        first = lf_int_get(this.al.first, name, -1);
                        lstart = lf_int_get(this.al.loop_start, L, 0);
                        if (first >= lstart) { continue; };
                        lend = lf_int_get(this.al.loop_end, L, 1073741824);
                        k1 = false;
                        k2 = false;
                        di = 0;
                        while (di < defs.len)
                        {
                            d = (LPos*)defs.items[di];
                            di++;
                            if (d.seq > pos.seq & lf_prefix(d.path, pos.path) & lf_pv_has(d.loops, L) & d.seq < lend)
                            {
                                k1 = true;
                            };
                            if (lstart <= d.seq & d.seq < u.seq & lf_prefix(d.path, u.path) & lf_pv_has(d.loops, L))
                            {
                                k2 = true;
                            };
                        };
                        if (k1 | k2) { continue; };
                        -> true;
                    };
                };
                -> false;
            };

            ancestors(byte* name) -> OMap*
            {
                OMap* seen = om_new();
                PtrVec* todo = pv_new();
                byte* x;
                OMap* ds;
                int i;
                pv_push(todo, (void*)name);
                while (todo.len > 0)
                {
                    x = (byte*)todo.items[todo.len - 1];
                    todo.len--;
                    ds = (OMap*)om_get(this.al.deriv, x);
                    if (ds != (OMap*)0)
                    {
                        i = 0;
                        while (i < ds.ks.len)
                        {
                            if (!om_has(seen, (byte*)ds.ks.items[i]))
                            {
                                om_put(seen, (byte*)ds.ks.items[i], (void*)1);
                                pv_push(todo, ds.ks.items[i]);
                            };
                            i++;
                        };
                    };
                };
                -> seen;
            };

            note_write(PtrVec* dr) -> void
            {
                int i;
                byte* r;
                while (i < dr.len)
                {
                    r = (byte*)dr.items[i];
                    if (r[0] == 'P')
                    {
                        if (cstr_eq(lf_seg(r, 1), this.fn)) { om_put(this.al.wr_params, lf_seg(r, 2), (void*)1); };
                    };
                    i++;
                };
                ->;
            };

            // the allocation named in a message: the smallest description
            pick_site(PtrVec* both) -> byte*
            {
                int i = 1;
                byte* best = this.rdesc((byte*)both.items[0]);
                byte* d;
                while (i < both.len)
                {
                    d = this.rdesc((byte*)both.items[i]);
                    if (bc_str_lt(d, best)) { best = d; };
                    i++;
                };
                -> best;
            };

            alias_check(Node* e, PtrVec* dr, LState* st, bool is_write) -> void
            {
                Node* rn;
                byte* p;
                LPos* pos;
                if (is_write) { this.note_write(dr); };
                rn = this.root_ident(e);
                if (rn == (Node*)0) { ->; };
                p = rn.text;
                if (!om_has(this.al.ptr_vars, p)) { ->; };
                if (!lf_rs_eq(dr, lf_env_get(st.env, p))) { ->; };
                pos = (LPos*)om_get(this.al.ix, lf_addr_key((void*)rn));
                if (pos == (LPos*)0) { ->; };
                -> this.alias_vs_live(p, pos, dr, is_write, st, (OMap*)0);
            };

            alias_vs_live(byte* p, LPos* pos, PtrVec* regs, bool is_write, LState* st, OMap* skip) -> void
            {
                OMap* anc = this.ancestors(p);
                int i;
                byte* y, site;
                PtrVec* yregs, both, d;
                int n = st.env.ks.len;
                byte* msg;
                while (i < n)
                {
                    y = (byte*)st.env.ks.items[i];
                    yregs = (PtrVec*)st.env.vs.items[i];
                    i++;
                    if (cstr_eq(y, p)) { continue; };
                    if (skip != (OMap*)0)
                    {
                        if (om_has(skip, y)) { continue; };
                    };
                    if (!om_has(this.al.ptr_vars, y)) { continue; };
                    if (yregs.len == 0) { continue; };
                    both = lf_rs_inter(regs, yregs);
                    if (both.len == 0) { continue; };
                    if (om_has(anc, y)) { continue; };
                    if (!this.live_after(y, pos)) { continue; };
                    if (!(is_write | om_has(this.al.writers, y) | om_has(this.al.writers, p))) { continue; };
                    site = this.pick_site(both);
                    this.sb.clear();
                    this.sb.put_str(f"pointer '{p}' is \0");
                    if (is_write) { this.sb.put_str(g"written\0"); } else { this.sb.put_str(g"read\0"); };
                    this.sb.put_str(f" through while pointer '{y}' to the same allocation '{site}' is still live (many readers or one writer)\0");
                    d = pv_new();
                    this.sb.clear();
                    this.sb.put_str(f"pointer '{p}' is \0");
                    if (is_write) { this.sb.put_str(g"written\0"); } else { this.sb.put_str(g"read\0"); };
                    this.sb.put_str(f" through while pointer '{y}' to the same allocation '{site}' is still live (many readers or one writer)\0");
                    {
                        msg = this.take();
                        this.sb.clear();
                        this.sb.put_str(f"'{p}' accessed at {this.where(this.cur_line)}\0");
                        pv_push(d, (void*)this.take());
                        this.sb.clear();
                        this.sb.put_str(f"'{y}' is used again after this point\0");
                        pv_push(d, (void*)this.take());
                        this.report(g"mutable_alias\0", msg, this.cur_line, d);
                    };
                };
                ->;
            };

            // arguments that overlap while the callee may write through one
            check_call_alias(Node* call, PtrVec* arg_regs, OMap* wr, LState* st) -> void
            {
                int n = arg_regs.len;
                PtrVec* roots = pv_new();
                OMap* names = om_new();
                int i, j;
                Node* r, a;
                PtrVec* both, d;
                bool wi, wj;
                byte* site;
                LPos* pos;
                while (i < n)
                {
                    r = this.arg_ident(node_child(call, 0, i));
                    pv_push(roots, (void*)r);
                    if (r != (Node*)0) { om_put(names, r.text, (void*)1); };
                    i++;
                };
                i = 0;
                byte* msg2;
                while (i < n)
                {
                    j = i + 1;
                    while (j < n)
                    {
                        if ((Node*)roots.items[i] != (Node*)0 & (Node*)roots.items[j] != (Node*)0)
                        {
                            both = lf_rs_inter((PtrVec*)arg_regs.items[i], (PtrVec*)arg_regs.items[j]);
                            if (both.len > 0)
                            {
                                wi = true;
                                wj = true;
                                if (wr != (OMap*)0)
                                {
                                    wi = om_has(wr, lf_itoa(i));
                                    wj = om_has(wr, lf_itoa(j));
                                };
                                if (wi | wj)
                                {
                                    site = this.pick_site(both);
                                    this.sb.clear();
                                    this.sb.put_str(g"arguments '\0");
                                    this.sb.put_str(((Node*)roots.items[i]).text);
                                    this.sb.put_str(g"' and '\0");
                                    this.sb.put_str(((Node*)roots.items[j]).text);
                                    this.sb.put_str(f"' alias the same allocation '{site}' and the callee may write through one of them (many readers or one writer)\0");
                                    {
                                        msg2 = this.take();
                                        d = this.det1(g"call at \0", this.where(this.cur_line));
                                        this.report(g"mutable_alias\0", msg2, this.cur_line, d);
                                    };
                                };
                            };
                        };
                        j++;
                    };
                    i++;
                };
                i = 0;
                while (i < n)
                {
                    r = (Node*)roots.items[i];
                    a = node_child(call, 0, i);
                    i++;
                    if (r == (Node*)0) { continue; };
                    if (a.kind == NodeKind.ADDRESS_OF) { continue; };
                    if (!om_has(this.al.ptr_vars, r.text)) { continue; };
                    if (((PtrVec*)arg_regs.items[i - 1]).len == 0) { continue; };
                    if (!lf_rs_eq((PtrVec*)arg_regs.items[i - 1], lf_env_get(st.env, r.text))) { continue; };
                    pos = (LPos*)om_get(this.al.ix, lf_addr_key((void*)r));
                    if (pos == (LPos*)0) { continue; };
                    wi = true;
                    if (wr != (OMap*)0) { wi = om_has(wr, lf_itoa(i - 1)); };
                    this.alias_vs_live(r.text, pos, (PtrVec*)arg_regs.items[i - 1], wi, st, names);
                };
                ->;
            };

            // ----- calls -----

            call(Node* e, LState* st) -> PtrVec*
            {
                byte* name = e.text;
                int n = bc_count(e, 0);
                int i;
                byte* base, site, resolved;
                PtrVec* v, old, arg_regs;
                LSumm* summ;
                if (name != (byte*)0)
                {
                    if (name[0] == 0) { name = (byte*)0; };
                };
                if (name == (byte*)0)
                {
                    if (e.a != (Node*)0) { this.eval(e.a, st); };
                };
                base = g"\0";
                if (name != (byte*)0) { base = bc_last_seg(name); };

                if (cstr_eq(base, g"frealloc\0") & n >= 1)
                {
                    old = this.eval(node_child(e, 0, 0), st);
                    i = 1;
                    while (i < n) { this.eval(node_child(e, 0, i), st); i++; };
                    this.mark_esc(old, st);
                    site = lf_heap(this.fn, this.cur_line, (byte*)0);
                    om_put(st.status, site, (void*)bx_new(LF_O));
                    om_del(st.esc, site);
                    om_del(st.free_at, site);
                    -> lf_rs_one(site);
                };
                if (cstr_eq(base, g"fmalloc\0") | cstr_eq(base, g"fcalloc\0"))
                {
                    i = 0;
                    while (i < n) { this.eval(node_child(e, 0, i), st); i++; };
                    site = lf_heap(this.fn, this.cur_line, (byte*)0);
                    om_put(st.status, site, (void*)bx_new(LF_O));
                    om_del(st.esc, site);
                    om_del(st.free_at, site);
                    -> lf_rs_one(site);
                };
                if (cstr_eq(base, g"ffree\0") & n == 1)
                {
                    v = this.eval(node_child(e, 0, 0), st);
                    this.do_free(v, st, true);
                    -> lf_rs_new();
                };

                arg_regs = pv_new();
                i = 0;
                while (i < n)
                {
                    pv_push(arg_regs, (void*)this.eval(node_child(e, 0, i), st));
                    i++;
                };
                resolved = (byte*)0;
                if (name != (byte*)0) { resolved = this.resolve(name, n); };
                if (resolved == (byte*)0)
                {
                    this.check_call_alias(e, arg_regs, (OMap*)0, st);
                    i = 0;
                    while (i < arg_regs.len) { this.mark_esc((PtrVec*)arg_regs.items[i], st); i++; };
                    -> lf_rs_new();
                };
                summ = this.summary(resolved);
                this.check_call_alias(e, arg_regs, summ.wr, st);
                -> this.call_resolved(e, resolved, summ, arg_regs, st);
            };

            method(Node* e, LState* st) -> PtrVec*
            {
                PtrVec* obj = this.eval(e.a, st);
                int n = bc_count(e, 0);
                int i;
                PtrVec* regs = pv_new();
                while (i < n)
                {
                    pv_push(regs, (void*)this.eval(node_child(e, 0, i), st));
                    i++;
                };
                this.mark_esc(obj, st);
                i = 0;
                while (i < regs.len) { this.mark_esc((PtrVec*)regs.items[i], st); i++; };
                -> lf_rs_new();
            };

            do_free(PtrVec* regs, LState* st, bool definite) -> void
            {
                bool single = regs.len == 1;
                PtrVec* hp = pv_new();
                bool allf, has_stat;
                int i, stat;
                byte* r;
                int* wp;
                PtrVec* det;
                while (i < regs.len)
                {
                    r = (byte*)regs.items[i];
                    if (r[0] == 'H' | r[0] == 'P')
                    {
                        if (!om_has(this.multi, r)) { pv_push(hp, (void*)r); };
                    };
                    i++;
                };
                if (hp.len > 0)
                {
                    allf = true;
                    i = 0;
                    while (i < hp.len)
                    {
                        if ((lf_flags(st.status, (byte*)hp.items[i]) `& LF_F) == 0) { allf = false; };
                        i++;
                    };
                };
                i = 0;
                {
                    PtrVec* fr = pv_new();
                    while (i < regs.len)
                    {
                        r = (byte*)regs.items[i];
                        if (r[0] == 'H' | r[0] == 'P') { pv_push(fr, (void*)r); };
                        i++;
                    };
                    this.access(this.roots_of(fr), LA_F, st, false, (byte*)0, (LRng*)0);
                };
                i = 0;
                while (i < regs.len)
                {
                    r = (byte*)regs.items[i];
                    i++;
                    if (r[0] == 'H' | r[0] == 'P')
                    {
                        if (om_has(this.multi, r)) { continue; };
                        has_stat = om_has(st.status, r);
                        stat = lf_flags(st.status, r);
                        if (r[0] == 'P' & !has_stat) { stat = LF_O; has_stat = true; };
                        if (has_stat & (stat `& LF_F) != 0 & allf)
                        {
                            det = pv_new();
                            if (om_has(st.free_at, r))
                            {
                                wp = (int*)om_get(st.free_at, r);
                                this.sb.clear();
                                this.sb.put_str(g"first ffree at \0");
                                this.sb.put_str(this.where(wp[0]));
                                pv_push(det, (void*)this.take());
                            };
                            this.sb.clear();
                            this.sb.put_str(f"allocation site '{this.rdesc(r)}' passed to ffree again\0");
                            if ((stat `& 3) != LF_F) { this.sb.put_str(g" (it may already have been freed)\0"); };
                            this.report(g"double_free\0", this.take(), this.cur_line, det);
                        };
                        if (definite & single) { om_put(st.status, r, (void*)bx_new(LF_F)); }
                        else
                        {
                            if (single) { om_put(st.status, r, (void*)bx_new(stat `| LF_F)); }
                            else
                            {
                                // freed through a pointer that may point elsewhere: it may be
                                // freed, which neither proves nor excludes a later free or use
                                om_put(st.status, r, (void*)bx_new(stat `| LF_W));
                                continue;
                            };
                        };
                        om_put(st.free_at, r, (void*)bx_new(this.cur_line));
                        continue;
                    };
                    if (r[0] == 'S' | r[0] == 'D')
                    {
                        this.sb.clear();
                        this.sb.put_str(f"ffree called on stack address '{this.rdesc(r)}'\0");
                        this.report(g"invalid_free\0", this.take(), this.cur_line, (PtrVec*)0);
                        continue;
                    };
                    if (r[0] == 'G')
                    {
                        this.sb.clear();
                        this.sb.put_str(f"ffree called on static address '{lf_seg(r, 1)}'\0");
                        this.report(g"invalid_free\0", this.take(), this.cur_line, (PtrVec*)0);
                    };
                };
                ->;
            };

            // callee region to caller regions
            map_region(byte* r, byte* fname, LSumm* sm, PtrVec* arg_regs, int call_line, OMap* cache, LState* st) -> PtrVec*
            {
                PtrVec* out;
                byte* ns;
                int idx;
                if (om_has(cache, r)) { -> (PtrVec*)om_get(cache, r); };
                if (r[0] == 'P')
                {
                    idx = lf_atoi(lf_seg(r, 2));
                    out = lf_rs_new();
                    if (idx < arg_regs.len & cstr_eq(lf_seg(r, 1), fname))
                    {
                        out = (PtrVec*)arg_regs.items[idx];
                    };
                }
                else
                {
                    if (r[0] == 'H')
                    {
                        ns = lf_heap_c(this.fn, call_line, this.call_col, r);
                        // key text of a mapped site is H|func|line|<inner>
                        if (om_has(sm.heap_status, r))
                        {
                            om_put(st.status, ns, om_get(sm.heap_status, r));
                            if (om_has(sm.esc, r)) { om_put(st.esc, ns, (void*)1); };
                            if (om_has(sm.free_at, r)) { om_put(st.free_at, ns, om_get(sm.free_at, r)); };
                        };
                        out = lf_rs_one(ns);
                    }
                    else
                    {
                        if (r[0] == 'S')
                        {
                            out = lf_rs_one(lf_dangling(lf_seg(r, 1), lf_seg(r, 2)));
                        }
                        else
                        {
                            out = lf_rs_one(r);
                        };
                    };
                };
                om_put(cache, r, (void*)out);
                -> out;
            };

            map_set(PtrVec* s, byte* fname, LSumm* sm, PtrVec* arg_regs, int call_line, OMap* cache, LState* st) -> PtrVec*
            {
                PtrVec* o = lf_rs_new();
                int i;
                while (i < s.len)
                {
                    o = lf_rs_union(o, this.map_region((byte*)s.items[i], fname, sm, arg_regs, call_line, cache, st));
                    i++;
                };
                -> o;
            };

            apply(byte* fname, PtrVec* arg_regs, LState* st) -> PtrVec*
            {
                LSumm* sm = this.summary(fname);
                int call_line = this.cur_line;
                OMap* cache = om_new();
                int i, j, fl, q;
                LHeld* lh;
                PtrVec* mapped, regs;
                byte* c, key;
                while (i < sm.wr.ks.len)
                {
                    key = (byte*)sm.wr.ks.items[i];
                    if (lf_atoi(key) < arg_regs.len) { this.note_write((PtrVec*)arg_regs.items[lf_atoi(key)]); };
                    i++;
                };
                i = 0;
                while (i < sm.nparams)
                {
                    key = lf_itoa(i);
                    if (om_has(sm.param_status, key))
                    {
                        fl = lf_flags(sm.param_status, key);
                        if ((fl `& LF_F) != 0 & i < arg_regs.len)
                        {
                            this.cur_line = call_line;
                            this.do_free((PtrVec*)arg_regs.items[i], st, fl == LF_F);
                            this.cur_line = call_line;
                        };
                    };
                    i++;
                };
                j = 0;
                while (j < sm.param_held.len)
                {
                    lh = (LHeld*)sm.param_held.items[j];
                    j++;
                    if (lh.idx >= arg_regs.len) { continue; };
                    mapped = this.map_set(lh.regs, fname, sm, arg_regs, call_line, cache, st);
                    regs = (PtrVec*)arg_regs.items[lh.idx];
                    i = 0;
                    while (i < regs.len)
                    {
                        c = (byte*)regs.items[i];
                        q = 0;
                        while (q < lh.path.len)
                        {
                            c = lf_fld(c, (byte*)lh.path.items[q]);
                            q++;
                        };
                        if (om_has(st.held, c))
                        {
                            om_put(st.held, c, (void*)lf_rs_union((PtrVec*)om_get(st.held, c), mapped));
                        }
                        else
                        {
                            om_put(st.held, c, (void*)mapped);
                        };
                        i++;
                    };
                    this.mark_esc(mapped, st);
                };
                // arguments the callee stored away are handed off
                i = 0;
                while (i < sm.esc.ks.len)
                {
                    c = (byte*)sm.esc.ks.items[i];
                    i++;
                    if (c[0] != 'P') { continue; };
                    if (!cstr_eq(lf_seg(c, 1), fname)) { continue; };
                    if (lf_atoi(lf_seg(c, 2)) < arg_regs.len)
                    {
                        this.mark_esc((PtrVec*)arg_regs.items[lf_atoi(lf_seg(c, 2))], st);
                    };
                };
                -> this.map_set(sm.ret, fname, sm, arg_regs, call_line, cache, st);
            };
        };

        // Function to module attribution, built by the module pass. A violation found in a
        // function whose module is not in the set 'on' is dropped.
        struct BcOwners
        {
            NameMap* full;      // mangled function name to module name
            NameMap* bare;      // last segment to module name (first module wins)
        };

        def bc_owner_of(BcOwners* o, byte* fn) -> byte*
        {
            if (fn == (byte*)0) { return (byte*)0; };
            if (fn[0] == 0) { return (byte*)0; };
            if (nm_has(o.full, fn)) { return (byte*)nm_get(o.full, fn); };
            byte* b = bc_last_seg(fn);
            byte* r = (byte*)0;
            if (nm_has(o.bare, b)) { r = (byte*)nm_get(o.bare, b); };
            ffree(b);
            return r;
        };

        // True when a violation in function fn is kept: its module is in 'on', or unknown
        def bc_owner_on(BcOwners* o, NameMap* on, byte* fn) -> bool
        {
            byte* m = bc_owner_of(o, fn);
            if (m == (byte*)0) { return true; };
            return nm_has(on, m);
        };

        def borrow_check_filtered(Node* prog, Preprocessor* pp, byte* entry, bool warn, BcOwners* owners, NameMap* on) -> int
        {
            CallGraph cg;
            cg.__init();
            defer cg.__exit();
            cg.collect(prog);
            BorrowChecker bc;
            bc.__init(@cg, entry, true, true, pp);
            defer bc.__exit();
            bc.run();
            // lifetime kinds come from the lifetime analysis, not the alias walk
            LifeChecker lc;
            lc.__init(@cg, entry, pp, warn);
            defer lc.__exit();
            lc.run();
            PtrVec* all = pv_new();
            int vi;
            BVio* vv;
            while (vi < lc.violations.len) { pv_push(all, lc.violations.items[vi]); vi++; };
            vi = 0;
            while (vi < bc.violations.len)
            {
                vv = (BVio*)bc.violations.items[vi];
                if (!(cstr_eq(vv.kind, g"scope_escape\0") | cstr_eq(vv.kind, g"use_after_scope\0")
                      | cstr_eq(vv.kind, g"use_after_free\0") | cstr_eq(vv.kind, g"heap_leak\0") | cstr_eq(vv.kind, g"mutable_alias\0")))
                {
                    pv_push(all, (void*)vv);
                };
                vi++;
            };
            if (on != (NameMap*)0)
            {
                PtrVec* kept = pv_new();
                vi = 0;
                while (vi < all.len)
                {
                    vv = (BVio*)all.items[vi];
                    if (bc_owner_on(owners, on, vv.func)) { pv_push(kept, (void*)vv); };
                    vi++;
                };
                pv_free(all);
                all = kept;
            };
            bc_print_violations(all, warn);
            bc_print_summary(all, 1, bc.funcs_checked);
            int n = all.len;
            pv_free(all);
            return n;
        };

        def borrow_check_program(Node* prog, Preprocessor* pp, byte* entry, bool warn) -> int
        {
            return borrow_check_filtered(prog, pp, entry, warn, (BcOwners*)0, (NameMap*)0);
        };
    };
};

#endif;
