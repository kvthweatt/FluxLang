// Author: Karac V. Thweatt
//
// fdce.fx - Flux dead code eliminator (port of fdce.py)
//
// Runs on the AST produced by the parser before the checker and code generation.
// Every namespace level declaration (functions, structs, objects and their methods,
// enums, unions, traits, variables) whose name is never referenced by live code is
// removed from its list. Liveness is a fixed point seeded from the entry point and
// from top level code that is not a function.
//
// Mangling: a call may spell any "__" suffix of the fully qualified mangled name, so
// declarations are indexed under every suffix and every reference expands to every
// suffix, exactly as fdce.py does.

#ifndef FLUX_AST
#import "fast.fx";
#endif;

#ifndef FLUX_TYPES
#import "ftypesys.fx";
#endif;

#ifndef FLUX_DCE
#def FLUX_DCE 1;

using flux::ast;
using flux::preprocessor;
using flux::types;

namespace flux
{
    namespace dce
    {
        dce_count(Node* n, int s) -> int
        {
            switch (n == (Node*)0)
            {
                case (true) { -> 0; }
                default {};
            };
            -> node_count(n, s);
        };

        // Substring test
        dce_contains(byte* hay, byte* needle) -> bool
        {
            int i = 0;
            int j;
            switch (needle[0] == 0)
            {
                case (true) { -> true; }
                default {};
            };
            while (hay[i] != 0)
            {
                j = 0;
                while (needle[j] != 0)
                {
                    switch (hay[i + j] != needle[j])
                    {
                        case (true) { break; }
                        default {};
                    };
                    j++;
                };
                switch (needle[j] == 0)
                {
                    case (true) { -> true; }
                    default {};
                };
                i++;
            };
            -> false;
        };

        // Index of the first occurrence of needle in hay, or -1
        dce_find(byte* hay, byte* needle) -> int
        {
            int i = 0;
            int j;
            while (hay[i] != 0)
            {
                j = 0;
                while (needle[j] != 0)
                {
                    switch (hay[i + j] != needle[j])
                    {
                        case (true) { break; }
                        default {};
                    };
                    j++;
                };
                switch (needle[j] == 0)
                {
                    case (true) { -> i; }
                    default {};
                };
                i++;
            };
            -> -1;
        };

        // Decimal key of a node pointer
        dce_ptr_key(Buf* b, void* p) -> byte*
        {
            u64 v = (u64)p;
            int i = 0;
            int d;
            b.clear();
            switch (v == (u64)0)
            {
                case (true) {
                b.put('0');
                -> b.mem;
            }
                default {};
            };
            while (i < 16)
            {
                d = (int)((v >> (u64)((15 - i) * 4)) `& (u64)15);
                switch (d < 10)
                {
                    case (true) { b.put('0' + d); }
                    default { b.put('a' + (d - 10)); };
                };
                i++;
            };
            -> b.mem;
        };

        // fstr_append overloads that code generation picks from value types
        dce_fstr_name(int i) -> byte*
        {
            switch (i)
            {
                case (0) { -> g"standard__strings__fstr_append__3__floatE1__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                case (1) { -> g"standard__strings__fstr_append__3__doubleE1__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                case (2) { -> g"standard__strings__fstr_append__3__byteE1_ptr1__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                case (3) { -> g"standard__strings__fstr_append__3__dataE1_ubits16__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                case (4) { -> g"standard__strings__fstr_append__3__dataE1_ubits32__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                case (5) { -> g"standard__strings__fstr_append__3__dataE1_ubits64__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                case (6) { -> g"standard__strings__fstr_append__3__dataE1_sbits16__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                case (7) { -> g"standard__strings__fstr_append__3__dataE1_sbits32__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                case (8) { -> g"standard__strings__fstr_append__3__dataE1_sbits64__byteE1_ptr1__intE1_ptr1__ret_intE1\0"; }
                default { -> (byte*)0; };
            };
            -> (byte*)0;
        };

        // Primitive and keyword names that are never user symbols
        dce_prim_name(int i) -> byte*
        {
            switch (i)
            {
                case (0) { -> g"int\0"; }
                case (1) { -> g"uint\0"; }
                case (2) { -> g"float\0"; }
                case (3) { -> g"double\0"; }
                case (4) { -> g"bool\0"; }
                case (5) { -> g"byte\0"; }
                case (6) { -> g"char\0"; }
                case (7) { -> g"void\0"; }
                case (8) { -> g"str\0"; }
                case (9) { -> g"string\0"; }
                case (10) { -> g"i8\0"; }
                case (11) { -> g"i16\0"; }
                case (12) { -> g"i32\0"; }
                case (13) { -> g"i64\0"; }
                case (14) { -> g"i128\0"; }
                case (15) { -> g"u8\0"; }
                case (16) { -> g"u16\0"; }
                case (17) { -> g"u32\0"; }
                case (18) { -> g"u64\0"; }
                case (19) { -> g"u128\0"; }
                case (20) { -> g"f32\0"; }
                case (21) { -> g"f64\0"; }
                case (22) { -> g"ptr\0"; }
                case (23) { -> g"ref\0"; }
                case (24) { -> g"null\0"; }
                case (25) { -> g"nullptr\0"; }
                case (26) { -> g"true\0"; }
                case (27) { -> g"false\0"; }
                default { -> (byte*)0; };
            };
            -> (byte*)0;
        };

        object Dce
        {
            NameMap* prims;
            NameMap* live;
            NameMap* nsf;       // namespace functions by every suffix and by name__N
            NameMap* tlf;       // top level functions
            NameMap* objm;      // object methods by every suffix
            NameMap* objmq;     // object methods by suffixes that contain Object__method
            NameMap* owner;     // method pointer -> bare object name
            PtrVec* keep;       // heap blocks owned until the end
            Buf sb;
            Buf kb;
            Buf kb2;
            byte* entry;
            int eliminated;

            __init(byte* entry_name) -> this
            {
                int i;
                byte* p;
                this.prims = nm_new();
                this.live = nm_new();
                this.nsf = nm_new();
                this.tlf = nm_new();
                this.objm = nm_new();
                this.objmq = nm_new();
                this.owner = nm_new();
                this.keep = pv_new();
                this.sb.__init();
                this.kb.__init();
                this.kb2.__init();
                this.entry = entry_name;
                this.eliminated = 0;
                p = dce_prim_name(0);
                while (p != (byte*)0)
                {
                    nm_put(this.prims, p, (void*)1);
                    i++;
                    p = dce_prim_name(i);
                };
                -> this;
            };

            __expr() -> Dce* -> this;

            __exit() -> void
            {
                int i;
                nm_free(this.prims);
                nm_free(this.live);
                nm_free(this.nsf);
                nm_free(this.tlf);
                nm_free(this.objm);
                nm_free(this.objmq);
                nm_free(this.owner);
                while (i < this.keep.len)
                {
                    ffree((byte*)this.keep.items[i]);
                    i++;
                };
                pv_free(this.keep);
                this.sb.__exit();
                this.kb.__exit();
                this.kb2.__exit();
                ->;
            };

            own(void* p) -> void*
            {
                pv_push(this.keep, p);
                -> p;
            };

            is_prim(byte* s) -> bool -> nm_has(this.prims, s);

            // ----------------------------------------------------------
            // Names
            // ----------------------------------------------------------

            // Adds every "__" suffix of s that is not empty and not primitive
            add_suffixes(NameMap* refs, byte* s) -> void
            {
                int i = 0;
                switch (s[0] != 0)
                {
                    case (true) {
                    switch (!this.is_prim(s))
                    {
                        case (true) { nm_put(refs, s, (void*)1); }
                        default {};
                    };
                }
                    default {};
                };
                while (s[i] != 0)
                {
                    switch (s[i] == '_')
                    {
                        case (true) {
                        switch (s[i + 1] == '_')
                        {
                            case (true) {
                            i = i + 2;
                            switch (s[i] != 0)
                            {
                                case (true) {
                                switch (!this.is_prim(s + i))
                                {
                                    case (true) { nm_put(refs, s + i, (void*)1); }
                                    default {};
                                };
                            }
                                default {};
                            };
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                ->;
            };

            // True when any "__" suffix of s is in the live set
            any_suffix_live(byte* s) -> bool
            {
                int i = 0;
                switch (s[0] != 0)
                {
                    case (true) {
                    switch (nm_has(this.live, s))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                }
                    default {};
                };
                while (s[i] != 0)
                {
                    switch (s[i] == '_')
                    {
                        case (true) {
                        switch (s[i + 1] == '_')
                        {
                            case (true) {
                            i = i + 2;
                            switch (s[i] != 0)
                            {
                                case (true) {
                                switch (nm_has(this.live, s + i))
                                {
                                    case (true) { -> true; }
                                    default {};
                                };
                            }
                                default {};
                            };
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // _RefCollector._add: a name and all its suffix variants
            add_ref(NameMap* refs, byte* name) -> void
            {
                Buf nb;
                Buf db;
                int i = 0;
                int r;
                int k;
                bool dot = false;
                switch (name == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (name[0] == 0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.is_prim(name))
                {
                    case (true) { ->; }
                    default {};
                };
                nb.__init();
                db.__init();
                defer nb.__exit();
                defer db.__exit();
                // "::" becomes "__"
                while (name[i] != 0)
                {
                    switch (name[i] == ':')
                    {
                        case (true) {
                        switch (name[i + 1] == ':')
                        {
                            case (true) {
                            nb.put_str(g"__\0");
                            i = i + 2;
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    nb.put(name[i]);
                    i++;
                };
                // TypeName.method is also added in its "__" spelling
                i = 0;
                while (nb.mem[i] != 0)
                {
                    switch (nb.mem[i] == '.')
                    {
                        case (true) {
                        dot = true;
                        db.put_str(g"__\0");
                    }
                        default { db.put(nb.mem[i]); };
                    };
                    i++;
                };
                switch (dot)
                {
                    case (true) { this.add_suffixes(refs, db.mem); }
                    default {};
                };
                this.add_suffixes(refs, nb.mem);
                // main__0__ret_intE1 also yields main__0 and the bare base name
                r = dce_find(nb.mem, g"__ret_\0");
                switch (r >= 0)
                {
                    case (true) {
                    db.clear();
                    k = 0;
                    while (k < r)
                    {
                        db.put(nb.mem[k]);
                        k++;
                    };
                    this.add_suffixes(refs, db.mem);
                    db.clear();
                    k = 0;
                    while (k < r)
                    {
                        switch (nb.mem[k] == '_')
                        {
                            case (true) {
                            switch (nb.mem[k + 1] == '_')
                            {
                                case (true) { break; }
                                default {};
                            };
                        }
                            default {};
                        };
                        db.put(nb.mem[k]);
                        k++;
                    };
                    switch (db.mem[0] != 0)
                    {
                        case (true) {
                        switch (!this.is_prim(db.mem))
                        {
                            case (true) { nm_put(refs, db.mem, (void*)1); }
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

            // Puts the text after the last "__" of name (with "::" read as "__") plus
            // "__N" into refs
            add_arity_ref(NameMap* refs, byte* name, int nargs) -> void
            {
                Buf nb;
                int i = 0;
                int last = 0;
                nb.__init();
                defer nb.__exit();
                while (name[i] != 0)
                {
                    switch (name[i] == ':')
                    {
                        case (true) {
                        switch (name[i + 1] == ':')
                        {
                            case (true) {
                            nb.put_str(g"__\0");
                            i = i + 2;
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    nb.put(name[i]);
                    i++;
                };
                // rsplit('__', 1): rightmost "__"
                i = nb.len - 2;
                last = 0;
                while (i >= 0)
                {
                    switch (nb.mem[i] == '_')
                    {
                        case (true) {
                        switch (nb.mem[i + 1] == '_')
                        {
                            case (true) {
                            last = i + 2;
                            break;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i--;
                };
                this.sb.clear();
                this.sb.put_str(nb.mem + last);
                switch (this.sb.mem[0] == 0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.is_prim(this.sb.mem))
                {
                    case (true) { ->; }
                    default {};
                };
                this.sb.put_str(g"__\0");
                this.sb.put_int(nargs);
                nm_put(refs, this.sb.mem, (void*)1);
                ->;
            };

            // ----------------------------------------------------------
            // Reference collector
            // ----------------------------------------------------------

            walk_ts(NameMap* refs, TypeSpec* t) -> void
            {
                int i;
                switch (t == (TypeSpec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (t.custom_typename != (byte*)0)
                {
                    case (true) { this.add_ref(refs, t.custom_typename); }
                    default {};
                };
                this.collect(refs, t.array_size);
                switch (t.array_dims != (NodeVec*)0)
                {
                    case (true) {
                    while (i < t.array_dims.len)
                    {
                        this.collect(refs, t.array_dims.items[i]);
                        i++;
                    };
                }
                    default {};
                };
                this.walk_ts(refs, t.array_elem);
                ->;
            };

            // Function pointer types are plain dataclasses in fdce.py, so every type
            // inside them is visited
            walk_fp(NameMap* refs, TypeSpec* t) -> void
            {
                int i;
                switch (t == (TypeSpec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                this.walk_ts(refs, t.fp_ret);
                this.walk_fp(refs, t.fp_ret);
                switch (t.fp_params != (TypeSpec**)0)
                {
                    case (true) {
                    while (i < t.fp_nparams)
                    {
                        this.walk_ts(refs, t.fp_params[i]);
                        this.walk_fp(refs, t.fp_params[i]);
                        i++;
                    };
                }
                    default {};
                };
                ->;
            };

            walk_list(NameMap* refs, Node* n, int slot) -> void
            {
                int c = dce_count(n, slot);
                int i;
                while (i < c)
                {
                    this.collect(refs, node_child(n, slot, i));
                    i++;
                };
                ->;
            };

            collect(NameMap* refs, Node* n) -> void
            {
                int k;
                int i;
                int c;
                Node* o;
                switch (n == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                k = n.kind;
                switch (k == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    this.add_ref(refs, n.text);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.FUNCTION_CALL)
                {
                    case (true) {
                    switch (n.text != (byte*)0)
                    {
                        case (true) {
                        this.add_ref(refs, n.text);
                        this.add_arity_ref(refs, n.text, dce_count(n, 0));
                    }
                        default {};
                    };
                    this.walk_list(refs, n, 0);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.METHOD_CALL)
                {
                    case (true) {
                    o = n.a;
                    switch (n.text != (byte*)0)
                    {
                        case (true) {
                        switch (n.text[0] != 0)
                        {
                            case (true) {
                            this.add_ref(refs, n.text);
                            this.sb.clear();
                            this.sb.put_str(n.text);
                            this.sb.put_str(g"__\0");
                            this.sb.put_int(dce_count(n, 0));
                            nm_put(refs, this.sb.mem, (void*)1);
                            switch (o != (Node*)0)
                            {
                                case (true) {
                                switch (o.kind == NodeKind.IDENTIFIER | o.kind == NodeKind.FUNCTION_CALL | o.kind == NodeKind.MACRO_CALL)
                                {
                                    case (true) {
                                    switch (o.text != (byte*)0)
                                    {
                                        case (true) {
                                        switch (o.text[0] != 0)
                                        {
                                            case (true) {
                                            this.kb.clear();
                                            this.kb.put_str(o.text);
                                            this.kb.put_str(g"__\0");
                                            this.kb.put_str(n.text);
                                            this.add_ref(refs, this.kb.mem);
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
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    this.collect(refs, o);
                    this.walk_list(refs, n, 0);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.F_STRING_LITERAL)
                {
                    case (true) {
                    i = 0;
                    while (i < 9)
                    {
                        this.add_ref(refs, dce_fstr_name(i));
                        i++;
                    };
                    this.walk_list(refs, n, 0);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.MEMBER_ACCESS)
                {
                    case (true) {
                    this.collect(refs, n.a);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.STRUCT_FIELD_ACCESS)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (k == NodeKind.ENUM_DEF)
                {
                    case (true) {
                    this.walk_ts(refs, n.ts);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.NAMESPACE_DEF)
                {
                    case (true) {
                    // Members only, base namespace names are plain strings
                    this.walk_list(refs, n, 0);
                    this.walk_list(refs, n, 1);
                    this.walk_list(refs, n, 2);
                    this.walk_list(refs, n, 3);
                    this.walk_list(refs, n, 4);
                    this.walk_list(refs, n, 5);
                    this.collect(refs, n.a);
                    this.collect(refs, n.b);
                    ->;
                }
                    default {};
                };

                this.walk_ts(refs, n.ts);
                this.walk_ts(refs, n.ts2);
                switch (k == NodeKind.FUNCTION_POINTER_DECLARATION)
                {
                    case (true) { this.walk_fp(refs, n.ts); }
                    default {};
                };

                this.collect(refs, n.a);
                this.collect(refs, n.b);
                this.collect(refs, n.c);
                switch (k != NodeKind.OBJECT_DEF)
                {
                    case (true) {
                    this.collect(refs, n.d);
                    this.collect(refs, n.e);
                }
                    default {};
                };

                // Lists whose members are plain names are skipped
                switch (k == NodeKind.FOR_IN_LOOP | k == NodeKind.STRUCT_INSTANCE | k == NodeKind.STRUCT_LITERAL |
                    k == NodeKind.INTERFACE_DEF | k == NodeKind.MACRO_DEF | k == NodeKind.CONTRACT_DEF |
                    k == NodeKind.CONSTRA_DEF)
                {
                    case (true) {
                    switch (k == NodeKind.STRUCT_INSTANCE | k == NodeKind.STRUCT_LITERAL)
                    {
                        case (true) {
                        this.walk_list(refs, n, 1);
                        this.walk_list(refs, n, 2);
                    }
                        default {
                            switch (k == NodeKind.INTERFACE_DEF)
                            {
                                case (true) { this.walk_list(refs, n, 1); }
                                default {
                                    switch (k == NodeKind.CONTRACT_DEF | k == NodeKind.CONSTRA_DEF | k == NodeKind.MACRO_DEF)
                                    {
                                        case (true) { }
                                        default {
                        this.walk_list(refs, n, 1);
                        this.walk_list(refs, n, 2);
                    };
                                    };
                                };
                            };
                        };
                    };
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.STRUCT_DEF)
                {
                    case (true) {
                    this.walk_list(refs, n, 0);
                    this.walk_list(refs, n, 3);
                    this.walk_list(refs, n, 5);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.OBJECT_DEF)
                {
                    case (true) {
                    this.walk_list(refs, n, 0);
                    this.walk_list(refs, n, 1);
                    this.walk_list(refs, n, 3);
                    this.walk_list(refs, n, 4);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.DESTRUCTURING_ASSIGNMENT)
                {
                    case (true) {
                    c = dce_count(n, 0);
                    i = 0;
                    while (i < c)
                    {
                        o = node_child(n, 0, i);
                        switch (o.kind != NodeKind.IDENTIFIER)
                        {
                            case (true) { this.collect(refs, o); }
                            default {};
                        };
                        i++;
                    };
                    this.walk_list(refs, n, 1);
                    this.walk_list(refs, n, 2);
                    this.walk_list(refs, n, 3);
                    this.walk_list(refs, n, 4);
                    this.walk_list(refs, n, 5);
                    ->;
                }
                    default {};
                };
                this.walk_list(refs, n, 0);
                this.walk_list(refs, n, 1);
                this.walk_list(refs, n, 2);
                this.walk_list(refs, n, 3);
                this.walk_list(refs, n, 4);
                this.walk_list(refs, n, 5);
                ->;
            };

            // ----------------------------------------------------------
            // Indexes
            // ----------------------------------------------------------

            idx_add(NameMap* m, byte* key, Node* f) -> void
            {
                PtrVec* v;
                switch (key[0] == 0)
                {
                    case (true) { ->; }
                    default {};
                };
                v = (PtrVec*)nm_get(m, key);
                switch (v == (PtrVec*)0)
                {
                    case (true) {
                    v = pv_new();
                    nm_put(m, key, (void*)v);
                }
                    default {};
                };
                pv_push(v, (void*)f);
                ->;
            };

            // Adds f under every suffix of key
            idx_suffixes(NameMap* m, byte* key, Node* f) -> void
            {
                int i = 0;
                this.idx_add(m, key, f);
                while (key[i] != 0)
                {
                    switch (key[i] == '_')
                    {
                        case (true) {
                        switch (key[i + 1] == '_')
                        {
                            case (true) {
                            i = i + 2;
                            this.idx_add(m, key + i, f);
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                ->;
            };

            ns_of(Node* s) -> Node*
            {
                switch (s.kind == NodeKind.NAMESPACE_DEF)
                {
                    case (true) { -> s; }
                    default {};
                };
                switch (s.kind == NodeKind.NAMESPACE_DEF_STATEMENT)
                {
                    case (true) { -> s.a; }
                    default {};
                };
                -> (Node*)0;
            };

            // Joins prefix and name with "__" into kb2 (name only when prefix is empty)
            join_prefix(byte* prefix, byte* name) -> byte*
            {
                this.kb2.clear();
                switch (prefix[0] != 0)
                {
                    case (true) {
                    this.kb2.put_str(prefix);
                    this.kb2.put_str(g"__\0");
                }
                    default {};
                };
                this.kb2.put_str(name);
                -> this.kb2.mem;
            };

            // New heap prefix for a child namespace
            child_prefix(byte* prefix, Node* ns) -> byte*
            {
                Buf pb;
                byte* r;
                pb.__init();
                defer pb.__exit();
                switch (prefix[0] != 0)
                {
                    case (true) {
                    pb.put_str(prefix);
                    switch (ns.text != (byte*)0)
                    {
                        case (true) {
                        switch (ns.text[0] != 0)
                        {
                            case (true) { pb.put_str(g"__\0"); }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (ns.text != (byte*)0)
                {
                    case (true) { pb.put_str(ns.text); }
                    default {};
                };
                r = ts_dup(pb.mem);
                this.own((void*)r);
                -> r;
            };

            index_ns(Node* ns, byte* prefix) -> void
            {
                byte* cur = this.child_prefix(prefix, ns);
                int c;
                int i;
                int j;
                int mc;
                Node* f;
                Node* o;
                Node* m;
                byte* full;
                byte* anchor;
                Buf kq;
                byte* key;
                c = dce_count(ns, 0);
                while (i < c)
                {
                    f = node_child(ns, 0, i);
                    i++;
                    switch (f.kind != NodeKind.FUNCTION_DEF)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (f.text == (byte*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    full = this.join_prefix(cur, f.text);
                    this.idx_suffixes(this.nsf, full, f);
                    this.sb.clear();
                    this.sb.put_str(f.text);
                    this.sb.put_str(g"__\0");
                    this.sb.put_int(dce_count(f, 0));
                    this.idx_add(this.nsf, this.sb.mem, f);
                };
                // Object methods
                kq.__init();
                defer kq.__exit();
                c = dce_count(ns, 2);
                i = 0;
                while (i < c)
                {
                    o = node_child(ns, 2, i);
                    i++;
                    switch (o.kind != NodeKind.OBJECT_DEF)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    mc = dce_count(o, 1);
                    j = 0;
                    while (j < mc)
                    {
                        m = node_child(o, 1, j);
                        j++;
                        switch (m.text == (byte*)0)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        kq.clear();
                        switch (o.text != (byte*)0)
                        {
                            case (true) { kq.put_str(o.text); }
                            default {};
                        };
                        kq.put_str(g"__\0");
                        kq.put_str(m.text);
                        anchor = ts_dup(kq.mem);
                        this.own((void*)anchor);
                        full = this.join_prefix(cur, anchor);
                        key = ts_dup(full);
                        this.own((void*)key);
                        nm_put(this.owner, dce_ptr_key(@this.sb, (void*)m), (void*)o.text);
                        this.index_method(key, anchor, m);
                    };
                };
                c = dce_count(ns.b, 0);
                i = 0;
                while (i < c)
                {
                    this.index_ns(node_child(ns.b, 0, i), cur);
                    i++;
                };
                ->;
            };

            // Method m under every suffix of full; the qualified index only keeps
            // suffixes that contain Object__method
            index_method(byte* full, byte* anchor, Node* m) -> void
            {
                int i = 0;
                this.idx_add(this.objm, full, m);
                this.idx_add(this.objmq, full, m);
                while (full[i] != 0)
                {
                    switch (full[i] == '_')
                    {
                        case (true) {
                        switch (full[i + 1] == '_')
                        {
                            case (true) {
                            i = i + 2;
                            switch (full[i] != 0)
                            {
                                case (true) {
                                this.idx_add(this.objm, full + i, m);
                                switch (dce_contains(full + i, anchor))
                                {
                                    case (true) { this.idx_add(this.objmq, full + i, m); }
                                    default {};
                                };
                            }
                                default {};
                            };
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                ->;
            };

            // ----------------------------------------------------------
            // Liveness
            // ----------------------------------------------------------

            is_entry(Node* f) -> bool
            {
                switch (f.text == (byte*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (cstr_eq(f.text, this.entry))
                {
                    case (true) { -> true; }
                    default {};
                };
                -> cstr_eq(f.text, g"_start\0");
            };

            // Adds every ref of f that is not live yet to out
            refs_into(Node* f, NameMap* out) -> void
            {
                NameMap* r = nm_new();
                int e;
                this.collect(r, f);
                while (e < r.count)
                {
                    switch (r.vals[e] != (void*)0)
                    {
                        case (true) {
                        switch (!nm_has(this.live, r.keys[e]))
                        {
                            case (true) { nm_put(out, r.keys[e], (void*)1); }
                            default {};
                        };
                    }
                        default {};
                    };
                    e++;
                };
                nm_free(r);
                ->;
            };

            walk_funcs(PtrVec* v, NameMap* out) -> void
            {
                int i;
                switch (v == (PtrVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                while (i < v.len)
                {
                    this.refs_into((Node*)v.items[i], out);
                    i++;
                };
                ->;
            };

            // Name of f followed by __N, N being its parameter count, in kb
            count_key(Node* f) -> byte*
            {
                this.kb.clear();
                this.kb.put_str(f.text);
                this.kb.put_str(g"__\0");
                this.kb.put_int(dce_count(f, 0));
                -> this.kb.mem;
            };

            // One fixed point round: expands frontier into live and returns the next one.
            // narrow selects the arity narrowing of namespace functions
            expand(NameMap* frontier, bool narrow) -> void
            {
                NameMap* cur = frontier;
                NameMap* nxt;
                int e;
                int i;
                bool has_count;
                PtrVec* funcs;
                Node* f;
                byte* name;
                while (cur.count > 0)
                {
                    nxt = nm_new();
                    e = 0;
                    while (e < cur.count)
                    {
                        switch (cur.vals[e] == (void*)0)
                        {
                            case (true) { e++; continue; }
                            default {};
                        };
                        name = cur.keys[e];
                        e++;
                        switch (nm_has(this.live, name))
                        {
                            case (true) { continue; }
                            default {};
                        };
                        nm_put(this.live, name, (void*)1);
                        funcs = (PtrVec*)nm_get(this.nsf, name);
                        switch (funcs != (PtrVec*)0)
                        {
                            case (true) {
                            has_count = false;
                            switch (narrow)
                            {
                                case (true) {
                                i = 0;
                                while (i < funcs.len)
                                {
                                    f = (Node*)funcs.items[i];
                                    i++;
                                    switch (nm_has(this.live, this.count_key(f)))
                                    {
                                        case (true) { has_count = true; }
                                        default {};
                                    };
                                };
                            }
                                default {};
                            };
                            i = 0;
                            while (i < funcs.len)
                            {
                                f = (Node*)funcs.items[i];
                                i++;
                                switch (has_count)
                                {
                                    case (true) {
                                    switch (!nm_has(this.live, this.count_key(f)))
                                    {
                                        case (true) { continue; }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                                this.refs_into(f, nxt);
                            };
                        }
                            default {};
                        };
                        this.walk_funcs((PtrVec*)nm_get(this.tlf, name), nxt);
                        this.walk_funcs((PtrVec*)nm_get(this.objmq, name), nxt);
                    };
                    switch (cur != frontier)
                    {
                        case (true) { nm_free(cur); }
                        default {};
                    };
                    cur = nxt;
                };
                switch (cur != frontier)
                {
                    case (true) { nm_free(cur); }
                    default {};
                };
                ->;
            };

            // Field and member types of live structs and objects
            type_field_refs(Node* ns, byte* prefix, NameMap* out) -> void
            {
                byte* cur = this.child_prefix(prefix, ns);
                int s;
                int c;
                int i;
                Node* d;
                while (s < 2)
                {
                    switch (s)
                    {
                        case (0) { c = dce_count(ns, 1); }
                        default { c = dce_count(ns, 2); };
                    };
                    i = 0;
                    while (i < c)
                    {
                        switch (s)
                        {
                            case (0) { d = node_child(ns, 1, i); }
                            default { d = node_child(ns, 2, i); };
                        };
                        i++;
                        switch (d.text == (byte*)0)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        switch (d.text[0] == 0)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        switch (!this.any_suffix_live(this.join_prefix(cur, d.text)))
                        {
                            case (true) { continue; }
                            default {};
                        };
                        this.refs_into(d, out);
                    };
                    s++;
                };
                c = dce_count(ns.b, 0);
                i = 0;
                while (i < c)
                {
                    this.type_field_refs(node_child(ns.b, 0, i), cur, out);
                    i++;
                };
                ->;
            };

            // Trait objects: method names enter the seed when the object name occurs in it
            seed_traits(Node* ns, byte* prefix, NameMap* seed) -> void
            {
                byte* cur = this.child_prefix(prefix, ns);
                int c = dce_count(ns, 2);
                int i;
                int j;
                int mc;
                int e;
                int q;
                Node* o;
                Node* m;
                bool refd;
                byte* full;
                byte* anchor;
                byte* v;
                Buf kq;
                kq.__init();
                defer kq.__exit();
                while (i < c)
                {
                    o = node_child(ns, 2, i);
                    i++;
                    switch (o.kind != NodeKind.OBJECT_DEF)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (dce_count(o, 5) == 0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (o.text == (byte*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (o.text[0] == 0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    refd = false;
                    e = 0;
                    while (e < seed.count)
                    {
                        switch (seed.vals[e] != (void*)0)
                        {
                            case (true) {
                            switch (dce_contains(seed.keys[e], o.text))
                            {
                                case (true) { refd = true; break; }
                                default {};
                            };
                        }
                            default {};
                        };
                        e++;
                    };
                    switch (!refd)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    mc = dce_count(o, 1);
                    j = 0;
                    while (j < mc)
                    {
                        m = node_child(o, 1, j);
                        j++;
                        switch (m.text == (byte*)0)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        kq.clear();
                        kq.put_str(o.text);
                        kq.put_str(g"__\0");
                        kq.put_str(m.text);
                        anchor = ts_dup(kq.mem);
                        this.own((void*)anchor);
                        full = ts_dup(this.join_prefix(cur, anchor));
                        this.own((void*)full);
                        nm_put(seed, full, (void*)1);
                        q = 0;
                        while (full[q] != 0)
                        {
                            switch (full[q] == '_')
                            {
                                case (true) {
                                switch (full[q + 1] == '_')
                                {
                                    case (true) {
                                    q = q + 2;
                                    v = full + q;
                                    switch (v[0] != 0)
                                    {
                                        case (true) {
                                        switch (dce_contains(v, anchor))
                                        {
                                            case (true) { nm_put(seed, v, (void*)1); }
                                            default {};
                                        };
                                    }
                                        default {};
                                    };
                                    continue;
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                            q++;
                        };
                    };
                };
                c = dce_count(ns.b, 0);
                i = 0;
                while (i < c)
                {
                    this.seed_traits(node_child(ns.b, 0, i), cur, seed);
                    i++;
                };
                ->;
            };

            seed_externs(Node* ns, NameMap* seed) -> void
            {
                int c = dce_count(ns, 5);
                int i;
                int j;
                int dc;
                Node* b;
                while (i < c)
                {
                    b = node_child(ns, 5, i);
                    i++;
                    switch (b.kind != NodeKind.EXTERN_BLOCK)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    dc = dce_count(b, 0);
                    j = 0;
                    while (j < dc)
                    {
                        this.collect(seed, node_child(b, 0, j));
                        j++;
                    };
                };
                c = dce_count(ns.b, 0);
                i = 0;
                while (i < c)
                {
                    this.seed_externs(node_child(ns.b, 0, i), seed);
                    i++;
                };
                ->;
            };

            compute_live(Node* prog) -> void
            {
                NameMap* seed = nm_new();
                NameMap* walked;
                NameMap* bare;
                NameMap* types;
                Node* s;
                Node* ns;
                int c = dce_count(prog, 0);
                int i;
                int e;
                int j;
                int before;
                bool progressed;
                PtrVec* ms;
                Node* m;
                byte* on;
                byte* key;
                Buf eb;
                eb.__init();
                defer eb.__exit();

                // Step 1: entry point and the fstr_append overloads
                eb.put_str(this.entry);
                this.add_suffixes(seed, eb.mem);
                this.add_suffixes(seed, g"standard__strings__fstr_append\0");
                nm_put(seed, g"fstr_append__3\0", (void*)1);
                i = 0;
                while (i < 9)
                {
                    this.add_suffixes(seed, dce_fstr_name(i));
                    i++;
                };

                // Step 1b: top level code that is not a namespace, using or function
                i = 0;
                while (i < c)
                {
                    s = node_child(prog, 0, i);
                    i++;
                    switch (this.ns_of(s) != (Node*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (s.kind == NodeKind.USING_STATEMENT)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (s.kind == NodeKind.FUNCTION_DEF)
                    {
                        case (true) {
                        switch (this.is_entry(s))
                        {
                            case (true) { this.collect(seed, s); }
                            default {};
                        };
                        continue;
                    }
                        default {};
                    };
                    this.collect(seed, s);
                };

                // Step 2: top level functions
                i = 0;
                while (i < c)
                {
                    s = node_child(prog, 0, i);
                    i++;
                    switch (s.kind != NodeKind.FUNCTION_DEF)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (s.text == (byte*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    this.idx_suffixes(this.tlf, s.text, s);
                    this.idx_add(this.tlf, this.count_key(s), s);
                    switch (this.is_entry(s))
                    {
                        case (true) { nm_put(seed, s.text, (void*)1); }
                        default {};
                    };
                };

                // Step 3b: namespace functions and object methods
                i = 0;
                while (i < c)
                {
                    ns = this.ns_of(node_child(prog, 0, i));
                    i++;
                    switch (ns != (Node*)0)
                    {
                        case (true) { this.index_ns(ns, g"\0"); }
                        default {};
                    };
                };
                i = 0;
                while (i < c)
                {
                    ns = this.ns_of(node_child(prog, 0, i));
                    i++;
                    switch (ns != (Node*)0)
                    {
                        case (true) { this.seed_traits(ns, g"\0", seed); }
                        default {};
                    };
                };
                i = 0;
                while (i < c)
                {
                    ns = this.ns_of(node_child(prog, 0, i));
                    i++;
                    switch (ns != (Node*)0)
                    {
                        case (true) { this.seed_externs(ns, seed); }
                        default {};
                    };
                };

                // Step 4: fixed point expansion with arity narrowing
                this.expand(seed, true);
                nm_free(seed);

                // Passes 2 and 3 repeat until nothing changes
                while (true)
                {
                    before = this.live.count;
                    walked = nm_new();
                    progressed = true;
                    while (progressed)
                    {
                        progressed = false;
                        bare = nm_new();
                        e = 0;
                        while (e < this.objm.count)
                        {
                            key = this.objm.keys[e];
                            ms = (PtrVec*)this.objm.vals[e];
                            e++;
                            switch (ms == (PtrVec*)0)
                            {
                                case (true) { continue; }
                                default {};
                            };
                            switch (dce_contains(key, g"__\0"))
                            {
                                case (true) { continue; }
                                default {};
                            };
                            switch (!nm_has(this.live, key))
                            {
                                case (true) { continue; }
                                default {};
                            };
                            j = 0;
                            while (j < ms.len)
                            {
                                m = (Node*)ms.items[j];
                                j++;
                                switch (nm_has(walked, dce_ptr_key(@this.kb2, (void*)m)))
                                {
                                    case (true) { continue; }
                                    default {};
                                };
                                on = (byte*)nm_get(this.owner, dce_ptr_key(@this.kb2, (void*)m));
                                switch (on != (byte*)0)
                                {
                                    case (true) {
                                    switch (on[0] != 0)
                                    {
                                        case (true) {
                                        switch (!nm_has(this.live, on))
                                        {
                                            case (true) { continue; }
                                            default {};
                                        };
                                    }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                                nm_put(walked, dce_ptr_key(@this.kb2, (void*)m), (void*)1);
                                progressed = true;
                                this.refs_into(m, bare);
                            };
                        };
                        this.expand(bare, false);
                        nm_free(bare);
                    };
                    nm_free(walked);

                    types = nm_new();
                    i = 0;
                    while (i < c)
                    {
                        ns = this.ns_of(node_child(prog, 0, i));
                        i++;
                        switch (ns != (Node*)0)
                        {
                            case (true) { this.type_field_refs(ns, g"\0", types); }
                            default {};
                        };
                    };
                    this.expand(types, false);
                    nm_free(types);

                    switch (this.live.count == before)
                    {
                        case (true) { break; }
                        default {};
                    };
                };
                ->;
            };

            // ----------------------------------------------------------
            // Pruning
            // ----------------------------------------------------------

            type_live(byte* prefix, byte* name) -> bool -> this.any_suffix_live(this.join_prefix(prefix, name));

            // Keeps the first n entries of the compacted list v
            set_len(NodeVec* v, int n) -> void
            {
                switch (v == (NodeVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                v.len = n;
                ->;
            };

            // Removes entries of list v (slot of node n) whose name is not live
            prune_named(NodeVec* v, byte* prefix) -> void
            {
                int i;
                int k;
                Node* d;
                bool keepd;
                switch (v == (NodeVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                while (i < v.len)
                {
                    d = v.items[i];
                    i++;
                    keepd = true;
                    switch (d.text != (byte*)0)
                    {
                        case (true) {
                        switch (d.text[0] != 0)
                        {
                            case (true) {
                            switch (!this.type_live(prefix, d.text))
                            {
                                case (true) {
                                keepd = false;
                                this.eliminated++;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (keepd)
                    {
                        case (true) {
                        v.items[k] = d;
                        k++;
                    }
                        default {};
                    };
                };
                v.len = k;
                ->;
            };

            prune_ns(Node* ns, byte* prefix) -> void
            {
                byte* cur = this.child_prefix(prefix, ns);
                NodeVec* v;
                NameMap* counted;
                int i;
                int k;
                int j;
                int jk;
                Node* f;
                Node* o;
                Node* m;
                bool lv;
                bool keepd;
                byte* full;
                byte* anchor;
                Buf kq;
                Buf fq;
                kq.__init();
                fq.__init();
                defer kq.__exit();
                defer fq.__exit();

                // Functions, with arity narrowing
                v = ns.l0;
                switch (v != (NodeVec*)0)
                {
                    case (true) {
                    counted = nm_new();
                    i = 0;
                    while (i < v.len)
                    {
                        f = v.items[i];
                        i++;
                        switch (f.kind != NodeKind.FUNCTION_DEF)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        switch (f.text == (byte*)0)
                        {
                            case (true) { continue; }
                            default {};
                        };
                        switch (nm_has(this.live, this.count_key(f)))
                        {
                            case (true) { nm_put(counted, f.text, (void*)1); }
                            default {};
                        };
                    };
                    i = 0;
                    k = 0;
                    while (i < v.len)
                    {
                        f = v.items[i];
                        i++;
                        keepd = true;
                        switch (f.kind == NodeKind.FUNCTION_DEF & f.text != (byte*)0)
                        {
                            case (true) {
                            lv = this.any_suffix_live(this.join_prefix(cur, f.text));
                            switch (lv)
                            {
                                case (true) {
                                switch (nm_has(counted, f.text))
                                {
                                    case (true) { lv = nm_has(this.live, this.count_key(f)); }
                                    default {};
                                };
                            }
                                default {};
                            };
                            switch (!(this.is_entry(f) | lv))
                            {
                                case (true) {
                                keepd = false;
                                this.eliminated++;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        switch (keepd)
                        {
                            case (true) {
                            v.items[k] = f;
                            k++;
                        }
                            default {};
                        };
                    };
                    v.len = k;
                    nm_free(counted);
                }
                    default {};
                };

                // Variables, structs, enums, unions
                switch (ns.a != (Node*)0)
                {
                    case (true) { this.prune_named(ns.a.l0, cur); }
                    default {};
                };
                this.prune_named(ns.l1, cur);
                this.prune_named(ns.l3, cur);
                this.prune_named(ns.l4, cur);

                // Objects and their methods
                v = ns.l2;
                switch (v != (NodeVec*)0)
                {
                    case (true) {
                    i = 0;
                    k = 0;
                    while (i < v.len)
                    {
                        o = v.items[i];
                        i++;
                        keepd = true;
                        switch (o.kind != NodeKind.OBJECT_DEF)
                        {
                            case (true) {
                            switch (o.text != (byte*)0)
                            {
                                case (true) {
                                switch (o.text[0] != 0)
                                {
                                    case (true) {
                                    switch (!this.type_live(cur, o.text))
                                    {
                                        case (true) {
                                        keepd = false;
                                        this.eliminated++;
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
                            default {
                                switch (o.text != (byte*)0)
                                {
                                    case (true) {
                            switch (!this.type_live(cur, o.text))
                            {
                                case (true) {
                                keepd = false;
                                this.eliminated++;
                            }
                                default {switch (o.l1 != (NodeVec*)0)
{
    case (true) {
                                j = 0;
                                jk = 0;
                                while (j < o.l1.len)
                                {
                                    m = o.l1.items[j];
                                    j++;
                                    lv = true;
                                    switch (m.text != (byte*)0)
                                    {
                                        case (true) {
                                        kq.clear();
                                        kq.put_str(o.text);
                                        kq.put_str(g"__\0");
                                        kq.put_str(m.text);
                                        anchor = kq.mem;
                                        fq.clear();
                                        switch (cur[0] != 0)
                                        {
                                            case (true) {
                                            fq.put_str(cur);
                                            fq.put_str(g"__\0");
                                        }
                                            default {};
                                        };
                                        fq.put_str(anchor);
                                        full = fq.mem;
                                        lv = this.method_live(full, anchor);
                                        switch (!lv)
                                        {
                                            case (true) {
                                            switch (nm_has(this.live, m.text))
                                            {
                                                case (true) { lv = true; }
                                                default {};
                                            };
                                        }
                                            default {};
                                        };
                                    }
                                        default {};
                                    };
                                    switch (lv)
                                    {
                                        case (true) {
                                        o.l1.items[jk] = m;
                                        jk++;
                                    }
                                        default { this.eliminated++; };
                                    };
                                };
                                o.l1.len = jk;
                            }
    default {};
};};
                            };
                        }
                                    default {};
                                };
                            };
                        };
                        switch (keepd)
                        {
                            case (true) {
                            v.items[k] = o;
                            k++;
                        }
                            default {};
                        };
                    };
                    v.len = k;
                }
                    default {};
                };

                switch (ns.b != (Node*)0)
                {
                    case (true) {
                    i = 0;
                    while (i < dce_count(ns.b, 0))
                    {
                        this.prune_ns(node_child(ns.b, 0, i), cur);
                        i++;
                    };
                }
                    default {};
                };
                ->;
            };

            // Any suffix of full that contains anchor, or full itself, is live
            method_live(byte* full, byte* anchor) -> bool
            {
                int i = 0;
                switch (nm_has(this.live, full))
                {
                    case (true) { -> true; }
                    default {};
                };
                while (full[i] != 0)
                {
                    switch (full[i] == '_')
                    {
                        case (true) {
                        switch (full[i + 1] == '_')
                        {
                            case (true) {
                            i = i + 2;
                            switch (full[i] != 0)
                            {
                                case (true) {
                                switch (dce_contains(full + i, anchor))
                                {
                                    case (true) {
                                    switch (nm_has(this.live, full + i))
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
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // eliminate(): prunes prog in place and returns the number of removed declarations
            run(Node* prog) -> int
            {
                int c;
                int i;
                int k;
                Node* s;
                Node* ns;
                bool keepd;
                this.compute_live(prog);
                c = dce_count(prog, 0);
                // Top level functions
                i = 0;
                k = 0;
                while (i < c)
                {
                    s = node_child(prog, 0, i);
                    i++;
                    keepd = true;
                    switch (s.kind == NodeKind.FUNCTION_DEF & s.text != (byte*)0)
                    {
                        case (true) {
                        switch (!(this.is_entry(s) | this.any_suffix_live(s.text)))
                        {
                            case (true) {
                            keepd = false;
                            this.eliminated++;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (keepd)
                    {
                        case (true) {
                        prog.l0.items[k] = s;
                        k++;
                    }
                        default {};
                    };
                };
                prog.l0.len = k;
                c = k;
                i = 0;
                while (i < c)
                {
                    ns = this.ns_of(node_child(prog, 0, i));
                    i++;
                    switch (ns != (Node*)0)
                    {
                        case (true) { this.prune_ns(ns, g"\0"); }
                        default {};
                    };
                };
                -> this.eliminated;
            };
        };

        // Dead code elimination on a parsed program. entry names the program entry point.
        eliminate(Node* prog, byte* entry) -> int
        {
            Dce d(entry);
            defer d.__exit();
            -> d.run(prog);
        };
    };
};

#endif;
