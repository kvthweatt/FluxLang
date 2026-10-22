// Author: Karac V. Thweatt
//
// feffects.fx - Flux effect checker (port of feffects.py)
//
// Compile time effect propagation, exclusion, Pure, conflict and boundary
// checks. Effects are erased before codegen and nothing in the AST is changed.
// The pass runs on the parsed program BEFORE dead code elimination, as fc.py
// does. Violations are collected, then printed in the format of
// feffects.print_violations / print_summary (no colour; violations and the
// summary both go to stdout).
//
// Sets of effect names are insertion ordered (OMap with a dummy value). Python
// iterates real sets in hash order, so the order of several violations that
// come from the same call site is not defined in feffects.py; here it is the
// order in which the effects were first seen.

#ifndef FLUX_AST
#import g"fast.fx";
#endif;

#ifndef FLUX_TYPES
#import g"ftypesys.fx";
#endif;

#ifndef FLUX_BORROW
#import g"fborrow.fx";
#endif;

#ifndef FLUX_EFFECTS
#def FLUX_EFFECTS 1;

using flux::ast;
using flux::preprocessor;
using flux::types;
using flux::borrow;

namespace flux
{
    namespace effects
    {
        // ------------------------------------------------------------------
        // Effect entries and sets
        // ------------------------------------------------------------------

        struct EEntry
        {
            byte* name;
            bool impl, req, excl, weak, atten, one, supp, cprop;
        };

        def ee_new(byte* name, bool atten) -> EEntry*
        {
            EEntry* e = (EEntry*)fmalloc((u64)((sizeof(EEntry) + 7) / 8));
            e.name = name;
            e.impl = false;
            e.req = false;
            e.excl = false;
            e.weak = false;
            e.atten = atten;
            e.one = false;
            e.supp = false;
            e.cprop = false;
            return e;
        };

        // A set of effects is an OMap name -> EEntry*
        def es_new() -> OMap* -> om_new();

        def es_add(OMap* s, EEntry* e) -> void
        {
            EEntry* ex = (EEntry*)om_get(s, e.name);
            if (ex == (EEntry*)0)
            {
                om_put(s, e.name, (void*)e);
                ->;
            };
            ex.impl = ex.impl | e.impl;
            ex.req = ex.req | e.req;
            ex.excl = ex.excl | e.excl;
            ex.weak = ex.weak | e.weak;
            if (!e.atten) { ex.atten = false; };
            ex.one = ex.one | e.one;
            ex.supp = ex.supp | e.supp;
            ex.cprop = ex.cprop | e.cprop;
            ->;
        };

        def es_copy(OMap* s) -> OMap*
        {
            OMap* r = es_new();
            EEntry* e;
            EEntry* n;
            int i = 0;
            while (i < s.ks.len)
            {
                e = (EEntry*)s.vs.items[i];
                n = ee_new(e.name, e.atten);
                n.impl = e.impl;
                n.req = e.req;
                n.excl = e.excl;
                n.weak = e.weak;
                n.one = e.one;
                n.supp = e.supp;
                n.cprop = e.cprop;
                om_put(r, n.name, (void*)n);
                i++;
            };
            return r;
        };

        def es_has(OMap* s, byte* name) -> bool -> om_has(s, name);

        // Union of the entries of b into a (by reference, as EffectSet.add does)
        def es_merge(OMap* a, OMap* b) -> void
        {
            int i = 0;
            while (i < b.ks.len)
            {
                es_add(a, (EEntry*)b.vs.items[i]);
                i++;
            };
            ->;
        };

        // ------------------------------------------------------------------
        // String sets (OMap with a dummy value)
        // ------------------------------------------------------------------

        def ss_new() -> OMap* -> om_new();

        def ss_add(OMap* s, byte* k) -> void
        {
            if (!om_has(s, k)) { om_put(s, k, (void*)1); };
            ->;
        };

        def ss_has(OMap* s, byte* k) -> bool -> om_has(s, k);

        def ss_len(OMap* s) -> int -> s.ks.len;

        def ss_key(OMap* s, int i) -> byte* -> (byte*)s.ks.items[i];

        def ss_copy(OMap* s) -> OMap*
        {
            OMap* r = ss_new();
            int i = 0;
            while (i < s.ks.len)
            {
                ss_add(r, (byte*)s.ks.items[i]);
                i++;
            };
            return r;
        };

        // ------------------------------------------------------------------
        // String helpers
        // ------------------------------------------------------------------

        def ef_prefix_dup(byte* s, int n) -> byte*
        {
            byte* r = (byte*)fmalloc((u64)(n + 1));
            int i = 0;
            while (i < n)
            {
                r[i] = s[i];
                i++;
            };
            r[n] = (byte)0;
            return r;
        };

        // Length of the part before the last '.', -1 when there is no '.'
        def ef_last_dot(byte* s, int len) -> int
        {
            int j = len - 1;
            while (j >= 0)
            {
                if (s[j] == '.') { return j; };
                j--;
            };
            return -1;
        };

        // True when s[0..n) equals t
        def ef_prefix_eq(byte* s, int n, byte* t) -> bool
        {
            int i = 0;
            while (i < n)
            {
                if (t[i] == 0) { return false; };
                if (s[i] != t[i]) { return false; };
                i++;
            };
            return t[n] == 0;
        };

        // True when v has a dotted ancestor equal to anc (IO.Console.Output -> IO.Console -> IO)
        def ef_dotted_anc_eq(byte* v, byte* anc) -> bool
        {
            int len = bc_len(v);
            int j;
            while (true)
            {
                j = ef_last_dot(v, len);
                if (j < 0) { return false; };
                len = j;
                if (ef_prefix_eq(v, len, anc)) { return true; };
            };
            return false;
        };

        // True when s starts with p followed by '.'
        def ef_starts_dotted(byte* s, byte* p) -> bool
        {
            int n = bc_len(p);
            int i = 0;
            while (i < n)
            {
                if (s[i] != p[i]) { return false; };
                i++;
            };
            return s[n] == '.';
        };

        // Text after the last "__" scanning from the right, the whole text when none (str.rsplit('__', 1)[-1])
        def ef_rsplit_last(byte* s) -> byte*
        {
            int n = bc_len(s);
            int j = n - 2;
            while (j >= 0)
            {
                if (s[j] == '_' & s[j + 1] == '_') { return ts_dup(s + j + 2); };
                j--;
            };
            return ts_dup(s);
        };

        // Splits a space separated list into a vector of owned strings
        def ef_split(byte* list) -> PtrVec*
        {
            PtrVec* v = pv_new();
            int i = 0;
            int st = 0;
            while (true)
            {
                if (list[i] == ' ' | list[i] == 0)
                {
                    if (i > st) { pv_push(v, (void*)ef_prefix_dup(list + st, i - st)); };
                    st = i + 1;
                    if (list[i] == 0) { break; };
                };
                i++;
            };
            return v;
        };

        // ------------------------------------------------------------------
        // Registry with the built in effect tables
        // ------------------------------------------------------------------

        struct EReg
        {
            OMap* user;            // name -> Node* (EFFECT_DEF)
            OMap* cache;           // name -> OMap* (effect set)
            OMap* fe;              // function name -> effect set
            OMap* ia;              // function or interface name -> attenuate set
            NameMap* children;     // parent -> PtrVec* of byte*
            NameMap* parent;       // child -> byte*
            NameMap* perm;         // permanent effect names
            NameMap* implies;      // name -> PtrVec* of byte*
            OMap* builtins;        // all built in names
            int depth;
            bool failed;
        };

        def er_hier(EReg* r, byte* parent, byte* kids) -> void
        {
            PtrVec* v = ef_split(kids);
            int i = 0;
            nm_put(r.children, parent, (void*)v);
            ss_add(r.builtins, parent);
            while (i < v.len)
            {
                nm_put(r.parent, (byte*)v.items[i], (void*)parent);
                ss_add(r.builtins, (byte*)v.items[i]);
                i++;
            };
            ->;
        };

        def er_impl(EReg* r, byte* name, byte* list) -> void
        {
            nm_put(r.implies, name, (void*)ef_split(list));
            ->;
        };

        def er_new() -> EReg*
        {
            EReg* r = (EReg*)fmalloc((u64)((sizeof(EReg) + 7) / 8));
            PtrVec* pv;
            int i;
            r.user = om_new();
            r.cache = om_new();
            r.fe = om_new();
            r.ia = om_new();
            r.children = nm_new();
            r.parent = nm_new();
            r.perm = nm_new();
            r.implies = nm_new();
            r.builtins = ss_new();
            r.depth = 0;
            r.failed = false;
            er_hier(r, g"IO\0", g"IO.Console IO.File IO.Socket IO.Pipe IO.Device IO.Serial IO.USB IO.GPU\0");
            er_hier(r, g"Alloc\0", g"Alloc.Heap Alloc.Pool Alloc.Stack Alloc.Virtual Alloc.Shared\0");
            er_hier(r, g"Unsafe\0", g"Unsafe.Ptr Unsafe.Cast Unsafe.ASM Unsafe.FFI Unsafe.Uninit\0");
            er_hier(r, g"Mem\0", g"Mem.Read Mem.Write Mem.Exec\0");
            er_hier(r, g"Mem.Read\0", g"Mem.Read.Process Mem.Read.Kernel Mem.Read.Mapped\0");
            er_hier(r, g"Mem.Write\0", g"Mem.Write.Process Mem.Write.Kernel Mem.Write.Exec Mem.Write.Mapped\0");
            er_hier(r, g"Mem.Exec\0", g"Mem.Exec.JIT Mem.Exec.Shellcode\0");
            er_hier(r, g"Sync\0", g"Sync.Lock Sync.Atomic Sync.Signal Sync.Wait\0");
            er_hier(r, g"Crypto\0", g"Crypto.Hash Crypto.Encrypt Crypto.Decrypt Crypto.Random Crypto.Key\0");
            er_hier(r, g"Process\0", g"Process.Spawn Process.Kill Process.Inject Process.Suspend Process.Token\0");
            er_hier(r, g"Hook\0", g"Hook.Detour Hook.IAT Hook.SSDT Hook.Vtable Hook.Exception\0");
            er_hier(r, g"Privilege\0", g"Privilege.Elevate Privilege.Drop Privilege.Check\0");
            er_hier(r, g"Time\0", g"Time.RealTime Time.Sleep Time.Timer\0");
            ss_add(r.builtins, g"Pure\0");
            ss_add(r.builtins, g"Throw\0");
            pv = ef_split(g"Unsafe Unsafe.Ptr Unsafe.Cast Unsafe.ASM Unsafe.FFI Unsafe.Uninit\0");
            i = 0;
            while (i < pv.len)
            {
                nm_put(r.perm, (byte*)pv.items[i], (void*)1);
                i++;
            };
            er_impl(r, g"Hook.Detour\0", g"Hook Unsafe Mem.Write.Exec\0");
            er_impl(r, g"Hook.IAT\0", g"Hook Mem.Write\0");
            er_impl(r, g"Hook.SSDT\0", g"Hook Privilege Mem.Write.Kernel Unsafe\0");
            er_impl(r, g"Hook.Vtable\0", g"Hook Mem.Write\0");
            er_impl(r, g"Process.Inject\0", g"Process Alloc.Virtual Mem.Write.Exec Hook Unsafe\0");
            er_impl(r, g"Crypto.Key\0", g"Crypto\0");
            return r;
        };

        // Children of a built in effect, null when it has none
        def er_kids(EReg* r, byte* name) -> PtrVec* -> (PtrVec*)nm_get(r.children, name);

        def er_parent(EReg* r, byte* name) -> byte* -> (byte*)nm_get(r.parent, name);

        def er_is_perm(EReg* r, byte* name) -> bool -> nm_has(r.perm, name);

        // Adds every static ancestor of name to s
        def er_add_parents(EReg* r, OMap* s, byte* name) -> void
        {
            byte* p = er_parent(r, name);
            while (p != (byte*)0)
            {
                ss_add(s, p);
                p = er_parent(r, p);
            };
            ->;
        };

        // True when any static ancestor of name is in s
        def er_parent_in(EReg* r, OMap* s, byte* name) -> bool
        {
            byte* p = er_parent(r, name);
            while (p != (byte*)0)
            {
                if (ss_has(s, p)) { return true; };
                p = er_parent(r, p);
            };
            return false;
        };

        // ------------------------------------------------------------------
        // Effect algebra evaluator
        // ------------------------------------------------------------------

        def er_resolve(EReg* r, byte* name) -> OMap*;

        def ef_unary_code(byte* op) -> int
        {
            if (cstr_eq(op, g"*\0")) { return 1; };
            if (cstr_eq(op, g"~\0")) { return 2; };
            if (cstr_eq(op, g"!\0")) { return 3; };
            if (cstr_eq(op, g"?\0")) { return 4; };
            if (cstr_eq(op, g"@\0")) { return 5; };
            if (cstr_eq(op, g"!@\0")) { return 6; };
            if (cstr_eq(op, g"..\0")) { return 7; };
            if (cstr_eq(op, g"...\0")) { return 8; };
            if (cstr_eq(op, g"^suppress\0")) { return 9; };
            if (cstr_eq(op, g"<*\0")) { return 10; };
            return 0;
        };

        def er_eval(EReg* r, Node* n) -> OMap*
        {
            OMap* es = es_new();
            OMap* inner;
            OMap* left;
            OMap* right;
            OMap* res;
            OMap* all;
            byte* name;
            byte* ns;
            byte* op;
            EEntry* e;
            int i;
            int code;
            int len;
            bool wild;
            if (n == (Node*)0) { return es; };
            if (r.failed) { return es; };
            if (n.kind == NodeKind.EFFECT_NAME)
            {
                name = n.text;
                if (cstr_eq(name, g"*.*\0"))
                {
                    all = ss_copy(r.builtins);
                    i = 0;
                    while (i < r.user.ks.len)
                    {
                        ss_add(all, (byte*)r.user.ks.items[i]);
                        i++;
                    };
                    i = 0;
                    while (i < all.ks.len)
                    {
                        res = er_resolve(r, ss_key(all, i));
                        es_merge(es, res);
                        i++;
                    };
                    return es;
                };
                len = bc_len(name);
                wild = false;
                if (len >= 2)
                {
                    if (name[len - 2] == '.' & name[len - 1] == '*') { wild = true; };
                };
                if (wild)
                {
                    ns = ef_prefix_dup(name, len - 2);
                    all = ss_copy(r.builtins);
                    i = 0;
                    while (i < r.user.ks.len)
                    {
                        ss_add(all, (byte*)r.user.ks.items[i]);
                        i++;
                    };
                    i = 0;
                    while (i < all.ks.len)
                    {
                        if (cstr_eq(ss_key(all, i), ns) | ef_starts_dotted(ss_key(all, i), ns))
                        {
                            res = er_resolve(r, ss_key(all, i));
                            es_merge(es, res);
                        };
                        i++;
                    };
                    return es;
                };
                res = er_resolve(r, name);
                es_merge(es, res);
                if (er_is_perm(r, name))
                {
                    e = (EEntry*)om_get(es, name);
                    if (e != (EEntry*)0) { e.atten = false; };
                };
                return es;
            };
            if (n.kind == NodeKind.EFFECT_EXPR)
            {
                op = n.text;
                code = ef_unary_code(op);
                if (code > 0)
                {
                    inner = er_eval(r, n.a);
                    i = 0;
                    while (i < inner.ks.len)
                    {
                        e = (EEntry*)inner.vs.items[i];
                        if (code == 1) { e.impl = true; };
                        if (code == 2) { e.req = true; };
                        if (code == 3) { e.excl = true; };
                        if (code == 4) { e.weak = true; };
                        if (code == 5) { e.atten = true; };
                        if (code == 6) { e.atten = false; e.excl = true; };
                        if (code == 7) { e.one = true; };
                        if (code == 8) { e.one = false; };
                        if (code == 9) { e.supp = true; };
                        if (code == 10) { e.cprop = true; };
                        i++;
                    };
                    return inner;
                };
                if (cstr_eq(op, g"&\0") | cstr_eq(op, g"|\0") | cstr_eq(op, g">\0") | cstr_eq(op, g"->\0"))
                {
                    left = er_eval(r, n.a);
                    right = er_eval(r, n.b);
                    res = es_copy(left);
                    es_merge(res, right);
                    return res;
                };
                // "^|" and "<->" are constraints only, anything else is unknown
                return es;
            };
            return es;
        };

        // Resolves a named effect to a fresh effect set
        def er_resolve(EReg* r, byte* name) -> OMap*
        {
            OMap* cached = (OMap*)om_get(r.cache, name);
            OMap* es;
            OMap* impl_es;
            Node* defn;
            PtrVec* imp;
            int i;
            bool perm;
            if (cached != (OMap*)0) { return es_copy(cached); };
            r.depth++;
            if (r.depth > 150)
            {
                r.failed = true;
                r.depth--;
                return es_new();
            };
            es = es_new();
            perm = er_is_perm(r, name);
            if (om_has(r.user, name))
            {
                defn = (Node*)om_get(r.user, name);
                if (defn.a != (Node*)0) { es = er_eval(r, defn.a); };
                es_add(es, ee_new(name, !perm));
            }
            else
            {
                es_add(es, ee_new(name, !perm));
                imp = (PtrVec*)nm_get(r.implies, name);
                if (imp != (PtrVec*)0)
                {
                    i = 0;
                    while (i < imp.len)
                    {
                        impl_es = er_resolve(r, (byte*)imp.items[i]);
                        es_merge(es, impl_es);
                        i++;
                    };
                };
            };
            r.depth--;
            om_put(r.cache, name, (void*)es);
            return es_copy(es);
        };

        // check_boundary: appended to the violation vector by the caller
        // ------------------------------------------------------------------
        // Violations
        // ------------------------------------------------------------------

        // kind: 0 exclusion, 1 boundary, 2 attenuation, 3 conflict
        struct EVio
        {
            int kind;
            byte* s1;
            byte* s2;
            byte* s3;
            int line;
            int col;
        };

        def ev_new(int kind, byte* s1, byte* s2, byte* s3, int line, int col) -> EVio*
        {
            EVio* v = (EVio*)fmalloc((u64)((sizeof(EVio) + 7) / 8));
            v.kind = kind;
            v.s1 = s1;
            v.s2 = s2;
            v.s3 = s3;
            v.line = line;
            v.col = col;
            return v;
        };

        def ev_kind_name(int kind) -> byte*
        {
            if (kind == 0) { return g"exclusion\0"; };
            if (kind == 1) { return g"boundary\0"; };
            if (kind == 2) { return g"attenuation\0"; };
            return g"conflict\0";
        };

        // str(v) of the Python violation class
        def ev_print_str(EVio* v) -> void
        {
            if (v.kind == 0)
            {
                print(g"Effect violation at \0");
                if (v.line!?)
                {
                    print(v.line);
                    print(g":\0");
                    print(v.col);
                }
                else { print(g"?\0"); };
                print(g": '\0");
                print(v.s1);
                print(g"' excludes effect '\0");
                print(v.s3);
                print(g"' but calls '\0");
                print(v.s2);
                print(g"' which introduces it\0");
                ->;
            };
            if (v.kind == 1)
            {
                print(g"Effect '\0");
                print(v.s2);
                print(g"' in '\0");
                print(v.s1);
                print(g"' crosses boundary '\0");
                print(v.s3);
                print(g"' without attenuation\0");
                ->;
            };
            if (v.kind == 2)
            {
                print(g"Cannot attenuate permanent effect '\0");
                print(v.s1);
                print(g"' at boundary '\0");
                print(v.s2);
                print(g"' (!@ prevents attenuation)\0");
                ->;
            };
            print(g"Effects '\0");
            print(v.s1);
            print(g"' and '\0");
            print(v.s2);
            print(g"' conflict at '\0");
            print(v.s3);
            print(g"' with no priority resolution\0");
            ->;
        };

        // _violation_message(v) without colour
        def ev_print_msg(EVio* v) -> void
        {
            if (v.kind == 0)
            {
                print(g"Function \0");
                print(v.s1);
                print(g" excludes effect \0");
                print(v.s3);
                print(g" but calls function \0");
                print(v.s2);
                print(g" which introduces it\0");
                ->;
            };
            if (v.kind == 1)
            {
                print(v.s1);
                print(g" introduces effect \0");
                print(v.s2);
                print(g" which crosses boundary \0");
                print(v.s3);
                print(g" without attenuation\0");
                ->;
            };
            if (v.kind == 2)
            {
                print(g"Cannot attenuate permanent effect \0");
                print(v.s1);
                print(g" at boundary \0");
                print(v.s2);
                print(g" -- !@ prevents attenuation\0");
                ->;
            };
            print(g"Effects \0");
            print(v.s1);
            print(g" and \0");
            print(v.s2);
            print(g" conflict at \0");
            print(v.s3);
            print(g" with no priority resolution\0");
            ->;
        };

        // strict: raw violations; otherwise every violation is an EffectWarning wrapper
        def ef_print_violations(PtrVec* vs, bool strict) -> void
        {
            int i = 0;
            EVio* v;
            while (i < vs.len)
            {
                v = (EVio*)vs.items[i];
                print(g"[\0");
                if (strict) { print(g"error\0"); } else { print(g"warning\0"); };
                print(g"] \0");
                if (strict) { println(ev_kind_name(v.kind)); } else { println(g"warning\0"); };
                if (strict)
                {
                    print(g"  \0");
                    if (v.kind == 0 & v.line!?)
                    {
                        print(v.line);
                        print(g":\0");
                        print(v.col);
                        print(g"  \0");
                    };
                    ev_print_msg(v);
                    println(g"\0");
                    if (v.kind == 0)
                    {
                        print(g"  caller \0");
                        print(v.s1);
                        print(g" declared effect !\0");
                        println(v.s3);
                        print(g"  callee \0");
                        print(v.s2);
                        print(g" declared effect \0");
                        println(v.s3);
                    };
                    if (v.kind == 1)
                    {
                        print(g"  add `# attenuate {v.effect_name}` to boundary \0");
                        print(v.s3);
                        println(g" to suppress\0");
                    };
                    if (v.kind == 2)
                    {
                        print(g"  effect \0");
                        print(v.s1);
                        println(g" is marked !@ and can never be stripped\0");
                    };
                }
                else
                {
                    print(g"  \0");
                    ev_print_str(v);
                    println(g"\0");
                };
                println(g"\0");
                i++;
            };
            ->;
        };

        def ef_print_summary(PtrVec* vs, bool strict) -> void
        {
            int n = vs.len;
            int cnt0 = 0;
            int cnt1 = 0;
            int cnt2 = 0;
            int cnt3 = 0;
            int i = 0;
            bool first = true;
            EVio* v;
            if (n == 0)
            {
                println(g"[Effects] OK -- no violations found.\0");
                ->;
            };
            while (i < n)
            {
                v = (EVio*)vs.items[i];
                if (v.kind == 0) { cnt0++; };
                if (v.kind == 1) { cnt1++; };
                if (v.kind == 2) { cnt2++; };
                if (v.kind == 3) { cnt3++; };
                i++;
            };
            print(g"[Effects] \0");
            print(n);
            print(g" violation(s)  \0");
            if (strict)
            {
                // sorted kind names: attenuation, boundary, conflict, exclusion
                if (cnt2 > 0) { print(g"attenuation: \0"); print(cnt2); first = false; };
                if (cnt1 > 0)
                {
                    if (!first) { print(g", \0"); };
                    print(g"boundary: \0");
                    print(cnt1);
                    first = false;
                };
                if (cnt3 > 0)
                {
                    if (!first) { print(g", \0"); };
                    print(g"conflict: \0");
                    print(cnt3);
                    first = false;
                };
                if (cnt0 > 0)
                {
                    if (!first) { print(g", \0"); };
                    print(g"exclusion: \0");
                    print(cnt0);
                };
            }
            else
            {
                print(g"warning: \0");
                print(n);
            };
            println(g"\0");
            ->;
        };

        // ------------------------------------------------------------------
        // The pass
        // ------------------------------------------------------------------

        struct EPass
        {
            EReg* reg;
            PtrVec* vios;          // EVio*
            bool strict;
            OMap* transitive;      // function name -> string set
            OMap* calls;           // function name -> string set (call graph)
            OMap* bare;            // bare or full name -> PtrVec* of effect sets
            PtrVec* xl;            // xor constraints: left, right, source (byte*) in triples
            PtrVec* ml;            // mutual constraints: left, right, negated flag, source in quads
            bool failed;
        };

        def ef_unwrap(Node* s) -> Node*
        {
            if (s == (Node*)0) { return s; };
            if (s.kind == NodeKind.FUNCTION_DEF_STATEMENT) { return s.a; };
            if (s.kind == NodeKind.NAMESPACE_DEF_STATEMENT) { return s.a; };
            return s;
        };

        // Flat list of FunctionDef, InterfaceDef and EffectDef nodes in the order the Python
        // passes visit them: a namespace's functions first, then its nested namespaces.
        def ef_walk_item(PtrVec* out, Node* s0) -> void
        {
            Node* s = ef_unwrap(s0);
            int c;
            int i;
            if (s == (Node*)0) { ->; };
            if (s.kind == NodeKind.FUNCTION_DEF | s.kind == NodeKind.INTERFACE_DEF | s.kind == NodeKind.EFFECT_DEF)
            {
                pv_push(out, (void*)s);
                ->;
            };
            if (s.kind == NodeKind.NAMESPACE_DEF)
            {
                c = bc_count(s, 0);
                i = 0;
                while (i < c)
                {
                    ef_walk_item(out, node_child(s, 0, i));
                    i++;
                };
                if (s.b != (Node*)0)
                {
                    c = bc_count(s.b, 0);
                    i = 0;
                    while (i < c)
                    {
                        ef_walk_item(out, node_child(s.b, 0, i));
                        i++;
                    };
                };
            };
            ->;
        };

        // All FUNCTION_CALL nodes below n, pre order
        def ef_collect_calls(Node* n, PtrVec* out) -> void
        {
            int s;
            int c;
            int i;
            if (n == (Node*)0) { ->; };
            if (n.kind == NodeKind.FUNCTION_CALL) { pv_push(out, (void*)n); };
            ef_collect_calls(n.a, out);
            ef_collect_calls(n.b, out);
            ef_collect_calls(n.c, out);
            ef_collect_calls(n.d, out);
            ef_collect_calls(n.e, out);
            s = 0;
            while (s < 6)
            {
                c = bc_count(n, s);
                i = 0;
                while (i < c)
                {
                    ef_collect_calls(node_child(n, s, i), out);
                    i++;
                };
                s++;
            };
            ->;
        };

        def ef_has_asm(Node* n) -> bool
        {
            int s;
            int c;
            int i;
            if (n == (Node*)0) { return false; };
            if (n.kind == NodeKind.INLINE_ASM) { return true; };
            if (ef_has_asm(n.a)) { return true; };
            if (ef_has_asm(n.b)) { return true; };
            if (ef_has_asm(n.c)) { return true; };
            if (ef_has_asm(n.d)) { return true; };
            if (ef_has_asm(n.e)) { return true; };
            s = 0;
            while (s < 6)
            {
                c = bc_count(n, s);
                i = 0;
                while (i < c)
                {
                    if (ef_has_asm(node_child(n, s, i))) { return true; };
                    i++;
                };
                s++;
            };
            return false;
        };

        // _direct_introduced: effects of the function's own annotation, with user effect
        // expansion and static ancestors
        def ep_direct(EPass* p, byte* fname) -> OMap*
        {
            EReg* r = p.reg;
            OMap* res = ss_new();
            OMap* es = (OMap*)om_get(r.fe, fname);
            OMap* ex;
            EEntry* e;
            EEntry* x;
            Node* ud;
            int i = 0;
            int j;
            if (es == (OMap*)0) { return res; };
            while (i < es.ks.len)
            {
                e = (EEntry*)es.vs.items[i];
                i++;
                if (e.excl) { continue; };
                ss_add(res, e.name);
                ud = (Node*)om_get(r.user, e.name);
                if (ud != (Node*)0)
                {
                    if (ud.a != (Node*)0)
                    {
                        ex = er_eval(r, ud.a);
                        j = 0;
                        while (j < ex.ks.len)
                        {
                            x = (EEntry*)ex.vs.items[j];
                            j++;
                            if (!x.excl)
                            {
                                ss_add(res, x.name);
                                er_add_parents(r, res, x.name);
                            };
                        };
                    };
                };
                er_add_parents(r, res, e.name);
            };
            return res;
        };

        // _attenuated_effects: names attenuated at this function's boundary, plus their children
        def ep_att(EPass* p, byte* fname) -> OMap*
        {
            EReg* r = p.reg;
            OMap* att = ss_new();
            OMap* es = (OMap*)om_get(r.ia, fname);
            EEntry* e;
            PtrVec* kids;
            int i = 0;
            int j;
            if (es == (OMap*)0) { return att; };
            while (i < es.ks.len)
            {
                e = (EEntry*)es.vs.items[i];
                i++;
                ss_add(att, e.name);
                kids = er_kids(r, e.name);
                if (kids != (PtrVec*)0)
                {
                    j = 0;
                    while (j < kids.len)
                    {
                        ss_add(att, (byte*)kids.items[j]);
                        j++;
                    };
                };
            };
            return att;
        };

        // _excluded_effects: names of ! entries of the function's own annotation, plus their children
        def ep_excluded(EPass* p, byte* fname) -> OMap*
        {
            EReg* r = p.reg;
            OMap* res = ss_new();
            OMap* es = (OMap*)om_get(r.fe, fname);
            EEntry* e;
            PtrVec* kids;
            int i = 0;
            int j;
            if (es == (OMap*)0) { return res; };
            while (i < es.ks.len)
            {
                e = (EEntry*)es.vs.items[i];
                i++;
                if (e.excl)
                {
                    ss_add(res, e.name);
                    kids = er_kids(r, e.name);
                    if (kids != (PtrVec*)0)
                    {
                        j = 0;
                        while (j < kids.len)
                        {
                            ss_add(res, (byte*)kids.items[j]);
                            j++;
                        };
                    };
                };
            };
            return res;
        };

        // _callee_requires_effects
        def ep_callee_requires(EPass* p, byte* cname) -> OMap*
        {
            EReg* r = p.reg;
            OMap* res = ss_new();
            PtrVec* cands = (PtrVec*)om_get(p.bare, cname);
            OMap* es;
            EEntry* e;
            PtrVec* kids;
            int ci = 0;
            int i;
            int j;
            int len;
            if (cands == (PtrVec*)0) { return res; };
            while (ci < cands.len)
            {
                es = (OMap*)cands.items[ci];
                ci++;
                i = 0;
                while (i < es.ks.len)
                {
                    e = (EEntry*)es.vs.items[i];
                    i++;
                    // requires, implies, or not excluded: the last test covers the others unless excluded
                    if (e.req | e.impl | !e.excl)
                    {
                        ss_add(res, e.name);
                        er_add_parents(r, res, e.name);
                        len = bc_len(e.name);
                        while (true)
                        {
                            j = ef_last_dot(e.name, len);
                            if (j < 0) { break; };
                            len = j;
                            ss_add(res, ef_prefix_dup(e.name, len));
                        };
                        kids = er_kids(r, e.name);
                        if (kids != (PtrVec*)0)
                        {
                            j = 0;
                            while (j < kids.len)
                            {
                                ss_add(res, (byte*)kids.items[j]);
                                j++;
                            };
                        };
                    };
                };
            };
            return res;
        };

        // _most_specific: keep effects with no child (static or from a user definition) also in m
        def ep_most_specific(EPass* p, OMap* m) -> OMap*
        {
            EReg* r = p.reg;
            OMap* res = ss_new();
            OMap* ex;
            PtrVec* kids;
            Node* ud;
            byte* eff;
            int i = 0;
            int j;
            bool has_child;
            while (i < m.ks.len)
            {
                eff = ss_key(m, i);
                i++;
                has_child = false;
                kids = er_kids(r, eff);
                if (kids != (PtrVec*)0)
                {
                    j = 0;
                    while (j < kids.len)
                    {
                        if (ss_has(m, (byte*)kids.items[j])) { has_child = true; };
                        j++;
                    };
                };
                ud = (Node*)om_get(r.user, eff);
                if (ud != (Node*)0)
                {
                    if (ud.a != (Node*)0)
                    {
                        ex = er_eval(r, ud.a);
                        j = 0;
                        while (j < ex.ks.len)
                        {
                            if (ss_has(m, ((EEntry*)ex.vs.items[j]).name)) { has_child = true; };
                            j++;
                        };
                    };
                };
                if (!has_child) { ss_add(res, eff); };
            };
            return res;
        };

        // Transitive set of a callee, falling back to its direct set
        def ep_trans_of(EPass* p, byte* name) -> OMap*
        {
            OMap* t = (OMap*)om_get(p.transitive, name);
            if (t != (OMap*)0) { return t; };
            return ep_direct(p, name);
        };

        def ep_report(EPass* p, EVio* v) -> void
        {
            pv_push(p.vios, (void*)v);
            ->;
        };

        def ef_matches(byte* excl, OMap* vis) -> bool
        {
            int i = 0;
            if (ss_has(vis, excl)) { return true; };
            while (i < vis.ks.len)
            {
                if (ef_dotted_anc_eq(ss_key(vis, i), excl)) { return true; };
                i++;
            };
            return false;
        };

        def ep_check_caller(EPass* p, Node* f) -> void
        {
            EReg* r = p.reg;
            OMap* excluded;
            OMap* reported;
            OMap* visible;
            OMap* callee_att;
            OMap* ct;
            OMap* matching;
            OMap* ms;
            PtrVec* calls;
            PtrVec* kids;
            Node* call;
            byte* eff;
            int ci;
            int i;
            int j;
            if (bc_is_proto(f)) { ->; };
            excluded = ep_excluded(p, f.text);
            if (ss_len(excluded) == 0) { ->; };
            if (f.a == (Node*)0) { ->; };
            calls = pv_new();
            ef_collect_calls(f.a, calls);
            reported = ss_new();
            ci = 0;
            while (ci < calls.len)
            {
                call = (Node*)calls.items[ci];
                ci++;
                ct = ep_trans_of(p, call.text);
                if (ss_len(ct) == 0) { ct = ep_callee_requires(p, call.text); };
                callee_att = ep_att(p, call.text);
                visible = ss_new();
                i = 0;
                while (i < ct.ks.len)
                {
                    if (!ss_has(callee_att, ss_key(ct, i))) { ss_add(visible, ss_key(ct, i)); };
                    i++;
                };
                i = 0;
                while (i < callee_att.ks.len)
                {
                    kids = er_kids(r, ss_key(callee_att, i));
                    if (kids != (PtrVec*)0)
                    {
                        j = 0;
                        while (j < kids.len)
                        {
                            om_del(visible, (byte*)kids.items[j]);
                            j++;
                        };
                    };
                    i++;
                };
                matching = ss_new();
                i = 0;
                while (i < excluded.ks.len)
                {
                    eff = ss_key(excluded, i);
                    i++;
                    if (ef_matches(eff, visible))
                    {
                        if (!ss_has(reported, eff)) { ss_add(matching, eff); };
                    };
                };
                if (ss_len(matching) == 0) { continue; };
                ms = ep_most_specific(p, matching);
                i = 0;
                while (i < ms.ks.len)
                {
                    eff = ss_key(ms, i);
                    i++;
                    ss_add(reported, eff);
                    ep_report(p, ev_new(0, f.text, call.text, eff, call.line, call.col));
                };
            };
            ->;
        };

        def ep_check_pure(EPass* p, Node* f) -> void
        {
            EReg* r = p.reg;
            OMap* es = (OMap*)om_get(r.fe, f.text);
            OMap* trans;
            OMap* forb;
            OMap* impure;
            OMap* ms;
            EEntry* e;
            PtrVec* calls;
            PtrVec* kids;
            Node* call;
            byte* eff;
            int i;
            int j;
            int k;
            int line;
            int col;
            bool pure;
            if (bc_is_proto(f)) { ->; };
            if (es == (OMap*)0) { ->; };
            pure = false;
            e = (EEntry*)om_get(es, g"Pure\0");
            if (e != (EEntry*)0)
            {
                if (!e.excl) { pure = true; };
            };
            if (!pure) { ->; };
            trans = (OMap*)om_get(p.transitive, f.text);
            if (trans == (OMap*)0) { trans = ss_new(); };
            forb = ss_new();
            ss_add(forb, g"IO\0");
            ss_add(forb, g"Alloc\0");
            ss_add(forb, g"Mem.Write\0");
            ss_add(forb, g"Throw\0");
            i = 0;
            while (i < 4)
            {
                kids = er_kids(r, ss_key(forb, i));
                if (kids != (PtrVec*)0)
                {
                    j = 0;
                    while (j < kids.len)
                    {
                        ss_add(forb, (byte*)kids.items[j]);
                        j++;
                    };
                };
                i++;
            };
            impure = ss_new();
            i = 0;
            while (i < trans.ks.len)
            {
                if (ss_has(forb, ss_key(trans, i))) { ss_add(impure, ss_key(trans, i)); };
                i++;
            };
            if (ss_len(impure) == 0) { ->; };
            ms = ep_most_specific(p, impure);
            i = 0;
            while (i < ms.ks.len)
            {
                eff = ss_key(ms, i);
                i++;
                line = 0;
                col = 0;
                if (f.a != (Node*)0)
                {
                    calls = pv_new();
                    ef_collect_calls(f.a, calls);
                    k = 0;
                    while (k < calls.len)
                    {
                        call = (Node*)calls.items[k];
                        k++;
                        if (ss_has(ep_trans_of(p, call.text), eff))
                        {
                            line = call.line;
                            col = call.col;
                            break;
                        };
                    };
                };
                if (line == 0) { line = f.line; };
                if (col == 0) { col = f.col; };
                ep_report(p, ev_new(0, f.text, g"(Pure violation)\0", eff, line, col));
            };
            ->;
        };

        // _effect_name_str: name of an effect node, looking through unary operators
        def ef_name_str(Node* n) -> byte*
        {
            if (n == (Node*)0) { return (byte*)0; };
            if (n.kind == NodeKind.EFFECT_NAME) { return n.text; };
            if (n.kind == NodeKind.EFFECT_EXPR)
            {
                if (n.b == (Node*)0)
                {
                    if (n.a != (Node*)0) { return ef_name_str(n.a); };
                };
            };
            return (byte*)0;
        };

        def ep_have_xor(EPass* p, byte* l, byte* rt, byte* src) -> bool
        {
            int i = 0;
            while (i < p.xl.len)
            {
                if (cstr_eq((byte*)p.xl.items[i], l) & cstr_eq((byte*)p.xl.items[i + 1], rt) & cstr_eq((byte*)p.xl.items[i + 2], src)) { return true; };
                i = i + 3;
            };
            return false;
        };

        def ep_have_mut(EPass* p, byte* l, byte* rt, int neg, byte* src) -> bool
        {
            int i = 0;
            while (i < p.ml.len)
            {
                if (cstr_eq((byte*)p.ml.items[i], l) & cstr_eq((byte*)p.ml.items[i + 1], rt) & (((int*)p.ml.items[i + 2])[0] == neg) & cstr_eq((byte*)p.ml.items[i + 3], src)) { return true; };
                i = i + 4;
            };
            return false;
        };

        def ep_collect_constraints(EPass* p, Node* x, byte* src) -> void
        {
            byte* ln;
            byte* rn;
            int neg;
            if (x == (Node*)0) { ->; };
            if (x.kind != NodeKind.EFFECT_EXPR) { ->; };
            if (cstr_eq(x.text, g"^|\0"))
            {
                ln = ef_name_str(x.a);
                rn = ef_name_str(x.b);
                if (ln != (byte*)0 & rn != (byte*)0)
                {
                    if (!ep_have_xor(p, ln, rn, src))
                    {
                        pv_push(p.xl, (void*)ln);
                        pv_push(p.xl, (void*)rn);
                        pv_push(p.xl, (void*)src);
                    };
                };
            }
            elif (cstr_eq(x.text, g"<->\0"))
            {
                ln = ef_name_str(x.a);
                rn = (byte*)0;
                neg = 0;
                if (x.b != (Node*)0)
                {
                    if (x.b.kind == NodeKind.EFFECT_EXPR)
                    {
                        if (cstr_eq(x.b.text, g"!\0"))
                        {
                            if (ef_name_str(x.b.a) != (byte*)0)
                            {
                                rn = ef_name_str(x.b.a);
                                neg = 1;
                            };
                        };
                    };
                };
                if (rn == (byte*)0)
                {
                    if (ef_name_str(x.b) != (byte*)0) { rn = ef_name_str(x.b); };
                };
                if (ln != (byte*)0 & rn != (byte*)0)
                {
                    if (!ep_have_mut(p, ln, rn, neg, src))
                    {
                        pv_push(p.ml, (void*)ln);
                        pv_push(p.ml, (void*)rn);
                        pv_push(p.ml, (void*)bx_new(neg));
                        pv_push(p.ml, (void*)src);
                    };
                };
            };
            ep_collect_constraints(p, x.a, src);
            ep_collect_constraints(p, x.b, src);
            ->;
        };

        // True when the effect or one of its static children is in trans
        def ep_present(EPass* p, OMap* trans, byte* name) -> bool
        {
            PtrVec* kids;
            int j;
            if (ss_has(trans, name)) { return true; };
            kids = er_kids(p.reg, name);
            if (kids != (PtrVec*)0)
            {
                j = 0;
                while (j < kids.len)
                {
                    if (ss_has(trans, (byte*)kids.items[j])) { return true; };
                    j++;
                };
            };
            return false;
        };

        def ep_check_conflicts(EPass* p, Node* f) -> void
        {
            EReg* r = p.reg;
            OMap* trans;
            OMap* fes;
            OMap* done;
            byte* src;
            byte* l;
            byte* rt;
            byte* missing;
            byte* key;
            int i;
            bool lp;
            bool rp;
            bool conflict;
            if (bc_is_proto(f)) { ->; };
            trans = (OMap*)om_get(p.transitive, f.text);
            if (trans == (OMap*)0) { ->; };
            if (ss_len(trans) == 0) { ->; };
            fes = (OMap*)om_get(r.fe, f.text);
            done = ss_new();
            i = 0;
            while (i < p.xl.len)
            {
                l = (byte*)p.xl.items[i];
                rt = (byte*)p.xl.items[i + 1];
                src = (byte*)p.xl.items[i + 2];
                i = i + 3;
                if (fes == (OMap*)0) { continue; };
                if (!es_has(fes, src)) { continue; };
                lp = ep_present(p, trans, l);
                rp = ep_present(p, trans, rt);
                if (lp & rp)
                {
                    key = join3(join3(g"xor\x1f\0", l, g"\x1f\0"), rt, g"\0");
                    if (ss_has(done, key)) { continue; };
                    ss_add(done, key);
                    ep_report(p, ev_new(3, l, rt, f.text, 0, 0));
                };
            };
            i = 0;
            while (i < p.ml.len)
            {
                l = (byte*)p.ml.items[i];
                rt = (byte*)p.ml.items[i + 1];
                src = (byte*)p.ml.items[i + 3];
                i = i + 4;
                if (fes == (OMap*)0) { continue; };
                if (!es_has(fes, src)) { continue; };
                lp = ep_present(p, trans, l);
                rp = ep_present(p, trans, rt);
                if (((int*)p.ml.items[i - 2])[0]!?) { conflict = lp & rp; }
                else { conflict = lp != rp; };
                if (conflict)
                {
                    key = join3(join3(g"mut\x1f\0", l, g"\x1f\0"), rt, g"\0");
                    if (ss_has(done, key)) { continue; };
                    ss_add(done, key);
                    if (((int*)p.ml.items[i - 2])[0]!?)
                    {
                        missing = join3(g"(excludes \0", rt, g" via <->)\0");
                    }
                    else
                    {
                        if (lp & !rp) { missing = rt; } else { missing = l; };
                        missing = join3(g"(requires \0", missing, g" via <->)\0");
                    };
                    ep_report(p, ev_new(3, l, missing, f.text, 0, 0));
                };
            };
            ->;
        };

        // registry.check_boundary
        def ep_check_boundary(EPass* p, byte* fname, OMap* es, byte* bname, OMap* att) -> void
        {
            EReg* r = p.reg;
            EEntry* e;
            byte* par;
            int i = 0;
            while (i < es.ks.len)
            {
                e = (EEntry*)es.vs.items[i];
                i++;
                if (e.excl) { continue; };
                if (es_has(att, e.name))
                {
                    if (!e.atten) { ep_report(p, ev_new(2, e.name, bname, (byte*)0, 0, 0)); };
                    continue;
                };
                par = er_parent(r, e.name);
                if (par != (byte*)0)
                {
                    if (es_has(att, par))
                    {
                        if (!e.atten) { ep_report(p, ev_new(2, e.name, bname, (byte*)0, 0, 0)); };
                        continue;
                    };
                };
                ep_report(p, ev_new(1, fname, e.name, bname, 0, 0));
            };
            ->;
        };

        def ep_add_bare(EPass* p, byte* key, OMap* es) -> void
        {
            PtrVec* l = (PtrVec*)om_get(p.bare, key);
            if (l == (PtrVec*)0)
            {
                l = pv_new();
                om_put(p.bare, key, (void*)l);
            };
            pv_push(l, (void*)es);
            ->;
        };

        def ep_call_name_ok(PtrVec* calls) -> bool
        {
            int i = 0;
            while (i < calls.len)
            {
                if (((Node*)calls.items[i]).text == (byte*)0) { return false; };
                i++;
            };
            return true;
        };

        // Runs the whole pass. Returns the number of violations, or -1 when the pass
        // itself failed (the Python pass reports "Effect pass error" and goes on).
        // Violations in a function (kinds 0 and 1) are reported only when its module is in 'on'
        def effects_check_filtered(Node* prog, bool strict, BcOwners* owners, NameMap* on) -> int
        {
            EReg* r = er_new();
            EPass p;
            PtrVec* items = pv_new();
            PtrVec* calls;
            OMap* proto_e = om_new();
            OMap* proto_a = om_new();
            OMap* es;
            OMap* cset;
            OMap* all_funcs;
            OMap* t;
            OMap* att;
            OMap* ce;
            OMap* ad;
            OMap* pn;
            Node* it;
            Node* ann;
            Node* prot;
            Node* meth;
            EEntry* e;
            byte* nm;
            byte* eff;
            byte* bare;
            int i;
            int j;
            int k;
            int m;
            int c;
            int old;
            bool changed;
            bool have_ann;
            bool bad;
            p.reg = r;
            p.vios = pv_new();
            p.strict = strict;
            p.transitive = om_new();
            p.calls = om_new();
            p.bare = om_new();
            p.xl = pv_new();
            p.ml = pv_new();
            p.failed = false;

            c = bc_count(prog, 0);
            i = 0;
            while (i < c)
            {
                ef_walk_item(items, node_child(prog, 0, i));
                i++;
            };

            // Pass 1: user effect definitions
            i = 0;
            while (i < items.len)
            {
                it = (Node*)items.items[i];
                i++;
                if (it.kind == NodeKind.EFFECT_DEF)
                {
                    om_put(r.user, it.text, (void*)it);
                    om_del(r.cache, it.text);
                };
            };

            // Pass 2: function effect sets. A prototype's annotation is the declaration.
            i = 0;
            while (i < items.len)
            {
                it = (Node*)items.items[i];
                i++;
                if (it.kind == NodeKind.FUNCTION_DEF)
                {
                    ann = it.b;
                    if (bc_is_proto(it))
                    {
                        if (ann != (Node*)0)
                        {
                            es = er_eval(r, ann.a);
                            om_put(proto_e, it.text, (void*)es);
                            om_put(r.fe, it.text, (void*)es);
                        };
                        if (it.c != (Node*)0)
                        {
                            es = er_eval(r, it.c.a);
                            om_put(proto_a, it.text, (void*)es);
                            om_put(r.ia, it.text, (void*)es);
                        };
                    }
                    else
                    {
                        if (ann != (Node*)0)
                        {
                            es = er_eval(r, ann.a);
                            om_put(r.fe, it.text, (void*)es);
                        }
                        elif (om_has(proto_e, it.text))
                        {
                            om_put(r.fe, it.text, om_get(proto_e, it.text));
                        };
                        if (it.c != (Node*)0)
                        {
                            es = er_eval(r, it.c.a);
                            om_put(r.ia, it.text, (void*)es);
                        }
                        elif (om_has(proto_a, it.text))
                        {
                            om_put(r.ia, it.text, om_get(proto_a, it.text));
                        };
                    };
                };
                if (it.kind == NodeKind.INTERFACE_DEF)
                {
                    if (it.a != (Node*)0)
                    {
                        es = er_eval(r, it.a.a);
                        om_put(r.ia, it.text, (void*)es);
                    };
                };
            };

            // Pass 2b: inline assembly implies Unsafe.ASM and Unsafe
            i = 0;
            while (i < items.len)
            {
                it = (Node*)items.items[i];
                i++;
                if (it.kind == NodeKind.FUNCTION_DEF)
                {
                    if (!bc_is_proto(it))
                    {
                        if (it.a != (Node*)0)
                        {
                            if (ef_has_asm(it.a))
                            {
                                es = (OMap*)om_get(r.fe, it.text);
                                if (es == (OMap*)0) { es = es_new(); };
                                e = ee_new(g"Unsafe.ASM\0", true);
                                e.req = true;
                                es_add(es, e);
                                e = ee_new(g"Unsafe\0", true);
                                e.req = true;
                                es_add(es, e);
                                om_put(r.fe, it.text, (void*)es);
                            };
                        };
                    };
                };
            };

            // Bare name index: calls resolved through 'using' use the bare name
            i = 0;
            while (i < r.fe.ks.len)
            {
                nm = ss_key(r.fe, i);
                es = (OMap*)r.fe.vs.items[i];
                i++;
                bare = ef_rsplit_last(nm);
                ep_add_bare(@p, bare, es);
                ep_add_bare(@p, nm, es);
            };

            if (r.failed) { return -1; };

            // Pass 3: call graph (definitions only)
            i = 0;
            while (i < items.len)
            {
                it = (Node*)items.items[i];
                i++;
                if (it.kind == NodeKind.FUNCTION_DEF)
                {
                    if (!bc_is_proto(it))
                    {
                        if (it.a != (Node*)0)
                        {
                            calls = pv_new();
                            ef_collect_calls(it.a, calls);
                            if (!ep_call_name_ok(calls)) { return -1; };
                            cset = (OMap*)om_get(p.calls, it.text);
                            if (cset == (OMap*)0)
                            {
                                cset = ss_new();
                                om_put(p.calls, it.text, (void*)cset);
                            };
                            j = 0;
                            while (j < calls.len)
                            {
                                ss_add(cset, ((Node*)calls.items[j]).text);
                                j++;
                            };
                        };
                    };
                };
            };

            // Pass 4: fixed point transitive propagation
            all_funcs = ss_new();
            i = 0;
            while (i < p.calls.ks.len)
            {
                ss_add(all_funcs, ss_key(p.calls, i));
                i++;
            };
            i = 0;
            while (i < r.fe.ks.len)
            {
                ss_add(all_funcs, ss_key(r.fe, i));
                i++;
            };
            i = 0;
            while (i < all_funcs.ks.len)
            {
                nm = ss_key(all_funcs, i);
                om_put(p.transitive, nm, (void*)ep_direct(@p, nm));
                i++;
            };
            changed = true;
            while (changed)
            {
                changed = false;
                i = 0;
                while (i < all_funcs.ks.len)
                {
                    nm = ss_key(all_funcs, i);
                    i++;
                    t = (OMap*)om_get(p.transitive, nm);
                    old = ss_len(t);
                    cset = (OMap*)om_get(p.calls, nm);
                    att = ep_att(@p, nm);
                    if (cset != (OMap*)0)
                    {
                        j = 0;
                        while (j < cset.ks.len)
                        {
                            ce = ep_trans_of(@p, ss_key(cset, j));
                            j++;
                            k = 0;
                            while (k < ce.ks.len)
                            {
                                eff = ss_key(ce, k);
                                k++;
                                if (ss_has(att, eff)) { continue; };
                                if (er_parent_in(r, att, eff)) { continue; };
                                ss_add(t, eff);
                            };
                        };
                    };
                    if (ss_len(t) != old) { changed = true; };
                };
            };

            // Pass 6: exclusions
            i = 0;
            while (i < items.len)
            {
                it = (Node*)items.items[i];
                i++;
                if (it.kind == NodeKind.FUNCTION_DEF) { ep_check_caller(@p, it); };
            };

            // Pass 7: Pure
            i = 0;
            while (i < items.len)
            {
                it = (Node*)items.items[i];
                i++;
                if (it.kind == NodeKind.FUNCTION_DEF) { ep_check_pure(@p, it); };
            };

            // Pass 8: conflicts
            i = 0;
            while (i < r.user.ks.len)
            {
                it = (Node*)r.user.vs.items[i];
                if (it.a != (Node*)0) { ep_collect_constraints(@p, it.a, ss_key(r.user, i)); };
                i++;
            };
            i = 0;
            while (i < items.len)
            {
                it = (Node*)items.items[i];
                i++;
                if (it.kind == NodeKind.FUNCTION_DEF) { ep_check_conflicts(@p, it); };
            };

            // Pass 9: interface boundaries
            i = 0;
            while (i < items.len)
            {
                it = (Node*)items.items[i];
                i++;
                if (it.kind == NodeKind.INTERFACE_DEF)
                {
                    ad = (OMap*)0;
                    if (it.a != (Node*)0) { ad = er_eval(r, it.a.a); };
                    c = bc_count(it, 1);
                    j = 0;
                    while (j < c)
                    {
                        prot = node_child(it, 1, j);
                        j++;
                        m = bc_count(prot, 0);
                        k = 0;
                        while (k < m)
                        {
                            meth = node_child(prot, 0, k);
                            k++;
                            es = (OMap*)om_get(r.fe, meth.text);
                            if (es == (OMap*)0) { continue; };
                            if (ad != (OMap*)0) { ep_check_boundary(@p, meth.text, es, it.text, ad); };
                        };
                    };
                };
            };

            if (r.failed) { return -1; };
            if (on != (NameMap*)0)
            {
                PtrVec* kept = pv_new();
                EVio* ev;
                int vi;
                while (vi < p.vios.len)
                {
                    ev = (EVio*)p.vios.items[vi];
                    vi++;
                    if (ev.kind == 0 | ev.kind == 1)
                    {
                        if (!bc_owner_on(owners, on, ev.s1)) { continue; };
                    };
                    pv_push(kept, (void*)ev);
                };
                p.vios = kept;
            };
            ef_print_violations(p.vios, strict);
            ef_print_summary(p.vios, strict);
            return p.vios.len;
        };

        def effects_check_program(Node* prog, bool strict) -> int
        {
            return effects_check_filtered(prog, strict, (BcOwners*)0, (NameMap*)0);
        };
    };
};

#endif;
