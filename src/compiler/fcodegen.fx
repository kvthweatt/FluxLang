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
        def dup_from(byte* s, int start) -> byte*
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
            return r;
        };

        // Bit width of an LLVM type (SizeOfTypeHandler.bits_from_llvm_type)
        def bits_of(IRType* t) -> int
        {
            int i, total;
            int k = t.kind;
            if (k == LK.INT) { return t.width; };
            if (k == LK.FLOAT) { return 32; };
            if (k == LK.DOUBLE) { return 64; };
            if (k == LK.ARRAY) { return bits_of(t.elem) * t.count; };
            if (k == LK.PTR) { return 64; };
            if (k == LK.STRUCT | k == LK.ISTRUCT)
            {
                while (i < t.nitems)
                {
                    total = total + bits_of(t.items[i]);
                    i++;
                };
                return total;
            };
            return 0;
        };

        // Field width used by ObjectTypeHandler.calculate_field_layout
        def obj_field_bits(IRType* t, int* align_out) -> int
        {
            IRType* e;
            if (t.kind == LK.INT)
            {
                align_out[0] = t.width;
                return t.width;
            };
            if (t.kind == LK.FLOAT)
            {
                align_out[0] = 32;
                return 32;
            };
            if (t.kind == LK.DOUBLE)
            {
                align_out[0] = 64;
                return 64;
            };
            if (t.kind == LK.ARRAY)
            {
                e = t.elem;
                if (e.kind == LK.INT)
                {
                    align_out[0] = e.width;
                    return e.width * t.count;
                };
                if (e.kind == LK.FLOAT)
                {
                    align_out[0] = 32;
                    return 32 * t.count;
                };
                if (e.kind == LK.DOUBLE)
                {
                    align_out[0] = 64;
                    return 64 * t.count;
                };
                align_out[0] = 64;
                return 64 * t.count;
            };
            if (t.kind == LK.STRUCT | t.kind == LK.ISTRUCT)
            {
                align_out[0] = 64;
                return bits_of(t);
            };
            align_out[0] = 64;
            return 64;
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
            PtrVec* al_names;   // type aliases in declaration order
            PtrVec* al_tys;
            PtrVec* al_specs;

            def __init(FXC_SYMTABLE* s) -> this
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
                this.al_names = pv_new();
                this.al_tys = pv_new();
                this.al_specs = pv_new();
                return this;
            };

            def __expr() -> CodeGen*
            {
                return this;
            };

            def __exit() -> void
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
                pv_free(this.al_names);
                pv_free(this.al_tys);
                pv_free(this.al_specs);
                pv_free(this.scopes);
                ffree(this.cur_ns);
                this.mod.__exit();
                ffree((byte*)this.mod);
                this.sc.__exit();
                this.asmb.__exit();
                this.asmc.__exit();
                return;
            };

            // ----------------------------------------------------------
            // Errors and small helpers
            // ----------------------------------------------------------

            def fail(byte* msg, int line) -> void
            {
                this.nerrors++;
                if (this.err_msg == (byte*)0)
                {
                    this.err_msg = this.mod.own(msg);
                    this.err_line = line;
                };
                return;
            };

            // Keeps a heap block alive until __exit
            def keep(void* p) -> void
            {
                pv_push(this.owned, p);
                return;
            };

            def ptr_of(IRType* t) -> IRType*
            {
                return this.mod.t_ptr(t);
            };

            def set_ns(byte* ns) -> void
            {
                ffree(this.cur_ns);
                this.cur_ns = ts_dup(ns);
                st_set_namespace(this.st, ns);
                return;
            };

            // Heap ns::name joined for a nested namespace
            def join_ns(byte* parent, byte* name) -> byte*
            {
                if (parent[0] == 0) { return ts_dup(name); };
                return join3(parent, g"::\0", name);
            };

            // ----------------------------------------------------------
            // Integer constants (global initializers used as array sizes)
            // ----------------------------------------------------------

            def add_const(byte* mangled, i64 v) -> void
            {
                i64* box = (i64*)fmalloc((u64)8);
                box[0] = v;
                this.keep((void*)box);
                nm_put(this.consts, mangled, (void*)box);
                return;
            };

            def const_get(byte* name, i64* out) -> bool
            {
                void* p = nm_get(this.consts, name);
                if (p == (void*)0) { return false; };
                i64* box = (i64*)p;
                out[0] = box[0];
                return true;
            };

            // Mirrors the four step lookup in get_llvm_type: bare name, current
            // namespace, using namespaces, then the symbol table.
            def resolve_dim(byte* name, i64* out) -> bool
            {
                byte* m;
                bool ok;
                int i;
                FXC_SYMENTRY* e;
                if (this.const_get(name, out)) { return true; };
                if (this.cur_ns[0] != 0)
                {
                    m = mangle_namespace_name(this.cur_ns, name);
                    ok = this.const_get(m, out);
                    ffree(m);
                    if (ok) { return true; };
                };
                while (i < this.st.using_ns.len)
                {
                    m = mangle_namespace_name((byte*)this.st.using_ns.items[i], name);
                    ok = this.const_get(m, out);
                    ffree(m);
                    if (ok) { return true; };
                    i++;
                };
                e = st_lookup_any(this.st, name, (byte*)0);
                if (e != (FXC_SYMENTRY*)0)
                {
                    m = sym_mangled(e);
                    ok = this.const_get(m, out);
                    ffree(m);
                    if (ok) { return true; };
                };
                return false;
            };

            // Child count and child of a namespace by virtual slot: 0..5 are the lists,
            // 6 is the variables list (a), 7 the nested namespaces list (b)
            def ns_count(Node* n, int s) -> int
            {
                if (s < 6) { return node_count(n, s); };
                if (s == 6)
                {
                    if (n.a == (Node*)0) { return 0; };
                    return node_count(n.a, 0);
                };
                if (n.b == (Node*)0) { return 0; };
                return node_count(n.b, 0);
            };

            def ns_child(Node* n, int s, int i) -> Node*
            {
                if (s < 6) { return node_child(n, s, i); };
                if (s == 6) { return node_child(n.a, 0, i); };
                return node_child(n.b, 0, i);
            };

            // Registers integer-literal initializers of globals before types are lowered
            def collect_consts(Node* n, byte* ns) -> void
            {
                int k = n.kind;
                int s, c, e;
                byte* full;
                byte* m;
                if (k == NodeKind.NAMESPACE_DEF_STATEMENT | k == NodeKind.EXPORT_BLOCK |
                    k == NodeKind.EXTERN_BLOCK)
                {
                    if (n.a != (Node*)0) { this.collect_consts(n.a, ns); };
                    return;
                };
                if (k == NodeKind.NAMESPACE_DEF)
                {
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
                    return;
                };
                if (k == NodeKind.VARIABLE_DECLARATION)
                {
                    if (n.text == (byte*)0) { return; };
                    if (n.a == (Node*)0) { return; };
                    if (n.a.kind != NodeKind.LITERAL) { return; };
                    if (n.a.op == DataType.FLOAT | n.a.op == DataType.DOUBLE) { return; };
                    m = mangle_namespace_name(ns, n.text);
                    this.add_const(m, n.a.ival);
                    ffree(m);
                };
                return;
            };

            // ----------------------------------------------------------
            // Type lowering
            // ----------------------------------------------------------

            // Struct, object or union symbol to its LLVM type, null when unknown
            def type_of_symbol(FXC_SYMENTRY* e) -> IRType*
            {
                byte* m = sym_mangled(e);
                void* p;
                IRType* r = (IRType*)0;
                if (e.kind_id == SymbolKind.STRUCT | e.kind_id == SymbolKind.OBJECT)
                {
                    p = nm_get(this.structs, m);
                    if (p != (void*)0)
                    {
                        SInfo* si = (SInfo*)p;
                        r = si.ty;
                    }
                    else { r = this.mod.t_named(m); };
                }
                elif (e.kind_id == SymbolKind.UNION)
                {
                    p = nm_get(this.unions, m);
                    if (p != (void*)0) { r = (IRType*)p; };
                }
                elif (e.kind_id == SymbolKind.ENUM)
                {
                    p = nm_get(this.enums, m);
                    if (p != (void*)0) { r = (IRType*)p; }
                    else { r = this.t_i32; };
                };
                ffree(m);
                return r;
            };

            // TypeResolver.resolve_custom_type
            def resolve_custom(byte* name) -> IRType*
            {
                FXC_SYMENTRY* e = st_lookup_any(this.st, name, this.cur_ns);
                byte* m;
                void* p;
                if (e == (FXC_SYMENTRY*)0) { return (IRType*)0; };
                if (e.kind_id == SymbolKind.TYPE)
                {
                    if (e.ts != (void*)0) { return this.lower((TypeSpec*)e.ts, false, 0); };
                    m = sym_mangled(e);
                    p = nm_get(this.aliases, m);
                    ffree(m);
                    if (p != (void*)0) { return (IRType*)p; };
                    return (IRType*)0;
                };
                if (e.kind_id == SymbolKind.TRAIT)
                {
                    this.fail(g"trait cannot be used in type contexts\0", 0);
                    return (IRType*)0;
                };
                return this.type_of_symbol(e);
            };

            // Array element count of a size node: literal value, or identifier resolved
            // as a constant. Returns false when the size is not a compile time constant.
            def dim_value(Node* d, i64* out) -> bool
            {
                if (d.kind == NodeKind.LITERAL)
                {
                    out[0] = d.ival;
                    return true;
                };
                if (d.kind == NodeKind.IDENTIFIER)
                {
                    if (d.text != (byte*)0) { return this.resolve_dim(d.text, out); };
                };
                return false;
            };

            // TypeSystem.get_llvm_type. incl wraps the array dimensions.
            def lower(TypeSpec* t, bool incl, int line) -> IRType*
            {
                IRType* base = (IRType*)0;
                IRType* el;
                IRType** ps;
                int i, depth, bt;
                i64 dv;
                bool wrap_i8;

                bt = t.base_type;
                if (bt == DataType.FUNC_PTR)
                {
                    ps = (IRType**)fmalloc((u64)(t.fp_nparams + 1) * (u64)((sizeof(IRType*) + 7) / 8));
                    this.keep((void*)ps);
                    while (i < t.fp_nparams)
                    {
                        ps[i] = this.lower(t.fp_params[i], false, line);
                        i++;
                    };
                    return this.ptr_of(this.mod.t_func(this.lower(t.fp_ret, false, line), ps, t.fp_nparams, false));
                };

                if (t.custom_typename != (byte*)0)
                {
                    base = this.resolve_custom(t.custom_typename);
                    if (base == (IRType*)0)
                    {
                        this.fail(join3(g"Unknown type: \0", t.custom_typename, g"\0"), line);
                        return this.t_i32;
                    };
                    if (base.kind == LK.ARRAY & !ts_is_array(t)) { base = this.ptr_of(base.elem); };
                }
                elif (bt == DataType.SINT | bt == DataType.UINT) { base = this.t_i32; }
                elif (bt == DataType.FLOAT) { base = this.t_float; }
                elif (bt == DataType.DOUBLE) { base = this.t_double; }
                elif (bt == DataType.SLONG | bt == DataType.ULONG) { base = this.t_i64; }
                elif (bt == DataType.BOOL) { base = this.t_i1; }
                elif (bt == DataType.CHAR) { base = this.t_i8; }
                elif (bt == DataType.BYTE)
                {
                    if (t.bit_width > 0) { base = this.mod.t_int(t.bit_width); }
                    else { base = this.mod.t_int(this.byte_width); };
                }
                elif (bt == DataType.STRUCT | bt == DataType.OBJECT) { base = this.t_i8; }
                elif (bt == DataType.ENUM) { base = this.t_i32; }
                elif (bt == DataType.VOID) { base = this.t_void; }
                elif (bt == DataType.DATA)
                {
                    if (t.bit_width <= 0)
                    {
                        this.fail(g"DATA type missing bit_width\0", line);
                        return this.t_i32;
                    };
                    base = this.mod.t_int(t.bit_width);
                }
                elif (bt == DataType.DICT)
                {
                    IRType* kt = this.t_i8;
                    IRType* vt = this.t_i8;
                    int cap = 0;
                    if (t.dict_capacity > 0) { cap = t.dict_capacity; };
                    if (t.dict_key != (TypeSpec*)0) { kt = this.lower(t.dict_key, false, line); };
                    if (t.dict_value != (TypeSpec*)0) { vt = this.lower(t.dict_value, false, line); };
                    ps = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                    this.keep((void*)ps);
                    ps[0] = this.mod.t_array(kt, cap);
                    ps[1] = this.mod.t_array(vt, cap);
                    ps[2] = this.t_i32;
                    base = this.mod.t_struct(ps, 3);
                }
                elif (bt == DataType.THIS)
                {
                    if (this.cur_obj != (byte*)0)
                    {
                        base = this.ptr_of(this.mod.t_named(this.cur_obj));
                    }
                    else { base = this.t_i8p; };
                }
                else
                {
                    this.fail(g"Unsupported type\0", line);
                    return this.t_i32;
                };

                el = base;
                if (ts_is_pointer(t))
                {
                    depth = t.pointer_depth;
                    if (depth <= 0) { depth = 1; };
                    wrap_i8 = (bt == DataType.VOID | bt == DataType.STRUCT | bt == DataType.OBJECT);
                    if (wrap_i8) { el = this.t_i8; };
                    i = 0;
                    while (i < depth)
                    {
                        el = this.ptr_of(el);
                        i++;
                    };
                };

                if (!incl) { return el; };

                if (ts_is_array(t))
                {
                    if (t.array_dims != (NodeVec*)0)
                    {
                        if (t.array_dims.len > 0)
                        {
                            IRType* cur = el;
                            Node* d;
                            i = t.array_dims.len - 1;
                            while (i >= 0)
                            {
                                d = t.array_dims.items[i];
                                if (d != (Node*)0)
                                {
                                    if (this.dim_value(d, @dv)) { cur = this.mod.t_array(cur, (int)dv); }
                                    else { return this.ptr_of(el); };
                                }
                                else { cur = this.ptr_of(cur); };
                                i--;
                            };
                            return cur;
                        };
                    };
                    if (t.array_size != (Node*)0)
                    {
                        if (this.dim_value(t.array_size, @dv)) { return this.mod.t_array(el, (int)dv); };
                        return this.ptr_of(el);
                    };
                    if (el.kind == LK.PTR) { return el; };
                    return this.ptr_of(el);
                };
                return el;
            };

            // convert_type_spec_to_llvm: dicts are passed by pointer
            def lower_sig(TypeSpec* t, int line) -> IRType*
            {
                IRType* b;
                if (t.base_type == DataType.DICT)
                {
                    b = this.lower(t, true, line);
                    if (ts_is_pointer(t)) { return b; };
                    return this.ptr_of(b);
                };
                return this.lower(t, true, line);
            };

            // ----------------------------------------------------------
            // Struct and object types
            // ----------------------------------------------------------

            def new_sinfo(byte* name, int n, bool is_object) -> SInfo*
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
                return si;
            };

            // Text of the {total_bits, field_count, [fields]} TLD constant and its type
            def tld_global(SInfo* si) -> void
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
                    if (i > 0) { this.sc.put_str(g", \0"); };
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
                return;
            };

            // Prepends or appends the fields of the base structs named in list slot
            def struct_member_count(Node* sd) -> int
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
                    if (p != (void*)0)
                    {
                        bi = (SInfo*)p;
                        total = total + bi.n;
                    };
                    i++;
                };
                while (j < node_count(sd, 2))
                {
                    b = node_child(sd, 2, j);
                    p = nm_get(this.structs, b.text);
                    if (p != (void*)0)
                    {
                        bi = (SInfo*)p;
                        total = total + bi.n;
                    };
                    j++;
                };
                return total;
            };

            // visit_StructDef
            def reg_struct(Node* sd, byte* ns) -> void
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

                if (sd.l4 != (NodeVec*)0)
                {
                    if (sd.l4.len > 0)
                    {
                        ffree(name);
                        return;
                    };
                };

                nm_ = node_count(sd, 0);
                p = nm_get(this.structs, name);
                if (p != (void*)0)
                {
                    if (nm_ == 0 & node_count(sd, 1) == 0 & node_count(sd, 2) == 0)
                    {
                        ffree(name);
                        return;
                    };
                    si = (SInfo*)p;
                    if (si.ty.defined & si.ty.nitems > 0)
                    {
                        ffree(name);
                        return;
                    };
                };

                total = this.struct_member_count(sd);
                if (total == 0)
                {
                    if (nm_get(this.structs, name) == (void*)0) { this.new_sinfo(name, 0, false); };
                    ffree(name);
                    return;
                };
                si = this.new_sinfo(name, total, false);
                si.ty.defined = false;

                // Pre-body bases, then own members, then post bases
                i = 0;
                while (i < node_count(sd, 1))
                {
                    b = node_child(sd, 1, i);
                    p = nm_get(this.structs, b.text);
                    if (p == (void*)0)
                    {
                        this.fail(join3(g"Struct composition: base struct '\0", b.text, g"' has not been defined\0"), sd.line);
                    }
                    else
                    {
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
                    if (p == (void*)0)
                    {
                        this.fail(join3(g"Struct post-composition: struct '\0", b.text, g"' has not been defined\0"), sd.line);
                    }
                    else
                    {
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
                    if (si.specs[i].bit_width > 0 & !ts_is_array(si.specs[i]))
                    {
                        bw = si.specs[i].bit_width;
                        if (si.specs[i].alignment > 0) { al = si.specs[i].alignment; }
                        else { al = bw; };
                    }
                    else
                    {
                        bw = bits_of(ft);
                        al = bw;
                        if (bw > 64) { al = 64; };
                    };
                    si.offs[i] = off;
                    si.bits[i] = bw;
                    si.aligns[i] = al;
                    off = off + bw;
                    if (al > si.max_align) { si.max_align = al; };
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
                return;
            };

            // ObjectTypeHandler.create_member_types, create_struct_type, create_vtable
            def reg_object_type(Node* od, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, od.text);
                int n = node_count(od, 0);
                int i, off, bw;
                void* p;
                SInfo* si;
                Node* mem;

                if (this.is_template(od))
                {
                    ffree(name);
                    return;
                };

                p = nm_get(this.structs, name);
                if (p != (void*)0)
                {
                    si = (SInfo*)p;
                    if (n == 0 | si.n > 0)
                    {
                        ffree(name);
                        return;
                    };
                };

                if (n == 0)
                {
                    if (p == (void*)0)
                    {
                        si = this.new_sinfo(name, 0, true);
                        si.ty.defined = false;
                    };
                    ffree(name);
                    return;
                };

                if (p == (void*)0) { si = this.new_sinfo(name, n, true); }
                else
                {
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
                    if (this.al_tmp > si.max_align) { si.max_align = this.al_tmp; };
                    off = off + bw;
                    i++;
                };
                si.total_bits = off;
                this.mod.set_body(si.ty, si.ftys, si.n);
                ffree(name);
                return;
            };

            def is_template(Node* od) -> bool
            {
                if (od.d == (Node*)0) { return false; };
                if (od.d.l0 == (NodeVec*)0) { return false; };
                return od.d.l0.len > 0;
            };

            // Types nested inside an object
            def reg_object_nested(Node* od, byte* ns) -> void
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
                return;
            };

            // ----------------------------------------------------------
            // Enums, unions, aliases
            // ----------------------------------------------------------

            def reg_enum(Node* ed, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, ed.text);
                IRType* ty = this.t_i32;
                int i, n;
                byte* cn;
                byte* nmx;
                IRGlobal* g;
                IRValue* v;
                Node* item;
                if (ed.ts != (TypeSpec*)0) { ty = this.lower(ed.ts, false, ed.line); };
                nm_put(this.enums, name, (void*)ty);
                n = node_count(ed, 0);
                while (i < n)
                {
                    item = node_child(ed, 0, i);
                    cn = join3(name, g".\0", item.text);
                    if (ty.kind == LK.STRUCT | ty.kind == LK.ISTRUCT | ty.kind == LK.ARRAY)
                    {
                        g = this.mod.add_global(ty, cn, g"zeroinitializer\0");
                    }
                    else
                    {
                        v = this.mod.c_int(ty, item.ival);
                        g = this.mod.add_global(ty, cn, v.text);
                        g.constant = true;
                    };
                    i64* eb = (i64*)fmalloc((u64)8);
                    eb[0] = item.ival;
                    this.keep((void*)eb);
                    nm_put(this.enumvals, this.mod.own(cn), (void*)eb);
                    ffree(cn);
                    i++;
                };
                ffree(name);
                return;
            };

            // Size in bytes the way visit_UnionDef computes it
            def union_size(IRType* t) -> int
            {
                int total, i;
                IRType* e;
                if (t.kind == LK.INT) { return (t.width + 7) / 8; };
                if (t.kind == LK.FLOAT) { return 4; };
                if (t.kind == LK.DOUBLE) { return 8; };
                if (t.kind == LK.PTR) { return 8; };
                if (t.kind == LK.ARRAY)
                {
                    e = t.elem;
                    if (e.kind == LK.INT) { return ((e.width + 7) / 8) * t.count; };
                    if (e.kind == LK.FLOAT) { return 4 * t.count; };
                    if (e.kind == LK.DOUBLE) { return 8 * t.count; };
                    return 8 * t.count;
                };
                if (t.kind == LK.STRUCT)
                {
                    while (i < t.nitems)
                    {
                        e = t.items[i];
                        if (e.kind == LK.INT) { total = total + (e.width + 7) / 8; }
                        elif (e.kind == LK.FLOAT) { total = total + 4; }
                        else { total = total + 8; };
                        i++;
                    };
                    return total;
                };
                return 8;
            };

            def reg_union(Node* ud, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, ud.text);
                int n = node_count(ud, 0);
                int i, sz, mx;
                IRType* mt;
                IRType* mxt = (IRType*)0;
                IRType** parts;
                Node* mem;
                i = 0;
                while (i < n)
                {
                    mem = node_child(ud, 0, i);
                    mt = this.lower(mem.ts, false, ud.line);
                    sz = this.union_size(mt);
                    if (sz > mx)
                    {
                        mx = sz;
                        mxt = mt;
                    };
                    i++;
                };
                parts = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)parts);
                if (ud.text2 != (byte*)0)
                {
                    parts[0] = this.t_i32;
                    parts[1] = this.mod.t_array(this.t_i8, mx);
                    nm_put(this.unions, name, (void*)this.mod.t_struct(parts, 2));
                }
                else
                {
                    if (mxt == (IRType*)0) { mxt = this.t_i8; };
                    parts[0] = mxt;
                    nm_put(this.unions, name, (void*)this.mod.t_struct(parts, 1));
                };
                ffree(name);
                return;
            };

            def reg_alias(Node* td, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, td.text);
                IRType* ty = this.lower(td.ts, true, td.line);
                nm_put(this.aliases, name, (void*)ty);
                pv_push(this.al_names, (void*)this.mod.own(td.text));
                pv_push(this.al_tys, (void*)ty);
                pv_push(this.al_specs, (void*)td.ts);
                ffree(name);
                return;
            };

            // ----------------------------------------------------------
            // Functions
            // ----------------------------------------------------------

            def cc_name(byte* cc) -> byte*
            {
                if (cstr_eq(cc, g"cdecl\0")) { return this.mod.own(g"ccc\0"); };
                if (cstr_eq(cc, g"stdcall\0")) { return this.mod.own(g"x86_stdcallcc\0"); };
                if (cstr_eq(cc, g"fastcall\0")) { return this.mod.own(g"fastcc\0"); };
                if (cstr_eq(cc, g"thiscall\0")) { return this.mod.own(g"x86_thiscallcc\0"); };
                if (cstr_eq(cc, g"vectorcall\0")) { return this.mod.own(g"x86_vectorcallcc\0"); };
                return this.mod.own(cc);
            };

            // Heap array of the parameter TypeSpecs of a function node
            def param_specs(Node* fd) -> TypeSpec**
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
                return ps;
            };

            def mangled_name(byte* base, Node* fd) -> byte*
            {
                this.sc.clear();
                mangle_function(@this.sc, base, this.param_specs(fd), node_count(fd, 0), fd.ts);
                return ts_dup(this.sc.mem);
            };

            // Names the arguments of a function the way visit_FunctionDef does
            def name_args(IRFunc* f, Node* fd, int skip) -> void
            {
                int i;
                Node* p;
                while (i < f.nargs - skip)
                {
                    p = node_child(fd, 0, i);
                    if (p.text != (byte*)0) { this.mod.name_arg(f, i + skip, p.text); }
                    else
                    {
                        this.sc.clear();
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(i);
                        this.mod.name_arg(f, i + skip, this.sc.mem);
                    };
                    i++;
                };
                return;
            };

            // Function type of a FUNCTION_DEF (dual return folds into a struct)
            def func_type_of(Node* fd, int skip, IRType* first) -> IRType*
            {
                int n = node_count(fd, 0);
                IRType* ret = this.lower_sig(fd.ts, fd.line);
                IRType** ps;
                IRType** rp;
                int i;
                if (fd.ts2 != (TypeSpec*)0)
                {
                    rp = (IRType**)fmalloc((u64)4 * (u64)((sizeof(IRType*) + 7) / 8));
                    this.keep((void*)rp);
                    rp[0] = ret;
                    rp[1] = this.lower_sig(fd.ts2, fd.line);
                    rp[2] = this.t_i1;
                    ret = this.mod.t_struct(rp, 3);
                };
                ps = (IRType**)fmalloc((u64)(n + skip + 1) * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)ps);
                if (skip > 0) { ps[0] = first; };
                while (i < n)
                {
                    ps[i + skip] = this.lower_sig(node_child(fd, 0, i).ts, fd.line);
                    i++;
                };
                return this.mod.t_func(ret, ps, n + skip, (fd.flags `& NF_VARIADIC) != 0);
            };

            // visit_FunctionDef up to the point a body would be emitted
            def declare_function(Node* fd, byte* ns) -> IRFunc*
            {
                if (fd.text == (byte*)0) { return (IRFunc*)0; };
                if ((fd.flags `& NF_TEMPLATE) != 0) { return (IRFunc*)0; };
                IRType* ft = this.func_type_of(fd, 0, (IRType*)0);
                byte* base = mangle_namespace_name(ns, fd.text);
                byte* mn;
                IRFunc* f;
                IRFunc* ex;
                bool proto = (fd.flags `& NF_PROTOTYPE) != 0;
                if ((fd.flags `& NF_NO_MANGLE) != 0) { mn = ts_dup(base); }
                else { mn = this.mangled_name(base, fd); };
                ex = this.mod.find_function(mn);
                if (ex != (IRFunc*)0)
                {
                    if (proto) { f = ex; }
                    elif (ex.is_decl & ex.nargs == node_count(fd, 0)) { f = ex; }
                    else
                    {
                        if (nm_has(this.defined, mn))
                        {
                            this.fail(join3(g"Function '\0", fd.text, g"' redefined\0"), fd.line);
                            ffree(base);
                            ffree(mn);
                            return ex;
                        };
                        byte* dn = join3(mn, g"__\0", g"args\0");
                        f = this.mod.find_function(dn);
                        if (f == (IRFunc*)0) { f = this.mod.add_function(ft, dn); };
                        ffree(dn);
                    };
                }
                else
                {
                    f = this.mod.add_function(ft, mn);
                    this.nfuncs++;
                };
                if (fd.text2 != (byte*)0) { f.cconv = this.cc_name(fd.text2); };
                if (!proto)
                {
                    nm_put(this.defined, mn, (void*)f);
                    nm_put(this.fdefs, f.name, (void*)fd);
                    if ((fd.flags `& NF_INLINE) != 0) { pv_push(f.attrs, (void*)this.mod.own(g"alwaysinline\0")); };
                    this.name_args(f, fd, 0);
                };
                ffree(base);
                ffree(mn);
                return f;
            };

            // visit_ExternBlock declaration
            def declare_extern(Node* fd, byte* ns) -> void
            {
                IRType* ft;
                byte* base;
                byte* fin;
                IRFunc* f;
                IRType* vt;
                IRGlobal* g;
                if (fd.kind == NodeKind.VARIABLE_DECLARATION)
                {
                    vt = this.lower(fd.ts, false, fd.line);
                    if (this.mod.find_global(fd.text) == (IRGlobal*)0)
                    {
                        g = this.mod.add_global(vt, fd.text, (byte*)0);
                        g.linkage = this.mod.own(g"external\0");
                    };
                    return;
                };
                if (fd.text == (byte*)0) { return; };
                if ((fd.flags `& NF_PROTOTYPE) == 0)
                {
                    this.fail(join3(g"Extern functions must be prototypes: \0", fd.text, g"\0"), fd.line);
                    return;
                };
                ft = this.extern_type(fd);
                base = ts_dup(fd.text);
                int cut = 0;
                int k = 0;
                while (base[k] != 0)
                {
                    if (base[k] == ':' & base[k + 1] == ':') { cut = k + 2; };
                    k++;
                };
                byte* b1 = dup_from(base, cut);
                k = 0;
                cut = 0;
                while (b1[k] != 0)
                {
                    if (b1[k] == '_' & b1[k + 1] == '_') { cut = k + 2; };
                    k++;
                };
                byte* b2 = dup_from(b1, cut);
                if ((fd.flags `& NF_NO_MANGLE) != 0) { fin = ts_dup(b2); }
                else { fin = this.mangled_name(b2, fd); };
                f = this.mod.find_function(fin);
                if (f == (IRFunc*)0)
                {
                    f = this.mod.add_function(ft, fin);
                    this.nfuncs++;
                };
                f.linkage = this.mod.own(g"external\0");
                this.name_args(f, fd, 0);
                ffree(base);
                ffree(b1);
                ffree(b2);
                ffree(fin);
                return;
            };

            // Extern prototypes lower without the dict/dual-return handling
            def extern_type(Node* fd) -> IRType*
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
                return this.mod.t_func(this.lower(fd.ts, false, fd.line), ps, n, false);
            };

            // ObjectTypeHandler.create_method_signature and predeclare_method
            def declare_method(Node* od, Node* m, byte* obj_name) -> void
            {
                IRType* st_ty = this.mod.t_named(obj_name);
                IRType* self_ty = this.ptr_of(st_ty);
                byte* prev = this.cur_obj;
                IRType* ft;
                IRFunc* f;
                byte* mn;
                byte* full;
                byte* mid;
                if (m.text == (byte*)0) { return; };
                if ((m.flags `& NF_TEMPLATE) != 0) { return; };
                this.cur_obj = this.mod.own(obj_name);
                if (m.ts.base_type == DataType.THIS)
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
                else
                {
                    ft = this.func_type_of(m, 1, self_ty);
                };
                mn = this.mangled_name(m.text, m);
                full = join3(obj_name, g".\0", mn);
                f = this.mod.find_function(full);
                if (f == (IRFunc*)0)
                {
                    f = this.mod.add_function(ft, full);
                    this.nfuncs++;
                };
                this.mod.name_arg(f, 0, g"this\0");
                this.name_args(f, m, 1);
                if (m.text2 != (byte*)0) { f.cconv = this.cc_name(m.text2); };
                ffree(mn);
                ffree(full);
                this.cur_obj = prev;
                return;
            };

            def declare_object_methods(Node* od, byte* ns) -> void
            {
                byte* name = mangle_namespace_name(ns, od.text);
                int i;
                Node* m;
                if (this.is_template(od))
                {
                    ffree(name);
                    return;
                };
                while (i < node_count(od, 1))
                {
                    m = node_child(od, 1, i);
                    this.declare_method(od, m, name);
                    i++;
                };
                ffree(name);
                return;
            };

            // ----------------------------------------------------------
            // Program walk
            // ----------------------------------------------------------

            def unwrap(Node* n) -> Node*
            {
                int k = n.kind;
                if (k == NodeKind.FUNCTION_DEF_STATEMENT | k == NodeKind.STRUCT_DEF_STATEMENT |
                    k == NodeKind.OBJECT_DEF_STATEMENT | k == NodeKind.ENUM_DEF_STATEMENT |
                    k == NodeKind.UNION_DEF_STATEMENT | k == NodeKind.NAMESPACE_DEF_STATEMENT)
                {
                    return n.a;
                };
                return n;
            };

            // Visit order of namespace members (visit_NamespaceDef): nested namespaces,
            // enums, structs, objects for types; nested, externs, objects, functions
            // for declarations
            def slot_at(int j, bool types) -> int
            {
                if (types)
                {
                    if (j == 0) { return 7; };
                    if (j == 1) { return 3; };
                    if (j == 2) { return 1; };
                    return 2;
                };
                if (j == 0) { return 7; };
                if (j == 1) { return 5; };
                if (j == 2) { return 2; };
                return 0;
            };

            // Registers every type declared in n
            def types_pass(Node* n0, byte* ns) -> void
            {
                Node* n = this.unwrap(n0);
                int k = n.kind;
                int s, c, e;
                byte* full;
                if (k == NodeKind.STRUCT_DEF) { this.reg_struct(n, ns); }
                elif (k == NodeKind.OBJECT_DEF)
                {
                    this.reg_object_type(n, ns);
                    this.reg_object_nested(n, ns);
                }
                elif (k == NodeKind.ENUM_DEF) { this.reg_enum(n, ns); }
                elif (k == NodeKind.UNION_DEF) { this.reg_union(n, ns); }
                elif (k == NodeKind.TYPE_DECLARATION) { this.reg_alias(n, ns); }
                elif (k == NodeKind.NAMESPACE_DEF)
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
                };
                return;
            };

            // Declares every function, method and extern in n
            def decls_pass(Node* n0, byte* ns) -> void
            {
                Node* n = this.unwrap(n0);
                int k = n.kind;
                int s, c, e;
                byte* full;
                if (k == NodeKind.FUNCTION_DEF) { this.declare_function(n, ns); }
                elif (k == NodeKind.VARIABLE_DECLARATION) { this.declare_global(n, ns); }
                elif (k == NodeKind.OBJECT_DEF) { this.declare_object_methods(n, ns); }
                elif (k == NodeKind.EXTERN_BLOCK)
                {
                    c = node_count(n, 0);
                    while (e < c)
                    {
                        this.declare_extern(node_child(n, 0, e), ns);
                        e++;
                    };
                }
                elif (k == NodeKind.EXPORT_BLOCK)
                {
                    c = node_count(n, 0);
                    while (e < c)
                    {
                        this.declare_function(node_child(n, 0, e), ns);
                        e++;
                    };
                }
                elif (k == NodeKind.NAMESPACE_DEF)
                {
                    full = this.join_ns(ns, n.text);
                    this.set_ns(full);
                    int j;
                    while (j < 4)
                    {
                        if (j == 1)
                        {
                            c = this.ns_count(n, 6);
                            e = 0;
                            while (e < c)
                            {
                                if (this.ns_child(n, 6, e).kind == NodeKind.VARIABLE_DECLARATION)
                                {
                                    this.declare_global(this.ns_child(n, 6, e), full);
                                };
                                e++;
                            };
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
                };
                return;
            };

            // ----------------------------------------------------------
            // Function bodies (stage B)
            // ----------------------------------------------------------

            // Marks the current body as not generated. what names the construct.
            def unsup(Node* n, byte* what) -> void
            {
                i64* box;
                if (this.bad) { return; };
                this.bad = true;
                this.bad_what = what;
                if (n != (Node*)0) { this.bad_line = n.line; };
                box = (i64*)nm_get(this.ucounts, what);
                if (box == (i64*)0)
                {
                    box = (i64*)fmalloc((u64)8);
                    this.keep((void*)box);
                    *box = (i64)0;
                    nm_put(this.ucounts, what, (void*)box);
                };
                *box = *box + (i64)1;
                return;
            };

            def push_scope() -> void
            {
                pv_push(this.scopes, (void*)nm_new());
                return;
            };

            def pop_scope() -> void
            {
                nm_free((NameMap*)this.scopes.items[this.scopes.len - 1]);
                this.scopes.len = this.scopes.len - 1;
                return;
            };

            def define_var(byte* name, IRValue* ptr, TypeSpec* ts) -> LVar*
            {
                LVar* v = (LVar*)fmalloc((u64)((sizeof(LVar) + 7) / 8));
                v.ptr = ptr;
                v.ts = ts;
                v.vol = false;
                this.keep((void*)v);
                nm_put((NameMap*)this.scopes.items[this.scopes.len - 1], name, (void*)v);
                return v;
            };

            def find_local(byte* name) -> LVar*
            {
                int i = this.scopes.len - 1;
                void* p;
                while (i >= 0)
                {
                    p = nm_get((NameMap*)this.scopes.items[i], name);
                    if (p != (void*)0) { return (LVar*)p; };
                    i--;
                };
                return (LVar*)0;
            };

            def find_var(byte* name) -> LVar*
            {
                LVar* lv = this.find_local(name);
                if (lv != (LVar*)0) { return lv; };
                return this.find_global_var(name);
            };

            // Global variable visible as name (module.globals, then the namespace resolution)
            def find_global_var(byte* name) -> LVar*
            {
                FXC_SYMENTRY* e = st_lookup_any(this.st, name, this.cur_ns);
                byte* m;
                IRGlobal* gl;
                LVar* v;
                void* p;
                if (e == (FXC_SYMENTRY*)0) { return (LVar*)nm_get(this.gvars, name); };
                if (e.kind_id != SymbolKind.VARIABLE) { return (LVar*)nm_get(this.gvars, name); };
                m = sym_mangled(e);
                gl = this.mod.find_global(m);
                if (gl == (IRGlobal*)0)
                {
                    ffree(m);
                    return (LVar*)0;
                };
                p = nm_get(this.gvars, m);
                if (p != (void*)0)
                {
                    ffree(m);
                    return (LVar*)p;
                };
                v = (LVar*)fmalloc((u64)((sizeof(LVar) + 7) / 8));
                v.ptr = gl.self;
                v.ts = (TypeSpec*)e.ts;
                v.vol = false;
                this.keep((void*)v);
                nm_put(this.gvars, m, (void*)v);
                ffree(m);
                return v;
            };

            // Counts a construct that stopped something other than a body
            def note_unsup(byte* what) -> void
            {
                i64* box = (i64*)nm_get(this.ucounts, what);
                if (box == (i64*)0)
                {
                    box = (i64*)fmalloc((u64)8);
                    this.keep((void*)box);
                    *box = (i64)0;
                    nm_put(this.ucounts, what, (void*)box);
                };
                *box = *box + (i64)1;
                return;
            };

            // Last "__" separated segment of name
            def last_seg(byte* name) -> byte*
            {
                int i;
                int cut;
                while (name[i] != 0)
                {
                    if (name[i] == '_' & name[i + 1] == '_') { cut = i + 2; };
                    i++;
                };
                return name + cut;
            };

            // _vardecl_global duplicate check: same name, or same last segment
            def global_dup(byte* name) -> bool
            {
                int i;
                byte* seg = this.last_seg(name);
                IRGlobal* g;
                IRFunc* fn;
                while (i < this.mod.globals.len)
                {
                    g = (IRGlobal*)this.mod.globals.items[i];
                    if (cstr_eq(g.name, name)) { return true; };
                    if (cstr_eq(this.last_seg(g.name), seg)) { return true; };
                    i++;
                };
                i = 0;
                while (i < this.mod.funcs.len)
                {
                    fn = (IRFunc*)this.mod.funcs.items[i];
                    if (cstr_eq(fn.name, name)) { return true; };
                    if (cstr_eq(this.last_seg(fn.name), seg)) { return true; };
                    i++;
                };
                return false;
            };

            // Initializer text of a global (create_global_initializer for literals),
            // null when the initializer is not handled yet
            def global_init(Node* n, IRType* lt) -> byte*
            {
                Node* ini = n.a;
                int dt;
                i64 v;
                i64 mask;
                int w;
                byte* r;
                bool neg = false;
                if (ini == (Node*)0) { return this.mod.c_null(lt).text; };
                if (ini.kind == NodeKind.NO_INIT) { return g"undef\0"; };
                if (ini.kind == NodeKind.CAST_EXPRESSION & lt.kind == LK.PTR)
                {
                    if (ini.a != (Node*)0)
                    {
                        if (ini.a.kind == NodeKind.ADDRESS_OF & ini.a.a != (Node*)0)
                        {
                            if (ini.a.a.kind == NodeKind.LITERAL & ini.a.a.op == DataType.VOID) { return g"null\0"; };
                        };
                        if (ini.a.kind == NodeKind.IDENTIFIER & ini.a.text != (byte*)0)
                        {
                            FXC_SYMENTRY* se = st_lookup_any(this.st, ini.a.text, this.cur_ns);
                            if (se != (FXC_SYMENTRY*)0)
                            {
                                byte* sm = sym_mangled(se);
                                IRGlobal* sg = this.mod.find_global(sm);
                                ffree(sm);
                                if (sg != (IRGlobal*)0)
                                {
                                    if (sg.init != (byte*)0)
                                    {
                                        if (cstr_eq(sg.init, g"null\0")) { return g"null\0"; };
                                    };
                                };
                            };
                        };
                        if (ini.a.kind == NodeKind.LITERAL & ini.a.ival == (i64)0 & (ini.a.op == DataType.SINT | ini.a.op == DataType.UINT | ini.a.op == DataType.ULONG | ini.a.op == DataType.SLONG))
                        {
                            return g"null\0";
                        };
                    };
                };
                if (ini.kind == NodeKind.UNARY_OP)
                {
                    if (ini.op == Operator.SUB & ini.a != (Node*)0)
                    {
                        if (ini.a.kind == NodeKind.LITERAL)
                        {
                            neg = true;
                            ini = ini.a;
                        };
                    };
                };
                if (ini.kind != NodeKind.LITERAL) { return (byte*)0; };
                dt = ini.op;
                v = ini.ival;
                if (neg)
                {
                    if (dt != DataType.SINT & dt != DataType.FLOAT & dt != DataType.DOUBLE) { return (byte*)0; };
                    v = (i64)0 - v;
                };
                if (dt == DataType.FLOAT | dt == DataType.DOUBLE)
                {
                    if (lt.kind == LK.FLOAT | lt.kind == LK.DOUBLE) { if (neg) { return this.mod.c_fp(lt, (double)0.0 - ini.fval).text; }; return this.mod.c_fp(lt, ini.fval).text; };
                    return (byte*)0;
                };
                if (lt.kind == LK.PTR)
                {
                    if (dt == DataType.SINT & v == (i64)0) { return g"null\0"; };
                    return (byte*)0;
                };
                if (lt.kind != LK.INT)
                {
                    if (dt == DataType.SINT | dt == DataType.BOOL | dt == DataType.UINT | dt == DataType.ULONG) { return (byte*)0; };
                    return this.mod.c_null(lt).text;
                };
                w = lt.width;
                if (dt == DataType.SINT | dt == DataType.BOOL) { return this.mod.c_int(this.t_i64, v).text; };
                if (dt == DataType.UINT | dt == DataType.ULONG | dt == DataType.DATA)
                {
                    if (w < 64)
                    {
                        mask = ((i64)1 << (i64)w) - (i64)1;
                        v = v `& mask;
                        if (v > (((i64)1 << (i64)(w - 1)) - (i64)1)) { v = v - ((i64)1 << (i64)w); };
                    };
                    return this.mod.c_int(this.t_i64, v).text;
                };
                return this.mod.c_null(lt).text;
            };

            // visit_VariableDeclaration at global scope (_vardecl_global)
            def declare_global(Node* n, byte* ns) -> void
            {
                TypeSpec* ts = n.ts;
                IRType* lt;
                IRGlobal* gl;
                byte* m;
                byte* it;
                if (n.text == (byte*)0) { return; };
                if (ts == (TypeSpec*)0) { return; };
                if (ts.base_type == DataType.DICT) { return; };
                if (ts.storage_class == StorageClass.AUTO) { this.note_unsup(g"global auto variable\0"); return; };
                if ((ts.flags `& TS_ARRAY) != 0 & ts.array_size == (Node*)0 & ts.array_dims == (NodeVec*)0)
                {
                    this.note_unsup(g"global array without size\0");
                    return;
                };
                lt = this.lower(ts, true, n.line);
                if (lt == (IRType*)0) { return; };
                m = mangle_namespace_name(ns, n.text);
                if (this.global_dup(m))
                {
                    ffree(m);
                    return;
                };
                it = this.global_init(n, lt);
                if (it == (byte*)0)
                {
                    this.note_unsup(g"global initializer\0");
                    ffree(m);
                    return;
                };
                gl = this.mod.add_global(lt, m, it);
                gl.linkage = this.mod.own(g"internal\0");
                if (nm_get(this.gvars, m) == (void*)0)
                {
                    LVar* gv = (LVar*)fmalloc((u64)((sizeof(LVar) + 7) / 8));
                    gv.ptr = gl.self;
                    gv.ts = ts;
                    gv.vol = false;
                    this.keep((void*)gv);
                    nm_put(this.gvars, m, (void*)gv);
                };
                ffree(m);
                return;
            };

            // TypeSpec that stands for a bare DataType attached to a value
            def lit_spec(int dt) -> TypeSpec*
            {
                TypeSpec* t;
                if (this.lspecs[dt] == (TypeSpec*)0)
                {
                    t = typespec_new();
                    t.base_type = dt;
                    this.keep((void*)t);
                    this.lspecs[dt] = t;
                };
                return this.lspecs[dt];
            };

            // CoercionContext.is_unsigned
            def is_uns(IRValue* v) -> bool
            {
                TypeSpec* s = v.spec;
                if (s == (TypeSpec*)0) { return false; };
                if (s.base_type == DataType.UINT) { return true; };
                if (s.base_type == DataType.BYTE) { return true; };
                if (s.base_type == DataType.DATA) { return (s.flags `& TS_SIGNED) == 0; };
                return false;
            };

            // EndianSwapHandler.get_endianness
            def endian_of(TypeSpec* t) -> int
            {
                if (t == (TypeSpec*)0) { return 1; };
                return t.endianness;
            };

            def with_spec(IRValue* v, TypeSpec* s) -> IRValue*
            {
                if (v != (IRValue*)0) { v.spec = s; };
                return v;
            };

            def int_ty(int w) -> IRType*
            {
                return this.mod.t_int(w);
            };

            def ci32(int v) -> IRValue*
            {
                return this.mod.c_int(this.t_i32, (i64)v);
            };

            // Object declaration with a constructor call (_vardecl_call_constructor)
            def init_ctor(IRValue* alloca, IRType* lt, Node* ini, Node* site) -> void
            {
                int argc = node_count(ini, 0);
                int i;
                IRValue* probe;
                IRValue* v;
                IRValue** args;
                IRFunc* f;
                IRType* ft;
                int j;
                if (argc == 1 & lt.kind == LK.ISTRUCT)
                {
                    probe = this.visit(node_child(ini, 0, 0));
                    if (this.bad) { return; };
                    if (probe != (IRValue*)0)
                    {
                        if (probe.ty.kind == LK.PTR)
                        {
                            if (lt_eq(probe.ty.elem, lt)) { probe = this.mod.load(probe, g"obj_copy_load\0"); };
                        };
                        if (lt_eq(probe.ty, lt))
                        {
                            this.mod.store(probe, alloca);
                            return;
                        };
                    };
                };
                if (lt.kind == LK.ISTRUCT)
                {
                    j = 0;
                    while (j < lt.nitems)
                    {
                        if (lt.items[j].kind == LK.ARRAY)
                        {
                            if (lt.items[j].count > 64)
                            {
                                this.unsup(site, g"constructor on large object\0");
                                return;
                            };
                        };
                        j++;
                    };
                    this.mod.store(this.zero_of(lt), alloca);
                };
                f = this.mod.find_function(ini.text3);
                if (f == (IRFunc*)0)
                {
                    this.unsup(site, g"constructor not declared\0");
                    return;
                };
                ft = f.ftype;
                args = (IRValue**)fmalloc((u64)(8 * (argc + 1)));
                this.keep((void*)args);
                args[0] = alloca;
                i = 0;
                while (i < argc)
                {
                    if (node_child(ini, 0, i).kind == NodeKind.STRING_LITERAL & i + 1 < ft.nitems & this.is_i8_ptr(ft.items[i + 1]))
                    {
                        this.sc.clear();
                        this.sc.put_str(g"ctor_arg\0");
                        this.sc.put_int(i);
                        v = this.local_string_value(node_child(ini, 0, i), this.sc.mem);
                    }
                    else { v = this.visit(node_child(ini, 0, i)); };
                    if (this.bad) { return; };
                    if (v == (IRValue*)0)
                    {
                        this.unsup(site, g"void constructor argument\0");
                        return;
                    };
                    if (i + 1 < ft.nitems) { v = this.convert_arg(v, ft.items[i + 1], i, site); };
                    if (this.bad) { return; };
                    args[i + 1] = v;
                    i++;
                };
                this.mod.call(f.self, args, argc + 1, (byte*)0);
                return;
            };

            def is_i8_ptr(IRType* t) -> bool
            {
                if (t.kind != LK.PTR) { return false; };
                return t.elem.kind == LK.INT & t.elem.width == 8;
            };

            // Bytes of a string literal (with the configured terminator); length in q_len
            def str_bytes(Node* n) -> byte*
            {
                int len = (int)n.ival;
                int i;
                byte* src = n.text;
                byte* buf;
                if (src == (byte*)0) { src = g"\0"; };
                if (len <= 0)
                {
                    while (src[len] != 0) { len++; };
                };
                buf = (byte*)fmalloc((u64)(len + 2));
                this.keep((void*)buf);
                while (i < len)
                {
                    buf[i] = src[i];
                    i++;
                };
                if (this.null_term)
                {
                    if (len == 0)
                    {
                        buf[0] = (byte)0;
                        len = 1;
                    }
                    elif (buf[len - 1] != (byte)0)
                    {
                        buf[len] = (byte)0;
                        len++;
                    };
                };
                this.q_len = len;
                return buf;
            };

            // Stores bytes into a [N x i8]* with unnamed gep and store pairs
            def store_bytes(IRValue* arr, byte* buf, int len) -> void
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
                return;
            };

            def str_init_ok(IRType* lt, Node* ini) -> bool
            {
                if (ini.op == StorageClass.HEAP) { return false; };
                if (this.is_i8_ptr(lt)) { return true; };
                return lt.kind == LK.ARRAY & lt.elem.kind == LK.INT & lt.elem.width == 8;
            };

            // ArrayTypeHandler.initialize_local_string
            def init_local_string(IRValue* alloca, IRType* lt, Node* ini) -> void
            {
                byte* buf = this.str_bytes(ini);
                int len = this.q_len;
                int i;
                IRValue* sa;
                IRValue* sp;
                IRValue* ep;
                if (this.is_i8_ptr(lt))
                {
                    sa = this.mod.alloca_here(this.mod.t_array(this.t_i8, len), g"str_data\0");
                    this.store_bytes(sa, buf, len);
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = this.ci32(0);
                    sp = this.mod.gep(sa, this.mod.ia, 2, false, g"str_ptr\0");
                    this.mod.store(sp, alloca);
                    return;
                };
                if (len > lt.count) { len = lt.count; };
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
                return;
            };

            // create_local_string_for_arg
            def local_string_value(Node* s, byte* hint) -> IRValue*
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
                return this.mod.gep(sa, this.mod.ia, 2, false, this.sc.mem);
            };

            // True when a local array literal is a list of plain scalar expressions
            def simple_array_init(IRType* lt, Node* ini) -> bool
            {
                int i;
                int c = node_count(ini, 0);
                int k;
                if (lt.kind != LK.ARRAY) { return false; };
                if (lt.elem.kind != LK.INT) { return false; };
                while (i < c)
                {
                    k = node_child(ini, 0, i).kind;
                    if (k == NodeKind.STRING_LITERAL | k == NodeKind.ARRAY_LITERAL | k == NodeKind.STRUCT_LITERAL) { return false; };
                    i++;
                };
                return true;
            };

            // ArrayTypeHandler.initialize_local_array for integer element arrays
            def init_local_array(IRValue* alloca, IRType* lt, Node* ini) -> void
            {
                int i;
                int c = node_count(ini, 0);
                IRValue* ev;
                IRValue* ep;
                while (i < c & i < lt.count)
                {
                    ev = this.visit(node_child(ini, 0, i));
                    if (this.bad) { return; };
                    if (ev == (IRValue*)0)
                    {
                        this.unsup(ini, g"void array element\0");
                        return;
                    };
                    if (ev.ty.kind == LK.PTR) { ev = this.mod.load(ev, (byte*)0); };
                    if (ev.ty.kind != LK.INT)
                    {
                        this.unsup(ini, g"array element type\0");
                        return;
                    };
                    if (ev.ty.width < lt.elem.width) { ev = this.mod.cast(g"zext\0", ev, lt.elem, (byte*)0); }
                    elif (ev.ty.width > lt.elem.width) { ev = this.mod.cast(g"trunc\0", ev, lt.elem, (byte*)0); };
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = this.ci32(i);
                    this.sc.clear();
                    this.sc.put_str(g"elem_\0");
                    this.sc.put_int(i);
                    ep = this.mod.gep(alloca, this.mod.ia, 2, false, this.sc.mem);
                    this.mod.store(ev, ep);
                    i++;
                };
                return;
            };

            // Zero fill of a large local array through llvm.memset
            def memset_zero(IRValue* alloca, IRType* lt) -> void
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
                if (lt.elem.kind == LK.INT) { eb = lt.elem.width / 8; };
                cp = this.mod.cast(g"bitcast\0", alloca, i8p, g"memset_ptr\0");
                this.mod.ia[0] = cp;
                this.mod.ia[1] = this.mod.c_int(this.t_i8, (i64)0);
                this.mod.ia[2] = this.mod.c_int(this.t_i64, (i64)lt.count * (i64)eb);
                this.mod.ia[3] = this.mod.c_null(this.t_i1);
                this.mod.call(f.self, this.mod.ia, 4, (byte*)0);
                return;
            };

            // Declares (or finds) an intrinsic or external function by type
            def intrinsic(byte* name, IRType* ft) -> IRFunc*
            {
                IRFunc* f = this.mod.find_function(name);
                if (f == (IRFunc*)0) { f = this.mod.add_function(ft, name); };
                return f;
            };

            // EndianSwapHandler.emit_bswap
            def bswap(IRValue* v) -> IRValue*
            {
                IRFunc* f;
                IRType** ps;
                int w = v.ty.width;
                if (v.ty.kind != LK.INT) { return v; };
                if (w < 16) { return v; };
                if (w % 16 != 0) { return v; };
                this.sc.clear();
                this.sc.put_str(g"llvm.bswap.i\0");
                this.sc.put_int(w);
                ps = (IRType**)fmalloc((u64)2 * (u64)((sizeof(IRType*) + 7) / 8));
                this.keep((void*)ps);
                ps[0] = v.ty;
                f = this.intrinsic(this.sc.mem, this.mod.t_func(v.ty, ps, 1, false));
                this.mod.ia[0] = v;
                return this.mod.call(f.self, this.mod.ia, 1, g"bswapped\0");
            };

            // EndianSwapHandler.maybe_swap(val, target_ptr)
            def maybe_swap(IRValue* v, IRValue* target) -> IRValue*
            {
                IRValue* sw;
                TypeSpec* ns;
                int se, te;
                if (v.ty.kind != LK.INT) { return v; };
                if (v.ty.width < 16) { return v; };
                se = this.endian_of(v.spec);
                te = this.endian_of(target.spec);
                if (se == te) { return v; };
                sw = this.bswap(v);
                if (v.spec != (TypeSpec*)0)
                {
                    ns = typespec_clone(v.spec);
                    ns.endianness = te;
                    this.keep((void*)ns);
                    sw.spec = ns;
                };
                return sw;
            };

            // Widens or narrows an integer to width ty (names are left to the builder)
            def int_resize(IRValue* v, IRType* ty, bool uns) -> IRValue*
            {
                IRValue* r;
                if (v.ty.width == ty.width) { return v; };
                if (v.ty.width < ty.width)
                {
                    if (uns) { r = this.mod.cast(g"zext\0", v, ty, (byte*)0); }
                    else { r = this.mod.cast(g"sext\0", v, ty, (byte*)0); };
                }
                else { r = this.mod.cast(g"trunc\0", v, ty, (byte*)0); };
                r.spec = v.spec;
                return r;
            };

            // CoercionContext.normalize_ints: result in nra and nrb
            def normalize_ints(IRValue* a, IRValue* b, bool uns, bool promote) -> void
            {
                int w;
                IRType* ty;
                this.nra = a;
                this.nrb = b;
                if (a.ty.width == b.ty.width) { return; };
                if (promote)
                {
                    w = a.ty.width;
                    if (b.ty.width > w) { w = b.ty.width; };
                }
                else
                {
                    w = a.ty.width;
                    if (b.ty.width < w) { w = b.ty.width; };
                };
                ty = this.int_ty(w);
                this.nra = this.int_resize(a, ty, uns);
                this.nrb = this.int_resize(b, ty, uns);
                return;
            };

            // _coerce_to_bool
            def to_bool(IRValue* v) -> IRValue*
            {
                IRType* t = v.ty;
                if (t.kind == LK.INT)
                {
                    if (t.width == 1) { return v; };
                    return this.mod.icmp(g"ne\0", v, this.mod.c_int(t, (i64)0), g"tobool\0");
                };
                if (t.kind == LK.PTR) { return this.mod.icmp(g"ne\0", v, this.mod.c_null(t), g"ptrbool\0"); };
                if (t.kind == LK.FLOAT | t.kind == LK.DOUBLE)
                {
                    return this.mod.fcmp(g"one\0", v, this.mod.c_fp(t, 0.0), g"fpbool\0");
                };
                return this.mod.icmp(g"ne\0", v, this.mod.c_null(t), g"tobool\0");
            };

            // ----------------------------------------------------------
            // Conversions
            // ----------------------------------------------------------

            def is_aggregate_ty(IRType* t) -> bool
            {
                return t.kind == LK.STRUCT | t.kind == LK.ISTRUCT;
            };

            // CoercionContext.coerce_return_value
            def coerce_ret(IRValue* v, IRType* expected, Node* site) -> IRValue*
            {
                IRType* src = v.ty;
                IRValue* r;
                if (lt_eq(src, expected)) { return v; };
                if (src.kind == LK.INT & expected.kind == LK.INT)
                {
                    if (src.width < expected.width)
                    {
                        if (this.is_uns(v)) { r = this.mod.cast(g"zext\0", v, expected, (byte*)0); }
                        else { r = this.mod.cast(g"sext\0", v, expected, (byte*)0); };
                    }
                    else { r = this.mod.cast(g"trunc\0", v, expected, (byte*)0); };
                    r.spec = v.spec;
                    return r;
                };
                if ((src.kind == LK.FLOAT | src.kind == LK.DOUBLE) & expected.kind == LK.INT)
                {
                    if (v.spec != (TypeSpec*)0 & this.is_uns(v)) { r = this.mod.cast(g"fptoui\0", v, expected, (byte*)0); }
                    else { r = this.mod.cast(g"fptosi\0", v, expected, (byte*)0); };
                    r.spec = v.spec;
                    return r;
                };
                if (src.kind == LK.INT & (expected.kind == LK.FLOAT | expected.kind == LK.DOUBLE))
                {
                    if (this.is_uns(v)) { r = this.mod.cast(g"uitofp\0", v, expected, (byte*)0); }
                    else { r = this.mod.cast(g"sitofp\0", v, expected, (byte*)0); };
                    r.spec = v.spec;
                    return r;
                };
                if ((src.kind == LK.FLOAT | src.kind == LK.DOUBLE) & (expected.kind == LK.FLOAT | expected.kind == LK.DOUBLE))
                {
                    if (src.kind == LK.FLOAT) { r = this.mod.cast(g"fpext\0", v, expected, (byte*)0); }
                    else { r = this.mod.cast(g"fptrunc\0", v, expected, (byte*)0); };
                    r.spec = v.spec;
                    return r;
                };
                if (src.kind == LK.PTR & expected.kind == LK.PTR)
                {
                    return this.mod.cast(g"bitcast\0", v, expected, (byte*)0);
                };
                if (src.kind == LK.STRUCT & expected.kind == LK.STRUCT)
                {
                    this.unsup(site, g"return struct mismatch\0");
                    return v;
                };
                if (src.kind == LK.ARRAY & expected.kind == LK.ARRAY)
                {
                    this.unsup(site, g"return array conversion\0");
                    return v;
                };
                if (src.kind == LK.PTR)
                {
                    if (lt_eq(src.elem, expected)) { return this.mod.load(v, g"array_decay\0"); };
                };
                this.unsup(site, g"return type mismatch\0");
                return v;
            };

            // VariableTypeHandler.store_with_type_conversion
            def store_conv(IRValue* alloca, IRType* llvm_type, IRValue* iv, Node* ini, Node* site) -> void
            {
                IRValue* v = iv;
                IRType* vt = v.ty;
                int ik = ini.kind;
                if (ik == NodeKind.CAST_EXPRESSION & vt.kind == LK.PTR & llvm_type.kind == LK.ARRAY)
                {
                    this.unsup(site, g"cast to array initializer\0");
                    return;
                };
                if (!lt_eq(vt, llvm_type))
                {
                    if (vt.kind == LK.PTR & vt.elem.kind == LK.ARRAY & llvm_type.kind == LK.ARRAY)
                    {
                        this.unsup(site, g"array widening initializer\0");
                        return;
                    };
                    if (vt.kind == LK.PTR & vt.elem.kind == LK.ARRAY & llvm_type.kind == LK.INT)
                    {
                        this.unsup(site, g"array pack initializer\0");
                        return;
                    };
                    if (vt.kind == LK.PTR & this.is_aggregate_ty(llvm_type) & lt_eq(vt.elem, llvm_type))
                    {
                        v = this.mod.load(v, g"struct_deref\0");
                    }
                    elif (vt.kind == LK.PTR & llvm_type.kind == LK.INT)
                    {
                        v = this.mod.cast(g"ptrtoint\0", v, llvm_type, g"ptr_to_int\0");
                    }
                    elif (vt.kind == LK.INT & llvm_type.kind == LK.PTR)
                    {
                        v = this.mod.cast(g"inttoptr\0", v, llvm_type, g"int_to_ptr\0");
                    }
                    elif (vt.kind == LK.PTR & llvm_type.kind == LK.PTR)
                    {
                        if (!lt_eq(llvm_type.elem, vt.elem)) { v = this.mod.cast(g"bitcast\0", v, llvm_type, (byte*)0); }
                        elif (vt.elem.kind == LK.ARRAY)
                        {
                            this.unsup(site, g"array pointer pack initializer\0");
                            return;
                        };
                    }
                    elif (vt.kind == LK.INT & llvm_type.kind == LK.INT)
                    {
                        if (vt.width > llvm_type.width) { v = this.mod.cast(g"trunc\0", v, llvm_type, (byte*)0); }
                        elif (vt.width < llvm_type.width)
                        {
                            if (this.is_uns(v)) { v = this.mod.cast(g"zext\0", v, llvm_type, (byte*)0); }
                            else { v = this.mod.cast(g"sext\0", v, llvm_type, (byte*)0); };
                        };
                    }
                    elif (vt.kind == LK.INT & (llvm_type.kind == LK.FLOAT | llvm_type.kind == LK.DOUBLE))
                    {
                        v = this.mod.cast(g"sitofp\0", v, llvm_type, (byte*)0);
                    }
                    elif ((vt.kind == LK.FLOAT | vt.kind == LK.DOUBLE) & llvm_type.kind == LK.INT)
                    {
                        v = this.mod.cast(g"fptosi\0", v, llvm_type, (byte*)0);
                    }
                    elif (vt.kind == LK.FLOAT & llvm_type.kind == LK.DOUBLE)
                    {
                        v = this.mod.cast(g"fpext\0", v, llvm_type, g"float_to_double\0");
                    }
                    elif (vt.kind == LK.DOUBLE & llvm_type.kind == LK.FLOAT)
                    {
                        v = this.mod.cast(g"fptrunc\0", v, llvm_type, g"double_to_float\0");
                    };
                };
                if (v.spec != (TypeSpec*)0)
                {
                    if (alloca.spec == (TypeSpec*)0) { alloca.spec = v.spec; };
                };
                v = this.maybe_swap(v, alloca);
                this.mod.store(v, alloca);
                return;
            };

            // AssignmentTypeHandler.convert_value_for_assignment
            def convert_assign(IRValue* v, IRType* target) -> IRValue*
            {
                IRType* vt = v.ty;
                IRValue* r;
                if (lt_eq(vt, target)) { return v; };
                if (vt.kind == LK.PTR & target.kind == LK.PTR)
                {
                    if (vt.elem.kind == LK.PTR & lt_eq(vt.elem, target))
                    {
                        return this.mod.load(v, g"ptr_val_loaded\0");
                    };
                    if (lt_eq(vt.elem, target.elem)) { return this.mod.cast(g"bitcast\0", v, target, g"ptr_compat\0"); };
                    if (vt.elem.kind == LK.INT & vt.elem.width == 8 & target.elem.kind == LK.INT & target.elem.width == 8)
                    {
                        return this.mod.cast(g"bitcast\0", v, target, g"i8ptr_compat\0");
                    };
                };
                if (vt.kind == LK.PTR & vt.elem.kind == LK.ARRAY)
                {
                    if (target.kind == LK.PTR)
                    {
                        if (lt_eq(target.elem, vt.elem)) { return v; };
                        if (lt_eq(target.elem, vt.elem.elem))
                        {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            return this.mod.gep(v, this.mod.ia, 2, false, g"array_to_elem_ptr\0");
                        };
                        if (target.elem.kind == LK.ARRAY)
                        {
                            if (target.elem.count == vt.elem.count)
                            {
                                return this.mod.cast(g"bitcast\0", v, target, g"array_ptr_bitcast\0");
                            };
                        };
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = this.ci32(0);
                        return this.mod.gep(v, this.mod.ia, 2, false, g"array_to_ptr\0");
                    };
                    if (lt_eq(target, vt.elem)) { return this.mod.load(v, g"array_load\0"); };
                };
                if (vt.kind == LK.PTR & target.kind != LK.PTR)
                {
                    if (lt_eq(vt.elem, target)) { return this.mod.load(v, g"struct_copy_load\0"); };
                };
                if (vt.kind == LK.PTR & vt.elem.kind == LK.INT & vt.elem.width == 8 & target.kind == LK.PTR)
                {
                    return this.mod.cast(g"bitcast\0", v, target, g"void_ptr_to_typed\0");
                };
                if (vt.kind == LK.INT & target.kind == LK.INT)
                {
                    if (vt.width != target.width)
                    {
                        return this.int_resize(v, target, this.is_uns(v));
                    };
                };
                if (vt.kind == LK.FLOAT & target.kind == LK.DOUBLE)
                {
                    return this.mod.cast(g"fpext\0", v, target, g"f32_to_f64\0");
                };
                if (vt.kind == LK.DOUBLE & target.kind == LK.FLOAT)
                {
                    return this.mod.cast(g"fptrunc\0", v, target, g"f64_to_f32\0");
                };
                return v;
            };

            // FunctionTypeHandler.convert_argument_to_parameter_type
            def convert_arg(IRValue* v, IRType* expected, int idx, Node* site) -> IRValue*
            {
                IRType* vt = v.ty;
                IRValue* d;
                if (lt_eq(vt, expected)) { return v; };
                this.sc.clear();
                if (expected.kind == LK.PTR & expected.elem.kind == LK.INT & expected.elem.width == 8)
                {
                    if (vt.kind == LK.PTR)
                    {
                        if (vt.elem.kind == LK.ARRAY)
                        {
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
                            return this.mod.cast(g"bitcast\0", d, expected, this.sc.mem);
                        };
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(idx);
                        this.sc.put_str(g"_to_void_ptr\0");
                        return this.mod.cast(g"bitcast\0", v, expected, this.sc.mem);
                    };
                };
                if (vt.kind == LK.PTR & vt.elem.kind == LK.INT & vt.elem.width == 8 & expected.kind == LK.PTR)
                {
                    this.sc.put_str(g"arg\0");
                    this.sc.put_int(idx);
                    if (expected.elem.kind == LK.ARRAY) { this.sc.put_str(g"_to_array_ptr\0"); }
                    else { this.sc.put_str(g"_from_void_ptr\0"); };
                    return this.mod.cast(g"bitcast\0", v, expected, this.sc.mem);
                };
                if (vt.kind == LK.PTR & vt.elem.kind == LK.ARRAY & expected.kind == LK.PTR)
                {
                    if (lt_eq(vt.elem.elem, expected.elem))
                    {
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(idx);
                        this.sc.put_str(g"_decay\0");
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = this.ci32(0);
                        return this.mod.gep(v, this.mod.ia, 2, false, this.sc.mem);
                    };
                };
                if (vt.kind == LK.INT & expected.kind == LK.INT)
                {
                    if (vt.width != expected.width) { return this.int_resize(v, expected, this.is_uns(v)); };
                };
                if (vt.kind == LK.FLOAT & expected.kind == LK.DOUBLE)
                {
                    this.sc.put_str(g"arg\0");
                    this.sc.put_int(idx);
                    this.sc.put_str(g"_float_to_double\0");
                    return this.mod.cast(g"fpext\0", v, expected, this.sc.mem);
                };
                if (vt.kind == LK.DOUBLE & expected.kind == LK.FLOAT)
                {
                    this.sc.put_str(g"arg\0");
                    this.sc.put_int(idx);
                    this.sc.put_str(g"_double_to_float\0");
                    return this.mod.cast(g"fptrunc\0", v, expected, this.sc.mem);
                };
                if (vt.kind == LK.PTR & this.is_aggregate_ty(expected))
                {
                    if (lt_eq(vt.elem, expected))
                    {
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(idx);
                        this.sc.put_str(g"_load\0");
                        return this.mod.load(v, this.sc.mem);
                    };
                };
                this.unsup(site, g"argument type mismatch\0");
                return v;
            };

            // ----------------------------------------------------------
            // Expressions
            // ----------------------------------------------------------

            def x_literal(Node* n) -> IRValue*
            {
                int dt = n.op;
                i64 v = n.ival;
                int w;
                IRValue* r;
                if (dt == DataType.SINT | dt == DataType.UINT)
                {
                    // Source text without a sign that wrapped negative exceeded INT64_MAX
                    if (v < (i64)0 & n.text != (byte*)0)
                    {
                        if (n.text[0] != '-')
                        {
                            r = this.mod.c_u64(this.t_i64, (u64)v);
                            r.spec = this.lit_spec(dt);
                            return r;
                        };
                    };
                    w = 32;
                    if (dt == DataType.SINT)
                    {
                        if (v < (i64)(0 - 2147483647 - 1) | v > (i64)2147483647) { w = 64; };
                    }
                    else
                    {
                        if (v >= (i64)0)
                        {
                            if (v > (i64)4294967295) { w = 64; };
                        }
                        else
                        {
                            if (v < (i64)0 - (i64)4294967296) { w = 64; };
                        };
                        if (w == 32 & v > (i64)2147483647) { v = v - (i64)4294967296; };
                    };
                    r = this.mod.c_int(this.int_ty(w), v);
                    r.spec = this.lit_spec(dt);
                    return r;
                };
                if (dt == DataType.SLONG | dt == DataType.ULONG)
                {
                    if (dt == DataType.ULONG & v < (i64)0) { r = this.mod.c_u64(this.t_i64, (u64)v); }
                    else { r = this.mod.c_int(this.t_i64, v); };
                    r.spec = this.lit_spec(dt);
                    return r;
                };
                if (dt == DataType.FLOAT) { return this.mod.c_fp(this.t_float, n.fval); };
                if (dt == DataType.DOUBLE) { return this.mod.c_fp(this.t_double, n.fval); };
                if (dt == DataType.BOOL) { return this.mod.c_int(this.t_i1, v); };
                if (dt == DataType.CHAR) { return this.mod.c_int(this.t_i8, v); };
                if (dt == DataType.BYTE) { return this.mod.c_int(this.int_ty(this.byte_width), v); };
                if (dt == DataType.VOID) { return this.mod.c_null(this.t_i1); };
                this.unsup(n, g"literal type\0");
                return (IRValue*)0;
            };

            // visit_Identifier for a local variable. Mirrors _try_expr_method and the
            // load rules.
            def try_expr_method(IRValue* ptr) -> IRValue*
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
                if (this.in_member) { return (IRValue*)0; };
                if (ptr.ty.kind != LK.PTR) { return (IRValue*)0; };
                pe = ptr.ty.elem;
                if (pe.kind == LK.PTR & pe.elem.kind == LK.ISTRUCT)
                {
                    st_ty = pe.elem;
                    this_ptr = this.mod.load(ptr, g"obj_this\0");
                }
                elif (pe.kind == LK.ISTRUCT)
                {
                    st_ty = pe;
                    this_ptr = ptr;
                }
                else { return (IRValue*)0; };
                if (st_ty.name == (byte*)0) { return (IRValue*)0; };
                // The base resolves "<namespace>__<Type>.__expr" through its overload table,
                // which never holds namespaced methods under that key, so no promotion happens
                if (this.has_ns_sep(st_ty.name)) { return (IRValue*)0; };
                key = join3(st_ty.name, g".__expr\0", g"\0");
                list = st_overloads_of(this.st, key);
                ffree(key);
                if (list == (PtrVec*)0) { return (IRValue*)0; };
                o = (Overload*)0;
                oi = 0;
                while (oi < list.len)
                {
                    oc = (Overload*)list.items[oi];
                    if (oc.nparams == 0)
                    {
                        o = oc;
                        break;
                    };
                    oi++;
                };
                if (o == (Overload*)0) { return (IRValue*)0; };
                f = this.mod.find_function(o.mangled);
                if (f == (IRFunc*)0) { return (IRValue*)0; };
                this.sc.clear();
                this.sc.put_str(st_ty.name);
                this.sc.put_str(g"_expr\0");
                this.mod.ia[0] = this_ptr;
                r = this.mod.call(f.self, this.mod.ia, 1, this.sc.mem);
                r.flags = r.flags `| VF_FROM_EXPR;
                return r;
            };

            // True when name contains a double underscore namespace separator
            def has_ns_sep(byte* s) -> bool
            {
                int i;
                while (s[i] != 0)
                {
                    if (s[i] == '_' & s[i + 1] == '_') { return true; };
                    i++;
                };
                return false;
            };

            def x_ident(Node* n) -> IRValue*
            {
                LVar* lv = this.find_var(n.text);
                IRValue* ptr;
                IRValue* r;
                IRValue* e;
                TypeSpec* ts;
                if (lv == (LVar*)0)
                {
                    this.unsup(n, g"identifier not local\0");
                    return (IRValue*)0;
                };
                ptr = lv.ptr;
                ts = lv.ts;
                if (cstr_eq(n.text, g"this\0")) { return ptr; };
                e = this.try_expr_method(ptr);
                if (e != (IRValue*)0) { return e; };
                if (ptr.ty.kind == LK.PTR)
                {
                    if (ptr.ty.elem.kind == LK.ARRAY | ptr.ty.elem.kind == LK.STRUCT) { return ptr; };
                };
                if (ts != (TypeSpec*)0)
                {
                    if (ts.array_size != (Node*)0) { return ptr; };
                };
                if (ptr.spec != (TypeSpec*)0)
                {
                    if (ptr.spec.array_size != (Node*)0) { return ptr; };
                };
                if (ptr.ty.kind != LK.PTR) { return ptr; };
                r = this.mod.load(ptr, n.text);
                r.spec = ptr.spec;
                if (r.spec == (TypeSpec*)0) { r.spec = ts; };
                r.flags = ptr.flags `& VF_TYPEFUNC_STR;
                return r;
            };

            def int_pred(int op, bool uns) -> byte*
            {
                if (op == Operator.EQUAL) { return g"eq\0"; };
                if (op == Operator.NOT_EQUAL) { return g"ne\0"; };
                if (op == Operator.LESS_THAN) { if (uns) { return g"ult\0"; }; return g"slt\0"; };
                if (op == Operator.LESS_EQUAL) { if (uns) { return g"ule\0"; }; return g"sle\0"; };
                if (op == Operator.GREATER_THAN) { if (uns) { return g"ugt\0"; }; return g"sgt\0"; };
                if (uns) { return g"uge\0"; };
                return g"sge\0";
            };

            def fp_pred(int op) -> byte*
            {
                if (op == Operator.EQUAL) { return g"oeq\0"; };
                if (op == Operator.NOT_EQUAL) { return g"one\0"; };
                if (op == Operator.LESS_THAN) { return g"olt\0"; };
                if (op == Operator.LESS_EQUAL) { return g"ole\0"; };
                if (op == Operator.GREATER_THAN) { return g"ogt\0"; };
                return g"oge\0";
            };

            // True when a user defined operator__<op> overload is registered
            def has_op_overload(int op) -> bool
            {
                byte* sym = operator_text(op);
                bool r;
                this.sc.clear();
                this.sc.put_str(g"operator__\0");
                mangle_builtin_op(@this.sc, sym);
                return st_overloads_of(this.st, this.sc.mem) != (PtrVec*)0;
            };

            def x_binary(Node* n) -> IRValue*
            {
                int op = n.op;
                IRValue* lhs;
                IRValue* rhs;
                IRValue* r;
                bool uns, is_cmp, might_ptr, lp, rp, li, ri;
                bool lzero, rzero;
                IRType* pe;
                if (op == Operator.ASSIGN)
                {
                    this.unsup(n, g"binary assign\0");
                    return (IRValue*)0;
                };
                if (this.has_op_overload(op))
                {
                    this.unsup(n, g"operator overload\0");
                    return (IRValue*)0;
                };
                lhs = this.visit(n.a);
                if (this.bad) { return (IRValue*)0; };
                rhs = this.visit(n.b);
                if (this.bad) { return (IRValue*)0; };
                if (lhs == (IRValue*)0 | rhs == (IRValue*)0)
                {
                    this.unsup(n, g"binary void operand\0");
                    return (IRValue*)0;
                };
                lp = lhs.ty.kind == LK.PTR;
                rp = rhs.ty.kind == LK.PTR;
                li = lhs.ty.kind == LK.INT;
                ri = rhs.ty.kind == LK.INT;
                might_ptr = false;
                if (op == Operator.ADD | op == Operator.SUB)
                {
                    if (lp)
                    {
                        if (lhs.ty.elem.kind == LK.PTR) { might_ptr = true; };
                    };
                    if (rp)
                    {
                        if (rhs.ty.elem.kind == LK.PTR) { might_ptr = true; };
                    };
                    if (lp & ri) { might_ptr = true; };
                    if (rp & li) { might_ptr = true; };
                };
                is_cmp = op == Operator.EQUAL | op == Operator.NOT_EQUAL | op == Operator.LESS_THAN |
                         op == Operator.GREATER_THAN | op == Operator.LESS_EQUAL | op == Operator.GREATER_EQUAL;
                rzero = rhs.is_const & ri & cstr_eq(rhs.text, g"0\0");
                lzero = lhs.is_const & li & cstr_eq(lhs.text, g"0\0");
                if (is_cmp & lp & rzero) { rhs = this.mod.c_null(lhs.ty); }
                elif (is_cmp & rp & lzero) { lhs = this.mod.c_null(rhs.ty); }
                elif (is_cmp & lp & rp) { r = lhs; }
                elif (!might_ptr)
                {
                    if (lhs.ty.kind == LK.PTR)
                    {
                        pe = lhs.ty.elem;
                        if (pe.kind != LK.ARRAY & pe.kind != LK.STRUCT & pe.kind != LK.ISTRUCT &
                            (lhs.flags `& (VF_FROM_EXPR `| VF_TYPEFUNC_STR)) == 0)
                        {
                            lhs = this.mod.load(lhs, g"auto_deref_lhs\0");
                        };
                    };
                    if (rhs.ty.kind == LK.PTR)
                    {
                        pe = rhs.ty.elem;
                        if (pe.kind != LK.ARRAY & pe.kind != LK.STRUCT & pe.kind != LK.ISTRUCT &
                            (rhs.flags `& (VF_FROM_EXPR `| VF_TYPEFUNC_STR)) == 0)
                        {
                            rhs = this.mod.load(rhs, g"auto_deref_rhs\0");
                        };
                    };
                }
                else
                {
                    if (lp)
                    {
                        if (lhs.ty.elem.kind == LK.PTR)
                        {
                            if (lhs.ty.elem.elem.kind == LK.INT & !ri)
                            {
                                lhs = this.mod.load(lhs, g"deref_ptr_for_arithmetic\0");
                            };
                        };
                    };
                    if (rp)
                    {
                        if (rhs.ty.elem.kind == LK.PTR)
                        {
                            if (rhs.ty.elem.elem.kind == LK.INT & !li)
                            {
                                rhs = this.mod.load(rhs, g"deref_ptr_for_arithmetic\0");
                            };
                        };
                    };
                };
                if (lhs.ty.kind == LK.INT & lhs.ty.width >= 16)
                {
                    if (this.endian_of(lhs.spec) == 0) { lhs = this.bswap(lhs); };
                };
                if (rhs.ty.kind == LK.INT & rhs.ty.width >= 16)
                {
                    if (this.endian_of(rhs.spec) == 0) { rhs = this.bswap(rhs); };
                };
                if (op == Operator.ADD | op == Operator.SUB)
                {
                    if (lhs.ty.kind == LK.ARRAY | rhs.ty.kind == LK.ARRAY |
                        (lhs.ty.kind == LK.PTR & lhs.ty.elem.kind == LK.ARRAY & rhs.ty.kind == LK.PTR & rhs.ty.elem.kind == LK.ARRAY))
                    {
                        this.unsup(n, g"array concatenation\0");
                        return (IRValue*)0;
                    };
                };
                if (op == Operator.ADD)
                {
                    if (((lhs.flags `| rhs.flags) `& (VF_FROM_EXPR `| VF_TYPEFUNC_STR)) != 0)
                    {
                        this.unsup(n, g"string concatenation\0");
                        return (IRValue*)0;
                    };
                };
                lp = lhs.ty.kind == LK.PTR;
                rp = rhs.ty.kind == LK.PTR;
                li = lhs.ty.kind == LK.INT;
                ri = rhs.ty.kind == LK.INT;
                if (op == Operator.ADD | op == Operator.SUB)
                {
                    if (lp & ri)
                    {
                        IRValue* off = rhs;
                        IRValue* base = lhs;
                        if (op == Operator.SUB)
                        {
                            off = this.mod.binop(g"sub\0", this.mod.c_int(rhs.ty, (i64)0), rhs, (byte*)0);
                        };
                        if (lhs.ty.elem.kind == LK.ARRAY)
                        {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            base = this.mod.gep(lhs, this.mod.ia, 2, false, g"arr_base\0");
                        };
                        r = this.mod.gep_ptr(base, off, false, (byte*)0);
                        r.spec = lhs.spec;
                        return r;
                    };
                    if (rp & li & op == Operator.ADD)
                    {
                        IRValue* base2 = rhs;
                        if (rhs.ty.elem.kind == LK.ARRAY)
                        {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            base2 = this.mod.gep(rhs, this.mod.ia, 2, false, g"arr_base\0");
                        };
                        r = this.mod.gep_ptr(base2, lhs, false, (byte*)0);
                        r.spec = rhs.spec;
                        return r;
                    };
                    if (lp & rp)
                    {
                        IRValue* pa = this.mod.cast(g"ptrtoint\0", lhs, this.t_i64, (byte*)0);
                        IRValue* pb = this.mod.cast(g"ptrtoint\0", rhs, this.t_i64, (byte*)0);
                        return this.mod.binop(g"sub\0", pa, pb, (byte*)0);
                    };
                };
                if (op == Operator.ADD | op == Operator.SUB | op == Operator.MUL | op == Operator.DIV |
                    op == Operator.MOD | op == Operator.POWER)
                {
                    if (lhs.ty.kind == LK.FLOAT & rhs.ty.kind == LK.DOUBLE)
                    {
                        lhs = this.mod.cast(g"fpext\0", lhs, this.t_double, g"float_to_double_lhs\0");
                    }
                    elif (lhs.ty.kind == LK.DOUBLE & rhs.ty.kind == LK.FLOAT)
                    {
                        rhs = this.mod.cast(g"fpext\0", rhs, this.t_double, g"float_to_double_rhs\0");
                    };
                    if (lhs.ty.kind == LK.FLOAT | lhs.ty.kind == LK.DOUBLE)
                    {
                        if (op == Operator.POWER)
                        {
                            this.unsup(n, g"float power\0");
                            return (IRValue*)0;
                        };
                        if (op == Operator.ADD) { return this.mod.binop(g"fadd\0", lhs, rhs, (byte*)0); };
                        if (op == Operator.SUB) { return this.mod.binop(g"fsub\0", lhs, rhs, (byte*)0); };
                        if (op == Operator.MUL) { return this.mod.binop(g"fmul\0", lhs, rhs, (byte*)0); };
                        if (op == Operator.DIV) { return this.mod.binop(g"fdiv\0", lhs, rhs, (byte*)0); };
                        return this.mod.binop(g"frem\0", lhs, rhs, (byte*)0);
                    };
                    uns = this.is_uns(lhs) | this.is_uns(rhs);
                    if (lhs.ty.kind == LK.INT & rhs.ty.kind == LK.INT)
                    {
                        if (lhs.ty.width != rhs.ty.width)
                        {
                            this.normalize_ints(lhs, rhs, uns, true);
                            lhs = this.nra;
                            rhs = this.nrb;
                        };
                    };
                    if (lhs.ty.kind != LK.INT | rhs.ty.kind != LK.INT)
                    {
                        this.unsup(n, g"arithmetic operand types\0");
                        return (IRValue*)0;
                    };
                    if (op == Operator.POWER)
                    {
                        this.unsup(n, g"integer power\0");
                        return (IRValue*)0;
                    };
                    if (op == Operator.ADD) { r = this.mod.binop(g"add\0", lhs, rhs, (byte*)0); }
                    elif (op == Operator.SUB) { r = this.mod.binop(g"sub\0", lhs, rhs, (byte*)0); }
                    elif (op == Operator.MUL) { r = this.mod.binop(g"mul\0", lhs, rhs, (byte*)0); }
                    elif (op == Operator.DIV)
                    {
                        if (uns) { r = this.mod.binop(g"udiv\0", lhs, rhs, (byte*)0); }
                        else { r = this.mod.binop(g"sdiv\0", lhs, rhs, (byte*)0); };
                    }
                    else
                    {
                        if (uns) { r = this.mod.binop(g"urem\0", lhs, rhs, (byte*)0); }
                        else { r = this.mod.binop(g"srem\0", lhs, rhs, (byte*)0); };
                    };
                    if (uns) { r.spec = this.lit_spec(DataType.UINT); }
                    else { r.spec = this.lit_spec(DataType.SINT); };
                    return r;
                };
                if (is_cmp)
                {
                    if ((lhs.ty.kind == LK.FLOAT | lhs.ty.kind == LK.DOUBLE) & (rhs.ty.kind == LK.FLOAT | rhs.ty.kind == LK.DOUBLE))
                    {
                        if (lhs.ty.kind == LK.FLOAT & rhs.ty.kind == LK.DOUBLE)
                        {
                            lhs = this.mod.cast(g"fpext\0", lhs, this.t_double, g"float_to_double_lhs\0");
                        }
                        elif (lhs.ty.kind == LK.DOUBLE & rhs.ty.kind == LK.FLOAT)
                        {
                            rhs = this.mod.cast(g"fpext\0", rhs, this.t_double, g"float_to_double_rhs\0");
                        };
                        return this.mod.fcmp(this.fp_pred(op), lhs, rhs, (byte*)0);
                    };
                    if (lp | rp)
                    {
                        if (lp) { lhs = this.mod.cast(g"ptrtoint\0", lhs, this.t_i64, (byte*)0); };
                        if (rp) { rhs = this.mod.cast(g"ptrtoint\0", rhs, this.t_i64, (byte*)0); };
                        return this.mod.icmp(this.int_pred(op, true), lhs, rhs, (byte*)0);
                    };
                    if (lhs.ty.kind != LK.INT | rhs.ty.kind != LK.INT)
                    {
                        this.unsup(n, g"comparison operand types\0");
                        return (IRValue*)0;
                    };
                    uns = this.is_uns(lhs) | this.is_uns(rhs);
                    if (lhs.ty.width != rhs.ty.width)
                    {
                        this.normalize_ints(lhs, rhs, uns, true);
                        lhs = this.nra;
                        rhs = this.nrb;
                    };
                    return this.mod.icmp(this.int_pred(op, uns), lhs, rhs, (byte*)0);
                };
                if (op == Operator.BITAND | op == Operator.BITOR | op == Operator.BITXOR)
                {
                    if (lhs.ty.kind != LK.INT | rhs.ty.kind != LK.INT)
                    {
                        this.unsup(n, g"bitwise operand types\0");
                        return (IRValue*)0;
                    };
                    this.normalize_ints(lhs, rhs, true, true);
                    lhs = this.nra;
                    rhs = this.nrb;
                    if (op == Operator.BITAND) { r = this.mod.binop(g"and\0", lhs, rhs, (byte*)0); }
                    elif (op == Operator.BITOR) { r = this.mod.binop(g"or\0", lhs, rhs, (byte*)0); }
                    else { r = this.mod.binop(g"xor\0", lhs, rhs, (byte*)0); };
                    if (this.is_uns(lhs) | this.is_uns(rhs)) { r.spec = this.lit_spec(DataType.UINT); }
                    else { r.spec = this.lit_spec(DataType.SINT); };
                    return r;
                };
                if (op == Operator.AND | op == Operator.OR | op == Operator.XOR)
                {
                    if (lhs.ty.kind == LK.INT & rhs.ty.kind == LK.INT)
                    {
                        if (lhs.ty.width != rhs.ty.width)
                        {
                            this.normalize_ints(lhs, rhs, true, true);
                            lhs = this.nra;
                            rhs = this.nrb;
                        };
                    };
                    if (op == Operator.AND) { r = this.mod.binop(g"and\0", lhs, rhs, (byte*)0); }
                    elif (op == Operator.OR) { r = this.mod.binop(g"or\0", lhs, rhs, (byte*)0); }
                    else { r = this.mod.binop(g"xor\0", lhs, rhs, (byte*)0); };
                    if (this.is_uns(lhs) | this.is_uns(rhs)) { r.spec = this.lit_spec(DataType.UINT); }
                    else { r.spec = this.lit_spec(DataType.SINT); };
                    return r;
                };
                if (op == Operator.BITSHIFT_LEFT | op == Operator.BITSHIFT_RIGHT)
                {
                    if (lhs.ty.kind != LK.INT | rhs.ty.kind != LK.INT)
                    {
                        this.unsup(n, g"shift operand types\0");
                        return (IRValue*)0;
                    };
                    if (lhs.ty.width != rhs.ty.width)
                    {
                        if (rhs.ty.width < lhs.ty.width) { rhs = this.mod.cast(g"zext\0", rhs, lhs.ty, (byte*)0); }
                        else { rhs = this.mod.cast(g"trunc\0", rhs, lhs.ty, (byte*)0); };
                    };
                    if (op == Operator.BITSHIFT_LEFT) { r = this.mod.binop(g"shl\0", lhs, rhs, (byte*)0); }
                    elif (this.is_uns(lhs) | lhs.spec == (TypeSpec*)0) { r = this.mod.binop(g"lshr\0", lhs, rhs, (byte*)0); }
                    else { r = this.mod.binop(g"ashr\0", lhs, rhs, (byte*)0); };
                    if (this.is_uns(lhs)) { r.spec = this.lit_spec(DataType.UINT); }
                    else { r.spec = this.lit_spec(DataType.SINT); };
                    return r;
                };
                if (op == Operator.NOR | op == Operator.NAND | op == Operator.BITNAND | op == Operator.BITNOR | op == Operator.BITXNOR)
                {
                    if (op == Operator.NOR | op == Operator.BITNOR) { r = this.mod.binop(g"or\0", lhs, rhs, (byte*)0); }
                    elif (op == Operator.NAND | op == Operator.BITNAND) { r = this.mod.binop(g"and\0", lhs, rhs, (byte*)0); }
                    else { r = this.mod.binop(g"xor\0", lhs, rhs, (byte*)0); };
                    r = this.mod.binop(g"xor\0", r, this.mod.c_int(r.ty, (i64)(0 - 1)), (byte*)0);
                    if (op != Operator.NOR & op != Operator.NAND)
                    {
                        if (this.is_uns(lhs) | this.is_uns(rhs)) { r.spec = this.lit_spec(DataType.UINT); }
                        else { r.spec = this.lit_spec(DataType.SINT); };
                    };
                    return r;
                };
                this.unsup(n, g"binary operator\0");
                return (IRValue*)0;
            };

            // ----------------------------------------------------------
            // Calls
            // ----------------------------------------------------------

            def x_call(Node* n) -> IRValue*
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
                if (n.text3 == (byte*)0)
                {
                    this.unsup(n, g"call target not resolved\0");
                    return (IRValue*)0;
                };
                f = this.mod.find_function(n.text3);
                if (f == (IRFunc*)0 & n.text != (byte*)0)
                {
                    // Extern prototypes and no-mangle functions carry their plain symbol name
                    f = this.mod.find_function(n.text);
                };
                if (f == (IRFunc*)0)
                {
                    this.unsup(n, g"call target not declared\0");
                    return (IRValue*)0;
                };
                ft = f.ftype;
                total = argc;
                if (ft.nitems > total & !ft.vararg) { total = ft.nitems; };
                args = (IRValue**)fmalloc((u64)(total + 1) * (u64)((sizeof(IRValue*) + 7) / 8));
                this.keep((void*)args);
                i = 0;
                while (i < argc)
                {
                    an = node_child(n, 0, i);
                    if (an.kind == NodeKind.IDENTIFIER)
                    {
                        if (this.local_flag(an.text, TS_LOCAL))
                        {
                            this.unsup(n, g"local variable leaves scope\0");
                            return (IRValue*)0;
                        };
                    };
                    v = this.visit(an);
                    if (this.bad) { return (IRValue*)0; };
                    if (v == (IRValue*)0)
                    {
                        this.unsup(n, g"void call argument\0");
                        return (IRValue*)0;
                    };
                    args[i] = v;
                    i++;
                };
                i = argc;
                while (i < total)
                {
                    dn = this.default_of(f, n, i);
                    if (dn == (Node*)0)
                    {
                        this.unsup(n, g"missing call argument\0");
                        return (IRValue*)0;
                    };
                    v = this.visit(dn);
                    if (this.bad) { return (IRValue*)0; };
                    args[i] = v;
                    i++;
                };
                i = 0;
                while (i < total & i < ft.nitems)
                {
                    args[i] = this.convert_arg(args[i], ft.items[i], i, n);
                    if (this.bad) { return (IRValue*)0; };
                    i++;
                };
                // Base compiler's pointer-param overload shortcut names every call
                // with no arguments op_overload_result, unless the call spells the mangled symbol
                if (argc == 0 & !this.spells_mangled(n.text)) { r = this.mod.call_ex(f.self, args, total, g"op_overload_result\0", f.cconv, this.fn == f); }
                else { r = this.mod.call_ex(f.self, args, total, (byte*)0, f.cconv, this.fn == f); };
                return r;
            };

            // True when a call name is already a mangled symbol (contains __ret_)
            def spells_mangled(byte* s) -> bool
            {
                int i;
                if (s == (byte*)0) { return false; };
                while (s[i] != 0)
                {
                    if (s[i] == '_' & s[i + 1] == '_' & s[i + 2] == 'r' & s[i + 3] == 'e' & s[i + 4] == 't' & s[i + 5] == '_') { return true; };
                    i++;
                };
                return false;
            };

            // Default argument expression of parameter i for the function f
            def default_of(IRFunc* f, Node* call, int i) -> Node*
            {
                Node* fd = (Node*)nm_get(this.fdefs, f.name);
                Node* p;
                if (fd == (Node*)0) { return (Node*)0; };
                if (i >= node_count(fd, 0)) { return (Node*)0; };
                p = node_child(fd, 0, i);
                return p.a;
            };

            // True when the variable name has the TypeSpec flag
            def local_flag(byte* name, int flag) -> bool
            {
                LVar* lv = this.find_var(name);
                if (lv == (LVar*)0) { return false; };
                if (lv.ts == (TypeSpec*)0) { return false; };
                return (lv.ts.flags `& flag) != 0;
            };

            // ----------------------------------------------------------
            // Assignment
            // ----------------------------------------------------------

            // AssignmentTypeHandler.handle_identifier_assignment (locals)
            def assign_ident(Node* target, IRValue* val, Node* value_expr) -> IRValue*
            {
                LVar* lv = this.find_var(target.text);
                IRValue* v;
                IRValue* st_v;
                if (lv == (LVar*)0)
                {
                    this.unsup(target, g"assign to non-local\0");
                    return (IRValue*)0;
                };
                if (lv.ts != (TypeSpec*)0)
                {
                    if ((lv.ts.flags `& TS_CONST) != 0)
                    {
                        this.unsup(target, g"assign to const\0");
                        return (IRValue*)0;
                    };
                    if ((lv.ts.flags `& TS_CONST_POINTER) != 0)
                    {
                        this.unsup(target, g"assign to const pointer\0");
                        return (IRValue*)0;
                    };
                };
                if (value_expr.kind == NodeKind.BINARY_OP)
                {
                    if (value_expr.op == Operator.ADD & val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY)
                    {
                        this.unsup(target, g"array concatenation assign\0");
                        return (IRValue*)0;
                    };
                };
                if (value_expr.kind == NodeKind.ARRAY_LITERAL & lv.ptr.ty.elem.kind == LK.PTR)
                {
                    this.unsup(target, g"array literal to pointer assign\0");
                    return (IRValue*)0;
                };
                v = this.maybe_swap(val, lv.ptr);
                v = this.convert_assign(v, lv.ptr.ty.elem);
                if (this.bad) { return (IRValue*)0; };
                this.mod.store(v, lv.ptr);
                return v;
            };

            // Zeroed scratch block of n pointers, released with the module
            def zbuf(int n) -> void*
            {
                byte* r = (byte*)fmalloc((u64)(8 * n));
                int i;
                while (i < 8 * n)
                {
                    r[i] = (byte)0;
                    i++;
                };
                this.keep((void*)r);
                return (void*)r;
            };

            // Next quoted string at or after p in s: returns start of content, sets
            // this.q_len to its length and this.q_end past the closing quote, null when none
            def next_quoted(byte* s, int p) -> int
            {
                int a;
                int b;
                while (s[p] != 0 & s[p] != '"') { p++; };
                if (s[p] == 0) { return -1; };
                a = p + 1;
                b = a;
                while (s[b] != 0 & s[b] != '"') { b++; };
                if (s[b] == 0) { return -1; };
                this.q_len = b - a;
                this.q_end = b + 1;
                return a;
            };

            // Copy of s[a .. a+len)
            def sub_dup(byte* s, int a, int len) -> byte*
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
                return r;
            };

            // Reads "constraint"(var) pairs of one constraint section; returns pair count
            def asm_pairs(byte* s, int a, int b, byte** cs, byte** vs) -> int
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
                    if (p >= b) { break; };
                    qs = p + 1;
                    ql = qs;
                    while (ql < b & s[ql] != '"') { ql++; };
                    if (ql >= b) { break; };
                    p = ql + 1;
                    while (p < b & (s[p] == ' ' | s[p] == 9 | s[p] == 10 | s[p] == 13)) { p++; };
                    if (p >= b | s[p] != '(') { continue; };
                    vs0 = p + 1;
                    ve = vs0;
                    while (ve < b & s[ve] != ')') { ve++; };
                    if (ve >= b | ve == vs0) { break; };
                    cs[n] = this.sub_dup(s, qs, ql - qs);
                    vs[n] = this.sub_dup(s, vs0, ve - vs0);
                    n++;
                    p = ve + 1;
                };
                return n;
            };

            // visit_InlineAsm
            def x_asm(Node* n) -> IRValue*
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
                if (body == (byte*)0) { body = g"\0"; };
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
                    if (te > ts)
                    {
                        if (!(body[ts] == '/' & body[ts + 1] == '/'))
                        {
                            if (!first) { this.asmb.put(10); };
                            first = false;
                            j = ls;
                            while (j < le)
                            {
                                this.asmb.put((int)body[j]);
                                j++;
                            };
                        };
                    };
                    if (body[i] == 0) { break; };
                    i++;
                };
                // sections split at ':'
                p0 = -1;
                p1 = -1;
                len = 0;
                if (cons != (byte*)0)
                {
                    while (cons[len] != 0)
                    {
                        if (cons[len] == ':')
                        {
                            if (p0 < 0) { p0 = len; }
                            elif (p1 < 0) { p1 = len; };
                        };
                        len++;
                    };
                };
                no = 0;
                ni = 0;
                nclob = 0;
                if (cons != (byte*)0)
                {
                    int oe = len;
                    int ie = len;
                    if (p0 >= 0) { oe = p0; };
                    if (p1 >= 0) { ie = p1; }
                    elif (p0 >= 0) { ie = len; };
                    ncs = this.asm_pairs(cons, 0, oe, cs, vs);
                    i = 0;
                    while (i < ncs)
                    {
                        c = cs[i];
                        if (c[0] != '=' & c[0] != '+')
                        {
                            this.sc.clear();
                            this.sc.put(61);
                            this.sc.put_str(c);
                            c = this.sub_dup(this.sc.mem, 0, this.sc.len);
                        };
                        lv = this.find_var(vs[i]);
                        if (lv != (LVar*)0)
                        {
                            oops[no] = lv.ptr;
                            ocs[no] = c;
                            no++;
                        };
                        i++;
                    };
                    if (p0 >= 0)
                    {
                        ncs = this.asm_pairs(cons, p0 + 1, ie, cs, vs);
                        i = 0;
                        while (i < ncs)
                        {
                            lv = this.find_var(vs[i]);
                            if (lv != (LVar*)0)
                            {
                                v = lv.ptr;
                                if (cstr_eq(cs[i], g"m\0") | (v.ty.kind == LK.PTR & v.ty.elem.kind == LK.ARRAY)) { iops[ni] = v; }
                                else
                                {
                                    this.sc.clear();
                                    this.sc.put_str(vs[i]);
                                    this.sc.put_str(g"_load\0");
                                    iops[ni] = this.mod.load(v, this.sc.mem);
                                };
                                ics[ni] = cs[i];
                                ni++;
                            };
                            i++;
                        };
                    };
                    if (p1 >= 0)
                    {
                        a = p1 + 1;
                        while (nclob < 16)
                        {
                            qs = this.next_quoted(cons, a);
                            if (qs < 0) { break; };
                            clob[nclob] = this.sub_dup(cons, qs, this.q_len);
                            nclob++;
                            a = this.q_end;
                        };
                    };
                };
                // translate register letters of the outputs
                i = 0;
                while (i < no)
                {
                    c = ocs[i];
                    a = 0;
                    if (c[0] == '=' | c[0] == '+') { a = 1; };
                    if (c[a + 1] == 0)
                    {
                        byte* rn = (byte*)0;
                        if (c[a] == 'a') { rn = g"rax\0"; }
                        elif (c[a] == 'b') { rn = g"rbx\0"; }
                        elif (c[a] == 'c') { rn = g"rcx\0"; }
                        elif (c[a] == 'd') { rn = g"rdx\0"; }
                        elif (c[a] == 'S') { rn = g"rsi\0"; }
                        elif (c[a] == 'D') { rn = g"rdi\0"; };
                        if (rn != (byte*)0)
                        {
                            this.sc.clear();
                            if (a == 1) { this.sc.put((int)c[0]); };
                            this.sc.put(123);
                            this.sc.put_str(rn);
                            this.sc.put(125);
                            ocs[i] = this.sub_dup(this.sc.mem, 0, this.sc.len);
                        };
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
                    if (c[0] == '=' | c[0] == '+')
                    {
                        if (c[1] == 'm')
                        {
                            j = nfin;
                            while (j > 0)
                            {
                                fin_ops[j] = fin_ops[j - 1];
                                j--;
                            };
                            fin_ops[0] = oops[i];
                            nfin++;
                            if (c[0] == '=')
                            {
                                this.sc.clear();
                                this.sc.put(43);
                                this.sc.put_str(c + 1);
                                c = this.sub_dup(this.sc.mem, 0, this.sc.len);
                            };
                        }
                        else
                        {
                            ro_ptr[nro] = oops[i];
                            nro++;
                        };
                    }
                    else
                    {
                        ro_ptr[nro] = oops[i];
                        nro++;
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
                    if (i > 0) { this.asmc.put(44); };
                    this.asmc.put_str(fcs[i]);
                    i++;
                };
                i = 0;
                while (i < nclob)
                {
                    if (nfc > 0 | i > 0) { this.asmc.put(44); };
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
                if (nro == 0) { rty = this.t_void; }
                elif (nro == 1) { rty = ro_ptr[0].ty.elem; }
                else
                {
                    i = 0;
                    while (i < nro)
                    {
                        otys[i] = ro_ptr[i].ty.elem;
                        i++;
                    };
                    rty = this.mod.t_struct(otys, nro);
                };
                ft = this.mod.t_func(rty, itys, nfin, false);
                // llvmlite prints asm, sideeffect flag, body and constraints verbatim
                this.sc.clear();
                this.sc.put_str(g"asm \0");
                if ((n.flags `& NF_VOLATILE) != 0) { this.sc.put_str(g"sideeffect\0"); };
                this.sc.put_str(g" \"\0");
                this.sc.put_str(this.asmb.mem);
                this.sc.put_str(g"\", \"\0");
                this.sc.put_str(this.asmc.mem);
                this.sc.put_str(g"\"\n\0");
                callee = this.mod.new_value(this.mod.t_ptr(ft), this.sc.mem);
                res = this.mod.call(callee, fin_ops, nfin, (byte*)0);
                if (nro == 1) { this.mod.store(res, ro_ptr[0]); }
                elif (nro > 1)
                {
                    i = 0;
                    while (i < nro)
                    {
                        v = this.mod.extractvalue(res, i, (byte*)0);
                        this.mod.store(v, ro_ptr[i]);
                        i++;
                    };
                };
                return res;
            };

            // visit_MethodCall for object receivers
            def x_method(Node* n) -> IRValue*
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
                if (n.text3 == (byte*)0)
                {
                    this.unsup(n, g"method target not resolved\0");
                    return (IRValue*)0;
                };
                if (o.kind == NodeKind.IDENTIFIER)
                {
                    lv = this.find_local(o.text);
                    if (lv == (LVar*)0)
                    {
                        this.unsup(n, g"method call on non-local\0");
                        return (IRValue*)0;
                    };
                    objp = lv.ptr;
                    vname = o.text;
                }
                else
                {
                    objp = this.visit(o);
                    if (this.bad) { return (IRValue*)0; };
                };
                if (objp == (IRValue*)0)
                {
                    this.unsup(n, g"void method receiver\0");
                    return (IRValue*)0;
                };
                if (objp.ty.kind != LK.PTR)
                {
                    this.unsup(n, g"type function call\0");
                    return (IRValue*)0;
                };
                sp = objp.ty.elem;
                if (sp.kind == LK.ISTRUCT) { thisp = objp; }
                elif (sp.kind == LK.PTR & sp.elem.kind == LK.ISTRUCT)
                {
                    this.sc.clear();
                    if (vname != (byte*)0)
                    {
                        this.sc.put_str(vname);
                        this.sc.put_str(g"_load\0");
                    }
                    else { this.sc.put_str(g"obj_load\0"); };
                    thisp = this.mod.load(objp, this.sc.mem);
                }
                else
                {
                    this.unsup(n, g"type function call\0");
                    return (IRValue*)0;
                };
                f = this.mod.find_function(n.text3);
                if (f == (IRFunc*)0)
                {
                    this.unsup(n, g"method not declared\0");
                    return (IRValue*)0;
                };
                ft = f.ftype;
                args = (IRValue**)fmalloc((u64)(8 * (argc + 1)));
                this.keep((void*)args);
                args[0] = thisp;
                i = 0;
                while (i < argc)
                {
                    v = this.visit(node_child(n, 0, i));
                    if (this.bad) { return (IRValue*)0; };
                    if (v == (IRValue*)0)
                    {
                        this.unsup(n, g"void method argument\0");
                        return (IRValue*)0;
                    };
                    args[i + 1] = v;
                    i++;
                };
                i = 0;
                while (i < argc & i + 1 < ft.nitems)
                {
                    v = args[i + 1];
                    if (v.ty.kind == LK.PTR & ft.items[i + 1].kind == LK.PTR)
                    {
                        if (v.ty.elem.kind == LK.ARRAY)
                        {
                            if (lt_eq(v.ty.elem.elem, ft.items[i + 1].elem))
                            {
                                this.sc.clear();
                                this.sc.put_str(g"marg\0");
                                this.sc.put_int(i);
                                this.sc.put_str(g"_decay\0");
                                this.mod.ia[0] = this.ci32(0);
                                this.mod.ia[1] = this.ci32(0);
                                v = this.mod.gep(v, this.mod.ia, 2, false, this.sc.mem);
                            };
                        };
                    };
                    args[i + 1] = this.convert_arg(v, ft.items[i + 1], i, n);
                    if (this.bad) { return (IRValue*)0; };
                    i++;
                };
                return this.mod.call_ex(f.self, args, argc + 1, (byte*)0, f.cconv, false);
            };

            // visit_NotNull: compare against null or zero, widened to i8
            def i1_lit(byte* txt) -> IRValue*
            {
                IRValue* v = this.mod.new_value(this.t_i1, txt);
                v.is_const = true;
                return v;
            };

            // 'needle in haystack' for byte* needle and byte* haystack (NUL terminated substring search)
            def x_in(Node* n) -> IRValue*
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
                if (this.bad) { return (IRValue*)0; };
                if (!this.is_i8_ptr(nd.ty))
                {
                    this.unsup(n, g"in: needle type\0");
                    return (IRValue*)0;
                };
                hy = this.visit(n.b);
                if (this.bad) { return (IRValue*)0; };
                if (!this.is_i8_ptr(hy.ty))
                {
                    this.unsup(n, g"in: haystack type\0");
                    return (IRValue*)0;
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
                if ((n.flags `& NF_NEGATED) != 0)
                {
                    res = this.mod.binop(g"xor\0", res, this.i1_lit(g"-1\0"), g"notin.result\0");
                };
                return res;
            };

            def x_notnull(Node* n) -> IRValue*
            {
                IRValue* v = this.visit(n.a);
                IRValue* c;
                if (this.bad) { return (IRValue*)0; };
                if (v == (IRValue*)0)
                {
                    this.unsup(n, g"not-null void operand\0");
                    return (IRValue*)0;
                };
                if (v.ty.kind == LK.PTR) { c = this.mod.icmp(g"ne\0", v, this.mod.c_null(v.ty), g"not_null\0"); }
                elif (v.ty.kind == LK.INT) { c = this.mod.icmp(g"ne\0", v, this.mod.c_int(v.ty, (i64)0), g"not_zero\0"); }
                elif (v.ty.kind == LK.FLOAT | v.ty.kind == LK.DOUBLE) { c = this.mod.fcmp(g"one\0", v, this.mod.c_fp(v.ty, 0.0), g"not_zero_f\0"); }
                else
                {
                    this.unsup(n, g"not-null operand type\0");
                    return (IRValue*)0;
                };
                return this.mod.cast(g"zext\0", c, this.t_i8, g"not_null_result\0");
            };

            // Operator of a compound assignment token, -1 when unsupported
            def compound_op(int tok) -> int
            {
                switch (tok)
                {
                    case (TokenType.PLUS_ASSIGN) { return Operator.ADD; }
                    case (TokenType.MINUS_ASSIGN) { return Operator.SUB; }
                    case (TokenType.MULTIPLY_ASSIGN) { return Operator.MUL; }
                    case (TokenType.DIVIDE_ASSIGN) { return Operator.DIV; }
                    case (TokenType.MODULO_ASSIGN) { return Operator.MOD; }
                    case (TokenType.EXPONENT_ASSIGN) { return Operator.POWER; }
                    case (TokenType.AND_ASSIGN) { return Operator.AND; }
                    case (TokenType.OR_ASSIGN) { return Operator.OR; }
                    case (TokenType.XOR_ASSIGN) { return Operator.XOR; }
                    case (TokenType.BITAND_ASSIGN) { return Operator.BITAND; }
                    case (TokenType.BITOR_ASSIGN) { return Operator.BITOR; }
                    case (TokenType.BITXOR_ASSIGN) { return Operator.BITXOR; }
                    case (TokenType.BITXNOR_ASSIGN) { return Operator.BITXNOR; }
                    case (TokenType.BITNAND_ASSIGN) { return Operator.BITNAND; }
                    case (TokenType.BITNOR_ASSIGN) { return Operator.BITNOR; }
                    case (TokenType.BITSHIFT_LEFT_ASSIGN) { return Operator.BITSHIFT_LEFT; }
                    case (TokenType.BITSHIFT_RIGHT_ASSIGN) { return Operator.BITSHIFT_RIGHT; }
                    default {};
                };
                return -1;
            };

            // handle_compound_assignment: t op= v is t = t op v. For an identifier
            // target with ADD the base evaluates both operands once before that.
            def x_compound(Node* n) -> IRValue*
            {
                int op = this.compound_op(n.op);
                Node* bin;
                Node* asg;
                IRValue* pre;
                IRValue* r;
                if (op < 0)
                {
                    this.unsup(n, g"compound operator\0");
                    return (IRValue*)0;
                };
                if (op == Operator.ADD & n.a.kind == NodeKind.IDENTIFIER)
                {
                    pre = this.visit(n.a);
                    if (this.bad) { return (IRValue*)0; };
                    pre = this.visit(n.b);
                    if (this.bad) { return (IRValue*)0; };
                    if (pre != (IRValue*)0)
                    {
                        if (pre.ty.kind == LK.PTR)
                        {
                            if (pre.ty.elem.kind == LK.ARRAY)
                            {
                                this.unsup(n, g"array concatenation\0");
                                return (IRValue*)0;
                            };
                        };
                    };
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
                return r;
            };

            def x_assign(Node* n) -> IRValue*
            {
                Node* t = n.a;
                int tk = t.kind;
                IRValue* val;
                if (tk != NodeKind.IDENTIFIER & tk != NodeKind.MEMBER_ACCESS & tk != NodeKind.ARRAY_ACCESS &
                    tk != NodeKind.POINTER_DEREF)
                {
                    this.unsup(n, g"assignment target\0");
                    return (IRValue*)0;
                };
                if (n.b.kind == NodeKind.ARRAY_LITERAL | n.b.kind == NodeKind.STRUCT_LITERAL)
                {
                    this.unsup(n, g"literal assignment\0");
                    return (IRValue*)0;
                };
                val = this.visit(n.b);
                if (this.bad) { return (IRValue*)0; };
                if (val == (IRValue*)0)
                {
                    this.unsup(n, g"void assignment value\0");
                    return (IRValue*)0;
                };
                if (tk == NodeKind.MEMBER_ACCESS) { return this.assign_member(t, val, n.b); };
                if (tk == NodeKind.ARRAY_ACCESS) { return this.assign_index(t, val, n.b); };
                if (tk == NodeKind.POINTER_DEREF) { return this.assign_deref(t, val); };
                return this.assign_ident(t, val, n.b);
            };

            // ----------------------------------------------------------
            // Variable declarations
            // ----------------------------------------------------------

            def zero_of(IRType* t) -> IRValue*
            {
                return this.mod.c_null(t);
            };

            def x_vardecl(Node* n) -> IRValue*
            {
                TypeSpec* ts = n.ts;
                IRType* lt;
                IRValue* alloca;
                IRValue* iv;
                LVar* lv;
                Node* ini = n.a;
                if (this.fn == (IRFunc*)0 | (n.flags `& NF_GLOBAL) != 0)
                {
                    this.unsup(n, g"global variable\0");
                    return (IRValue*)0;
                };
                if (ts == (TypeSpec*)0)
                {
                    this.unsup(n, g"declaration without type\0");
                    return (IRValue*)0;
                };
                if (ts.base_type == DataType.DICT)
                {
                    this.unsup(n, g"dict variable\0");
                    return (IRValue*)0;
                };
                if (ts.storage_class == StorageClass.AUTO)
                {
                    this.unsup(n, g"auto variable\0");
                    return (IRValue*)0;
                };
                if (ts.storage_class == StorageClass.SINGINIT | ts.storage_class == StorageClass.HEAP)
                {
                    this.unsup(n, g"singinit or heap variable\0");
                    return (IRValue*)0;
                };
                if ((ts.flags `& TS_ARRAY) != 0 & ts.array_size == (Node*)0 & ts.array_dims == (NodeVec*)0)
                {
                    this.unsup(n, g"array without size\0");
                    return (IRValue*)0;
                };
                lt = this.lower(ts, true, n.line);
                if (this.nerrors > this.body_errs)
                {
                    this.unsup(n, g"variable type lowering\0");
                    return (IRValue*)0;
                };
                if (lt.kind == LK.PTR & (ts.flags `& TS_ARRAY) != 0)
                {
                    this.unsup(n, g"variable length array\0");
                    return (IRValue*)0;
                };
                if (ini != (Node*)0)
                {
                    if (ini.kind == NodeKind.STRUCT_RECAST)
                    {
                        this.unsup(n, g"struct recast initializer\0");
                        return (IRValue*)0;
                    };
                    if (ini.kind == NodeKind.FUNCTION_CALL)
                    {
                        if (ini.text != (byte*)0)
                        {
                            if (ends_with(ini.text, g".__init\0"))
                            {
                                if (ini.text3 == (byte*)0 | node_count(ini, 0) > 0 & lt.kind != LK.ISTRUCT)
                                {
                                    this.unsup(n, g"constructor initializer\0");
                                    return (IRValue*)0;
                                };
                            };
                        };
                    };
                    if (ini.kind == NodeKind.STRING_LITERAL & this.str_init_ok(lt, ini)) { }
                    elif (ini.kind == NodeKind.ARRAY_LITERAL & this.simple_array_init(lt, ini)) { }
                    elif (ini.kind == NodeKind.ARRAY_LITERAL | ini.kind == NodeKind.ARRAY_COMPREHENSION |
                        ini.kind == NodeKind.STRING_LITERAL | ini.kind == NodeKind.STRUCT_LITERAL)
                    {
                        this.unsup(n, g"aggregate initializer\0");
                        return (IRValue*)0;
                    };
                    if (lt.kind == LK.ARRAY & ini.kind == NodeKind.IDENTIFIER)
                    {
                        this.unsup(n, g"array copy initializer\0");
                        return (IRValue*)0;
                    };
                };
                alloca = this.mod.alloca(lt, n.text);
                alloca.spec = ts;
                lv = this.define_var(n.text, alloca, ts);
                if ((ts.flags `& TS_VOLATILE) != 0) { lv.vol = true; };
                if (ini != (Node*)0)
                {
                    if (ini.kind == NodeKind.NO_INIT) { return alloca; };
                    if (ini.kind == NodeKind.ARRAY_LITERAL)
                    {
                        this.init_local_array(alloca, lt, ini);
                        return alloca;
                    };
                    if (ini.kind == NodeKind.STRING_LITERAL)
                    {
                        this.init_local_string(alloca, lt, ini);
                        return alloca;
                    };
                    if (ini.kind == NodeKind.FUNCTION_CALL & ini.text != (byte*)0)
                    {
                        if (ends_with(ini.text, g".__init\0"))
                        {
                            this.init_ctor(alloca, lt, ini, n);
                            return alloca;
                        };
                    };
                    iv = this.visit(ini);
                    if (this.bad) { return (IRValue*)0; };
                    if (iv != (IRValue*)0)
                    {
                        this.store_conv(alloca, lt, iv, ini, n);
                    };
                    return alloca;
                };
                if (lt.kind == LK.ARRAY)
                {
                    if (lt.count > 64)
                    {
                        this.memset_zero(alloca, lt);
                        return alloca;
                    };
                };
                this.mod.store(this.zero_of(lt), alloca);
                return alloca;
            };

            // ----------------------------------------------------------
            // Statements
            // ----------------------------------------------------------

            def s_block(Node* n) -> void
            {
                int i;
                int c = node_count(n, 0);
                PtrVec* outer = this.defers;
                this.defers = (PtrVec*)0;
                while (i < c)
                {
                    if (this.mod.is_terminated()) { break; };
                    this.visit(node_child(n, 0, i));
                    if (this.bad) { break; };
                    i++;
                };
                if (!this.bad & !this.mod.is_terminated()) { this.run_defers(); };
                if (this.defers != (PtrVec*)0) { pv_free(this.defers); };
                this.defers = outer;
                return;
            };

            // Emits the deferred statements of the current block in reverse order
            def run_defers() -> void
            {
                int i;
                int j;
                Node* d;
                if (this.defers == (PtrVec*)0) { return; };
                i = this.defers.len - 1;
                while (i >= 0)
                {
                    d = (Node*)this.defers.items[i];
                    if ((d.flags `& NF_HAS_BODY) != 0)
                    {
                        j = node_count(d, 0) - 1;
                        while (j >= 0)
                        {
                            this.visit(node_child(d, 0, j));
                            if (this.bad) { return; };
                            j--;
                        };
                    }
                    else { this.visit(d.a); };
                    if (this.bad) { return; };
                    i--;
                };
                return;
            };

            def check_cond_node(Node* c) -> void
            {
                if (c.kind == NodeKind.STRING_LITERAL | c.kind == NodeKind.F_STRING_LITERAL)
                {
                    this.unsup(c, g"string literal condition\0");
                };
                return;
            };

            def cond_value(Node* c) -> IRValue*
            {
                IRValue* v;
                this.check_cond_node(c);
                if (this.bad) { return (IRValue*)0; };
                v = this.visit(c);
                if (this.bad) { return (IRValue*)0; };
                if (v == (IRValue*)0)
                {
                    this.unsup(c, g"void condition\0");
                    return (IRValue*)0;
                };
                return this.to_bool(v);
            };

            def s_if(Node* n) -> void
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
                if (this.bad) { return; };
                then_b = this.mod.append_block(this.fn, g"then\0");
                else_b = this.mod.append_block(this.fn, g"else\0");
                merge_b = this.mod.append_block(this.fn, g"ifcont\0");
                this.mod.cbr(cv, then_b, else_b);
                this.mod.position(this.fn, then_b);
                this.visit(n.b);
                if (this.bad) { return; };
                if (!this.mod.is_terminated()) { this.mod.br(merge_b); };
                this.mod.position(this.fn, else_b);
                while (i < ne)
                {
                    cv = this.cond_value(node_child(n, 0, i));
                    if (this.bad) { return; };
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
                    if (this.bad) { return; };
                    if (!this.mod.is_terminated()) { this.mod.br(merge_b); };
                    this.mod.position(this.fn, ee);
                    i++;
                };
                if (n.c != (Node*)0)
                {
                    this.visit(n.c);
                    if (this.bad) { return; };
                };
                if (!this.mod.is_terminated()) { this.mod.br(merge_b); };
                this.mod.position(this.fn, merge_b);
                return;
            };

            // Value of a constant IRValue from its text (decimal, true, false)
            def const_i64(IRValue* v) -> i64
            {
                byte* t = v.text;
                i64 r;
                int i;
                bool neg;
                if (t[0] == 't') { return (i64)1; };
                if (t[0] == 'f') { return (i64)0; };
                if (t[0] == '-') { neg = true; i = 1; };
                while (t[i] >= '0' & t[i] <= '9')
                {
                    r = r * (i64)10 + (i64)(t[i] - '0');
                    i++;
                };
                if (neg) { r = (i64)0 - r; };
                return r;
            };

            def s_switch(Node* n) -> void
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
                if (n.a.kind == NodeKind.TYPE_OF)
                {
                    this.unsup(n, g"switch on typeof\0");
                    return;
                };
                sv = this.visit(n.a);
                if (this.bad) { return; };
                if (sv == (IRValue*)0)
                {
                    this.unsup(n, g"switch value\0");
                    return;
                };
                if (sv.ty.kind != LK.INT)
                {
                    this.unsup(n, g"switch on non-integer\0");
                    return;
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
                    if (c.a == (Node*)0)
                    {
                        dflt_b = this.mod.append_block(this.fn, g"switch_default\0");
                        bodies[i] = dflt_b;
                    }
                    else
                    {
                        bodies[i] = this.mod.append_block(this.fn, this.case_name(i));
                        cv = this.visit(c.a);
                        if (this.bad) { return; };
                        if (cv == (IRValue*)0)
                        {
                            this.unsup(c.a, g"switch case value\0");
                            return;
                        };
                        if (!cv.is_const | cv.ty.kind != LK.INT)
                        {
                            this.unsup(c.a, g"switch case value\0");
                            return;
                        };
                        if (sv.ty.kind == LK.INT & sv.ty.width == 1) { vals[ncase] = this.mod.c_u64(sv.ty, (u64)(this.const_i64(cv) `& (i64)1)); }
                        else { vals[ncase] = this.mod.c_int(sv.ty, this.const_i64(cv)); };
                        blocks[ncase] = bodies[i];
                        ncase++;
                    };
                    i++;
                };
                if (dflt_b == (IRBlock*)0) { dflt_b = merge_b; };
                this.mod.switch_to(sv, dflt_b, vals, blocks, ncase);
                i = 0;
                while (i < nc)
                {
                    c = node_child(n, 0, i);
                    this.mod.position(this.fn, bodies[i]);
                    this.visit(c.b);
                    if (this.bad) { return; };
                    if (!this.mod.is_terminated()) { this.mod.br(merge_b); };
                    i++;
                };
                this.mod.position(this.fn, merge_b);
                return;
            };

            // "switch_case_<i>"
            def case_name(int i) -> byte*
            {
                Buf nb;
                nb.__init();
                nb.put_str(g"switch_case_\0");
                nb.put_int(i);
                byte* r = ts_dup(nb.mem);
                this.keep((void*)r);
                nb.__exit();
                return r;
            };

            def s_try(Node* n) -> void
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
                    if (cl.text != (byte*)0)
                    {
                        if (cl.text[0] != (byte)0)
                        {
                            this.unsup(n, g"named catch\0");
                            pv_free(cbs);
                            return;
                        };
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
                if (this.bad) { pv_free(cbs); return; };
                if (!this.mod.is_terminated()) { this.mod.br(chk_b); };
                this.mod.position(this.fn, chk_b);
                fv = this.mod.load(flag, g"exc_flag\0");
                hx = this.mod.icmp(g"ne\0", fv, this.mod.c_int(this.t_i32, (i64)0), g"has_exception\0");
                if (cc > 0) { first_c = (IRBlock*)cbs.items[0]; }
                else { first_c = end_b; };
                this.mod.cbr(hx, first_c, end_b);
                i = 0;
                while (i < cc)
                {
                    cl = node_child(n, 0, i);
                    this.mod.position(this.fn, (IRBlock*)cbs.items[i]);
                    this.mod.store(fz, flag);
                    this.visit(cl.a);
                    if (this.bad) { pv_free(cbs); return; };
                    if (!this.mod.is_terminated()) { this.mod.br(end_b); };
                    i++;
                };
                pv_free(cbs);
                this.mod.position(this.fn, end_b);
                return;
            };

            def s_while(Node* n) -> void
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
                if (this.bad) { return; };
                this.mod.cbr(cv, body_b, end_b);
                this.mod.position(this.fn, body_b);
                this.visit(n.b);
                if (this.bad) { return; };
                if (!this.mod.is_terminated()) { this.mod.br(cond_b); };
                this.brk = ob;
                this.cont = oc;
                this.mod.position(this.fn, end_b);
                return;
            };

            def s_do(Node* n) -> void
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
                if (this.bad) { return; };
                if (!this.mod.is_terminated()) { this.mod.br(body_b); };
                this.brk = ob;
                this.cont = oc;
                this.mod.position(this.fn, end_b);
                return;
            };

            def s_dowhile(Node* n) -> void
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
                if (this.bad) { return; };
                if (!this.mod.is_terminated()) { this.mod.br(cond_b); };
                this.mod.position(this.fn, cond_b);
                this.check_cond_node(n.a);
                if (this.bad) { return; };
                cv = this.visit(n.a);
                if (this.bad) { return; };
                if (cv == (IRValue*)0)
                {
                    this.unsup(n, g"void condition\0");
                    return;
                };
                this.mod.cbr(cv, body_b, end_b);
                this.brk = ob;
                this.cont = oc;
                this.mod.position(this.fn, end_b);
                return;
            };

            def s_for(Node* n) -> void
            {
                IRBlock* cond_b = this.mod.append_block(this.fn, g"for.cond\0");
                IRBlock* body_b = this.mod.append_block(this.fn, g"for.body\0");
                IRBlock* upd_b = this.mod.append_block(this.fn, g"for.update\0");
                IRBlock* end_b = this.mod.append_block(this.fn, g"for.end\0");
                IRBlock* ob;
                IRBlock* oc;
                IRValue* cv;
                if (n.a != (Node*)0)
                {
                    this.visit(n.a);
                    if (this.bad) { return; };
                };
                this.mod.br(cond_b);
                this.mod.position(this.fn, cond_b);
                if (n.b != (Node*)0)
                {
                    cv = this.cond_value(n.b);
                    if (this.bad) { return; };
                    this.mod.cbr(cv, body_b, end_b);
                }
                else { this.mod.br(body_b); };
                this.mod.position(this.fn, body_b);
                ob = this.brk;
                oc = this.cont;
                this.brk = end_b;
                this.cont = upd_b;
                this.visit(n.d);
                if (this.bad) { return; };
                if (!this.mod.is_terminated()) { this.mod.br(upd_b); };
                this.mod.position(this.fn, upd_b);
                if (n.c != (Node*)0)
                {
                    this.visit(n.c);
                    if (this.bad) { return; };
                };
                this.mod.br(cond_b);
                this.brk = ob;
                this.cont = oc;
                this.mod.position(this.fn, end_b);
                return;
            };

            // visit_NoreturnStatement
            def s_noreturn() -> void
            {
                int i;
                bool have;
                if (!this.mod.is_terminated()) { this.mod.unreachable(); };
                if (this.fn != (IRFunc*)0)
                {
                    while (i < this.fn.attrs.len)
                    {
                        if (cstr_eq((byte*)this.fn.attrs.items[i], g"noreturn\0")) { have = true; };
                        i++;
                    };
                    if (!have) { pv_push(this.fn.attrs, (void*)this.mod.own(g"noreturn\0")); };
                };
                return;
            };

            def s_return(Node* n) -> void
            {
                IRValue* rv;
                IRType* expected = this.fret;
                bool suppress;
                if (this.mod.is_terminated()) { return; };
                if (n.a == (Node*)0)
                {
                    this.mod.ret_void();
                    return;
                };
                if (n.a.kind == NodeKind.IDENTIFIER)
                {
                    if (this.local_flag(n.a.text, TS_LOCAL))
                    {
                        this.unsup(n, g"local variable returned\0");
                        return;
                    };
                };
                if (n.a.kind == NodeKind.STRUCT_LITERAL)
                {
                    this.unsup(n, g"struct literal return\0");
                    return;
                };
                suppress = expected.kind == LK.STRUCT | expected.kind == LK.ISTRUCT;
                if (suppress) { this.in_member = true; };
                rv = this.visit(n.a);
                if (suppress) { this.in_member = false; };
                if (this.bad) { return; };
                this.run_defers();
                if (this.bad) { return; };
                if (rv == (IRValue*)0)
                {
                    this.mod.ret_void();
                    return;
                };
                if (this.mod.is_terminated()) { return; };
                if (expected.kind == LK.VOID)
                {
                    this.mod.ret_void();
                    return;
                };
                if (rv.ty.kind == LK.PTR & rv.ty.elem.kind == LK.STRUCT & lt_eq(rv.ty.elem, expected))
                {
                    rv = this.mod.load(rv, g"ret_load\0");
                };
                rv = this.coerce_ret(rv, expected, n);
                if (this.bad) { return; };
                this.mod.ret(rv);
                return;
            };


            // ----------------------------------------------------------
            // Unary, address-of, dereference, casts, strings, sizeof
            // ----------------------------------------------------------

            // x with every bit set (builder.not_ uses Constant(type, -1))
            def all_ones(IRType* t) -> IRValue*
            {
                IRValue* v = this.mod.new_value(t, g"-1\0");
                v.is_const = true;
                return v;
            };

            // visit_UnaryOp (identifier operands; member and array operands are not
            // generated yet)
            def x_unary(Node* n) -> IRValue*
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
                if (incdec & opd.kind == NodeKind.ADDRESS_OF)
                {
                    this.unsup(n, g"increment of address-of\0");
                    return (IRValue*)0;
                };
                v = this.visit(opd);
                if (this.bad) { return (IRValue*)0; };
                if (v == (IRValue*)0)
                {
                    this.unsup(n, g"void unary operand\0");
                    return (IRValue*)0;
                };
                if (incdec & opd.kind == NodeKind.IDENTIFIER)
                {
                    if (v.ty.kind == LK.PTR & v.ty.elem.kind == LK.PTR)
                    {
                        this.sc.clear();
                        this.sc.put_str(opd.text);
                        this.sc.put_str(g"_loaded\0");
                        v = this.mod.load(v, this.sc.mem);
                    };
                };
                if (op == Operator.NOT)
                {
                    if (v.ty.kind == LK.PTR)
                    {
                        return this.mod.icmp(g"eq\0", v, this.mod.c_null(v.ty), g"is_null\0");
                    };
                    if (v.ty.kind != LK.INT)
                    {
                        this.unsup(n, g"not of non-integer\0");
                        return (IRValue*)0;
                    };
                    return this.mod.binop(g"xor\0", v, this.all_ones(v.ty), (byte*)0);
                };
                if (op == Operator.SUB)
                {
                    if (v.ty.kind == LK.FLOAT | v.ty.kind == LK.DOUBLE)
                    {
                        return this.mod.binop(g"fsub\0", this.mod.c_fp(v.ty, 0.0), v, (byte*)0);
                    };
                    if (v.ty.kind != LK.INT)
                    {
                        this.unsup(n, g"negate of non-number\0");
                        return (IRValue*)0;
                    };
                    return this.mod.binop(g"sub\0", this.mod.c_int(v.ty, (i64)0), v, (byte*)0);
                };
                if (op == Operator.BITNOT)
                {
                    if (v.ty.kind != LK.INT)
                    {
                        this.unsup(n, g"bit not of non-integer\0");
                        return (IRValue*)0;
                    };
                    return this.mod.binop(g"xor\0", v, this.all_ones(v.ty), (byte*)0);
                };
                if (incdec)
                {
                    if (v.ty.kind == LK.PTR)
                    {
                        if (op == Operator.INCREMENT)
                        {
                            nv = this.mod.gep_ptr(v, this.ci32(1), false, g"ptr_inc\0");
                        }
                        else
                        {
                            nv = this.mod.gep_ptr(v, this.ci32(0 - 1), false, g"ptr_dec\0");
                        };
                    }
                    elif (v.ty.kind == LK.INT)
                    {
                        off = this.mod.c_int(v.ty, (i64)1);
                        if (op == Operator.INCREMENT) { nv = this.mod.binop(g"add\0", v, off, (byte*)0); }
                        else { nv = this.mod.binop(g"sub\0", v, off, (byte*)0); };
                    }
                    else
                    {
                        this.unsup(n, g"increment of non-integer\0");
                        return (IRValue*)0;
                    };
                    if (opd.kind == NodeKind.IDENTIFIER)
                    {
                        lv = this.find_var(opd.text);
                        if (lv == (LVar*)0)
                        {
                            this.unsup(n, g"increment of non-local\0");
                            return (IRValue*)0;
                        };
                        this.mod.store(nv, lv.ptr);
                    }
                    elif (opd.kind == NodeKind.MEMBER_ACCESS)
                    {
                        mpv = this.member_ptr(opd);
                        if (this.bad) { return (IRValue*)0; };
                        this.mod.store(nv, mpv);
                    }
                    elif (opd.kind == NodeKind.ARRAY_ACCESS)
                    {
                        mpv = this.index_ptr(opd);
                        if (this.bad) { return (IRValue*)0; };
                        this.mod.store(nv, mpv);
                    };
                    if (post) { return v; };
                    return nv;
                };
                this.unsup(n, g"unary operator\0");
                return (IRValue*)0;
            };

            // visit_PointerDeref
            def x_deref(Node* n) -> IRValue*
            {
                IRValue* p = this.visit(n.a);
                if (this.bad) { return (IRValue*)0; };
                if (p == (IRValue*)0)
                {
                    this.unsup(n, g"void dereference\0");
                    return (IRValue*)0;
                };
                if (p.ty.kind != LK.PTR)
                {
                    this.unsup(n, g"dereference of non-pointer\0");
                    return (IRValue*)0;
                };
                return this.mod.load(p, g"deref\0");
            };

            // visit_AddressOf (literals and local variables)
            // '@name' where name is a function: the base returns the function itself
            def function_ref(byte* name) -> IRValue*
            {
                FXC_SYMENTRY* fe = st_lookup_any(this.st, name, this.cur_ns);
                PtrVec* list;
                Overload* o;
                Overload* oc;
                IRFunc* f;
                byte* key;
                int oi;
                if (fe == (FXC_SYMENTRY*)0) { return (IRValue*)0; };
                if (fe.kind_id != SymbolKind.FUNCTION) { return (IRValue*)0; };
                key = sym_mangled(fe);
                list = st_overloads_of(this.st, key);
                ffree(key);
                if (list == (PtrVec*)0) { return (IRValue*)0; };
                if (list.len == 1) { o = (Overload*)list.items[0]; }
                else
                {
                    while (oi < list.len)
                    {
                        oc = (Overload*)list.items[oi];
                        if (oc.nparams == 0)
                        {
                            o = oc;
                            break;
                        };
                        oi++;
                    };
                };
                if (o == (Overload*)0) { return (IRValue*)0; };
                f = this.mod.find_function(o.mangled);
                if (f == (IRFunc*)0) { return (IRValue*)0; };
                return f.self;
            };

            def x_addrof(Node* n) -> IRValue*
            {
                Node* e = n.a;
                IRValue* v;
                IRValue* tmp;
                IRValue* fv;
                LVar* lv;
                if (e.kind == NodeKind.LITERAL)
                {
                    v = this.visit(e);
                    if (this.bad) { return (IRValue*)0; };
                    tmp = this.mod.alloca(v.ty, (byte*)0);
                    this.mod.store(v, tmp);
                    return tmp;
                };
                if (e.kind == NodeKind.IDENTIFIER)
                {
                    lv = this.find_var(e.text);
                    if (lv == (LVar*)0)
                    {
                        fv = this.function_ref(e.text);
                        if (fv != (IRValue*)0) { return fv; };
                        this.unsup(n, g"address of non-local\0");
                        return (IRValue*)0;
                    };
                    if (lv.ptr.ty.kind == LK.PTR & lv.ptr.ty.elem.kind == LK.PTR)
                    {
                        this.sc.clear();
                        this.sc.put_str(e.text);
                        this.sc.put_str(g"_ptr\0");
                        return this.mod.load(lv.ptr, this.sc.mem);
                    };
                    return lv.ptr;
                };
                if (e.kind == NodeKind.MEMBER_ACCESS) { return this.member_ptr(e); };
                if (e.kind == NodeKind.POINTER_DEREF) { return this.visit(e.a); };
                if (e.kind == NodeKind.FUNCTION_CALL)
                {
                    v = this.visit(e);
                    if (this.bad) { return (IRValue*)0; };
                    if (v == (IRValue*)0)
                    {
                        this.unsup(n, g"address of void call\0");
                        return (IRValue*)0;
                    };
                    tmp = this.mod.alloca(v.ty, g"func_result_temp\0");
                    this.mod.store(v, tmp);
                    return tmp;
                };
                if (e.kind == NodeKind.ARRAY_ACCESS)
                {
                    Node* an = e.a;
                    IRValue* arrp;
                    IRValue* ix;
                    if (e.b.kind == NodeKind.RANGE_EXPRESSION)
                    {
                        this.unsup(n, g"address of range index\0");
                        return (IRValue*)0;
                    };
                    if (an.kind == NodeKind.IDENTIFIER)
                    {
                        lv = this.find_var(an.text);
                        if (lv == (LVar*)0)
                        {
                            this.unsup(n, g"address of non-local array\0");
                            return (IRValue*)0;
                        };
                        arrp = lv.ptr;
                    }
                    elif (an.kind == NodeKind.MEMBER_ACCESS) { arrp = this.member_ptr(an); }
                    else { arrp = this.visit(an); };
                    if (this.bad) { return (IRValue*)0; };
                    if (arrp == (IRValue*)0)
                    {
                        this.unsup(n, g"address of void array\0");
                        return (IRValue*)0;
                    };
                    ix = this.visit(e.b);
                    if (this.bad) { return (IRValue*)0; };
                    if (ix == (IRValue*)0)
                    {
                        this.unsup(n, g"address of void index\0");
                        return (IRValue*)0;
                    };
                    if (arrp.ty.kind == LK.PTR & arrp.ty.elem.kind == LK.PTR) { arrp = this.mod.load(arrp, g"array_param_ptr\0"); };
                    if (arrp.ty.kind == LK.PTR)
                    {
                        if (arrp.ty.elem.kind == LK.ARRAY)
                        {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = ix;
                            return this.mod.gep(arrp, this.mod.ia, 2, true, (byte*)0);
                        };
                        return this.mod.gep_ptr(arrp, ix, true, (byte*)0);
                    };
                };
                this.unsup(n, g"address-of operand\0");
                return (IRValue*)0;
            };

            // EndianSwapHandler fix applied to the result of a cast
            def cast_endian_fix(IRValue* v, TypeSpec* tgt) -> IRValue*
            {
                if (v.ty.kind == LK.INT & v.ty.width >= 16)
                {
                    if (this.endian_of(v.spec) != this.endian_of(tgt)) { return this.bswap(v); };
                };
                return v;
            };

            // _cast_handle_void for stack variables: null the slot and forget the name
            def cast_void(Node* n) -> IRValue*
            {
                Node* e = n.a;
                LVar* lv;
                IRType* pt;
                IRValue* ev;
                int i;
                if (e.kind == NodeKind.IDENTIFIER)
                {
                    lv = this.find_local(e.text);
                    if (lv == (LVar*)0)
                    {
                        this.unsup(n, g"void cast of non-local\0");
                        return (IRValue*)0;
                    };
                    if (lv.ptr.ty.kind != LK.PTR)
                    {
                        this.unsup(n, g"void cast of non-pointer slot\0");
                        return (IRValue*)0;
                    };
                    pt = lv.ptr.ty.elem;
                    if (pt.kind != LK.PTR & pt.kind != LK.INT & pt.kind != LK.FLOAT & pt.kind != LK.DOUBLE)
                    {
                        this.unsup(n, g"void cast of aggregate\0");
                        return (IRValue*)0;
                    };
                    this.mod.store(this.mod.c_null(pt), lv.ptr);
                    i = this.scopes.len - 1;
                    while (i >= 0)
                    {
                        if (nm_get((NameMap*)this.scopes.items[i], e.text) != (void*)0)
                        {
                            nm_del((NameMap*)this.scopes.items[i], e.text);
                            break;
                        };
                        i--;
                    };
                    return (IRValue*)0;
                };
                ev = this.visit(e);
                if (this.bad) { return (IRValue*)0; };
                if (ev != (IRValue*)0)
                {
                    if (ev.ty.kind == LK.PTR)
                    {
                        this.unsup(n, g"void cast runtime free\0");
                        return (IRValue*)0;
                    };
                };
                return (IRValue*)0;
            };

            // visit_CastExpression (scalar, pointer and integer conversions)
            def x_cast(Node* n) -> IRValue*
            {
                IRType* tt;
                IRType* st;
                IRValue* v;
                IRValue* r;
                LVar* lv;
                TypeSpec* tsp = n.ts;
                bool su, tu;
                tt = this.lower(tsp, true, n.line);
                if (this.nerrors > this.body_errs)
                {
                    this.unsup(n, g"cast type lowering\0");
                    return (IRValue*)0;
                };
                if (tt.kind == LK.VOID)
                {
                    return this.cast_void(n);
                };
                if (n.a.kind == NodeKind.LITERAL & n.a.op == DataType.VOID)
                {
                    if (tt.kind == LK.PTR) { return this.mod.c_null(tt); };
                    if (tt.kind == LK.INT) { return this.mod.c_int(tt, (i64)0); };
                    if (tt.kind == LK.FLOAT | tt.kind == LK.DOUBLE) { return this.mod.c_fp(tt, 0.0); };
                    this.unsup(n, g"void literal cast\0");
                    return (IRValue*)0;
                };
                v = this.visit(n.a);
                if (this.bad) { return (IRValue*)0; };
                if (v == (IRValue*)0)
                {
                    this.unsup(n, g"cast of void value\0");
                    return (IRValue*)0;
                };
                st = v.ty;
                if (lt_eq(st, tt))
                {
                    v = this.cast_endian_fix(v, tsp);
                    v.spec = tsp;
                    return v;
                };
                if (lt_eq(tt, this.t_i8p) & st.kind == LK.PTR)
                {
                    return this.mod.cast(g"bitcast\0", v, this.t_i8p, g"to_void_ptr\0");
                };
                if (lt_eq(st, this.t_i8p) & tt.kind == LK.PTR)
                {
                    return this.mod.cast(g"bitcast\0", v, tt, g"from_void_ptr\0");
                };
                if (st.kind == LK.INT & tt.kind == LK.INT)
                {
                    if (st.width > tt.width) { r = this.mod.cast(g"trunc\0", v, tt, (byte*)0); }
                    elif (st.width < tt.width)
                    {
                        if (n.a.kind == NodeKind.LITERAL)
                        {
                            if (n.a.op == DataType.UINT) { r = this.mod.cast(g"zext\0", v, tt, (byte*)0); }
                            else { r = this.mod.cast(g"sext\0", v, tt, (byte*)0); };
                        }
                        else
                        {
                            su = this.is_uns(v);
                            if (!su & n.a.kind == NodeKind.IDENTIFIER)
                            {
                                lv = this.find_var(n.a.text);
                                if (lv != (LVar*)0)
                                {
                                    if (lv.ts != (TypeSpec*)0) { su = (lv.ts.flags `& TS_SIGNED) == 0; };
                                };
                            };
                            tu = su | tsp.base_type == DataType.UINT | tsp.base_type == DataType.BYTE;
                            if (tsp.base_type == DataType.DATA & (tsp.flags `& TS_SIGNED) == 0) { tu = true; };
                            if (tsp.custom_typename != (byte*)0)
                            {
                                if (tsp.custom_typename[0] == 'u') { tu = true; };
                            };
                            if (tu) { r = this.mod.cast(g"zext\0", v, tt, (byte*)0); }
                            else { r = this.mod.cast(g"sext\0", v, tt, (byte*)0); };
                        };
                    }
                    else { r = v; };
                    r = this.cast_endian_fix(r, tsp);
                    r.spec = tsp;
                    return r;
                };
                if (st.kind == LK.INT & (tt.kind == LK.FLOAT | tt.kind == LK.DOUBLE))
                {
                    return this.mod.cast(g"sitofp\0", v, tt, (byte*)0);
                };
                if ((st.kind == LK.FLOAT | st.kind == LK.DOUBLE) & tt.kind == LK.INT)
                {
                    return this.mod.cast(g"fptosi\0", v, tt, (byte*)0);
                };
                if (st.kind == LK.FLOAT & tt.kind == LK.DOUBLE)
                {
                    return this.mod.cast(g"fpext\0", v, tt, (byte*)0);
                };
                if (st.kind == LK.DOUBLE & tt.kind == LK.FLOAT)
                {
                    return this.mod.cast(g"fptrunc\0", v, tt, (byte*)0);
                };
                if (st.kind == LK.PTR & tt.kind == LK.PTR)
                {
                    return this.mod.cast(g"bitcast\0", v, tt, (byte*)0);
                };
                if (st.kind == LK.INT & tt.kind == LK.PTR)
                {
                    if (st.width < 64) { v = this.mod.cast(g"zext\0", v, this.t_i64, g"int_to_ptr_zext\0"); };
                    return this.mod.cast(g"inttoptr\0", v, tt, g"int_to_ptr\0");
                };
                if (st.kind == LK.PTR & tt.kind == LK.INT)
                {
                    if (st.elem.kind == LK.ARRAY)
                    {
                        this.unsup(n, g"array pointer pack cast\0");
                        return (IRValue*)0;
                    };
                    return this.mod.cast(g"ptrtoint\0", v, tt, g"ptr_to_int\0");
                };
                this.unsup(n, g"cast between these types\0");
                return (IRValue*)0;
            };

            // visit_StringLiteral: g-strings are shared constants, others are built on
            // the stack
            def x_string(Node* n) -> IRValue*
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
                if (src == (byte*)0)
                {
                    this.unsup(n, g"string without text\0");
                    return (IRValue*)0;
                };
                if (len <= 0)
                {
                    while (src[len] != 0)
                    {
                        len++;
                    };
                };
                if (n.op == StorageClass.HEAP)
                {
                    this.unsup(n, g"heap string\0");
                    return (IRValue*)0;
                };
                buf = (byte*)fmalloc((u64)(len + 2));
                this.keep((void*)buf);
                i = 0;
                while (i < len)
                {
                    buf[i] = src[i];
                    i++;
                };
                if (this.null_term)
                {
                    if (len == 0)
                    {
                        buf[0] = (byte)0;
                        len = 1;
                    }
                    elif (buf[len - 1] != (byte)0)
                    {
                        buf[len] = (byte)0;
                        len++;
                    };
                };
                aty = this.mod.t_array(this.t_i8, len);
                if (n.op == StorageClass.GLOBAL)
                {
                    cv = this.mod.c_bytes(aty, buf, len);
                    hit = nm_get(this.gcache, cv.text);
                    if (hit != (void*)0) { return (IRValue*)hit; };
                    this.sc.clear();
                    this.sc.put_str(g".str.\0");
                    this.sc.put_int(this.nstr);
                    this.nstr++;
                    gl = this.mod.add_global(aty, this.sc.mem, cv.text);
                    gl.linkage = this.mod.own(g"internal\0");
                    gl.constant = true;
                    nm_put(this.gcache, this.mod.own(cv.text), (void*)gl.self);
                    return gl.self;
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
                return arr;
            };

            // visit_SizeOf: size in bits as an i32 constant
            def x_sizeof(Node* n) -> IRValue*
            {
                IRType* t;
                IRValue* v;
                FXC_SYMENTRY* e;
                LVar* lv;
                if (n.ts != (TypeSpec*)0)
                {
                    t = this.lower(n.ts, true, n.line);
                    if (this.nerrors > this.body_errs)
                    {
                        this.unsup(n, g"sizeof type lowering\0");
                        return (IRValue*)0;
                    };
                    return this.mod.c_int(this.t_i32, (i64)bits_of(t));
                };
                if (n.a == (Node*)0)
                {
                    this.unsup(n, g"sizeof without target\0");
                    return (IRValue*)0;
                };
                if (n.a.kind == NodeKind.IDENTIFIER)
                {
                    e = st_lookup_any(this.st, n.a.text, this.cur_ns);
                    if (e != (FXC_SYMENTRY*)0)
                    {
                        if (e.kind_id == SymbolKind.STRUCT | e.kind_id == SymbolKind.OBJECT |
                            e.kind_id == SymbolKind.UNION | e.kind_id == SymbolKind.ENUM |
                            e.kind_id == SymbolKind.TYPE)
                        {
                            t = this.resolve_custom(n.a.text);
                            if (t != (IRType*)0) { return this.mod.c_int(this.t_i32, (i64)bits_of(t)); };
                        };
                    };
                    lv = this.find_var(n.a.text);
                    if (lv != (LVar*)0)
                    {
                        if (lv.ts != (TypeSpec*)0)
                        {
                            t = this.lower(lv.ts, true, n.line);
                            if (this.nerrors > this.body_errs)
                            {
                                this.unsup(n, g"sizeof variable type\0");
                                return (IRValue*)0;
                            };
                            return this.mod.c_int(this.t_i32, (i64)bits_of(t));
                        };
                        return this.mod.c_int(this.t_i32, (i64)bits_of(lv.ptr.ty.elem));
                    };
                    this.unsup(n, g"sizeof unresolved name\0");
                    return (IRValue*)0;
                };
                v = this.visit(n.a);
                if (this.bad) { return (IRValue*)0; };
                if (v == (IRValue*)0)
                {
                    this.unsup(n, g"sizeof void\0");
                    return (IRValue*)0;
                };
                return this.mod.c_int(this.t_i32, (i64)bits_of(v.ty));
            };


            // ----------------------------------------------------------
            // Member access, element access, element and member assignment
            // ----------------------------------------------------------

            def sty(IRType* t) -> bool
            {
                return t.kind == LK.STRUCT | t.kind == LK.ISTRUCT;
            };

            def is_struct_ptr_ty(IRType* t) -> bool
            {
                if (t.kind != LK.PTR) { return false; };
                return this.sty(t.elem);
            };

            def sinfo_of(IRType* t) -> SInfo*
            {
                if (t.kind != LK.ISTRUCT) { return (SInfo*)0; };
                return (SInfo*)nm_get(this.structs, t.name);
            };

            def sidx(SInfo* si, byte* name) -> int
            {
                int i;
                while (i < si.n)
                {
                    if (cstr_eq(si.names[i], name)) { return i; };
                    i++;
                };
                return 0 - 1;
            };

            // MemberAccessTypeHandler.is_struct_type
            def is_struct_val(IRType* t) -> bool
            {
                IRType* b = t;
                if (b.kind == LK.PTR) { b = b.elem; };
                if (b.kind != LK.ISTRUCT) { return false; };
                return nm_has(this.structs, b.name);
            };

            // TypeSystem.attach_type_metadata_from_llvm_type: the first type alias of
            // the same LLVM type gives the value its spec
            def meta_from_type(IRValue* v) -> IRValue*
            {
                int i;
                bool uns;
                TypeSpec* as_;
                TypeSpec* ts;
                IRType* at;
                while (i < this.al_tys.len)
                {
                    at = (IRType*)this.al_tys.items[i];
                    if (lt_eq(at, v.ty))
                    {
                        uns = false;
                        as_ = (TypeSpec*)this.al_specs.items[i];
                        if (as_ != (TypeSpec*)0) { uns = (as_.flags `& TS_SIGNED) == 0; };
                        ts = typespec_new();
                        this.keep((void*)ts);
                        if (uns) { ts.base_type = DataType.UINT; }
                        else
                        {
                            ts.base_type = DataType.SINT;
                            ts.flags = TS_SIGNED;
                        };
                        if (v.ty.kind == LK.INT) { ts.bit_width = v.ty.width; };
                        ts.custom_typename = (byte*)this.al_names.items[i];
                        v.spec = ts;
                        return v;
                    };
                    i++;
                };
                return v;
            };

            // ArrayTypeHandler.preserve_array_element_type_metadata
            def elem_meta(IRValue* loaded, IRValue* src) -> IRValue*
            {
                TypeSpec* es = src.espec;
                if (es == (TypeSpec*)0)
                {
                    if (src.spec != (TypeSpec*)0) { es = src.spec.array_elem; };
                };
                if (es != (TypeSpec*)0)
                {
                    if (loaded.spec == (TypeSpec*)0) { loaded.spec = es; };
                    return loaded;
                };
                return this.meta_from_type(loaded);
            };

            // i32 index as the element access code builds it
            def idx_i32(IRValue* v) -> IRValue*
            {
                if (v.ty.kind == LK.INT & v.ty.width != 32)
                {
                    if (v.ty.width > 32) { return this.mod.cast(g"trunc\0", v, this.t_i32, g"idx_trunc\0"); };
                    return this.mod.cast(g"sext\0", v, this.t_i32, g"idx_ext\0");
                };
                return v;
            };

            // Key in enums for a type name, or null
            def find_enum_key(byte* name) -> byte*
            {
                FXC_SYMENTRY* e;
                byte* m;
                byte* key;
                if (nm_has(this.enums, name)) { return name; };
                e = st_lookup_any(this.st, name, this.cur_ns);
                if (e == (FXC_SYMENTRY*)0) { return (byte*)0; };
                if (e.kind_id != SymbolKind.ENUM) { return (byte*)0; };
                m = sym_mangled(e);
                if (!nm_has(this.enums, m))
                {
                    ffree(m);
                    return (byte*)0;
                };
                key = this.mod.own(m);
                ffree(m);
                return key;
            };

            def enum_member(Node* n, byte* key) -> IRValue*
            {
                IRType* ty = (IRType*)nm_get(this.enums, key);
                byte* full = join3(key, g".\0", n.text);
                void* p = nm_get(this.enumvals, full);
                IRGlobal* gl;
                i64* box;
                IRValue* r;
                if (p == (void*)0)
                {
                    ffree(full);
                    this.unsup(n, g"enum member not found\0");
                    return (IRValue*)0;
                };
                if (ty.kind == LK.STRUCT | ty.kind == LK.ISTRUCT | ty.kind == LK.ARRAY)
                {
                    gl = this.mod.find_global(full);
                    ffree(full);
                    if (gl == (IRGlobal*)0)
                    {
                        this.unsup(n, g"enum member not found\0");
                        return (IRValue*)0;
                    };
                    return gl.self;
                };
                ffree(full);
                box = (i64*)p;
                r = this.mod.c_int(ty, box[0]);
                return r;
            };

            // StructFieldAccess for a field of a struct reached through a pointer
            def struct_field(Node* n, Node* objn, byte* field) -> IRValue*
            {
                IRValue* inst = this.visit(objn);
                IRValue* fp;
                LVar* lv;
                SInfo* si;
                IRType* pe;
                int idx;
                if (this.bad) { return (IRValue*)0; };
                if (inst == (IRValue*)0)
                {
                    this.unsup(n, g"void struct instance\0");
                    return (IRValue*)0;
                };
                if (objn.kind == NodeKind.IDENTIFIER)
                {
                    if (inst.ty.kind != LK.PTR & this.sty(inst.ty))
                    {
                        lv = this.find_var(objn.text);
                        if (lv != (LVar*)0)
                        {
                            if (this.is_struct_ptr_ty(lv.ptr.ty)) { inst = lv.ptr; };
                        };
                    };
                };
                if (inst.ty.kind == LK.PTR & this.sty(inst.ty.elem))
                {
                    pe = inst.ty.elem;
                    si = this.sinfo_of(pe);
                    if (si == (SInfo*)0)
                    {
                        this.unsup(n, g"field of unnamed struct\0");
                        return (IRValue*)0;
                    };
                    idx = this.sidx(si, field);
                    if (idx < 0)
                    {
                        this.unsup(n, g"field not found\0");
                        return (IRValue*)0;
                    };
                    this.sc.clear();
                    this.sc.put_str(field);
                    this.sc.put_str(g"_ptr\0");
                    fp = this.mod.gep_field(inst, idx, true, this.sc.mem);
                    if (fp.ty.elem.kind == LK.ARRAY | this.sty(fp.ty.elem)) { return fp; };
                    return this.mod.load(fp, field);
                };
                this.unsup(n, g"field access on struct value\0");
                return (IRValue*)0;
            };

            // visit_MemberAccess
            def x_member(Node* n) -> IRValue*
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
                if (o.kind == NodeKind.IDENTIFIER)
                {
                    key = this.find_enum_key(o.text);
                    if (key != (byte*)0) { return this.enum_member(n, key); };
                    lv = this.find_var(o.text);
                    if (lv != (LVar*)0)
                    {
                        if (lv.ts != (TypeSpec*)0)
                        {
                            if (lv.ts.custom_typename != (byte*)0)
                            {
                                key = this.find_enum_key(lv.ts.custom_typename);
                                if (key != (byte*)0) { return this.enum_member(n, key); };
                            };
                        };
                    };
                };
                prev = this.in_member;
                this.in_member = true;
                obj = this.visit(o);
                if (this.bad)
                {
                    this.in_member = prev;
                    return (IRValue*)0;
                };
                if (obj == (IRValue*)0)
                {
                    this.in_member = prev;
                    this.unsup(n, g"void member access object\0");
                    return (IRValue*)0;
                };
                if (this.is_struct_val(obj.ty))
                {
                    r = this.struct_field(n, o, n.text);
                    this.in_member = prev;
                    return r;
                };
                obj2 = this.visit(o);
                this.in_member = prev;
                if (this.bad) { return (IRValue*)0; };
                if (obj2 == (IRValue*)0)
                {
                    this.unsup(n, g"void member access object\0");
                    return (IRValue*)0;
                };
                if (o.kind == NodeKind.IDENTIFIER)
                {
                    if (cstr_eq(o.text, g"this\0"))
                    {
                        if (obj2.ty.kind == LK.PTR & obj2.ty.elem.kind == LK.PTR & obj2.ty.elem.elem.kind == LK.STRUCT)
                        {
                            obj2 = this.mod.load(obj2, g"this_ptr\0");
                        };
                    };
                };
                if (obj2.ty.kind == LK.PTR & obj2.ty.elem.kind == LK.PTR)
                {
                    if (this.is_struct_ptr_ty(obj2.ty.elem)) { obj2 = this.mod.load(obj2, g"deref_struct_ptr\0"); };
                };
                if (this.is_struct_ptr_ty(obj2.ty))
                {
                    si = this.sinfo_of(obj2.ty.elem);
                    if (si == (SInfo*)0)
                    {
                        this.unsup(n, g"member of union or unnamed struct\0");
                        return (IRValue*)0;
                    };
                    idx = this.sidx(si, n.text);
                    if (idx < 0)
                    {
                        this.unsup(n, g"member not found\0");
                        return (IRValue*)0;
                    };
                    mp = this.mod.gep_field(obj2, idx, true, (byte*)0);
                    pe = mp.ty.elem;
                    if (pe.kind == LK.ARRAY)
                    {
                        if (si.specs[idx] != (TypeSpec*)0) { mp.espec = si.specs[idx].array_elem; };
                        return mp;
                    };
                    if (this.sty(pe)) { return mp; };
                    ld = this.mod.load(mp, (byte*)0);
                    if (si.specs[idx] != (TypeSpec*)0)
                    {
                        ld.spec = si.specs[idx];
                        return ld;
                    };
                    return this.meta_from_type(ld);
                };
                this.unsup(n, g"member access on unsupported type\0");
                return (IRValue*)0;
            };

            // _member_access_get_ptr: address of a member, without loading it
            def member_ptr(Node* n) -> IRValue*
            {
                Node* o = n.a;
                IRValue* obj;
                LVar* lv;
                SInfo* si;
                int idx;
                if (o.kind == NodeKind.IDENTIFIER)
                {
                    if (cstr_eq(o.text, g"this\0"))
                    {
                        obj = this.visit(o);
                        if (this.bad) { return (IRValue*)0; };
                        if (obj.ty.kind == LK.PTR & obj.ty.elem.kind == LK.PTR & obj.ty.elem.elem.kind == LK.STRUCT)
                        {
                            obj = this.mod.load(obj, g"this_ptr\0");
                        };
                    }
                    else
                    {
                        lv = this.find_local(o.text);
                        if (lv == (LVar*)0)
                        {
                            // Global object: the base evaluates the identifier as an expression
                            lv = this.find_global_var(o.text);
                            if (lv == (LVar*)0)
                            {
                                this.unsup(n, g"member of non-local\0");
                                return (IRValue*)0;
                            };
                            if (lv.ptr.ty.elem.kind == LK.STRUCT | lv.ptr.ty.elem.kind == LK.ISTRUCT)
                            {
                                obj = lv.ptr;
                            }
                            else
                            {
                                obj = this.visit(o);
                                if (this.bad) { return (IRValue*)0; };
                            };
                        }
                        else { obj = lv.ptr; };
                    };
                }
                else
                {
                    obj = this.visit(o);
                    if (this.bad) { return (IRValue*)0; };
                };
                if (obj == (IRValue*)0)
                {
                    this.unsup(n, g"void member object\0");
                    return (IRValue*)0;
                };
                if (obj.ty.kind == LK.PTR & obj.ty.elem.kind == LK.PTR)
                {
                    if (this.is_struct_ptr_ty(obj.ty.elem)) { obj = this.mod.load(obj, g"struct_ptr\0"); };
                };
                if (this.is_struct_ptr_ty(obj.ty))
                {
                    si = this.sinfo_of(obj.ty.elem);
                    if (si == (SInfo*)0)
                    {
                        this.unsup(n, g"member pointer of unnamed struct\0");
                        return (IRValue*)0;
                    };
                    idx = this.sidx(si, n.text);
                    if (idx < 0)
                    {
                        this.unsup(n, g"member not found\0");
                        return (IRValue*)0;
                    };
                    return this.mod.gep_field(obj, idx, true, (byte*)0);
                };
                this.unsup(n, g"member pointer of non-struct\0");
                return (IRValue*)0;
            };

            // True when a looks like an indexable pointer slot that must be loaded first
            def needs_ptr_load(IRValue* a) -> bool
            {
                TypeSpec* ts = a.spec;
                int depth = 1;
                bool is_arr = false;
                if (ts != (TypeSpec*)0)
                {
                    depth = ts.pointer_depth;
                    is_arr = (ts.flags `& TS_ARRAY) != 0;
                };
                if (is_arr | depth > 1) { return false; };
                if ((a.flags `& (VF_ALLOCA `| VF_GLOBAL)) == 0) { return false; };
                if (a.ty.kind != LK.PTR) { return false; };
                if (a.ty.elem.kind != LK.PTR) { return false; };
                if (a.ty.elem.elem.kind == LK.ARRAY | a.ty.elem.elem.kind == LK.PTR) { return false; };
                return true;
            };

            def is_dict_ty(IRType* t) -> bool
            {
                IRType* b = t;
                if (b.kind == LK.PTR) { b = b.elem; };
                if (b.kind != LK.STRUCT) { return false; };
                if (b.nitems != 3) { return false; };
                return b.items[0].kind == LK.ARRAY & b.items[1].kind == LK.ARRAY & b.items[2].kind == LK.INT;
            };

            // visit_ArrayAccess
            def x_index(Node* n) -> IRValue*
            {
                IRValue* arr;
                IRValue* idx;
                IRValue* gp;
                IRValue* ld;
                IRValue* t1;
                IRValue* t2;
                IRValue* t3;
                if (n.b.kind == NodeKind.RANGE_EXPRESSION)
                {
                    this.unsup(n, g"range index\0");
                    return (IRValue*)0;
                };
                arr = this.visit(n.a);
                if (this.bad) { return (IRValue*)0; };
                if (arr == (IRValue*)0)
                {
                    this.unsup(n, g"void indexed value\0");
                    return (IRValue*)0;
                };
                if (this.is_dict_ty(arr.ty))
                {
                    this.unsup(n, g"dict access\0");
                    return (IRValue*)0;
                };
                if (this.needs_ptr_load(arr)) { arr = this.mod.load(arr, g"ptr_loaded_for_access\0"); };
                idx = this.visit(n.b);
                if (this.bad) { return (IRValue*)0; };
                if (idx == (IRValue*)0)
                {
                    this.unsup(n, g"void index\0");
                    return (IRValue*)0;
                };
                idx = this.idx_i32(idx);
                if ((arr.flags `& VF_GLOBAL) != 0 | (arr.ty.kind == LK.PTR & arr.ty.elem.kind == LK.ARRAY))
                {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = idx;
                    gp = this.mod.gep(arr, this.mod.ia, 2, true, g"array_gep\0");
                    if (gp.ty.elem.kind == LK.ARRAY | this.sty(gp.ty.elem)) { return gp; };
                    ld = this.mod.load(gp, g"array_load\0");
                    return this.elem_meta(ld, arr);
                };
                if (arr.ty.kind == LK.PTR)
                {
                    gp = this.mod.gep_ptr(arr, idx, true, g"ptr_gep\0");
                    if (this.sty(gp.ty.elem)) { return gp; };
                    ld = this.mod.load(gp, g"ptr_load\0");
                    return this.elem_meta(ld, arr);
                };
                if (arr.ty.kind == LK.INT)
                {
                    if (idx.ty.width != 64) { t1 = this.mod.cast(g"sext\0", idx, this.t_i64, g"idx_i64\0"); }
                    else { t1 = idx; };
                    t2 = this.mod.binop(g"mul\0", t1, this.mod.c_int(this.t_i64, (i64)8), g"byte_shift\0");
                    if (arr.ty.width != 64) { t3 = this.mod.cast(g"zext\0", arr, this.t_i64, g"val_i64\0"); }
                    else { t3 = arr; };
                    t3 = this.mod.binop(g"lshr\0", t3, t2, g"byte_shr\0");
                    return this.mod.cast(g"trunc\0", t3, this.t_i8, g"byte_extract\0");
                };
                this.unsup(n, g"element access type\0");
                return (IRValue*)0;
            };

            // _array_access_get_ptr: address of an element, for ++ and --
            def index_ptr(Node* n) -> IRValue*
            {
                IRValue* arr = this.visit(n.a);
                IRValue* idx;
                if (this.bad) { return (IRValue*)0; };
                if (arr == (IRValue*)0)
                {
                    this.unsup(n, g"void indexed value\0");
                    return (IRValue*)0;
                };
                if (this.needs_ptr_load(arr)) { arr = this.mod.load(arr, g"ptr_loaded_for_inc\0"); };
                idx = this.visit(n.b);
                if (this.bad) { return (IRValue*)0; };
                if (idx == (IRValue*)0)
                {
                    this.unsup(n, g"void index\0");
                    return (IRValue*)0;
                };
                idx = this.idx_i32(idx);
                if ((arr.flags `& VF_GLOBAL) != 0 | (arr.ty.kind == LK.PTR & arr.ty.elem.kind == LK.ARRAY))
                {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = idx;
                    return this.mod.gep(arr, this.mod.ia, 2, true, g"inc_gep\0");
                };
                if (arr.ty.kind == LK.PTR) { return this.mod.gep_ptr(arr, idx, true, g"inc_gep\0"); };
                this.unsup(n, g"element pointer type\0");
                return (IRValue*)0;
            };

            // First character of a string literal as an i8 constant
            def first_char(Node* s) -> IRValue*
            {
                int c = 0;
                if (s.text != (byte*)0)
                {
                    if (s.ival > (i64)0 | s.text[0] != (byte)0) { c = (int)s.text[0]; };
                };
                return this.mod.c_int(this.t_i8, (i64)c);
            };

            // AssignmentTypeHandler.handle_member_assignment
            def assign_member(Node* t, IRValue* val0, Node* vexpr) -> IRValue*
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
                if (o.kind == NodeKind.IDENTIFIER)
                {
                    if (this.find_local(o.text) == (LVar*)0)
                    {
                        glob = this.find_global_var(o.text) != (LVar*)0;
                    };
                };
                if (glob)
                {
                    lv = this.find_global_var(o.text);
                    if (lv.ptr.ty.elem.kind == LK.STRUCT | lv.ptr.ty.elem.kind == LK.ISTRUCT)
                    {
                        // Struct global: base uses module.globals[name], the pointer itself
                        obj = lv.ptr;
                    }
                    else
                    {
                        // Global object: the base evaluates the identifier as an expression
                        obj = this.visit(o);
                        if (this.bad) { return (IRValue*)0; };
                    };
                }
                elif (o.kind == NodeKind.IDENTIFIER)
                {
                    lv = this.find_var(o.text);
                    if (lv == (LVar*)0)
                    {
                        this.unsup(t, g"member assignment to non-local\0");
                        return (IRValue*)0;
                    };
                    obj = lv.ptr;
                    if (obj.ty.kind == LK.PTR & obj.ty.elem.kind == LK.PTR)
                    {
                        if (this.is_struct_ptr_ty(obj.ty.elem))
                        {
                            this.sc.clear();
                            this.sc.put_str(o.text);
                            this.sc.put_str(g"_ptr\0");
                            obj = this.mod.load(obj, this.sc.mem);
                        };
                    };
                }
                elif (o.kind == NodeKind.MEMBER_ACCESS)
                {
                    obj = this.member_ptr(o);
                    if (this.bad) { return (IRValue*)0; };
                }
                else
                {
                    obj = this.visit(o);
                    if (this.bad) { return (IRValue*)0; };
                };
                if (obj == (IRValue*)0)
                {
                    this.unsup(t, g"void member assignment object\0");
                    return (IRValue*)0;
                };
                if (obj.ty.kind == LK.PTR & obj.ty.elem.kind == LK.PTR)
                {
                    if (this.is_struct_ptr_ty(obj.ty.elem)) { obj = this.mod.load(obj, g"struct_ptr\0"); };
                };
                if (!this.is_struct_ptr_ty(obj.ty))
                {
                    this.unsup(t, g"member assignment to non-struct\0");
                    return (IRValue*)0;
                };
                si = this.sinfo_of(obj.ty.elem);
                if (si == (SInfo*)0)
                {
                    this.unsup(t, g"member assignment to union or unnamed struct\0");
                    return (IRValue*)0;
                };
                idx = this.sidx(si, t.text);
                if (idx < 0)
                {
                    this.unsup(t, g"member not found\0");
                    return (IRValue*)0;
                };
                mp = this.mod.gep_field(obj, idx, true, (byte*)0);
                mt = mp.ty.elem;
                if (vexpr.kind == NodeKind.ARRAY_LITERAL & mt.kind == LK.ARRAY)
                {
                    this.unsup(t, g"array literal to member\0");
                    return (IRValue*)0;
                };
                if (val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY & mt.kind == LK.ARRAY)
                {
                    if (lt_eq(val.ty.elem.elem, mt.elem) & val.ty.elem.count <= mt.count)
                    {
                        this.unsup(t, g"array widening member assignment\0");
                        return (IRValue*)0;
                    };
                };
                if (val.ty.kind == LK.PTR & mt.kind != LK.PTR)
                {
                    if (lt_eq(val.ty.elem, mt)) { val = this.mod.load(val, g"obj_val_deref\0"); };
                };
                val = this.convert_assign(val, mt);
                if (this.bad) { return (IRValue*)0; };
                this.mod.store(val, mp);
                return val;
            };

            // AssignmentTypeHandler.handle_array_element_assignment and the struct
            // member array path of visit_Assignment
            def assign_index(Node* t, IRValue* val0, Node* vexpr) -> IRValue*
            {
                Node* an = t.a;
                Node* ix = t.b;
                IRValue* val = val0;
                IRValue* arr;
                IRValue* idx;
                IRValue* ep;
                IRValue* mp;
                IRType* et;
                if (an.kind == NodeKind.MEMBER_ACCESS)
                {
                    mp = this.member_ptr(an);
                    if (this.bad) { return (IRValue*)0; };
                    if (mp.ty.kind == LK.PTR & mp.ty.elem.kind == LK.ARRAY)
                    {
                        if (ix.kind == NodeKind.RANGE_EXPRESSION)
                        {
                            this.unsup(t, g"member slice assignment\0");
                            return (IRValue*)0;
                        };
                        idx = this.visit(ix);
                        if (this.bad) { return (IRValue*)0; };
                        idx = this.idx_i32(idx);
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = idx;
                        ep = this.mod.gep(mp, this.mod.ia, 2, true, (byte*)0);
                        et = mp.ty.elem.elem;
                        if (!lt_eq(val.ty, et))
                        {
                            if (val.ty.kind == LK.INT & et.kind == LK.INT)
                            {
                                if (val.ty.width > et.width) { val = this.mod.cast(g"trunc\0", val, et, g"val_trunc\0"); }
                                else { val = this.mod.cast(g"sext\0", val, et, g"val_ext\0"); };
                            }
                            elif (val.ty.kind == LK.PTR & lt_eq(val.ty.elem, et))
                            {
                                val = this.mod.load(val, g"struct_elem_load\0");
                            }
                            elif (val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY & et.kind == LK.PTR)
                            {
                                if (lt_eq(val.ty.elem.elem, et.elem))
                                {
                                    this.mod.ia[0] = this.ci32(0);
                                    this.mod.ia[1] = this.ci32(0);
                                    val = this.mod.gep(val, this.mod.ia, 2, true, g"arr_decay\0");
                                };
                            };
                        };
                        this.mod.store(val, ep);
                        return val;
                    };
                };
                arr = this.visit(an);
                if (this.bad) { return (IRValue*)0; };
                if (arr == (IRValue*)0)
                {
                    this.unsup(t, g"void indexed target\0");
                    return (IRValue*)0;
                };
                if (ix.kind == NodeKind.RANGE_EXPRESSION)
                {
                    this.unsup(t, g"slice assignment\0");
                    return (IRValue*)0;
                };
                idx = this.visit(ix);
                if (this.bad) { return (IRValue*)0; };
                if (idx == (IRValue*)0)
                {
                    this.unsup(t, g"void index\0");
                    return (IRValue*)0;
                };
                if (arr.ty.kind == LK.PTR & arr.ty.elem.kind == LK.ARRAY)
                {
                    this.mod.ia[0] = this.ci32(0);
                    this.mod.ia[1] = idx;
                    ep = this.mod.gep(arr, this.mod.ia, 2, true, (byte*)0);
                    et = arr.ty.elem.elem;
                    if (vexpr.kind == NodeKind.STRING_LITERAL & et.kind == LK.INT & et.width == 8)
                    {
                        val = this.first_char(vexpr);
                    }
                    elif (val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY & et.kind == LK.PTR)
                    {
                        if (et.elem.kind == LK.INT & et.elem.width == 8)
                        {
                            this.mod.ia[0] = this.ci32(0);
                            this.mod.ia[1] = this.ci32(0);
                            val = this.mod.gep(val, this.mod.ia, 2, true, g"str_to_ptr\0");
                        };
                    };
                    if (val.ty.kind == LK.PTR & et.kind != LK.PTR)
                    {
                        if (this.sty(val.ty.elem) & lt_eq(val.ty.elem, et)) { val = this.mod.load(val, g"struct_elem_load\0"); }
                        else { ep = this.mod.cast(g"bitcast\0", ep, this.ptr_of(val.ty), g"void_arr_elem_ptr\0"); };
                    }
                    elif (val.ty.kind == LK.PTR & et.kind == LK.PTR)
                    {
                        if (!lt_eq(val.ty, et)) { val = this.mod.cast(g"bitcast\0", val, et, g"ptr_cast\0"); };
                    };
                    val = this.convert_assign(val, et);
                    if (this.bad) { return (IRValue*)0; };
                    this.mod.store(val, ep);
                    return val;
                };
                if (arr.ty.kind == LK.PTR)
                {
                    ep = this.mod.gep_ptr(arr, idx, true, (byte*)0);
                    et = arr.ty.elem;
                    if (val.ty.kind == LK.PTR & val.ty.elem.kind == LK.ARRAY & et.kind == LK.PTR & et.elem.kind == LK.INT & et.elem.width == 8)
                    {
                        this.mod.ia[0] = this.ci32(0);
                        this.mod.ia[1] = this.ci32(0);
                        val = this.mod.gep(val, this.mod.ia, 2, true, g"str_to_ptr\0");
                    }
                    elif (vexpr.kind == NodeKind.STRING_LITERAL & et.kind == LK.INT & et.width == 8)
                    {
                        val = this.first_char(vexpr);
                    };
                    if (val.ty.kind == LK.PTR & et.kind == LK.PTR)
                    {
                        if (!lt_eq(val.ty, et)) { val = this.mod.cast(g"bitcast\0", val, et, g"ptr_cast\0"); };
                    };
                    if (val.ty.kind == LK.PTR & et.kind != LK.PTR)
                    {
                        if (!lt_eq(val.ty.elem, et))
                        {
                            ep = this.mod.cast(g"bitcast\0", ep, this.ptr_of(val.ty), g"void_arr_elem_ptr\0");
                        };
                    };
                    val = this.convert_assign(val, et);
                    if (this.bad) { return (IRValue*)0; };
                    this.mod.store(val, ep);
                    return val;
                };
                this.unsup(t, g"index assignment on non-pointer\0");
                return (IRValue*)0;
            };

            // handle_pointer_deref_assignment
            def assign_deref(Node* t, IRValue* val0) -> IRValue*
            {
                IRValue* p = this.visit(t.a);
                IRValue* val = val0;
                if (this.bad) { return (IRValue*)0; };
                if (p == (IRValue*)0)
                {
                    this.unsup(t, g"void dereference target\0");
                    return (IRValue*)0;
                };
                if (p.ty.kind == LK.PTR & p.ty.elem.kind == LK.PTR & p.ty.elem.elem.kind == LK.PTR)
                {
                    p = this.mod.load(p, g"deref_ptr_loaded\0");
                };
                if (p.ty.kind != LK.PTR)
                {
                    this.unsup(t, g"dereference assignment to non-pointer\0");
                    return (IRValue*)0;
                };
                val = this.convert_assign(val, p.ty.elem);
                if (this.bad) { return (IRValue*)0; };
                if (!lt_eq(val.ty, p.ty.elem)) { p = this.mod.cast(g"bitcast\0", p, this.ptr_of(val.ty), (byte*)0); };
                this.mod.store(val, p);
                return val;
            };

            // Dispatches one node. Statements return null.
            def visit(Node* n) -> IRValue*
            {
                int k;
                IRValue* r;
                if (n == (Node*)0) { return (IRValue*)0; };
                if (this.bad) { return (IRValue*)0; };
                k = n.kind;
                if (k == NodeKind.LITERAL) { return this.x_literal(n); };
                if (k == NodeKind.IDENTIFIER) { return this.x_ident(n); };
                if (k == NodeKind.BINARY_OP) { return this.x_binary(n); };
                if (k == NodeKind.FUNCTION_CALL) { return this.x_call(n); };
                if (k == NodeKind.ASSIGNMENT) { return this.x_assign(n); };
                if (k == NodeKind.COMPOUND_ASSIGNMENT) { return this.x_compound(n); };
                if (k == NodeKind.NOT_NULL) { return this.x_notnull(n); };
                if (k == NodeKind.IN_EXPRESSION) { return this.x_in(n); };
                if (k == NodeKind.INLINE_ASM) { return this.x_asm(n); };
                if (k == NodeKind.METHOD_CALL) { return this.x_method(n); };
                if (k == NodeKind.UNARY_OP) { return this.x_unary(n); };
                if (k == NodeKind.POINTER_DEREF) { return this.x_deref(n); };
                if (k == NodeKind.ADDRESS_OF) { return this.x_addrof(n); };
                if (k == NodeKind.CAST_EXPRESSION | k == NodeKind.TYPE_CONVERT_EXPRESSION) { return this.x_cast(n); };
                if (k == NodeKind.STRING_LITERAL) { return this.x_string(n); };
                if (k == NodeKind.SIZE_OF) { return this.x_sizeof(n); };
                if (k == NodeKind.MEMBER_ACCESS) { return this.x_member(n); };
                if (k == NodeKind.ARRAY_ACCESS) { return this.x_index(n); };
                if (k == NodeKind.VARIABLE_DECLARATION) { return this.x_vardecl(n); };
                if (k == NodeKind.EXPRESSION_STATEMENT) { return this.visit(n.a); };
                if (k == NodeKind.BLOCK) { this.s_block(n); return (IRValue*)0; };
                if (k == NodeKind.IF_STATEMENT) { this.s_if(n); return (IRValue*)0; };
                if (k == NodeKind.SWITCH_STATEMENT) { this.s_switch(n); return (IRValue*)0; };
                if (k == NodeKind.DEFER_STATEMENT)
                {
                    if (this.defers == (PtrVec*)0) { this.defers = pv_new(); };
                    pv_push(this.defers, (void*)n);
                    return (IRValue*)0;
                };
                if (k == NodeKind.NORETURN_STATEMENT) { this.s_noreturn(); return (IRValue*)0; };
                if (k == NodeKind.TRY_BLOCK) { this.s_try(n); return (IRValue*)0; };
                if (k == NodeKind.WHILE_LOOP) { this.s_while(n); return (IRValue*)0; };
                if (k == NodeKind.DO_LOOP) { this.s_do(n); return (IRValue*)0; };
                if (k == NodeKind.DO_WHILE_LOOP) { this.s_dowhile(n); return (IRValue*)0; };
                if (k == NodeKind.FOR_LOOP) { this.s_for(n); return (IRValue*)0; };
                if (k == NodeKind.RETURN_STATEMENT) { this.s_return(n); return (IRValue*)0; };
                if (k == NodeKind.BREAK_STATEMENT)
                {
                    if (this.brk == (IRBlock*)0)
                    {
                        this.unsup(n, g"break outside loop\0");
                        return (IRValue*)0;
                    };
                    if (!this.mod.is_terminated()) { this.mod.br(this.brk); };
                    return (IRValue*)0;
                };
                if (k == NodeKind.CONTINUE_STATEMENT)
                {
                    if (this.cont == (IRBlock*)0)
                    {
                        this.unsup(n, g"continue outside loop\0");
                        return (IRValue*)0;
                    };
                    if (!this.mod.is_terminated()) { this.mod.br(this.cont); };
                    return (IRValue*)0;
                };
                this.unsup(n, node_kind_name(k));
                return (IRValue*)0;
            };

            // ----------------------------------------------------------
            // Function bodies
            // ----------------------------------------------------------

            // visit_FunctionDef after the declaration: entry block, parameters, body
            def gen_body(Node* fd, IRFunc* f, byte* obj) -> void
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
                if (fd.ts2 != (TypeSpec*)0)
                {
                    this.unsup(fd, g"dual return function\0");
                    return;
                };
                if ((fd.flags `& NF_VARIADIC) != 0)
                {
                    this.unsup(fd, g"variadic function\0");
                    return;
                };
                if ((fd.flags `& NF_RECURSIVE) != 0)
                {
                    this.unsup(fd, g"recursive function\0");
                    return;
                };
                ebk = this.mod.append_block(f, g"entry\0");
                this.mod.position(f, ebk);
                this.mod.set_entry(ebk);
                this.push_scope();
                if (obj != (byte*)0)
                {
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
                        if (p.text != (byte*)0) { this.mod.rename_arg(f, i + 1, p.text); }
                        else
                        {
                            this.sc.clear();
                            this.sc.put_str(g"arg\0");
                            this.sc.put_int(i);
                            this.mod.rename_arg(f, i + 1, this.sc.mem);
                        };
                        i++;
                    };
                    this.define_var(g"this\0", f.args[0], this_ts);
                };
                i = 0;
                while (i < np)
                {
                    p = node_child(fd, 0, i);
                    if (p.text != (byte*)0) { pname = p.text; }
                    else
                    {
                        this.sc.clear();
                        this.sc.put_str(g"arg\0");
                        this.sc.put_int(i);
                        pname = this.mod.own(this.sc.mem);
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
                if (this.bad) { return; };
                if (!this.mod.is_terminated())
                {
                    if (obj != (byte*)0 & cstr_eq(fd.text, g"__init\0")) { this.mod.ret(f.args[0]); }
                    elif (this.fret.kind == LK.VOID) { this.mod.ret_void(); }
                    elif (this.mod.cb.lines.len == 0) { this.mod.unreachable(); }
                    else { this.unsup(fd, g"function must end with return\0"); };
                };
                return;
            };

            // Generates the body of fd into f. On failure the function stays a declaration.
            def run_body(Node* fd, IRFunc* f, byte* ns, byte* obj) -> void
            {
                int i;
                byte* prev = this.cur_obj;
                this.set_ns(ns);
                if (obj != (byte*)0) { this.cur_obj = this.mod.own(obj); };
                this.gen_body(fd, f, obj);
                this.cur_obj = prev;
                if (this.bad)
                {
                    this.nskipped++;
                    f.is_decl = true;
                }
                else { this.nbodies++; };
                return;
            };

            // Generates the method bodies of an object definition
            def object_bodies(Node* od, byte* ns) -> void
            {
                byte* oname;
                byte* mn;
                byte* full;
                Node* m;
                IRFunc* f;
                int i;
                if (this.is_template(od)) { return; };
                oname = mangle_namespace_name(ns, od.text);
                while (i < node_count(od, 1))
                {
                    m = node_child(od, 1, i);
                    i++;
                    if (m.text == (byte*)0) { continue; };
                    if ((m.flags `& NF_TEMPLATE) != 0) { continue; };
                    if ((m.flags `& NF_PROTOTYPE) != 0) { continue; };
                    if (m.a == (Node*)0) { continue; };
                    this.cur_obj = this.mod.own(oname);
                    mn = this.mangled_name(m.text, m);
                    this.cur_obj = (byte*)0;
                    full = join3(oname, g".\0", mn);
                    f = this.mod.find_function(full);
                    ffree(mn);
                    ffree(full);
                    if (f == (IRFunc*)0) { continue; };
                    if (!f.is_decl) { continue; };
                    this.run_body(m, f, ns, oname);
                };
                ffree(oname);
                return;
            };

            // Walks the program in declaration order and generates the bodies
            def bodies_pass(Node* n0, byte* ns) -> void
            {
                Node* n = this.unwrap(n0);
                int k = n.kind;
                int s, c, e, j;
                byte* full;
                IRFunc* f;
                byte* mn;
                byte* base;
                if (k == NodeKind.FUNCTION_DEF)
                {
                    if (n.text == (byte*)0) { return; };
                    if ((n.flags `& NF_TEMPLATE) != 0) { return; };
                    if ((n.flags `& NF_PROTOTYPE) != 0) { return; };
                    if (n.a == (Node*)0) { return; };
                    base = mangle_namespace_name(ns, n.text);
                    if ((n.flags `& NF_NO_MANGLE) != 0) { mn = ts_dup(base); }
                    else { mn = this.mangled_name(base, n); };
                    f = this.mod.find_function(mn);
                    ffree(base);
                    ffree(mn);
                    if (f == (IRFunc*)0) { return; };
                    if (!f.is_decl) { return; };
                    this.run_body(n, f, ns, (byte*)0);
                }
                elif (k == NodeKind.OBJECT_DEF) { this.object_bodies(n, ns); }
                elif (k == NodeKind.EXPORT_BLOCK)
                {
                    c = node_count(n, 0);
                    while (e < c)
                    {
                        this.bodies_pass(node_child(n, 0, e), ns);
                        e++;
                    };
                }
                elif (k == NodeKind.NAMESPACE_DEF)
                {
                    full = this.join_ns(ns, n.text);
                    this.set_ns(full);
                    while (j < 3)
                    {
                        // nested namespaces, functions, then objects
                        if (j == 0) { s = 7; }
                        elif (j == 1) { s = 0; }
                        else { s = 2; };
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
                };
                return;
            };

            def gen_program(Node* prog) -> void
            {
                int i;
                int n = node_count(prog, 0);
                Node* s;
                byte* root = ts_dup(g"\0");
                while (i < n)
                {
                    s = node_child(prog, 0, i);
                    if (s.kind == NodeKind.USING_STATEMENT) { st_add_using_namespace(this.st, s.text); }
                    elif (s.kind == NodeKind.NOT_USING_STATEMENT) { st_remove_using_namespace(this.st, s.text); };
                    i++;
                };
                i = 0;
                while (i < n)
                {
                    this.collect_consts(node_child(prog, 0, i), root);
                    i++;
                };
                i = 0;
                while (i < n)
                {
                    this.types_pass(node_child(prog, 0, i), root);
                    i++;
                };
                i = 0;
                while (i < n)
                {
                    this.decls_pass(node_child(prog, 0, i), root);
                    i++;
                };
                i = 0;
                while (i < n)
                {
                    this.bodies_pass(node_child(prog, 0, i), root);
                    i++;
                };
                ffree(root);
                this.main_stubs();
                return;
            };

            // Defines whichever of main() and main(int, byte**) the program left undefined,
            // so FRTStartup can call either form
            def main_stubs() -> void
            {
                IRFunc* m0 = this.mod.find_function(g"main__0__ret_intE1\0");
                IRFunc* m2 = this.mod.find_function(g"main__2__intE1__byteE1_ptr2__ret_intE1\0");
                IRBlock* eb;
                IRValue* r;
                if (m0 == (IRFunc*)0 | m2 == (IRFunc*)0) { return; };
                if (m0.is_decl & !m2.is_decl)
                {
                    eb = this.mod.append_block(m0, g"entry\0");
                    this.mod.position(m0, eb);
                    this.mod.set_entry(eb);
                    this.mod.ia[0] = this.mod.c_int(this.t_i32, (i64)0);
                    this.mod.ia[1] = this.mod.c_null(m2.ftype.items[1]);
                    r = this.mod.call(m2.self, this.mod.ia, 2, (byte*)0);
                    this.mod.ret(r);
                    m0.is_decl = false;
                }
                elif (m2.is_decl & !m0.is_decl)
                {
                    eb = this.mod.append_block(m2, g"entry\0");
                    this.mod.position(m2, eb);
                    this.mod.set_entry(eb);
                    r = this.mod.call(m0.self, this.mod.ia, 0, (byte*)0);
                    this.mod.ret(r);
                    m2.is_decl = false;
                };
                return;
            };
        };
    };
};

#endif;
