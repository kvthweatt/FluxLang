// Author: Karac V. Thweatt
//
// fcodegen.fx - Flux code generator (bootstrap, port of fcodegen.py)
//
// Emits textual LLVM IR through f_llvmir.fx. Built in stages and checked by
// diffing against the .ll the Python compiler writes.
//
// Stage A (this file so far):
//     TypeSpec to LLVM type lowering          (TypeSystem.get_llvm_type)
//     struct, union, enum, object, alias types (visit_StructDef, visit_UnionDef,
//                                               visit_EnumDef, visit_ObjectDef,
//                                               visit_TypeDeclaration)
//     function and method declarations         (visit_FunctionDef signature,
//                                               visit_ExternBlock)
//
#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_AST
#import "fast.fx";
#endif;

#ifndef FLUX_TYPES
#import "ftypesys.fx";
#endif;

#ifndef FLUX_LLVMIR
#import "f_llvmir.fx";
#endif;

#ifndef FLUX_TYPER
#import "ftyper.fx";
#endif;

#ifndef FLUX_CODEGEN
#def FLUX_CODEGEN 1;

using flux::ast;
using flux::preprocessor;
using flux::types;
using flux::ir;
using flux::check;
using flux::typer;

namespace flux
{
    namespace codegen
    {
        // Layout of a struct or object: field names, declared specs, LLVM types and
        // the vtable numbers (offset, width, alignment per field, in bits).
        struct SInfo
        {
            byte* name;
            IRType* ty;
            int n;
            byte** names;
            TypeSpec** specs;
            IRType** ftys;
            int* offs;
            int* bits;
            int* aligns;
            int total_bits;
            int max_align;
            bool is_object;
        };

        // A local variable: its storage and declared type
        struct LVar
        {
            IRValue* ptr;
            TypeSpec* ts;
            bool vol;
        };

        // Heap copy of s from index start
        dup_from(byte* s, int start) -> byte*
        {
            int i = start;
            int n;
            while (s[i] != 0)
            {
                i++;
            };
            n = i - start;
            byte* r = (byte*)fmalloc((u64)(n + 1));
            i = 0;
            while (i < n)
            {
                r[i] = s[start + i];
                i++;
            };
            r[n] = (byte)0;
            -> r;
        };

        // Bit width of an LLVM type (SizeOfTypeHandler.bits_from_llvm_type)
        bits_of(IRType* t) -> int
        {
            int i, total;
            int k = t.kind;
            switch (k == LK.INT)
            {
                case (true) { -> t.width; }
                default {};
            };
            switch (k == LK.FLOAT)
            {
                case (true) { -> 32; }
                default {};
            };
            switch (k == LK.DOUBLE)
            {
                case (true) { -> 64; }
                default {};
            };
            switch (k == LK.ARRAY)
            {
                case (true) { -> bits_of(t.elem) * t.count; }
                default {};
            };
            switch (k == LK.PTR)
            {
                case (true) { -> 64; }
                default {};
            };
            switch (k == LK.STRUCT | k == LK.ISTRUCT)
            {
                case (true) {
                while (i < t.nitems)
                {
                    total = total + bits_of(t.items[i]);
                    i++;
                };
                -> total;
            }
                default {};
            };
            -> 0;
        };

        // Field width used by ObjectTypeHandler.calculate_field_layout
        obj_field_bits(IRType* t, int* align_out) -> int
        {
            IRType* e;
            switch (t.kind == LK.INT)
            {
                case (true) {
                align_out[0] = t.width;
                -> t.width;
            }
                default {};
            };
            switch (t.kind == LK.FLOAT)
            {
                case (true) {
                align_out[0] = 32;
                -> 32;
            }
                default {};
            };
            switch (t.kind == LK.DOUBLE)
            {
                case (true) {
                align_out[0] = 64;
                -> 64;
            }
                default {};
            };
            switch (t.kind == LK.ARRAY)
            {
                case (true) {
                e = t.elem;
                switch (e.kind == LK.INT)
                {
                    case (true) {
                    align_out[0] = e.width;
                    -> e.width * t.count;
                }
                    default {};
                };
                switch (e.kind == LK.FLOAT)
                {
                    case (true) {
                    align_out[0] = 32;
                    -> 32 * t.count;
                }
                    default {};
                };
                switch (e.kind == LK.DOUBLE)
                {
                    case (true) {
                    align_out[0] = 64;
                    -> 64 * t.count;
                }
                    default {};
                };
                align_out[0] = 64;
                -> 64 * t.count;
            }
                default {};
            };
            switch (t.kind == LK.STRUCT | t.kind == LK.ISTRUCT)
            {
                case (true) {
                align_out[0] = 64;
                -> bits_of(t);
            }
                default {};
            };
            align_out[0] = 64;
            -> 64;
        };

        object CodeGen
        {
            IRModule* mod;
            FXC_SYMTABLE* st;
            NameMap* structs;       // mangled name to SInfo*
            NameMap* unions;        // mangled name to IRType*
            NameMap* enums;         // mangled name to IRType*
            NameMap* aliases;       // mangled name to IRType*
            NameMap* consts;        // global name to i64* (integer initializers)
            NameMap* defined;       // function names that have a body
            PtrVec* owned;
            byte* cur_ns;
            byte* cur_obj;
            int byte_width;
            int nerrors;
            int err_line;
            byte* err_msg;
            IRType* t_i1;
            IRType* t_i8;
            IRType* t_i32;
            IRType* t_i64;
            IRType* t_void;
            IRType* t_float;
            IRType* t_double;
            IRType* t_i8p;
            int nfuncs;
            int ntypes;
            int al_tmp;
            Buf sc;             // text scratch
            int q_len;          // next_quoted results
            int q_end;
            PtrVec* defers;     // deferred statements of the block being generated
            Buf asmb;           // inline asm body
            Buf asmc;           // inline asm constraint string
            PtrVec* scopes;     // NameMap* of LVar*, innermost last
            IRFunc* fn;         // function whose body is being generated
            Node* fnd;
            IRType* fret;
            IRBlock* brk;
            IRBlock* cont;
            bool bad;           // the current body hit something not generated yet
            byte* bad_what;
            int bad_line;
            int body_errs;
            bool in_member;
            IRValue* nra;
            IRValue* nrb;
            TypeSpec** lspecs;
            NameMap* ucounts;   // construct name to count of bodies it stopped
            NameMap* gvars;     // mangled global name to its LVar
            NameMap* fdefs;     // function name to its FUNCTION_DEF
            int nbodies;
            int nskipped;
            NameMap* gcache;    // g-string bytes (escaped) to its global
            int nstr;           // .str.N counter
            bool null_term;     // config null_terminate_strings
            NameMap* enumvals;  // Enum.Item to i64 box
            NameMap* enum_defs; // mangled enum name to its ENUM_DEF node (borrowed)
            NameMap* union_defs; // mangled union name to its UNION_DEF node (borrowed)
            NameMap* tcache;    // typeof() result string to its global (deduplicated)
            PtrVec* arr_ptrs;   // pointer types that came from array decay (_is_array_pointer)
            PtrVec* al_names;   // type aliases in declaration order
            PtrVec* al_tys;
            PtrVec* al_specs;
            PtrVec* al_idx;     // top level statement index of each alias
            int cur_stmt;       // top level statement being generated
            bool si_closed;     // a top level function body has been generated

            __init(FXC_SYMTABLE* s) -> this
            {
                this.st = s;
                this.mod = (IRModule*)fmalloc((u64)((sizeof(IRModule) + 7) / 8));
                this.mod.__init(g"flux_module\0");
                this.structs = nm_new();
                this.unions = nm_new();
                this.enums = nm_new();
                this.aliases = nm_new();
                this.consts = nm_new();
                this.defined = nm_new();
                this.owned = pv_new();
                this.cur_ns = ts_dup(g"\0");
                this.cur_obj = (byte*)0;
                this.byte_width = 8;
                this.nerrors = 0;
                this.err_line = 0;
                this.err_msg = (byte*)0;
                this.t_i1 = this.mod.t_int(1);
                this.t_i8 = this.mod.t_int(8);
                this.t_i32 = this.mod.t_int(32);
                this.t_i64 = this.mod.t_int(64);
                this.t_void = this.mod.t_void();
                this.t_float = this.mod.t_float();
                this.t_double = this.mod.t_double();
                this.t_i8p = this.mod.t_ptr(this.t_i8);
                this.al_tmp = 0;
                this.sc.__init();
                this.defers = (PtrVec*)0;
                this.asmb.__init();
                this.asmc.__init();
                this.scopes = pv_new();
                this.fn = (IRFunc*)0;
                this.fnd = (Node*)0;
                this.fret = (IRType*)0;
                this.brk = (IRBlock*)0;
                this.cont = (IRBlock*)0;
                this.bad = false;
                this.bad_what = (byte*)0;
                this.bad_line = 0;
                this.body_errs = 0;
                this.in_member = false;
                this.nra = (IRValue*)0;
                this.nrb = (IRValue*)0;
                this.lspecs = (TypeSpec**)fmalloc((u64)24 * (u64)((sizeof(TypeSpec*) + 7) / 8));
                this.keep((void*)this.lspecs);
                int li;
                while (li < 24)
                {
                    this.lspecs[li] = (TypeSpec*)0;
                    li++;
                };
                this.ucounts = nm_new();
                this.gvars = nm_new();
                this.fdefs = nm_new();
                this.nbodies = 0;
                this.nskipped = 0;
                this.gcache = nm_new();
                this.nstr = 0;
                this.null_term = false;
                this.enumvals = nm_new();
                this.enum_defs = nm_new();
                this.union_defs = nm_new();
                this.tcache = nm_new();
                this.arr_ptrs = pv_new();
                this.al_names = pv_new();
                this.al_tys = pv_new();
                this.al_specs = pv_new();
                this.al_idx = pv_new();
                this.cur_stmt = 0;
                this.si_closed = false;
                -> this;
            };

            __expr() -> CodeGen* -> this;

            __exit() -> void
            {
                int i;
                while (i < this.owned.len)
                {
                    ffree((byte*)this.owned.items[i]);
                    i++;
                };
                pv_free(this.owned);
                nm_free(this.structs);
                nm_free(this.unions);
                nm_free(this.enums);
                nm_free(this.aliases);
                nm_free(this.consts);
                nm_free(this.defined);
                nm_free(this.ucounts);
                nm_free(this.gvars);
                nm_free(this.fdefs);
                nm_free(this.gcache);
                nm_free(this.enumvals);
                nm_free(this.enum_defs);
                nm_free(this.union_defs);
                nm_free(this.tcache);
                pv_free(this.arr_ptrs);
                pv_free(this.al_names);
                pv_free(this.al_tys);
                pv_free(this.al_specs);
                pv_free(this.al_idx);
                pv_free(this.scopes);
                ffree(this.cur_ns);
                this.mod.__exit();
                ffree((byte*)this.mod);
                this.sc.__exit();
                this.asmb.__exit();
                this.asmc.__exit();
                ->;
            };

            // ----------------------------------------------------------
            // Errors and small helpers
            // ----------------------------------------------------------

            fail(byte* msg, int line) -> void
            {
                this.nerrors++;
                switch (this.err_msg == (byte*)0)
                {
                    case (true) {
                    this.err_msg = this.mod.own(msg);
                    this.err_line = line;
                }
                    default {};
                };
                ->;
            };

            // Keeps a heap block alive until __exit
            keep(void* p) -> void
            {
                pv_push(this.owned, p);
                ->;
            };

            ptr_of(IRType* t) -> IRType* -> this.mod.t_ptr(t);

            set_ns(byte* ns) -> void
            {
                ffree(this.cur_ns);
                this.cur_ns = ts_dup(ns);
                st_set_namespace(this.st, ns);
                ->;
            };

            // Heap ns::name joined for a nested namespace
            join_ns(byte* parent, byte* name) -> byte*
            {
                switch (parent[0] == 0)
                {
                    case (true) { -> ts_dup(name); }
                    default {};
                };
                -> join3(parent, g"::\0", name);
            };

            // ----------------------------------------------------------
            // Integer constants (global initializers used as array sizes)
            // ----------------------------------------------------------

            add_const(byte* mangled, i64 v) -> void
            {
                i64* box = (i64*)fmalloc((u64)8);
                box[0] = v;
                this.keep((void*)box);
                nm_put(this.consts, mangled, (void*)box);
                ->;
            };

            const_get(byte* name, i64* out) -> bool
            {
                void* p = nm_get(this.consts, name);
                switch (p == (void*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                i64* box = (i64*)p;
                out[0] = box[0];
                -> true;
            };

            // Mirrors the four step lookup in get_llvm_type: bare name, current
            // namespace, using namespaces, then the symbol table.
            resolve_dim(byte* name, i64* out) -> bool
            {
                byte* m;
                bool ok;
                int i;
                FXC_SYMENTRY* e;
                switch (this.const_get(name, out))
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (this.cur_ns[0] != 0)
                {
                    case (true) {
                    m = mangle_namespace_name(this.cur_ns, name);
                    ok = this.const_get(m, out);
                    ffree(m);
                    switch (ok)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                }
                    default {};
                };
                while (i < this.st.using_ns.len)
                {
                    m = mangle_namespace_name((byte*)this.st.using_ns.items[i], name);
                    ok = this.const_get(m, out);
                    ffree(m);
                    switch (ok)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                e = st_lookup_any(this.st, name, (byte*)0);
                switch (e != (FXC_SYMENTRY*)0)
                {
                    case (true) {
                    m = sym_mangled(e);
                    ok = this.const_get(m, out);
                    ffree(m);
                    switch (ok)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                }
                    default {};
                };
                -> false;
            };

            // Child count and child of a namespace by virtual slot: 0..5 are the lists,
            // 6 is the variables list (a), 7 the nested namespaces list (b)
            ns_count(Node* n, int s) -> int
            {
                switch (s < 6)
                {
                    case (true) { -> node_count(n, s); }
                    default {};
                };
                switch (s == 6)
                {
                    case (true) {
                    switch (n.a == (Node*)0)
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    -> node_count(n.a, 0);
                }
                    default {};
                };
                switch (n.b == (Node*)0)
                {
                    case (true) { -> 0; }
                    default {};
                };
                -> node_count(n.b, 0);
            };

            ns_child(Node* n, int s, int i) -> Node*
            {
                switch (s < 6)
                {
                    case (true) { -> node_child(n, s, i); }
                    default {};
                };
                switch (s == 6)
                {
                    case (true) { -> node_child(n.a, 0, i); }
                    default {};
                };
                -> node_child(n.b, 0, i);
            };

            // Registers integer-literal initializers of globals before types are lowered
            collect_consts(Node* n, byte* ns) -> void
            {
                int k = n.kind;
                int s, c, e;
                byte* full;
                byte* m;
                switch (k == NodeKind.NAMESPACE_DEF_STATEMENT | k == NodeKind.EXPORT_BLOCK |
                    k == NodeKind.EXTERN_BLOCK)
                {
                    case (true) {
                    switch (n.a != (Node*)0)
                    {
                        case (true) { this.collect_consts(n.a, ns); }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.NAMESPACE_DEF)
                {
                    case (true) {
                    full = this.join_ns(ns, n.text);
                    while (s < 8)
                    {
                        c = this.ns_count(n, s);
                        e = 0;
                        while (e < c)
                        {
                            this.collect_consts(this.ns_child(n, s, e), full);
                            e++;
                        };
                        s++;
                    };
                    ffree(full);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.VARIABLE_DECLARATION)
                {
                    case (true) {
                    switch (n.text == (byte*)0)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (n.a == (Node*)0)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (n.a.kind != NodeKind.LITERAL)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (n.a.op == DataType.FLOAT | n.a.op == DataType.DOUBLE)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    m = mangle_namespace_name(ns, n.text);
                    this.add_const(m, n.a.ival);
                    ffree(m);
                }
                    default {};
                };
                ->;
            };

            // ----------------------------------------------------------
            // Type lowering
            // ----------------------------------------------------------

            // Struct, object or union symbol to its LLVM type, null when unknown
            type_of_symbol(FXC_SYMENTRY* e) -> IRType*
            {
                byte* m = sym_mangled(e);
                void* p;
                IRType* r = (IRType*)0;
                switch (e.kind_id == SymbolKind.STRUCT | e.kind_id == SymbolKind.OBJECT)
                {
                    case (true) {
                    p = nm_get(this.structs, m);
                    switch (p != (void*)0)
                    {
                        case (true) {
                        SInfo* si = (SInfo*)p;
                        r = si.ty;
                    }
                        default { r = this.mod.t_named(m); };
                    };
                }
                    default {
                        switch (e.kind_id == SymbolKind.UNION)
                        {
                            case (true) {
                    p = nm_get(this.unions, m);
                    switch (p != (void*)0)
                    {
                        case (true) { r = (IRType*)p; }
                        default {};
                    };
                }
                            default {
                                switch (e.kind_id == SymbolKind.ENUM)
                                {
                                    case (true) {
                    p = nm_get(this.enums, m);
                    switch (p != (void*)0)
                    {
                        case (true) { r = (IRType*)p; }
                        default { r = this.t_i32; };
                    };
                }
                                    default {};
                                };
                            };
                        };
                    };
                };
                ffree(m);
                -> r;
            };

            // TypeResolver.resolve_custom_type
            resolve_custom(byte* name) -> IRType*
            {
                FXC_SYMENTRY* e = st_lookup_any(this.st, name, this.cur_ns);
                byte* m;
                void* p;
                switch (e == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> (IRType*)0; }
                    default {};
                };
                switch (e.kind_id == SymbolKind.TYPE)
                {
                    case (true) {
                    switch (e.ts != (void*)0)
                    {
                        case (true) { -> this.lower((TypeSpec*)e.ts, false, 0); }
                        default {};
                    };
                    m = sym_mangled(e);
                    p = nm_get(this.aliases, m);
                    ffree(m);
                    switch (p != (void*)0)
                    {
                        case (true) { -> (IRType*)p; }
                        default {};
                    };
                    -> (IRType*)0;
                }
                    default {};
                };
                switch (e.kind_id == SymbolKind.TRAIT)
                {
                    case (true) {
                    this.fail(g"trait cannot be used in type contexts\0", 0);
                    -> (IRType*)0;
                }
                    default {};
                };
                -> this.type_of_symbol(e);
            };

            // Array element count of a size node: literal value, or identifier resolved
            // as a constant. Returns false when the size is not a compile time constant.
            dim_value(Node* d, i64* out) -> bool
            {
                switch (d.kind == NodeKind.LITERAL)
                {
                    case (true) {
                    out[0] = d.ival;
                    -> true;
                }
                    default {};
                };
                switch (d.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (d.text != (byte*)0)
                    {
                        case (true) { -> this.resolve_dim(d.text, out); }
                        default {};
                    };
                }
                    default {};
                };
                -> false;
            };

            // TypeSystem.get_llvm_type. incl wraps the array dimensions.
            lower(TypeSpec* t, bool incl, int line) -> IRType*
            {
                IRType* base = (IRType*)0;
                IRType* el;
                IRType** ps;
                int i, depth, bt;
                i64 dv;
                bool wrap_i8;

                bt = t.base_type;
                switch (bt == DataType.FUNC_PTR)
                {
                    case (true) {
                    ps = (IRType**)fmalloc((u64)(t.fp_nparams + 1) * (u64)((sizeof(IRType*) + 7) / 8));
                    this.keep((void*)ps);
                    while (i < t.fp_nparams)
                    {
                        ps[i] = this.lower(t.fp_params[i], false, line);
                        i++;
                    };
                    -> this.ptr_of(this.mod.t_func(this.lower(t.fp_ret, false, line), ps, t.fp_nparams, false));
                }
                    default {};
                };

                switch (t.custom_typename != (byte*)0)
                {
                    case (true) {
                    base = this.resolve_custom(t.custom_typename);
                    switch (base == (IRType*)0)
                    {
                        case (true) {
                        this.fail(join3(g"Unknown type: \0", t.custom_typename, g"\0"), line);
                        -> this.t_i32;
                    }
                        default {};
                    };
                    switch (base.kind == LK.ARRAY & !ts_is_array(t))
                    {
                        case (true) { base = this.ptr_of(base.elem); }
                        default {};
                    };
                }
                    default {
                        switch (bt == DataType.SINT | bt == DataType.UINT)
                        {
                            case (true) { base = this.t_i32; }
                            default {
                                switch (bt == DataType.FLOAT)
                                {
                                    case (true) { base = this.t_float; }
                                    default {
                                        switch (bt == DataType.DOUBLE)
                                        {
                                            case (true) { base = this.t_double; }
                                            default {
                                                switch (bt == DataType.SLONG | bt == DataType.ULONG)
                                                {
                                                    case (true) { base = this.t_i64; }
                                                    default {
                                                        switch (bt == DataType.BOOL)
                                                        {
                                                            case (true) { base = this.t_i1; }
                                                            default {
                                                                switch (bt == DataType.CHAR)
                                                                {
                                                                    case (true) { base = this.t_i8; }
                                                                    default {
                                                                        switch (bt == DataType.BYTE)
                                                                        {
                                                                            case (true) {
                    switch (t.bit_width > 0)
                    {
                        case (true) { base = this.mod.t_int(t.bit_width); }
                        default { base = this.mod.t_int(this.byte_width); };
                    };
                }
                                                                            default {
                                                                                switch (bt == DataType.STRUCT | bt == DataType.OBJECT)
                                                                                {
                                                                                    case (true) { base = this.t_i8; }
                                                                                    default {
                                                                                        switch (bt == DataType.ENUM)
                                                                                        {
                                                                                            case (true) { base = this.t_i32; }
                                                                                            default {
                                                                                                switch (bt == DataType.VOID)
                                                                                                {
                                                                                                    case (true) { base = this.t_void; }
                                                                                                    default {
                                                                                                        switch (bt == DataType.DATA)
                                                                                                        {
                                                                                                            case (true) {
                    switch (t.bit_width <= 0)
                    {
                        case (true) {
                        this.fail(g"DATA type missing bit_width\0", line);
                        -> this.t_i32;
                    }
                        default {};
                    };
                    base = this.mod.t_int(t.bit_width);
                }
                                                                                                            default {
                                                                                                                switch (bt == DataType.DICT)
                                                                                                                {
                                                                                                                    case (true) {
                    IRType* kt = this.t_i8;
                    IRType* vt = this.t_i8;
                    int cap = 0;
                    switch (t.dict_capacity > 0)
                    {
                        case (true) { cap = t.dict_capacity; }
                        default {};
                    };
                    switch (t.dict_key != (TypeSpec*)0)
                    {
                        case (true) { kt = this.lower(t.dict_key, false, line); }
                        default {};
                    };
                    switch (t.dict_value != (TypeSpec*)0)
                    {
                        case (true) { vt = this.lower(t.dict_value, false, line); }
                        default {};
                    };
                    ps = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                    this.keep((void*)ps);
                    ps[0] = this.mod.t_array(kt, cap);
                    ps[1] = this.mod.t_array(vt, cap);
                    ps[2] = this.t_i32;
                    base = this.mod.t_struct(ps, 3);
                }
                                                                                                                    default {
                                                                                                                        switch (bt == DataType.THIS)
                                                                                                                        {
                                                                                                                            case (true) {
                    switch (this.cur_obj != (byte*)0)
                    {
                        case (true) {
                        base = this.ptr_of(this.mod.t_named(this.cur_obj));
                    }
                        default { base = this.t_i8p; };
                    };
                }
                                                                                                                            default {
                    this.fail(g"Unsupported type\0", line);
                    -> this.t_i32;
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

                el = base;
                switch (ts_is_pointer(t))
                {
                    case (true) {
                    depth = t.pointer_depth;
                    switch (depth <= 0)
                    {
                        case (true) { depth = 1; }
                        default {};
                    };
                    wrap_i8 = (bt == DataType.VOID | bt == DataType.STRUCT | bt == DataType.OBJECT);
                    switch (wrap_i8)
                    {
                        case (true) { el = this.t_i8; }
                        default {};
                    };
                    i = 0;
                    while (i < depth)
                    {
                        el = this.ptr_of(el);
                        i++;
                    };
                }
                    default {};
                };

                switch (!incl)
                {
                    case (true) { -> el; }
                    default {};
                };

                switch (ts_is_array(t))
                {
                    case (true) {
                    switch (t.array_dims != (NodeVec*)0)
                    {
                        case (true) {
                        switch (t.array_dims.len > 0)
                        {
                            case (true) {
                            IRType* cur = el;
                            Node* d;
                            i = t.array_dims.len - 1;
                            while (i >= 0)
                            {
                                d = t.array_dims.items[i];
                                switch (d != (Node*)0)
                                {
                                    case (true) {
                                    switch (this.dim_value(d, @dv))
                                    {
                                        case (true) { cur = this.mod.t_array(cur, (int)dv); }
                                        default { -> this.ptr_of(el); };
                                    };
                                }
                                    default { cur = this.ptr_of(cur); };
                                };
                                i--;
                            };
                            -> cur;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (t.array_size != (Node*)0)
                    {
                        case (true) {
                        switch (this.dim_value(t.array_size, @dv))
                        {
                            case (true) { -> this.mod.t_array(el, (int)dv); }
                            default {};
                        };
                        -> this.ptr_of(el);
                    }
                        default {};
                    };
                    switch (el.kind == LK.PTR)
                    {
                        case (true) { -> el; }
                        default {};
                    };
                    -> this.ptr_of(el);
                }
                    default {};
                };
                -> el;
            };

            // convert_type_spec_to_llvm: dicts are passed by pointer
            lower_sig(TypeSpec* t, int line) -> IRType*
            {
                IRType* b;
                switch (t.base_type == DataType.DICT)
                {
                    case (true) {
                    b = this.lower(t, true, line);
                    switch (ts_is_pointer(t))
                    {
                        case (true) { -> b; }
                        default {};
                    };
                    -> this.ptr_of(b);
                }
                    default {};
                };
                -> this.lower(t, true, line);
            };

            // ----------------------------------------------------------
            // Struct and object types
            // ----------------------------------------------------------

            new_sinfo(byte* name, int n, bool is_object) -> SInfo*
            {
                SInfo* si = (SInfo*)fmalloc((u64)((sizeof(SInfo) + 7) / 8));
                si.name = this.mod.own(name);
                si.ty = this.mod.t_named(name);
                si.n = n;
                si.names = (byte**)fmalloc((u64)(n + 1) * (u64)((sizeof(byte*) + 7) / 8));
                si.specs = (TypeSpec**)fmalloc((u64)(n + 1) * (u64)((sizeof(TypeSpec*) + 7) / 8));
                si.ftys = (IRType**)fmalloc((u64)(n + 1) * (u64)((sizeof(IRType*) + 7) / 8));
                si.offs = (int*)fmalloc((u64)(n + 1) * (u64)((sizeof(int) + 7) / 8));
                si.bits = (int*)fmalloc((u64)(n + 1) * (u64)((sizeof(int) + 7) / 8));
                si.aligns = (int*)fmalloc((u64)(n + 1) * (u64)((sizeof(int) + 7) / 8));
                si.total_bits = 0;
                si.max_align = 1;
                si.is_object = is_object;
                this.keep((void*)si.names);
                this.keep((void*)si.specs);
                this.keep((void*)si.ftys);
                this.keep((void*)si.offs);
                this.keep((void*)si.bits);
                this.keep((void*)si.aligns);
                this.keep((void*)si);
                nm_put(this.structs, si.name, (void*)si);
                -> si;
            };

            // Text of the {total_bits, field_count, [fields]} TLD constant and its type
            tld_global(SInfo* si) -> void
            {
                IRType* ft;
                IRType* at;
                IRType* vt;
                IRType** parts;
                int i;
                byte* nm;
                IRGlobal* g;
                parts = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)parts);
                parts[0] = this.t_i32;
                parts[1] = this.t_i32;
                parts[2] = this.t_i32;
                ft = this.mod.t_struct(parts, 3);
                at = this.mod.t_array(ft, si.n);
                parts = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)parts);
                parts[0] = this.t_i32;
                parts[1] = this.t_i32;
                parts[2] = at;
                vt = this.mod.t_struct(parts, 3);

                this.sc.clear();
                this.sc.put_str(g"{i32 \0");
                this.sc.put_int(si.total_bits);
                this.sc.put_str(g", i32 \0");
                this.sc.put_int(si.n);
                this.sc.put_str(g", \0");
                lt_text(@this.sc, at);
                this.sc.put_str(g" [\0");
                while (i < si.n)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sc.put_str(g", \0"); }
                        default {};
                    };
                    lt_text(@this.sc, ft);
                    this.sc.put_str(g" {i32 \0");
                    this.sc.put_int(si.offs[i]);
                    this.sc.put_str(g", i32 \0");
                    this.sc.put_int(si.bits[i]);
                    this.sc.put_str(g", i32 \0");
                    this.sc.put_int(si.aligns[i]);
                    this.sc.put(125);
                    i++;
                };
                this.sc.put_str(g"]}\0");
                nm = join3(si.name, g".TLD\0", g"\0");
                g = this.mod.add_global(vt, nm, this.sc.mem);
                g.linkage = this.mod.own(g"internal\0");
                g.constant = true;
                ffree(nm);
                ->;
            };

            // Prepends or appends the fields of the base structs named in list slot
            struct_member_count(Node* sd) -> int
            {
                int total = node_count(sd, 0);
                int i, j;
                Node* b;
                void* p;
                SInfo* bi;
                while (i < node_count(sd, 1))
                {
                    b = node_child(sd, 1, i);
                    p = nm_get(this.structs, b.text);
                    switch (p != (void*)0)
                    {
                        case (true) {
                        bi = (SInfo*)p;
                        total = total + bi.n;
                    }
                        default {};
                    };
                    i++;
                };
                while (j < node_count(sd, 2))
                {
                    b = node_child(sd, 2, j);
                    p = nm_get(this.structs, b.text);
                    switch (p != (void*)0)
                    {
                        case (true) {
                        bi = (SInfo*)p;
                        total = total + bi.n;
                    }
                        default {};
                    };
                    j++;
                };
                -> total;
            };

            // visit_StructDef
            reg_struct(Node* sd, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, sd.text);
                int i, j, idx, total, nm_, k;
                Node* mem;
                Node* b;
                void* p;
                SInfo* si;
                SInfo* bi;
                IRType* ft;
                bool has_bits;

                switch (sd.l4 != (NodeVec*)0)
                {
                    case (true) {
                    switch (sd.l4.len > 0)
                    {
                        case (true) {
                        ffree(name);
                        ->;
                    }
                        default {};
                    };
                }
                    default {};
                };

                nm_ = node_count(sd, 0);
                p = nm_get(this.structs, name);
                switch (p != (void*)0)
                {
                    case (true) {
                    switch (nm_ == 0 & node_count(sd, 1) == 0 & node_count(sd, 2) == 0)
                    {
                        case (true) {
                        ffree(name);
                        ->;
                    }
                        default {};
                    };
                    si = (SInfo*)p;
                    switch (si.ty.defined & si.ty.nitems > 0)
                    {
                        case (true) {
                        ffree(name);
                        ->;
                    }
                        default {};
                    };
                }
                    default {};
                };

                total = this.struct_member_count(sd);
                switch (total == 0)
                {
                    case (true) {
                    switch (nm_get(this.structs, name) == (void*)0)
                    {
                        case (true) { this.new_sinfo(name, 0, false); }
                        default {};
                    };
                    ffree(name);
                    ->;
                }
                    default {};
                };
                si = this.new_sinfo(name, total, false);
                si.ty.defined = false;

                // Pre-body bases, then own members, then post bases
                i = 0;
                while (i < node_count(sd, 1))
                {
                    b = node_child(sd, 1, i);
                    p = nm_get(this.structs, b.text);
                    switch (p == (void*)0)
                    {
                        case (true) {
                        this.fail(join3(g"Struct composition: base struct '\0", b.text, g"' has not been defined\0"), sd.line);
                    }
                        default {
                        bi = (SInfo*)p;
                        k = 0;
                        while (k < bi.n)
                        {
                            si.names[idx] = bi.names[k];
                            si.specs[idx] = bi.specs[k];
                            idx++;
                            k++;
                        };
                    };
                    };
                    i++;
                };
                i = 0;
                while (i < nm_)
                {
                    mem = node_child(sd, 0, i);
                    si.names[idx] = mem.text;
                    si.specs[idx] = mem.ts;
                    idx++;
                    i++;
                };
                j = 0;
                while (j < node_count(sd, 2))
                {
                    b = node_child(sd, 2, j);
                    p = nm_get(this.structs, b.text);
                    switch (p == (void*)0)
                    {
                        case (true) {
                        this.fail(join3(g"Struct post-composition: struct '\0", b.text, g"' has not been defined\0"), sd.line);
                    }
                        default {
                        bi = (SInfo*)p;
                        k = 0;
                        while (k < bi.n)
                        {
                            si.names[idx] = bi.names[k];
                            si.specs[idx] = bi.specs[k];
                            idx++;
                            k++;
                        };
                    };
                    };
                    j++;
                };
                si.n = idx;

                // calculate_vtable: tightly packed, widths from the declared bit width
                // of scalar data{} members, else from the LLVM type
                int off = 0;
                int bw, al;
                i = 0;
                while (i < si.n)
                {
                    ft = this.lower(si.specs[i], true, sd.line);
                    si.ftys[i] = ft;
                    switch (si.specs[i].bit_width > 0 & !ts_is_array(si.specs[i]))
                    {
                        case (true) {
                        bw = si.specs[i].bit_width;
                        switch (si.specs[i].alignment > 0)
                        {
                            case (true) { al = si.specs[i].alignment; }
                            default { al = bw; };
                        };
                    }
                        default {
                        bw = bits_of(ft);
                        al = bw;
                        switch (bw > 64)
                        {
                            case (true) { al = 64; }
                            default {};
                        };
                    };
                    };
                    si.offs[i] = off;
                    si.bits[i] = bw;
                    si.aligns[i] = al;
                    off = off + bw;
                    switch (al > si.max_align)
                    {
                        case (true) { si.max_align = al; }
                        default {};
                    };
                    i++;
                };
                si.total_bits = off;
                this.mod.set_body(si.ty, si.ftys, si.n);
                this.tld_global(si);

                i = 0;
                while (i < node_count(sd, 3))
                {
                    this.reg_struct(node_child(sd, 3, i), ns);
                    i++;
                };
                ffree(name);
                ->;
            };

            // ObjectTypeHandler.create_member_types, create_struct_type, create_vtable
            reg_object_type(Node* od, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, od.text);
                int n = node_count(od, 0);
                int i, off, bw;
                void* p;
                SInfo* si;
                Node* mem;

                switch (this.is_template(od))
                {
                    case (true) {
                    ffree(name);
                    ->;
                }
                    default {};
                };

                p = nm_get(this.structs, name);
                switch (p != (void*)0)
                {
                    case (true) {
                    si = (SInfo*)p;
                    switch (n == 0 | si.n > 0)
                    {
                        case (true) {
                        ffree(name);
                        ->;
                    }
                        default {};
                    };
                }
                    default {};
                };

                switch (n == 0)
                {
                    case (true) {
                    switch (p == (void*)0)
                    {
                        case (true) {
                        si = this.new_sinfo(name, 0, true);
                        si.ty.defined = false;
                    }
                        default {};
                    };
                    ffree(name);
                    ->;
                }
                    default {};
                };

                switch (p == (void*)0)
                {
                    case (true) { si = this.new_sinfo(name, n, true); }
                    default {
                    si = (SInfo*)p;
                    si.n = n;
                    si.is_object = true;
                    si.names = (byte**)fmalloc((u64)(n + 1) * (u64)((sizeof(byte*) + 7) / 8));
                    si.specs = (TypeSpec**)fmalloc((u64)(n + 1) * (u64)((sizeof(TypeSpec*) + 7) / 8));
                    si.ftys = (IRType**)fmalloc((u64)(n + 1) * (u64)((sizeof(IRType*) + 7) / 8));
                    si.offs = (int*)fmalloc((u64)(n + 1) * (u64)((sizeof(int) + 7) / 8));
                    si.bits = (int*)fmalloc((u64)(n + 1) * (u64)((sizeof(int) + 7) / 8));
                    si.aligns = (int*)fmalloc((u64)(n + 1) * (u64)((sizeof(int) + 7) / 8));
                    this.keep((void*)si.names);
                    this.keep((void*)si.specs);
                    this.keep((void*)si.ftys);
                    this.keep((void*)si.offs);
                    this.keep((void*)si.bits);
                    this.keep((void*)si.aligns);
                };
                };
                si.ty.defined = false;

                i = 0;
                while (i < n)
                {
                    mem = node_child(od, 0, i);
                    si.names[i] = mem.text;
                    si.specs[i] = mem.ts;
                    si.ftys[i] = this.lower(mem.ts, true, od.line);
                    bw = obj_field_bits(si.ftys[i], @this.al_tmp);
                    si.offs[i] = off;
                    si.bits[i] = bw;
                    si.aligns[i] = this.al_tmp;
                    switch (this.al_tmp > si.max_align)
                    {
                        case (true) { si.max_align = this.al_tmp; }
                        default {};
                    };
                    off = off + bw;
                    i++;
                };
                si.total_bits = off;
                this.mod.set_body(si.ty, si.ftys, si.n);
                ffree(name);
                ->;
            };

            is_template(Node* od) -> bool
            {
                switch (od.d == (Node*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (od.d.l0 == (NodeVec*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> od.d.l0.len > 0;
            };

            // Types nested inside an object
            reg_object_nested(Node* od, byte* ns) -> void
            {
                int i;
                while (i < node_count(od, 4))
                {
                    this.reg_struct(node_child(od, 4, i), ns);
                    i++;
                };
                i = 0;
                while (i < node_count(od, 3))
                {
                    this.reg_object_type(node_child(od, 3, i), ns);
                    i++;
                };
                ->;
            };

            // ----------------------------------------------------------
            // Enums, unions, aliases
            // ----------------------------------------------------------

            reg_enum(Node* ed, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, ed.text);
                IRType* ty = this.t_i32;
                int i, n;
                byte* cn;
                byte* nmx;
                IRGlobal* g;
                IRValue* v;
                Node* item;
                switch (ed.ts != (TypeSpec*)0)
                {
                    case (true) { ty = this.lower(ed.ts, false, ed.line); }
                    default {};
                };
                nm_put(this.enums, name, (void*)ty);
                nm_put(this.enum_defs, name, (void*)ed);
                n = node_count(ed, 0);
                while (i < n)
                {
                    item = node_child(ed, 0, i);
                    cn = join3(name, g".\0", item.text);
                    switch (ty.kind == LK.STRUCT | ty.kind == LK.ISTRUCT | ty.kind == LK.ARRAY)
                    {
                        case (true) {
                        g = this.mod.add_global(ty, cn, g"zeroinitializer\0");
                    }
                        default {
                        v = this.mod.c_int(ty, item.ival);
                        g = this.mod.add_global(ty, cn, v.text);
                        g.constant = true;
                    };
                    };
                    i64* eb = (i64*)fmalloc((u64)8);
                    eb[0] = item.ival;
                    this.keep((void*)eb);
                    nm_put(this.enumvals, this.mod.own(cn), (void*)eb);
                    ffree(cn);
                    i++;
                };
                ffree(name);
                ->;
            };

            // Size in bytes the way visit_UnionDef computes it
            union_size(IRType* t) -> int
            {
                int total, i;
                IRType* e;
                switch (t.kind == LK.INT)
                {
                    case (true) { -> (t.width + 7) / 8; }
                    default {};
                };
                switch (t.kind == LK.FLOAT)
                {
                    case (true) { -> 4; }
                    default {};
                };
                switch (t.kind == LK.DOUBLE)
                {
                    case (true) { -> 8; }
                    default {};
                };
                switch (t.kind == LK.PTR)
                {
                    case (true) { -> 8; }
                    default {};
                };
                switch (t.kind == LK.ARRAY)
                {
                    case (true) {
                    e = t.elem;
                    switch (e.kind == LK.INT)
                    {
                        case (true) { -> ((e.width + 7) / 8) * t.count; }
                        default {};
                    };
                    switch (e.kind == LK.FLOAT)
                    {
                        case (true) { -> 4 * t.count; }
                        default {};
                    };
                    switch (e.kind == LK.DOUBLE)
                    {
                        case (true) { -> 8 * t.count; }
                        default {};
                    };
                    -> 8 * t.count;
                }
                    default {};
                };
                switch (t.kind == LK.STRUCT)
                {
                    case (true) {
                    while (i < t.nitems)
                    {
                        e = t.items[i];
                        switch (e.kind)
                        {
                            case (LK.INT) { total = total + (e.width + 7) / 8; }
                            case (LK.FLOAT) { total = total + 4; }
                            default { total = total + 8; };
                        };
                        i++;
                    };
                    -> total;
                }
                    default {};
                };
                -> 8;
            };

            reg_union(Node* ud, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, ud.text);
                int n = node_count(ud, 0);
                int i, sz, mx;
                IRType* mt;
                IRType* mxt = (IRType*)0;
                IRType** parts;
                Node* mem;
                nm_put(this.union_defs, name, (void*)ud);
                i = 0;
                while (i < n)
                {
                    mem = node_child(ud, 0, i);
                    mt = this.lower(mem.ts, false, ud.line);
                    sz = this.union_size(mt);
                    switch (sz > mx)
                    {
                        case (true) {
                        mx = sz;
                        mxt = mt;
                    }
                        default {};
                    };
                    i++;
                };
                parts = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)parts);
                switch (ud.text2 != (byte*)0)
                {
                    case (true) {
                    parts[0] = this.t_i32;
                    parts[1] = this.mod.t_array(this.t_i8, mx);
                    nm_put(this.unions, name, (void*)this.mod.t_struct(parts, 2));
                }
                    default {
                    switch (mxt == (IRType*)0)
                    {
                        case (true) { mxt = this.t_i8; }
                        default {};
                    };
                    parts[0] = mxt;
                    nm_put(this.unions, name, (void*)this.mod.t_struct(parts, 1));
                };
                };
                ffree(name);
                ->;
            };

            reg_alias(Node* td, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, td.text);
                IRType* ty = this.lower(td.ts, true, td.line);
                nm_put(this.aliases, name, (void*)ty);
                pv_push(this.al_names, (void*)this.mod.own(td.text));
                pv_push(this.al_tys, (void*)ty);
                pv_push(this.al_specs, (void*)td.ts);
                pv_push(this.al_idx, (void*)(i64)this.cur_stmt);
                ffree(name);
                ->;
            };

            // ----------------------------------------------------------
            // Functions
            // ----------------------------------------------------------

            cc_name(byte* cc) -> byte*
            {
                switch (cstr_eq(cc, g"cdecl\0"))
                {
                    case (true) { -> this.mod.own(g"ccc\0"); }
                    default {};
                };
                switch (cstr_eq(cc, g"stdcall\0"))
                {
                    case (true) { -> this.mod.own(g"x86_stdcallcc\0"); }
                    default {};
                };
                switch (cstr_eq(cc, g"fastcall\0"))
                {
                    case (true) { -> this.mod.own(g"fastcc\0"); }
                    default {};
                };
                switch (cstr_eq(cc, g"thiscall\0"))
                {
                    case (true) { -> this.mod.own(g"x86_thiscallcc\0"); }
                    default {};
                };
                switch (cstr_eq(cc, g"vectorcall\0"))
                {
                    case (true) { -> this.mod.own(g"x86_vectorcallcc\0"); }
                    default {};
                };
                -> this.mod.own(cc);
            };

            // Heap array of the parameter TypeSpecs of a function node
            param_specs(Node* fd) -> TypeSpec**
            {
                int n = node_count(fd, 0);
                int i;
                TypeSpec** ps = (TypeSpec**)fmalloc((u64)(n + 1) * (u64)((sizeof(TypeSpec*) + 7) / 8));
                this.keep((void*)ps);
                while (i < n)
                {
                    ps[i] = node_child(fd, 0, i).ts;
                    i++;
                };
                -> ps;
            };

            mangled_name(byte* base, Node* fd) -> byte*
            {
                this.sc.clear();
                mangle_function(@this.sc, base, this.param_specs(fd), node_count(fd, 0), fd.ts);
                -> ts_dup(this.sc.mem);
            };

            // Names the arguments of a function the way visit_FunctionDef does
            name_args(IRFunc* f, Node* fd, int skip) -> void
            {
                int i;
                Node* p;
                while (i < f.nargs - skip)
                {
                    p = node_child(fd, 0, i);
                    switch (p.text != (byte*)0)
                    {
                        case (true) { this.mod.name_arg(f, i + skip, p.text); }
                        default {
                        this.sc.clear();
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(i);
                        this.mod.name_arg(f, i + skip, this.sc.mem);
                    };
                    };
                    i++;
                };
                ->;
            };

            // Function type of a FUNCTION_DEF (dual return folds into a struct)
            func_type_of(Node* fd, int skip, IRType* first) -> IRType*
            {
                int n = node_count(fd, 0);
                IRType* ret = this.lower_sig(fd.ts, fd.line);
                IRType** ps;
                IRType** rp;
                int i;
                switch (fd.ts2 != (TypeSpec*)0)
                {
                    case (true) {
                    rp = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                    this.keep((void*)rp);
                    rp[0] = ret;
                    rp[1] = this.lower_sig(fd.ts2, fd.line);
                    rp[2] = this.t_i1;
                    ret = this.mod.t_struct(rp, 3);
                }
                    default {};
                };
                ps = (IRType**)fmalloc((u64)(n + skip + 1) * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)ps);
                switch (skip > 0)
                {
                    case (true) { ps[0] = first; }
                    default {};
                };
                while (i < n)
                {
                    ps[i + skip] = this.lower_sig(node_child(fd, 0, i).ts, fd.line);
                    i++;
                };
                -> this.mod.t_func(ret, ps, n + skip, (fd.flags `& NF_VARIADIC) != 0);
            };

            // visit_FunctionDef up to the point a body would be emitted
            declare_function(Node* fd, byte* ns) -> IRFunc*
            {
                switch (fd.text == (byte*)0)
                {
                    case (true) { -> (IRFunc*)0; }
                    default {};
                };
                switch ((fd.flags `& NF_TEMPLATE) != 0)
                {
                    case (true) { -> (IRFunc*)0; }
                    default {};
                };
                IRType* ft = this.func_type_of(fd, 0, (IRType*)0);
                byte* base = mangle_namespace_name(ns, fd.text);
                byte* mn;
                IRFunc* f;
                IRFunc* ex;
                bool proto = (fd.flags `& NF_PROTOTYPE) != 0;
                switch ((fd.flags `& NF_NO_MANGLE) != 0)
                {
                    case (true) { mn = ts_dup(base); }
                    default { mn = this.mangled_name(base, fd); };
                };
                ex = this.mod.find_function(mn);
                switch (ex != (IRFunc*)0)
                {
                    case (true) {
                    switch (proto)
                    {
                        case (true) { f = ex; }
                        default {
                            switch (ex.is_decl & ex.nargs == node_count(fd, 0))
                            {
                                case (true) { f = ex; }
                                default {
                        switch (nm_has(this.defined, mn))
                        {
                            case (true) {
                            this.fail(join3(g"Function '\0", fd.text, g"' redefined\0"), fd.line);
                            ffree(base);
                            ffree(mn);
                            -> ex;
                        }
                            default {};
                        };
                        byte* dn = join3(mn, g"__\0", g"args\0");
                        f = this.mod.find_function(dn);
                        switch (f == (IRFunc*)0)
                        {
                            case (true) { f = this.mod.add_function(ft, dn); }
                            default {};
                        };
                        ffree(dn);
                    };
                            };
                        };
                    };
                }
                    default {
                    f = this.mod.add_function(ft, mn);
                    this.nfuncs++;
                };
                };
                switch (fd.text2 != (byte*)0)
                {
                    case (true) { f.cconv = this.cc_name(fd.text2); }
                    default {};
                };
                switch (!proto)
                {
                    case (true) {
                    nm_put(this.defined, mn, (void*)f);
                    nm_put(this.fdefs, f.name, (void*)fd);
                    switch ((fd.flags `& NF_INLINE) != 0)
                    {
                        case (true) { pv_push(f.attrs, (void*)this.mod.own(g"alwaysinline\0")); }
                        default {};
                    };
                    this.name_args(f, fd, 0);
                }
                    default {};
                };
                ffree(base);
                ffree(mn);
                -> f;
            };

            // visit_ExternBlock declaration
            declare_extern(Node* fd, byte* ns) -> void
            {
                IRType* ft;
                byte* base;
                byte* fin;
                IRFunc* f;
                IRType* vt;
                IRGlobal* g;
                switch (fd.kind == NodeKind.VARIABLE_DECLARATION)
                {
                    case (true) {
                    vt = this.lower(fd.ts, false, fd.line);
                    switch (this.mod.find_global(fd.text) == (IRGlobal*)0)
                    {
                        case (true) {
                        g = this.mod.add_global(vt, fd.text, (byte*)0);
                        g.linkage = this.mod.own(g"external\0");
                    }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                switch (fd.text == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch ((fd.flags `& NF_PROTOTYPE) == 0)
                {
                    case (true) {
                    this.fail(join3(g"Extern functions must be prototypes: \0", fd.text, g"\0"), fd.line);
                    ->;
                }
                    default {};
                };
                ft = this.extern_type(fd);
                base = ts_dup(fd.text);
                int cut = 0;
                int k = 0;
                while (base[k] != 0)
                {
                    switch (base[k] == ':' & base[k + 1] == ':')
                    {
                        case (true) { cut = k + 2; }
                        default {};
                    };
                    k++;
                };
                byte* b1 = dup_from(base, cut);
                k = 0;
                cut = 0;
                while (b1[k] != 0)
                {
                    switch (b1[k] == '_' & b1[k + 1] == '_')
                    {
                        case (true) { cut = k + 2; }
                        default {};
                    };
                    k++;
                };
                byte* b2 = dup_from(b1, cut);
                switch ((fd.flags `& NF_NO_MANGLE) != 0)
                {
                    case (true) { fin = ts_dup(b2); }
                    default { fin = this.mangled_name(b2, fd); };
                };
                f = this.mod.find_function(fin);
                switch (f == (IRFunc*)0)
                {
                    case (true) {
                    f = this.mod.add_function(ft, fin);
                    this.nfuncs++;
                }
                    default {};
                };
                f.linkage = this.mod.own(g"external\0");
                this.name_args(f, fd, 0);
                ffree(base);
                ffree(b1);
                ffree(b2);
                ffree(fin);
                ->;
            };

            // Extern prototypes lower without the dict/dual-return handling
            extern_type(Node* fd) -> IRType*
            {
                int n = node_count(fd, 0);
                int i;
                IRType** ps = (IRType**)fmalloc((u64)(n + 1) * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)ps);
                while (i < n)
                {
                    ps[i] = this.lower(node_child(fd, 0, i).ts, false, fd.line);
                    i++;
                };
                -> this.mod.t_func(this.lower(fd.ts, false, fd.line), ps, n, false);
            };

            // ObjectTypeHandler.create_method_signature and predeclare_method
            declare_method(Node* od, Node* m, byte* obj_name) -> void
            {
                IRType* st_ty = this.mod.t_named(obj_name);
                IRType* self_ty = this.ptr_of(st_ty);
                byte* prev = this.cur_obj;
                IRType* ft;
                IRFunc* f;
                byte* mn;
                byte* full;
                byte* mid;
                switch (m.text == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch ((m.flags `& NF_TEMPLATE) != 0)
                {
                    case (true) { ->; }
                    default {};
                };
                this.cur_obj = this.mod.own(obj_name);
                switch (m.ts.base_type)
                {
                    case (DataType.THIS)
                    {
                        IRType** ps = (IRType**)fmalloc((u64)(node_count(m, 0) + 2) * (u64)((sizeof(IRType*) + 7) / 8));
                        this.keep((void*)ps);
                        int i;
                        ps[0] = self_ty;
                        while (i < node_count(m, 0))
                        {
                            ps[i + 1] = this.lower_sig(node_child(m, 0, i).ts, m.line);
                            i++;
                        };
                        ft = this.mod.t_func(self_ty, ps, node_count(m, 0) + 1, false);
                    }
                    default
                    {
                        ft = this.func_type_of(m, 1, self_ty);
                    };
                };
                mn = this.mangled_name(m.text, m);
                full = join3(obj_name, g".\0", mn);
                f = this.mod.find_function(full);
                switch (f == (IRFunc*)0)
                {
                    case (true) {
                    f = this.mod.add_function(ft, full);
                    this.nfuncs++;
                }
                    default {};
                };
                this.mod.name_arg(f, 0, g"this\0");
                this.name_args(f, m, 1);
                switch (m.text2 != (byte*)0)
                {
                    case (true) { f.cconv = this.cc_name(m.text2); }
                    default {};
                };
                ffree(mn);
                ffree(full);
                this.cur_obj = prev;
                ->;
            };

            declare_object_methods(Node* od, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, od.text);
                int i;
                Node* m;
                switch (this.is_template(od))
                {
                    case (true) {
                    ffree(name);
                    ->;
                }
                    default {};
                };
                while (i < node_count(od, 1))
                {
                    m = node_child(od, 1, i);
                    this.declare_method(od, m, name);
                    i++;
                };
                ffree(name);
                ->;
            };

            // ----------------------------------------------------------
            // Program walk
            // ----------------------------------------------------------

            unwrap(Node* n) -> Node*
            {
                int k = n.kind;
                switch (k == NodeKind.FUNCTION_DEF_STATEMENT | k == NodeKind.STRUCT_DEF_STATEMENT |
                    k == NodeKind.OBJECT_DEF_STATEMENT | k == NodeKind.ENUM_DEF_STATEMENT |
                    k == NodeKind.UNION_DEF_STATEMENT | k == NodeKind.NAMESPACE_DEF_STATEMENT)
                {
                    case (true) {
                    -> n.a;
                }
                    default {};
                };
                -> n;
            };

            // Visit order of namespace members (visit_NamespaceDef): nested namespaces,
            // enums, structs, objects for types; nested, externs, objects, functions
            // for declarations
            slot_at(int j, bool types) -> int
            {
                switch (types)
                {
                    case (true) {
                    switch (j == 0)
                    {
                        case (true) { -> 7; }
                        default {};
                    };
                    switch (j == 1)
                    {
                        case (true) { -> 3; }
                        default {};
                    };
                    switch (j == 2)
                    {
                        case (true) { -> 1; }
                        default {};
                    };
                    -> 2;
                }
                    default {};
                };
                switch (j == 0)
                {
                    case (true) { -> 7; }
                    default {};
                };
                switch (j == 1)
                {
                    case (true) { -> 5; }
                    default {};
                };
                switch (j == 2)
                {
                    case (true) { -> 2; }
                    default {};
                };
                -> 0;
            };

            // Registers every type declared in n
            types_pass(Node* n0, byte* ns) -> void
            {
                Node* n = this.unwrap(n0);
                int k = n.kind;
                int s, c, e;
                byte* full;
                switch (k)
                {
                    case (NodeKind.STRUCT_DEF) { this.reg_struct(n, ns); }
                    case (NodeKind.OBJECT_DEF)
                    {
                        this.reg_object_type(n, ns);
                        this.reg_object_nested(n, ns);
                    }
                    case (NodeKind.ENUM_DEF) { this.reg_enum(n, ns); }
                    case (NodeKind.UNION_DEF) { this.reg_union(n, ns); }
                    case (NodeKind.TYPE_DECLARATION) { this.reg_alias(n, ns); }
                    case (NodeKind.NAMESPACE_DEF)
                    {
                        full = this.join_ns(ns, n.text);
                        this.set_ns(full);
                        int j;
                        while (j < 4)
                        {
                            s = this.slot_at(j, true);
                            c = this.ns_count(n, s);
                            e = 0;
                            while (e < c)
                            {
                                this.types_pass(this.ns_child(n, s, e), full);
                                e++;
                            };
                            j++;
                        };
                        this.set_ns(ns);
                        ffree(full);
                    }
                    default {};
                };
                ->;
            };

            // Declares every function, method and extern in n
            decls_pass(Node* n0, byte* ns) -> void
            {
                Node* n = this.unwrap(n0);
                int k = n.kind;
                int s, c, e;
                byte* full;
                switch (k == NodeKind.FUNCTION_DEF)
                {
                    case (true) { this.declare_function(n, ns); }
                    default {
                        switch (k == NodeKind.VARIABLE_DECLARATION | k == NodeKind.FUNCTION_POINTER_DECLARATION)
                        {
                            case (true) { this.declare_global(n, ns); }
                            default {
                                switch (k == NodeKind.OBJECT_DEF)
                                {
                                    case (true) { this.declare_object_methods(n, ns); }
                                    default {
                                        switch (k == NodeKind.EXTERN_BLOCK)
                                        {
                                            case (true) {
                    c = node_count(n, 0);
                    while (e < c)
                    {
                        this.declare_extern(node_child(n, 0, e), ns);
                        e++;
                    };
                }
                                            default {
                                                switch (k == NodeKind.EXPORT_BLOCK)
                                                {
                                                    case (true) {
                    c = node_count(n, 0);
                    while (e < c)
                    {
                        this.declare_function(node_child(n, 0, e), ns);
                        e++;
                    };
                }
                                                    default {
                                                        switch (k == NodeKind.NAMESPACE_DEF)
                                                        {
                                                            case (true) {
                    full = this.join_ns(ns, n.text);
                    this.set_ns(full);
                    int j;
                    while (j < 4)
                    {
                        switch (j == 1)
                        {
                            case (true) {
                            c = this.ns_count(n, 6);
                            e = 0;
                            while (e < c)
                            {
                                switch (this.ns_child(n, 6, e).kind == NodeKind.VARIABLE_DECLARATION)
                                {
                                    case (true) {
                                    this.declare_global(this.ns_child(n, 6, e), full);
                                }
                                    default {};
                                };
                                e++;
                            };
                        }
                            default {};
                        };
                        s = this.slot_at(j, false);
                        c = this.ns_count(n, s);
                        e = 0;
                        while (e < c)
                        {
                            this.decls_pass(this.ns_child(n, s, e), full);
                            e++;
                        };
                        j++;
                    };
                    this.set_ns(ns);
                    ffree(full);
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
                        };
                    };
                };
                ->;
            };

            // ----------------------------------------------------------
            // Function bodies (stage B)
            // ----------------------------------------------------------

            // Marks the current body as not generated. what names the construct.
            unsup(Node* n, byte* what) -> void
            {
                i64* box;
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                this.bad = true;
                this.bad_what = what;
                switch (n != (Node*)0)
                {
                    case (true) { this.bad_line = n.line; }
                    default {};
                };
                box = (i64*)nm_get(this.ucounts, what);
                switch (box == (i64*)0)
                {
                    case (true) {
                    box = (i64*)fmalloc((u64)8);
                    this.keep((void*)box);
                    *box = (i64)0;
                    nm_put(this.ucounts, what, (void*)box);
                }
                    default {};
                };
                *box = *box + (i64)1;
                ->;
            };

            push_scope() -> void
            {
                pv_push(this.scopes, (void*)nm_new());
                ->;
            };

            pop_scope() -> void
            {
                nm_free((NameMap*)this.scopes.items[this.scopes.len - 1]);
                this.scopes.len = this.scopes.len - 1;
                ->;
            };

            define_var(byte* name, IRValue* ptr, TypeSpec* ts) -> LVar*
            {
                LVar* v = (LVar*)fmalloc((u64)((sizeof(LVar) + 7) / 8));
                v.ptr = ptr;
                v.ts = ts;
                v.vol = false;
                this.keep((void*)v);
                nm_put((NameMap*)this.scopes.items[this.scopes.len - 1], name, (void*)v);
                -> v;
            };

            find_local(byte* name) -> LVar*
            {
                int i = this.scopes.len - 1;
                void* p;
                while (i >= 0)
                {
                    p = nm_get((NameMap*)this.scopes.items[i], name);
                    switch (p != (void*)0)
                    {
                        case (true) { -> (LVar*)p; }
                        default {};
                    };
                    i--;
                };
                -> (LVar*)0;
            };

            find_var(byte* name) -> LVar*
            {
                LVar* lv = this.find_local(name);
                switch (lv != (LVar*)0)
                {
                    case (true) { -> lv; }
                    default {};
                };
                -> this.find_global_var(name);
            };

            // Global variable visible as name (module.globals, then the namespace resolution)
            find_global_var(byte* name) -> LVar*
            {
                FXC_SYMENTRY* e = st_lookup_any(this.st, name, this.cur_ns);
                byte* m;
                IRGlobal* gl;
                LVar* v;
                void* p;
                switch (e == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> (LVar*)nm_get(this.gvars, name); }
                    default {};
                };
                switch (e.kind_id != SymbolKind.VARIABLE)
                {
                    case (true) { -> (LVar*)nm_get(this.gvars, name); }
                    default {};
                };
                m = sym_mangled(e);
                gl = this.mod.find_global(m);
                switch (gl == (IRGlobal*)0)
                {
                    case (true) {
                    ffree(m);
                    -> (LVar*)0;
                }
                    default {};
                };
                p = nm_get(this.gvars, m);
                switch (p != (void*)0)
                {
                    case (true) {
                    ffree(m);
                    -> (LVar*)p;
                }
                    default {};
                };
                v = (LVar*)fmalloc((u64)((sizeof(LVar) + 7) / 8));
                v.ptr = gl.self;
                v.ts = (TypeSpec*)e.ts;
                v.vol = false;
                this.keep((void*)v);
                nm_put(this.gvars, m, (void*)v);
                ffree(m);
                -> v;
            };

            // Counts a construct that stopped something other than a body
            note_unsup(byte* what) -> void
            {
                i64* box = (i64*)nm_get(this.ucounts, what);
                switch (box == (i64*)0)
                {
                    case (true) {
                    box = (i64*)fmalloc((u64)8);
                    this.keep((void*)box);
                    *box = (i64)0;
                    nm_put(this.ucounts, what, (void*)box);
                }
                    default {};
                };
                *box = *box + (i64)1;
                ->;
            };

            // Last "__" separated segment of name
            last_seg(byte* name) -> byte*
            {
                int i;
                int cut;
                while (name[i] != 0)
                {
                    switch (name[i] == '_' & name[i + 1] == '_')
                    {
                        case (true) { cut = i + 2; }
                        default {};
                    };
                    i++;
                };
                -> name + cut;
            };

            // _vardecl_global duplicate check: same name, or same last segment
            global_dup(byte* name) -> bool
            {
                int i;
                byte* seg = this.last_seg(name);
                IRGlobal* g;
                IRFunc* fn;
                while (i < this.mod.globals.len)
                {
                    g = (IRGlobal*)this.mod.globals.items[i];
                    switch (cstr_eq(g.name, name))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    switch (cstr_eq(this.last_seg(g.name), seg))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < this.mod.funcs.len)
                {
                    fn = (IRFunc*)this.mod.funcs.items[i];
                    switch (cstr_eq(fn.name, name))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    switch (cstr_eq(this.last_seg(fn.name), seg))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // Initializer text of a global (create_global_initializer for literals),
            // null when the initializer is not handled yet
            global_init(Node* n, IRType* lt) -> byte*
            {
                Node* ini = n.a;
                int dt;
                i64 v;
                i64 mask;
                int w;
                byte* r;
                bool neg = false;
                switch (ini == (Node*)0)
                {
                    case (true) { -> this.mod.c_null(lt).text; }
                    default {};
                };
                switch (ini.kind == NodeKind.NO_INIT)
                {
                    case (true) { -> g"undef\0"; }
                    default {};
                };
                switch (ini.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    r = this.global_ident_init(ini.text);
                    switch (r == (byte*)0)
                    {
                        case (true) { -> this.mod.c_null(lt).text; }
                        default {};
                    };
                    -> r;
                }
                    default {};
                };
                switch (ini.kind == NodeKind.STRING_LITERAL)
                {
                    case (true) { -> this.global_string_init(ini, lt); }
                    default {};
                };
                switch (ini.kind == NodeKind.ARRAY_LITERAL)
                {
                    case (true) { -> this.global_array_init(ini, lt); }
                    default {};
                };
                switch (ini.kind == NodeKind.CAST_EXPRESSION | ini.kind == NodeKind.FUNCTION_CALL | ini.kind == NodeKind.METHOD_CALL)
                {
                    case (true) {
                    // The base has no constant for these and falls back to the default initializer
                    -> this.mod.c_null(lt).text;
                }
                    default {};
                };
                switch (ini.kind == NodeKind.CAST_EXPRESSION & lt.kind == LK.PTR)
                {
                    case (true) {
                    switch (ini.a != (Node*)0)
                    {
                        case (true) {
                        switch (ini.a.kind == NodeKind.ADDRESS_OF & ini.a.a != (Node*)0)
                        {
                            case (true) {
                            switch (ini.a.a.kind == NodeKind.LITERAL & ini.a.a.op == DataType.VOID)
                            {
                                case (true) { -> g"null\0"; }
                                default {};
                            };
                        }
                            default {};
                        };
                        switch (ini.a.kind == NodeKind.IDENTIFIER & ini.a.text != (byte*)0)
                        {
                            case (true) {
                            FXC_SYMENTRY* se = st_lookup_any(this.st, ini.a.text, this.cur_ns);
                            switch (se != (FXC_SYMENTRY*)0)
                            {
                                case (true) {
                                byte* sm = sym_mangled(se);
                                IRGlobal* sg = this.mod.find_global(sm);
                                ffree(sm);
                                switch (sg != (IRGlobal*)0)
                                {
                                    case (true) {
                                    switch (sg.init != (byte*)0)
                                    {
                                        case (true) {
                                        switch (cstr_eq(sg.init, g"null\0"))
                                        {
                                            case (true) { -> g"null\0"; }
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
                        switch (ini.a.kind == NodeKind.LITERAL & ini.a.ival == (i64)0 & (ini.a.op == DataType.SINT | ini.a.op == DataType.UINT | ini.a.op == DataType.ULONG | ini.a.op == DataType.SLONG))
                        {
                            case (true) {
                            -> g"null\0";
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (ini.kind == NodeKind.UNARY_OP)
                {
                    case (true) {
                    switch (ini.op == Operator.SUB & ini.a != (Node*)0)
                    {
                        case (true) {
                        switch (ini.a.kind == NodeKind.LITERAL)
                        {
                            case (true) {
                            neg = true;
                            ini = ini.a;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (ini.kind != NodeKind.LITERAL)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                dt = ini.op;
                v = ini.ival;
                switch (neg)
                {
                    case (true) {
                    switch (dt != DataType.SINT & dt != DataType.FLOAT & dt != DataType.DOUBLE)
                    {
                        case (true) { -> (byte*)0; }
                        default {};
                    };
                    v = (i64)0 - v;
                }
                    default {};
                };
                switch (dt == DataType.FLOAT | dt == DataType.DOUBLE)
                {
                    case (true) {
                    switch (lt.kind == LK.FLOAT | lt.kind == LK.DOUBLE)
                    {
                        case (true) { switch (neg)
 {
     case (true) { -> this.mod.c_fp(lt, (double)0.0 - ini.fval).text; }
     default {};
 }; -> this.mod.c_fp(lt, ini.fval).text; }
                        default {};
                    };
                    -> (byte*)0;
                }
                    default {};
                };
                switch (lt.kind == LK.PTR)
                {
                    case (true) {
                    switch (dt == DataType.SINT & v == (i64)0)
                    {
                        case (true) { -> g"null\0"; }
                        default {};
                    };
                    -> (byte*)0;
                }
                    default {};
                };
                switch (lt.kind != LK.INT)
                {
                    case (true) {
                    switch (dt == DataType.SINT | dt == DataType.BOOL | dt == DataType.UINT | dt == DataType.ULONG)
                    {
                        case (true) { -> (byte*)0; }
                        default {};
                    };
                    -> this.mod.c_null(lt).text;
                }
                    default {};
                };
                w = lt.width;
                switch (dt == DataType.SINT | dt == DataType.BOOL)
                {
                    case (true) { -> this.mod.c_int(this.t_i64, v).text; }
                    default {};
                };
                switch (dt == DataType.UINT | dt == DataType.ULONG | dt == DataType.DATA)
                {
                    case (true) {
                    switch (w < 64)
                    {
                        case (true) {
                        mask = ((i64)1 << (i64)w) - (i64)1;
                        v = v `& mask;
                        switch (v > (((i64)1 << (i64)(w - 1)) - (i64)1))
                        {
                            case (true) { v = v - ((i64)1 << (i64)w); }
                            default {};
                        };
                    }
                        default {};
                    };
                    -> this.mod.c_int(this.t_i64, v).text;
                }
                    default {};
                };
                -> this.mod.c_null(lt).text;
            };

            // Initializer text of the global an identifier names, or null when it has none
            global_ident_init(byte* name) -> byte*
            {
                FXC_SYMENTRY* se = st_lookup_any(this.st, name, this.cur_ns);
                IRGlobal* sg;
                byte* sm;
                switch (se != (FXC_SYMENTRY*)0)
                {
                    case (true) {
                    sm = sym_mangled(se);
                    sg = this.mod.find_global(sm);
                    ffree(sm);
                    switch (sg != (IRGlobal*)0)
                    {
                        case (true) { -> sg.init; }
                        default {};
                    };
                }
                    default {};
                };
                sg = this.mod.find_global(name);
                switch (sg != (IRGlobal*)0)
                {
                    case (true) { -> sg.init; }
                    default {};
                };
                -> (byte*)0;
            };

            // Decimal text to integer. False when the text is not a plain integer.
            parse_int_text(byte* t, i64* out) -> bool
            {
                int i = 0;
                bool neg = false;
                i64 v = (i64)0;
                switch (t == (byte*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (t[0] == '-')
                {
                    case (true) {
                    neg = true;
                    i = 1;
                }
                    default {};
                };
                switch (t[i] < '0' | t[i] > '9')
                {
                    case (true) { -> false; }
                    default {};
                };
                while (t[i] >= '0' & t[i] <= '9')
                {
                    v = v * (i64)10 + (i64)(t[i] - '0');
                    i++;
                };
                switch (t[i] != 0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (neg)
                {
                    case (true) { v = (i64)0 - v; }
                    default {};
                };
                *out = v;
                -> true;
            };

            // ArrayTypeHandler.create_global_array_initializer for integer literal elements.
            // Literal.codegen gives the literal its own width, then it is truncated (masked) or
            // widened (value kept) to the element width.
            global_elem_value(Node* e, IRType* et, i64* out) -> bool
            {
                i64 v;
                int sw;
                int dt;
                i64 mask;
                switch (et.kind != LK.INT)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (e.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    -> this.parse_int_text(this.global_ident_init(e.text), out);
                }
                    default {};
                };
                switch (e.kind != NodeKind.LITERAL)
                {
                    case (true) { -> false; }
                    default {};
                };
                dt = e.op;
                v = e.ival;
                switch (dt == DataType.SINT)
                {
                    case (true) { sw = 32; }
                    default {
                        switch (dt == DataType.UINT)
                        {
                            case (true) {
                    sw = 32;
                    switch (v > (i64)2147483647)
                    {
                        case (true) { v = v - ((i64)1 << (i64)32); }
                        default {};
                    };
                }
                            default {
                                switch (dt == DataType.SLONG | dt == DataType.ULONG)
                                {
                                    case (true) { sw = 64; }
                                    default {
                                        switch (dt == DataType.BOOL)
                                        {
                                            case (true) {
                    sw = 1;
                    switch (v != (i64)0)
                    {
                        case (true) { v = (i64)1; }
                        default {};
                    };
                }
                                            default {
                                                switch (dt == DataType.CHAR)
                                                {
                                                    case (true) { sw = 8; }
                                                    default { -> false; };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                };
                switch (sw > et.width)
                {
                    case (true) {
                    switch (et.width < 64)
                    {
                        case (true) {
                        mask = ((i64)1 << (i64)et.width) - (i64)1;
                        v = v `& mask;
                    }
                        default {};
                    };
                }
                    default {};
                };
                *out = v;
                -> true;
            };

            // "[T v, T v, ...]" text for a global array whose elements are v[0..n)
            global_array_text(IRType* lt, i64* v, int n) -> byte*
            {
                Buf ab;
                int i;
                byte* r;
                ab.__init();
                defer ab.__exit();
                ab.put(91);
                while (i < lt.count)
                {
                    switch (i > 0)
                    {
                        case (true) { ab.put_str(g", \0"); }
                        default {};
                    };
                    lt_text(@ab, lt.elem);
                    ab.put(32);
                    switch (i < n)
                    {
                        case (true) { put_i64(@ab, v[i]); }
                        default { ab.put(48); };
                    };
                    i++;
                };
                ab.put(93);
                r = this.mod.own(ab.mem);
                -> r;
            };

            global_array_init(Node* ini, IRType* lt) -> byte*
            {
                int n = node_count(ini, 0);
                int i;
                i64* vals;
                i64 one;
                byte* r;
                switch (lt.kind != LK.ARRAY)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (lt.elem.kind != LK.INT)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (n > lt.count)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                vals = (i64*)fmalloc((u64)(8 * (n + 1)));
                while (i < n)
                {
                    switch (!this.global_elem_value(node_child(ini, 0, i), lt.elem, @one))
                    {
                        case (true) { ffree((void*)vals); -> (byte*)0; }
                        default {};
                    };
                    vals[i] = one;
                    i++;
                };
                r = this.global_array_text(lt, vals, n);
                ffree((void*)vals);
                -> r;
            };

            global_string_init(Node* ini, IRType* lt) -> byte*
            {
                int len;
                int i;
                i64* vals;
                byte* r;
                byte* src = this.str_bytes(ini);
                len = this.q_len;
                switch (lt.kind != LK.ARRAY)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (lt.elem.kind != LK.INT)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (lt.elem.width != 8)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (len > lt.count)
                {
                    case (true) { len = lt.count; }
                    default {};
                };
                vals = (i64*)fmalloc((u64)(8 * (len + 1)));
                while (i < len)
                {
                    vals[i] = (i64)src[i];
                    i++;
                };
                r = this.global_array_text(lt, vals, len);
                ffree((void*)vals);
                -> r;
            };

            // visit_VariableDeclaration at global scope (_vardecl_global)
            dims_empty(TypeSpec* ts) -> bool
            {
                switch (ts.array_dims == (NodeVec*)0)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (ts.array_dims.len == 0)
                {
                    case (true) { -> true; }
                    default {};
                };
                // A single dimension written without a size
                -> ts.array_dims.len == 1 & ts.array_dims.items[0] == (Node*)0;
            };

            declare_global(Node* n, byte* ns) -> void
            {
                TypeSpec* ts = n.ts;
                IRType* lt;
                IRGlobal* gl;
                byte* m;
                byte* it;
                switch (n.text == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ts == (TypeSpec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ts.base_type == DataType.DICT)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ts.storage_class == StorageClass.AUTO)
                {
                    case (true) { this.note_unsup(g"global auto variable\0"); ->; }
                    default {};
                };
                lt = (IRType*)0;
                switch ((ts.flags `& TS_ARRAY) != 0 & ts.array_size == (Node*)0 & (ts.array_dims == (NodeVec*)0 | this.dims_empty(ts)))
                {
                    case (true) {
                    // Unsized array: the size comes from a string initializer
                    switch (n.a == (Node*)0)
                    {
                        case (true) {
                        this.note_unsup(g"global array without size\0");
                        ->;
                    }
                        default {};
                    };
                    switch (n.a.kind != NodeKind.STRING_LITERAL)
                    {
                        case (true) {
                        this.note_unsup(g"global array without size\0");
                        ->;
                    }
                        default {};
                    };
                    lt = this.lower(ts, true, n.line);
                    switch (lt == (IRType*)0)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.str_bytes(n.a);
                    lt = this.mod.t_array(lt.elem, this.q_len);
                }
                    default {};
                };
                switch (lt == (IRType*)0)
                {
                    case (true) { lt = this.lower(ts, true, n.line); }
                    default {};
                };
                switch (lt == (IRType*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                m = mangle_namespace_name(ns, n.text);
                switch (this.global_dup(m))
                {
                    case (true) {
                    ffree(m);
                    ->;
                }
                    default {};
                };
                it = this.global_init(n, lt);
                switch (it == (byte*)0)
                {
                    case (true) {
                    this.note_unsup(g"global initializer\0");
                    ffree(m);
                    ->;
                }
                    default {};
                };
                gl = this.mod.add_global(lt, m, it);
                gl.linkage = this.mod.own(g"internal\0");
                switch (nm_get(this.gvars, m) == (void*)0)
                {
                    case (true) {
                    LVar* gv = (LVar*)fmalloc((u64)((sizeof(LVar) + 7) / 8));
                    gv.ptr = gl.self;
                    gv.ts = ts;
                    gv.vol = false;
                    this.keep((void*)gv);
                    nm_put(this.gvars, m, (void*)gv);
                }
                    default {};
                };
                ffree(m);
                ->;
            };

            // TypeSpec that stands for a bare DataType attached to a value
            lit_spec(int dt) -> TypeSpec*
            {
                TypeSpec* t;
                switch (this.lspecs[dt] == (TypeSpec*)0)
                {
                    case (true) {
                    t = typespec_new();
                    t.base_type = dt;
                    this.keep((void*)t);
                    this.lspecs[dt] = t;
                }
                    default {};
                };
                -> this.lspecs[dt];
            };

            // CoercionContext.is_unsigned
            is_uns(IRValue* v) -> bool
            {
                TypeSpec* s = v.spec;
                switch (s == (TypeSpec*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (s.base_type == DataType.UINT)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (s.base_type == DataType.BYTE)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (s.base_type == DataType.DATA)
                {
                    case (true) { -> (s.flags `& TS_SIGNED) == 0; }
                    default {};
                };
                -> false;
            };

            // EndianSwapHandler.get_endianness
            endian_of(TypeSpec* t) -> int
            {
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> 1; }
                    default {};
                };
                -> t.endianness;
            };

            with_spec(IRValue* v, TypeSpec* s) -> IRValue*
            {
                switch (v != (IRValue*)0)
                {
                    case (true) { v.spec = s; }
                    default {};
                };
                -> v;
            };

            int_ty(int w) -> IRType* -> this.mod.t_int(w);

            ci32(int v) -> IRValue* -> this.mod.c_int(this.t_i32, (i64)v);

            // Object declaration with a constructor call (_vardecl_call_constructor)
            init_ctor(IRValue* alloca, IRType* lt, Node* ini, Node* site) -> void
            {
                int argc = node_count(ini, 0);
                int i;
                IRValue* probe;
                IRValue* v;
                IRValue** args;
                IRFunc* f;
                IRType* ft;
                int j;
                switch (argc == 1 & lt.kind == LK.ISTRUCT)
                {
                    case (true) {
                    probe = this.visit(node_child(ini, 0, 0));
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (probe != (IRValue*)0)
                    {
                        case (true) {
                        switch (probe.ty.kind == LK.PTR)
                        {
                            case (true) {
                            switch (lt_eq(probe.ty.elem, lt))
                            {
                                case (true) { probe = this.mod.load(probe, g"obj_copy_load\0"); }
                                default {};
                            };
                        }
                            default {};
                        };
                        switch (lt_eq(probe.ty, lt))
                        {
                            case (true) {
                            this.mod.store(probe, alloca);
                            ->;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (lt.kind == LK.ISTRUCT)
                {
                    case (true) {
                    j = 0;
                    while (j < lt.nitems)
                    {
                        switch (lt.items[j].kind == LK.ARRAY)
                        {
                            case (true) {
                            switch (lt.items[j].count > 64)
                            {
                                case (true) {
                                this.unsup(site, g"constructor on large object\0");
                                ->;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        j++;
                    };
                    this.mod.store(this.zero_of(lt), alloca);
                }
                    default {};
                };
                f = this.mod.find_function(ini.text3);
                switch (f == (IRFunc*)0)
                {
                    case (true) {
                    this.unsup(site, g"constructor not declared\0");
                    ->;
                }
                    default {};
                };
                ft = f.ftype;
                args = (IRValue**)fmalloc((u64)(8 * (argc + 1)));
                this.keep((void*)args);
                args[0] = alloca;
                i = 0;
                while (i < argc)
                {
                    switch (node_child(ini, 0, i).kind == NodeKind.STRING_LITERAL & i + 1 < ft.nitems & this.is_i8_ptr(ft.items[i + 1]))
                    {
                        case (true) {
                        this.sc.clear();
                        this.sc.put_str(g"ctor_arg\0");
                        this.sc.put_int(i);
                        v = this.local_string_value(node_child(ini, 0, i), this.sc.mem);
                    }
                        default { v = this.visit(node_child(ini, 0, i)); };
                    };
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (v == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(site, g"void constructor argument\0");
                        ->;
                    }
                        default {};
                    };
                    switch (i + 1 < ft.nitems)
                    {
                        case (true) { v = this.convert_arg(v, ft.items[i + 1], i, site); }
                        default {};
                    };
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    args[i + 1] = v;
                    i++;
                };
                this.mod.call(f.self, args, argc + 1, (byte*)0);
                ->;
            };

            is_i8_ptr(IRType* t) -> bool
            {
                switch (t.kind != LK.PTR)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> t.elem.kind == LK.INT & t.elem.width == 8;
            };

            // Bytes of a string literal (with the configured terminator); length in q_len
            str_bytes(Node* n) -> byte*
            {
                int len = (int)n.ival;
                int i;
                byte* src = n.text;
                byte* buf;
                switch (src == (byte*)0)
                {
                    case (true) { src = g"\0"; }
                    default {};
                };
                switch (len <= 0)
                {
                    case (true) {
                    while (src[len] != 0) { len++; };
                }
                    default {};
                };
                buf = (byte*)fmalloc((u64)(len + 2));
                this.keep((void*)buf);
                while (i < len)
                {
                    buf[i] = src[i];
                    i++;
                };
                switch (this.null_term)
                {
                    case (true) {
                    switch (len == 0)
                    {
                        case (true) {
                        buf[0] = (byte)0;
                        len = 1;
                    }
                        default {
                            switch (buf[len - 1] != (byte)0)
                            {
                                case (true) {
                        buf[len] = (byte)0;
                        len++;
                    }
                                default {};
                            };
                        };
                    };
                }
                    default {};
                };
                this.q_len = len;
                -> buf;
            };

            // Stores bytes into a [N x i8]* with unnamed gep and store pairs
            store_bytes(IRValue* arr, byte* buf, int len) -> void
            {
                int i;
                IRValue* ep;
                while (i < len)
                {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = this.ci32(i);
                    ep = this.mod.gep(arr, this.mod.ia, 2, false, (byte*)0);
                    this.mod.store(this.mod.c_int(this.t_i8, (i64)(int)buf[i]), ep);
                    i++;
                };
                ->;
            };

            str_init_ok(IRType* lt, Node* ini) -> bool
            {
                switch (ini.op == StorageClass.HEAP)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (this.is_i8_ptr(lt))
                {
                    case (true) { -> true; }
                    default {};
                };
                -> lt.kind == LK.ARRAY & lt.elem.kind == LK.INT & lt.elem.width == 8;
            };

            // ArrayTypeHandler.initialize_local_string
            init_local_string(IRValue* alloca, IRType* lt, Node* ini) -> void
            {
                byte* buf = this.str_bytes(ini);
                int len = this.q_len;
                int i;
                IRValue* sa;
                IRValue* sp;
                IRValue* ep;
                switch (this.is_i8_ptr(lt))
                {
                    case (true) {
                    sa = this.mod.alloca_here(this.mod.t_array(this.t_i8, len), g"str_data\0");
                    this.store_bytes(sa, buf, len);
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = this.ci32(0);
                    sp = this.mod.gep(sa, this.mod.ia, 2, false, g"str_ptr\0");
                    this.mod.store(sp, alloca);
                    ->;
                }
                    default {};
                };
                switch (len > lt.count)
                {
                    case (true) { len = lt.count; }
                    default {};
                };
                this.store_bytes(alloca, buf, len);
                i = len;
                while (i < lt.count)
                {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = this.ci32(i);
                    ep = this.mod.gep(alloca, this.mod.ia, 2, false, (byte*)0);
                    this.mod.store(this.mod.c_int(this.t_i8, (i64)0), ep);
                    i++;
                };
                ->;
            };

            // create_local_string_for_arg
            local_string_value(Node* s, byte* hint) -> IRValue*
            {
                byte* buf = this.str_bytes(s);
                int len = this.q_len;
                IRValue* sa;
                byte* h = ts_dup(hint);
                this.keep((void*)h);
                this.sc.clear();
                this.sc.put_str(h);
                this.sc.put_str(g"_str_data\0");
                sa = this.mod.alloca_here(this.mod.t_array(this.t_i8, len), this.sc.mem);
                this.store_bytes(sa, buf, len);
                this.sc.clear();
                this.sc.put_str(h);
                this.sc.put_str(g"_str_ptr\0");
                this.mod.ia[0] = this.ci32(0);
                this.mod.ia[1] = this.ci32(0);
                -> this.mod.gep(sa, this.mod.ia, 2, false, this.sc.mem);
            };

            // True when a local array literal is a list of plain scalar expressions
            simple_array_init(IRType* lt, Node* ini) -> bool
            {
                int i;
                int c = node_count(ini, 0);
                int k;
                switch (lt.kind != LK.ARRAY)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (lt.elem.kind != LK.INT & lt.elem.kind != LK.PTR & lt.elem.kind != LK.FLOAT & lt.elem.kind != LK.DOUBLE)
                {
                    case (true) { -> false; }
                    default {};
                };
                while (i < c)
                {
                    k = node_child(ini, 0, i).kind;
                    switch (k == NodeKind.STRING_LITERAL | k == NodeKind.ARRAY_LITERAL | k == NodeKind.STRUCT_LITERAL)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    i++;
                };
                -> true;
            };

            // ArrayTypeHandler.initialize_local_array for integer element arrays
            init_local_array(IRValue* alloca, IRType* lt, Node* ini) -> void
            {
                int i;
                int c = node_count(ini, 0);
                IRValue* ev;
                IRValue* ep;
                while (i < c & i < lt.count)
                {
                    ev = this.visit(node_child(ini, 0, i));
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (ev == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(ini, g"void array element\0");
                        ->;
                    }
                        default {};
                    };
                    switch (lt.elem.kind)
                    {
                        case (LK.PTR)
                        {
                            // Pointer elements keep the pointer, an array pointer decays to its first element
                            switch (ev.ty.kind == LK.PTR)
                            {
                                case (true) {
                                switch (ev.ty.elem.kind == LK.ARRAY)
                                {
                                    case (true) {
                                    this.mod.ia[0] = this.ci32(0);
                                    this.mod.ia[1] = this.ci32(0);
                                    ev = this.mod.gep(ev, this.mod.ia, 2, false, g"str_to_ptr\0");
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                            switch (!lt_eq(ev.ty, lt.elem))
                            {
                                case (true) {
                                this.unsup(ini, g"array element type\0");
                                ->;
                            }
                                default {};
                            };
                        }
                        default
                        {
                            switch (ev.ty.kind == LK.PTR)
                            {
                                case (true) { ev = this.mod.load(ev, (byte*)0); }
                                default {};
                            };
                            switch (lt.elem.kind == LK.INT)
                            {
                                case (true) {
                                switch (ev.ty.kind != LK.INT)
                                {
                                    case (true) {
                                    this.unsup(ini, g"array element type\0");
                                    ->;
                                }
                                    default {};
                                };
                                switch (ev.ty.width < lt.elem.width)
                                {
                                    case (true) { ev = this.mod.cast(g"zext\0", ev, lt.elem, (byte*)0); }
                                    default {
                                        switch (ev.ty.width > lt.elem.width)
                                        {
                                            case (true) { ev = this.mod.cast(g"trunc\0", ev, lt.elem, (byte*)0); }
                                            default {};
                                        };
                                    };
                                };
                            }
                                default {
                                    switch (!lt_eq(ev.ty, lt.elem))
                                    {
                                        case (true) {
                                this.unsup(ini, g"array element type\0");
                                ->;
                            }
                                        default {};
                                    };
                                };
                            };
                        };
                    };
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = this.ci32(i);
                    this.sc.clear();
                    this.sc.put_str(g"elem_\0");
                    this.sc.put_int(i);
                    ep = this.mod.gep(alloca, this.mod.ia, 2, false, this.sc.mem);
                    this.mod.store(ev, ep);
                    i++;
                };
                ->;
            };

            // Zero fill of a large local array through llvm.memset
            memset_zero(IRValue* alloca, IRType* lt) -> void
            {
                IRType** ps = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                IRType* i8p = this.mod.t_ptr(this.t_i8);
                IRFunc* f;
                IRValue* cp;
                int eb = 1;
                this.keep((void*)ps);
                ps[0] = i8p;
                ps[1] = this.t_i8;
                ps[2] = this.t_i64;
                ps[3] = this.t_i1;
                f = this.intrinsic(g"llvm.memset.p0i8.i64\0", this.mod.t_func(this.t_void, ps, 4, false));
                switch (lt.elem.kind == LK.INT)
                {
                    case (true) { eb = lt.elem.width / 8; }
                    default {};
                };
                cp = this.mod.cast(g"bitcast\0", alloca, i8p, g"memset_ptr\0");
                this.mod.ia[0] = cp;
                this.mod.ia[1] = this.mod.c_int(this.t_i8, (i64)0);
                this.mod.ia[2] = this.mod.c_int(this.t_i64, (i64)lt.count * (i64)eb);
                this.mod.ia[3] = this.mod.c_null(this.t_i1);
                this.mod.call(f.self, this.mod.ia, 4, (byte*)0);
                ->;
            };

            // Declares (or finds) an intrinsic or external function by type
            intrinsic(byte* name, IRType* ft) -> IRFunc*
            {
                IRFunc* f = this.mod.find_function(name);
                switch (f == (IRFunc*)0)
                {
                    case (true) { f = this.mod.add_function(ft, name); }
                    default {};
                };
                -> f;
            };

            // EndianSwapHandler.emit_bswap
            bswap(IRValue* v) -> IRValue*
            {
                IRFunc* f;
                IRType** ps;
                int w = v.ty.width;
                switch (v.ty.kind != LK.INT)
                {
                    case (true) { -> v; }
                    default {};
                };
                switch (w < 16)
                {
                    case (true) { -> v; }
                    default {};
                };
                switch (w % 16 != 0)
                {
                    case (true) { -> v; }
                    default {};
                };
                this.sc.clear();
                this.sc.put_str(g"llvm.bswap.i\0");
                this.sc.put_int(w);
                ps = (IRType**)fmalloc((u64)2 * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)ps);
                ps[0] = v.ty;
                f = this.intrinsic(this.sc.mem, this.mod.t_func(v.ty, ps, 1, false));
                this.mod.ia[0] = v;
                -> this.mod.call(f.self, this.mod.ia, 1, g"bswapped\0");
            };

            // EndianSwapHandler.maybe_swap(val, target_ptr)
            maybe_swap(IRValue* v, IRValue* target) -> IRValue*
            {
                IRValue* sw;
                TypeSpec* ns;
                int se, te;
                switch (v.ty.kind != LK.INT)
                {
                    case (true) { -> v; }
                    default {};
                };
                switch (v.ty.width < 16)
                {
                    case (true) { -> v; }
                    default {};
                };
                se = this.endian_of(v.spec);
                te = this.endian_of(target.spec);
                switch (se == te)
                {
                    case (true) { -> v; }
                    default {};
                };
                sw = this.bswap(v);
                switch (v.spec != (TypeSpec*)0)
                {
                    case (true) {
                    ns = typespec_clone(v.spec);
                    ns.endianness = te;
                    this.keep((void*)ns);
                    sw.spec = ns;
                }
                    default {};
                };
                -> sw;
            };

            // Widens or narrows an integer to width ty (names are left to the builder)
            int_resize(IRValue* v, IRType* ty, bool uns) -> IRValue*
            {
                IRValue* r;
                switch (v.ty.width == ty.width)
                {
                    case (true) { -> v; }
                    default {};
                };
                switch (v.ty.width < ty.width)
                {
                    case (true) {
                    switch (uns)
                    {
                        case (true) { r = this.mod.cast(g"zext\0", v, ty, (byte*)0); }
                        default { r = this.mod.cast(g"sext\0", v, ty, (byte*)0); };
                    };
                }
                    default { r = this.mod.cast(g"trunc\0", v, ty, (byte*)0); };
                };
                r.spec = v.spec;
                -> r;
            };

            // CoercionContext.normalize_ints: result in nra and nrb
            normalize_ints(IRValue* a, IRValue* b, bool uns, bool promote) -> void
            {
                int w;
                IRType* ty;
                this.nra = a;
                this.nrb = b;
                switch (a.ty.width == b.ty.width)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (promote)
                {
                    case (true) {
                    w = a.ty.width;
                    switch (b.ty.width > w)
                    {
                        case (true) { w = b.ty.width; }
                        default {};
                    };
                }
                    default {
                    w = a.ty.width;
                    switch (b.ty.width < w)
                    {
                        case (true) { w = b.ty.width; }
                        default {};
                    };
                };
                };
                ty = this.int_ty(w);
                this.nra = this.int_resize(a, ty, uns);
                this.nrb = this.int_resize(b, ty, uns);
                ->;
            };

            // _coerce_to_bool
            to_bool(IRValue* v) -> IRValue*
            {
                IRType* t = v.ty;
                switch (t.kind == LK.INT)
                {
                    case (true) {
                    switch (t.width == 1)
                    {
                        case (true) { -> v; }
                        default {};
                    };
                    -> this.mod.icmp(g"ne\0", v, this.mod.c_int(t, (i64)0), g"tobool\0");
                }
                    default {};
                };
                switch (t.kind == LK.PTR)
                {
                    case (true) { -> this.mod.icmp(g"ne\0", v, this.mod.c_null(t), g"ptrbool\0"); }
                    default {};
                };
                switch (t.kind == LK.FLOAT | t.kind == LK.DOUBLE)
                {
                    case (true) {
                    -> this.mod.fcmp(g"one\0", v, this.mod.c_fp(t, 0.0), g"fpbool\0");
                }
                    default {};
                };
                -> this.mod.icmp(g"ne\0", v, this.mod.c_null(t), g"tobool\0");
            };

            // ----------------------------------------------------------
            // Conversions
            // ----------------------------------------------------------

            is_aggregate_ty(IRType* t) -> bool -> t.kind == LK.STRUCT | t.kind == LK.ISTRUCT;

            // CoercionContext.coerce_return_value
            coerce_ret(IRValue* v, IRType* expected, Node* site) -> IRValue*
            {
                IRType* src = v.ty;
                IRValue* r;
                switch (lt_eq(src, expected))
                {
                    case (true) { -> v; }
                    default {};
                };
                switch (src.kind == LK.INT & expected.kind == LK.INT)
                {
                    case (true) {
                    switch (src.width < expected.width)
                    {
                        case (true) {
                        switch (this.is_uns(v))
                        {
                            case (true) { r = this.mod.cast(g"zext\0", v, expected, (byte*)0); }
                            default { r = this.mod.cast(g"sext\0", v, expected, (byte*)0); };
                        };
                    }
                        default { r = this.mod.cast(g"trunc\0", v, expected, (byte*)0); };
                    };
                    r.spec = v.spec;
                    -> r;
                }
                    default {};
                };
                switch ((src.kind == LK.FLOAT | src.kind == LK.DOUBLE) & expected.kind == LK.INT)
                {
                    case (true) {
                    switch (v.spec != (TypeSpec*)0 & this.is_uns(v))
                    {
                        case (true) { r = this.mod.cast(g"fptoui\0", v, expected, (byte*)0); }
                        default { r = this.mod.cast(g"fptosi\0", v, expected, (byte*)0); };
                    };
                    r.spec = v.spec;
                    -> r;
                }
                    default {};
                };
                switch (src.kind == LK.INT & (expected.kind == LK.FLOAT | expected.kind == LK.DOUBLE))
                {
                    case (true) {
                    switch (this.is_uns(v))
                    {
                        case (true) { r = this.mod.cast(g"uitofp\0", v, expected, (byte*)0); }
                        default { r = this.mod.cast(g"sitofp\0", v, expected, (byte*)0); };
                    };
                    r.spec = v.spec;
                    -> r;
                }
                    default {};
                };
                switch ((src.kind == LK.FLOAT | src.kind == LK.DOUBLE) & (expected.kind == LK.FLOAT | expected.kind == LK.DOUBLE))
                {
                    case (true) {
                    switch (src.kind)
                    {
                        case (LK.FLOAT) { r = this.mod.cast(g"fpext\0", v, expected, (byte*)0); }
                        default { r = this.mod.cast(g"fptrunc\0", v, expected, (byte*)0); };
                    };
                    r.spec = v.spec;
                    -> r;
                }
                    default {};
                };
                switch (src.kind == LK.PTR & expected.kind == LK.PTR)
                {
                    case (true) {
                    -> this.mod.cast(g"bitcast\0", v, expected, (byte*)0);
                }
                    default {};
                };
                switch (src.kind == LK.STRUCT & expected.kind == LK.STRUCT)
                {
                    case (true) {
                    this.unsup(site, g"return struct mismatch\0");
                    -> v;
                }
                    default {};
                };
                switch (src.kind == LK.ARRAY & expected.kind == LK.ARRAY)
                {
                    case (true) {
                    this.unsup(site, g"return array conversion\0");
                    -> v;
                }
                    default {};
                };
                switch (src.kind == LK.PTR)
                {
                    case (true) {
                    switch (lt_eq(src.elem, expected))
                    {
                        case (true) { -> this.mod.load(v, g"array_decay\0"); }
                        default {};
                    };
                }
                    default {};
                };
                this.unsup(site, g"return type mismatch\0");
                -> v;
            };

            // VariableTypeHandler.store_with_type_conversion
            store_conv(IRValue* alloca, IRType* llvm_type, IRValue* iv, Node* ini, Node* site) -> void
            {
                IRValue* v = iv;
                IRType* vt = v.ty;
                int ik = ini.kind;
                switch (ik == NodeKind.CAST_EXPRESSION & vt.kind == LK.PTR & llvm_type.kind == LK.ARRAY)
                {
                    case (true) {
                    this.unsup(site, g"cast to array initializer\0");
                    ->;
                }
                    default {};
                };
                switch (!lt_eq(vt, llvm_type))
                {
                    case (true) {
                    switch (vt.kind == LK.PTR & vt.elem.kind == LK.ARRAY & llvm_type.kind == LK.ARRAY)
                    {
                        case (true) {
                        this.unsup(site, g"array widening initializer\0");
                        ->;
                    }
                        default {};
                    };
                    switch (vt.kind == LK.PTR & vt.elem.kind == LK.ARRAY & llvm_type.kind == LK.INT)
                    {
                        case (true) {
                        this.unsup(site, g"array pack initializer\0");
                        ->;
                    }
                        default {};
                    };
                    switch (vt.kind == LK.PTR & this.is_aggregate_ty(llvm_type) & lt_eq(vt.elem, llvm_type))
                    {
                        case (true) {
                        v = this.mod.load(v, g"struct_deref\0");
                    }
                        default {
                            switch (vt.kind == LK.PTR & llvm_type.kind == LK.INT)
                            {
                                case (true) {
                        v = this.mod.cast(g"ptrtoint\0", v, llvm_type, g"ptr_to_int\0");
                    }
                                default {
                                    switch (vt.kind == LK.INT & llvm_type.kind == LK.PTR)
                                    {
                                        case (true) {
                        v = this.mod.cast(g"inttoptr\0", v, llvm_type, g"int_to_ptr\0");
                    }
                                        default {
                                            switch (vt.kind == LK.PTR & llvm_type.kind == LK.PTR)
                                            {
                                                case (true) {
                        switch (!lt_eq(llvm_type.elem, vt.elem))
                        {
                            case (true) { v = this.mod.cast(g"bitcast\0", v, llvm_type, (byte*)0); }
                            default {
                                switch (vt.elem.kind == LK.ARRAY)
                                {
                                    case (true) {
                            this.unsup(site, g"array pointer pack initializer\0");
                            ->;
                        }
                                    default {};
                                };
                            };
                        };
                    }
                                                default {
                                                    switch (vt.kind == LK.INT & llvm_type.kind == LK.INT)
                                                    {
                                                        case (true) {
                        switch (vt.width > llvm_type.width)
                        {
                            case (true) { v = this.mod.cast(g"trunc\0", v, llvm_type, (byte*)0); }
                            default {
                                switch (vt.width < llvm_type.width)
                                {
                                    case (true) {
                            switch (this.is_uns(v))
                            {
                                case (true) { v = this.mod.cast(g"zext\0", v, llvm_type, (byte*)0); }
                                default { v = this.mod.cast(g"sext\0", v, llvm_type, (byte*)0); };
                            };
                        }
                                    default {};
                                };
                            };
                        };
                    }
                                                        default {
                                                            switch (vt.kind == LK.INT & (llvm_type.kind == LK.FLOAT | llvm_type.kind == LK.DOUBLE))
                                                            {
                                                                case (true) {
                        v = this.mod.cast(g"sitofp\0", v, llvm_type, (byte*)0);
                    }
                                                                default {
                                                                    switch ((vt.kind == LK.FLOAT | vt.kind == LK.DOUBLE) & llvm_type.kind == LK.INT)
                                                                    {
                                                                        case (true) {
                        v = this.mod.cast(g"fptosi\0", v, llvm_type, (byte*)0);
                    }
                                                                        default {
                                                                            switch (vt.kind == LK.FLOAT & llvm_type.kind == LK.DOUBLE)
                                                                            {
                                                                                case (true) {
                        v = this.mod.cast(g"fpext\0", v, llvm_type, g"float_to_double\0");
                    }
                                                                                default {
                                                                                    switch (vt.kind == LK.DOUBLE & llvm_type.kind == LK.FLOAT)
                                                                                    {
                                                                                        case (true) {
                        v = this.mod.cast(g"fptrunc\0", v, llvm_type, g"double_to_float\0");
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
                                                    };
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                }
                    default {};
                };
                switch (v.spec != (TypeSpec*)0)
                {
                    case (true) {
                    switch (alloca.spec == (TypeSpec*)0)
                    {
                        case (true) { alloca.spec = v.spec; }
                        default {};
                    };
                }
                    default {};
                };
                v = this.maybe_swap(v, alloca);
                this.mod.store(v, alloca);
                ->;
            };

            // AssignmentTypeHandler.convert_value_for_assignment
            convert_assign(IRValue* v, IRType* target) -> IRValue*
            {
                IRType* vt = v.ty;
                IRValue* r;
                switch (lt_eq(vt, target))
                {
                    case (true) { -> v; }
                    default {};
                };
                switch (vt.kind == LK.PTR & target.kind == LK.PTR)
                {
                    case (true) {
                    switch (vt.elem.kind == LK.PTR & lt_eq(vt.elem, target))
                    {
                        case (true) {
                        -> this.mod.load(v, g"ptr_val_loaded\0");
                    }
                        default {};
                    };
                    switch (lt_eq(vt.elem, target.elem))
                    {
                        case (true) { -> this.mod.cast(g"bitcast\0", v, target, g"ptr_compat\0"); }
                        default {};
                    };
                    switch (vt.elem.kind == LK.INT & vt.elem.width == 8 & target.elem.kind == LK.INT & target.elem.width == 8)
                    {
                        case (true) {
                        -> this.mod.cast(g"bitcast\0", v, target, g"i8ptr_compat\0");
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (vt.kind == LK.PTR & vt.elem.kind == LK.ARRAY)
                {
                    case (true) {
                    switch (target.kind == LK.PTR)
                    {
                        case (true) {
                        switch (lt_eq(target.elem, vt.elem))
                        {
                            case (true) { -> v; }
                            default {};
                        };
                        switch (lt_eq(target.elem, vt.elem.elem))
                        {
                            case (true) {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            -> this.mod.gep(v, this.mod.ia, 2, false, g"array_to_elem_ptr\0");
                        }
                            default {};
                        };
                        switch (target.elem.kind == LK.ARRAY)
                        {
                            case (true) {
                            switch (target.elem.count == vt.elem.count)
                            {
                                case (true) {
                                -> this.mod.cast(g"bitcast\0", v, target, g"array_ptr_bitcast\0");
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = this.ci32(0);
                        -> this.mod.gep(v, this.mod.ia, 2, false, g"array_to_ptr\0");
                    }
                        default {};
                    };
                    switch (lt_eq(target, vt.elem))
                    {
                        case (true) { -> this.mod.load(v, g"array_load\0"); }
                        default {};
                    };
                }
                    default {};
                };
                switch (vt.kind == LK.PTR & target.kind != LK.PTR)
                {
                    case (true) {
                    switch (lt_eq(vt.elem, target))
                    {
                        case (true) { -> this.mod.load(v, g"struct_copy_load\0"); }
                        default {};
                    };
                }
                    default {};
                };
                switch (vt.kind == LK.PTR & vt.elem.kind == LK.INT & vt.elem.width == 8 & target.kind == LK.PTR)
                {
                    case (true) {
                    -> this.mod.cast(g"bitcast\0", v, target, g"void_ptr_to_typed\0");
                }
                    default {};
                };
                switch (vt.kind == LK.INT & target.kind == LK.INT)
                {
                    case (true) {
                    switch (vt.width != target.width)
                    {
                        case (true) {
                        -> this.int_resize(v, target, this.is_uns(v));
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (vt.kind == LK.FLOAT & target.kind == LK.DOUBLE)
                {
                    case (true) {
                    -> this.mod.cast(g"fpext\0", v, target, g"f32_to_f64\0");
                }
                    default {};
                };
                switch (vt.kind == LK.DOUBLE & target.kind == LK.FLOAT)
                {
                    case (true) {
                    -> this.mod.cast(g"fptrunc\0", v, target, g"f64_to_f32\0");
                }
                    default {};
                };
                -> v;
            };

            // FunctionTypeHandler.convert_argument_to_parameter_type
            convert_arg(IRValue* v, IRType* expected, int idx, Node* site) -> IRValue*
            {
                IRType* vt = v.ty;
                IRValue* d;
                switch (lt_eq(vt, expected))
                {
                    case (true) { -> v; }
                    default {};
                };
                this.sc.clear();
                switch (expected.kind == LK.PTR & expected.elem.kind == LK.INT & expected.elem.width == 8)
                {
                    case (true) {
                    switch (vt.kind == LK.PTR)
                    {
                        case (true) {
                        switch (vt.elem.kind == LK.ARRAY)
                        {
                            case (true) {
                            this.sc.put_str(g"arg\0");
                            this.sc.put_int(idx);
                            this.sc.put_str(g"_decay\0");
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            d = this.mod.gep(v, this.mod.ia, 2, false, this.sc.mem);
                            this.sc.clear();
                            this.sc.put_str(g"arg\0");
                            this.sc.put_int(idx);
                            this.sc.put_str(g"_to_void_ptr\0");
                            -> this.mod.cast(g"bitcast\0", d, expected, this.sc.mem);
                        }
                            default {};
                        };
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(idx);
                        this.sc.put_str(g"_to_void_ptr\0");
                        -> this.mod.cast(g"bitcast\0", v, expected, this.sc.mem);
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (vt.kind == LK.PTR & vt.elem.kind == LK.INT & vt.elem.width == 8 & expected.kind == LK.PTR)
                {
                    case (true) {
                    this.sc.put_str(g"arg\0");
                    this.sc.put_int(idx);
                    switch (expected.elem.kind)
                    {
                        case (LK.ARRAY) { this.sc.put_str(g"_to_array_ptr\0"); }
                        default { this.sc.put_str(g"_from_void_ptr\0"); };
                    };
                    -> this.mod.cast(g"bitcast\0", v, expected, this.sc.mem);
                }
                    default {};
                };
                switch (vt.kind == LK.PTR & vt.elem.kind == LK.ARRAY & expected.kind == LK.PTR)
                {
                    case (true) {
                    switch (lt_eq(vt.elem.elem, expected.elem))
                    {
                        case (true) {
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(idx);
                        this.sc.put_str(g"_decay\0");
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = this.ci32(0);
                        -> this.mod.gep(v, this.mod.ia, 2, false, this.sc.mem);
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (vt.kind == LK.INT & expected.kind == LK.INT)
                {
                    case (true) {
                    switch (vt.width != expected.width)
                    {
                        case (true) { -> this.int_resize(v, expected, this.is_uns(v)); }
                        default {};
                    };
                }
                    default {};
                };
                switch (vt.kind == LK.FLOAT & expected.kind == LK.DOUBLE)
                {
                    case (true) {
                    this.sc.put_str(g"arg\0");
                    this.sc.put_int(idx);
                    this.sc.put_str(g"_float_to_double\0");
                    -> this.mod.cast(g"fpext\0", v, expected, this.sc.mem);
                }
                    default {};
                };
                switch (vt.kind == LK.DOUBLE & expected.kind == LK.FLOAT)
                {
                    case (true) {
                    this.sc.put_str(g"arg\0");
                    this.sc.put_int(idx);
                    this.sc.put_str(g"_double_to_float\0");
                    -> this.mod.cast(g"fptrunc\0", v, expected, this.sc.mem);
                }
                    default {};
                };
                switch (vt.kind == LK.PTR & this.is_aggregate_ty(expected))
                {
                    case (true) {
                    switch (lt_eq(vt.elem, expected))
                    {
                        case (true) {
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(idx);
                        this.sc.put_str(g"_load\0");
                        -> this.mod.load(v, this.sc.mem);
                    }
                        default {};
                    };
                }
                    default {};
                };
                this.unsup(site, g"argument type mismatch\0");
                -> v;
            };

            // ----------------------------------------------------------
            // Expressions
            // ----------------------------------------------------------

            x_literal(Node* n) -> IRValue*
            {
                int dt = n.op;
                i64 v = n.ival;
                int w;
                IRValue* r;
                switch (dt == DataType.SINT | dt == DataType.UINT)
                {
                    case (true) {
                    // Source text without a sign that wrapped negative exceeded INT64_MAX
                    switch (v < (i64)0 & n.text != (byte*)0)
                    {
                        case (true) {
                        switch (n.text[0] != '-')
                        {
                            case (true) {
                            r = this.mod.c_u64(this.t_i64, (u64)v);
                            r.spec = this.lit_spec(dt);
                            -> r;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    w = 32;
                    switch (dt)
                    {
                        case (DataType.SINT)
                        {
                            switch (v < (i64)(0 - 2147483647 - 1) | v > (i64)2147483647)
                            {
                                case (true) { w = 64; }
                                default {};
                            };
                        }
                        default
                        {
                            switch (v >= (i64)0)
                            {
                                case (true) {
                                switch (v > (i64)4294967295)
                                {
                                    case (true) { w = 64; }
                                    default {};
                                };
                            }
                                default {
                                switch (v < (i64)0 - (i64)4294967296)
                                {
                                    case (true) { w = 64; }
                                    default {};
                                };
                            };
                            };
                            switch (w == 32 & v > (i64)2147483647)
                            {
                                case (true) { v = v - (i64)4294967296; }
                                default {};
                            };
                        };
                    };
                    r = this.mod.c_int(this.int_ty(w), v);
                    r.spec = this.lit_spec(dt);
                    -> r;
                }
                    default {};
                };
                switch (dt == DataType.SLONG | dt == DataType.ULONG)
                {
                    case (true) {
                    switch (dt == DataType.ULONG & v < (i64)0)
                    {
                        case (true) { r = this.mod.c_u64(this.t_i64, (u64)v); }
                        default { r = this.mod.c_int(this.t_i64, v); };
                    };
                    r.spec = this.lit_spec(dt);
                    -> r;
                }
                    default {};
                };
                switch (dt == DataType.FLOAT)
                {
                    case (true) { -> this.mod.c_fp(this.t_float, n.fval); }
                    default {};
                };
                switch (dt == DataType.DOUBLE)
                {
                    case (true) { -> this.mod.c_fp(this.t_double, n.fval); }
                    default {};
                };
                switch (dt == DataType.BOOL)
                {
                    case (true) { -> this.mod.c_int(this.t_i1, v); }
                    default {};
                };
                switch (dt == DataType.CHAR)
                {
                    case (true) { -> this.mod.c_int(this.t_i8, v); }
                    default {};
                };
                switch (dt == DataType.BYTE)
                {
                    case (true) { -> this.mod.c_int(this.int_ty(this.byte_width), v); }
                    default {};
                };
                switch (dt == DataType.VOID)
                {
                    case (true) { -> this.mod.c_null(this.t_i1); }
                    default {};
                };
                this.unsup(n, g"literal type\0");
                -> (IRValue*)0;
            };

            // visit_Identifier for a local variable. Mirrors _try_expr_method and the
            // load rules.
            try_expr_method(IRValue* ptr) -> IRValue*
            {
                IRType* pe;
                IRType* st_ty;
                IRValue* this_ptr;
                PtrVec* list;
                Overload* o;
                Overload* oc;
                int oi;
                IRFunc* f;
                byte* key;
                IRValue* r;
                switch (this.in_member)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (ptr.ty.kind != LK.PTR)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                pe = ptr.ty.elem;
                switch (pe.kind == LK.PTR & pe.elem.kind == LK.ISTRUCT)
                {
                    case (true) {
                    st_ty = pe.elem;
                    this_ptr = this.mod.load(ptr, g"obj_this\0");
                }
                    default {
                        switch (pe.kind == LK.ISTRUCT)
                        {
                            case (true) {
                    st_ty = pe;
                    this_ptr = ptr;
                }
                            default { -> (IRValue*)0; };
                        };
                    };
                };
                switch (st_ty.name == (byte*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                // The base resolves "<namespace>__<Type>.__expr" through its overload table,
                // which never holds namespaced methods under that key, so no promotion happens
                switch (this.has_ns_sep(st_ty.name))
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                key = join3(st_ty.name, g".__expr\0", g"\0");
                list = st_overloads_of(this.st, key);
                ffree(key);
                switch (list == (PtrVec*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                o = (Overload*)0;
                oi = 0;
                while (oi < list.len)
                {
                    oc = (Overload*)list.items[oi];
                    switch (oc.nparams == 0)
                    {
                        case (true) {
                        o = oc;
                        break;
                    }
                        default {};
                    };
                    oi++;
                };
                switch (o == (Overload*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                f = this.mod.find_function(o.mangled);
                switch (f == (IRFunc*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                this.sc.clear();
                this.sc.put_str(st_ty.name);
                this.sc.put_str(g"_expr\0");
                this.mod.ia[0] = this_ptr;
                r = this.mod.call(f.self, this.mod.ia, 1, this.sc.mem);
                r.flags = r.flags `| VF_FROM_EXPR;
                -> r;
            };

            // True when name contains a double underscore namespace separator
            has_ns_sep(byte* s) -> bool
            {
                int i;
                while (s[i] != 0)
                {
                    switch (s[i] == '_' & s[i + 1] == '_')
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            x_ident(Node* n) -> IRValue*
            {
                LVar* lv = this.find_var(n.text);
                IRValue* ptr;
                IRValue* r;
                IRValue* e;
                TypeSpec* ts;
                switch (lv == (LVar*)0)
                {
                    case (true) {
                    this.unsup(n, g"identifier not local\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                ptr = lv.ptr;
                ts = lv.ts;
                switch (cstr_eq(n.text, g"this\0"))
                {
                    case (true) { -> ptr; }
                    default {};
                };
                e = this.try_expr_method(ptr);
                switch (e != (IRValue*)0)
                {
                    case (true) { -> e; }
                    default {};
                };
                switch (ptr.ty.kind == LK.PTR)
                {
                    case (true) {
                    switch (ptr.ty.elem.kind == LK.ARRAY | ptr.ty.elem.kind == LK.STRUCT)
                    {
                        case (true) { -> ptr; }
                        default {};
                    };
                }
                    default {};
                };
                switch (ts != (TypeSpec*)0)
                {
                    case (true) {
                    switch (ts.array_size != (Node*)0)
                    {
                        case (true) { -> ptr; }
                        default {};
                    };
                }
                    default {};
                };
                switch (ptr.spec != (TypeSpec*)0)
                {
                    case (true) {
                    switch (ptr.spec.array_size != (Node*)0)
                    {
                        case (true) { -> ptr; }
                        default {};
                    };
                }
                    default {};
                };
                switch (ptr.ty.kind != LK.PTR)
                {
                    case (true) { -> ptr; }
                    default {};
                };
                r = this.mod.load(ptr, n.text);
                r.spec = ptr.spec;
                switch (r.spec == (TypeSpec*)0)
                {
                    case (true) { r.spec = ts; }
                    default {};
                };
                r.flags = ptr.flags `& VF_TYPEFUNC_STR;
                -> r;
            };

            int_pred(int op, bool uns) -> byte*
            {
                switch (op == Operator.EQUAL)
                {
                    case (true) { -> g"eq\0"; }
                    default {};
                };
                switch (op == Operator.NOT_EQUAL)
                {
                    case (true) { -> g"ne\0"; }
                    default {};
                };
                switch (op == Operator.LESS_THAN)
                {
                    case (true) { switch (uns)
 {
     case (true) { -> g"ult\0"; }
     default {};
 }; -> g"slt\0"; }
                    default {};
                };
                switch (op == Operator.LESS_EQUAL)
                {
                    case (true) { switch (uns)
 {
     case (true) { -> g"ule\0"; }
     default {};
 }; -> g"sle\0"; }
                    default {};
                };
                switch (op == Operator.GREATER_THAN)
                {
                    case (true) { switch (uns)
 {
     case (true) { -> g"ugt\0"; }
     default {};
 }; -> g"sgt\0"; }
                    default {};
                };
                switch (uns)
                {
                    case (true) { -> g"uge\0"; }
                    default {};
                };
                -> g"sge\0";
            };

            fp_pred(int op) -> byte*
            {
                switch (op == Operator.EQUAL)
                {
                    case (true) { -> g"oeq\0"; }
                    default {};
                };
                switch (op == Operator.NOT_EQUAL)
                {
                    case (true) { -> g"one\0"; }
                    default {};
                };
                switch (op == Operator.LESS_THAN)
                {
                    case (true) { -> g"olt\0"; }
                    default {};
                };
                switch (op == Operator.LESS_EQUAL)
                {
                    case (true) { -> g"ole\0"; }
                    default {};
                };
                switch (op == Operator.GREATER_THAN)
                {
                    case (true) { -> g"ogt\0"; }
                    default {};
                };
                -> g"oge\0";
            };

            // True when a user defined operator__<op> overload is registered
            has_op_overload(int op) -> bool
            {
                byte* sym = operator_text(op);
                bool r;
                this.sc.clear();
                this.sc.put_str(g"operator__\0");
                mangle_builtin_op(@this.sc, sym);
                -> st_overloads_of(this.st, this.sc.mem) != (PtrVec*)0;
            };

            x_binary(Node* n) -> IRValue*
            {
                int op = n.op;
                IRValue* lhs;
                IRValue* rhs;
                IRValue* r;
                bool uns, is_cmp, might_ptr, lp, rp, li, ri;
                bool lzero, rzero;
                IRType* pe;
                int lcat, rcat, bare_cat, other_cat;
                Node* other_n;
                bool matches, tres;
                switch (op == Operator.EQUAL | op == Operator.NOT_EQUAL)
                {
                    case (true) {
                    switch (n.a.kind == NodeKind.TYPE_OF & n.b.kind == NodeKind.TYPE_OF)
                    {
                        case (true) {
                        lcat = this.typeof_bare_cat(n.a);
                        rcat = this.typeof_bare_cat(n.b);
                        switch (lcat >= 0 | rcat >= 0)
                        {
                            case (true) {
                            switch (lcat >= 0 & rcat >= 0)
                            {
                                case (true) {
                                this.fail(g"typeof(struct) == typeof(struct)-style comparison has no specific type on either side to check category membership for\0", n.line);
                                this.unsup(n, g"typeof category comparison\0");
                                -> (IRValue*)0;
                            }
                                default {};
                            };
                            switch (lcat >= 0)
                            {
                                case (true) {
                                bare_cat = lcat;
                                other_n = n.b;
                            }
                                default {
                                bare_cat = rcat;
                                other_n = n.a;
                            };
                            };
                            other_cat = this.typeof_arg_category(other_n);
                            matches = other_cat == bare_cat;
                            tres = matches;
                            switch (op == Operator.NOT_EQUAL)
                            {
                                case (true) { tres = !matches; }
                                default {};
                            };
                            switch (tres)
                            {
                                case (true) { r = this.mod.new_value(this.t_i1, g"1\0"); }
                                default { r = this.mod.new_value(this.t_i1, g"0\0"); };
                            };
                            r.is_const = true;
                            -> r;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (op == Operator.ASSIGN)
                {
                    case (true) {
                    this.unsup(n, g"binary assign\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (this.has_op_overload(op))
                {
                    case (true) {
                    this.unsup(n, g"operator overload\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                lhs = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                rhs = this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (lhs == (IRValue*)0 | rhs == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"binary void operand\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                lp = lhs.ty.kind == LK.PTR;
                rp = rhs.ty.kind == LK.PTR;
                li = lhs.ty.kind == LK.INT;
                ri = rhs.ty.kind == LK.INT;
                might_ptr = false;
                switch (op == Operator.ADD | op == Operator.SUB)
                {
                    case (true) {
                    switch (lp)
                    {
                        case (true) {
                        switch (lhs.ty.elem.kind == LK.PTR)
                        {
                            case (true) { might_ptr = true; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (rp)
                    {
                        case (true) {
                        switch (rhs.ty.elem.kind == LK.PTR)
                        {
                            case (true) { might_ptr = true; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (lp & ri)
                    {
                        case (true) { might_ptr = true; }
                        default {};
                    };
                    switch (rp & li)
                    {
                        case (true) { might_ptr = true; }
                        default {};
                    };
                }
                    default {};
                };
                is_cmp = op == Operator.EQUAL | op == Operator.NOT_EQUAL | op == Operator.LESS_THAN |
                         op == Operator.GREATER_THAN | op == Operator.LESS_EQUAL | op == Operator.GREATER_EQUAL;
                rzero = rhs.is_const & ri & cstr_eq(rhs.text, g"0\0");
                lzero = lhs.is_const & li & cstr_eq(lhs.text, g"0\0");
                switch (is_cmp & lp & rzero)
                {
                    case (true) { rhs = this.mod.c_null(lhs.ty); }
                    default {
                        switch (is_cmp & rp & lzero)
                        {
                            case (true) { lhs = this.mod.c_null(rhs.ty); }
                            default {
                                switch (is_cmp & lp & rp)
                                {
                                    case (true) { r = lhs; }
                                    default {
                                        switch (!might_ptr)
                                        {
                                            case (true) {
                    switch (lhs.ty.kind == LK.PTR)
                    {
                        case (true) {
                        pe = lhs.ty.elem;
                        switch (pe.kind != LK.ARRAY & pe.kind != LK.STRUCT & pe.kind != LK.ISTRUCT &
                            (lhs.flags `& (VF_FROM_EXPR `| VF_TYPEFUNC_STR)) == 0)
                        {
                            case (true) {
                            lhs = this.mod.load(lhs, g"auto_deref_lhs\0");
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (rhs.ty.kind == LK.PTR)
                    {
                        case (true) {
                        pe = rhs.ty.elem;
                        switch (pe.kind != LK.ARRAY & pe.kind != LK.STRUCT & pe.kind != LK.ISTRUCT &
                            (rhs.flags `& (VF_FROM_EXPR `| VF_TYPEFUNC_STR)) == 0)
                        {
                            case (true) {
                            rhs = this.mod.load(rhs, g"auto_deref_rhs\0");
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                                            default {
                    switch (lp)
                    {
                        case (true) {
                        switch (lhs.ty.elem.kind == LK.PTR)
                        {
                            case (true) {
                            switch (lhs.ty.elem.elem.kind == LK.INT & !ri)
                            {
                                case (true) {
                                lhs = this.mod.load(lhs, g"deref_ptr_for_arithmetic\0");
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (rp)
                    {
                        case (true) {
                        switch (rhs.ty.elem.kind == LK.PTR)
                        {
                            case (true) {
                            switch (rhs.ty.elem.elem.kind == LK.INT & !li)
                            {
                                case (true) {
                                rhs = this.mod.load(rhs, g"deref_ptr_for_arithmetic\0");
                            }
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
                                    };
                                };
                            };
                        };
                    };
                };
                switch (lhs.ty.kind == LK.INT & lhs.ty.width >= 16)
                {
                    case (true) {
                    switch (this.endian_of(lhs.spec) == 0)
                    {
                        case (true) { lhs = this.bswap(lhs); }
                        default {};
                    };
                }
                    default {};
                };
                switch (rhs.ty.kind == LK.INT & rhs.ty.width >= 16)
                {
                    case (true) {
                    switch (this.endian_of(rhs.spec) == 0)
                    {
                        case (true) { rhs = this.bswap(rhs); }
                        default {};
                    };
                }
                    default {};
                };
                switch (op == Operator.ADD | op == Operator.SUB)
                {
                    case (true) {
                    switch (lhs.ty.kind == LK.ARRAY | rhs.ty.kind == LK.ARRAY |
                        (lhs.ty.kind == LK.PTR & lhs.ty.elem.kind == LK.ARRAY & rhs.ty.kind == LK.PTR & rhs.ty.elem.kind == LK.ARRAY))
                    {
                        case (true) {
                        this.unsup(n, g"array concatenation\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (op == Operator.ADD)
                {
                    case (true) {
                    switch (((lhs.flags `| rhs.flags) `& (VF_FROM_EXPR `| VF_TYPEFUNC_STR)) != 0)
                    {
                        case (true) {
                        this.unsup(n, g"string concatenation\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                lp = lhs.ty.kind == LK.PTR;
                rp = rhs.ty.kind == LK.PTR;
                li = lhs.ty.kind == LK.INT;
                ri = rhs.ty.kind == LK.INT;
                switch (op == Operator.ADD | op == Operator.SUB)
                {
                    case (true) {
                    switch (lp & ri)
                    {
                        case (true) {
                        IRValue* off = rhs;
                        IRValue* base = lhs;
                        switch (op == Operator.SUB)
                        {
                            case (true) {
                            off = this.mod.binop(g"sub\0", this.mod.c_int(rhs.ty, (i64)0), rhs, (byte*)0);
                        }
                            default {};
                        };
                        switch (lhs.ty.elem.kind == LK.ARRAY)
                        {
                            case (true) {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            base = this.mod.gep(lhs, this.mod.ia, 2, false, g"arr_base\0");
                        }
                            default {};
                        };
                        r = this.mod.gep_ptr(base, off, false, (byte*)0);
                        r.spec = lhs.spec;
                        -> r;
                    }
                        default {};
                    };
                    switch (rp & li & op == Operator.ADD)
                    {
                        case (true) {
                        IRValue* base2 = rhs;
                        switch (rhs.ty.elem.kind == LK.ARRAY)
                        {
                            case (true) {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            base2 = this.mod.gep(rhs, this.mod.ia, 2, false, g"arr_base\0");
                        }
                            default {};
                        };
                        r = this.mod.gep_ptr(base2, lhs, false, (byte*)0);
                        r.spec = rhs.spec;
                        -> r;
                    }
                        default {};
                    };
                    switch (lp & rp)
                    {
                        case (true) {
                        IRValue* pa = this.mod.cast(g"ptrtoint\0", lhs, this.t_i64, (byte*)0);
                        IRValue* pb = this.mod.cast(g"ptrtoint\0", rhs, this.t_i64, (byte*)0);
                        -> this.mod.binop(g"sub\0", pa, pb, (byte*)0);
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (op == Operator.ADD | op == Operator.SUB | op == Operator.MUL | op == Operator.DIV |
                    op == Operator.MOD | op == Operator.POWER)
                {
                    case (true) {
                    switch (lhs.ty.kind == LK.FLOAT & rhs.ty.kind == LK.DOUBLE)
                    {
                        case (true) {
                        lhs = this.mod.cast(g"fpext\0", lhs, this.t_double, g"float_to_double_lhs\0");
                    }
                        default {
                            switch (lhs.ty.kind == LK.DOUBLE & rhs.ty.kind == LK.FLOAT)
                            {
                                case (true) {
                        rhs = this.mod.cast(g"fpext\0", rhs, this.t_double, g"float_to_double_rhs\0");
                    }
                                default {};
                            };
                        };
                    };
                    switch (lhs.ty.kind == LK.FLOAT | lhs.ty.kind == LK.DOUBLE)
                    {
                        case (true) {
                        switch (op == Operator.POWER)
                        {
                            case (true) {
                            this.unsup(n, g"float power\0");
                            -> (IRValue*)0;
                        }
                            default {};
                        };
                        switch (op == Operator.ADD)
                        {
                            case (true) { -> this.mod.binop(g"fadd\0", lhs, rhs, (byte*)0); }
                            default {};
                        };
                        switch (op == Operator.SUB)
                        {
                            case (true) { -> this.mod.binop(g"fsub\0", lhs, rhs, (byte*)0); }
                            default {};
                        };
                        switch (op == Operator.MUL)
                        {
                            case (true) { -> this.mod.binop(g"fmul\0", lhs, rhs, (byte*)0); }
                            default {};
                        };
                        switch (op == Operator.DIV)
                        {
                            case (true) { -> this.mod.binop(g"fdiv\0", lhs, rhs, (byte*)0); }
                            default {};
                        };
                        -> this.mod.binop(g"frem\0", lhs, rhs, (byte*)0);
                    }
                        default {};
                    };
                    uns = this.is_uns(lhs) | this.is_uns(rhs);
                    switch (lhs.ty.kind == LK.INT & rhs.ty.kind == LK.INT)
                    {
                        case (true) {
                        switch (lhs.ty.width != rhs.ty.width)
                        {
                            case (true) {
                            this.normalize_ints(lhs, rhs, uns, true);
                            lhs = this.nra;
                            rhs = this.nrb;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (lhs.ty.kind != LK.INT | rhs.ty.kind != LK.INT)
                    {
                        case (true) {
                        this.unsup(n, g"arithmetic operand types\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (op == Operator.POWER)
                    {
                        case (true) {
                        this.unsup(n, g"integer power\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (op)
                    {
                        case (Operator.ADD) { r = this.mod.binop(g"add\0", lhs, rhs, (byte*)0); }
                        case (Operator.SUB) { r = this.mod.binop(g"sub\0", lhs, rhs, (byte*)0); }
                        case (Operator.MUL) { r = this.mod.binop(g"mul\0", lhs, rhs, (byte*)0); }
                        case (Operator.DIV)
                        {
                            switch (uns)
                            {
                                case (true) { r = this.mod.binop(g"udiv\0", lhs, rhs, (byte*)0); }
                                default { r = this.mod.binop(g"sdiv\0", lhs, rhs, (byte*)0); };
                            };
                        }
                        default
                        {
                            switch (uns)
                            {
                                case (true) { r = this.mod.binop(g"urem\0", lhs, rhs, (byte*)0); }
                                default { r = this.mod.binop(g"srem\0", lhs, rhs, (byte*)0); };
                            };
                        };
                    };
                    switch (uns)
                    {
                        case (true) { r.spec = this.lit_spec(DataType.UINT); }
                        default { r.spec = this.lit_spec(DataType.SINT); };
                    };
                    -> r;
                }
                    default {};
                };
                switch (is_cmp)
                {
                    case (true) {
                    switch ((lhs.ty.kind == LK.FLOAT | lhs.ty.kind == LK.DOUBLE) & (rhs.ty.kind == LK.FLOAT | rhs.ty.kind == LK.DOUBLE))
                    {
                        case (true) {
                        switch (lhs.ty.kind == LK.FLOAT & rhs.ty.kind == LK.DOUBLE)
                        {
                            case (true) {
                            lhs = this.mod.cast(g"fpext\0", lhs, this.t_double, g"float_to_double_lhs\0");
                        }
                            default {
                                switch (lhs.ty.kind == LK.DOUBLE & rhs.ty.kind == LK.FLOAT)
                                {
                                    case (true) {
                            rhs = this.mod.cast(g"fpext\0", rhs, this.t_double, g"float_to_double_rhs\0");
                        }
                                    default {};
                                };
                            };
                        };
                        -> this.mod.fcmp(this.fp_pred(op), lhs, rhs, (byte*)0);
                    }
                        default {};
                    };
                    switch (lp | rp)
                    {
                        case (true) {
                        switch (lp)
                        {
                            case (true) { lhs = this.mod.cast(g"ptrtoint\0", lhs, this.t_i64, (byte*)0); }
                            default {};
                        };
                        switch (rp)
                        {
                            case (true) { rhs = this.mod.cast(g"ptrtoint\0", rhs, this.t_i64, (byte*)0); }
                            default {};
                        };
                        -> this.mod.icmp(this.int_pred(op, true), lhs, rhs, (byte*)0);
                    }
                        default {};
                    };
                    switch (lhs.ty.kind != LK.INT | rhs.ty.kind != LK.INT)
                    {
                        case (true) {
                        this.unsup(n, g"comparison operand types\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    uns = this.is_uns(lhs) | this.is_uns(rhs);
                    switch (lhs.ty.width != rhs.ty.width)
                    {
                        case (true) {
                        this.normalize_ints(lhs, rhs, uns, true);
                        lhs = this.nra;
                        rhs = this.nrb;
                    }
                        default {};
                    };
                    -> this.mod.icmp(this.int_pred(op, uns), lhs, rhs, (byte*)0);
                }
                    default {};
                };
                switch (op == Operator.BITAND | op == Operator.BITOR | op == Operator.BITXOR)
                {
                    case (true) {
                    switch (lhs.ty.kind != LK.INT | rhs.ty.kind != LK.INT)
                    {
                        case (true) {
                        this.unsup(n, g"bitwise operand types\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    this.normalize_ints(lhs, rhs, true, true);
                    lhs = this.nra;
                    rhs = this.nrb;
                    switch (op)
                    {
                        case (Operator.BITAND) { r = this.mod.binop(g"and\0", lhs, rhs, (byte*)0); }
                        case (Operator.BITOR) { r = this.mod.binop(g"or\0", lhs, rhs, (byte*)0); }
                        default { r = this.mod.binop(g"xor\0", lhs, rhs, (byte*)0); };
                    };
                    switch (this.is_uns(lhs) | this.is_uns(rhs))
                    {
                        case (true) { r.spec = this.lit_spec(DataType.UINT); }
                        default { r.spec = this.lit_spec(DataType.SINT); };
                    };
                    -> r;
                }
                    default {};
                };
                switch (op == Operator.AND | op == Operator.OR | op == Operator.XOR)
                {
                    case (true) {
                    switch (lhs.ty.kind == LK.INT & rhs.ty.kind == LK.INT)
                    {
                        case (true) {
                        switch (lhs.ty.width != rhs.ty.width)
                        {
                            case (true) {
                            this.normalize_ints(lhs, rhs, true, true);
                            lhs = this.nra;
                            rhs = this.nrb;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (op)
                    {
                        case (Operator.AND) { r = this.mod.binop(g"and\0", lhs, rhs, (byte*)0); }
                        case (Operator.OR) { r = this.mod.binop(g"or\0", lhs, rhs, (byte*)0); }
                        default { r = this.mod.binop(g"xor\0", lhs, rhs, (byte*)0); };
                    };
                    switch (this.is_uns(lhs) | this.is_uns(rhs))
                    {
                        case (true) { r.spec = this.lit_spec(DataType.UINT); }
                        default { r.spec = this.lit_spec(DataType.SINT); };
                    };
                    -> r;
                }
                    default {};
                };
                switch (op == Operator.BITSHIFT_LEFT | op == Operator.BITSHIFT_RIGHT)
                {
                    case (true) {
                    switch (lhs.ty.kind != LK.INT | rhs.ty.kind != LK.INT)
                    {
                        case (true) {
                        this.unsup(n, g"shift operand types\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (lhs.ty.width != rhs.ty.width)
                    {
                        case (true) {
                        switch (rhs.ty.width < lhs.ty.width)
                        {
                            case (true) { rhs = this.mod.cast(g"zext\0", rhs, lhs.ty, (byte*)0); }
                            default { rhs = this.mod.cast(g"trunc\0", rhs, lhs.ty, (byte*)0); };
                        };
                    }
                        default {};
                    };
                    switch (op == Operator.BITSHIFT_LEFT)
                    {
                        case (true) { r = this.mod.binop(g"shl\0", lhs, rhs, (byte*)0); }
                        default {
                            switch (this.is_uns(lhs) | lhs.spec == (TypeSpec*)0)
                            {
                                case (true) { r = this.mod.binop(g"lshr\0", lhs, rhs, (byte*)0); }
                                default { r = this.mod.binop(g"ashr\0", lhs, rhs, (byte*)0); };
                            };
                        };
                    };
                    switch (this.is_uns(lhs))
                    {
                        case (true) { r.spec = this.lit_spec(DataType.UINT); }
                        default { r.spec = this.lit_spec(DataType.SINT); };
                    };
                    -> r;
                }
                    default {};
                };
                switch (op == Operator.NOR | op == Operator.NAND | op == Operator.BITNAND | op == Operator.BITNOR | op == Operator.BITXNOR)
                {
                    case (true) {
                    switch (op == Operator.NOR | op == Operator.BITNOR)
                    {
                        case (true) { r = this.mod.binop(g"or\0", lhs, rhs, (byte*)0); }
                        default {
                            switch (op == Operator.NAND | op == Operator.BITNAND)
                            {
                                case (true) { r = this.mod.binop(g"and\0", lhs, rhs, (byte*)0); }
                                default { r = this.mod.binop(g"xor\0", lhs, rhs, (byte*)0); };
                            };
                        };
                    };
                    r = this.mod.binop(g"xor\0", r, this.mod.c_int(r.ty, (i64)(0 - 1)), (byte*)0);
                    switch (op != Operator.NOR & op != Operator.NAND)
                    {
                        case (true) {
                        switch (this.is_uns(lhs) | this.is_uns(rhs))
                        {
                            case (true) { r.spec = this.lit_spec(DataType.UINT); }
                            default { r.spec = this.lit_spec(DataType.SINT); };
                        };
                    }
                        default {};
                    };
                    -> r;
                }
                    default {};
                };
                this.unsup(n, g"binary operator\0");
                -> (IRValue*)0;
            };

            // ----------------------------------------------------------
            // Calls
            // ----------------------------------------------------------

            // _funcall_is_fp_variable: the callee name is a variable holding a function pointer
            is_fp_var(byte* name) -> bool
            {
                LVar* lv = this.find_local(name);
                IRType* pe;
                switch (lv != (LVar*)0)
                {
                    case (true) {
                    switch (lv.ptr.ty.kind != LK.PTR)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    pe = lv.ptr.ty.elem;
                    switch (pe.kind == LK.FUNC)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    switch (pe.kind == LK.PTR)
                    {
                        case (true) { -> pe.elem.kind == LK.FUNC; }
                        default {};
                    };
                    -> false;
                }
                    default {};
                };
                lv = this.find_global_var(name);
                switch (lv == (LVar*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (lv.ptr.ty.kind != LK.PTR)
                {
                    case (true) { -> false; }
                    default {};
                };
                pe = lv.ptr.ty.elem;
                -> pe.kind == LK.FUNC | pe.kind == LK.PTR;
            };

            // visit_FunctionPointerCall for a call spelled as name(args)
            x_fpcall(Node* n) -> IRValue*
            {
                Node* idn = node_new(NodeKind.IDENTIFIER, n.line, n.col);
                IRValue* pv;
                IRValue* fpv;
                IRValue* v;
                IRValue** args;
                IRType* pe;
                IRType* ft;
                Node* an;
                int argc = node_count(n, 0);
                int i;
                this.keep((void*)idn);
                idn.text = n.text;
                pv = this.visit(idn);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (pv == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"function pointer value\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                fpv = pv;
                switch (pv.ty.kind == LK.PTR)
                {
                    case (true) {
                    pe = pv.ty.elem;
                    switch (pe.kind)
                    {
                        case (LK.FUNC) { fpv = pv; }
                        default { fpv = this.mod.load(pv, g"fp_load\0"); };
                    };
                }
                    default {};
                };
                switch (fpv.ty.kind != LK.PTR)
                {
                    case (true) {
                    this.unsup(n, g"function pointer type\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (fpv.ty.elem.kind != LK.FUNC)
                {
                    case (true) {
                    this.unsup(n, g"function pointer type\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                ft = fpv.ty.elem;
                args = (IRValue**)this.zbuf(argc + 1);
                i = 0;
                while (i < argc)
                {
                    an = node_child(n, 0, i);
                    v = this.visit(an);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (v == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(n, g"void call argument\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    args[i] = v;
                    i++;
                };
                i = 0;
                while (i < argc & i < ft.nitems)
                {
                    args[i] = this.convert_arg(args[i], ft.items[i], i, n);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    i++;
                };
                -> this.mod.call_ex(fpv, args, argc, g"fp_call\0", (byte*)0, false);
            };

            x_call(Node* n) -> IRValue*
            {
                int argc = node_count(n, 0);
                int i;
                int total;
                IRFunc* f;
                IRValue** args;
                IRValue* v;
                IRValue* r;
                IRType* ft;
                Node* an;
                Node* dn;
                switch (n.text != (byte*)0)
                {
                    case (true) {
                    switch (this.is_fp_var(n.text))
                    {
                        case (true) { -> this.x_fpcall(n); }
                        default {};
                    };
                }
                    default {};
                };
                switch (n.text3 == (byte*)0)
                {
                    case (true) {
                    this.unsup(n, g"call target not resolved\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                f = this.mod.find_function(n.text3);
                switch (f == (IRFunc*)0 & n.text != (byte*)0)
                {
                    case (true) {
                    // Extern prototypes and no-mangle functions carry their plain symbol name
                    f = this.mod.find_function(n.text);
                }
                    default {};
                };
                switch (f == (IRFunc*)0)
                {
                    case (true) {
                    this.unsup(n, g"call target not declared\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                ft = f.ftype;
                total = argc;
                switch (ft.nitems > total & !ft.vararg)
                {
                    case (true) { total = ft.nitems; }
                    default {};
                };
                args = (IRValue**)fmalloc((u64)(total + 1) * (u64)((sizeof(IRValue*) + 7) / 8));
                this.keep((void*)args);
                i = 0;
                while (i < argc)
                {
                    an = node_child(n, 0, i);
                    switch (an.kind == NodeKind.IDENTIFIER)
                    {
                        case (true) {
                        switch (this.local_flag(an.text, TS_LOCAL))
                        {
                            case (true) {
                            this.unsup(n, g"local variable leaves scope\0");
                            -> (IRValue*)0;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    v = this.visit(an);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (v == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(n, g"void call argument\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    args[i] = v;
                    i++;
                };
                i = argc;
                while (i < total)
                {
                    dn = this.default_of(f, n, i);
                    switch (dn == (Node*)0)
                    {
                        case (true) {
                        this.unsup(n, g"missing call argument\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    v = this.visit(dn);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    args[i] = v;
                    i++;
                };
                i = 0;
                while (i < total & i < ft.nitems)
                {
                    args[i] = this.convert_arg(args[i], ft.items[i], i, n);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    i++;
                };
                // Base compiler's pointer-param overload shortcut names every call
                // with no arguments op_overload_result, unless the call spells the mangled symbol
                switch (argc == 0 & !this.spells_mangled(n.text) & nm_get(this.fdefs, f.name) != (void*)0)
                {
                    case (true) { r = this.mod.call_ex(f.self, args, total, g"op_overload_result\0", f.cconv, this.fn == f); }
                    default { r = this.mod.call_ex(f.self, args, total, (byte*)0, f.cconv, this.fn == f); };
                };
                -> r;
            };

            // True when a call name is already a mangled symbol (contains __ret_)
            spells_mangled(byte* s) -> bool
            {
                int i;
                switch (s == (byte*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                while (s[i] != 0)
                {
                    switch (s[i] == '_' & s[i + 1] == '_' & s[i + 2] == 'r' & s[i + 3] == 'e' & s[i + 4] == 't' & s[i + 5] == '_')
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // Default argument expression of parameter i for the function f
            default_of(IRFunc* f, Node* call, int i) -> Node*
            {
                Node* fd = (Node*)nm_get(this.fdefs, f.name);
                Node* p;
                switch (fd == (Node*)0)
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                switch (i >= node_count(fd, 0))
                {
                    case (true) { -> (Node*)0; }
                    default {};
                };
                p = node_child(fd, 0, i);
                -> p.a;
            };

            // True when the variable name has the TypeSpec flag
            local_flag(byte* name, int flag) -> bool
            {
                LVar* lv = this.find_var(name);
                switch (lv == (LVar*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (lv.ts == (TypeSpec*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> (lv.ts.flags `& flag) != 0;
            };

            // ----------------------------------------------------------
            // Assignment
            // ----------------------------------------------------------

            // AssignmentTypeHandler.handle_identifier_assignment (locals)
            assign_ident(Node* target, IRValue* val, Node* value_expr) -> IRValue*
            {
                LVar* lv = this.find_var(target.text);
                IRValue* v;
                IRValue* st_v;
                switch (lv == (LVar*)0)
                {
                    case (true) {
                    this.unsup(target, g"assign to non-local\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (lv.ts != (TypeSpec*)0)
                {
                    case (true) {
                    switch ((lv.ts.flags `& TS_CONST) != 0)
                    {
                        case (true) {
                        this.unsup(target, g"assign to const\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch ((lv.ts.flags `& TS_CONST_POINTER) != 0)
                    {
                        case (true) {
                        this.unsup(target, g"assign to const pointer\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (value_expr.kind == NodeKind.BINARY_OP)
                {
                    case (true) {
                    switch (value_expr.op == Operator.ADD & val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY)
                    {
                        case (true) {
                        this.unsup(target, g"array concatenation assign\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (value_expr.kind == NodeKind.ARRAY_LITERAL & lv.ptr.ty.elem.kind == LK.PTR)
                {
                    case (true) {
                    this.unsup(target, g"array literal to pointer assign\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                v = this.maybe_swap(val, lv.ptr);
                v = this.convert_assign(v, lv.ptr.ty.elem);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                this.mod.store(v, lv.ptr);
                -> v;
            };

            // Zeroed scratch block of n pointers, released with the module
            zbuf(int n) -> void*
            {
                byte* r = (byte*)fmalloc((u64)(8 * n));
                int i;
                while (i < 8 * n)
                {
                    r[i] = (byte)0;
                    i++;
                };
                this.keep((void*)r);
                -> (void*)r;
            };

            // Next quoted string at or after p in s: returns start of content, sets
            // this.q_len to its length and this.q_end past the closing quote, null when none
            next_quoted(byte* s, int p) -> int
            {
                int a;
                int b;
                while (s[p] != 0 & s[p] != '"') { p++; };
                switch (s[p] == 0)
                {
                    case (true) { -> -1; }
                    default {};
                };
                a = p + 1;
                b = a;
                while (s[b] != 0 & s[b] != '"') { b++; };
                switch (s[b] == 0)
                {
                    case (true) { -> -1; }
                    default {};
                };
                this.q_len = b - a;
                this.q_end = b + 1;
                -> a;
            };

            // Copy of s[a .. a+len)
            sub_dup(byte* s, int a, int len) -> byte*
            {
                byte* r = (byte*)fmalloc((u64)(len + 1));
                int i;
                while (i < len)
                {
                    r[i] = s[a + i];
                    i++;
                };
                r[len] = (byte)0;
                this.keep((void*)r);
                -> r;
            };

            // Reads "constraint"(var) pairs of one constraint section; returns pair count
            asm_pairs(byte* s, int a, int b, byte** cs, byte** vs) -> int
            {
                int p = a;
                int n = 0;
                int qs;
                int ql;
                int vs0;
                int ve;
                while (p < b & n < 16)
                {
                    while (p < b & s[p] != '"') { p++; };
                    switch (p >= b)
                    {
                        case (true) { break; }
                        default {};
                    };
                    qs = p + 1;
                    ql = qs;
                    while (ql < b & s[ql] != '"') { ql++; };
                    switch (ql >= b)
                    {
                        case (true) { break; }
                        default {};
                    };
                    p = ql + 1;
                    while (p < b & (s[p] == ' ' | s[p] == 9 | s[p] == 10 | s[p] == 13)) { p++; };
                    switch (p >= b | s[p] != '(')
                    {
                        case (true) { continue; }
                        default {};
                    };
                    vs0 = p + 1;
                    ve = vs0;
                    while (ve < b & s[ve] != ')') { ve++; };
                    switch (ve >= b | ve == vs0)
                    {
                        case (true) { break; }
                        default {};
                    };
                    cs[n] = this.sub_dup(s, qs, ql - qs);
                    vs[n] = this.sub_dup(s, vs0, ve - vs0);
                    n++;
                    p = ve + 1;
                };
                -> n;
            };

            // visit_InlineAsm
            x_asm(Node* n) -> IRValue*
            {
                byte* body = n.text;
                byte* cons = n.text2;
                byte** cs = (byte**)this.zbuf(16);
                byte** vs = (byte**)this.zbuf(16);
                byte** ocs = (byte**)this.zbuf(16);
                byte** ics = (byte**)this.zbuf(16);
                byte** fcs = (byte**)this.zbuf(40);
                IRValue** oops = (IRValue**)this.zbuf(16);
                IRValue** iops = (IRValue**)this.zbuf(16);
                IRValue** fin_ops = (IRValue**)this.zbuf(40);
                byte** clob = (byte**)this.zbuf(16);
                IRType** itys = (IRType**)this.zbuf(40);
                IRType** otys = (IRType**)this.zbuf(16);
                IRValue** ro_ptr = (IRValue**)this.zbuf(16);
                int ncs;
                int no;
                int ni;
                int nclob;
                int nfin;
                int nfc;
                int nro;
                int i;
                int j;
                int p0;
                int p1;
                int len;
                int a;
                int ls;
                int le;
                int ts;
                int te;
                int qs;
                IRValue* v;
                IRValue* res;
                IRValue* callee;
                IRType* rty;
                IRType* ft;
                LVar* lv;
                byte* c;
                bool first = true;
                switch (body == (byte*)0)
                {
                    case (true) { body = g"\0"; }
                    default {};
                };
                // asm text: non-empty, non-comment lines joined with newlines
                this.asmb.clear();
                i = 0;
                while (body[i] != 0 | i == 0)
                {
                    ls = i;
                    while (body[i] != 0 & body[i] != 10) { i++; };
                    le = i;
                    ts = ls;
                    te = le;
                    while (ts < te & (body[ts] == ' ' | body[ts] == 9 | body[ts] == 13)) { ts++; };
                    while (te > ts & (body[te - 1] == ' ' | body[te - 1] == 9 | body[te - 1] == 13)) { te--; };
                    switch (te > ts)
                    {
                        case (true) {
                        switch (!(body[ts] == '/' & body[ts + 1] == '/'))
                        {
                            case (true) {
                            switch (!first)
                            {
                                case (true) { this.asmb.put(10); }
                                default {};
                            };
                            first = false;
                            j = ls;
                            while (j < le)
                            {
                                this.asmb.put((int)body[j]);
                                j++;
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (body[i] == 0)
                    {
                        case (true) { break; }
                        default {};
                    };
                    i++;
                };
                // sections split at ':'
                p0 = -1;
                p1 = -1;
                len = 0;
                switch (cons != (byte*)0)
                {
                    case (true) {
                    while (cons[len] != 0)
                    {
                        switch (cons[len] == ':')
                        {
                            case (true) {
                            switch (p0 < 0)
                            {
                                case (true) { p0 = len; }
                                default {
                                    switch (p1 < 0)
                                    {
                                        case (true) { p1 = len; }
                                        default {};
                                    };
                                };
                            };
                        }
                            default {};
                        };
                        len++;
                    };
                }
                    default {};
                };
                no = 0;
                ni = 0;
                nclob = 0;
                switch (cons != (byte*)0)
                {
                    case (true) {
                    int oe = len;
                    int ie = len;
                    switch (p0 >= 0)
                    {
                        case (true) { oe = p0; }
                        default {};
                    };
                    switch (p1 >= 0)
                    {
                        case (true) { ie = p1; }
                        default {
                            switch (p0 >= 0)
                            {
                                case (true) { ie = len; }
                                default {};
                            };
                        };
                    };
                    ncs = this.asm_pairs(cons, 0, oe, cs, vs);
                    i = 0;
                    while (i < ncs)
                    {
                        c = cs[i];
                        switch (c[0] != '=' & c[0] != '+')
                        {
                            case (true) {
                            this.sc.clear();
                            this.sc.put(61);
                            this.sc.put_str(c);
                            c = this.sub_dup(this.sc.mem, 0, this.sc.len);
                        }
                            default {};
                        };
                        lv = this.find_var(vs[i]);
                        switch (lv != (LVar*)0)
                        {
                            case (true) {
                            oops[no] = lv.ptr;
                            ocs[no] = c;
                            no++;
                        }
                            default {};
                        };
                        i++;
                    };
                    switch (p0 >= 0)
                    {
                        case (true) {
                        ncs = this.asm_pairs(cons, p0 + 1, ie, cs, vs);
                        i = 0;
                        while (i < ncs)
                        {
                            lv = this.find_var(vs[i]);
                            switch (lv != (LVar*)0)
                            {
                                case (true) {
                                v = lv.ptr;
                                switch (cstr_eq(cs[i], g"m\0") | (v.ty.kind == LK.PTR & v.ty.elem.kind == LK.ARRAY))
                                {
                                    case (true) { iops[ni] = v; }
                                    default {
                                    this.sc.clear();
                                    this.sc.put_str(vs[i]);
                                    this.sc.put_str(g"_load\0");
                                    iops[ni] = this.mod.load(v, this.sc.mem);
                                };
                                };
                                ics[ni] = cs[i];
                                ni++;
                            }
                                default {};
                            };
                            i++;
                        };
                    }
                        default {};
                    };
                    switch (p1 >= 0)
                    {
                        case (true) {
                        a = p1 + 1;
                        while (nclob < 16)
                        {
                            qs = this.next_quoted(cons, a);
                            switch (qs < 0)
                            {
                                case (true) { break; }
                                default {};
                            };
                            clob[nclob] = this.sub_dup(cons, qs, this.q_len);
                            nclob++;
                            a = this.q_end;
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                // translate register letters of the outputs
                i = 0;
                while (i < no)
                {
                    c = ocs[i];
                    a = 0;
                    switch (c[0] == '=' | c[0] == '+')
                    {
                        case (true) { a = 1; }
                        default {};
                    };
                    switch (c[a + 1] == 0)
                    {
                        case (true) {
                        byte* rn = (byte*)0;
                        switch (c[a] == 'a')
                        {
                            case (true) { rn = g"rax\0"; }
                            default {
                                switch (c[a] == 'b')
                                {
                                    case (true) { rn = g"rbx\0"; }
                                    default {
                                        switch (c[a] == 'c')
                                        {
                                            case (true) { rn = g"rcx\0"; }
                                            default {
                                                switch (c[a] == 'd')
                                                {
                                                    case (true) { rn = g"rdx\0"; }
                                                    default {
                                                        switch (c[a] == 'S')
                                                        {
                                                            case (true) { rn = g"rsi\0"; }
                                                            default {
                                                                switch (c[a] == 'D')
                                                                {
                                                                    case (true) { rn = g"rdi\0"; }
                                                                    default {};
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
                        switch (rn != (byte*)0)
                        {
                            case (true) {
                            this.sc.clear();
                            switch (a == 1)
                            {
                                case (true) { this.sc.put((int)c[0]); }
                                default {};
                            };
                            this.sc.put(123);
                            this.sc.put_str(rn);
                            this.sc.put(125);
                            ocs[i] = this.sub_dup(this.sc.mem, 0, this.sc.len);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                // final operand and constraint lists: inputs, then outputs inserted at the front
                nfin = 0;
                nfc = 0;
                i = 0;
                while (i < ni)
                {
                    fin_ops[nfin] = iops[i];
                    nfin++;
                    fcs[nfc] = ics[i];
                    nfc++;
                    i++;
                };
                nro = 0;
                i = 0;
                while (i < no)
                {
                    c = ocs[i];
                    switch (c[0] == '=' | c[0] == '+')
                    {
                        case (true) {
                        switch (c[1] == 'm')
                        {
                            case (true) {
                            j = nfin;
                            while (j > 0)
                            {
                                fin_ops[j] = fin_ops[j - 1];
                                j--;
                            };
                            fin_ops[0] = oops[i];
                            nfin++;
                            switch (c[0] == '=')
                            {
                                case (true) {
                                this.sc.clear();
                                this.sc.put(43);
                                this.sc.put_str(c + 1);
                                c = this.sub_dup(this.sc.mem, 0, this.sc.len);
                            }
                                default {};
                            };
                        }
                            default {
                            ro_ptr[nro] = oops[i];
                            nro++;
                        };
                        };
                    }
                        default {
                        ro_ptr[nro] = oops[i];
                        nro++;
                    };
                    };
                    j = nfc;
                    while (j > 0)
                    {
                        fcs[j] = fcs[j - 1];
                        j--;
                    };
                    fcs[0] = c;
                    nfc++;
                    i++;
                };
                this.asmc.clear();
                i = 0;
                while (i < nfc)
                {
                    switch (i > 0)
                    {
                        case (true) { this.asmc.put(44); }
                        default {};
                    };
                    this.asmc.put_str(fcs[i]);
                    i++;
                };
                i = 0;
                while (i < nclob)
                {
                    switch (nfc > 0 | i > 0)
                    {
                        case (true) { this.asmc.put(44); }
                        default {};
                    };
                    this.asmc.put_str(g"~{\0");
                    this.asmc.put_str(clob[i]);
                    this.asmc.put(125);
                    i++;
                };
                i = 0;
                while (i < nfin)
                {
                    itys[i] = fin_ops[i].ty;
                    i++;
                };
                switch (nro)
                {
                    case (0) { rty = this.t_void; }
                    case (1) { rty = ro_ptr[0].ty.elem; }
                    default
                    {
                        i = 0;
                        while (i < nro)
                        {
                            otys[i] = ro_ptr[i].ty.elem;
                            i++;
                        };
                        rty = this.mod.t_struct(otys, nro);
                    };
                };
                ft = this.mod.t_func(rty, itys, nfin, false);
                // llvmlite prints asm, sideeffect flag, body and constraints verbatim
                this.sc.clear();
                this.sc.put_str(g"asm \0");
                switch ((n.flags `& NF_VOLATILE) != 0)
                {
                    case (true) { this.sc.put_str(g"sideeffect\0"); }
                    default {};
                };
                this.sc.put_str(g" \"\0");
                this.sc.put_str(this.asmb.mem);
                this.sc.put_str(g"\", \"\0");
                this.sc.put_str(this.asmc.mem);
                this.sc.put_str(g"\"\n\0");
                callee = this.mod.new_value(this.mod.t_ptr(ft), this.sc.mem);
                res = this.mod.call(callee, fin_ops, nfin, (byte*)0);
                switch (nro == 1)
                {
                    case (true) { this.mod.store(res, ro_ptr[0]); }
                    default {
                        switch (nro > 1)
                        {
                            case (true) {
                    i = 0;
                    while (i < nro)
                    {
                        v = this.mod.extractvalue(res, i, (byte*)0);
                        this.mod.store(v, ro_ptr[i]);
                        i++;
                    };
                }
                            default {};
                        };
                    };
                };
                -> res;
            };

            // visit_MethodCall for object receivers
            x_method(Node* n) -> IRValue*
            {
                Node* o = n.a;
                int argc = node_count(n, 0);
                int i;
                LVar* lv;
                IRValue* objp;
                IRValue* thisp;
                IRValue* v;
                IRValue** args;
                IRFunc* f;
                IRType* ft;
                IRType* sp;
                byte* vname = (byte*)0;
                switch (n.text3 == (byte*)0)
                {
                    case (true) {
                    this.unsup(n, g"method target not resolved\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (o.kind)
                {
                    case (NodeKind.IDENTIFIER)
                    {
                        lv = this.find_local(o.text);
                        switch (lv == (LVar*)0)
                        {
                            case (true) {
                            this.unsup(n, g"method call on non-local\0");
                            -> (IRValue*)0;
                        }
                            default {};
                        };
                        objp = lv.ptr;
                        vname = o.text;
                    }
                    default
                    {
                        objp = this.visit(o);
                        switch (this.bad)
                        {
                            case (true) { -> (IRValue*)0; }
                            default {};
                        };
                    };
                };
                switch (objp == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void method receiver\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (objp.ty.kind != LK.PTR)
                {
                    case (true) {
                    this.unsup(n, g"type function call\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                sp = objp.ty.elem;
                switch (sp.kind == LK.ISTRUCT)
                {
                    case (true) { thisp = objp; }
                    default {
                        switch (sp.kind == LK.PTR & sp.elem.kind == LK.ISTRUCT)
                        {
                            case (true) {
                    this.sc.clear();
                    switch (vname != (byte*)0)
                    {
                        case (true) {
                        this.sc.put_str(vname);
                        this.sc.put_str(g"_load\0");
                    }
                        default { this.sc.put_str(g"obj_load\0"); };
                    };
                    thisp = this.mod.load(objp, this.sc.mem);
                }
                            default {
                    this.unsup(n, g"type function call\0");
                    -> (IRValue*)0;
                };
                        };
                    };
                };
                f = this.mod.find_function(n.text3);
                switch (f == (IRFunc*)0)
                {
                    case (true) {
                    this.unsup(n, g"method not declared\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                ft = f.ftype;
                args = (IRValue**)fmalloc((u64)(8 * (argc + 1)));
                this.keep((void*)args);
                args[0] = thisp;
                i = 0;
                while (i < argc)
                {
                    v = this.visit(node_child(n, 0, i));
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (v == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(n, g"void method argument\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    args[i + 1] = v;
                    i++;
                };
                i = 0;
                while (i < argc & i + 1 < ft.nitems)
                {
                    v = args[i + 1];
                    switch (v.ty.kind == LK.PTR & ft.items[i + 1].kind == LK.PTR)
                    {
                        case (true) {
                        switch (v.ty.elem.kind == LK.ARRAY)
                        {
                            case (true) {
                            switch (lt_eq(v.ty.elem.elem, ft.items[i + 1].elem))
                            {
                                case (true) {
                                this.sc.clear();
                                this.sc.put_str(g"marg\0");
                                this.sc.put_int(i);
                                this.sc.put_str(g"_decay\0");
                                this.mod.ia[0] = this.ci32(0);
                                this.mod.ia[1] = this.ci32(0);
                                v = this.mod.gep(v, this.mod.ia, 2, false, this.sc.mem);
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    args[i + 1] = this.convert_arg(v, ft.items[i + 1], i, n);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    i++;
                };
                -> this.mod.call_ex(f.self, args, argc + 1, (byte*)0, f.cconv, false);
            };

            // visit_NotNull: compare against null or zero, widened to i8
            i1_lit(byte* txt) -> IRValue*
            {
                IRValue* v = this.mod.new_value(this.t_i1, txt);
                v.is_const = true;
                -> v;
            };

            // 'needle in haystack' for byte* needle and byte* haystack (NUL terminated substring search)
            // Pops the terminator of b so more instructions can be added; returns the line
            pop_term(IRBlock* b) -> void*
            {
                void* tl = (void*)0;
                switch (b.terminated)
                {
                    case (true) {
                    tl = b.lines.items[b.lines.len - 1];
                    b.lines.len = b.lines.len - 1;
                    b.terminated = false;
                }
                    default {};
                };
                -> tl;
            };

            // Puts a popped terminator line back without renumbering
            push_term(IRBlock* b, void* tl) -> void
            {
                switch (tl == (void*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                pv_push(b.lines, tl);
                b.terminated = true;
                ->;
            };

            // Loads a branch value in its (reopened) end block and re-branches to merge
            tern_load(IRValue* v, IRBlock* eb, IRBlock* mb) -> IRValue*
            {
                IRValue* r;
                this.pop_term(eb);
                this.mod.position(this.fn, eb);
                r = this.mod.load(v, g"ternary_load\0");
                this.mod.br(mb);
                this.mod.position(this.fn, mb);
                -> r;
            };

            // Array pointer decays to an element pointer in front of the block terminator
            tern_decay(IRValue* v, IRBlock* eb, IRBlock* mb) -> IRValue*
            {
                IRValue* r = v;
                void* tl;
                switch (v.ty.elem.kind == LK.ARRAY)
                {
                    case (true) {
                    tl = this.pop_term(eb);
                    this.mod.position(this.fn, eb);
                    r = this.mod.cast(g"bitcast\0", v, this.ptr_of(v.ty.elem.elem), g"ternary_decay\0");
                    this.push_term(eb, tl);
                    this.mod.position(this.fn, mb);
                }
                    default {};
                };
                -> r;
            };

            // Double held in the text of a floating constant ("   0x3ff0000000000000")
            fp_const_value(IRValue* v) -> double
            {
                int i;
                u64 bits;
                u64* bp;
                double d;
                int c;
                byte* t = v.text;
                while (t[i] == 32) { i++; };
                switch (t[i] == '0' & t[i + 1] == 'x')
                {
                    case (true) { i = i + 2; }
                    default {};
                };
                while (t[i] != 0)
                {
                    c = (int)t[i];
                    switch (c >= '0' & c <= '9')
                    {
                        case (true) { bits = bits * (u64)16 + (u64)(c - '0'); }
                        default {
                            switch (c >= 'a' & c <= 'f')
                            {
                                case (true) { bits = bits * (u64)16 + (u64)(c - 'a' + 10); }
                                default {
                                    switch (c >= 'A' & c <= 'F')
                                    {
                                        case (true) { bits = bits * (u64)16 + (u64)(c - 'A' + 10); }
                                        default {};
                                    };
                                };
                            };
                        };
                    };
                    i++;
                };
                bp = (u64*)@d;
                *bp = bits;
                -> d;
            };

            // StructTypeHandler.pack_struct_literal. ctx is the struct type when the
            // surrounding declaration gives one, else the literal's own type name is resolved.
            x_struct_lit(Node* n, IRType* ctx) -> IRValue*
            {
                IRType* st = ctx;
                SInfo* si;
                Node** exprs;
                IRValue** vals;
                IRValue* fv;
                IRValue* res;
                IRType* ft;
                IRValue* gz;
                IRValue** gp;
                Buf cb;
                int nf;
                int np;
                int nn;
                int i;
                int j;
                bool has_non = false;
                switch (st == (IRType*)0)
                {
                    case (true) {
                    switch (n.text == (byte*)0)
                    {
                        case (true) {
                        this.unsup(n, g"struct literal type context\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    st = this.resolve_custom(n.text);
                    switch (st == (IRType*)0)
                    {
                        case (true) {
                        this.unsup(n, g"struct literal type\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                si = this.sinfo_of(st);
                switch (si == (SInfo*)0)
                {
                    case (true) {
                    this.unsup(n, g"struct literal type\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                nf = si.n;
                np = node_count(n, 2);
                nn = node_count(n, 0);
                switch (np > nf)
                {
                    case (true) {
                    this.unsup(n, g"too many struct initializers\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                exprs = (Node**)this.zbuf(nf + 1);
                vals = (IRValue**)this.zbuf(nf + 1);
                while (i < nn)
                {
                    j = 0;
                    while (j < nf)
                    {
                        switch (cstr_eq(si.names[j], node_child(n, 0, i).text))
                        {
                            case (true) { break; }
                            default {};
                        };
                        j++;
                    };
                    switch (j >= nf)
                    {
                        case (true) {
                        this.unsup(n, g"struct literal field\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    exprs[j] = node_child(n, 1, i);
                    i++;
                };
                i = 0;
                while (i < np)
                {
                    exprs[i] = node_child(n, 2, i);
                    i++;
                };
                i = 0;
                while (i < nf)
                {
                    switch (exprs[i] != (Node*)0)
                    {
                        case (true) {
                        fv = this.visit(exprs[i]);
                        switch (this.bad)
                        {
                            case (true) { -> (IRValue*)0; }
                            default {};
                        };
                        switch (fv == (IRValue*)0)
                        {
                            case (true) {
                            this.unsup(n, g"void struct field value\0");
                            -> (IRValue*)0;
                        }
                            default {};
                        };
                        switch (!fv.is_const)
                        {
                            case (true) { has_non = true; }
                            default {};
                        };
                        vals[i] = fv;
                    }
                        default { vals[i] = this.mod.c_null(si.ftys[i]); };
                    };
                    i++;
                };
                switch (!has_non)
                {
                    case (true) {
                    // All constants: widths and float kinds are converted in place
                    i = 0;
                    while (i < nf)
                    {
                        fv = vals[i];
                        ft = si.ftys[i];
                        switch (!lt_eq(fv.ty, ft))
                        {
                            case (true) {
                            switch (fv.ty.kind == LK.INT & ft.kind == LK.INT)
                            {
                                case (true) { vals[i] = this.mod.new_value(ft, fv.text); vals[i].is_const = true; }
                                default {
                                    switch ((fv.ty.kind == LK.FLOAT | fv.ty.kind == LK.DOUBLE) & (ft.kind == LK.FLOAT | ft.kind == LK.DOUBLE))
                                    {
                                        case (true) {
                                vals[i] = this.mod.c_fp(ft, this.fp_const_value(fv));
                            }
                                        default {};
                                    };
                                };
                            };
                        }
                            default {};
                        };
                        i++;
                    };
                }
                    default {};
                };
                cb.__init();
                defer cb.__exit();
                cb.put(123);
                i = 0;
                while (i < nf)
                {
                    switch (i > 0)
                    {
                        case (true) { cb.put_str(g", \0"); }
                        default {};
                    };
                    lt_text(@cb, vals[i].ty);
                    cb.put(32);
                    cb.put_str(vals[i].text);
                    i++;
                };
                cb.put(125);
                switch (!has_non)
                {
                    case (true) {
                    res = this.mod.new_value(st, cb.mem);
                    res.is_const = true;
                    -> res;
                }
                    default {};
                };
                // Zeroed struct constant, then one insertvalue per field
                i = 0;
                cb.clear();
                cb.put(123);
                while (i < nf)
                {
                    switch (i > 0)
                    {
                        case (true) { cb.put_str(g", \0"); }
                        default {};
                    };
                    fv = this.mod.c_null(si.ftys[i]);
                    lt_text(@cb, fv.ty);
                    cb.put(32);
                    cb.put_str(fv.text);
                    i++;
                };
                cb.put(125);
                res = this.mod.new_value(st, cb.mem);
                res.is_const = true;
                i = 0;
                while (i < nf)
                {
                    fv = vals[i];
                    ft = si.ftys[i];
                    switch (!lt_eq(fv.ty, ft))
                    {
                        case (true) {
                        switch (fv.ty.kind == LK.INT & ft.kind == LK.INT)
                        {
                            case (true) {
                            switch (fv.ty.width < ft.width)
                            {
                                case (true) { fv = this.mod.cast(g"zext\0", fv, ft, (byte*)0); }
                                default {
                                    switch (fv.ty.width > ft.width)
                                    {
                                        case (true) { fv = this.mod.cast(g"trunc\0", fv, ft, (byte*)0); }
                                        default {};
                                    };
                                };
                            };
                        }
                            default {
                                switch (fv.ty.kind == LK.FLOAT & ft.kind == LK.DOUBLE)
                                {
                                    case (true) { fv = this.mod.cast(g"fpext\0", fv, ft, (byte*)0); }
                                    default {
                                        switch (fv.ty.kind == LK.DOUBLE & ft.kind == LK.FLOAT)
                                        {
                                            case (true) { fv = this.mod.cast(g"fptrunc\0", fv, ft, (byte*)0); }
                                            default {
                                                switch (fv.ty.kind == LK.PTR & fv.ty.elem.kind == LK.ARRAY & ft.kind == LK.PTR)
                                                {
                                                    case (true) {
                            switch (ft.elem.kind == LK.INT & ft.elem.width == 8)
                            {
                                case (true) {
                                this.mod.ia[0] = this.ci32(0);
                                this.mod.ia[1] = this.ci32(0);
                                fv = this.mod.gep(fv, this.mod.ia, 2, true, g"str_gep\0");
                            }
                                default {};
                            };
                        }
                                                    default {};
                                                };
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    }
                        default {};
                    };
                    res = this.mod.insertvalue(res, fv, i, (byte*)0);
                    i++;
                };
                -> res;
            };

            // visit_TernaryOp
            x_ternary(Node* n) -> IRValue*
            {
                IRValue* cv;
                IRValue* tv;
                IRValue* fv;
                IRValue* phi;
                IRValue** pv;
                IRBlock** pb;
                IRBlock* tb;
                IRBlock* fb;
                IRBlock* mb;
                IRBlock* te;
                IRBlock* fe;
                void* tl;
                bool tp;
                bool fpp;
                cv = this.cond_value(n.a);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                tb = this.mod.append_block(this.fn, g"ternary_true\0");
                fb = this.mod.append_block(this.fn, g"ternary_false\0");
                mb = this.mod.append_block(this.fn, g"ternary_merge\0");
                this.mod.cbr(cv, tb, fb);

                this.mod.position(this.fn, tb);
                tv = this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                te = this.mod.cb;
                switch (!te.terminated)
                {
                    case (true) { this.mod.br(mb); }
                    default {};
                };

                this.mod.position(this.fn, fb);
                fv = this.visit(n.c);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                fe = this.mod.cb;
                switch (!fe.terminated)
                {
                    case (true) { this.mod.br(mb); }
                    default {};
                };

                this.mod.position(this.fn, mb);
                switch (tv == (IRValue*)0 | fv == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void ternary branch\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (!lt_eq(tv.ty, fv.ty))
                {
                    case (true) {
                    tp = tv.ty.kind == LK.PTR;
                    fpp = fv.ty.kind == LK.PTR;
                    switch (tp & lt_eq(tv.ty.elem, fv.ty))
                    {
                        case (true) { tv = this.tern_load(tv, te, mb); }
                        default {
                            switch (fpp & lt_eq(fv.ty.elem, tv.ty))
                            {
                                case (true) { fv = this.tern_load(fv, fe, mb); }
                                default {
                                    switch (tp & fpp)
                                    {
                                        case (true) {
                        tv = this.tern_decay(tv, te, mb);
                        fv = this.tern_decay(fv, fe, mb);
                        switch (!lt_eq(tv.ty, fv.ty))
                        {
                            case (true) {
                            switch (!(tv.ty.elem.kind == LK.ISTRUCT & fv.ty.elem.kind == LK.ISTRUCT & cstr_eq(tv.ty.elem.name, fv.ty.elem.name)))
                            {
                                case (true) {
                                tl = this.pop_term(fe);
                                this.mod.position(this.fn, fe);
                                fv = this.mod.cast(g"bitcast\0", fv, tv.ty, g"ternary_cast\0");
                                this.push_term(fe, tl);
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                        this.mod.position(this.fn, mb);
                    }
                                        default {
                                            switch (tp & (tv.ty.elem.kind == LK.INT | tv.ty.elem.kind == LK.FLOAT | tv.ty.elem.kind == LK.DOUBLE))
                                            {
                                                case (true) {
                        tv = this.tern_load(tv, te, mb);
                    }
                                                default {
                                                    switch (fpp & (fv.ty.elem.kind == LK.INT | fv.ty.elem.kind == LK.FLOAT | fv.ty.elem.kind == LK.DOUBLE))
                                                    {
                                                        case (true) {
                        fv = this.tern_load(fv, fe, mb);
                    }
                                                        default {
                                                            switch (tv.ty.kind == LK.INT & fv.ty.kind == LK.INT)
                                                            {
                                                                case (true) {
                        switch (tv.ty.width < fv.ty.width)
                        {
                            case (true) {
                            this.pop_term(te);
                            this.mod.position(this.fn, te);
                            tv = this.mod.cast(g"sext\0", tv, fv.ty, (byte*)0);
                            this.mod.br(mb);
                            this.mod.position(this.fn, mb);
                        }
                            default {
                                switch (fv.ty.width < tv.ty.width)
                                {
                                    case (true) {
                            this.pop_term(fe);
                            this.mod.position(this.fn, fe);
                            fv = this.mod.cast(g"sext\0", fv, tv.ty, (byte*)0);
                            this.mod.br(mb);
                            this.mod.position(this.fn, mb);
                        }
                                    default {};
                                };
                            };
                        };
                    }
                                                                default {
                        this.unsup(n, g"ternary incompatible branch types\0");
                        -> (IRValue*)0;
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
                }
                    default {};
                };
                pv = (IRValue**)this.zbuf(2);
                pb = (IRBlock**)this.zbuf(2);
                pv[0] = tv;
                pv[1] = fv;
                pb[0] = te;
                pb[1] = fe;
                phi = this.mod.phi(tv.ty, pv, pb, 2, g"ternary_result\0");
                -> phi;
            };

            x_in(Node* n) -> IRValue*
            {
                IRValue* nd = this.visit(n.a);
                IRValue* hy;
                IRValue* i0 = this.mod.c_int(this.t_i32, (i64)0);
                IRValue* i1v = this.mod.c_int(this.t_i32, (i64)1);
                IRValue* oidx;
                IRValue* oi;
                IRValue* hp;
                IRValue* hc;
                IRValue* ae;
                IRValue* ni;
                IRValue* hi;
                IRValue* oi2;
                IRValue* ni2;
                IRValue* hi2;
                IRValue* np;
                IRValue* nc;
                IRValue* ne;
                IRValue* nel;
                IRValue* hp2;
                IRValue* hel;
                IRValue* oob;
                IRValue* nev;
                IRValue* mm;
                IRValue* oi3;
                IRValue* nidx;
                IRValue* hidx;
                IRValue* res;
                IRValue** pv;
                IRBlock** pb;
                IRBlock* found_b;
                IRBlock* nf_b;
                IRBlock* merge_b;
                IRBlock* oc_b;
                IRBlock* ob_b;
                IRBlock* ic_b;
                IRBlock* ib_b;
                IRBlock* if_b;
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (!this.is_i8_ptr(nd.ty))
                {
                    case (true) {
                    this.unsup(n, g"in: needle type\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                hy = this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (!this.is_i8_ptr(hy.ty))
                {
                    case (true) {
                    this.unsup(n, g"in: haystack type\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                found_b = this.mod.append_block(this.fn, g"in.found\0");
                nf_b = this.mod.append_block(this.fn, g"in.notfound\0");
                merge_b = this.mod.append_block(this.fn, g"in.merge\0");
                oc_b = this.mod.append_block(this.fn, g"in.outer.cond\0");
                ob_b = this.mod.append_block(this.fn, g"in.outer.body\0");
                ic_b = this.mod.append_block(this.fn, g"in.inner.cond\0");
                ib_b = this.mod.append_block(this.fn, g"in.inner.body\0");
                if_b = this.mod.append_block(this.fn, g"in.inner.fail\0");
                oidx = this.mod.alloca_here(this.t_i32, g"in.outer.idx\0");
                this.mod.store(i0, oidx);
                this.mod.br(oc_b);
                this.mod.position(this.fn, oc_b);
                oi = this.mod.load(oidx, g"o.idx\0");
                hp = this.mod.gep_ptr(hy, oi, false, g"hay.ep\0");
                hc = this.mod.load(hp, g"hay.ch\0");
                ae = this.mod.icmp(g"eq\0", hc, this.mod.c_int(this.t_i8, (i64)0), g"hay.end\0");
                this.mod.cbr(ae, nf_b, ob_b);
                this.mod.position(this.fn, ob_b);
                nidx = this.mod.alloca_here(this.t_i32, g"in.ndl.idx\0");
                this.mod.store(i0, nidx);
                hidx = this.mod.alloca_here(this.t_i32, g"in.hay.idx\0");
                oi2 = this.mod.load(oidx, g"o.idx2\0");
                this.mod.store(oi2, hidx);
                this.mod.br(ic_b);
                this.mod.position(this.fn, ic_b);
                ni = this.mod.load(nidx, g"n.idx\0");
                np = this.mod.gep_ptr(nd, ni, false, g"ndl.ep\0");
                nc = this.mod.load(np, g"ndl.ch\0");
                ne = this.mod.icmp(g"eq\0", nc, this.mod.c_int(this.t_i8, (i64)0), g"ndl.end\0");
                this.mod.cbr(ne, found_b, ib_b);
                this.mod.position(this.fn, ib_b);
                ni2 = this.mod.load(nidx, g"n.idx2\0");
                hi2 = this.mod.load(hidx, g"h.idx2\0");
                np = this.mod.gep_ptr(nd, ni2, false, g"ndl.ep2\0");
                nel = this.mod.load(np, g"ndl.el\0");
                hp2 = this.mod.gep_ptr(hy, hi2, false, g"hay.ep2\0");
                hel = this.mod.load(hp2, g"hay.el\0");
                oob = this.mod.icmp(g"eq\0", hel, this.mod.c_int(this.t_i8, (i64)0), g"hay.oob\0");
                nev = this.mod.icmp(g"ne\0", hel, nel, g"el.ne\0");
                mm = this.mod.binop(g"or\0", oob, nev, g"mismatch\0");
                this.mod.store(this.mod.binop(g"add\0", ni2, i1v, (byte*)0), nidx);
                this.mod.store(this.mod.binop(g"add\0", hi2, i1v, (byte*)0), hidx);
                this.mod.cbr(mm, if_b, ic_b);
                this.mod.position(this.fn, if_b);
                oi3 = this.mod.load(oidx, g"o.idx3\0");
                this.mod.store(this.mod.binop(g"add\0", oi3, i1v, (byte*)0), oidx);
                this.mod.br(oc_b);
                this.mod.position(this.fn, found_b);
                this.mod.br(merge_b);
                this.mod.position(this.fn, nf_b);
                this.mod.br(merge_b);
                this.mod.position(this.fn, merge_b);
                pv = (IRValue**)this.zbuf(2);
                pb = (IRBlock**)this.zbuf(2);
                pv[0] = this.i1_lit(g"1\0");
                pv[1] = this.i1_lit(g"0\0");
                pb[0] = found_b;
                pb[1] = nf_b;
                res = this.mod.phi(this.t_i1, pv, pb, 2, g"in.result\0");
                switch ((n.flags `& NF_NEGATED) != 0)
                {
                    case (true) {
                    res = this.mod.binop(g"xor\0", res, this.i1_lit(g"-1\0"), g"notin.result\0");
                }
                    default {};
                };
                -> res;
            };

            x_notnull(Node* n) -> IRValue*
            {
                IRValue* v = this.visit(n.a);
                IRValue* c;
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (v == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"not-null void operand\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (v.ty.kind == LK.PTR)
                {
                    case (true) { c = this.mod.icmp(g"ne\0", v, this.mod.c_null(v.ty), g"not_null\0"); }
                    default {
                        switch (v.ty.kind == LK.INT)
                        {
                            case (true) { c = this.mod.icmp(g"ne\0", v, this.mod.c_int(v.ty, (i64)0), g"not_zero\0"); }
                            default {
                                switch (v.ty.kind == LK.FLOAT | v.ty.kind == LK.DOUBLE)
                                {
                                    case (true) { c = this.mod.fcmp(g"one\0", v, this.mod.c_fp(v.ty, 0.0), g"not_zero_f\0"); }
                                    default {
                    this.unsup(n, g"not-null operand type\0");
                    -> (IRValue*)0;
                };
                                };
                            };
                        };
                    };
                };
                -> this.mod.cast(g"zext\0", c, this.t_i8, g"not_null_result\0");
            };

            // Operator of a compound assignment token, -1 when unsupported
            compound_op(int tok) -> int
            {
                switch (tok)
                {
                    case (TokenType.PLUS_ASSIGN) { -> Operator.ADD; }
                    case (TokenType.MINUS_ASSIGN) { -> Operator.SUB; }
                    case (TokenType.MULTIPLY_ASSIGN) { -> Operator.MUL; }
                    case (TokenType.DIVIDE_ASSIGN) { -> Operator.DIV; }
                    case (TokenType.MODULO_ASSIGN) { -> Operator.MOD; }
                    case (TokenType.EXPONENT_ASSIGN) { -> Operator.POWER; }
                    case (TokenType.AND_ASSIGN) { -> Operator.AND; }
                    case (TokenType.OR_ASSIGN) { -> Operator.OR; }
                    case (TokenType.XOR_ASSIGN) { -> Operator.XOR; }
                    case (TokenType.BITAND_ASSIGN) { -> Operator.BITAND; }
                    case (TokenType.BITOR_ASSIGN) { -> Operator.BITOR; }
                    case (TokenType.BITXOR_ASSIGN) { -> Operator.BITXOR; }
                    case (TokenType.BITXNOR_ASSIGN) { -> Operator.BITXNOR; }
                    case (TokenType.BITNAND_ASSIGN) { -> Operator.BITNAND; }
                    case (TokenType.BITNOR_ASSIGN) { -> Operator.BITNOR; }
                    case (TokenType.BITSHIFT_LEFT_ASSIGN) { -> Operator.BITSHIFT_LEFT; }
                    case (TokenType.BITSHIFT_RIGHT_ASSIGN) { -> Operator.BITSHIFT_RIGHT; }
                    default {};
                };
                -> -1;
            };

            // handle_compound_assignment: t op= v is t = t op v. For an identifier
            // target with ADD the base evaluates both operands once before that.
            x_compound(Node* n) -> IRValue*
            {
                int op = this.compound_op(n.op);
                Node* bin;
                Node* asg;
                IRValue* pre;
                IRValue* r;
                switch (op < 0)
                {
                    case (true) {
                    this.unsup(n, g"compound operator\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (op == Operator.ADD & n.a.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    pre = this.visit(n.a);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    pre = this.visit(n.b);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (pre != (IRValue*)0)
                    {
                        case (true) {
                        switch (pre.ty.kind == LK.PTR)
                        {
                            case (true) {
                            switch (pre.ty.elem.kind == LK.ARRAY)
                            {
                                case (true) {
                                this.unsup(n, g"array concatenation\0");
                                -> (IRValue*)0;
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
                bin = node_new(NodeKind.BINARY_OP, n.line, n.col);
                bin.op = op;
                bin.a = n.a;
                bin.b = n.b;
                asg = node_new(NodeKind.ASSIGNMENT, n.line, n.col);
                asg.a = n.a;
                asg.b = bin;
                r = this.x_assign(asg);
                bin.a = (Node*)0;
                bin.b = (Node*)0;
                asg.a = (Node*)0;
                asg.b = (Node*)0;
                node_free(bin);
                node_free(asg);
                -> r;
            };

            x_assign(Node* n) -> IRValue*
            {
                Node* t = n.a;
                int tk = t.kind;
                IRValue* val;
                switch (tk != NodeKind.IDENTIFIER & tk != NodeKind.MEMBER_ACCESS & tk != NodeKind.ARRAY_ACCESS &
                    tk != NodeKind.POINTER_DEREF)
                {
                    case (true) {
                    this.unsup(n, g"assignment target\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (n.b.kind == NodeKind.ARRAY_LITERAL | n.b.kind == NodeKind.STRUCT_LITERAL)
                {
                    case (true) {
                    this.unsup(n, g"literal assignment\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                val = this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (val == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void assignment value\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (tk == NodeKind.MEMBER_ACCESS)
                {
                    case (true) { -> this.assign_member(t, val, n.b); }
                    default {};
                };
                switch (tk == NodeKind.ARRAY_ACCESS)
                {
                    case (true) { -> this.assign_index(t, val, n.b); }
                    default {};
                };
                switch (tk == NodeKind.POINTER_DEREF)
                {
                    case (true) { -> this.assign_deref(t, val); }
                    default {};
                };
                -> this.assign_ident(t, val, n.b);
            };

            // ----------------------------------------------------------
            // Variable declarations
            // ----------------------------------------------------------

            zero_of(IRType* t) -> IRValue* -> this.mod.c_null(t);

            x_vardecl(Node* n) -> IRValue*
            {
                TypeSpec* ts = n.ts;
                IRType* lt;
                IRValue* alloca;
                IRValue* iv;
                LVar* lv;
                Node* dimn;
                IRValue* cv;
                Node* ini = n.a;
                switch (this.fn == (IRFunc*)0 | (n.flags `& NF_GLOBAL) != 0)
                {
                    case (true) {
                    this.unsup(n, g"global variable\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (ts == (TypeSpec*)0)
                {
                    case (true) {
                    this.unsup(n, g"declaration without type\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (ts.base_type == DataType.DICT)
                {
                    case (true) {
                    this.unsup(n, g"dict variable\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (ts.storage_class == StorageClass.AUTO)
                {
                    case (true) {
                    this.unsup(n, g"auto variable\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (ts.storage_class == StorageClass.SINGINIT | ts.storage_class == StorageClass.HEAP)
                {
                    case (true) {
                    this.unsup(n, g"singinit or heap variable\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch ((ts.flags `& TS_ARRAY) != 0 & ts.array_size == (Node*)0 & ts.array_dims == (NodeVec*)0)
                {
                    case (true) {
                    this.unsup(n, g"array without size\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                lt = this.lower(ts, true, n.line);
                switch (this.nerrors > this.body_errs)
                {
                    case (true) {
                    this.unsup(n, g"variable type lowering\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                dimn = (Node*)0;
                switch (lt.kind == LK.PTR & (ts.flags `& TS_ARRAY) != 0)
                {
                    case (true) {
                    switch (ts.array_dims != (NodeVec*)0)
                    {
                        case (true) {
                        switch (ts.array_dims.len > 0)
                        {
                            case (true) { dimn = (Node*)ts.array_dims.items[0]; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (dimn == (Node*)0)
                    {
                        case (true) { dimn = ts.array_size; }
                        default {};
                    };
                }
                    default {};
                };
                switch (dimn != (Node*)0)
                {
                    case (true) {
                    // Runtime sized: alloca with a dynamic count at the current position, no initializer
                    cv = this.visit(dimn);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (cv == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(n, g"variable length array\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    alloca = this.mod.alloca_count(lt.elem, cv, n.text);
                    alloca.spec = ts;
                    this.define_var(n.text, alloca, ts);
                    -> alloca;
                }
                    default {};
                };
                switch (ini != (Node*)0)
                {
                    case (true) {
                    switch (ini.kind == NodeKind.STRUCT_RECAST)
                    {
                        case (true) {
                        this.unsup(n, g"struct recast initializer\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (ini.kind == NodeKind.FUNCTION_CALL)
                    {
                        case (true) {
                        switch (ini.text != (byte*)0)
                        {
                            case (true) {
                            switch (ends_with(ini.text, g".__init\0"))
                            {
                                case (true) {
                                switch (ini.text3 == (byte*)0 | node_count(ini, 0) > 0 & lt.kind != LK.ISTRUCT)
                                {
                                    case (true) {
                                    this.unsup(n, g"constructor initializer\0");
                                    -> (IRValue*)0;
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
                    switch (ini.kind == NodeKind.STRING_LITERAL & this.str_init_ok(lt, ini))
                    {
                        case (true) { }
                        default {
                            switch (ini.kind == NodeKind.ARRAY_LITERAL & this.simple_array_init(lt, ini))
                            {
                                case (true) { }
                                default {
                                    switch (ini.kind == NodeKind.STRUCT_LITERAL & lt.kind == LK.ISTRUCT)
                                    {
                                        case (true) { }
                                        default {
                                            switch (ini.kind == NodeKind.ARRAY_LITERAL | ini.kind == NodeKind.ARRAY_COMPREHENSION |
                        ini.kind == NodeKind.STRING_LITERAL | ini.kind == NodeKind.STRUCT_LITERAL)
                                            {
                                                case (true) {
                        this.unsup(n, g"aggregate initializer\0");
                        -> (IRValue*)0;
                    }
                                                default {};
                                            };
                                        };
                                    };
                                };
                            };
                        };
                    };
                    switch (lt.kind == LK.ARRAY & ini.kind == NodeKind.IDENTIFIER)
                    {
                        case (true) {
                        this.unsup(n, g"array copy initializer\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                alloca = this.mod.alloca(lt, n.text);
                alloca.spec = ts;
                lv = this.define_var(n.text, alloca, ts);
                switch ((ts.flags `& TS_VOLATILE) != 0)
                {
                    case (true) { lv.vol = true; }
                    default {};
                };
                switch (ini != (Node*)0)
                {
                    case (true) {
                    switch (ini.kind == NodeKind.NO_INIT)
                    {
                        case (true) { -> alloca; }
                        default {};
                    };
                    switch (ini.kind == NodeKind.ARRAY_LITERAL)
                    {
                        case (true) {
                        this.init_local_array(alloca, lt, ini);
                        -> alloca;
                    }
                        default {};
                    };
                    switch (ini.kind == NodeKind.STRING_LITERAL)
                    {
                        case (true) {
                        this.init_local_string(alloca, lt, ini);
                        -> alloca;
                    }
                        default {};
                    };
                    switch (ini.kind == NodeKind.FUNCTION_CALL & ini.text != (byte*)0)
                    {
                        case (true) {
                        switch (ends_with(ini.text, g".__init\0"))
                        {
                            case (true) {
                            this.init_ctor(alloca, lt, ini, n);
                            -> alloca;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (ini.kind == NodeKind.STRUCT_LITERAL & lt.kind == LK.ISTRUCT)
                    {
                        case (true) { iv = this.x_struct_lit(ini, lt); }
                        default { iv = this.visit(ini); };
                    };
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (iv != (IRValue*)0)
                    {
                        case (true) {
                        this.store_conv(alloca, lt, iv, ini, n);
                    }
                        default {};
                    };
                    -> alloca;
                }
                    default {};
                };
                switch (lt.kind == LK.ARRAY)
                {
                    case (true) {
                    switch (lt.count > 64)
                    {
                        case (true) {
                        this.memset_zero(alloca, lt);
                        -> alloca;
                    }
                        default {};
                    };
                }
                    default {};
                };
                this.mod.store(this.zero_of(lt), alloca);
                -> alloca;
            };

            // ----------------------------------------------------------
            // Statements
            // ----------------------------------------------------------

            s_block(Node* n) -> void
            {
                int i;
                int c = node_count(n, 0);
                PtrVec* outer = this.defers;
                this.defers = (PtrVec*)0;
                while (i < c)
                {
                    switch (this.mod.is_terminated())
                    {
                        case (true) { break; }
                        default {};
                    };
                    this.visit(node_child(n, 0, i));
                    switch (this.bad)
                    {
                        case (true) { break; }
                        default {};
                    };
                    i++;
                };
                switch (!this.bad & !this.mod.is_terminated())
                {
                    case (true) { this.run_defers(); }
                    default {};
                };
                switch (this.defers != (PtrVec*)0)
                {
                    case (true) { pv_free(this.defers); }
                    default {};
                };
                this.defers = outer;
                ->;
            };

            // Emits the deferred statements of the current block in reverse order
            run_defers() -> void
            {
                int i;
                int j;
                Node* d;
                switch (this.defers == (PtrVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                i = this.defers.len - 1;
                while (i >= 0)
                {
                    d = (Node*)this.defers.items[i];
                    switch ((d.flags `& NF_HAS_BODY) != 0)
                    {
                        case (true) {
                        j = node_count(d, 0) - 1;
                        while (j >= 0)
                        {
                            this.visit(node_child(d, 0, j));
                            switch (this.bad)
                            {
                                case (true) { ->; }
                                default {};
                            };
                            j--;
                        };
                    }
                        default { this.visit(d.a); };
                    };
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    i--;
                };
                ->;
            };

            check_cond_node(Node* c) -> void
            {
                switch (c.kind == NodeKind.STRING_LITERAL | c.kind == NodeKind.F_STRING_LITERAL)
                {
                    case (true) {
                    this.unsup(c, g"string literal condition\0");
                }
                    default {};
                };
                ->;
            };

            cond_value(Node* c) -> IRValue*
            {
                IRValue* v;
                this.check_cond_node(c);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                v = this.visit(c);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (v == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(c, g"void condition\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                -> this.to_bool(v);
            };

            s_if(Node* n) -> void
            {
                IRValue* cv;
                IRBlock* then_b;
                IRBlock* else_b;
                IRBlock* merge_b;
                IRBlock* et;
                IRBlock* ee;
                int i;
                int ne = node_count(n, 0);
                cv = this.cond_value(n.a);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                then_b = this.mod.append_block(this.fn, g"then\0");
                else_b = this.mod.append_block(this.fn, g"else\0");
                merge_b = this.mod.append_block(this.fn, g"ifcont\0");
                this.mod.cbr(cv, then_b, else_b);
                this.mod.position(this.fn, then_b);
                this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (!this.mod.is_terminated())
                {
                    case (true) { this.mod.br(merge_b); }
                    default {};
                };
                this.mod.position(this.fn, else_b);
                while (i < ne)
                {
                    cv = this.cond_value(node_child(n, 0, i));
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.sc.clear();
                    this.sc.put_str(g"elif_then_\0");
                    this.sc.put_int(i);
                    et = this.mod.append_block(this.fn, this.sc.mem);
                    this.sc.clear();
                    this.sc.put_str(g"elif_else_\0");
                    this.sc.put_int(i);
                    ee = this.mod.append_block(this.fn, this.sc.mem);
                    this.mod.cbr(cv, et, ee);
                    this.mod.position(this.fn, et);
                    this.visit(node_child(n, 1, i));
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (!this.mod.is_terminated())
                    {
                        case (true) { this.mod.br(merge_b); }
                        default {};
                    };
                    this.mod.position(this.fn, ee);
                    i++;
                };
                switch (n.c != (Node*)0)
                {
                    case (true) {
                    this.visit(n.c);
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                }
                    default {};
                };
                switch (!this.mod.is_terminated())
                {
                    case (true) { this.mod.br(merge_b); }
                    default {};
                };
                this.mod.position(this.fn, merge_b);
                ->;
            };

            // Value of a constant IRValue from its text (decimal, true, false)
            const_i64(IRValue* v) -> i64
            {
                byte* t = v.text;
                i64 r;
                int i;
                bool neg;
                switch (t[0] == 't')
                {
                    case (true) { -> (i64)1; }
                    default {};
                };
                switch (t[0] == 'f')
                {
                    case (true) { -> (i64)0; }
                    default {};
                };
                switch (t[0] == '-')
                {
                    case (true) { neg = true; i = 1; }
                    default {};
                };
                while (t[i] >= '0' & t[i] <= '9')
                {
                    r = r * (i64)10 + (i64)(t[i] - '0');
                    i++;
                };
                switch (neg)
                {
                    case (true) { r = (i64)0 - r; }
                    default {};
                };
                -> r;
            };

            // Constant integer a switch case label stands for (fcodegen._fold_case_const):
            // a literal, a negated constant, or a global constant found by name
            case_value(Node* e) -> IRValue*
            {
                IRValue* r;
                IRValue* o;
                IRGlobal* g;
                byte* nm;
                byte* sfx;
                int i, ln, ls, c0;
                bool hit;
                switch (e.kind == NodeKind.UNARY_OP)
                {
                    case (true)
                    {
                        switch (e.op == Operator.SUB)
                        {
                            case (true)
                            {
                                o = this.case_value(e.a);
                                switch (o == (IRValue*)0)
                                {
                                    case (true) { -> o; }
                                    default {};
                                };
                                switch (o.is_const & o.ty.kind == LK.INT)
                                {
                                    case (true) { -> this.mod.c_int(o.ty, (i64)0 - this.const_i64(o)); }
                                    default {};
                                };
                                -> o;
                            }
                            default {};
                        };
                    }
                    default {};
                };
                switch (e.kind == NodeKind.IDENTIFIER)
                {
                    case (true)
                    {
                        switch (e.text != (byte*)0)
                        {
                            case (true)
                            {
                                nm = colons_to_underscores(e.text);
                                sfx = join3(g"__\0", nm, g"\0");
                                ls = pp_cstrlen(sfx);
                                while (i < this.mod.globals.len & !hit)
                                {
                                    g = (IRGlobal*)this.mod.globals.items[i];
                                    i++;
                                    switch (g.init == (byte*)0)
                                    {
                                        case (true) { continue; }
                                        default {};
                                    };
                                    switch (g.ty.kind != LK.INT)
                                    {
                                        case (true) { continue; }
                                        default {};
                                    };
                                    ln = pp_cstrlen(g.name);
                                    hit = cstr_eq(g.name, nm);
                                    switch (!hit & ln >= ls)
                                    {
                                        case (true) { hit = pp_eq(g.name + ln - ls, sfx, ls); }
                                        default {};
                                    };
                                    c0 = (int)g.init[0];
                                    switch (hit & !((c0 >= '0' & c0 <= '9') | c0 == '-' | c0 == 't' | c0 == 'f'))
                                    {
                                        case (true) { hit = false; }
                                        default {};
                                    };
                                    switch (hit)
                                    {
                                        case (true)
                                        {
                                            r = this.mod.new_value(g.ty, g.init);
                                            r.is_const = true;
                                        }
                                        default {};
                                    };
                                };
                                ffree(nm);
                                ffree(sfx);
                                switch (hit)
                                {
                                    case (true) { -> r; }
                                    default {};
                                };
                            }
                            default {};
                        };
                    }
                    default {};
                };
                -> this.visit(e);
            };

            // _visit_switch_typeof: switch (typeof(x)) as a pointer equality if/else-if
            // chain. typeof() results are deduplicated globals, so comparing the
            // pointers is the comparison of the types.
            s_switch_typeof(Node* n) -> void
            {
                int i;
                int nc = node_count(n, 0);
                bool done;
                Node* c;
                IRValue* sp;
                IRValue* si8;
                IRValue* cp;
                IRValue* ci8;
                IRValue* cmpv;
                IRBlock* merge_b;
                IRBlock* dflt_b;
                IRBlock* next_b;
                IRBlock** bodies;
                sp = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (sp == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"switch typeof value\0");
                    ->;
                }
                    default {};
                };
                switch (sp.ty.kind != LK.PTR)
                {
                    case (true) {
                    this.unsup(n, g"switch typeof value\0");
                    ->;
                }
                    default {};
                };
                switch (sp.ty.elem.kind != LK.ARRAY)
                {
                    case (true) {
                    this.unsup(n, g"switch typeof value\0");
                    ->;
                }
                    default {};
                };
                this.mod.ia[0] = this.ci32(0);
                this.mod.ia[1] = this.ci32(0);
                si8 = this.mod.gep(sp, this.mod.ia, 2, false, g"typeof_ptr\0");
                merge_b = this.mod.append_block(this.fn, g"switch_typeof_merge\0");
                bodies = (IRBlock**)fmalloc((u64)(nc + 1) * (u64)((sizeof(IRBlock*) + 7) / 8));
                this.keep((void*)bodies);
                while (i < nc)
                {
                    c = node_child(n, 0, i);
                    switch (c.a == (Node*)0)
                    {
                        case (true) {
                        dflt_b = this.mod.append_block(this.fn, g"switch_typeof_default\0");
                        bodies[i] = dflt_b;
                    }
                        default {
                        bodies[i] = this.mod.append_block(this.fn, this.name_n(g"switch_typeof_case_\0", i));
                    };
                    };
                    i++;
                };
                switch (dflt_b == (IRBlock*)0)
                {
                    case (true) { dflt_b = merge_b; }
                    default {};
                };
                i = 0;
                while (i < nc & !done)
                {
                    c = node_child(n, 0, i);
                    switch (c.a == (Node*)0)
                    {
                        case (true) {
                        this.mod.br(dflt_b);
                        done = true;
                    }
                        default {
                        cp = this.visit(c.a);
                        switch (this.bad)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch (cp == (IRValue*)0)
                        {
                            case (true) {
                            this.unsup(c.a, g"switch typeof case value\0");
                            ->;
                        }
                            default {};
                        };
                        switch (cp.ty.kind != LK.PTR)
                        {
                            case (true) {
                            this.unsup(c.a, g"switch typeof case value\0");
                            ->;
                        }
                            default {};
                        };
                        switch (cp.ty.elem.kind != LK.ARRAY)
                        {
                            case (true) {
                            this.unsup(c.a, g"switch typeof case value\0");
                            ->;
                        }
                            default {};
                        };
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = this.ci32(0);
                        ci8 = this.mod.gep(cp, this.mod.ia, 2, false, g"typeof_ptr\0");
                        cmpv = this.mod.icmp(g"eq\0", si8, ci8, this.name_n(g"typeof_cmp_\0", i));
                        next_b = this.mod.append_block(this.fn, this.name_n(g"switch_typeof_next_\0", i));
                        this.mod.cbr(cmpv, bodies[i], next_b);
                        this.mod.position(this.fn, next_b);
                    };
                    };
                    i++;
                };
                switch (!done)
                {
                    case (true) { this.mod.br(dflt_b); }
                    default {};
                };
                i = 0;
                while (i < nc)
                {
                    c = node_child(n, 0, i);
                    this.mod.position(this.fn, bodies[i]);
                    this.visit(c.b);
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (!this.mod.is_terminated())
                    {
                        case (true) { this.mod.br(merge_b); }
                        default {};
                    };
                    i++;
                };
                this.mod.position(this.fn, merge_b);
                ->;
            };

            // Key in unions for a type name, or null
            find_union_key(byte* name) -> byte*
            {
                FXC_SYMENTRY* e;
                byte* m;
                byte* key;
                switch (nm_has(this.unions, name))
                {
                    case (true) { -> name; }
                    default {};
                };
                e = st_lookup_any(this.st, name, this.cur_ns);
                switch (e == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (e.kind_id != SymbolKind.UNION)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                m = sym_mangled(e);
                switch (!nm_has(this.unions, m))
                {
                    case (true) {
                    ffree(m);
                    -> (byte*)0;
                }
                    default {};
                };
                key = this.mod.own(m);
                ffree(m);
                -> key;
            };

            // Byte order comparison of two names, like Python sorted() on str
            name_lt(byte* a, byte* b) -> bool
            {
                int i;
                while (a[i] != (byte)0 & b[i] != (byte)0 & a[i] == b[i])
                {
                    i++;
                };
                -> (int)a[i] < (int)b[i];
            };

            // visit_SwitchStatement exhaustiveness check: switching on the tag of a
            // tagged union (v.#) without a default must cover every member of the tag enum
            check_tag_cover(Node* n) -> void
            {
                Node* ex = n.a;
                Node* c;
                Node* ed;
                Node* ud;
                Node* item;
                LVar* lv;
                byte* ukey;
                byte* ekey;
                byte* uname;
                byte* tname;
                byte* tmp;
                PtrVec* missing;
                void* p;
                int i, j, nc, ni;
                bool found;
                bool has_default;
                switch (ex.kind != NodeKind.MEMBER_ACCESS)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ex.text == (byte*)0 | ex.a == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ex.text[0] != '#')
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ex.text[1] != (byte)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ex.a.kind != NodeKind.IDENTIFIER)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (ex.a.text == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                nc = node_count(n, 0);
                while (i < nc)
                {
                    c = node_child(n, 0, i);
                    switch (c.a == (Node*)0)
                    {
                        case (true) { has_default = true; }
                        default {};
                    };
                    i++;
                };
                switch (has_default)
                {
                    case (true) { ->; }
                    default {};
                };
                lv = this.find_var(ex.a.text);
                switch (lv == (LVar*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (lv.ts == (TypeSpec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                uname = lv.ts.custom_typename;
                switch (uname == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                ukey = this.find_union_key(uname);
                switch (ukey == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                p = nm_get(this.union_defs, ukey);
                switch (p == (void*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                ud = (Node*)p;
                tname = ud.text2;
                switch (tname == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                ekey = this.find_enum_key(tname);
                switch (ekey == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                p = nm_get(this.enum_defs, ekey);
                switch (p == (void*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                ed = (Node*)p;
                missing = pv_new();
                ni = node_count(ed, 0);
                i = 0;
                while (i < ni)
                {
                    item = node_child(ed, 0, i);
                    found = false;
                    j = 0;
                    while (j < nc & !found)
                    {
                        c = node_child(n, 0, j);
                        switch (c.a != (Node*)0)
                        {
                            case (true) {
                            switch (c.a.kind == NodeKind.MEMBER_ACCESS & c.a.text != (byte*)0)
                            {
                                case (true) { found = cstr_eq(c.a.text, item.text); }
                                default {};
                            };
                        }
                            default {};
                        };
                        j++;
                    };
                    switch (!found)
                    {
                        case (true) { pv_push(missing, (void*)item.text); }
                        default {};
                    };
                    i++;
                };
                switch (missing.len == 0)
                {
                    case (true) {
                    pv_free(missing);
                    ->;
                }
                    default {};
                };
                i = 1;
                while (i < missing.len)
                {
                    tmp = (byte*)missing.items[i];
                    j = i - 1;
                    found = true;
                    while (found)
                    {
                        switch (j < 0)
                        {
                            case (true) { found = false; }
                            default {
                            found = this.name_lt(tmp, (byte*)missing.items[j]);
                        };
                        };
                        switch (found)
                        {
                            case (true) {
                            missing.items[j + 1] = missing.items[j];
                            j--;
                        }
                            default {};
                        };
                    };
                    missing.items[j + 1] = (void*)tmp;
                    i++;
                };
                this.sc.clear();
                this.sc.put_str(g"'\0");
                this.sc.put_str(uname);
                this.sc.put_str(g"' is tagged and thereby a sum type. Missing case(s): \0");
                i = 0;
                while (i < missing.len)
                {
                    switch (i > 0)
                    {
                        case (true) { this.sc.put_str(g", \0"); }
                        default {};
                    };
                    this.sc.put_str(tname);
                    this.sc.put_str(g".\0");
                    this.sc.put_str((byte*)missing.items[i]);
                    i++;
                };
                this.fail(this.sc.mem, n.line);
                this.unsup(n, g"switch exhaustiveness\0");
                pv_free(missing);
                ->;
            };

            s_switch(Node* n) -> void
            {
                int i;
                int nc = node_count(n, 0);
                int ncase;
                Node* c;
                IRValue* sv;
                IRValue* cv;
                IRValue** vals;
                IRBlock** blocks;
                IRBlock** bodies;
                IRBlock* merge_b;
                IRBlock* dflt_b;
                switch (n.a.kind == NodeKind.TYPE_OF)
                {
                    case (true) {
                    this.s_switch_typeof(n);
                    ->;
                }
                    default {};
                };
                this.check_tag_cover(n);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                sv = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (sv == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"switch value\0");
                    ->;
                }
                    default {};
                };
                switch (sv.ty.kind != LK.INT)
                {
                    case (true) {
                    this.unsup(n, g"switch on non-integer\0");
                    ->;
                }
                    default {};
                };
                merge_b = this.mod.append_block(this.fn, g"switch_merge\0");
                vals = (IRValue**)fmalloc((u64)(nc + 1) * (u64)((sizeof(IRValue*) + 7) / 8));
                this.keep((void*)vals);
                blocks = (IRBlock**)fmalloc((u64)(nc + 1) * (u64)((sizeof(IRBlock*) + 7) / 8));
                this.keep((void*)blocks);
                bodies = (IRBlock**)fmalloc((u64)(nc + 1) * (u64)((sizeof(IRBlock*) + 7) / 8));
                this.keep((void*)bodies);
                while (i < nc)
                {
                    c = node_child(n, 0, i);
                    switch (c.a == (Node*)0)
                    {
                        case (true) {
                        dflt_b = this.mod.append_block(this.fn, g"switch_default\0");
                        bodies[i] = dflt_b;
                    }
                        default {
                        bodies[i] = this.mod.append_block(this.fn, this.case_name(i));
                        cv = this.case_value(c.a);
                        switch (this.bad)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch (cv == (IRValue*)0)
                        {
                            case (true) {
                            this.unsup(c.a, g"switch case value\0");
                            ->;
                        }
                            default {};
                        };
                        switch (!cv.is_const | cv.ty.kind != LK.INT)
                        {
                            case (true) {
                            this.unsup(c.a, g"switch case value\0");
                            ->;
                        }
                            default {};
                        };
                        switch (sv.ty.kind == LK.INT & sv.ty.width == 1)
                        {
                            case (true) { vals[ncase] = this.mod.c_u64(sv.ty, (u64)(this.const_i64(cv) `& (i64)1)); }
                            default { vals[ncase] = this.mod.c_int(sv.ty, this.const_i64(cv)); };
                        };
                        blocks[ncase] = bodies[i];
                        ncase++;
                    };
                    };
                    i++;
                };
                switch (dflt_b == (IRBlock*)0)
                {
                    case (true) { dflt_b = merge_b; }
                    default {};
                };
                this.mod.switch_to(sv, dflt_b, vals, blocks, ncase);
                i = 0;
                while (i < nc)
                {
                    c = node_child(n, 0, i);
                    this.mod.position(this.fn, bodies[i]);
                    this.visit(c.b);
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (!this.mod.is_terminated())
                    {
                        case (true) { this.mod.br(merge_b); }
                        default {};
                    };
                    i++;
                };
                this.mod.position(this.fn, merge_b);
                ->;
            };

            // "switch_case_<i>"
            case_name(int i) -> byte*
            {
                Buf nb;
                nb.__init();
                nb.put_str(g"switch_case_\0");
                nb.put_int(i);
                byte* r = ts_dup(nb.mem);
                this.keep((void*)r);
                nb.__exit();
                -> r;
            };

            s_try(Node* n) -> void
            {
                IRValue* flag;
                IRValue* fz;
                IRValue* fv;
                IRValue* hx;
                IRBlock* try_b;
                IRBlock* chk_b;
                IRBlock* end_b;
                IRBlock* first_c;
                IRBlock* cb;
                PtrVec* cbs = pv_new();
                int cc = node_count(n, 0);
                int i;
                Node* cl;
                while (i < cc)
                {
                    cl = node_child(n, 0, i);
                    switch (cl.text != (byte*)0)
                    {
                        case (true) {
                        switch (cl.text[0] != (byte)0)
                        {
                            case (true) {
                            this.unsup(n, g"named catch\0");
                            pv_free(cbs);
                            ->;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                flag = this.mod.alloca_here(this.t_i1, g"exception_flag\0");
                this.mod.alloca_here(this.t_i64, g"exception_value\0");
                try_b = this.mod.append_block(this.fn, g"try.body\0");
                chk_b = this.mod.append_block(this.fn, g"catch.check\0");
                end_b = this.mod.append_block(this.fn, g"try.end\0");
                i = 0;
                while (i < cc)
                {
                    this.sc.clear();
                    this.sc.put_str(g"catch.\0");
                    this.sc.put_int(i);
                    cb = this.mod.append_block(this.fn, this.sc.mem);
                    pv_push(cbs, (void*)cb);
                    i++;
                };
                fz = this.mod.new_value(this.t_i1, g"0\0");
                fz.is_const = true;
                this.mod.store(fz, flag);
                this.mod.br(try_b);
                this.mod.position(this.fn, try_b);
                this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { pv_free(cbs); ->; }
                    default {};
                };
                switch (!this.mod.is_terminated())
                {
                    case (true) { this.mod.br(chk_b); }
                    default {};
                };
                this.mod.position(this.fn, chk_b);
                fv = this.mod.load(flag, g"exc_flag\0");
                hx = this.mod.icmp(g"ne\0", fv, this.mod.c_int(this.t_i32, (i64)0), g"has_exception\0");
                switch (cc > 0)
                {
                    case (true) { first_c = (IRBlock*)cbs.items[0]; }
                    default { first_c = end_b; };
                };
                this.mod.cbr(hx, first_c, end_b);
                i = 0;
                while (i < cc)
                {
                    cl = node_child(n, 0, i);
                    this.mod.position(this.fn, (IRBlock*)cbs.items[i]);
                    this.mod.store(fz, flag);
                    this.visit(cl.a);
                    switch (this.bad)
                    {
                        case (true) { pv_free(cbs); ->; }
                        default {};
                    };
                    switch (!this.mod.is_terminated())
                    {
                        case (true) { this.mod.br(end_b); }
                        default {};
                    };
                    i++;
                };
                pv_free(cbs);
                this.mod.position(this.fn, end_b);
                ->;
            };

            s_while(Node* n) -> void
            {
                IRBlock* cond_b = this.mod.append_block(this.fn, g"while.cond\0");
                IRBlock* body_b = this.mod.append_block(this.fn, g"while.body\0");
                IRBlock* end_b = this.mod.append_block(this.fn, g"while.end\0");
                IRBlock* ob = this.brk;
                IRBlock* oc = this.cont;
                IRValue* cv;
                this.brk = end_b;
                this.cont = cond_b;
                this.mod.br(cond_b);
                this.mod.position(this.fn, cond_b);
                cv = this.cond_value(n.a);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                this.mod.cbr(cv, body_b, end_b);
                this.mod.position(this.fn, body_b);
                this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (!this.mod.is_terminated())
                {
                    case (true) { this.mod.br(cond_b); }
                    default {};
                };
                this.brk = ob;
                this.cont = oc;
                this.mod.position(this.fn, end_b);
                ->;
            };

            s_do(Node* n) -> void
            {
                IRBlock* body_b = this.mod.append_block(this.fn, g"do.body\0");
                IRBlock* end_b = this.mod.append_block(this.fn, g"do.end\0");
                IRBlock* ob = this.brk;
                IRBlock* oc = this.cont;
                this.brk = end_b;
                this.cont = body_b;
                this.mod.br(body_b);
                this.mod.position(this.fn, body_b);
                this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (!this.mod.is_terminated())
                {
                    case (true) { this.mod.br(body_b); }
                    default {};
                };
                this.brk = ob;
                this.cont = oc;
                this.mod.position(this.fn, end_b);
                ->;
            };

            s_dowhile(Node* n) -> void
            {
                IRBlock* body_b = this.mod.append_block(this.fn, g"dowhile.body\0");
                IRBlock* cond_b = this.mod.append_block(this.fn, g"dowhile.cond\0");
                IRBlock* end_b = this.mod.append_block(this.fn, g"dowhile.end\0");
                IRBlock* ob = this.brk;
                IRBlock* oc = this.cont;
                IRValue* cv;
                this.brk = end_b;
                this.cont = cond_b;
                this.mod.br(body_b);
                this.mod.position(this.fn, body_b);
                this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (!this.mod.is_terminated())
                {
                    case (true) { this.mod.br(cond_b); }
                    default {};
                };
                this.mod.position(this.fn, cond_b);
                this.check_cond_node(n.a);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                cv = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (cv == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void condition\0");
                    ->;
                }
                    default {};
                };
                this.mod.cbr(cv, body_b, end_b);
                this.brk = ob;
                this.cont = oc;
                this.mod.position(this.fn, end_b);
                ->;
            };

            s_for(Node* n) -> void
            {
                IRBlock* cond_b = this.mod.append_block(this.fn, g"for.cond\0");
                IRBlock* body_b = this.mod.append_block(this.fn, g"for.body\0");
                IRBlock* upd_b = this.mod.append_block(this.fn, g"for.update\0");
                IRBlock* end_b = this.mod.append_block(this.fn, g"for.end\0");
                IRBlock* ob;
                IRBlock* oc;
                IRValue* cv;
                switch (n.a != (Node*)0)
                {
                    case (true) {
                    this.visit(n.a);
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                }
                    default {};
                };
                this.mod.br(cond_b);
                this.mod.position(this.fn, cond_b);
                switch (n.b != (Node*)0)
                {
                    case (true) {
                    cv = this.cond_value(n.b);
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    this.mod.cbr(cv, body_b, end_b);
                }
                    default { this.mod.br(body_b); };
                };
                this.mod.position(this.fn, body_b);
                ob = this.brk;
                oc = this.cont;
                this.brk = end_b;
                this.cont = upd_b;
                this.visit(n.d);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (!this.mod.is_terminated())
                {
                    case (true) { this.mod.br(upd_b); }
                    default {};
                };
                this.mod.position(this.fn, upd_b);
                switch (n.c != (Node*)0)
                {
                    case (true) {
                    this.visit(n.c);
                    switch (this.bad)
                    {
                        case (true) { ->; }
                        default {};
                    };
                }
                    default {};
                };
                this.mod.br(cond_b);
                this.brk = ob;
                this.cont = oc;
                this.mod.position(this.fn, end_b);
                ->;
            };

            // visit_NoreturnStatement
            s_noreturn() -> void
            {
                int i;
                bool have;
                switch (!this.mod.is_terminated())
                {
                    case (true) { this.mod.unreachable(); }
                    default {};
                };
                switch (this.fn != (IRFunc*)0)
                {
                    case (true) {
                    while (i < this.fn.attrs.len)
                    {
                        switch (cstr_eq((byte*)this.fn.attrs.items[i], g"noreturn\0"))
                        {
                            case (true) { have = true; }
                            default {};
                        };
                        i++;
                    };
                    switch (!have)
                    {
                        case (true) { pv_push(this.fn.attrs, (void*)this.mod.own(g"noreturn\0")); }
                        default {};
                    };
                }
                    default {};
                };
                ->;
            };

            s_return(Node* n) -> void
            {
                IRValue* rv;
                IRType* expected = this.fret;
                bool suppress;
                switch (this.mod.is_terminated())
                {
                    case (true) { ->; }
                    default {};
                };
                switch (n.a == (Node*)0)
                {
                    case (true) {
                    this.mod.ret_void();
                    ->;
                }
                    default {};
                };
                switch (n.a.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (this.local_flag(n.a.text, TS_LOCAL))
                    {
                        case (true) {
                        this.unsup(n, g"local variable returned\0");
                        ->;
                    }
                        default {};
                    };
                }
                    default {};
                };
                suppress = expected.kind == LK.STRUCT | expected.kind == LK.ISTRUCT;
                switch (suppress)
                {
                    case (true) { this.in_member = true; }
                    default {};
                };
                // A bare struct literal takes its type from the return type
                switch (n.a.kind == NodeKind.STRUCT_LITERAL & n.a.text == (byte*)0 & expected.kind == LK.ISTRUCT)
                {
                    case (true) { rv = this.x_struct_lit(n.a, expected); }
                    default { rv = this.visit(n.a); };
                };
                switch (suppress)
                {
                    case (true) { this.in_member = false; }
                    default {};
                };
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                this.run_defers();
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (rv == (IRValue*)0)
                {
                    case (true) {
                    this.mod.ret_void();
                    ->;
                }
                    default {};
                };
                switch (this.mod.is_terminated())
                {
                    case (true) { ->; }
                    default {};
                };
                switch (expected.kind == LK.VOID)
                {
                    case (true) {
                    this.mod.ret_void();
                    ->;
                }
                    default {};
                };
                switch (rv.ty.kind == LK.PTR & rv.ty.elem.kind == LK.STRUCT & lt_eq(rv.ty.elem, expected))
                {
                    case (true) {
                    rv = this.mod.load(rv, g"ret_load\0");
                }
                    default {};
                };
                rv = this.coerce_ret(rv, expected, n);
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                this.mod.ret(rv);
                ->;
            };


            // ----------------------------------------------------------
            // Unary, address-of, dereference, casts, strings, sizeof
            // ----------------------------------------------------------

            // x with every bit set (builder.not_ uses Constant(type, -1))
            all_ones(IRType* t) -> IRValue*
            {
                IRValue* v = this.mod.new_value(t, g"-1\0");
                v.is_const = true;
                -> v;
            };

            // visit_UnaryOp (identifier operands; member and array operands are not
            // generated yet)
            x_unary(Node* n) -> IRValue*
            {
                int op = n.op;
                Node* opd = n.a;
                IRValue* v;
                IRValue* nv;
                IRValue* off;
                IRValue* mpv;
                LVar* lv;
                bool post = (n.flags `& NF_POSTFIX) != 0;
                bool incdec = op == Operator.INCREMENT | op == Operator.DECREMENT;
                switch (incdec & opd.kind == NodeKind.ADDRESS_OF)
                {
                    case (true) {
                    this.unsup(n, g"increment of address-of\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                v = this.visit(opd);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (v == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void unary operand\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (incdec & opd.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (v.ty.kind == LK.PTR & v.ty.elem.kind == LK.PTR)
                    {
                        case (true) {
                        this.sc.clear();
                        this.sc.put_str(opd.text);
                        this.sc.put_str(g"_loaded\0");
                        v = this.mod.load(v, this.sc.mem);
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (op == Operator.NOT)
                {
                    case (true) {
                    switch (v.ty.kind == LK.PTR)
                    {
                        case (true) {
                        -> this.mod.icmp(g"eq\0", v, this.mod.c_null(v.ty), g"is_null\0");
                    }
                        default {};
                    };
                    switch (v.ty.kind != LK.INT)
                    {
                        case (true) {
                        this.unsup(n, g"not of non-integer\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    -> this.mod.binop(g"xor\0", v, this.all_ones(v.ty), (byte*)0);
                }
                    default {};
                };
                switch (op == Operator.SUB)
                {
                    case (true) {
                    switch (v.ty.kind == LK.FLOAT | v.ty.kind == LK.DOUBLE)
                    {
                        case (true) {
                        -> this.mod.binop(g"fsub\0", this.mod.c_fp(v.ty, 0.0), v, (byte*)0);
                    }
                        default {};
                    };
                    switch (v.ty.kind != LK.INT)
                    {
                        case (true) {
                        this.unsup(n, g"negate of non-number\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    -> this.mod.binop(g"sub\0", this.mod.c_int(v.ty, (i64)0), v, (byte*)0);
                }
                    default {};
                };
                switch (op == Operator.BITNOT)
                {
                    case (true) {
                    switch (v.ty.kind != LK.INT)
                    {
                        case (true) {
                        this.unsup(n, g"bit not of non-integer\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    -> this.mod.binop(g"xor\0", v, this.all_ones(v.ty), (byte*)0);
                }
                    default {};
                };
                switch (incdec)
                {
                    case (true) {
                    switch (v.ty.kind)
                    {
                        case (LK.PTR)
                        {
                            switch (op)
                            {
                                case (Operator.INCREMENT)
                                {
                                    nv = this.mod.gep_ptr(v, this.ci32(1), false, g"ptr_inc\0");
                                }
                                default
                                {
                                    nv = this.mod.gep_ptr(v, this.ci32(0 - 1), false, g"ptr_dec\0");
                                };
                            };
                        }
                        case (LK.INT)
                        {
                            off = this.mod.c_int(v.ty, (i64)1);
                            switch (op)
                            {
                                case (Operator.INCREMENT) { nv = this.mod.binop(g"add\0", v, off, (byte*)0); }
                                default { nv = this.mod.binop(g"sub\0", v, off, (byte*)0); };
                            };
                        }
                        default
                        {
                            this.unsup(n, g"increment of non-integer\0");
                            -> (IRValue*)0;
                        };
                    };
                    switch (opd.kind)
                    {
                        case (NodeKind.IDENTIFIER)
                        {
                            lv = this.find_var(opd.text);
                            switch (lv == (LVar*)0)
                            {
                                case (true) {
                                this.unsup(n, g"increment of non-local\0");
                                -> (IRValue*)0;
                            }
                                default {};
                            };
                            this.mod.store(nv, lv.ptr);
                        }
                        case (NodeKind.MEMBER_ACCESS)
                        {
                            mpv = this.member_ptr(opd);
                            switch (this.bad)
                            {
                                case (true) { -> (IRValue*)0; }
                                default {};
                            };
                            this.mod.store(nv, mpv);
                        }
                        case (NodeKind.ARRAY_ACCESS)
                        {
                            mpv = this.index_ptr(opd);
                            switch (this.bad)
                            {
                                case (true) { -> (IRValue*)0; }
                                default {};
                            };
                            this.mod.store(nv, mpv);
                        }
                        default {};
                    };
                    switch (post)
                    {
                        case (true) { -> v; }
                        default {};
                    };
                    -> nv;
                }
                    default {};
                };
                this.unsup(n, g"unary operator\0");
                -> (IRValue*)0;
            };

            // visit_PointerDeref
            x_deref(Node* n) -> IRValue*
            {
                IRValue* p = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (p == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void dereference\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (p.ty.kind != LK.PTR)
                {
                    case (true) {
                    this.unsup(n, g"dereference of non-pointer\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                -> this.mod.load(p, g"deref\0");
            };

            // visit_AddressOf (literals and local variables)
            // '@name' where name is a function: the base returns the function itself
            function_ref(byte* name) -> IRValue*
            {
                FXC_SYMENTRY* fe = st_lookup_any(this.st, name, this.cur_ns);
                PtrVec* list;
                Overload* o;
                Overload* oc;
                IRFunc* f;
                byte* key;
                int oi;
                // module.globals[var_name]: externs and other functions keep their plain name
                f = this.mod.find_function(name);
                switch (f != (IRFunc*)0)
                {
                    case (true) { -> f.self; }
                    default {};
                };
                switch (fe == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (fe.kind_id != SymbolKind.FUNCTION)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                key = sym_mangled(fe);
                list = st_overloads_of(this.st, key);
                ffree(key);
                switch (list == (PtrVec*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (list.len >= 1)
                {
                    case (true) { o = (Overload*)list.items[0]; }
                    default {};
                };
                // A prototype followed by its definition registers one overload twice
                oi = 1;
                while (oi < list.len)
                {
                    oc = (Overload*)list.items[oi];
                    switch (!cstr_eq(oc.mangled, o.mangled))
                    {
                        case (true) { o = (Overload*)0; break; }
                        default {};
                    };
                    oi++;
                };
                oi = 0;
                switch (o == (Overload*)0 & list.len > 1)
                {
                    case (true) {
                    while (oi < list.len)
                    {
                        oc = (Overload*)list.items[oi];
                        switch (oc.nparams == 0)
                        {
                            case (true) {
                            o = oc;
                            break;
                        }
                            default {};
                        };
                        oi++;
                    };
                }
                    default {};
                };
                switch (o == (Overload*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                f = this.mod.find_function(o.mangled);
                switch (f == (IRFunc*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                -> f.self;
            };

            x_addrof(Node* n) -> IRValue*
            {
                Node* e = n.a;
                IRValue* v;
                IRValue* tmp;
                IRValue* fv;
                LVar* lv;
                switch (e.kind == NodeKind.LITERAL)
                {
                    case (true) {
                    v = this.visit(e);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    tmp = this.mod.alloca(v.ty, (byte*)0);
                    this.mod.store(v, tmp);
                    -> tmp;
                }
                    default {};
                };
                switch (e.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    lv = this.find_var(e.text);
                    switch (lv == (LVar*)0)
                    {
                        case (true) {
                        fv = this.function_ref(e.text);
                        switch (fv != (IRValue*)0)
                        {
                            case (true) { -> fv; }
                            default {};
                        };
                        this.unsup(n, g"address of non-local\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (lv.ptr.ty.kind == LK.PTR & lv.ptr.ty.elem.kind == LK.PTR)
                    {
                        case (true) {
                        this.sc.clear();
                        this.sc.put_str(e.text);
                        this.sc.put_str(g"_ptr\0");
                        -> this.mod.load(lv.ptr, this.sc.mem);
                    }
                        default {};
                    };
                    -> lv.ptr;
                }
                    default {};
                };
                switch (e.kind == NodeKind.MEMBER_ACCESS)
                {
                    case (true) { -> this.member_ptr(e); }
                    default {};
                };
                switch (e.kind == NodeKind.POINTER_DEREF)
                {
                    case (true) { -> this.visit(e.a); }
                    default {};
                };
                switch (e.kind == NodeKind.FUNCTION_CALL)
                {
                    case (true) {
                    v = this.visit(e);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (v == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(n, g"address of void call\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    tmp = this.mod.alloca(v.ty, g"func_result_temp\0");
                    this.mod.store(v, tmp);
                    -> tmp;
                }
                    default {};
                };
                switch (e.kind == NodeKind.ARRAY_ACCESS)
                {
                    case (true) {
                    Node* an = e.a;
                    IRValue* arrp;
                    IRValue* ix;
                    switch (e.b.kind == NodeKind.RANGE_EXPRESSION)
                    {
                        case (true) {
                        this.unsup(n, g"address of range index\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (an.kind)
                    {
                        case (NodeKind.IDENTIFIER)
                        {
                            lv = this.find_var(an.text);
                            switch (lv == (LVar*)0)
                            {
                                case (true) {
                                this.unsup(n, g"address of non-local array\0");
                                -> (IRValue*)0;
                            }
                                default {};
                            };
                            arrp = lv.ptr;
                        }
                        case (NodeKind.MEMBER_ACCESS) { arrp = this.member_ptr(an); }
                        default { arrp = this.visit(an); };
                    };
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (arrp == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(n, g"address of void array\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    ix = this.visit(e.b);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (ix == (IRValue*)0)
                    {
                        case (true) {
                        this.unsup(n, g"address of void index\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (arrp.ty.kind == LK.PTR & arrp.ty.elem.kind == LK.PTR)
                    {
                        case (true) { arrp = this.mod.load(arrp, g"array_param_ptr\0"); }
                        default {};
                    };
                    switch (arrp.ty.kind == LK.PTR)
                    {
                        case (true) {
                        switch (arrp.ty.elem.kind == LK.ARRAY)
                        {
                            case (true) {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = ix;
                            -> this.mod.gep(arrp, this.mod.ia, 2, true, (byte*)0);
                        }
                            default {};
                        };
                        -> this.mod.gep_ptr(arrp, ix, true, (byte*)0);
                    }
                        default {};
                    };
                }
                    default {};
                };
                this.unsup(n, g"address-of operand\0");
                -> (IRValue*)0;
            };

            // EndianSwapHandler fix applied to the result of a cast
            cast_endian_fix(IRValue* v, TypeSpec* tgt) -> IRValue*
            {
                switch (v.ty.kind == LK.INT & v.ty.width >= 16)
                {
                    case (true) {
                    switch (this.endian_of(v.spec) != this.endian_of(tgt))
                    {
                        case (true) { -> this.bswap(v); }
                        default {};
                    };
                }
                    default {};
                };
                -> v;
            };

            // _cast_handle_void for stack variables: null the slot and forget the name
            cast_void(Node* n) -> IRValue*
            {
                Node* e = n.a;
                LVar* lv;
                IRType* pt;
                IRValue* ev;
                int i;
                switch (e.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    lv = this.find_local(e.text);
                    switch (lv == (LVar*)0)
                    {
                        case (true) {
                        this.unsup(n, g"void cast of non-local\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (lv.ptr.ty.kind != LK.PTR)
                    {
                        case (true) {
                        this.unsup(n, g"void cast of non-pointer slot\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    pt = lv.ptr.ty.elem;
                    switch (pt.kind != LK.PTR & pt.kind != LK.INT & pt.kind != LK.FLOAT & pt.kind != LK.DOUBLE)
                    {
                        case (true) {
                        this.unsup(n, g"void cast of aggregate\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    this.mod.store(this.mod.c_null(pt), lv.ptr);
                    i = this.scopes.len - 1;
                    while (i >= 0)
                    {
                        switch (nm_get((NameMap*)this.scopes.items[i], e.text) != (void*)0)
                        {
                            case (true) {
                            nm_del((NameMap*)this.scopes.items[i], e.text);
                            break;
                        }
                            default {};
                        };
                        i--;
                    };
                    -> (IRValue*)0;
                }
                    default {};
                };
                ev = this.visit(e);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (ev != (IRValue*)0)
                {
                    case (true) {
                    switch (ev.ty.kind == LK.PTR)
                    {
                        case (true) {
                        this.unsup(n, g"void cast runtime free\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                -> (IRValue*)0;
            };

            // visit_CastExpression (scalar, pointer and integer conversions)
            x_cast(Node* n) -> IRValue*
            {
                IRType* tt;
                IRType* st;
                IRValue* v;
                IRValue* r;
                LVar* lv;
                TypeSpec* tsp = n.ts;
                bool su, tu;
                tt = this.lower(tsp, true, n.line);
                switch (this.nerrors > this.body_errs)
                {
                    case (true) {
                    this.unsup(n, g"cast type lowering\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (tt.kind == LK.VOID)
                {
                    case (true) {
                    -> this.cast_void(n);
                }
                    default {};
                };
                switch (n.a.kind == NodeKind.LITERAL & n.a.op == DataType.VOID)
                {
                    case (true) {
                    switch (tt.kind == LK.PTR)
                    {
                        case (true) { -> this.mod.c_null(tt); }
                        default {};
                    };
                    switch (tt.kind == LK.INT)
                    {
                        case (true) { -> this.mod.c_int(tt, (i64)0); }
                        default {};
                    };
                    switch (tt.kind == LK.FLOAT | tt.kind == LK.DOUBLE)
                    {
                        case (true) { -> this.mod.c_fp(tt, 0.0); }
                        default {};
                    };
                    this.unsup(n, g"void literal cast\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                v = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (v == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"cast of void value\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                st = v.ty;
                switch (lt_eq(st, tt))
                {
                    case (true) {
                    v = this.cast_endian_fix(v, tsp);
                    v.spec = tsp;
                    -> v;
                }
                    default {};
                };
                switch (lt_eq(tt, this.t_i8p) & st.kind == LK.PTR)
                {
                    case (true) {
                    -> this.mod.cast(g"bitcast\0", v, this.t_i8p, g"to_void_ptr\0");
                }
                    default {};
                };
                switch (lt_eq(st, this.t_i8p) & tt.kind == LK.PTR)
                {
                    case (true) {
                    -> this.mod.cast(g"bitcast\0", v, tt, g"from_void_ptr\0");
                }
                    default {};
                };
                switch (st.kind == LK.INT & tt.kind == LK.INT)
                {
                    case (true) {
                    switch (st.width > tt.width)
                    {
                        case (true) { r = this.mod.cast(g"trunc\0", v, tt, (byte*)0); }
                        default {
                            switch (st.width < tt.width)
                            {
                                case (true) {
                        switch (n.a.kind)
                        {
                            case (NodeKind.LITERAL)
                            {
                                switch (n.a.op)
                                {
                                    case (DataType.UINT) { r = this.mod.cast(g"zext\0", v, tt, (byte*)0); }
                                    default { r = this.mod.cast(g"sext\0", v, tt, (byte*)0); };
                                };
                            }
                            default
                            {
                                su = this.is_uns(v);
                                switch (!su & n.a.kind == NodeKind.IDENTIFIER)
                                {
                                    case (true) {
                                    lv = this.find_var(n.a.text);
                                    switch (lv != (LVar*)0)
                                    {
                                        case (true) {
                                        switch (lv.ts != (TypeSpec*)0)
                                        {
                                            case (true) { su = (lv.ts.flags `& TS_SIGNED) == 0; }
                                            default {};
                                        };
                                    }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                                tu = su | tsp.base_type == DataType.UINT | tsp.base_type == DataType.BYTE;
                                switch (tsp.base_type == DataType.DATA & (tsp.flags `& TS_SIGNED) == 0)
                                {
                                    case (true) { tu = true; }
                                    default {};
                                };
                                switch (tsp.custom_typename != (byte*)0)
                                {
                                    case (true) {
                                    switch (tsp.custom_typename[0] == 'u')
                                    {
                                        case (true) { tu = true; }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                                switch (tu)
                                {
                                    case (true) { r = this.mod.cast(g"zext\0", v, tt, (byte*)0); }
                                    default { r = this.mod.cast(g"sext\0", v, tt, (byte*)0); };
                                };
                            };
                        };
                    }
                                default { r = v; };
                            };
                        };
                    };
                    r = this.cast_endian_fix(r, tsp);
                    r.spec = tsp;
                    -> r;
                }
                    default {};
                };
                switch (st.kind == LK.INT & (tt.kind == LK.FLOAT | tt.kind == LK.DOUBLE))
                {
                    case (true) {
                    -> this.mod.cast(g"sitofp\0", v, tt, (byte*)0);
                }
                    default {};
                };
                switch ((st.kind == LK.FLOAT | st.kind == LK.DOUBLE) & tt.kind == LK.INT)
                {
                    case (true) {
                    -> this.mod.cast(g"fptosi\0", v, tt, (byte*)0);
                }
                    default {};
                };
                switch (st.kind == LK.FLOAT & tt.kind == LK.DOUBLE)
                {
                    case (true) {
                    -> this.mod.cast(g"fpext\0", v, tt, (byte*)0);
                }
                    default {};
                };
                switch (st.kind == LK.DOUBLE & tt.kind == LK.FLOAT)
                {
                    case (true) {
                    -> this.mod.cast(g"fptrunc\0", v, tt, (byte*)0);
                }
                    default {};
                };
                switch (st.kind == LK.PTR & tt.kind == LK.PTR)
                {
                    case (true) {
                    -> this.mod.cast(g"bitcast\0", v, tt, (byte*)0);
                }
                    default {};
                };
                switch (st.kind == LK.INT & tt.kind == LK.PTR)
                {
                    case (true) {
                    switch (st.width < 64)
                    {
                        case (true) { v = this.mod.cast(g"zext\0", v, this.t_i64, g"int_to_ptr_zext\0"); }
                        default {};
                    };
                    -> this.mod.cast(g"inttoptr\0", v, tt, g"int_to_ptr\0");
                }
                    default {};
                };
                switch (st.kind == LK.PTR & tt.kind == LK.INT)
                {
                    case (true) {
                    switch (st.elem.kind == LK.ARRAY)
                    {
                        case (true) {
                        this.unsup(n, g"array pointer pack cast\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    -> this.mod.cast(g"ptrtoint\0", v, tt, g"ptr_to_int\0");
                }
                    default {};
                };
                this.unsup(n, g"cast between these types\0");
                -> (IRValue*)0;
            };

            // visit_StringLiteral: g-strings are shared constants, others are built on
            // the stack
            x_string(Node* n) -> IRValue*
            {
                int len = (int)n.ival;
                int i;
                byte* src = n.text;
                byte* buf;
                IRType* aty;
                IRValue* cv;
                IRValue* arr;
                IRValue* gp;
                IRGlobal* gl;
                void* hit;
                switch (src == (byte*)0)
                {
                    case (true) {
                    this.unsup(n, g"string without text\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (len <= 0)
                {
                    case (true) {
                    while (src[len] != 0)
                    {
                        len++;
                    };
                }
                    default {};
                };
                switch (n.op == StorageClass.HEAP)
                {
                    case (true) {
                    this.unsup(n, g"heap string\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                buf = (byte*)fmalloc((u64)(len + 2));
                this.keep((void*)buf);
                i = 0;
                while (i < len)
                {
                    buf[i] = src[i];
                    i++;
                };
                switch (this.null_term)
                {
                    case (true) {
                    switch (len == 0)
                    {
                        case (true) {
                        buf[0] = (byte)0;
                        len = 1;
                    }
                        default {
                            switch (buf[len - 1] != (byte)0)
                            {
                                case (true) {
                        buf[len] = (byte)0;
                        len++;
                    }
                                default {};
                            };
                        };
                    };
                }
                    default {};
                };
                aty = this.mod.t_array(this.t_i8, len);
                switch (n.op == StorageClass.GLOBAL)
                {
                    case (true) {
                    cv = this.mod.c_bytes(aty, buf, len);
                    hit = nm_get(this.gcache, cv.text);
                    switch (hit != (void*)0)
                    {
                        case (true) { -> (IRValue*)hit; }
                        default {};
                    };
                    this.sc.clear();
                    this.sc.put_str(g".str.\0");
                    this.sc.put_int(this.nstr);
                    this.nstr++;
                    gl = this.mod.add_global(aty, this.sc.mem, cv.text);
                    gl.linkage = this.mod.own(g"internal\0");
                    gl.constant = true;
                    this.mark_arr_ptr(gl.self.ty);
                    nm_put(this.gcache, this.mod.own(cv.text), (void*)gl.self);
                    -> gl.self;
                }
                    default {};
                };
                arr = this.mod.alloca_here(aty, g"str_stack\0");
                i = 0;
                while (i < len)
                {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = this.ci32(i);
                    this.sc.clear();
                    this.sc.put_str(g"str_char_\0");
                    this.sc.put_int(i);
                    gp = this.mod.gep(arr, this.mod.ia, 2, false, this.sc.mem);
                    this.mod.store(this.mod.c_int(this.t_i8, (i64)((int)buf[i])), gp);
                    i++;
                };
                this.mark_arr_ptr(arr.ty);
                -> arr;
            };

            // visit_SizeOf: size in bits as an i32 constant
            x_sizeof(Node* n) -> IRValue*
            {
                IRType* t;
                IRValue* v;
                FXC_SYMENTRY* e;
                LVar* lv;
                switch (n.ts != (TypeSpec*)0)
                {
                    case (true) {
                    t = this.lower(n.ts, true, n.line);
                    switch (this.nerrors > this.body_errs)
                    {
                        case (true) {
                        this.unsup(n, g"sizeof type lowering\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    -> this.mod.c_int(this.t_i32, (i64)bits_of(t));
                }
                    default {};
                };
                switch (n.a == (Node*)0)
                {
                    case (true) {
                    this.unsup(n, g"sizeof without target\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (n.a.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    e = st_lookup_any(this.st, n.a.text, this.cur_ns);
                    switch (e != (FXC_SYMENTRY*)0)
                    {
                        case (true) {
                        switch (e.kind_id == SymbolKind.STRUCT | e.kind_id == SymbolKind.OBJECT |
                            e.kind_id == SymbolKind.UNION | e.kind_id == SymbolKind.ENUM |
                            e.kind_id == SymbolKind.TYPE)
                        {
                            case (true) {
                            t = this.resolve_custom(n.a.text);
                            switch (t != (IRType*)0)
                            {
                                case (true) { -> this.mod.c_int(this.t_i32, (i64)bits_of(t)); }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    lv = this.find_var(n.a.text);
                    switch (lv != (LVar*)0)
                    {
                        case (true) {
                        switch (lv.ts != (TypeSpec*)0)
                        {
                            case (true) {
                            t = this.lower(lv.ts, true, n.line);
                            switch (this.nerrors > this.body_errs)
                            {
                                case (true) {
                                this.unsup(n, g"sizeof variable type\0");
                                -> (IRValue*)0;
                            }
                                default {};
                            };
                            -> this.mod.c_int(this.t_i32, (i64)bits_of(t));
                        }
                            default {};
                        };
                        -> this.mod.c_int(this.t_i32, (i64)bits_of(lv.ptr.ty.elem));
                    }
                        default {};
                    };
                    this.unsup(n, g"sizeof unresolved name\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                v = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (v == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"sizeof void\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                -> this.mod.c_int(this.t_i32, (i64)bits_of(v.ty));
            };


            // ----------------------------------------------------------
            // typeof
            // ----------------------------------------------------------

            // Records a pointer type produced by array to pointer decay (_is_array_pointer)
            mark_arr_ptr(IRType* t) -> void
            {
                pv_push(this.arr_ptrs, (void*)t);
                ->;
            };

            is_arr_ptr(IRType* t) -> bool
            {
                int i;
                while (i < this.arr_ptrs.len)
                {
                    switch (this.arr_ptrs.items[i] == (void*)t)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // base followed by depth '*' characters, owned by the module
            star_name(byte* base, int depth) -> byte*
            {
                Buf nb;
                byte* r;
                int i;
                nb.__init();
                nb.put_str(base);
                while (i < depth)
                {
                    nb.put_str(g"*\0");
                    i++;
                };
                r = this.mod.own(nb.mem);
                nb.__exit();
                -> r;
            };

            // prefix followed by the decimal i, owned by the module
            name_n(byte* prefix, int i) -> byte*
            {
                Buf nb;
                byte* r;
                nb.__init();
                nb.put_str(prefix);
                nb.put_int(i);
                r = this.mod.own(nb.mem);
                nb.__exit();
                -> r;
            };

            // _typeof_name_from_typespec
            typeof_name_ts(TypeSpec* t) -> byte*
            {
                byte* base = datatype_text(t.base_type);
                int depth = t.pointer_depth;
                switch (t.custom_typename != (byte*)0)
                {
                    case (true) {
                    switch (t.custom_typename[0] != (byte)0)
                    {
                        case (true) { base = t.custom_typename; }
                        default {};
                    };
                }
                    default {};
                };
                switch (ts_is_pointer(t) & depth < 1)
                {
                    case (true) { depth = 1; }
                    default {};
                };
                switch (ts_is_array(t))
                {
                    case (true) { depth++; }
                    default {};
                };
                -> this.star_name(base, depth);
            };

            // _typeof_name_from_llvm_type. Null when no Flux name exists for the type.
            typeof_name_llvm(IRType* t) -> byte*
            {
                IRType* inner;
                byte* b;
                int depth;
                switch (t.kind == LK.INT)
                {
                    case (true) {
                    switch (t.width == 1)
                    {
                        case (true) { -> datatype_text(DataType.BOOL); }
                        default {};
                    };
                    switch (t.width == 8)
                    {
                        case (true) { -> datatype_text(DataType.BYTE); }
                        default {};
                    };
                    switch (t.width == 64)
                    {
                        case (true) { -> datatype_text(DataType.SLONG); }
                        default {};
                    };
                    -> datatype_text(DataType.SINT);
                }
                    default {};
                };
                switch (t.kind == LK.FLOAT)
                {
                    case (true) { -> datatype_text(DataType.FLOAT); }
                    default {};
                };
                switch (t.kind == LK.DOUBLE)
                {
                    case (true) { -> datatype_text(DataType.DOUBLE); }
                    default {};
                };
                switch (t.kind == LK.PTR)
                {
                    case (true) {
                    switch (t.elem.kind == LK.ARRAY & this.is_arr_ptr(t))
                    {
                        case (true) {
                        b = this.typeof_name_llvm(t.elem.elem);
                        switch (b == (byte*)0)
                        {
                            case (true) { -> (byte*)0; }
                            default {};
                        };
                        -> this.star_name(b, 1);
                    }
                        default {};
                    };
                    inner = t;
                    while (inner.kind == LK.PTR)
                    {
                        depth++;
                        inner = inner.elem;
                    };
                    b = this.typeof_name_llvm(inner);
                    switch (b == (byte*)0)
                    {
                        case (true) { -> (byte*)0; }
                        default {};
                    };
                    -> this.star_name(b, depth);
                }
                    default {};
                };
                switch (t.kind == LK.ARRAY)
                {
                    case (true) {
                    b = this.typeof_name_llvm(t.elem);
                    switch (b == (byte*)0)
                    {
                        case (true) { -> (byte*)0; }
                        default {};
                    };
                    -> this.star_name(b, 1);
                }
                    default {};
                };
                switch (t.kind == LK.ISTRUCT)
                {
                    case (true) {
                    switch (t.name != (byte*)0)
                    {
                        case (true) {
                        switch (t.name[0] != (byte)0)
                        {
                            case (true) { -> t.name; }
                            default {};
                        };
                    }
                        default {};
                    };
                    -> datatype_text(DataType.STRUCT);
                }
                    default {};
                };
                switch (t.kind == LK.STRUCT)
                {
                    case (true) { -> datatype_text(DataType.STRUCT); }
                    default {};
                };
                switch (t.kind == LK.VOID)
                {
                    case (true) { -> datatype_text(DataType.VOID); }
                    default {};
                };
                -> (byte*)0;
            };

            // True when an identified struct named name exists (context.get_identified_type)
            has_named_type(byte* name) -> bool
            {
                int i;
                IRType* t;
                while (i < this.mod.named.len)
                {
                    t = (IRType*)this.mod.named.items[i];
                    switch (cstr_eq(t.name, name))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    i++;
                };
                -> false;
            };

            // _typeof_resolve_identifier_name. Null when the identifier names nothing.
            typeof_resolve_ident(byte* name) -> byte*
            {
                FXC_SYMENTRY* e;
                LVar* lv;
                int i, ln, ls1, ls2;
                byte* key;
                byte* m;
                byte* sfx1;
                byte* sfx2;
                bool hit;
                e = st_lookup_type(this.st, name, this.cur_ns);
                switch (e != (FXC_SYMENTRY*)0)
                {
                    case (true) { -> name; }
                    default {};
                };
                switch (nm_has(this.structs, name) | nm_has(this.unions, name) | nm_has(this.enums, name))
                {
                    case (true) { -> name; }
                    default {};
                };
                while (i < this.st.registered_ns.len)
                {
                    m = mangle_namespace_name((byte*)this.st.registered_ns.items[i], name);
                    hit = nm_has(this.structs, m);
                    ffree(m);
                    switch (hit)
                    {
                        case (true) { -> name; }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < this.st.using_ns.len)
                {
                    m = mangle_namespace_name((byte*)this.st.using_ns.items[i], name);
                    hit = nm_has(this.structs, m);
                    ffree(m);
                    switch (hit)
                    {
                        case (true) { -> name; }
                        default {};
                    };
                    i++;
                };
                switch (this.cur_ns[0] != (byte)0)
                {
                    case (true) {
                    m = mangle_namespace_name(this.cur_ns, name);
                    hit = nm_has(this.structs, m);
                    ffree(m);
                    switch (hit)
                    {
                        case (true) { -> name; }
                        default {};
                    };
                }
                    default {};
                };
                lv = this.find_var(name);
                switch (lv != (LVar*)0)
                {
                    case (true) {
                    switch (lv.ts != (TypeSpec*)0)
                    {
                        case (true) { -> this.typeof_name_ts(lv.ts); }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.has_named_type(name))
                {
                    case (true) { -> name; }
                    default {};
                };
                sfx1 = join3(g"__\0", name, g"\0");
                sfx2 = join3(g".\0", name, g"\0");
                ls1 = pp_cstrlen(sfx1);
                ls2 = pp_cstrlen(sfx2);
                i = 0;
                hit = false;
                while (i < this.structs.count & !hit)
                {
                    key = this.structs.keys[i];
                    ln = pp_cstrlen(key);
                    hit = cstr_eq(key, name);
                    switch (!hit & ln >= ls1)
                    {
                        case (true) { hit = pp_eq(key + ln - ls1, sfx1, ls1); }
                        default {};
                    };
                    switch (!hit & ln >= ls2)
                    {
                        case (true) { hit = pp_eq(key + ln - ls2, sfx2, ls2); }
                        default {};
                    };
                    i++;
                };
                ffree(sfx1);
                ffree(sfx2);
                switch (hit)
                {
                    case (true) { -> name; }
                    default {};
                };
                -> (byte*)0;
            };

            // _typeof_const_str: deduplicated global holding the type name bytes
            typeof_str(byte* name) -> IRValue*
            {
                void* hit = nm_get(this.tcache, name);
                int len = pp_cstrlen(name);
                IRType* aty;
                IRValue* cv;
                IRGlobal* gl;
                byte* gn;
                switch (hit != (void*)0)
                {
                    case (true) { -> (IRValue*)hit; }
                    default {};
                };
                aty = this.mod.t_array(this.t_i8, len);
                cv = this.mod.c_bytes(aty, name, len);
                gn = join3(g".typeof.\0", name, g"\0");
                gl = this.mod.add_global(aty, gn, cv.text);
                ffree(gn);
                gl.linkage = this.mod.own(g"internal\0");
                gl.constant = true;
                this.mark_arr_ptr(gl.self.ty);
                nm_put(this.tcache, name, (void*)gl.self);
                -> gl.self;
            };

            // visit_TypeOf
            x_typeof(Node* n) -> IRValue*
            {
                IRValue* v;
                byte* nm;
                switch (n.ts != (TypeSpec*)0)
                {
                    case (true) { -> this.typeof_str(this.typeof_name_ts(n.ts)); }
                    default {};
                };
                switch (n.a == (Node*)0)
                {
                    case (true) {
                    this.unsup(n, g"typeof without target\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (n.a.kind == NodeKind.IDENTIFIER & n.a.text != (byte*)0)
                {
                    case (true) {
                    nm = this.typeof_resolve_ident(n.a.text);
                    switch (nm != (byte*)0)
                    {
                        case (true) { -> this.typeof_str(nm); }
                        default {};
                    };
                }
                    default {};
                };
                switch (n.a.kind == NodeKind.LITERAL)
                {
                    case (true) { -> this.typeof_str(datatype_text(n.a.op)); }
                    default {};
                };
                v = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (v == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"typeof void\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (v.spec != (TypeSpec*)0)
                {
                    case (true) { -> this.typeof_str(this.typeof_name_ts(v.spec)); }
                    default {};
                };
                nm = this.typeof_name_llvm(v.ty);
                switch (nm == (byte*)0)
                {
                    case (true) {
                    this.sc.clear();
                    this.sc.put_str(g"typeof(): cannot determine a Flux type name for LLVM type \0");
                    this.sc.put_str(this.mod.type_str(v.ty));
                    this.fail(this.sc.mem, n.line);
                    this.unsup(n, g"typeof llvm type name\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                -> this.typeof_str(nm);
            };

            // _typeof_category_for_name: DataType.STRUCT or DataType.OBJECT, -1 for neither
            typeof_category_for_name(byte* name) -> int
            {
                void* p;
                SInfo* si;
                LVar* lv;
                p = nm_get(this.structs, name);
                switch (p != (void*)0)
                {
                    case (true) {
                    si = (SInfo*)p;
                    switch (si.is_object)
                    {
                        case (true) { -> DataType.OBJECT; }
                        default {};
                    };
                    -> DataType.STRUCT;
                }
                    default {};
                };
                switch (nm_has(this.unions, name) | nm_has(this.enums, name))
                {
                    case (true) { -> 0 - 1; }
                    default {};
                };
                lv = this.find_var(name);
                switch (lv != (LVar*)0)
                {
                    case (true) {
                    switch (lv.ts != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (lv.ts.custom_typename != (byte*)0)
                        {
                            case (true) { -> this.typeof_category_for_name(lv.ts.custom_typename); }
                            default {};
                        };
                        switch (lv.ts.base_type == DataType.STRUCT | lv.ts.base_type == DataType.OBJECT)
                        {
                            case (true) { -> lv.ts.base_type; }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.has_named_type(name))
                {
                    case (true) { -> DataType.STRUCT; }
                    default {};
                };
                -> 0 - 1;
            };

            // _typeof_arg_category on the argument of a TYPE_OF node
            typeof_arg_category(Node* t) -> int
            {
                switch (t.ts != (TypeSpec*)0)
                {
                    case (true) {
                    switch (t.ts.custom_typename != (byte*)0)
                    {
                        case (true) { -> this.typeof_category_for_name(t.ts.custom_typename); }
                        default {};
                    };
                    switch (t.ts.base_type == DataType.STRUCT | t.ts.base_type == DataType.OBJECT)
                    {
                        case (true) { -> t.ts.base_type; }
                        default {};
                    };
                    -> 0 - 1;
                }
                    default {};
                };
                switch (t.a == (Node*)0)
                {
                    case (true) { -> 0 - 1; }
                    default {};
                };
                switch (t.a.kind == NodeKind.IDENTIFIER & t.a.text != (byte*)0)
                {
                    case (true) { -> this.typeof_category_for_name(t.a.text); }
                    default {};
                };
                switch (t.a.kind == NodeKind.LITERAL)
                {
                    case (true) {
                    switch (t.a.op == DataType.STRUCT | t.a.op == DataType.OBJECT)
                    {
                        case (true) { -> t.a.op; }
                        default {};
                    };
                }
                    default {};
                };
                -> 0 - 1;
            };

            // _typeof_bare_category_literal: DataType.STRUCT or DataType.OBJECT when the
            // argument is the bare struct or object keyword, -1 otherwise
            typeof_bare_cat(Node* t) -> int
            {
                TypeSpec* s = t.ts;
                switch (s != (TypeSpec*)0)
                {
                    case (true) {
                    switch (s.custom_typename == (byte*)0 & (s.base_type == DataType.STRUCT | s.base_type == DataType.OBJECT) &
                            !ts_is_pointer(s) & !ts_is_array(s) & s.pointer_depth == 0)
                    {
                        case (true) { -> s.base_type; }
                        default {};
                    };
                    -> 0 - 1;
                }
                    default {};
                };
                switch (t.a == (Node*)0)
                {
                    case (true) { -> 0 - 1; }
                    default {};
                };
                switch (t.a.kind == NodeKind.LITERAL & (t.a.op == DataType.STRUCT | t.a.op == DataType.OBJECT) & t.a.text != (byte*)0)
                {
                    case (true) {
                    switch (cstr_eq(t.a.text, datatype_text(t.a.op)))
                    {
                        case (true) { -> t.a.op; }
                        default {};
                    };
                }
                    default {};
                };
                -> 0 - 1;
            };

            // ----------------------------------------------------------
            // Member access, element access, element and member assignment
            // ----------------------------------------------------------

            sty(IRType* t) -> bool -> t.kind == LK.STRUCT | t.kind == LK.ISTRUCT;

            is_struct_ptr_ty(IRType* t) -> bool
            {
                switch (t.kind != LK.PTR)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> this.sty(t.elem);
            };

            sinfo_of(IRType* t) -> SInfo*
            {
                switch (t.kind != LK.ISTRUCT)
                {
                    case (true) { -> (SInfo*)0; }
                    default {};
                };
                -> (SInfo*)nm_get(this.structs, t.name);
            };

            sidx(SInfo* si, byte* name) -> int
            {
                int i;
                while (i < si.n)
                {
                    switch (cstr_eq(si.names[i], name))
                    {
                        case (true) { -> i; }
                        default {};
                    };
                    i++;
                };
                -> 0 - 1;
            };

            // MemberAccessTypeHandler.is_struct_type
            is_struct_val(IRType* t) -> bool
            {
                IRType* b = t;
                switch (b.kind == LK.PTR)
                {
                    case (true) { b = b.elem; }
                    default {};
                };
                switch (b.kind != LK.ISTRUCT)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> nm_has(this.structs, b.name);
            };

            // TypeSystem.attach_type_metadata_from_llvm_type: the first type alias of
            // the same LLVM type gives the value its spec
            meta_from_type(IRValue* v) -> IRValue*
            {
                int i;
                bool uns;
                TypeSpec* as_;
                TypeSpec* ts;
                IRType* at;
                while (i < this.al_tys.len)
                {
                    at = (IRType*)this.al_tys.items[i];
                    switch ((i64)this.al_idx.items[i] > (i64)this.cur_stmt)
                    {
                        case (true) { i++; continue; }
                        default {};
                    };
                    switch (lt_eq(at, v.ty))
                    {
                        case (true) {
                        uns = false;
                        as_ = (TypeSpec*)this.al_specs.items[i];
                        switch (as_ != (TypeSpec*)0)
                        {
                            case (true) { uns = (as_.flags `& TS_SIGNED) == 0; }
                            default {};
                        };
                        ts = typespec_new();
                        this.keep((void*)ts);
                        switch (uns)
                        {
                            case (true) { ts.base_type = DataType.UINT; }
                            default {
                            ts.base_type = DataType.SINT;
                            ts.flags = TS_SIGNED;
                        };
                        };
                        switch (v.ty.kind == LK.INT)
                        {
                            case (true) { ts.bit_width = v.ty.width; }
                            default {};
                        };
                        ts.custom_typename = (byte*)this.al_names.items[i];
                        v.spec = ts;
                        -> v;
                    }
                        default {};
                    };
                    i++;
                };
                -> v;
            };

            // ArrayTypeHandler.preserve_array_element_type_metadata
            elem_meta(IRValue* loaded, IRValue* src) -> IRValue*
            {
                TypeSpec* es = src.espec;
                switch (es == (TypeSpec*)0)
                {
                    case (true) {
                    switch (src.spec != (TypeSpec*)0)
                    {
                        case (true) { es = src.spec.array_elem; }
                        default {};
                    };
                }
                    default {};
                };
                switch (es != (TypeSpec*)0)
                {
                    case (true) {
                    switch (loaded.spec == (TypeSpec*)0)
                    {
                        case (true) { loaded.spec = es; }
                        default {};
                    };
                    -> loaded;
                }
                    default {};
                };
                -> this.meta_from_type(loaded);
            };

            // i32 index as the element access code builds it
            idx_i32(IRValue* v) -> IRValue*
            {
                switch (v.ty.kind == LK.INT & v.ty.width != 32)
                {
                    case (true) {
                    switch (v.ty.width > 32)
                    {
                        case (true) { -> this.mod.cast(g"trunc\0", v, this.t_i32, g"idx_trunc\0"); }
                        default {};
                    };
                    -> this.mod.cast(g"sext\0", v, this.t_i32, g"idx_ext\0");
                }
                    default {};
                };
                -> v;
            };

            // Key in enums for a type name, or null
            find_enum_key(byte* name) -> byte*
            {
                FXC_SYMENTRY* e;
                byte* m;
                byte* key;
                switch (nm_has(this.enums, name))
                {
                    case (true) { -> name; }
                    default {};
                };
                e = st_lookup_any(this.st, name, this.cur_ns);
                switch (e == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (e.kind_id != SymbolKind.ENUM)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                m = sym_mangled(e);
                switch (!nm_has(this.enums, m))
                {
                    case (true) {
                    ffree(m);
                    -> (byte*)0;
                }
                    default {};
                };
                key = this.mod.own(m);
                ffree(m);
                -> key;
            };

            enum_member(Node* n, byte* key) -> IRValue*
            {
                IRType* ty = (IRType*)nm_get(this.enums, key);
                byte* full = join3(key, g".\0", n.text);
                void* p = nm_get(this.enumvals, full);
                IRGlobal* gl;
                i64* box;
                IRValue* r;
                switch (p == (void*)0)
                {
                    case (true) {
                    ffree(full);
                    this.unsup(n, g"enum member not found\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (ty.kind == LK.STRUCT | ty.kind == LK.ISTRUCT | ty.kind == LK.ARRAY)
                {
                    case (true) {
                    gl = this.mod.find_global(full);
                    ffree(full);
                    switch (gl == (IRGlobal*)0)
                    {
                        case (true) {
                        this.unsup(n, g"enum member not found\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    -> gl.self;
                }
                    default {};
                };
                ffree(full);
                box = (i64*)p;
                r = this.mod.c_int(ty, box[0]);
                -> r;
            };

            // StructFieldAccess for a field of a struct reached through a pointer
            struct_field(Node* n, Node* objn, byte* field) -> IRValue*
            {
                IRValue* inst = this.visit(objn);
                IRValue* fp;
                LVar* lv;
                SInfo* si;
                IRType* pe;
                int idx;
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (inst == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void struct instance\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (objn.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (inst.ty.kind != LK.PTR & this.sty(inst.ty))
                    {
                        case (true) {
                        lv = this.find_var(objn.text);
                        switch (lv != (LVar*)0)
                        {
                            case (true) {
                            switch (this.is_struct_ptr_ty(lv.ptr.ty))
                            {
                                case (true) { inst = lv.ptr; }
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
                switch (inst.ty.kind == LK.PTR & this.sty(inst.ty.elem))
                {
                    case (true) {
                    pe = inst.ty.elem;
                    si = this.sinfo_of(pe);
                    switch (si == (SInfo*)0)
                    {
                        case (true) {
                        this.unsup(n, g"field of unnamed struct\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    idx = this.sidx(si, field);
                    switch (idx < 0)
                    {
                        case (true) {
                        this.unsup(n, g"field not found\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    this.sc.clear();
                    this.sc.put_str(field);
                    this.sc.put_str(g"_ptr\0");
                    fp = this.mod.gep_field(inst, idx, true, this.sc.mem);
                    switch (fp.ty.elem.kind == LK.ARRAY | this.sty(fp.ty.elem))
                    {
                        case (true) { -> fp; }
                        default {};
                    };
                    -> this.mod.load(fp, field);
                }
                    default {};
                };
                this.unsup(n, g"field access on struct value\0");
                -> (IRValue*)0;
            };

            // visit_MemberAccess
            x_member(Node* n) -> IRValue*
            {
                Node* o = n.a;
                byte* key;
                LVar* lv;
                IRValue* obj;
                IRValue* obj2;
                IRValue* r;
                IRValue* mp;
                IRValue* ld;
                IRType* pe;
                SInfo* si;
                int idx;
                bool prev;
                switch (o.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    key = this.find_enum_key(o.text);
                    switch (key != (byte*)0)
                    {
                        case (true) { -> this.enum_member(n, key); }
                        default {};
                    };
                    lv = this.find_var(o.text);
                    switch (lv != (LVar*)0)
                    {
                        case (true) {
                        switch (lv.ts != (TypeSpec*)0)
                        {
                            case (true) {
                            switch (lv.ts.custom_typename != (byte*)0)
                            {
                                case (true) {
                                key = this.find_enum_key(lv.ts.custom_typename);
                                switch (key != (byte*)0)
                                {
                                    case (true) { -> this.enum_member(n, key); }
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
                prev = this.in_member;
                this.in_member = true;
                obj = this.visit(o);
                switch (this.bad)
                {
                    case (true) {
                    this.in_member = prev;
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (obj == (IRValue*)0)
                {
                    case (true) {
                    this.in_member = prev;
                    this.unsup(n, g"void member access object\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (this.is_struct_val(obj.ty))
                {
                    case (true) {
                    r = this.struct_field(n, o, n.text);
                    this.in_member = prev;
                    -> r;
                }
                    default {};
                };
                obj2 = this.visit(o);
                this.in_member = prev;
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (obj2 == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void member access object\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (o.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (cstr_eq(o.text, g"this\0"))
                    {
                        case (true) {
                        switch (obj2.ty.kind == LK.PTR & obj2.ty.elem.kind == LK.PTR & obj2.ty.elem.elem.kind == LK.STRUCT)
                        {
                            case (true) {
                            obj2 = this.mod.load(obj2, g"this_ptr\0");
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (obj2.ty.kind == LK.PTR & obj2.ty.elem.kind == LK.PTR)
                {
                    case (true) {
                    switch (this.is_struct_ptr_ty(obj2.ty.elem))
                    {
                        case (true) { obj2 = this.mod.load(obj2, g"deref_struct_ptr\0"); }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.is_struct_ptr_ty(obj2.ty))
                {
                    case (true) {
                    si = this.sinfo_of(obj2.ty.elem);
                    switch (si == (SInfo*)0)
                    {
                        case (true) {
                        this.unsup(n, g"member of union or unnamed struct\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    idx = this.sidx(si, n.text);
                    switch (idx < 0)
                    {
                        case (true) {
                        this.unsup(n, g"member not found\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    mp = this.mod.gep_field(obj2, idx, true, (byte*)0);
                    pe = mp.ty.elem;
                    switch (pe.kind == LK.ARRAY)
                    {
                        case (true) {
                        switch (si.specs[idx] != (TypeSpec*)0)
                        {
                            case (true) { mp.espec = si.specs[idx].array_elem; }
                            default {};
                        };
                        -> mp;
                    }
                        default {};
                    };
                    switch (this.sty(pe))
                    {
                        case (true) { -> mp; }
                        default {};
                    };
                    ld = this.mod.load(mp, (byte*)0);
                    switch (si.specs[idx] != (TypeSpec*)0)
                    {
                        case (true) {
                        ld.spec = si.specs[idx];
                        -> ld;
                    }
                        default {};
                    };
                    -> this.meta_from_type(ld);
                }
                    default {};
                };
                this.unsup(n, g"member access on unsupported type\0");
                -> (IRValue*)0;
            };

            // _member_access_get_ptr: address of a member, without loading it
            member_ptr(Node* n) -> IRValue*
            {
                Node* o = n.a;
                IRValue* obj;
                LVar* lv;
                SInfo* si;
                int idx;
                switch (o.kind)
                {
                    case (NodeKind.IDENTIFIER)
                    {
                        switch (cstr_eq(o.text, g"this\0"))
                        {
                            case (true) {
                            obj = this.visit(o);
                            switch (this.bad)
                            {
                                case (true) { -> (IRValue*)0; }
                                default {};
                            };
                            switch (obj.ty.kind == LK.PTR & obj.ty.elem.kind == LK.PTR & obj.ty.elem.elem.kind == LK.STRUCT)
                            {
                                case (true) {
                                obj = this.mod.load(obj, g"this_ptr\0");
                            }
                                default {};
                            };
                        }
                            default {
                            lv = this.find_local(o.text);
                            switch (lv == (LVar*)0)
                            {
                                case (true) {
                                // Global object: the base evaluates the identifier as an expression
                                lv = this.find_global_var(o.text);
                                switch (lv == (LVar*)0)
                                {
                                    case (true) {
                                    this.unsup(n, g"member of non-local\0");
                                    -> (IRValue*)0;
                                }
                                    default {};
                                };
                                switch (lv.ptr.ty.elem.kind == LK.STRUCT | lv.ptr.ty.elem.kind == LK.ISTRUCT)
                                {
                                    case (true) {
                                    obj = lv.ptr;
                                }
                                    default {
                                    obj = this.visit(o);
                                    switch (this.bad)
                                    {
                                        case (true) { -> (IRValue*)0; }
                                        default {};
                                    };
                                };
                                };
                            }
                                default { obj = lv.ptr; };
                            };
                        };
                        };
                    }
                    default
                    {
                        obj = this.visit(o);
                        switch (this.bad)
                        {
                            case (true) { -> (IRValue*)0; }
                            default {};
                        };
                    };
                };
                switch (obj == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void member object\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (obj.ty.kind == LK.PTR & obj.ty.elem.kind == LK.PTR)
                {
                    case (true) {
                    switch (this.is_struct_ptr_ty(obj.ty.elem))
                    {
                        case (true) { obj = this.mod.load(obj, g"struct_ptr\0"); }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.is_struct_ptr_ty(obj.ty))
                {
                    case (true) {
                    si = this.sinfo_of(obj.ty.elem);
                    switch (si == (SInfo*)0)
                    {
                        case (true) {
                        this.unsup(n, g"member pointer of unnamed struct\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    idx = this.sidx(si, n.text);
                    switch (idx < 0)
                    {
                        case (true) {
                        this.unsup(n, g"member not found\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    -> this.mod.gep_field(obj, idx, true, (byte*)0);
                }
                    default {};
                };
                this.unsup(n, g"member pointer of non-struct\0");
                -> (IRValue*)0;
            };

            // True when a looks like an indexable pointer slot that must be loaded first
            needs_ptr_load(IRValue* a) -> bool
            {
                TypeSpec* ts = a.spec;
                int depth = 1;
                bool is_arr = false;
                switch (ts != (TypeSpec*)0)
                {
                    case (true) {
                    depth = ts.pointer_depth;
                    is_arr = (ts.flags `& TS_ARRAY) != 0;
                }
                    default {};
                };
                switch (is_arr | depth > 1)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch ((a.flags `& (VF_ALLOCA `| VF_GLOBAL)) == 0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (a.ty.kind != LK.PTR)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (a.ty.elem.kind != LK.PTR)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (a.ty.elem.elem.kind == LK.ARRAY | a.ty.elem.elem.kind == LK.PTR)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> true;
            };

            is_dict_ty(IRType* t) -> bool
            {
                IRType* b = t;
                switch (b.kind == LK.PTR)
                {
                    case (true) { b = b.elem; }
                    default {};
                };
                switch (b.kind != LK.STRUCT)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (b.nitems != 3)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> b.items[0].kind == LK.ARRAY & b.items[1].kind == LK.ARRAY & b.items[2].kind == LK.INT;
            };

            // visit_ArrayAccess
            x_index(Node* n) -> IRValue*
            {
                IRValue* arr;
                IRValue* idx;
                IRValue* gp;
                IRValue* ld;
                IRValue* t1;
                IRValue* t2;
                IRValue* t3;
                switch (n.b.kind == NodeKind.RANGE_EXPRESSION)
                {
                    case (true) {
                    this.unsup(n, g"range index\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                arr = this.visit(n.a);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (arr == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void indexed value\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (this.is_dict_ty(arr.ty))
                {
                    case (true) {
                    this.unsup(n, g"dict access\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (this.needs_ptr_load(arr))
                {
                    case (true) { arr = this.mod.load(arr, g"ptr_loaded_for_access\0"); }
                    default {};
                };
                idx = this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (idx == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void index\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                idx = this.idx_i32(idx);
                switch ((arr.flags `& VF_GLOBAL) != 0 | (arr.ty.kind == LK.PTR & arr.ty.elem.kind == LK.ARRAY))
                {
                    case (true) {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = idx;
                    gp = this.mod.gep(arr, this.mod.ia, 2, true, g"array_gep\0");
                    switch (gp.ty.elem.kind == LK.ARRAY | this.sty(gp.ty.elem))
                    {
                        case (true) { -> gp; }
                        default {};
                    };
                    ld = this.mod.load(gp, g"array_load\0");
                    -> this.elem_meta(ld, arr);
                }
                    default {};
                };
                switch (arr.ty.kind == LK.PTR)
                {
                    case (true) {
                    gp = this.mod.gep_ptr(arr, idx, true, g"ptr_gep\0");
                    switch (this.sty(gp.ty.elem))
                    {
                        case (true) { -> gp; }
                        default {};
                    };
                    ld = this.mod.load(gp, g"ptr_load\0");
                    -> this.elem_meta(ld, arr);
                }
                    default {};
                };
                switch (arr.ty.kind == LK.INT)
                {
                    case (true) {
                    switch (idx.ty.width != 64)
                    {
                        case (true) { t1 = this.mod.cast(g"sext\0", idx, this.t_i64, g"idx_i64\0"); }
                        default { t1 = idx; };
                    };
                    t2 = this.mod.binop(g"mul\0", t1, this.mod.c_int(this.t_i64, (i64)8), g"byte_shift\0");
                    switch (arr.ty.width != 64)
                    {
                        case (true) { t3 = this.mod.cast(g"zext\0", arr, this.t_i64, g"val_i64\0"); }
                        default { t3 = arr; };
                    };
                    t3 = this.mod.binop(g"lshr\0", t3, t2, g"byte_shr\0");
                    -> this.mod.cast(g"trunc\0", t3, this.t_i8, g"byte_extract\0");
                }
                    default {};
                };
                this.unsup(n, g"element access type\0");
                -> (IRValue*)0;
            };

            // _array_access_get_ptr: address of an element, for ++ and --
            index_ptr(Node* n) -> IRValue*
            {
                IRValue* arr = this.visit(n.a);
                IRValue* idx;
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (arr == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void indexed value\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (this.needs_ptr_load(arr))
                {
                    case (true) { arr = this.mod.load(arr, g"ptr_loaded_for_inc\0"); }
                    default {};
                };
                idx = this.visit(n.b);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (idx == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(n, g"void index\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                idx = this.idx_i32(idx);
                switch ((arr.flags `& VF_GLOBAL) != 0 | (arr.ty.kind == LK.PTR & arr.ty.elem.kind == LK.ARRAY))
                {
                    case (true) {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = idx;
                    -> this.mod.gep(arr, this.mod.ia, 2, true, g"inc_gep\0");
                }
                    default {};
                };
                switch (arr.ty.kind == LK.PTR)
                {
                    case (true) { -> this.mod.gep_ptr(arr, idx, true, g"inc_gep\0"); }
                    default {};
                };
                this.unsup(n, g"element pointer type\0");
                -> (IRValue*)0;
            };

            // First character of a string literal as an i8 constant
            first_char(Node* s) -> IRValue*
            {
                int c = 0;
                switch (s.text != (byte*)0)
                {
                    case (true) {
                    switch (s.ival > (i64)0 | s.text[0] != (byte)0)
                    {
                        case (true) { c = (int)s.text[0]; }
                        default {};
                    };
                }
                    default {};
                };
                -> this.mod.c_int(this.t_i8, (i64)c);
            };

            // AssignmentTypeHandler.handle_member_assignment
            assign_member(Node* t, IRValue* val0, Node* vexpr) -> IRValue*
            {
                Node* o = t.a;
                IRValue* obj;
                IRValue* mp;
                IRValue* val = val0;
                IRType* mt;
                LVar* lv;
                SInfo* si;
                int idx;
                bool glob = false;
                switch (o.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (this.find_local(o.text) == (LVar*)0)
                    {
                        case (true) {
                        glob = this.find_global_var(o.text) != (LVar*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (glob)
                {
                    case (true) {
                    lv = this.find_global_var(o.text);
                    switch (lv.ptr.ty.elem.kind == LK.STRUCT | lv.ptr.ty.elem.kind == LK.ISTRUCT)
                    {
                        case (true) {
                        // Struct global: base uses module.globals[name], the pointer itself
                        obj = lv.ptr;
                    }
                        default {
                        // Global object: the base evaluates the identifier as an expression
                        obj = this.visit(o);
                        switch (this.bad)
                        {
                            case (true) { -> (IRValue*)0; }
                            default {};
                        };
                    };
                    };
                }
                    default {
                        switch (o.kind == NodeKind.IDENTIFIER)
                        {
                            case (true) {
                    lv = this.find_var(o.text);
                    switch (lv == (LVar*)0)
                    {
                        case (true) {
                        this.unsup(t, g"member assignment to non-local\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    obj = lv.ptr;
                    switch (obj.ty.kind == LK.PTR & obj.ty.elem.kind == LK.PTR)
                    {
                        case (true) {
                        switch (this.is_struct_ptr_ty(obj.ty.elem))
                        {
                            case (true) {
                            this.sc.clear();
                            this.sc.put_str(o.text);
                            this.sc.put_str(g"_ptr\0");
                            obj = this.mod.load(obj, this.sc.mem);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                            default {
                                switch (o.kind == NodeKind.MEMBER_ACCESS)
                                {
                                    case (true) {
                    obj = this.member_ptr(o);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                }
                                    default {
                    obj = this.visit(o);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                };
                                };
                            };
                        };
                    };
                };
                switch (obj == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(t, g"void member assignment object\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (obj.ty.kind == LK.PTR & obj.ty.elem.kind == LK.PTR)
                {
                    case (true) {
                    switch (this.is_struct_ptr_ty(obj.ty.elem))
                    {
                        case (true) { obj = this.mod.load(obj, g"struct_ptr\0"); }
                        default {};
                    };
                }
                    default {};
                };
                switch (!this.is_struct_ptr_ty(obj.ty))
                {
                    case (true) {
                    this.unsup(t, g"member assignment to non-struct\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                si = this.sinfo_of(obj.ty.elem);
                switch (si == (SInfo*)0)
                {
                    case (true) {
                    this.unsup(t, g"member assignment to union or unnamed struct\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                idx = this.sidx(si, t.text);
                switch (idx < 0)
                {
                    case (true) {
                    this.unsup(t, g"member not found\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                mp = this.mod.gep_field(obj, idx, true, (byte*)0);
                mt = mp.ty.elem;
                switch (vexpr.kind == NodeKind.ARRAY_LITERAL & mt.kind == LK.ARRAY)
                {
                    case (true) {
                    this.unsup(t, g"array literal to member\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY & mt.kind == LK.ARRAY)
                {
                    case (true) {
                    switch (lt_eq(val.ty.elem.elem, mt.elem) & val.ty.elem.count <= mt.count)
                    {
                        case (true) {
                        this.unsup(t, g"array widening member assignment\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (val.ty.kind == LK.PTR & mt.kind != LK.PTR)
                {
                    case (true) {
                    switch (lt_eq(val.ty.elem, mt))
                    {
                        case (true) { val = this.mod.load(val, g"obj_val_deref\0"); }
                        default {};
                    };
                }
                    default {};
                };
                val = this.convert_assign(val, mt);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                this.mod.store(val, mp);
                -> val;
            };

            // AssignmentTypeHandler.handle_array_element_assignment and the struct
            // member array path of visit_Assignment
            assign_index(Node* t, IRValue* val0, Node* vexpr) -> IRValue*
            {
                Node* an = t.a;
                Node* ix = t.b;
                IRValue* val = val0;
                IRValue* arr;
                IRValue* idx;
                IRValue* ep;
                IRValue* mp;
                IRType* et;
                switch (an.kind == NodeKind.MEMBER_ACCESS)
                {
                    case (true) {
                    mp = this.member_ptr(an);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    switch (mp.ty.kind == LK.PTR & mp.ty.elem.kind == LK.ARRAY)
                    {
                        case (true) {
                        switch (ix.kind == NodeKind.RANGE_EXPRESSION)
                        {
                            case (true) {
                            this.unsup(t, g"member slice assignment\0");
                            -> (IRValue*)0;
                        }
                            default {};
                        };
                        idx = this.visit(ix);
                        switch (this.bad)
                        {
                            case (true) { -> (IRValue*)0; }
                            default {};
                        };
                        idx = this.idx_i32(idx);
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = idx;
                        ep = this.mod.gep(mp, this.mod.ia, 2, true, (byte*)0);
                        et = mp.ty.elem.elem;
                        switch (!lt_eq(val.ty, et))
                        {
                            case (true) {
                            switch (val.ty.kind == LK.INT & et.kind == LK.INT)
                            {
                                case (true) {
                                switch (val.ty.width > et.width)
                                {
                                    case (true) { val = this.mod.cast(g"trunc\0", val, et, g"val_trunc\0"); }
                                    default { val = this.mod.cast(g"sext\0", val, et, g"val_ext\0"); };
                                };
                            }
                                default {
                                    switch (val.ty.kind == LK.PTR & lt_eq(val.ty.elem, et))
                                    {
                                        case (true) {
                                val = this.mod.load(val, g"struct_elem_load\0");
                            }
                                        default {
                                            switch (val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY & et.kind == LK.PTR)
                                            {
                                                case (true) {
                                switch (lt_eq(val.ty.elem.elem, et.elem))
                                {
                                    case (true) {
                                    this.mod.ia[0] = this.ci32(0);
                                    this.mod.ia[1] = this.ci32(0);
                                    val = this.mod.gep(val, this.mod.ia, 2, true, g"arr_decay\0");
                                }
                                    default {};
                                };
                            }
                                                default {};
                                            };
                                        };
                                    };
                                };
                            };
                        }
                            default {};
                        };
                        this.mod.store(val, ep);
                        -> val;
                    }
                        default {};
                    };
                }
                    default {};
                };
                arr = this.visit(an);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (arr == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(t, g"void indexed target\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (ix.kind == NodeKind.RANGE_EXPRESSION)
                {
                    case (true) {
                    this.unsup(t, g"slice assignment\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                idx = this.visit(ix);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (idx == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(t, g"void index\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (arr.ty.kind == LK.PTR & arr.ty.elem.kind == LK.ARRAY)
                {
                    case (true) {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = idx;
                    ep = this.mod.gep(arr, this.mod.ia, 2, true, (byte*)0);
                    et = arr.ty.elem.elem;
                    switch (vexpr.kind == NodeKind.STRING_LITERAL & et.kind == LK.INT & et.width == 8)
                    {
                        case (true) {
                        val = this.first_char(vexpr);
                    }
                        default {
                            switch (val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY & et.kind == LK.PTR)
                            {
                                case (true) {
                        switch (et.elem.kind == LK.INT & et.elem.width == 8)
                        {
                            case (true) {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            val = this.mod.gep(val, this.mod.ia, 2, true, g"str_to_ptr\0");
                        }
                            default {};
                        };
                    }
                                default {};
                            };
                        };
                    };
                    switch (val.ty.kind == LK.PTR & et.kind != LK.PTR)
                    {
                        case (true) {
                        switch (this.sty(val.ty.elem) & lt_eq(val.ty.elem, et))
                        {
                            case (true) { val = this.mod.load(val, g"struct_elem_load\0"); }
                            default { ep = this.mod.cast(g"bitcast\0", ep, this.ptr_of(val.ty), g"void_arr_elem_ptr\0"); };
                        };
                    }
                        default {
                            switch (val.ty.kind == LK.PTR & et.kind == LK.PTR)
                            {
                                case (true) {
                        switch (!lt_eq(val.ty, et))
                        {
                            case (true) { val = this.mod.cast(g"bitcast\0", val, et, g"ptr_cast\0"); }
                            default {};
                        };
                    }
                                default {};
                            };
                        };
                    };
                    val = this.convert_assign(val, et);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    this.mod.store(val, ep);
                    -> val;
                }
                    default {};
                };
                switch (arr.ty.kind == LK.PTR)
                {
                    case (true) {
                    ep = this.mod.gep_ptr(arr, idx, true, (byte*)0);
                    et = arr.ty.elem;
                    switch (val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY & et.kind == LK.PTR & et.elem.kind == LK.INT & et.elem.width == 8)
                    {
                        case (true) {
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = this.ci32(0);
                        val = this.mod.gep(val, this.mod.ia, 2, true, g"str_to_ptr\0");
                    }
                        default {
                            switch (vexpr.kind == NodeKind.STRING_LITERAL & et.kind == LK.INT & et.width == 8)
                            {
                                case (true) {
                        val = this.first_char(vexpr);
                    }
                                default {};
                            };
                        };
                    };
                    switch (val.ty.kind == LK.PTR & et.kind == LK.PTR)
                    {
                        case (true) {
                        switch (!lt_eq(val.ty, et))
                        {
                            case (true) { val = this.mod.cast(g"bitcast\0", val, et, g"ptr_cast\0"); }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (val.ty.kind == LK.PTR & et.kind != LK.PTR)
                    {
                        case (true) {
                        switch (!lt_eq(val.ty.elem, et))
                        {
                            case (true) {
                            ep = this.mod.cast(g"bitcast\0", ep, this.ptr_of(val.ty), g"void_arr_elem_ptr\0");
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    val = this.convert_assign(val, et);
                    switch (this.bad)
                    {
                        case (true) { -> (IRValue*)0; }
                        default {};
                    };
                    this.mod.store(val, ep);
                    -> val;
                }
                    default {};
                };
                this.unsup(t, g"index assignment on non-pointer\0");
                -> (IRValue*)0;
            };

            // handle_pointer_deref_assignment
            assign_deref(Node* t, IRValue* val0) -> IRValue*
            {
                IRValue* p = this.visit(t.a);
                IRValue* val = val0;
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (p == (IRValue*)0)
                {
                    case (true) {
                    this.unsup(t, g"void dereference target\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (p.ty.kind == LK.PTR & p.ty.elem.kind == LK.PTR & p.ty.elem.elem.kind == LK.PTR)
                {
                    case (true) {
                    p = this.mod.load(p, g"deref_ptr_loaded\0");
                }
                    default {};
                };
                switch (p.ty.kind != LK.PTR)
                {
                    case (true) {
                    this.unsup(t, g"dereference assignment to non-pointer\0");
                    -> (IRValue*)0;
                }
                    default {};
                };
                val = this.convert_assign(val, p.ty.elem);
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (!lt_eq(val.ty, p.ty.elem))
                {
                    case (true) { p = this.mod.cast(g"bitcast\0", p, this.ptr_of(val.ty), (byte*)0); }
                    default {};
                };
                this.mod.store(val, p);
                -> val;
            };

            // Dispatches one node. Statements return null.
            visit(Node* n) -> IRValue*
            {
                int k;
                IRValue* r;
                switch (n == (Node*)0)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                switch (this.bad)
                {
                    case (true) { -> (IRValue*)0; }
                    default {};
                };
                k = n.kind;
                switch (k == NodeKind.LITERAL)
                {
                    case (true) { -> this.x_literal(n); }
                    default {};
                };
                switch (k == NodeKind.IDENTIFIER)
                {
                    case (true) { -> this.x_ident(n); }
                    default {};
                };
                switch (k == NodeKind.BINARY_OP)
                {
                    case (true) { -> this.x_binary(n); }
                    default {};
                };
                switch (k == NodeKind.FUNCTION_CALL)
                {
                    case (true) { -> this.x_call(n); }
                    default {};
                };
                switch (k == NodeKind.ASSIGNMENT)
                {
                    case (true) { -> this.x_assign(n); }
                    default {};
                };
                switch (k == NodeKind.COMPOUND_ASSIGNMENT)
                {
                    case (true) { -> this.x_compound(n); }
                    default {};
                };
                switch (k == NodeKind.NOT_NULL)
                {
                    case (true) { -> this.x_notnull(n); }
                    default {};
                };
                switch (k == NodeKind.IN_EXPRESSION)
                {
                    case (true) { -> this.x_in(n); }
                    default {};
                };
                switch (k == NodeKind.TERNARY_OP)
                {
                    case (true) { -> this.x_ternary(n); }
                    default {};
                };
                switch (k == NodeKind.STRUCT_LITERAL)
                {
                    case (true) { -> this.x_struct_lit(n, (IRType*)0); }
                    default {};
                };
                switch (k == NodeKind.INLINE_ASM)
                {
                    case (true) { -> this.x_asm(n); }
                    default {};
                };
                switch (k == NodeKind.METHOD_CALL)
                {
                    case (true) { -> this.x_method(n); }
                    default {};
                };
                switch (k == NodeKind.UNARY_OP)
                {
                    case (true) { -> this.x_unary(n); }
                    default {};
                };
                switch (k == NodeKind.POINTER_DEREF)
                {
                    case (true) { -> this.x_deref(n); }
                    default {};
                };
                switch (k == NodeKind.ADDRESS_OF)
                {
                    case (true) { -> this.x_addrof(n); }
                    default {};
                };
                switch (k == NodeKind.CAST_EXPRESSION | k == NodeKind.TYPE_CONVERT_EXPRESSION)
                {
                    case (true) { -> this.x_cast(n); }
                    default {};
                };
                switch (k == NodeKind.STRING_LITERAL)
                {
                    case (true) { -> this.x_string(n); }
                    default {};
                };
                switch (k == NodeKind.SIZE_OF)
                {
                    case (true) { -> this.x_sizeof(n); }
                    default {};
                };
                switch (k == NodeKind.TYPE_OF)
                {
                    case (true) { -> this.x_typeof(n); }
                    default {};
                };
                switch (k == NodeKind.MEMBER_ACCESS)
                {
                    case (true) { -> this.x_member(n); }
                    default {};
                };
                switch (k == NodeKind.ARRAY_ACCESS)
                {
                    case (true) { -> this.x_index(n); }
                    default {};
                };
                switch (k == NodeKind.VARIABLE_DECLARATION)
                {
                    case (true) { -> this.x_vardecl(n); }
                    default {};
                };
                switch (k == NodeKind.EXPRESSION_STATEMENT)
                {
                    case (true) { -> this.visit(n.a); }
                    default {};
                };
                switch (k == NodeKind.BLOCK)
                {
                    case (true) { this.s_block(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.IF_STATEMENT)
                {
                    case (true) { this.s_if(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.SWITCH_STATEMENT)
                {
                    case (true) { this.s_switch(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.DEFER_STATEMENT)
                {
                    case (true) {
                    switch (this.defers == (PtrVec*)0)
                    {
                        case (true) { this.defers = pv_new(); }
                        default {};
                    };
                    pv_push(this.defers, (void*)n);
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (k == NodeKind.NORETURN_STATEMENT)
                {
                    case (true) { this.s_noreturn(); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.TRY_BLOCK)
                {
                    case (true) { this.s_try(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.WHILE_LOOP)
                {
                    case (true) { this.s_while(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.DO_LOOP)
                {
                    case (true) { this.s_do(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.DO_WHILE_LOOP)
                {
                    case (true) { this.s_dowhile(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.FOR_LOOP)
                {
                    case (true) { this.s_for(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.RETURN_STATEMENT)
                {
                    case (true) { this.s_return(n); -> (IRValue*)0; }
                    default {};
                };
                switch (k == NodeKind.BREAK_STATEMENT)
                {
                    case (true) {
                    switch (this.brk == (IRBlock*)0)
                    {
                        case (true) {
                        this.unsup(n, g"break outside loop\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (!this.mod.is_terminated())
                    {
                        case (true) { this.mod.br(this.brk); }
                        default {};
                    };
                    -> (IRValue*)0;
                }
                    default {};
                };
                switch (k == NodeKind.CONTINUE_STATEMENT)
                {
                    case (true) {
                    switch (this.cont == (IRBlock*)0)
                    {
                        case (true) {
                        this.unsup(n, g"continue outside loop\0");
                        -> (IRValue*)0;
                    }
                        default {};
                    };
                    switch (!this.mod.is_terminated())
                    {
                        case (true) { this.mod.br(this.cont); }
                        default {};
                    };
                    -> (IRValue*)0;
                }
                    default {};
                };
                this.unsup(n, node_kind_name(k));
                -> (IRValue*)0;
            };

            // ----------------------------------------------------------
            // Function bodies
            // ----------------------------------------------------------

            // visit_FunctionDef after the declaration: entry block, parameters, body
            gen_body(Node* fd, IRFunc* f, byte* obj) -> void
            {
                int i;
                int off = 0;
                TypeSpec* this_ts;
                int np = node_count(fd, 0);
                Node* p;
                byte* pname;
                IRBlock* ebk;
                IRValue* a;
                IRValue* slot;
                IRType* ft = f.ftype;
                this.bad = false;
                this.bad_what = (byte*)0;
                this.body_errs = this.nerrors;
                this.brk = (IRBlock*)0;
                this.cont = (IRBlock*)0;
                this.in_member = false;
                this.fn = f;
                                this.fnd = fd;
                this.fret = ft.elem;
                switch (fd.ts2 != (TypeSpec*)0)
                {
                    case (true) {
                    this.unsup(fd, g"dual return function\0");
                    ->;
                }
                    default {};
                };
                switch ((fd.flags `& NF_VARIADIC) != 0)
                {
                    case (true) {
                    this.unsup(fd, g"variadic function\0");
                    ->;
                }
                    default {};
                };
                switch ((fd.flags `& NF_RECURSIVE) != 0)
                {
                    case (true) {
                    this.unsup(fd, g"recursive function\0");
                    ->;
                }
                    default {};
                };
                ebk = this.mod.append_block(f, g"entry\0");
                this.mod.position(f, ebk);
                this.mod.set_entry(ebk);
                this.push_scope();
                switch (obj != (byte*)0)
                {
                    case (true) {
                    off = 1;
                    this_ts = typespec_new();
                    this.keep((void*)this_ts);
                    this_ts.base_type = DataType.DATA;
                    this_ts.custom_typename = this.mod.own(obj);
                    this_ts.pointer_depth = 1;
                    f.args[0].spec = this_ts;
                    // Method parameters were named when declared; naming them again at
                    // emission gives the .1 suffixed names
                    this.mod.rename_arg(f, 0, g"this\0");
                    i = 0;
                    while (i < np)
                    {
                        p = node_child(fd, 0, i);
                        switch (p.text != (byte*)0)
                        {
                            case (true) { this.mod.rename_arg(f, i + 1, p.text); }
                            default {
                            this.sc.clear();
                            this.sc.put_str(g"arg\0");
                            this.sc.put_int(i);
                            this.mod.rename_arg(f, i + 1, this.sc.mem);
                        };
                        };
                        i++;
                    };
                    this.define_var(g"this\0", f.args[0], this_ts);
                }
                    default {};
                };
                i = 0;
                while (i < np)
                {
                    p = node_child(fd, 0, i);
                    switch (p.text != (byte*)0)
                    {
                        case (true) { pname = p.text; }
                        default {
                        this.sc.clear();
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(i);
                        pname = this.mod.own(this.sc.mem);
                    };
                    };
                    a = f.args[i + off];
                    this.sc.clear();
                    this.sc.put_str(pname);
                    this.sc.put_str(g".addr\0");
                    slot = this.mod.alloca(a.ty, this.sc.mem);
                    slot.spec = p.ts;
                    a.spec = p.ts;
                    this.mod.store(a, slot);
                    this.define_var(pname, slot, p.ts);
                    i++;
                };
                this.visit(fd.a);
                this.pop_scope();
                switch (this.bad)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (!this.mod.is_terminated())
                {
                    case (true) {
                    switch (obj != (byte*)0 & cstr_eq(fd.text, g"__init\0"))
                    {
                        case (true) { this.mod.ret(f.args[0]); }
                        default {
                            switch (this.fret.kind == LK.VOID)
                            {
                                case (true) { this.mod.ret_void(); }
                                default {
                                    switch (this.mod.cb.lines.len == 0)
                                    {
                                        case (true) { this.mod.unreachable(); }
                                        default { this.unsup(fd, g"function must end with return\0"); };
                                    };
                                };
                            };
                        };
                    };
                }
                    default {};
                };
                ->;
            };

            // Generates the body of fd into f. On failure the function stays a declaration.
            run_body(Node* fd, IRFunc* f, byte* ns, byte* obj) -> void
            {
                int i;
                byte* prev = this.cur_obj;
                this.set_ns(ns);
                switch (obj != (byte*)0)
                {
                    case (true) { this.cur_obj = this.mod.own(obj); }
                    default {};
                };
                this.gen_body(fd, f, obj);
                this.cur_obj = prev;
                switch (this.bad)
                {
                    case (true) {
                    this.nskipped++;
                    f.is_decl = true;
                }
                    default { this.nbodies++; };
                };
                ->;
            };

            // Generates the method bodies of an object definition
            object_bodies(Node* od, byte* ns) -> void
            {
                byte* oname;
                byte* mn;
                byte* full;
                Node* m;
                IRFunc* f;
                int i;
                switch (this.is_template(od))
                {
                    case (true) { ->; }
                    default {};
                };
                oname = mangle_namespace_name(ns, od.text);
                while (i < node_count(od, 1))
                {
                    m = node_child(od, 1, i);
                    i++;
                    switch (m.text == (byte*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch ((m.flags `& NF_TEMPLATE) != 0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch ((m.flags `& NF_PROTOTYPE) != 0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (m.a == (Node*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    this.cur_obj = this.mod.own(oname);
                    mn = this.mangled_name(m.text, m);
                    this.cur_obj = (byte*)0;
                    full = join3(oname, g".\0", mn);
                    f = this.mod.find_function(full);
                    ffree(mn);
                    ffree(full);
                    switch (f == (IRFunc*)0)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (!f.is_decl)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    this.run_body(m, f, ns, oname);
                };
                ffree(oname);
                ->;
            };

            // Walks the program in declaration order and generates the bodies
            bodies_pass(Node* n0, byte* ns) -> void
            {
                Node* n = this.unwrap(n0);
                int k = n.kind;
                int s, c, e, j;
                byte* full;
                IRFunc* f;
                byte* mn;
                byte* base;
                switch (k)
                {
                    case (NodeKind.FUNCTION_DEF)
                    {
                        switch (n.text == (byte*)0)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch ((n.flags `& NF_TEMPLATE) != 0)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch ((n.flags `& NF_PROTOTYPE) != 0)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch (n.a == (Node*)0)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        base = mangle_namespace_name(ns, n.text);
                        switch ((n.flags `& NF_NO_MANGLE) != 0)
                        {
                            case (true) { mn = ts_dup(base); }
                            default { mn = this.mangled_name(base, n); };
                        };
                        f = this.mod.find_function(mn);
                        ffree(base);
                        ffree(mn);
                        switch (f == (IRFunc*)0)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        switch (!f.is_decl)
                        {
                            case (true) { ->; }
                            default {};
                        };
                        this.run_body(n, f, ns, (byte*)0);
                    }
                    case (NodeKind.OBJECT_DEF) { this.object_bodies(n, ns); }
                    case (NodeKind.EXPORT_BLOCK)
                    {
                        c = node_count(n, 0);
                        while (e < c)
                        {
                            this.bodies_pass(node_child(n, 0, e), ns);
                            e++;
                        };
                    }
                    case (NodeKind.NAMESPACE_DEF)
                    {
                        full = this.join_ns(ns, n.text);
                        this.set_ns(full);
                        while (j < 3)
                        {
                            // nested namespaces, functions, then objects
                            switch (j)
                            {
                                case (0) { s = 7; }
                                case (1) { s = 0; }
                                default { s = 2; };
                            };
                            c = this.ns_count(n, s);
                            e = 0;
                            while (e < c)
                            {
                                this.bodies_pass(this.ns_child(n, s, e), full);
                                e++;
                            };
                            j++;
                        };
                        this.set_ns(ns);
                        ffree(full);
                    }
                    default {};
                };
                ->;
            };

            gen_program(Node* prog) -> void
            {
                int i;
                int n = node_count(prog, 0);
                Node* s;
                byte* root = ts_dup(g"\0");
                int nns;
                while (i < n)
                {
                    s = node_child(prog, 0, i);
                    switch (s.kind == NodeKind.NAMESPACE_DEF | s.kind == NodeKind.NAMESPACE_DEF_STATEMENT)
                    {
                        case (true) { nns++; }
                        default {};
                    };
                    i++;
                };
                i = 0;
                standard::io::console::println(g"[AST] Begining codegen for Flux program ...\0");
                standard::io::console::print(g"[AST] Total statements in AST: \0");
                standard::io::console::println(n);
                standard::io::console::print(g"[AST] Namespace definitions: \0");
                standard::io::console::println(nns);
                standard::io::console::println(g"[AST] Pass 1: Processing using statements...\0");
                standard::io::console::println(g"[AST] Pass 2: Processing not using statements...\0");
                while (i < n)
                {
                    s = node_child(prog, 0, i);
                    switch (s.kind)
                    {
                        case (NodeKind.USING_STATEMENT) { st_add_using_namespace(this.st, s.text); }
                        case (NodeKind.NOT_USING_STATEMENT) { st_remove_using_namespace(this.st, s.text); }
                        default {};
                    };
                    i++;
                };
                i = 0;
                standard::io::console::println(g"[AST] Pre-pass: Registering all object types and extern blocks...\0");
                while (i < n)
                {
                    this.collect_consts(node_child(prog, 0, i), root);
                    i++;
                };
                i = 0;
                while (i < n)
                {
                    this.cur_stmt = i;
                    this.types_pass(node_child(prog, 0, i), root);
                    i++;
                };
                // Top level extern blocks are registered first, as the base pre-pass does
                i = 0;
                while (i < n)
                {
                    switch (node_child(prog, 0, i).kind == NodeKind.EXTERN_BLOCK)
                    {
                        case (true) { this.decls_pass(node_child(prog, 0, i), root); }
                        default {};
                    };
                    i++;
                };
                i = 0;
                while (i < n)
                {
                    this.decls_pass(node_child(prog, 0, i), root);
                    i++;
                };
                i = 0;
                standard::io::console::println(g"[AST] Pass 3: Processing all other statements...\0");
                while (i < n)
                {
                    this.cur_stmt = i;
                    s = node_child(prog, 0, i);
                    // The base global builder keeps a block after the first top level
                    // function body, so only namespaces before it extend __static_init
                    switch (!this.si_closed & (s.kind == NodeKind.NAMESPACE_DEF | s.kind == NodeKind.NAMESPACE_DEF_STATEMENT))
                    {
                        case (true) { this.static_init_block(); }
                        default {};
                    };
                    this.bodies_pass(s, root);
                    switch (s.kind == NodeKind.FUNCTION_DEF)
                    {
                        case (true) {
                        switch (s.a != (Node*)0)
                        {
                            case (true) { this.si_closed = true; }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                ffree(root);
                this.main_stubs();
                ->;
            };

            // Defines whichever of main() and main(int, byte**) the program left undefined,
            // so FRTStartup can call either form
            // visit_NamespaceDef without a builder: __static_init gains a block that returns
            static_init_block() -> void
            {
                IRFunc* f = this.mod.find_function(g"__static_init\0");
                IRBlock* b;
                switch (f == (IRFunc*)0)
                {
                    case (true) {
                    f = this.mod.add_function(this.mod.t_func(this.t_void, (IRType**)0, 0, false), g"__static_init\0");
                    b = this.mod.append_block(f, g"entry\0");
                }
                    default { b = this.mod.append_block(f, g"cont\0"); };
                };
                this.mod.position(f, b);
                this.mod.ret_void();
                ->;
            };

            main_stubs() -> void
            {
                IRFunc* m0 = this.mod.find_function(g"main__0__ret_intE1\0");
                IRFunc* m2 = this.mod.find_function(g"main__2__intE1__byteE1_ptr2__ret_intE1\0");
                IRBlock* eb;
                IRValue* r;
                switch (m0 == (IRFunc*)0 | m2 == (IRFunc*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (m0.is_decl & !m2.is_decl)
                {
                    case (true) {
                    eb = this.mod.append_block(m0, g"entry\0");
                    this.mod.position(m0, eb);
                    this.mod.set_entry(eb);
                    this.mod.ia[0] = this.mod.c_int(this.t_i32, (i64)0);
                    this.mod.ia[1] = this.mod.c_null(m2.ftype.items[1]);
                    this.mod.ret(this.mod.call(m2.self, this.mod.ia, 2, (byte*)0));
                    m0.is_decl = false;
                }
                    default {
                        switch (m2.is_decl & !m0.is_decl)
                        {
                            case (true) {
                    eb = this.mod.append_block(m2, g"entry\0");
                    this.mod.position(m2, eb);
                    this.mod.set_entry(eb);
                    this.mod.ret(this.mod.call(m0.self, this.mod.ia, 0, (byte*)0));
                    m2.is_decl = false;
                }
                            default {};
                        };
                    };
                };
                ->;
            };
        };
    };
};

#endif;
