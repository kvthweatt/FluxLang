// Author: Karac V. Thweatt
//
// ftyper.fx - Flux expression typer (bootstrap)
//
// Derives the type of every expression node as a TypeSpec, following the
// rules fcodegen.py uses to derive LLVM types:
//     literals          infer_int_width, DataType to width (visit_Literal)
//     identifiers       symbol table, __expr promotion (visit_Identifier)
//     binary operators  operator overloads, pointer arithmetic, array
//                       concatenation, float/int promotion, comparisons
//                       (visit_BinaryOp, CoercionContext)
//     unary operators   visit_UnaryOp
//     calls             overload selection (TypeResolver._resolve_from_overloads),
//                       constructor sugar, function pointers, type functions
//     members           struct, object and union members, enum constants
//     casts, indexing, slices, address-of, dereference, ternary, ...
//
// The result of every typed expression node is stored in Node.ety. A type
// that cannot be derived is left null and counted, never reported as an
// error: this pass derives types, it does not check them.
//
// Ownership: TypeSpecs made here live in the typer arena and are freed by
// __exit. They never own their children (array sizes made here are owned
// separately). Types borrowed from the AST (declared types, member types)
// are never freed by the typer.
//
// Usage:
//     ExprTyper ty(st);
//     defer ty.__exit();
//     ty.walk_program(prog);
//
#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_TYPES
#import "ftypesys.fx";
#endif;

#ifndef FLUX_CHECK
#import "fcheck.fx";
#endif;

#ifndef FLUX_TYPER
#def FLUX_TYPER 1;

using flux::ast;
using flux::preprocessor;
using flux::types;
using flux::check;

namespace flux
{
    namespace typer
    {

        // How an expression value is represented (mirrors the LLVM type class)
        enum TyKind
        {
            UNKNOWN,
            INT,
            FLOAT,
            DOUBLE,
            PTR,
            AGG,
            ARRAY,
            VOID,
            FUNC,
            DICT
        };

        // ------------------------------------------------------------------
        // Operator name mangling (fcodegen._mangle_builtin_op)
        // ------------------------------------------------------------------

        def match_at(byte* s, int i, byte* lit) -> bool
        {
            int j;
            while (lit[j] != 0)
            {
                if (s[i + j] != lit[j]) { return false; };
                j++;
            };
            return true;
        };

        // Length of the multi character operator part at s[i], 1 when there is none
        def op_part_len(byte* s, int i) -> int
        {
            if (match_at(s, i, g"^|!&\0")) { return 4; };
            if (match_at(s, i, g"^|!|\0")) { return 4; };
            if (match_at(s, i, g"^|!\0")) { return 3; };
            if (match_at(s, i, g"`!&\0")) { return 3; };
            if (match_at(s, i, g"`!|\0")) { return 3; };
            if (match_at(s, i, g"`^|\0")) { return 3; };
            if (match_at(s, i, g"^|\0")) { return 2; };
            if (match_at(s, i, g"!&\0")) { return 2; };
            if (match_at(s, i, g"!|\0")) { return 2; };
            if (match_at(s, i, g"<=\0")) { return 2; };
            if (match_at(s, i, g">=\0")) { return 2; };
            if (match_at(s, i, g"==\0")) { return 2; };
            if (match_at(s, i, g"!=\0")) { return 2; };
            if (match_at(s, i, g"++\0")) { return 2; };
            if (match_at(s, i, g"--\0")) { return 2; };
            if (match_at(s, i, g"<<\0")) { return 2; };
            if (match_at(s, i, g">>\0")) { return 2; };
            return 1;
        };

        def op_char_word(byte c) -> byte*
        {
            if (c == '+') { return g"plus\0"; };
            if (c == '-') { return g"minus\0"; };
            if (c == '*') { return g"mul\0"; };
            if (c == '/') { return g"div\0"; };
            if (c == '%') { return g"mod\0"; };
            if (c == '!') { return g"not\0"; };
            if (c == '^') { return g"pow\0"; };
            if (c == '&') { return g"and\0"; };
            if (c == '|') { return g"or\0"; };
            if (c == '<') { return g"lt\0"; };
            if (c == '>') { return g"gt\0"; };
            if (c == '=') { return g"eq\0"; };
            if (c == '~') { return g"tilde\0"; };
            if (c == '`') { return g"tick\0"; };
            return (byte*)0;
        };

        def hex_char(int v) -> int
        {
            if (v < 10) { return 48 + v; };
            return 97 + v - 10;
        };

        // Appends the mangled form of a builtin operator symbol to out
        def mangle_builtin_op(Buf* out, byte* sym) -> void
        {
            int i, j, plen;
            byte* w;
            bool first_part = true;
            int c;
            while (sym[i] != 0)
            {
                plen = op_part_len(sym, i);
                if (!first_part) { out.put('_'); };
                first_part = false;
                j = 0;
                while (j < plen)
                {
                    if (j > 0) { out.put('_'); };
                    w = op_char_word(sym[i + j]);
                    if (w != (byte*)0) { out.put_str(w); }
                    else
                    {
                        c = (int)sym[i + j];
                        out.put_str(g"0x\0");
                        if (c / 16 > 0) { out.put(hex_char(c / 16)); };
                        out.put(hex_char(c % 16));
                    };
                    j++;
                };
                i = i + plen;
            };
            return;
        };

        // Implicit conversion applied by the base compiler at a coercion site
        enum Conv
        {
            NONE,
            EXACT,
            INT_WIDEN,
            INT_NARROW,
            INT_TO_FLOAT,
            FLOAT_TO_INT,
            FLOAT_EXT,
            FLOAT_TRUNC,
            PTR_CAST,
            PTR_TO_INT,
            INT_TO_PTR,
            ARRAY_DECAY,
            ARRAY_COPY,
            ARRAY_PACK,
            STRUCT_LOAD,
            EXPR_CALL,
            INVALID
        };

        // Coercion sites (the base compiler handles each with its own routine)
        enum Site
        {
            STORE,     // initializer and assignment (store_with_type_conversion)
            ARG,       // call argument (convert_argument_to_parameter_type)
            RETURN     // return value (coerce_return_value)
        };

        struct ConvRec
        {
            Node* at;
            TypeSpec* dst;
            int site;
        };

        def conv_name(int c) -> byte*
        {
            switch (c)
            {
                case (Conv.EXACT)        { return g"exact\0"; }
                case (Conv.INT_WIDEN)    { return g"int widen\0"; }
                case (Conv.INT_NARROW)   { return g"int narrow\0"; }
                case (Conv.INT_TO_FLOAT) { return g"int to float\0"; }
                case (Conv.FLOAT_TO_INT) { return g"float to int\0"; }
                case (Conv.FLOAT_EXT)    { return g"float extend\0"; }
                case (Conv.FLOAT_TRUNC)  { return g"float truncate\0"; }
                case (Conv.PTR_CAST)     { return g"pointer cast\0"; }
                case (Conv.PTR_TO_INT)   { return g"pointer to int\0"; }
                case (Conv.INT_TO_PTR)   { return g"int to pointer\0"; }
                case (Conv.ARRAY_DECAY)  { return g"array decay\0"; }
                case (Conv.ARRAY_COPY)   { return g"array copy\0"; }
                case (Conv.ARRAY_PACK)   { return g"array pack\0"; }
                case (Conv.STRUCT_LOAD)  { return g"struct load\0"; }
                case (Conv.EXPR_CALL)    { return g"__expr call\0"; }
                case (Conv.INVALID)      { return g"invalid\0"; }
                default                  { return g"none\0"; };
            };
            return g"none\0";
        };

        def site_name(int s) -> byte*
        {
            if (s == Site.ARG) { return g"argument\0"; };
            if (s == Site.RETURN) { return g"return\0"; };
            return g"assignment\0";
        };

        def ends_with(byte* s, byte* suf) -> bool
        {
            int ls = pp_cstrlen(s);
            int lf = pp_cstrlen(suf);
            int i;
            if (lf > ls) { return false; };
            while (i < lf)
            {
                if (s[ls - lf + i] != suf[i]) { return false; };
                i++;
            };
            return true;
        };

        // Kinds of node that are expressions (typed by ExprTyper.type_of)
        def is_expr_kind(int k) -> bool
        {
            if (k == NodeKind.LITERAL | k == NodeKind.IDENTIFIER | k == NodeKind.ARRAY_LITERAL |
                k == NodeKind.STRING_LITERAL | k == NodeKind.BINARY_OP | k == NodeKind.IN_EXPRESSION |
                k == NodeKind.HAS_EXPRESSION | k == NodeKind.UNARY_OP | k == NodeKind.CAST_EXPRESSION |
                k == NodeKind.TYPE_CONVERT_EXPRESSION | k == NodeKind.RANGE_EXPRESSION |
                k == NodeKind.ARRAY_COMPREHENSION | k == NodeKind.F_STRING_LITERAL |
                k == NodeKind.FUNCTION_CALL | k == NodeKind.MEMBER_ACCESS | k == NodeKind.METHOD_CALL)
            {
                return true;
            };
            if (k == NodeKind.VARIADIC_ACCESS | k == NodeKind.ARRAY_ACCESS | k == NodeKind.ARRAY_SLICE |
                k == NodeKind.BIT_SLICE | k == NodeKind.BIT_INDEX_ACCESS | k == NodeKind.POINTER_DEREF |
                k == NodeKind.ADDRESS_OF | k == NodeKind.STRINGIFY | k == NodeKind.CODIFY |
                k == NodeKind.ALIGN_OF | k == NodeKind.TYPE_OF | k == NodeKind.SIZE_OF |
                k == NodeKind.ENDIAN_OF | k == NodeKind.NO_INIT | k == NodeKind.IF_EXPRESSION |
                k == NodeKind.TERNARY_OP | k == NodeKind.NULL_COALESCE | k == NodeKind.NOT_NULL)
            {
                return true;
            };
            if (k == NodeKind.FUNCTION_POINTER_CALL | k == NodeKind.TIE_EXPRESSION |
                k == NodeKind.STRUCT_INSTANCE | k == NodeKind.STRUCT_LITERAL |
                k == NodeKind.STRUCT_FIELD_ACCESS | k == NodeKind.STRUCT_RECAST |
                k == NodeKind.TYPE_FUNC_CALL | k == NodeKind.DICT_LITERAL_EXPR |
                k == NodeKind.DICT_LITERAL | k == NodeKind.MACRO_CALL)
            {
                return true;
            };
            return false;
        };

        // Expression kinds whose value has no TypeSpec representation. They stay
        // untyped without being counted as unresolved.
        def is_untyped_kind(int k) -> bool
        {
            return k == NodeKind.NO_INIT | k == NodeKind.RANGE_EXPRESSION |
                   k == NodeKind.ARRAY_COMPREHENSION | k == NodeKind.MACRO_CALL;
        };

        // ------------------------------------------------------------------
        // ExprTyper
        // ------------------------------------------------------------------
        object ExprTyper
        {
            FXC_SYMTABLE* st;
            PtrVec* arena;      // TypeSpec* made here (freed shallow)
            PtrVec* shells;     // NodeVec* that borrow their items
            PtrVec* anodes;     // Node* made here (array sizes)
            PtrVec* blobs;      // raw allocations (function pointer parameter arrays)
            PtrVec* unk;        // Node* of expressions left untyped
            Buf mb;             // name scratch
            byte* cur_obj;      // name of the object being walked, or null
            Node* cur_fn;       // function being walked, or null
            TypeSpec* cur_ret;  // its return type
            int typed, untyped;
            bool raw;           // next type_of call skips __expr promotion
            bool null_term;     // config null_terminate_strings
            Checker* ck;        // receives diagnostics, null when none are wanted
            int* convs;         // count per Conv value
            PtrVec* bad;        // ConvRec* of invalid conversions

            def __init(FXC_SYMTABLE* table) -> this
            {
                this.st = table;
                this.arena = pv_new();
                this.shells = pv_new();
                this.anodes = pv_new();
                this.blobs = pv_new();
                this.unk = pv_new();
                this.mb.__init();
                this.cur_obj = (byte*)0;
                this.cur_fn = (Node*)0;
                this.cur_ret = (TypeSpec*)0;
                this.typed = 0;
                this.untyped = 0;
                this.raw = false;
                this.null_term = false;
                this.ck = (Checker*)0;
                this.convs = (int*)fmalloc((u64)32 * (u64)(sizeof(int) / 8));
                int ci;
                while (ci < 32)
                {
                    this.convs[ci] = 0;
                    ci++;
                };
                this.bad = pv_new();
                return this;
            };

            def __expr() -> ExprTyper*
            {
                return this;
            };

            def __exit() -> void
            {
                int i;
                NodeVec* sh;
                while (i < this.arena.len)
                {
                    ffree((byte*)this.arena.items[i]);
                    i++;
                };
                i = 0;
                while (i < this.shells.len)
                {
                    sh = (NodeVec*)this.shells.items[i];
                    ffree((byte*)sh.items);
                    ffree((byte*)sh);
                    i++;
                };
                i = 0;
                while (i < this.anodes.len)
                {
                    node_free((Node*)this.anodes.items[i]);
                    i++;
                };
                i = 0;
                while (i < this.blobs.len)
                {
                    ffree((byte*)this.blobs.items[i]);
                    i++;
                };
                i = 0;
                while (i < this.bad.len)
                {
                    ffree((byte*)this.bad.items[i]);
                    i++;
                };
                pv_free(this.bad);
                ffree((byte*)this.convs);
                pv_free(this.arena);
                pv_free(this.shells);
                pv_free(this.anodes);
                pv_free(this.blobs);
                pv_free(this.unk);
                this.mb.__exit();
                return;
            };

            def clear_mb() -> void
            {
                this.mb.len = 0;
                if (this.mb.mem != (byte*)0) { this.mb.mem[0] = (byte)0; };
                return;
            };

            // ----------------------------------------------------------
            // Construction
            // ----------------------------------------------------------

            def keep(TypeSpec* t) -> TypeSpec*
            {
                if (t != (TypeSpec*)0) { pv_push(this.arena, (void*)t); };
                return t;
            };

            def mk(int base, int flags, int width) -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                t.base_type = base;
                t.flags = flags;
                t.bit_width = width;
                return this.keep(t);
            };

            // Integer of an exact LLVM width. Arithmetic results carry only the
            // signedness (UINT or SINT) exactly as attach_type_metadata does.
            def mk_int(int width, bool uns) -> TypeSpec*
            {
                if (width == 1) { return this.mk(DataType.BOOL, 0, -1); };
                if (uns) { return this.mk(DataType.UINT, 0, width); };
                return this.mk(DataType.SINT, TS_SIGNED, width);
            };

            def mk_named(int base, byte* name) -> TypeSpec*
            {
                TypeSpec* t = this.mk(base, 0, -1);
                t.custom_typename = name;
                return t;
            };

            def ptr_to(TypeSpec* t) -> TypeSpec*
            {
                if (t == (TypeSpec*)0) { return t; };
                TypeSpec* c = typespec_clone(t);
                c.flags = c.flags `| TS_POINTER;
                c.pointer_depth = c.pointer_depth + 1;
                return this.keep(c);
            };

            def byte_ptr() -> TypeSpec*
            {
                TypeSpec* t = this.mk(DataType.BYTE, TS_POINTER, -1);
                t.pointer_depth = 1;
                return t;
            };

            // Integer literal node used as an array size (owned by the typer)
            def size_node(int v) -> Node*
            {
                Node* s = node_new(NodeKind.LITERAL, 0, 0);
                s.op = DataType.SINT;
                s.ival = (i64)v;
                pv_push(this.anodes, (void*)s);
                return s;
            };

            def pointee_of(TypeSpec* t) -> TypeSpec*
            {
                if (t == (TypeSpec*)0) { return t; };
                if (t.pointer_depth <= 0) { return (TypeSpec*)0; };
                TypeSpec* c = typespec_clone(t);
                c.pointer_depth = c.pointer_depth - 1;
                if (c.pointer_depth == 0)
                {
                    if (ts_is_pointer(c)) { c.flags = c.flags - TS_POINTER; };
                };
                return this.keep(c);
            };

            // ----------------------------------------------------------
            // Classification
            // ----------------------------------------------------------

            // Follows type aliases (def ... as name) to the underlying spec.
            // An alias used with extra pointer depth keeps that depth.
            def resolve_alias(TypeSpec* t) -> TypeSpec*
            {
                TypeSpec* cur = t;
                TypeSpec* tgt;
                TypeSpec* c;
                FXC_SYMENTRY* e;
                int guard;
                while (guard < 16)
                {
                    if (cur == (TypeSpec*)0) { return cur; };
                    if (cur.custom_typename == (byte*)0) { return cur; };
                    e = st_lookup_type(this.st, cur.custom_typename, (byte*)0);
                    if (e == (FXC_SYMENTRY*)0) { return cur; };
                    if (e.kind_id != SymbolKind.TYPE) { return cur; };
                    tgt = (TypeSpec*)e.ts;
                    if (tgt == (TypeSpec*)0) { return cur; };
                    if (cur.pointer_depth > 0 | ts_is_array(cur))
                    {
                        c = typespec_clone(tgt);
                        c.pointer_depth = c.pointer_depth + cur.pointer_depth;
                        if (cur.pointer_depth > 0) { c.flags = c.flags `| TS_POINTER; };
                        if (ts_is_array(cur))
                        {
                            c.flags = c.flags `| TS_ARRAY;
                            c.array_size = cur.array_size;
                            c.array_dims = cur.array_dims;
                        };
                        cur = this.keep(c);
                    }
                    else { cur = tgt; };
                    guard++;
                };
                return cur;
            };

            def kind_of(TypeSpec* t) -> int
            {
                if (t == (TypeSpec*)0) { return TyKind.UNKNOWN; };
                TypeSpec* a = this.resolve_alias(t);
                FXC_SYMENTRY* e;
                int b;
                if (ts_is_array(a))
                {
                    if (a.array_size != (Node*)0) { return TyKind.ARRAY; };
                    if (a.array_dims != (NodeVec*)0)
                    {
                        if (a.array_dims.len > 0)
                        {
                            if (a.array_dims.items[0] != (Node*)0) { return TyKind.ARRAY; };
                        };
                    };
                    return TyKind.PTR;
                };
                if (ts_is_pointer(a)) { return TyKind.PTR; };
                if (a.custom_typename != (byte*)0)
                {
                    e = st_lookup_type(this.st, a.custom_typename, (byte*)0);
                    if (e == (FXC_SYMENTRY*)0) { return TyKind.UNKNOWN; };
                    if (e.kind_id == SymbolKind.STRUCT | e.kind_id == SymbolKind.OBJECT |
                        e.kind_id == SymbolKind.UNION)
                    {
                        return TyKind.AGG;
                    };
                    if (e.kind_id == SymbolKind.ENUM) { return TyKind.INT; };
                    return TyKind.UNKNOWN;
                };
                b = a.base_type;
                if (b == DataType.SINT | b == DataType.UINT | b == DataType.SLONG | b == DataType.ULONG |
                    b == DataType.BOOL | b == DataType.CHAR | b == DataType.BYTE | b == DataType.DATA |
                    b == DataType.ENUM | b == DataType.STRUCT | b == DataType.OBJECT)
                {
                    return TyKind.INT;
                };
                if (b == DataType.FLOAT) { return TyKind.FLOAT; };
                if (b == DataType.DOUBLE) { return TyKind.DOUBLE; };
                if (b == DataType.VOID) { return TyKind.VOID; };
                if (b == DataType.THIS) { return TyKind.PTR; };
                if (b == DataType.FUNC_PTR) { return TyKind.FUNC; };
                if (b == DataType.DICT) { return TyKind.DICT; };
                if (b == DataType.UNION) { return TyKind.AGG; };
                return TyKind.UNKNOWN;
            };

            // Bit width of an integer typed value, 0 when it has none
            def width_of(TypeSpec* t) -> int
            {
                TypeSpec* a = this.resolve_alias(t);
                int b;
                if (a == (TypeSpec*)0) { return 0; };
                if (a.custom_typename != (byte*)0) { return 32; };
                b = a.base_type;
                if (b == DataType.SINT | b == DataType.UINT)
                {
                    if (a.bit_width > 0) { return a.bit_width; };
                    return 32;
                };
                if (b == DataType.SLONG | b == DataType.ULONG) { return 64; };
                if (b == DataType.BOOL) { return 1; };
                if (b == DataType.CHAR) { return 8; };
                if (b == DataType.STRUCT | b == DataType.OBJECT) { return 8; };
                if (b == DataType.ENUM) { return 32; };
                if (b == DataType.BYTE)
                {
                    if (a.bit_width > 0) { return a.bit_width; };
                    return 8;
                };
                if (b == DataType.DATA)
                {
                    if (a.bit_width > 0) { return a.bit_width; };
                    return 0;
                };
                return 0;
            };

            // CoercionContext.is_unsigned over a TypeSpec
            def uns_of(TypeSpec* t) -> bool
            {
                TypeSpec* a = this.resolve_alias(t);
                if (a == (TypeSpec*)0) { return false; };
                if (a.custom_typename != (byte*)0) { return false; };
                if (a.base_type == DataType.UINT) { return true; };
                if (a.base_type == DataType.BYTE) { return true; };
                if (a.base_type == DataType.DATA) { return !ts_is_signed(a); };
                return false;
            };

            // Element type of an array or pointee of a pointer
            def elem_of(TypeSpec* t) -> TypeSpec*
            {
                if (t == (TypeSpec*)0) { return t; };
                TypeSpec* a = this.resolve_alias(t);
                TypeSpec* c;
                NodeVec* d;
                NodeVec* sh;
                int i;
                if (ts_is_array(a))
                {
                    c = typespec_clone(a);
                    d = a.array_dims;
                    if (d != (NodeVec*)0)
                    {
                        if (d.len > 1)
                        {
                            sh = (NodeVec*)fmalloc((u64)(sizeof(NodeVec) / 8));
                            sh.len = d.len - 1;
                            sh.cap = d.len - 1;
                            sh.items = (Node**)fmalloc((u64)sh.len * (u64)(sizeof(Node*) / 8));
                            while (i < sh.len)
                            {
                                sh.items[i] = d.items[i + 1];
                                i++;
                            };
                            pv_push(this.shells, (void*)sh);
                            c.array_dims = sh;
                            c.array_size = sh.items[0];
                            return this.keep(c);
                        };
                    };
                    c.flags = c.flags - TS_ARRAY;
                    c.array_size = (Node*)0;
                    c.array_dims = (NodeVec*)0;
                    return this.keep(c);
                };
                if (ts_is_pointer(a)) { return this.pointee_of(a); };
                return (TypeSpec*)0;
            };

            // Pointer to a value of type t. An array decays to a pointer to its element.
            def addr_of_type(TypeSpec* t) -> TypeSpec*
            {
                if (t == (TypeSpec*)0) { return t; };
                TypeSpec* a = this.resolve_alias(t);
                if (ts_is_array(a)) { return this.ptr_to(this.elem_of(a)); };
                return this.ptr_to(a);
            };

            // Declared size of a one dimensional array, -1 when it is not a literal
            def array_len(TypeSpec* t) -> int
            {
                TypeSpec* a = this.resolve_alias(t);
                Node* d0;
                if (a == (TypeSpec*)0) { return -1; };
                d0 = a.array_size;
                if (a.array_dims != (NodeVec*)0)
                {
                    if (a.array_dims.len != 1) { return -1; };
                    d0 = a.array_dims.items[0];
                };
                if (d0 == (Node*)0) { return -1; };
                if (d0.kind != NodeKind.LITERAL) { return -1; };
                return (int)d0.ival;
            };

            // Same LLVM type for pointers: equal depth and equal pointee
            def ptr_same(TypeSpec* a, TypeSpec* b) -> bool
            {
                TypeSpec* ra = this.resolve_alias(a);
                TypeSpec* rb = this.resolve_alias(b);
                TypeSpec* ba;
                TypeSpec* bb;
                int da = ra.pointer_depth;
                int db = rb.pointer_depth;
                if (ts_is_array(ra)) { da = da + 1; };
                if (ts_is_array(rb)) { db = db + 1; };
                if (da != db) { return false; };
                ba = typespec_clone(ra);
                bb = typespec_clone(rb);
                ba.pointer_depth = 0;
                bb.pointer_depth = 0;
                ba.flags = ba.flags - (ba.flags `& (TS_POINTER `| TS_ARRAY));
                bb.flags = bb.flags - (bb.flags `& (TS_POINTER `| TS_ARRAY));
                ba.array_size = (Node*)0;
                bb.array_size = (Node*)0;
                ba.array_dims = (NodeVec*)0;
                bb.array_dims = (NodeVec*)0;
                if (ba.base_type == DataType.VOID & ba.custom_typename == (byte*)0)
                {
                    ba.base_type = DataType.CHAR;
                };
                if (bb.base_type == DataType.VOID & bb.custom_typename == (byte*)0)
                {
                    bb.base_type = DataType.CHAR;
                };
                this.keep(ba);
                this.keep(bb);
                return this.ty_same(ba, bb);
            };

            def agg_same(TypeSpec* a, TypeSpec* b) -> bool
            {
                TypeSpec* ra = this.resolve_alias(a);
                TypeSpec* rb = this.resolve_alias(b);
                FXC_SYMENTRY* ea;
                FXC_SYMENTRY* eb;
                if (ra.custom_typename == (byte*)0 | rb.custom_typename == (byte*)0)
                {
                    return ra.base_type == rb.base_type;
                };
                ea = st_lookup_type(this.st, ra.custom_typename, (byte*)0);
                eb = st_lookup_type(this.st, rb.custom_typename, (byte*)0);
                if (ea != (FXC_SYMENTRY*)0 & eb != (FXC_SYMENTRY*)0)
                {
                    return (u64)ea.node == (u64)eb.node;
                };
                return cstr_eq(ra.custom_typename, rb.custom_typename);
            };

            // True when a and b have the same LLVM type
            def ty_same(TypeSpec* a, TypeSpec* b) -> bool
            {
                int ka = this.kind_of(a);
                int kb = this.kind_of(b);
                int la, lb;
                if (ka != kb) { return false; };
                if (ka == TyKind.UNKNOWN) { return false; };
                if (ka == TyKind.INT) { return this.width_of(a) == this.width_of(b); };
                if (ka == TyKind.PTR) { return this.ptr_same(a, b); };
                if (ka == TyKind.AGG) { return this.agg_same(a, b); };
                if (ka == TyKind.ARRAY)
                {
                    la = this.array_len(a);
                    lb = this.array_len(b);
                    if (la != lb) { return false; };
                    return this.ty_same(this.elem_of(a), this.elem_of(b));
                };
                return true;
            };

            // Argument of type at is accepted by a parameter of type pt without conversion
            // (same type, array decay, or pointer to the struct passed by value and back)
            def arg_matches(TypeSpec* pt, TypeSpec* at) -> bool
            {
                int kp = this.kind_of(pt);
                int ka = this.kind_of(at);
                TypeSpec* rp;
                TypeSpec* ra;
                if (this.ty_same(pt, at)) { return true; };
                if (kp == TyKind.PTR & ka == TyKind.ARRAY)
                {
                    return this.ty_same(this.elem_of(pt), this.elem_of(at));
                };
                if (kp == TyKind.PTR & ka == TyKind.AGG)
                {
                    rp = this.resolve_alias(pt);
                    if (rp.pointer_depth == 1) { return this.ty_same(this.elem_of(pt), at); };
                };
                if (kp == TyKind.AGG & ka == TyKind.PTR)
                {
                    ra = this.resolve_alias(at);
                    if (ra.pointer_depth == 1) { return this.ty_same(pt, this.elem_of(at)); };
                };
                return false;
            };

            // ----------------------------------------------------------
            // Declarations
            // ----------------------------------------------------------

            def type_entry(TypeSpec* t) -> FXC_SYMENTRY*
            {
                TypeSpec* a = this.resolve_alias(t);
                if (a == (TypeSpec*)0) { return (FXC_SYMENTRY*)0; };
                if (a.custom_typename == (byte*)0) { return (FXC_SYMENTRY*)0; };
                return st_lookup_type(this.st, a.custom_typename, (byte*)0);
            };

            // Declared type of member name of the struct, object or union type ot
            // (an enum typed value gives the enum type itself)
            def member_type_of(TypeSpec* ot, byte* name) -> TypeSpec*
            {
                FXC_SYMENTRY* e = this.type_entry(ot);
                TypeSpec* a;
                Node* dn;
                Node* m;
                int i, cnt;
                if (e == (FXC_SYMENTRY*)0 | name == (byte*)0) { return (TypeSpec*)0; };
                if (e.kind_id == SymbolKind.ENUM)
                {
                    a = this.resolve_alias(ot);
                    return this.mk_named(DataType.ENUM, a.custom_typename);
                };
                dn = (Node*)e.node;
                if (dn == (Node*)0) { return (TypeSpec*)0; };
                cnt = node_count(dn, 0);
                while (i < cnt)
                {
                    m = node_child(dn, 0, i);
                    if (m.text != (byte*)0)
                    {
                        if (cstr_eq(m.text, name)) { return m.ts; };
                    };
                    i++;
                };
                return (TypeSpec*)0;
            };

            // First method of object definition dn called name taking argc parameters
            def find_method0(Node* dn, byte* name) -> Node*
            {
                int i, cnt;
                Node* m;
                if (dn == (Node*)0) { return dn; };
                cnt = node_count(dn, 1);
                while (i < cnt)
                {
                    m = node_child(dn, 1, i);
                    if (m.text != (byte*)0)
                    {
                        if (cstr_eq(m.text, name))
                        {
                            if (node_count(m, 0) == 0) { return m; };
                        };
                    };
                    i++;
                };
                return (Node*)0;
            };

            // Return type of function fn. A this return type is a pointer to the object.
            def ret_of_fn(Node* fn, byte* objname) -> TypeSpec*
            {
                if (fn == (Node*)0) { return (TypeSpec*)0; };
                TypeSpec* r = fn.ts;
                if (r == (TypeSpec*)0) { return r; };
                if (r.base_type == DataType.THIS)
                {
                    if (objname == (byte*)0) { return (TypeSpec*)0; };
                    return this.ptr_to(this.mk_named(DataType.OBJECT, objname));
                };
                return r;
            };

            // Type a variable of type vt has in expression context when its object
            // defines __expr (null when it does not)
            def expr_promote(TypeSpec* vt) -> TypeSpec*
            {
                FXC_SYMENTRY* e = this.type_entry(vt);
                TypeSpec* a;
                Node* m;
                if (vt == (TypeSpec*)0) { return (TypeSpec*)0; };
                if (e == (FXC_SYMENTRY*)0) { return (TypeSpec*)0; };
                if (e.kind_id != SymbolKind.OBJECT) { return (TypeSpec*)0; };
                a = this.resolve_alias(vt);
                if (a.pointer_depth > 1) { return (TypeSpec*)0; };
                if (ts_is_array(a)) { return (TypeSpec*)0; };
                m = this.find_method0((Node*)e.node, g"__expr\0");
                if (m == (Node*)0) { return (TypeSpec*)0; };
                return this.ret_of_fn(m, e.name);
            };

            // Type of a function used as a value (@f)
            def fn_value(Node* fn) -> TypeSpec*
            {
                if (fn == (Node*)0) { return (TypeSpec*)0; };
                int cnt = node_count(fn, 0);
                int i, np;
                Node* p;
                TypeSpec* t = this.mk(DataType.FUNC_PTR, 0, -1);
                TypeSpec** ps = (TypeSpec**)fmalloc((u64)(cnt + 1) * (u64)(sizeof(TypeSpec*) / 8));
                pv_push(this.blobs, (void*)ps);
                while (i < cnt)
                {
                    p = node_child(fn, 0, i);
                    if (p.ts != (TypeSpec*)0)
                    {
                        ps[np] = p.ts;
                        np++;
                    };
                    i++;
                };
                t.fp_nparams = np;
                t.fp_params = ps;
                t.fp_ret = fn.ts;
                return t;
            };

            // ----------------------------------------------------------
            // Overloads
            // ----------------------------------------------------------

            // Overload list for name through the namespace walk
            // (the same order as st_resolve_with_namespaces)
            def ov_resolve(byte* name) -> PtrVec*
            {
                PtrVec* r;
                byte* m;
                byte* walk;
                byte* p;
                bool more;
                int i;
                byte* cur = this.st.current_ns;

                if (has_scope_sep(name))
                {
                    m = colons_to_underscores(name);
                    r = st_overloads_of(this.st, m);
                    ffree(m);
                    if (r != (PtrVec*)0) { return r; };
                };

                r = st_overloads_of(this.st, name);
                if (r != (PtrVec*)0) { return r; };

                if (cur[0] != 0)
                {
                    m = mangle_namespace_name(cur, name);
                    r = st_overloads_of(this.st, m);
                    ffree(m);
                    if (r != (PtrVec*)0) { return r; };

                    walk = ts_dup(cur);
                    more = true;
                    while (more)
                    {
                        more = has_scope_sep(walk);
                        p = namespace_parent(walk);
                        m = mangle_namespace_name(p, name);
                        r = st_overloads_of(this.st, m);
                        ffree(m);
                        ffree(walk);
                        walk = p;
                        if (r != (PtrVec*)0)
                        {
                            ffree(walk);
                            return r;
                        };
                    };
                    ffree(walk);
                };

                while (i < this.st.using_ns.len)
                {
                    m = mangle_namespace_name((byte*)this.st.using_ns.items[i], name);
                    r = st_overloads_of(this.st, m);
                    ffree(m);
                    if (r != (PtrVec*)0) { return r; };
                    i++;
                };

                i = 0;
                while (i < this.st.registered_ns.len)
                {
                    m = mangle_namespace_name((byte*)this.st.registered_ns.items[i], name);
                    r = st_overloads_of(this.st, m);
                    ffree(m);
                    if (r != (PtrVec*)0) { return r; };
                    i++;
                };
                return (PtrVec*)0;
            };

            // True when an argument node carries a TypeSpec in fcodegen (identifiers,
            // casts, members, elements). Literals and arithmetic results carry only
            // a DataType, calls carry nothing, so signedness, char and endianness
            // are not compared for them.
            def has_spec(Node* an) -> bool
            {
                int k = an.kind;
                return k == NodeKind.IDENTIFIER | k == NodeKind.CAST_EXPRESSION |
                       k == NodeKind.TYPE_CONVERT_EXPRESSION | k == NodeKind.MEMBER_ACCESS |
                       k == NodeKind.ARRAY_ACCESS | k == NodeKind.STRUCT_FIELD_ACCESS;
            };

            // Type of an argument used for overload selection: an object variable is
            // the object itself (the __expr promotion is undone in fcodegen)
            def arg_type(Node* an) -> TypeSpec*
            {
                FXC_SYMENTRY* e;
                if (an.kind == NodeKind.IDENTIFIER)
                {
                    if (an.text != (byte*)0)
                    {
                        e = st_lookup_any(this.st, an.text, (byte*)0);
                        if (e != (FXC_SYMENTRY*)0)
                        {
                            if (e.kind_id == SymbolKind.VARIABLE)
                            {
                                if ((TypeSpec*)e.ts != (TypeSpec*)0) { return (TypeSpec*)e.ts; };
                            };
                        };
                    };
                };
                return an.ety;
            };

            def exact_param(TypeSpec* pt, Node* an) -> bool
            {
                TypeSpec* at = this.arg_type(an);
                TypeSpec* rp;
                TypeSpec* ra;
                if (pt == (TypeSpec*)0 | at == (TypeSpec*)0) { return true; };
                if (!this.arg_matches(pt, at)) { return false; };
                if (this.kind_of(pt) != TyKind.INT) { return true; };
                if (this.kind_of(at) != TyKind.INT) { return true; };
                if (!this.has_spec(an)) { return true; };
                rp = this.resolve_alias(pt);
                ra = this.resolve_alias(at);
                if (ts_is_signed(rp) != ts_is_signed(ra)) { return false; };
                if ((rp.base_type == DataType.CHAR) != (ra.base_type == DataType.CHAR)) { return false; };
                if (rp.endianness != ra.endianness) { return false; };
                return true;
            };

            // The caller may leave out trailing parameters that have defaults
            def count_ok(Overload* o, int argc) -> bool
            {
                int i;
                Node* p;
                if (o.nparams == argc) { return true; };
                if (argc > o.nparams) { return false; };
                if (o.func == (Node*)0) { return false; };
                i = argc;
                while (i < o.nparams)
                {
                    p = node_child(o.func, 0, i);
                    if (p.a == (Node*)0) { return false; };
                    i++;
                };
                return true;
            };

            // TypeResolver._resolve_from_overloads: the first overload whose parameter
            // types match the arguments, else the first with an acceptable count
            def pick_overload(PtrVec* list, NodeVec* args) -> Overload*
            {
                Overload* first = (Overload*)0;
                Overload* o;
                int i, j, np;
                int argc = 0;
                bool ok, vari;
                if (list == (PtrVec*)0) { return first; };
                if (args != (NodeVec*)0) { argc = args.len; };
                while (i < list.len)
                {
                    o = (Overload*)list.items[i];
                    i++;
                    vari = false;
                    if (o.func != (Node*)0)
                    {
                        if ((o.func.flags `& NF_VARIADIC) != 0) { vari = true; };
                    };
                    np = o.nparams;
                    if (vari) { ok = argc >= np; }
                    else { ok = this.count_ok(o, argc); };
                    if (!ok) { continue; };
                    if (first == (Overload*)0) { first = o; };
                    ok = true;
                    j = 0;
                    while (j < argc & j < np)
                    {
                        if (!this.exact_param(o.params[j], args.items[j]))
                        {
                            ok = false;
                            break;
                        };
                        j++;
                    };
                    if (ok) { return o; };
                };
                return first;
            };

            // Overload of builtin operator op taking exactly (lt, rt)
            def binary_overload(int op, TypeSpec* lt, TypeSpec* rt) -> Overload*
            {
                PtrVec* list;
                Overload* o;
                int i;
                if (lt == (TypeSpec*)0 | rt == (TypeSpec*)0) { return (Overload*)0; };
                this.clear_mb();
                this.mb.put_str(g"operator__\0");
                mangle_builtin_op(@this.mb, operator_text(op));
                list = this.ov_resolve(this.mb.mem);
                if (list == (PtrVec*)0) { return (Overload*)0; };
                while (i < list.len)
                {
                    o = (Overload*)list.items[i];
                    i++;
                    if (o.nparams != 2) { continue; };
                    if (o.func == this.cur_fn) { continue; };
                    if (this.arg_matches(o.params[0], lt))
                    {
                        if (this.arg_matches(o.params[1], rt)) { return o; };
                    };
                };
                return (Overload*)0;
            };

            // ----------------------------------------------------------
            // Type functions
            // ----------------------------------------------------------

            // Flux type name of a receiver (_llvm_type_to_flux_type_name). Heap string or null.
            def flux_type_name(TypeSpec* t) -> byte*
            {
                TypeSpec* a = this.resolve_alias(t);
                TypeSpec* el;
                int k = this.kind_of(t);
                int w;
                byte* base;
                byte* r;
                if (a == (TypeSpec*)0) { return (byte*)0; };
                if (k == TyKind.INT)
                {
                    w = this.width_of(t);
                    if (w == 1) { return ts_dup(g"bool\0"); };
                    if (w == 8) { return ts_dup(g"byte\0"); };
                    if (w == 16 | w == 32) { return ts_dup(g"int\0"); };
                    if (w == 64) { return ts_dup(g"long\0"); };
                    this.clear_mb();
                    this.mb.put_str(g"data\0");
                    this.mb.put_int(w);
                    return ts_dup(this.mb.mem);
                };
                if (k == TyKind.FLOAT) { return ts_dup(g"float\0"); };
                if (k == TyKind.DOUBLE) { return ts_dup(g"double\0"); };
                if (k == TyKind.PTR)
                {
                    el = this.elem_of(a);
                    if (el == (TypeSpec*)0) { return (byte*)0; };
                    if (this.kind_of(el) == TyKind.INT)
                    {
                        if (this.width_of(el) == 8) { return ts_dup(g"string\0"); };
                    };
                    if (this.kind_of(el) == TyKind.VOID) { return ts_dup(g"string\0"); };
                    if (this.kind_of(el) == TyKind.AGG)
                    {
                        return ts_dup(this.resolve_alias(el).custom_typename);
                    };
                    return (byte*)0;
                };
                if (k == TyKind.AGG) { return ts_dup(a.custom_typename); };
                if (k == TyKind.ARRAY)
                {
                    el = this.elem_of(a);
                    base = this.flux_type_name(el);
                    if (base == (byte*)0) { return (byte*)0; };
                    r = join3(base, g"_arr\0", g"\0");
                    ffree(base);
                    return r;
                };
                return (byte*)0;
            };

            // Return type of type function ftype.fname called with args, null when none
            def typefunc_ret(byte* ftype, byte* fname, NodeVec* args) -> TypeSpec*
            {
                byte* mid = join3(g"__typefunc__\0", ftype, g"__\0");
                byte* key = join3(mid, fname, g"\0");
                PtrVec* list = st_overloads_of(this.st, key);
                Overload* o;
                ffree(mid);
                ffree(key);
                if (list == (PtrVec*)0) { return (TypeSpec*)0; };
                o = this.pick_overload(list, args);
                if (o == (Overload*)0) { return (TypeSpec*)0; };
                return o.ret;
            };

            // ----------------------------------------------------------
            // Expressions
            // ----------------------------------------------------------

            def type_list(Node* n, int slot) -> void
            {
                int i;
                int cnt = node_count(n, slot);
                while (i < cnt)
                {
                    this.type_of(node_child(n, slot, i));
                    i++;
                };
                return;
            };

            def type_raw(Node* n) -> TypeSpec*
            {
                this.raw = true;
                return this.type_of(n);
            };

            // Types expression n (and its children) and stores the result in n.ety
            def type_of(Node* n) -> TypeSpec*
            {
                if (n == (Node*)0) { return (TypeSpec*)0; };
                bool r = this.raw;
                this.raw = false;
                if (!is_expr_kind(n.kind))
                {
                    this.walk(n);
                    return (TypeSpec*)0;
                };
                TypeSpec* t = this.compute(n, r);
                n.ety = t;
                if (t != (TypeSpec*)0) { this.typed++; }
                else
                {
                    if (!is_untyped_kind(n.kind))
                    {
                        this.untyped++;
                        pv_push(this.unk, (void*)n);
                    };
                };
                return t;
            };

            def t_literal(Node* n) -> TypeSpec*
            {
                int op = n.op;
                int w;
                if (op == DataType.SINT)
                {
                    w = infer_int_width(n.ival, op);
                    if (w == 32) { w = -1; };
                    return this.mk(DataType.SINT, TS_SIGNED, w);
                };
                if (op == DataType.UINT)
                {
                    w = infer_int_width(n.ival, op);
                    if (w == 32) { w = -1; };
                    return this.mk(DataType.UINT, 0, w);
                };
                if (op == DataType.SLONG) { return this.mk(DataType.SLONG, TS_SIGNED, -1); };
                if (op == DataType.ULONG) { return this.mk(DataType.ULONG, 0, -1); };
                if (op == DataType.FLOAT) { return this.mk(DataType.FLOAT, TS_SIGNED, -1); };
                if (op == DataType.DOUBLE) { return this.mk(DataType.DOUBLE, TS_SIGNED, -1); };
                if (op == DataType.BOOL) { return this.mk(DataType.BOOL, 0, -1); };
                if (op == DataType.CHAR) { return this.mk(DataType.CHAR, TS_SIGNED, -1); };
                if (op == DataType.VOID) { return this.mk(DataType.VOID, 0, -1); };
                return (TypeSpec*)0;
            };

            // byte[len] for string text
            def string_type(byte* text) -> TypeSpec*
            {
                int len = 0;
                TypeSpec* t = this.mk(DataType.BYTE, TS_ARRAY, -1);
                if (text != (byte*)0) { len = pp_cstrlen(text); };
                if (this.null_term)
                {
                    if (len == 0) { len = 1; }
                    elif (text[len - 1] != 0) { len = len + 1; };
                };
                t.array_size = this.size_node(len);
                return t;
            };

            def t_ident(Node* n, bool r) -> TypeSpec*
            {
                FXC_SYMENTRY* e;
                TypeSpec* vt;
                TypeSpec* pr;
                TypeSpec* tt;
                if (n.text == (byte*)0) { return (TypeSpec*)0; };
                if (cstr_eq(n.text, g"this\0"))
                {
                    if (this.cur_obj == (byte*)0) { return (TypeSpec*)0; };
                    tt = this.mk_named(DataType.OBJECT, this.cur_obj);
                    return this.ptr_to(tt);
                };
                e = st_lookup_any(this.st, n.text, (byte*)0);
                if (e == (FXC_SYMENTRY*)0) { return (TypeSpec*)0; };
                if (e.kind_id == SymbolKind.VARIABLE)
                {
                    vt = (TypeSpec*)e.ts;
                    if (r) { return vt; };
                    pr = this.expr_promote(vt);
                    if (pr != (TypeSpec*)0) { return pr; };
                    return vt;
                };
                if (e.kind_id == SymbolKind.FUNCTION) { return this.fn_value((Node*)e.node); };
                // A type name used as a value operand (sizeof, alignof, typeof)
                if (e.kind_id == SymbolKind.STRUCT) { return this.mk_named(DataType.STRUCT, n.text); };
                if (e.kind_id == SymbolKind.OBJECT) { return this.mk_named(DataType.OBJECT, n.text); };
                if (e.kind_id == SymbolKind.UNION) { return this.mk_named(DataType.UNION, n.text); };
                if (e.kind_id == SymbolKind.ENUM) { return this.mk_named(DataType.ENUM, n.text); };
                if (e.kind_id == SymbolKind.TYPE) { return (TypeSpec*)e.ts; };
                return (TypeSpec*)0;
            };

            // Object variable promoted by __expr (its value is a byte string for +)
            def is_expr_source(Node* x) -> bool
            {
                FXC_SYMENTRY* e;
                if (x.kind == NodeKind.F_STRING_LITERAL) { return true; };
                if (x.kind != NodeKind.IDENTIFIER) { return false; };
                if (x.text == (byte*)0) { return false; };
                e = st_lookup_any(this.st, x.text, (byte*)0);
                if (e == (FXC_SYMENTRY*)0) { return false; };
                if (e.kind_id != SymbolKind.VARIABLE) { return false; };
                return this.expr_promote((TypeSpec*)e.ts) != (TypeSpec*)0;
            };

            // Result of array + array and array - array
            def concat(TypeSpec* lt, TypeSpec* rt, int op) -> TypeSpec*
            {
                TypeSpec* le = this.elem_of(lt);
                TypeSpec* c;
                int ln = this.array_len(lt);
                int rn = this.array_len(rt);
                int total;
                if (le == (TypeSpec*)0) { return (TypeSpec*)0; };
                c = typespec_clone(this.resolve_alias(lt));
                c.array_dims = (NodeVec*)0;
                c.array_size = (Node*)0;
                this.keep(c);
                if (ln < 0 | rn < 0) { return c; };
                if (op == Operator.ADD)
                {
                    total = ln + rn;
                    if (this.null_term & ln >= 1)
                    {
                        if (this.kind_of(le) == TyKind.INT)
                        {
                            if (this.width_of(le) == 8) { total = ln - 1 + rn; };
                        };
                    };
                }
                else
                {
                    total = ln - rn;
                    if (total < 0) { total = 0; };
                };
                c.array_size = this.size_node(total);
                return c;
            };

            def t_binary(Node* n) -> TypeSpec*
            {
                int op = n.op;
                TypeSpec* lt;
                TypeSpec* rt;
                Overload* ov;
                int lk, rk, w, lw, rw;
                bool lp, rp, uns;
                if (op == Operator.ASSIGN)
                {
                    lt = this.type_raw(n.a);
                    this.type_of(n.b);
                    this.conv_check(lt, n.b, Site.STORE);
                    return lt;
                };
                lt = this.type_of(n.a);
                rt = this.type_of(n.b);
                ov = this.binary_overload(op, lt, rt);
                if (ov != (Overload*)0)
                {
                    if (ov.ret != (TypeSpec*)0)
                    {
                        if (ov.ret.base_type == DataType.THIS) { return this.ret_of_fn(ov.func, this.cur_obj); };
                    };
                    return ov.ret;
                };
                if (op == Operator.EQUAL | op == Operator.NOT_EQUAL | op == Operator.LESS_THAN |
                    op == Operator.LESS_EQUAL | op == Operator.GREATER_THAN | op == Operator.GREATER_EQUAL)
                {
                    return this.mk(DataType.BOOL, 0, -1);
                };
                lk = this.kind_of(lt);
                rk = this.kind_of(rt);
                if (op == Operator.ADD)
                {
                    if (this.is_expr_source(n.a) | this.is_expr_source(n.b)) { return this.byte_ptr(); };
                };
                if (op == Operator.ADD | op == Operator.SUB)
                {
                    if (lk == TyKind.ARRAY & rk == TyKind.ARRAY) { return this.concat(lt, rt, op); };
                    lp = lk == TyKind.PTR | lk == TyKind.ARRAY;
                    rp = rk == TyKind.PTR | rk == TyKind.ARRAY;
                    if (lp & rk == TyKind.INT) { return this.addr_of_type(this.elem_of(lt)); };
                    if (rp & lk == TyKind.INT & op == Operator.ADD) { return this.addr_of_type(this.elem_of(rt)); };
                    if (lp & rp) { return this.mk_int(64, false); };
                };
                if (op == Operator.ADD | op == Operator.SUB | op == Operator.MUL | op == Operator.DIV |
                    op == Operator.MOD | op == Operator.POWER)
                {
                    if (lk == TyKind.FLOAT | lk == TyKind.DOUBLE)
                    {
                        if (lk == TyKind.FLOAT & rk == TyKind.DOUBLE) { return rt; };
                        return lt;
                    };
                    if (lk == TyKind.INT & rk == TyKind.INT)
                    {
                        lw = this.width_of(lt);
                        rw = this.width_of(rt);
                        w = lw;
                        if (rw > lw) { w = rw; };
                        uns = this.uns_of(lt) | this.uns_of(rt);
                        return this.mk_int(w, uns);
                    };
                    return (TypeSpec*)0;
                };
                if (op == Operator.BITAND | op == Operator.BITOR | op == Operator.BITXOR |
                    op == Operator.AND | op == Operator.OR | op == Operator.XOR)
                {
                    if (lk == TyKind.INT & rk == TyKind.INT)
                    {
                        lw = this.width_of(lt);
                        rw = this.width_of(rt);
                        w = lw;
                        if (rw > lw) { w = rw; };
                        uns = this.uns_of(lt) | this.uns_of(rt);
                        return this.mk_int(w, uns);
                    };
                    return (TypeSpec*)0;
                };
                if (op == Operator.BITSHIFT_LEFT | op == Operator.BITSHIFT_RIGHT)
                {
                    if (lk == TyKind.INT) { return this.mk_int(this.width_of(lt), this.uns_of(lt)); };
                    return (TypeSpec*)0;
                };
                if (op == Operator.NOR | op == Operator.NAND) { return lt; };
                if (op == Operator.BITNAND | op == Operator.BITNOR | op == Operator.BITXNOR)
                {
                    if (lk == TyKind.INT)
                    {
                        uns = this.uns_of(lt) | this.uns_of(rt);
                        return this.mk_int(this.width_of(lt), uns);
                    };
                    return (TypeSpec*)0;
                };
                return (TypeSpec*)0;
            };

            def t_unary(Node* n) -> TypeSpec*
            {
                TypeSpec* ot = this.type_of(n.a);
                int op = n.op;
                if (op == Operator.NOT)
                {
                    if (this.kind_of(ot) == TyKind.PTR) { return this.mk(DataType.BOOL, 0, -1); };
                    return ot;
                };
                return ot;
            };

            // Branch type of a ternary or null coalesce: the wider integer, else the first
            def join_types(TypeSpec* a, TypeSpec* b) -> TypeSpec*
            {
                int ka = this.kind_of(a);
                int kb = this.kind_of(b);
                if (a == (TypeSpec*)0) { return b; };
                if (b == (TypeSpec*)0) { return a; };
                if (ka == TyKind.INT & kb == TyKind.INT)
                {
                    if (this.width_of(b) > this.width_of(a)) { return b; };
                    return a;
                };
                if (ka == TyKind.ARRAY & kb == TyKind.PTR) { return b; };
                return a;
            };

            // Function named by its mangled name (fcodegen finds these in module.globals).
            // The base name is the part before the first double underscore.
            def by_mangled(byte* name) -> Overload*
            {
                int i, n;
                byte* base;
                PtrVec* list;
                Overload* o;
                while (name[n] != 0)
                {
                    if (name[n] == '_' & name[n + 1] == '_') { break; };
                    n++;
                };
                if (name[n] == 0) { return (Overload*)0; };
                base = (byte*)fmalloc((u64)n + (u64)1);
                while (i < n)
                {
                    base[i] = name[i];
                    i++;
                };
                base[n] = (byte)0;
                list = this.ov_resolve(base);
                ffree(base);
                if (list == (PtrVec*)0) { return (Overload*)0; };
                i = 0;
                while (i < list.len)
                {
                    o = (Overload*)list.items[i];
                    if (cstr_eq(o.mangled, name)) { return o; };
                    i++;
                };
                return (Overload*)0;
            };

            // Reports the message built in ck.mb at node n
            def report(int severity, Node* n) -> void
            {
                if (this.ck == (Checker*)0) { return; };
                this.ck.emit(severity, n.line, n.col);
                return;
            };

            // First overload for name (the one fcodegen reads the tie, endianness and
            // deprecation contracts from: resolve_overload_entry with no argument values)
            def first_overload(PtrVec* list) -> Overload*
            {
                if (list == (PtrVec*)0) { return (Overload*)0; };
                if (list.len == 0) { return (Overload*)0; };
                return (Overload*)list.items[0];
            };

            // Contracts visit_FunctionCall enforces before resolving the call
            def call_contracts(Node* n, PtrVec* list) -> void
            {
                Overload* o = this.first_overload(list);
                Node* an;
                TypeSpec* pt;
                TypeSpec* at;
                TypeSpec* ra;
                FXC_SYMENTRY* e;
                int i, tgt, src;
                int argc = node_count(n, 0);
                bool tied_arg;
                if (this.ck == (Checker*)0) { return; };
                while (i < argc)
                {
                    an = node_child(n, 0, i);
                    // A local variable cannot leave its scope through a call
                    if (an.kind == NodeKind.IDENTIFIER & an.text != (byte*)0)
                    {
                        e = st_lookup_any(this.st, an.text, (byte*)0);
                        if (e != (FXC_SYMENTRY*)0)
                        {
                            if (e.kind_id == SymbolKind.VARIABLE & (TypeSpec*)e.ts != (TypeSpec*)0)
                            {
                                if ((((TypeSpec*)e.ts).flags `& TS_LOCAL) != 0)
                                {
                                    this.ck.clear_msg();
                                    this.ck.mb.put_str(g"local variable '\0");
                                    this.ck.mb.put_str(an.text);
                                    this.ck.mb.put_str(g"' cannot leave its scope via function call\0");
                                    this.report(Severity.ERROR, n);
                                };
                            };
                        };
                    };
                    i++;
                };
                if (o == (Overload*)0) { return; };
                if (o.deprecated)
                {
                    this.ck.clear_msg();
                    this.ck.mb.put_str(g"call to deprecated function '\0");
                    this.ck.mb.put_str(n.text);
                    this.ck.mb.put_str(g"'\0");
                    this.report(Severity.WARNING, n);
                };
                i = 0;
                while (i < argc & i < o.nparams)
                {
                    an = node_child(n, 0, i);
                    pt = o.params[i];
                    tied_arg = an.kind == NodeKind.TIE_EXPRESSION;
                    if (pt != (TypeSpec*)0)
                    {
                        if (((pt.flags `& TS_TIED) != 0) & !tied_arg)
                        {
                            this.ck.clear_msg();
                            this.ck.mb.put_str(g"parameter \0");
                            this.ck.mb.put_int(i);
                            this.ck.mb.put_str(g" of '\0");
                            this.ck.mb.put_str(n.text);
                            this.ck.mb.put_str(g"' requires a tied argument (~), but a non-tied expression was passed\0");
                            this.report(Severity.ERROR, n);
                        };
                        if (((pt.flags `& TS_TIED) == 0) & tied_arg)
                        {
                            this.ck.clear_msg();
                            this.ck.mb.put_str(g"parameter \0");
                            this.ck.mb.put_int(i);
                            this.ck.mb.put_str(g" of '\0");
                            this.ck.mb.put_str(n.text);
                            this.ck.mb.put_str(g"' is not a tied parameter, but a tie expression (~) was passed\0");
                            this.report(Severity.ERROR, n);
                        };
                        // Assignment swaps endianness, parameter passing does not
                        tgt = pt.endianness;
                        src = 1;
                        if (this.has_spec(an))
                        {
                            at = this.arg_type(an);
                            if (at != (TypeSpec*)0) { src = this.resolve_alias(at).endianness; };
                        };
                        if (src != tgt)
                        {
                            this.ck.clear_msg();
                            this.ck.mb.put_str(g"passing argument \0");
                            this.ck.mb.put_int(i);
                            this.ck.mb.put_str(g" of function \0");
                            this.ck.mb.put_str(n.text);
                            if (src == 0) { this.ck.mb.put_str(g" is little-endian, but parameter expects big-endian\0"); }
                            else { this.ck.mb.put_str(g" is big-endian, but parameter expects little-endian\0"); };
                            this.report(Severity.ERROR, n);
                        };
                    };
                    i++;
                };
                return;
            };

            // Function name that no overload or symbol accepts (_funcall_not_found)
            def call_unresolved(Node* n) -> void
            {
                PtrVec* exact;
                Overload* o;
                int i, argc;
                if (this.ck == (Checker*)0) { return; };
                argc = node_count(n, 0);
                this.ck.clear_msg();
                exact = st_overloads_of(this.st, n.text);
                if (exact != (PtrVec*)0)
                {
                    this.ck.mb.put_str(g"function \0");
                    this.ck.mb.put_str(n.text);
                    this.ck.mb.put_str(g" found but no overload accepts \0");
                    this.ck.mb.put_int(argc);
                    this.ck.mb.put_str(g" arguments. Available overloads accept: [\0");
                    while (i < exact.len)
                    {
                        o = (Overload*)exact.items[i];
                        if (i > 0) { this.ck.mb.put_str(g", \0"); };
                        this.ck.mb.put_int(o.nparams);
                        i++;
                    };
                    this.ck.mb.put_str(g"]\0");
                }
                else
                {
                    this.ck.mb.put_str(g"function '\0");
                    this.ck.mb.put_str(n.text);
                    this.ck.mb.put_str(g"' not found in module or any imported namespaces\0");
                };
                this.report(Severity.ERROR, n);
                return;
            };

            def t_call(Node* n) -> TypeSpec*
            {
                int i;
                int cnt = node_count(n, 0);
                FXC_SYMENTRY* e;
                PtrVec* list;
                Overload* o;
                TypeSpec* vt;
                while (i < cnt)
                {
                    this.type_of(node_child(n, 0, i));
                    i++;
                };
                if (n.text == (byte*)0) { return (TypeSpec*)0; };
                e = st_lookup_any(this.st, n.text, (byte*)0);
                if (e != (FXC_SYMENTRY*)0)
                {
                    if (e.kind_id == SymbolKind.VARIABLE)
                    {
                        vt = this.resolve_alias((TypeSpec*)e.ts);
                        if (vt != (TypeSpec*)0)
                        {
                            if (vt.base_type == DataType.FUNC_PTR) { return vt.fp_ret; };
                        };
                    };
                };
                list = this.ov_resolve(n.text);
                this.call_contracts(n, list);
                o = this.pick_overload(list, n.l0);
                if (o != (Overload*)0)
                {
                    this.conv_args(o, n.l0);
                    n.text3 = o.mangled;
                    return o.ret;
                };
                o = this.by_mangled(n.text);
                if (o != (Overload*)0)
                {
                    n.text3 = o.mangled;
                    return o.ret;
                };
                e = st_lookup_any(this.st, n.text, (byte*)0);
                if (e != (FXC_SYMENTRY*)0)
                {
                    if (e.kind_id == SymbolKind.FUNCTION & list == (PtrVec*)0) { return (TypeSpec*)e.ts; };
                    if (e.kind_id == SymbolKind.STRUCT) { return this.mk_named(DataType.STRUCT, n.text); };
                    if (e.kind_id == SymbolKind.OBJECT) { return this.mk_named(DataType.OBJECT, n.text); };
                    if (e.kind_id == SymbolKind.VARIABLE)
                    {
                        if (this.kind_of((TypeSpec*)e.ts) == TyKind.AGG) { return (TypeSpec*)e.ts; };
                    };
                };
                this.call_unresolved(n);
                return (TypeSpec*)0;
            };

            def t_method(Node* n) -> TypeSpec*
            {
                TypeSpec* rt = this.type_raw(n.a);
                FXC_SYMENTRY* e;
                PtrVec* list;
                Overload* o;
                byte* key;
                byte* objkey;
                byte* tn;
                byte* mk2;
                TypeSpec* r;
                this.type_list(n, 0);
                if (n.text == (byte*)0) { return (TypeSpec*)0; };
                if (rt == (TypeSpec*)0) { return (TypeSpec*)0; };
                e = this.type_entry(rt);
                if (e != (FXC_SYMENTRY*)0)
                {
                    if (e.kind_id == SymbolKind.OBJECT | e.kind_id == SymbolKind.STRUCT)
                    {
                        objkey = mangle_namespace_name(e.ns, e.name);
                        key = join3(objkey, g".\0", n.text);
                        ffree(objkey);
                        list = st_overloads_of(this.st, key);
                        ffree(key);
                        o = this.pick_overload(list, n.l0);
                        if (o != (Overload*)0)
                        {
                            this.conv_args(o, n.l0);
                            n.text3 = o.mangled;
                            return this.ret_of_fn(o.func, e.name);
                        };
                    };
                };
                tn = this.flux_type_name(rt);
                if (tn == (byte*)0) { return (TypeSpec*)0; };
                r = this.typefunc_ret(tn, n.text, n.l0);
                if (r == (TypeSpec*)0)
                {
                    if (e != (FXC_SYMENTRY*)0)
                    {
                        mk2 = mangle_namespace_name(e.ns, e.name);
                        r = this.typefunc_ret(mk2, n.text, n.l0);
                        ffree(mk2);
                    };
                };
                ffree(tn);
                return r;
            };

            def t_member(Node* n) -> TypeSpec*
            {
                TypeSpec* ot;
                FXC_SYMENTRY* e;
                if (n.text == (byte*)0)
                {
                    this.type_raw(n.a);
                    return (TypeSpec*)0;
                };
                if (n.a != (Node*)0)
                {
                    if (n.a.kind == NodeKind.IDENTIFIER)
                    {
                        if (n.a.text != (byte*)0)
                        {
                            e = st_lookup_type(this.st, n.a.text, (byte*)0);
                            if (e != (FXC_SYMENTRY*)0)
                            {
                                if (e.kind_id == SymbolKind.ENUM)
                                {
                                    return this.mk_named(DataType.ENUM, n.a.text);
                                };
                            };
                        };
                    };
                };
                ot = this.type_raw(n.a);
                if (ot == (TypeSpec*)0) { return (TypeSpec*)0; };
                return this.member_type_of(ot, n.text);
            };

            def t_index(Node* n) -> TypeSpec*
            {
                TypeSpec* at = this.type_of(n.a);
                TypeSpec* a;
                int k;
                this.type_of(n.b);
                if (at == (TypeSpec*)0) { return (TypeSpec*)0; };
                a = this.resolve_alias(at);
                if (a.base_type == DataType.DICT)
                {
                    if (a.custom_typename == (byte*)0) { return a.dict_value; };
                };
                k = this.kind_of(at);
                if (k == TyKind.INT) { return this.mk(DataType.BYTE, 0, -1); };
                if (n.b != (Node*)0)
                {
                    if (n.b.kind == NodeKind.RANGE_EXPRESSION)
                    {
                        return this.addr_of_type(this.elem_of(at));
                    };
                };
                return this.elem_of(at);
            };

            def t_bitslice(Node* n) -> TypeSpec*
            {
                TypeSpec* vt = this.type_of(n.a);
                int lo = -1;
                int hi = -1;
                int width;
                this.type_of(n.b);
                this.type_of(n.c);
                if (n.b != (Node*)0)
                {
                    if (n.b.kind == NodeKind.LITERAL) { lo = (int)n.b.ival; };
                };
                if (n.c != (Node*)0)
                {
                    if (n.c.kind == NodeKind.LITERAL) { hi = (int)n.c.ival; };
                };
                if (lo >= 0 & hi >= 0)
                {
                    width = hi - lo;
                    if (width < 0) { width = lo - hi; };
                    return this.mk_int(width + 1, true);
                };
                return vt;
            };

            def t_address(Node* n) -> TypeSpec*
            {
                TypeSpec* ot = this.type_raw(n.a);
                TypeSpec* a;
                if (ot == (TypeSpec*)0) { return ot; };
                if (n.a.kind == NodeKind.IDENTIFIER)
                {
                    a = this.resolve_alias(ot);
                    if (this.kind_of(ot) == TyKind.FUNC) { return ot; };
                    // fcodegen loads a pointer variable: the address of a pointer
                    // variable is the pointer value itself
                    if (this.kind_of(ot) == TyKind.PTR & !ts_is_array(a)) { return ot; };
                };
                if (n.a.kind == NodeKind.POINTER_DEREF) { return n.a.a.ety; };
                return this.addr_of_type(ot);
            };

            def t_dict(Node* n) -> TypeSpec*
            {
                TypeSpec* t;
                TypeSpec* kt;
                TypeSpec* vt;
                int cnt;
                int step = 1;
                if (n.kind == NodeKind.DICT_LITERAL)
                {
                    this.type_list(n, 0);
                    cnt = node_count(n, 0);
                    if (cnt < 2) { return (TypeSpec*)0; };
                    kt = node_child(n, 0, 0).ety;
                    vt = node_child(n, 0, 1).ety;
                    cnt = cnt / 2;
                }
                else
                {
                    this.type_list(n, 0);
                    this.type_list(n, 1);
                    cnt = node_count(n, 0);
                    if (cnt < 1) { return (TypeSpec*)0; };
                    if (node_count(n, 1) < 1) { return (TypeSpec*)0; };
                    kt = node_child(n, 0, 0).ety;
                    vt = node_child(n, 1, 0).ety;
                };
                t = this.mk(DataType.DICT, 0, -1);
                t.dict_key = kt;
                t.dict_value = vt;
                t.dict_capacity = cnt;
                return t;
            };

            def t_array_lit(Node* n) -> TypeSpec*
            {
                TypeSpec* el;
                TypeSpec* c;
                int cnt = node_count(n, 0);
                this.type_list(n, 0);
                if ((n.flags `& NF_IS_STRING) != 0) { return this.string_type(n.text); };
                el = n.ts;
                if (el == (TypeSpec*)0)
                {
                    if (cnt == 0) { return (TypeSpec*)0; };
                    el = node_child(n, 0, 0).ety;
                };
                if (el == (TypeSpec*)0) { return el; };
                if (ts_is_array(el)) { return (TypeSpec*)0; };
                c = typespec_clone(el);
                c.flags = c.flags `| TS_ARRAY;
                c.array_size = this.size_node(cnt);
                c.array_dims = (NodeVec*)0;
                return this.keep(c);
            };

            def compute(Node* n, bool r) -> TypeSpec*
            {
                int k = n.kind;
                TypeSpec* t;
                TypeSpec* u;
                if (k == NodeKind.LITERAL) { return this.t_literal(n); };
                if (k == NodeKind.IDENTIFIER) { return this.t_ident(n, r); };
                if (k == NodeKind.STRING_LITERAL) { return this.string_type(n.text); };
                if (k == NodeKind.F_STRING_LITERAL)
                {
                    this.type_list(n, 0);
                    return this.byte_ptr();
                };
                if (k == NodeKind.ARRAY_LITERAL) { return this.t_array_lit(n); };
                if (k == NodeKind.BINARY_OP) { return this.t_binary(n); };
                if (k == NodeKind.UNARY_OP) { return this.t_unary(n); };
                if (k == NodeKind.CAST_EXPRESSION | k == NodeKind.TYPE_CONVERT_EXPRESSION)
                {
                    this.type_of(n.a);
                    return n.ts;
                };
                if (k == NodeKind.FUNCTION_CALL) { return this.t_call(n); };
                if (k == NodeKind.METHOD_CALL) { return this.t_method(n); };
                if (k == NodeKind.MEMBER_ACCESS) { return this.t_member(n); };
                if (k == NodeKind.STRUCT_FIELD_ACCESS)
                {
                    t = this.type_raw(n.a);
                    if (t == (TypeSpec*)0) { return t; };
                    return this.member_type_of(t, n.text);
                };
                if (k == NodeKind.ARRAY_ACCESS) { return this.t_index(n); };
                if (k == NodeKind.ARRAY_SLICE)
                {
                    t = this.type_of(n.a);
                    this.type_of(n.b);
                    this.type_of(n.c);
                    return this.addr_of_type(this.elem_of(t));
                };
                if (k == NodeKind.BIT_SLICE) { return this.t_bitslice(n); };
                if (k == NodeKind.BIT_INDEX_ACCESS)
                {
                    this.type_of(n.a);
                    this.type_of(n.b);
                    return this.mk(DataType.BYTE, 0, -1);
                };
                if (k == NodeKind.VARIADIC_ACCESS)
                {
                    this.type_of(n.a);
                    return this.mk_int(64, false);
                };
                if (k == NodeKind.POINTER_DEREF)
                {
                    t = this.type_of(n.a);
                    if (this.kind_of(t) == TyKind.PTR) { return this.pointee_of(this.resolve_alias(t)); };
                    if (this.kind_of(t) == TyKind.ARRAY) { return t; };
                    return (TypeSpec*)0;
                };
                if (k == NodeKind.ADDRESS_OF) { return this.t_address(n); };
                if (k == NodeKind.STRINGIFY) { return this.byte_ptr(); };
                if (k == NodeKind.CODIFY)
                {
                    this.type_of(n.a);
                    return (TypeSpec*)0;
                };
                if (k == NodeKind.SIZE_OF | k == NodeKind.ALIGN_OF | k == NodeKind.ENDIAN_OF)
                {
                    if (n.a != (Node*)0) { this.type_raw(n.a); };
                    return this.mk_int(32, false);
                };
                if (k == NodeKind.TYPE_OF)
                {
                    if (n.a != (Node*)0) { this.type_raw(n.a); };
                    return this.byte_ptr();
                };
                if (k == NodeKind.TERNARY_OP | k == NodeKind.IF_EXPRESSION)
                {
                    if (k == NodeKind.TERNARY_OP)
                    {
                        this.type_of(n.a);
                        t = this.type_of(n.b);
                        u = this.type_of(n.c);
                    }
                    else
                    {
                        t = this.type_of(n.a);
                        this.type_of(n.b);
                        u = this.type_of(n.c);
                    };
                    return this.join_types(t, u);
                };
                if (k == NodeKind.NULL_COALESCE)
                {
                    t = this.type_of(n.a);
                    u = this.type_of(n.b);
                    return this.join_types(t, u);
                };
                if (k == NodeKind.NOT_NULL)
                {
                    this.type_of(n.a);
                    return this.mk(DataType.BYTE, 0, -1);
                };
                if (k == NodeKind.IN_EXPRESSION)
                {
                    this.type_of(n.a);
                    this.type_of(n.b);
                    return this.mk(DataType.BOOL, 0, -1);
                };
                if (k == NodeKind.HAS_EXPRESSION)
                {
                    this.type_of(n.a);
                    return this.mk(DataType.BOOL, 0, -1);
                };
                if (k == NodeKind.TIE_EXPRESSION) { return this.type_raw(n.a); };
                if (k == NodeKind.FUNCTION_POINTER_CALL)
                {
                    t = this.type_of(n.a);
                    this.type_list(n, 0);
                    if (t == (TypeSpec*)0) { return t; };
                    t = this.resolve_alias(t);
                    if (t.base_type == DataType.FUNC_PTR) { return t.fp_ret; };
                    return (TypeSpec*)0;
                };
                if (k == NodeKind.STRUCT_LITERAL | k == NodeKind.STRUCT_INSTANCE)
                {
                    this.type_list(n, 1);
                    this.type_list(n, 2);
                    if (n.text == (byte*)0) { return (TypeSpec*)0; };
                    return this.mk_named(DataType.STRUCT, n.text);
                };
                if (k == NodeKind.STRUCT_RECAST)
                {
                    this.type_of(n.a);
                    if (n.text == (byte*)0) { return (TypeSpec*)0; };
                    return this.ptr_to(this.mk_named(DataType.STRUCT, n.text));
                };
                if (k == NodeKind.TYPE_FUNC_CALL)
                {
                    this.type_raw(n.a);
                    this.type_list(n, 0);
                    if (n.text == (byte*)0 | n.text2 == (byte*)0) { return (TypeSpec*)0; };
                    return this.typefunc_ret(n.text, n.text2, n.l0);
                };
                if (k == NodeKind.DICT_LITERAL | k == NodeKind.DICT_LITERAL_EXPR) { return this.t_dict(n); };
                if (k == NodeKind.RANGE_EXPRESSION)
                {
                    this.type_of(n.a);
                    this.type_of(n.b);
                    this.type_of(n.c);
                    return (TypeSpec*)0;
                };
                if (k == NodeKind.ARRAY_COMPREHENSION)
                {
                    st_enter_scope(this.st);
                    this.type_of(n.b);
                    if (n.text != (byte*)0) { this.def_var(n.text, n.ts, n); };
                    this.type_of(n.a);
                    this.type_of(n.c);
                    st_exit_scope(this.st);
                    return (TypeSpec*)0;
                };
                if (k == NodeKind.MACRO_CALL)
                {
                    this.type_list(n, 0);
                    return (TypeSpec*)0;
                };
                return (TypeSpec*)0;
            };

            // ----------------------------------------------------------
            // Implicit conversions (store_with_type_conversion,
            // convert_argument_to_parameter_type, coerce_return_value)
            // ----------------------------------------------------------

            // Object type (or pointer to it) that defines __expr
            def has_expr(TypeSpec* t) -> bool
            {
                TypeSpec* p = t;
                FXC_SYMENTRY* e;
                if (t == (TypeSpec*)0) { return false; };
                if (this.kind_of(t) == TyKind.PTR) { p = this.elem_of(t); };
                e = this.type_entry(p);
                if (e == (FXC_SYMENTRY*)0) { return false; };
                if (e.kind_id != SymbolKind.OBJECT) { return false; };
                return this.find_method0((Node*)e.node, g"__expr\0") != (Node*)0;
            };

            // Conversion the base compiler applies to turn a value of type src into dst
            def classify(TypeSpec* dst, TypeSpec* src, int site, Node* sn) -> int
            {
                int kd = this.kind_of(dst);
                int ks = this.kind_of(src);
                int wd, ws;
                TypeSpec* ed;
                TypeSpec* es;
                int ld, ls;
                bool agg_src;
                if (kd == TyKind.UNKNOWN | ks == TyKind.UNKNOWN) { return Conv.NONE; };
                if (kd == TyKind.VOID | ks == TyKind.VOID) { return Conv.NONE; };
                if (kd == TyKind.FUNC | ks == TyKind.FUNC) { return Conv.NONE; };
                if (kd == TyKind.DICT | ks == TyKind.DICT) { return Conv.NONE; };

                if (site == Site.ARG)
                {
                    if (!this.arg_matches(dst, src))
                    {
                        if (this.has_expr(src))
                        {
                            if (kd != TyKind.AGG | ks != TyKind.AGG) { return Conv.EXPR_CALL; };
                        };
                    };
                };

                if (kd == TyKind.INT)
                {
                    if (ks == TyKind.INT)
                    {
                        wd = this.width_of(dst);
                        ws = this.width_of(src);
                        if (wd == ws) { return Conv.EXACT; };
                        if (ws < wd) { return Conv.INT_WIDEN; };
                        return Conv.INT_NARROW;
                    };
                    if (ks == TyKind.FLOAT | ks == TyKind.DOUBLE)
                    {
                        if (site == Site.ARG) { return Conv.INVALID; };
                        return Conv.FLOAT_TO_INT;
                    };
                    if (ks == TyKind.PTR)
                    {
                        if (site == Site.STORE) { return Conv.PTR_TO_INT; };
                        return Conv.INVALID;
                    };
                    if (ks == TyKind.ARRAY)
                    {
                        if (site == Site.STORE) { return Conv.ARRAY_PACK; };
                        return Conv.INVALID;
                    };
                    return Conv.INVALID;
                };

                if (kd == TyKind.FLOAT | kd == TyKind.DOUBLE)
                {
                    if (ks == TyKind.INT)
                    {
                        if (site == Site.ARG) { return Conv.INVALID; };
                        return Conv.INT_TO_FLOAT;
                    };
                    if (ks == TyKind.FLOAT | ks == TyKind.DOUBLE)
                    {
                        if (kd == ks) { return Conv.EXACT; };
                        if (kd == TyKind.DOUBLE) { return Conv.FLOAT_EXT; };
                        return Conv.FLOAT_TRUNC;
                    };
                    return Conv.INVALID;
                };

                if (kd == TyKind.PTR)
                {
                    if (ks == TyKind.PTR)
                    {
                        if (this.ptr_same(dst, src)) { return Conv.EXACT; };
                        return Conv.PTR_CAST;
                    };
                    if (ks == TyKind.ARRAY) { return Conv.ARRAY_DECAY; };
                    if (ks == TyKind.INT)
                    {
                        if (site == Site.STORE) { return Conv.INT_TO_PTR; };
                        return Conv.INVALID;
                    };
                    return Conv.INVALID;
                };

                if (kd == TyKind.ARRAY)
                {
                    if (ks == TyKind.ARRAY)
                    {
                        if (this.ty_same(dst, src)) { return Conv.EXACT; };
                        ed = this.elem_of(dst);
                        es = this.elem_of(src);
                        ld = this.array_len(dst);
                        ls = this.array_len(src);
                        if (site == Site.STORE)
                        {
                            if (this.ty_same(ed, es))
                            {
                                if (ld < 0 | ls < 0) { return Conv.ARRAY_COPY; };
                                if (ls <= ld) { return Conv.ARRAY_COPY; };
                            };
                            return Conv.INVALID;
                        };
                        if (site == Site.RETURN)
                        {
                            if (this.kind_of(ed) == TyKind.INT & this.kind_of(es) == TyKind.INT)
                            {
                                if (ld >= 0 & ls >= 0)
                                {
                                    if (ld * this.width_of(ed) == ls * this.width_of(es)) { return Conv.ARRAY_COPY; };
                                };
                            };
                        };
                        return Conv.INVALID;
                    };
                    if (ks == TyKind.PTR)
                    {
                        if (sn != (Node*)0)
                        {
                            if (sn.kind == NodeKind.CAST_EXPRESSION) { return Conv.ARRAY_COPY; };
                        };
                    };
                    return Conv.INVALID;
                };

                if (kd == TyKind.AGG)
                {
                    if (ks == TyKind.AGG)
                    {
                        if (this.agg_same(dst, src)) { return Conv.EXACT; };
                        return Conv.INVALID;
                    };
                    if (ks == TyKind.PTR)
                    {
                        if (this.resolve_alias(src).pointer_depth == 1)
                        {
                            if (this.agg_same(dst, this.elem_of(src))) { return Conv.STRUCT_LOAD; };
                        };
                    };
                    return Conv.INVALID;
                };
                return Conv.NONE;
            };

            // Records the conversion of source expression sn to type dst
            def conv_check(TypeSpec* dst, Node* sn, int site) -> void
            {
                int c;
                ConvRec* r;
                if (dst == (TypeSpec*)0 | sn == (Node*)0) { return; };
                TypeSpec* sty = sn.ety;
                if (site == Site.ARG & sn.kind == NodeKind.IDENTIFIER) { sty = this.arg_type(sn); };
                if (sty == (TypeSpec*)0) { return; };
                c = this.classify(dst, sty, site, sn);
                if (c == Conv.NONE) { return; };
                this.convs[c] = this.convs[c] + 1;
                if (c == Conv.INVALID)
                {
                    r = (ConvRec*)fmalloc((u64)(sizeof(ConvRec) / 8));
                    r.at = sn;
                    r.dst = dst;
                    r.site = site;
                    pv_push(this.bad, (void*)r);
                };
                return;
            };

            def conv_args(Overload* o, NodeVec* args) -> void
            {
                int j;
                int argc = 0;
                if (o == (Overload*)0 | args == (NodeVec*)0) { return; };
                argc = args.len;
                while (j < argc & j < o.nparams)
                {
                    this.conv_check(o.params[j], args.items[j], Site.ARG);
                    j++;
                };
                return;
            };

            // Initializers the base compiler handles outside the store conversion
            def init_converts(Node* decl, TypeSpec* ts) -> bool
            {
                Node* a = decl.a;
                int k;
                if (a == (Node*)0) { return false; };
                k = a.kind;
                if (k == NodeKind.NO_INIT | k == NodeKind.ARRAY_LITERAL | k == NodeKind.STRING_LITERAL |
                    k == NodeKind.ARRAY_COMPREHENSION | k == NodeKind.STRUCT_RECAST)
                {
                    return false;
                };
                if (k == NodeKind.FUNCTION_CALL)
                {
                    if (a.text != (byte*)0)
                    {
                        if (ends_with(a.text, g".__init\0")) { return false; };
                    };
                };
                if (ts.storage_class == StorageClass.HEAP | ts.storage_class == StorageClass.SINGINIT) { return false; };
                if (ts_is_array(ts) & k == NodeKind.IDENTIFIER) { return false; };
                return true;
            };

            // Prints the conversion counts and, with verbose, the invalid conversions
            def print_conv(byte* path, bool verbose) -> void
            {
                int c = 1;
                int i;
                int n;
                ConvRec* r;
                while (c < 17)
                {
                    if (this.convs[c] != 0)
                    {
                        print(g"  \0");
                        print(conv_name(c));
                        print(g": \0");
                        println(this.convs[c]);
                    };
                    c++;
                };
                if (!verbose) { return; };
                while (i < this.bad.len)
                {
                    if (i >= 60) { break; };
                    r = (ConvRec*)this.bad.items[i];
                    print(path);
                    print(g":\0");
                    print(r.at.line);
                    print(g":\0");
                    print(r.at.col);
                    print(g": invalid \0");
                    print(site_name(r.site));
                    print(g" conversion \0");
                    this.clear_mb();
                    mangle_type(@this.mb, r.at.ety);
                    print(this.mb.mem);
                    print(g" to \0");
                    this.clear_mb();
                    mangle_type(@this.mb, r.dst);
                    println(this.mb.mem);
                    i++;
                };
                return;
            };

            // ----------------------------------------------------------
            // Statements
            // ----------------------------------------------------------

            def def_var(byte* name, TypeSpec* ts, Node* decl) -> void
            {
                if (st_is_global_scope(this.st)) { return; };
                st_define(this.st, name, SymbolKind.VARIABLE, ts, decl);
                return;
            };

            // int[] x = [..] and byte[] s = ".." take their size from the initializer
            def infer_decl(TypeSpec* ts, Node* init) -> TypeSpec*
            {
                TypeSpec* c;
                int cnt = -1;
                if (ts == (TypeSpec*)0) { return ts; };
                if (init == (Node*)0) { return ts; };
                if (!ts_is_array(ts)) { return ts; };
                if (ts.array_size != (Node*)0) { return ts; };
                if (ts.array_dims != (NodeVec*)0) { return ts; };
                if (init.kind == NodeKind.ARRAY_LITERAL)
                {
                    if ((init.flags `& NF_IS_STRING) != 0)
                    {
                        if (init.ety != (TypeSpec*)0) { cnt = this.array_len(init.ety); };
                    }
                    else { cnt = node_count(init, 0); };
                }
                elif (init.kind == NodeKind.STRING_LITERAL)
                {
                    if (init.ety != (TypeSpec*)0) { cnt = this.array_len(init.ety); };
                };
                if (cnt < 0) { return ts; };
                c = typespec_clone(ts);
                c.array_size = this.size_node(cnt);
                return this.keep(c);
            };

            def walk_list(Node* n, int slot) -> void
            {
                int i;
                int cnt = node_count(n, slot);
                while (i < cnt)
                {
                    this.walk(node_child(n, slot, i));
                    i++;
                };
                return;
            };

            def walk_children(Node* n) -> void
            {
                int s;
                this.walk(n.a);
                this.walk(n.b);
                this.walk(n.c);
                this.walk(n.d);
                this.walk(n.e);
                while (s < 6)
                {
                    this.walk_list(n, s);
                    s++;
                };
                return;
            };

            def walk_function(Node* fn) -> void
            {
                Node* prev_fn = this.cur_fn;
                TypeSpec* prev_ret = this.cur_ret;
                Node* p;
                int i;
                int cnt = node_count(fn, 0);
                if ((fn.flags `& NF_TEMPLATE) != 0) { return; };
                if (fn.a == (Node*)0) { return; };
                st_enter_scope(this.st);
                this.cur_fn = fn;
                this.cur_ret = fn.ts;
                while (i < cnt)
                {
                    p = node_child(fn, 0, i);
                    if (p.text != (byte*)0) { this.def_var(p.text, p.ts, p); };
                    i++;
                };
                this.walk(fn.a);
                this.cur_fn = prev_fn;
                this.cur_ret = prev_ret;
                st_exit_scope(this.st);
                return;
            };

            def walk_type_func(Node* tf) -> void
            {
                Node* prev_fn = this.cur_fn;
                TypeSpec* prev_ret = this.cur_ret;
                Node* p;
                int i;
                int cnt = node_count(tf, 0);
                if (tf.a == (Node*)0) { return; };
                st_enter_scope(this.st);
                this.cur_fn = tf;
                this.cur_ret = tf.ts;
                this.def_var(g"_\0", tf.ts2, tf);
                while (i < cnt)
                {
                    p = node_child(tf, 0, i);
                    if (p.text != (byte*)0) { this.def_var(p.text, p.ts, p); };
                    i++;
                };
                this.walk(tf.a);
                this.cur_fn = prev_fn;
                this.cur_ret = prev_ret;
                st_exit_scope(this.st);
                return;
            };

            // Struct, object and union definitions: member initializers and methods
            def walk_aggregate(Node* d) -> void
            {
                byte* prev_obj = this.cur_obj;
                Node* m;
                int i, cnt;
                if (d.kind == NodeKind.OBJECT_DEF)
                {
                    if (d.d != (Node*)0) { return; };
                    if (d.text != (byte*)0) { this.cur_obj = d.text; };
                };
                if (d.kind == NodeKind.STRUCT_DEF)
                {
                    if (node_count(d, 4) > 0) { return; };
                };
                cnt = node_count(d, 0);
                while (i < cnt)
                {
                    m = node_child(d, 0, i);
                    if (m.a != (Node*)0) { this.type_of(m.a); };
                    i++;
                };
                if (d.kind == NodeKind.OBJECT_DEF)
                {
                    cnt = node_count(d, 1);
                    i = 0;
                    while (i < cnt)
                    {
                        this.walk(node_child(d, 1, i));
                        i++;
                    };
                };
                cnt = node_count(d, 3);
                i = 0;
                while (i < cnt)
                {
                    this.walk(node_child(d, 3, i));
                    i++;
                };
                cnt = node_count(d, 4);
                i = 0;
                if (d.kind == NodeKind.OBJECT_DEF)
                {
                    while (i < cnt)
                    {
                        this.walk(node_child(d, 4, i));
                        i++;
                    };
                };
                this.cur_obj = prev_obj;
                return;
            };

            def walk_namespace(Node* ns) -> void
            {
                byte* prev = ts_dup(this.st.current_ns);
                byte* full;
                int s, c, e, w;
                Node* lst;
                if (ns.text == (byte*)0)
                {
                    ffree(prev);
                    return;
                };
                if (prev[0] == 0) { full = ts_dup(ns.text); }
                else { full = join3(prev, g"::\0", ns.text); };
                st_set_namespace(this.st, full);
                while (s < 6)
                {
                    c = node_count(ns, s);
                    e = 0;
                    while (e < c)
                    {
                        this.walk(node_child(ns, s, e));
                        e++;
                    };
                    s++;
                };
                while (w < 2)
                {
                    if (w == 0) { lst = ns.a; } else { lst = ns.b; };
                    if (lst != (Node*)0)
                    {
                        c = node_count(lst, 0);
                        e = 0;
                        while (e < c)
                        {
                            this.walk(node_child(lst, 0, e));
                            e++;
                        };
                    };
                    w++;
                };
                st_set_namespace(this.st, prev);
                ffree(prev);
                ffree(full);
                return;
            };

            def walk_var_decl(Node* n) -> void
            {
                TypeSpec* it = (TypeSpec*)0;
                TypeSpec* ts = n.ts;
                bool chk = false;
                if (n.a != (Node*)0) { it = this.type_of(n.a); };
                if (ts != (TypeSpec*)0)
                {
                    if (ts.storage_class == StorageClass.AUTO & ts.base_type == DataType.VOID) { ts = it; }
                    else
                    {
                        ts = this.infer_decl(ts, n.a);
                        chk = true;
                    };
                };
                if (chk & !st_is_global_scope(this.st))
                {
                    if (this.init_converts(n, ts)) { this.conv_check(ts, n.a, Site.STORE); };
                };
                if (n.text != (byte*)0) { this.def_var(n.text, ts, n); };
                n.ety = ts;
                return;
            };

            def walk_destructure(Node* n) -> void
            {
                TypeSpec* src = this.type_of(n.a);
                FXC_SYMENTRY* e = this.type_entry(src);
                Node* dn = (Node*)0;
                Node* v;
                Node* m;
                TypeSpec* vt;
                int i;
                int cnt = node_count(n, 0);
                if (e != (FXC_SYMENTRY*)0) { dn = (Node*)e.node; };
                while (i < cnt)
                {
                    v = node_child(n, 0, i);
                    vt = (TypeSpec*)0;
                    if (v.kind == NodeKind.VARIABLE_DECLARATION) { vt = v.ts; }
                    elif (dn != (Node*)0)
                    {
                        if (i < node_count(dn, 0))
                        {
                            m = node_child(dn, 0, i);
                            vt = m.ts;
                        };
                    };
                    if (v.text != (byte*)0) { this.def_var(v.text, vt, v); };
                    i++;
                };
                return;
            };

            def walk_for_in(Node* n) -> void
            {
                TypeSpec* it;
                TypeSpec* et;
                TypeSpec* vt;
                FXC_SYMENTRY* e;
                Node* dn;
                Node* v;
                Node* m;
                int i;
                int cnt = node_count(n, 0);
                st_enter_scope(this.st);
                it = this.type_of(n.a);
                et = this.elem_of(it);
                dn = (Node*)0;
                if ((n.flags `& NF_DESTRUCTURE) != 0)
                {
                    e = this.type_entry(et);
                    if (e != (FXC_SYMENTRY*)0) { dn = (Node*)e.node; };
                };
                while (i < cnt)
                {
                    v = node_child(n, 0, i);
                    vt = et;
                    if ((n.flags `& NF_DESTRUCTURE) != 0)
                    {
                        vt = (TypeSpec*)0;
                        if (dn != (Node*)0)
                        {
                            if (i < node_count(dn, 0))
                            {
                                m = node_child(dn, 0, i);
                                vt = m.ts;
                            };
                        };
                    }
                    elif (i > 0) { vt = (TypeSpec*)0; };
                    if (v.text != (byte*)0) { this.def_var(v.text, vt, v); };
                    i++;
                };
                this.walk(n.b);
                st_exit_scope(this.st);
                return;
            };

            def walk_try(Node* n) -> void
            {
                Node* cc;
                int i;
                int cnt = node_count(n, 0);
                this.walk(n.a);
                while (i < cnt)
                {
                    cc = node_child(n, 0, i);
                    st_enter_scope(this.st);
                    if (cc.text != (byte*)0) { this.def_var(cc.text, cc.ts, cc); };
                    this.walk(cc.a);
                    st_exit_scope(this.st);
                    i++;
                };
                return;
            };

            def walk(Node* n) -> void
            {
                if (n == (Node*)0) { return; };
                int k = n.kind;
                if (is_expr_kind(k))
                {
                    this.type_of(n);
                    return;
                };
                if (k == NodeKind.BLOCK)
                {
                    st_enter_scope(this.st);
                    this.walk_list(n, 0);
                    st_exit_scope(this.st);
                    return;
                };
                if (k == NodeKind.VARIABLE_DECLARATION)
                {
                    this.walk_var_decl(n);
                    return;
                };
                if (k == NodeKind.ASSIGNMENT | k == NodeKind.COMPOUND_ASSIGNMENT | k == NodeKind.TERNARY_ASSIGN)
                {
                    this.type_raw(n.a);
                    this.type_of(n.b);
                    if (k == NodeKind.ASSIGNMENT | k == NodeKind.TERNARY_ASSIGN)
                    {
                        if (n.a != (Node*)0) { this.conv_check(n.a.ety, n.b, Site.STORE); };
                    };
                    return;
                };
                if (k == NodeKind.RETURN_STATEMENT)
                {
                    // A function returning an aggregate gets the value itself, not its __expr
                    if (this.kind_of(this.cur_ret) == TyKind.AGG) { this.type_raw(n.a); }
                    else { this.type_of(n.a); };
                    if (this.cur_ret != (TypeSpec*)0 & n.a != (Node*)0)
                    {
                        if (this.cur_ret.base_type != DataType.THIS & this.cur_ret.base_type != DataType.VOID)
                        {
                            this.conv_check(this.cur_ret, n.a, Site.RETURN);
                        };
                    };
                    return;
                };
                if (k == NodeKind.FUNCTION_DEF | k == NodeKind.OBJECT_METHOD)
                {
                    this.walk_function(n);
                    return;
                };
                if (k == NodeKind.TYPE_FUNC_DEF)
                {
                    this.walk_type_func(n);
                    return;
                };
                if (k == NodeKind.FUNCTION_DEF_STATEMENT | k == NodeKind.STRUCT_DEF_STATEMENT |
                    k == NodeKind.OBJECT_DEF_STATEMENT | k == NodeKind.UNION_DEF_STATEMENT |
                    k == NodeKind.NAMESPACE_DEF_STATEMENT | k == NodeKind.ENUM_DEF_STATEMENT |
                    k == NodeKind.MACRO_DEF_STATEMENT)
                {
                    this.walk(n.a);
                    return;
                };
                if (k == NodeKind.OBJECT_DEF | k == NodeKind.STRUCT_DEF)
                {
                    this.walk_aggregate(n);
                    return;
                };
                if (k == NodeKind.NAMESPACE_DEF)
                {
                    this.walk_namespace(n);
                    return;
                };
                if (k == NodeKind.EXTERN_BLOCK | k == NodeKind.EXPORT_BLOCK | k == NodeKind.PROGRAM)
                {
                    this.walk_list(n, 0);
                    return;
                };
                if (k == NodeKind.USING_STATEMENT)
                {
                    if (n.text != (byte*)0) { st_add_using_namespace(this.st, n.text); };
                    return;
                };
                if (k == NodeKind.NOT_USING_STATEMENT)
                {
                    if (n.text != (byte*)0) { st_remove_using_namespace(this.st, n.text); };
                    return;
                };
                if (k == NodeKind.FOR_LOOP)
                {
                    st_enter_scope(this.st);
                    this.walk_children(n);
                    st_exit_scope(this.st);
                    return;
                };
                if (k == NodeKind.FOR_IN_LOOP)
                {
                    this.walk_for_in(n);
                    return;
                };
                if (k == NodeKind.TRY_BLOCK)
                {
                    this.walk_try(n);
                    return;
                };
                if (k == NodeKind.DESTRUCTURING_ASSIGNMENT)
                {
                    this.walk_destructure(n);
                    return;
                };
                if (k == NodeKind.DUAL_ASSIGN_DECLARATION)
                {
                    this.type_of(n.a);
                    if (n.text != (byte*)0) { this.def_var(n.text, n.ts, n); };
                    if (n.text2 != (byte*)0) { this.def_var(n.text2, n.ts2, n); };
                    return;
                };
                if (k == NodeKind.FUNCTION_POINTER_DECLARATION)
                {
                    this.type_of(n.a);
                    if (n.text != (byte*)0) { this.def_var(n.text, n.ts, n); };
                    return;
                };
                if (k == NodeKind.ENUM_DEF | k == NodeKind.UNION_DEF | k == NodeKind.TRAIT_DEF |
                    k == NodeKind.INTERFACE_DEF | k == NodeKind.CONTRACT_DEF | k == NodeKind.CONSTRA_DEF |
                    k == NodeKind.MACRO_DEF | k == NodeKind.EFFECT_DEF | k == NodeKind.EMIT_FLUX |
                    k == NodeKind.COMPTIME_BLOCK | k == NodeKind.INLINE_ASM | k == NodeKind.FLUXVM_BLOCK |
                    k == NodeKind.TYPE_DECLARATION | k == NodeKind.STRUCT_MEMBER | k == NodeKind.UNION_MEMBER)
                {
                    return;
                };
                this.walk_children(n);
                return;
            };

            // Types every expression of a parsed program
            def walk_program(Node* prog) -> void
            {
                this.walk_list(prog, 0);
                return;
            };

            // Prints up to limit expressions that stayed untyped
            def print_unknown(byte* path, int limit) -> void
            {
                int i;
                Node* n;
                while (i < this.unk.len)
                {
                    if (i >= limit) { break; };
                    n = (Node*)this.unk.items[i];
                    print(path);
                    print(g":\0");
                    print(n.line);
                    print(g":\0");
                    print(n.col);
                    print(g": untyped \0");
                    print(node_kind_name(n.kind));
                    if (n.text != (byte*)0)
                    {
                        print(g" \0");
                        print(n.text);
                    };
                    println(g"\0");
                    i++;
                };
                return;
            };
        };
    };
};

#endif;
