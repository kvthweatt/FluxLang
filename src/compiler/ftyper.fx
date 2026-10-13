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

        match_at(byte* s, int i, byte* lit) -> bool
        {
            int j;
            while (lit[j] != 0)
            {
                switch (s[i + j] != lit[j])
                {
                    case (true) { -> false; }
                    default {};
                };
                j++;
            };
            -> true;
        };

        // Length of the multi character operator part at s[i], 1 when there is none
        op_part_len(byte* s, int i) -> int
        {
            switch (match_at(s, i, g"^|!&\0"))
            {
                case (true) { -> 4; }
                default {};
            };
            switch (match_at(s, i, g"^|!|\0"))
            {
                case (true) { -> 4; }
                default {};
            };
            switch (match_at(s, i, g"^|!\0"))
            {
                case (true) { -> 3; }
                default {};
            };
            switch (match_at(s, i, g"`!&\0"))
            {
                case (true) { -> 3; }
                default {};
            };
            switch (match_at(s, i, g"`!|\0"))
            {
                case (true) { -> 3; }
                default {};
            };
            switch (match_at(s, i, g"`^|\0"))
            {
                case (true) { -> 3; }
                default {};
            };
            switch (match_at(s, i, g"^|\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g"!&\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g"!|\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g"<=\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g">=\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g"==\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g"!=\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g"++\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g"--\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g"<<\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            switch (match_at(s, i, g">>\0"))
            {
                case (true) { -> 2; }
                default {};
            };
            -> 1;
        };

        op_char_word(byte c) -> byte*
        {
            switch (c == '+')
            {
                case (true) { -> g"plus\0"; }
                default {};
            };
            switch (c == '-')
            {
                case (true) { -> g"minus\0"; }
                default {};
            };
            switch (c == '*')
            {
                case (true) { -> g"mul\0"; }
                default {};
            };
            switch (c == '/')
            {
                case (true) { -> g"div\0"; }
                default {};
            };
            switch (c == '%')
            {
                case (true) { -> g"mod\0"; }
                default {};
            };
            switch (c == '!')
            {
                case (true) { -> g"not\0"; }
                default {};
            };
            switch (c == '^')
            {
                case (true) { -> g"pow\0"; }
                default {};
            };
            switch (c == '&')
            {
                case (true) { -> g"and\0"; }
                default {};
            };
            switch (c == '|')
            {
                case (true) { -> g"or\0"; }
                default {};
            };
            switch (c == '<')
            {
                case (true) { -> g"lt\0"; }
                default {};
            };
            switch (c == '>')
            {
                case (true) { -> g"gt\0"; }
                default {};
            };
            switch (c == '=')
            {
                case (true) { -> g"eq\0"; }
                default {};
            };
            switch (c == '~')
            {
                case (true) { -> g"tilde\0"; }
                default {};
            };
            switch (c == '`')
            {
                case (true) { -> g"tick\0"; }
                default {};
            };
            -> (byte*)0;
        };

        hex_char(int v) -> int
        {
            switch (v < 10)
            {
                case (true) { -> 48 + v; }
                default {};
            };
            -> 97 + v - 10;
        };

        // Appends the mangled form of a builtin operator symbol to out
        mangle_builtin_op(Buf* out, byte* sym) -> void
        {
            int i, j, plen;
            byte* w;
            bool first_part = true;
            int c;
            while (sym[i] != 0)
            {
                plen = op_part_len(sym, i);
                switch (!first_part)
                {
                    case (true) { out.put('_'); }
                    default {};
                };
                first_part = false;
                j = 0;
                while (j < plen)
                {
                    switch (j > 0)
                    {
                        case (true) { out.put('_'); }
                        default {};
                    };
                    w = op_char_word(sym[i + j]);
                    switch (w != (byte*)0)
                    {
                        case (true) { out.put_str(w); }
                        default {
                        c = (int)sym[i + j];
                        out.put_str(g"0x\0");
                        switch (c / 16 > 0)
                        {
                            case (true) { out.put(hex_char(c / 16)); }
                            default {};
                        };
                        out.put(hex_char(c % 16));
                    };
                    };
                    j++;
                };
                i = i + plen;
            };
            ->;
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

        conv_name(int c) -> byte*
        {
            switch (c)
            {
                case (Conv.EXACT)        { -> g"exact\0"; }
                case (Conv.INT_WIDEN)    { -> g"int widen\0"; }
                case (Conv.INT_NARROW)   { -> g"int narrow\0"; }
                case (Conv.INT_TO_FLOAT) { -> g"int to float\0"; }
                case (Conv.FLOAT_TO_INT) { -> g"float to int\0"; }
                case (Conv.FLOAT_EXT)    { -> g"float extend\0"; }
                case (Conv.FLOAT_TRUNC)  { -> g"float truncate\0"; }
                case (Conv.PTR_CAST)     { -> g"pointer cast\0"; }
                case (Conv.PTR_TO_INT)   { -> g"pointer to int\0"; }
                case (Conv.INT_TO_PTR)   { -> g"int to pointer\0"; }
                case (Conv.ARRAY_DECAY)  { -> g"array decay\0"; }
                case (Conv.ARRAY_COPY)   { -> g"array copy\0"; }
                case (Conv.ARRAY_PACK)   { -> g"array pack\0"; }
                case (Conv.STRUCT_LOAD)  { -> g"struct load\0"; }
                case (Conv.EXPR_CALL)    { -> g"__expr call\0"; }
                case (Conv.INVALID)      { -> g"invalid\0"; }
                default                  { -> g"none\0"; };
            };
            -> g"none\0";
        };

        site_name(int s) -> byte*
        {
            switch (s == Site.ARG)
            {
                case (true) { -> g"argument\0"; }
                default {};
            };
            switch (s == Site.RETURN)
            {
                case (true) { -> g"return\0"; }
                default {};
            };
            -> g"assignment\0";
        };

        ends_with(byte* s, byte* suf) -> bool
        {
            int ls = pp_cstrlen(s);
            int lf = pp_cstrlen(suf);
            int i;
            switch (lf > ls)
            {
                case (true) { -> false; }
                default {};
            };
            while (i < lf)
            {
                switch (s[ls - lf + i] != suf[i])
                {
                    case (true) { -> false; }
                    default {};
                };
                i++;
            };
            -> true;
        };

        // Kinds of node that are expressions (typed by ExprTyper.type_of)
        is_expr_kind(int k) -> bool
        {
            switch (k == NodeKind.LITERAL | k == NodeKind.IDENTIFIER | k == NodeKind.ARRAY_LITERAL |
                k == NodeKind.STRING_LITERAL | k == NodeKind.BINARY_OP | k == NodeKind.IN_EXPRESSION |
                k == NodeKind.HAS_EXPRESSION | k == NodeKind.UNARY_OP | k == NodeKind.CAST_EXPRESSION |
                k == NodeKind.TYPE_CONVERT_EXPRESSION | k == NodeKind.RANGE_EXPRESSION |
                k == NodeKind.ARRAY_COMPREHENSION | k == NodeKind.F_STRING_LITERAL |
                k == NodeKind.FUNCTION_CALL | k == NodeKind.MEMBER_ACCESS | k == NodeKind.METHOD_CALL)
            {
                case (true) {
                -> true;
            }
                default {};
            };
            switch (k == NodeKind.VARIADIC_ACCESS | k == NodeKind.ARRAY_ACCESS | k == NodeKind.ARRAY_SLICE |
                k == NodeKind.BIT_SLICE | k == NodeKind.BIT_INDEX_ACCESS | k == NodeKind.POINTER_DEREF |
                k == NodeKind.ADDRESS_OF | k == NodeKind.STRINGIFY | k == NodeKind.CODIFY |
                k == NodeKind.ALIGN_OF | k == NodeKind.TYPE_OF | k == NodeKind.SIZE_OF |
                k == NodeKind.ENDIAN_OF | k == NodeKind.NO_INIT | k == NodeKind.IF_EXPRESSION |
                k == NodeKind.TERNARY_OP | k == NodeKind.NULL_COALESCE | k == NodeKind.NOT_NULL)
            {
                case (true) {
                -> true;
            }
                default {};
            };
            switch (k == NodeKind.FUNCTION_POINTER_CALL | k == NodeKind.TIE_EXPRESSION |
                k == NodeKind.STRUCT_INSTANCE | k == NodeKind.STRUCT_LITERAL |
                k == NodeKind.STRUCT_FIELD_ACCESS | k == NodeKind.STRUCT_RECAST |
                k == NodeKind.TYPE_FUNC_CALL | k == NodeKind.DICT_LITERAL_EXPR |
                k == NodeKind.DICT_LITERAL | k == NodeKind.MACRO_CALL)
            {
                case (true) {
                -> true;
            }
                default {};
            };
            -> false;
        };

        // Expression kinds whose value has no TypeSpec representation. They stay
        // untyped without being counted as unresolved.
        is_untyped_kind(int k) -> bool -> k == NodeKind.NO_INIT | k == NodeKind.RANGE_EXPRESSION | k == NodeKind.ARRAY_COMPREHENSION | k == NodeKind.MACRO_CALL;

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

            __init(FXC_SYMTABLE* table) -> this
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
                -> this;
            };

            __expr() -> ExprTyper* -> this;

            __exit() -> void
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
                ->;
            };

            clear_mb() -> void
            {
                this.mb.len = 0;
                switch (this.mb.mem != (byte*)0)
                {
                    case (true) { this.mb.mem[0] = (byte)0; }
                    default {};
                };
                ->;
            };

            // ----------------------------------------------------------
            // Construction
            // ----------------------------------------------------------

            keep(TypeSpec* t) -> TypeSpec*
            {
                switch (t != (TypeSpec*)0)
                {
                    case (true) { pv_push(this.arena, (void*)t); }
                    default {};
                };
                -> t;
            };

            mk(int base, int flags, int width) -> TypeSpec*
            {
                TypeSpec* t = typespec_new();
                t.base_type = base;
                t.flags = flags;
                t.bit_width = width;
                -> this.keep(t);
            };

            // Integer of an exact LLVM width. Arithmetic results carry only the
            // signedness (UINT or SINT) exactly as attach_type_metadata does.
            mk_int(int width, bool uns) -> TypeSpec*
            {
                switch (width == 1)
                {
                    case (true) { -> this.mk(DataType.BOOL, 0, -1); }
                    default {};
                };
                switch (uns)
                {
                    case (true) { -> this.mk(DataType.UINT, 0, width); }
                    default {};
                };
                -> this.mk(DataType.SINT, TS_SIGNED, width);
            };

            mk_named(int base, byte* name) -> TypeSpec*
            {
                TypeSpec* t = this.mk(base, 0, -1);
                t.custom_typename = name;
                -> t;
            };

            ptr_to(TypeSpec* t) -> TypeSpec*
            {
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> t; }
                    default {};
                };
                TypeSpec* c = typespec_clone(t);
                c.flags = c.flags `| TS_POINTER;
                c.pointer_depth = c.pointer_depth + 1;
                -> this.keep(c);
            };

            byte_ptr() -> TypeSpec*
            {
                TypeSpec* t = this.mk(DataType.BYTE, TS_POINTER, -1);
                t.pointer_depth = 1;
                -> t;
            };

            // Integer literal node used as an array size (owned by the typer)
            size_node(int v) -> Node*
            {
                Node* s = node_new(NodeKind.LITERAL, 0, 0);
                s.op = DataType.SINT;
                s.ival = (i64)v;
                pv_push(this.anodes, (void*)s);
                -> s;
            };

            pointee_of(TypeSpec* t) -> TypeSpec*
            {
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> t; }
                    default {};
                };
                switch (t.pointer_depth <= 0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                TypeSpec* c = typespec_clone(t);
                c.pointer_depth = c.pointer_depth - 1;
                switch (c.pointer_depth == 0)
                {
                    case (true) {
                    switch (ts_is_pointer(c))
                    {
                        case (true) { c.flags = c.flags - TS_POINTER; }
                        default {};
                    };
                }
                    default {};
                };
                -> this.keep(c);
            };

            // ----------------------------------------------------------
            // Classification
            // ----------------------------------------------------------

            // Follows type aliases (def ... as name) to the underlying spec.
            // An alias used with extra pointer depth keeps that depth.
            resolve_alias(TypeSpec* t) -> TypeSpec*
            {
                TypeSpec* cur = t;
                TypeSpec* tgt;
                TypeSpec* c;
                FXC_SYMENTRY* e;
                int guard;
                while (guard < 16)
                {
                    switch (cur == (TypeSpec*)0)
                    {
                        case (true) { -> cur; }
                        default {};
                    };
                    switch (cur.custom_typename == (byte*)0)
                    {
                        case (true) { -> cur; }
                        default {};
                    };
                    e = st_lookup_type(this.st, cur.custom_typename, (byte*)0);
                    switch (e == (FXC_SYMENTRY*)0)
                    {
                        case (true) { -> cur; }
                        default {};
                    };
                    switch (e.kind_id != SymbolKind.TYPE)
                    {
                        case (true) { -> cur; }
                        default {};
                    };
                    tgt = (TypeSpec*)e.ts;
                    switch (tgt == (TypeSpec*)0)
                    {
                        case (true) { -> cur; }
                        default {};
                    };
                    switch (cur.pointer_depth > 0 | ts_is_array(cur))
                    {
                        case (true) {
                        c = typespec_clone(tgt);
                        c.pointer_depth = c.pointer_depth + cur.pointer_depth;
                        switch (cur.pointer_depth > 0)
                        {
                            case (true) { c.flags = c.flags `| TS_POINTER; }
                            default {};
                        };
                        switch (ts_is_array(cur))
                        {
                            case (true) {
                            c.flags = c.flags `| TS_ARRAY;
                            c.array_size = cur.array_size;
                            c.array_dims = cur.array_dims;
                        }
                            default {};
                        };
                        cur = this.keep(c);
                    }
                        default { cur = tgt; };
                    };
                    guard++;
                };
                -> cur;
            };

            kind_of(TypeSpec* t) -> int
            {
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> TyKind.UNKNOWN; }
                    default {};
                };
                TypeSpec* a = this.resolve_alias(t);
                FXC_SYMENTRY* e;
                int b;
                switch (ts_is_array(a))
                {
                    case (true) {
                    switch (a.array_size != (Node*)0)
                    {
                        case (true) { -> TyKind.ARRAY; }
                        default {};
                    };
                    switch (a.array_dims != (NodeVec*)0)
                    {
                        case (true) {
                        switch (a.array_dims.len > 0)
                        {
                            case (true) {
                            switch (a.array_dims.items[0] != (Node*)0)
                            {
                                case (true) { -> TyKind.ARRAY; }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    -> TyKind.PTR;
                }
                    default {};
                };
                switch (ts_is_pointer(a))
                {
                    case (true) { -> TyKind.PTR; }
                    default {};
                };
                switch (a.custom_typename != (byte*)0)
                {
                    case (true) {
                    e = st_lookup_type(this.st, a.custom_typename, (byte*)0);
                    switch (e == (FXC_SYMENTRY*)0)
                    {
                        case (true) { -> TyKind.UNKNOWN; }
                        default {};
                    };
                    switch (e.kind_id == SymbolKind.STRUCT | e.kind_id == SymbolKind.OBJECT |
                        e.kind_id == SymbolKind.UNION)
                    {
                        case (true) {
                        -> TyKind.AGG;
                    }
                        default {};
                    };
                    switch (e.kind_id == SymbolKind.ENUM)
                    {
                        case (true) { -> TyKind.INT; }
                        default {};
                    };
                    -> TyKind.UNKNOWN;
                }
                    default {};
                };
                b = a.base_type;
                switch (b == DataType.SINT | b == DataType.UINT | b == DataType.SLONG | b == DataType.ULONG |
                    b == DataType.BOOL | b == DataType.CHAR | b == DataType.BYTE | b == DataType.DATA |
                    b == DataType.ENUM | b == DataType.STRUCT | b == DataType.OBJECT)
                {
                    case (true) {
                    -> TyKind.INT;
                }
                    default {};
                };
                switch (b == DataType.FLOAT)
                {
                    case (true) { -> TyKind.FLOAT; }
                    default {};
                };
                switch (b == DataType.DOUBLE)
                {
                    case (true) { -> TyKind.DOUBLE; }
                    default {};
                };
                switch (b == DataType.VOID)
                {
                    case (true) { -> TyKind.VOID; }
                    default {};
                };
                switch (b == DataType.THIS)
                {
                    case (true) { -> TyKind.PTR; }
                    default {};
                };
                switch (b == DataType.FUNC_PTR)
                {
                    case (true) { -> TyKind.FUNC; }
                    default {};
                };
                switch (b == DataType.DICT)
                {
                    case (true) { -> TyKind.DICT; }
                    default {};
                };
                switch (b == DataType.UNION)
                {
                    case (true) { -> TyKind.AGG; }
                    default {};
                };
                -> TyKind.UNKNOWN;
            };

            // Bit width of an integer typed value, 0 when it has none
            width_of(TypeSpec* t) -> int
            {
                TypeSpec* a = this.resolve_alias(t);
                int b;
                switch (a == (TypeSpec*)0)
                {
                    case (true) { -> 0; }
                    default {};
                };
                switch (a.custom_typename != (byte*)0)
                {
                    case (true) { -> 32; }
                    default {};
                };
                b = a.base_type;
                switch (b == DataType.SINT | b == DataType.UINT)
                {
                    case (true) {
                    switch (a.bit_width > 0)
                    {
                        case (true) { -> a.bit_width; }
                        default {};
                    };
                    -> 32;
                }
                    default {};
                };
                switch (b == DataType.SLONG | b == DataType.ULONG)
                {
                    case (true) { -> 64; }
                    default {};
                };
                switch (b == DataType.BOOL)
                {
                    case (true) { -> 1; }
                    default {};
                };
                switch (b == DataType.CHAR)
                {
                    case (true) { -> 8; }
                    default {};
                };
                switch (b == DataType.STRUCT | b == DataType.OBJECT)
                {
                    case (true) { -> 8; }
                    default {};
                };
                switch (b == DataType.ENUM)
                {
                    case (true) { -> 32; }
                    default {};
                };
                switch (b == DataType.BYTE)
                {
                    case (true) {
                    switch (a.bit_width > 0)
                    {
                        case (true) { -> a.bit_width; }
                        default {};
                    };
                    -> 8;
                }
                    default {};
                };
                switch (b == DataType.DATA)
                {
                    case (true) {
                    switch (a.bit_width > 0)
                    {
                        case (true) { -> a.bit_width; }
                        default {};
                    };
                    -> 0;
                }
                    default {};
                };
                -> 0;
            };

            // CoercionContext.is_unsigned over a TypeSpec
            uns_of(TypeSpec* t) -> bool
            {
                TypeSpec* a = this.resolve_alias(t);
                switch (a == (TypeSpec*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (a.custom_typename != (byte*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (a.base_type == DataType.UINT)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (a.base_type == DataType.BYTE)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (a.base_type == DataType.DATA)
                {
                    case (true) { -> !ts_is_signed(a); }
                    default {};
                };
                -> false;
            };

            // Element type of an array or pointee of a pointer
            elem_of(TypeSpec* t) -> TypeSpec*
            {
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> t; }
                    default {};
                };
                TypeSpec* a = this.resolve_alias(t);
                TypeSpec* c;
                NodeVec* d;
                NodeVec* sh;
                int i;
                switch (ts_is_array(a))
                {
                    case (true) {
                    c = typespec_clone(a);
                    d = a.array_dims;
                    switch (d != (NodeVec*)0)
                    {
                        case (true) {
                        switch (d.len > 1)
                        {
                            case (true) {
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
                            -> this.keep(c);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    c.flags = c.flags - TS_ARRAY;
                    c.array_size = (Node*)0;
                    c.array_dims = (NodeVec*)0;
                    -> this.keep(c);
                }
                    default {};
                };
                switch (ts_is_pointer(a))
                {
                    case (true) { -> this.pointee_of(a); }
                    default {};
                };
                -> (TypeSpec*)0;
            };

            // Pointer to a value of type t. An array decays to a pointer to its element.
            addr_of_type(TypeSpec* t) -> TypeSpec*
            {
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> t; }
                    default {};
                };
                TypeSpec* a = this.resolve_alias(t);
                switch (ts_is_array(a))
                {
                    case (true) { -> this.ptr_to(this.elem_of(a)); }
                    default {};
                };
                -> this.ptr_to(a);
            };

            // Declared size of a one dimensional array, -1 when it is not a literal
            array_len(TypeSpec* t) -> int
            {
                TypeSpec* a = this.resolve_alias(t);
                Node* d0;
                switch (a == (TypeSpec*)0)
                {
                    case (true) { -> -1; }
                    default {};
                };
                d0 = a.array_size;
                switch (a.array_dims != (NodeVec*)0)
                {
                    case (true) {
                    switch (a.array_dims.len != 1)
                    {
                        case (true) { -> -1; }
                        default {};
                    };
                    d0 = a.array_dims.items[0];
                }
                    default {};
                };
                switch (d0 == (Node*)0)
                {
                    case (true) { -> -1; }
                    default {};
                };
                switch (d0.kind != NodeKind.LITERAL)
                {
                    case (true) { -> -1; }
                    default {};
                };
                -> (int)d0.ival;
            };

            // Same LLVM type for pointers: equal depth and equal pointee
            ptr_same(TypeSpec* a, TypeSpec* b) -> bool
            {
                TypeSpec* ra = this.resolve_alias(a);
                TypeSpec* rb = this.resolve_alias(b);
                TypeSpec* ba;
                TypeSpec* bb;
                int da = ra.pointer_depth;
                int db = rb.pointer_depth;
                switch (ts_is_array(ra))
                {
                    case (true) { da = da + 1; }
                    default {};
                };
                switch (ts_is_array(rb))
                {
                    case (true) { db = db + 1; }
                    default {};
                };
                switch (da != db)
                {
                    case (true) { -> false; }
                    default {};
                };
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
                switch (ba.base_type == DataType.VOID & ba.custom_typename == (byte*)0)
                {
                    case (true) {
                    ba.base_type = DataType.CHAR;
                }
                    default {};
                };
                switch (bb.base_type == DataType.VOID & bb.custom_typename == (byte*)0)
                {
                    case (true) {
                    bb.base_type = DataType.CHAR;
                }
                    default {};
                };
                this.keep(ba);
                this.keep(bb);
                -> this.ty_same(ba, bb);
            };

            agg_same(TypeSpec* a, TypeSpec* b) -> bool
            {
                TypeSpec* ra = this.resolve_alias(a);
                TypeSpec* rb = this.resolve_alias(b);
                FXC_SYMENTRY* ea;
                FXC_SYMENTRY* eb;
                switch (ra.custom_typename == (byte*)0 | rb.custom_typename == (byte*)0)
                {
                    case (true) {
                    -> ra.base_type == rb.base_type;
                }
                    default {};
                };
                ea = st_lookup_type(this.st, ra.custom_typename, (byte*)0);
                eb = st_lookup_type(this.st, rb.custom_typename, (byte*)0);
                switch (ea != (FXC_SYMENTRY*)0 & eb != (FXC_SYMENTRY*)0)
                {
                    case (true) {
                    -> (u64)ea.node == (u64)eb.node;
                }
                    default {};
                };
                -> cstr_eq(ra.custom_typename, rb.custom_typename);
            };

            // True when a and b have the same LLVM type
            ty_same(TypeSpec* a, TypeSpec* b) -> bool
            {
                int ka = this.kind_of(a);
                int kb = this.kind_of(b);
                int la, lb;
                switch (ka != kb)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (ka == TyKind.UNKNOWN)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (ka == TyKind.INT)
                {
                    case (true) { -> this.width_of(a) == this.width_of(b); }
                    default {};
                };
                switch (ka == TyKind.PTR)
                {
                    case (true) { -> this.ptr_same(a, b); }
                    default {};
                };
                switch (ka == TyKind.AGG)
                {
                    case (true) { -> this.agg_same(a, b); }
                    default {};
                };
                switch (ka == TyKind.ARRAY)
                {
                    case (true) {
                    la = this.array_len(a);
                    lb = this.array_len(b);
                    switch (la != lb)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    -> this.ty_same(this.elem_of(a), this.elem_of(b));
                }
                    default {};
                };
                -> true;
            };

            // Argument of type at is accepted by a parameter of type pt without conversion
            // (same type, array decay, or pointer to the struct passed by value and back)
            arg_matches(TypeSpec* pt, TypeSpec* at) -> bool
            {
                int kp = this.kind_of(pt);
                int ka = this.kind_of(at);
                TypeSpec* rp;
                TypeSpec* ra;
                switch (this.ty_same(pt, at))
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (kp == TyKind.PTR & ka == TyKind.ARRAY)
                {
                    case (true) {
                    -> this.ty_same(this.elem_of(pt), this.elem_of(at));
                }
                    default {};
                };
                switch (kp == TyKind.PTR & ka == TyKind.AGG)
                {
                    case (true) {
                    rp = this.resolve_alias(pt);
                    switch (rp.pointer_depth == 1)
                    {
                        case (true) { -> this.ty_same(this.elem_of(pt), at); }
                        default {};
                    };
                }
                    default {};
                };
                switch (kp == TyKind.AGG & ka == TyKind.PTR)
                {
                    case (true) {
                    ra = this.resolve_alias(at);
                    switch (ra.pointer_depth == 1)
                    {
                        case (true) { -> this.ty_same(pt, this.elem_of(at)); }
                        default {};
                    };
                }
                    default {};
                };
                -> false;
            };

            // ----------------------------------------------------------
            // Declarations
            // ----------------------------------------------------------

            type_entry(TypeSpec* t) -> FXC_SYMENTRY*
            {
                TypeSpec* a = this.resolve_alias(t);
                switch (a == (TypeSpec*)0)
                {
                    case (true) { -> (FXC_SYMENTRY*)0; }
                    default {};
                };
                switch (a.custom_typename == (byte*)0)
                {
                    case (true) { -> (FXC_SYMENTRY*)0; }
                    default {};
                };
                -> st_lookup_type(this.st, a.custom_typename, (byte*)0);
            };

            // Declared type of member name of the struct, object or union type ot
            // (an enum typed value gives the enum type itself)
            member_type_of(TypeSpec* ot, byte* name) -> TypeSpec*
            {
                FXC_SYMENTRY* e = this.type_entry(ot);
                TypeSpec* a;
                Node* dn;
                Node* m;
                int i, cnt;
                switch (e == (FXC_SYMENTRY*)0 | name == (byte*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                switch (e.kind_id == SymbolKind.ENUM)
                {
                    case (true) {
                    a = this.resolve_alias(ot);
                    -> this.mk_named(DataType.ENUM, a.custom_typename);
                }
                    default {};
                };
                dn = (Node*)e.node;
                switch (dn == (Node*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                cnt = node_count(dn, 0);
                while (i < cnt)
                {
                    m = node_child(dn, 0, i);
                    switch (m.text != (byte*)0)
                    {
                        case (true) {
                        switch (cstr_eq(m.text, name))
                        {
                            case (true) { -> m.ts; }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> (TypeSpec*)0;
            };

            // First method of object definition dn called name taking argc parameters
            find_method0(Node* dn, byte* name) -> Node*
            {
                int i, cnt;
                Node* m;
                switch (dn == (Node*)0)
                {
                    case (true) { -> dn; }
                    default {};
                };
                cnt = node_count(dn, 1);
                while (i < cnt)
                {
                    m = node_child(dn, 1, i);
                    switch (m.text != (byte*)0)
                    {
                        case (true) {
                        switch (cstr_eq(m.text, name))
                        {
                            case (true) {
                            switch (node_count(m, 0) == 0)
                            {
                                case (true) { -> m; }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    i++;
                };
                -> (Node*)0;
            };

            // Return type of function fn. A this return type is a pointer to the object.
            ret_of_fn(Node* fn, byte* objname) -> TypeSpec*
            {
                switch (fn == (Node*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                TypeSpec* r = fn.ts;
                switch (r == (TypeSpec*)0)
                {
                    case (true) { -> r; }
                    default {};
                };
                switch (r.base_type == DataType.THIS)
                {
                    case (true) {
                    switch (objname == (byte*)0)
                    {
                        case (true) { -> (TypeSpec*)0; }
                        default {};
                    };
                    -> this.ptr_to(this.mk_named(DataType.OBJECT, objname));
                }
                    default {};
                };
                -> r;
            };

            // Type a variable of type vt has in expression context when its object
            // defines __expr (null when it does not)
            expr_promote(TypeSpec* vt) -> TypeSpec*
            {
                FXC_SYMENTRY* e = this.type_entry(vt);
                TypeSpec* a;
                Node* m;
                switch (vt == (TypeSpec*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                switch (e == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                switch (e.kind_id != SymbolKind.OBJECT)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                a = this.resolve_alias(vt);
                switch (a.pointer_depth > 1)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                switch (ts_is_array(a))
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                m = this.find_method0((Node*)e.node, g"__expr\0");
                switch (m == (Node*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                -> this.ret_of_fn(m, e.name);
            };

            // Type of a function used as a value (@f)
            fn_value(Node* fn) -> TypeSpec*
            {
                switch (fn == (Node*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                int cnt = node_count(fn, 0);
                int i, np;
                Node* p;
                TypeSpec* t = this.mk(DataType.FUNC_PTR, 0, -1);
                TypeSpec** ps = (TypeSpec**)fmalloc((u64)(cnt + 1) * (u64)(sizeof(TypeSpec*) / 8));
                pv_push(this.blobs, (void*)ps);
                while (i < cnt)
                {
                    p = node_child(fn, 0, i);
                    switch (p.ts != (TypeSpec*)0)
                    {
                        case (true) {
                        ps[np] = p.ts;
                        np++;
                    }
                        default {};
                    };
                    i++;
                };
                t.fp_nparams = np;
                t.fp_params = ps;
                t.fp_ret = fn.ts;
                -> t;
            };

            // ----------------------------------------------------------
            // Overloads
            // ----------------------------------------------------------

            // Overload list for name through the namespace walk
            // (the same order as st_resolve_with_namespaces)
            ov_resolve(byte* name) -> PtrVec*
            {
                PtrVec* r;
                byte* m;
                byte* walk;
                byte* p;
                bool more;
                int i;
                byte* cur = this.st.current_ns;

                switch (has_scope_sep(name))
                {
                    case (true) {
                    m = colons_to_underscores(name);
                    r = st_overloads_of(this.st, m);
                    ffree(m);
                    switch (r != (PtrVec*)0)
                    {
                        case (true) { -> r; }
                        default {};
                    };
                }
                    default {};
                };

                r = st_overloads_of(this.st, name);
                switch (r != (PtrVec*)0)
                {
                    case (true) { -> r; }
                    default {};
                };

                switch (cur[0] != 0)
                {
                    case (true) {
                    m = mangle_namespace_name(cur, name);
                    r = st_overloads_of(this.st, m);
                    ffree(m);
                    switch (r != (PtrVec*)0)
                    {
                        case (true) { -> r; }
                        default {};
                    };

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
                        switch (r != (PtrVec*)0)
                        {
                            case (true) {
                            ffree(walk);
                            -> r;
                        }
                            default {};
                        };
                    };
                    ffree(walk);
                }
                    default {};
                };

                while (i < this.st.using_ns.len)
                {
                    m = mangle_namespace_name((byte*)this.st.using_ns.items[i], name);
                    r = st_overloads_of(this.st, m);
                    ffree(m);
                    switch (r != (PtrVec*)0)
                    {
                        case (true) { -> r; }
                        default {};
                    };
                    i++;
                };

                i = 0;
                while (i < this.st.registered_ns.len)
                {
                    m = mangle_namespace_name((byte*)this.st.registered_ns.items[i], name);
                    r = st_overloads_of(this.st, m);
                    ffree(m);
                    switch (r != (PtrVec*)0)
                    {
                        case (true) { -> r; }
                        default {};
                    };
                    i++;
                };
                -> (PtrVec*)0;
            };

            // True when an argument node carries a TypeSpec in fcodegen (identifiers,
            // casts, members, elements). Literals and arithmetic results carry only
            // a DataType, calls carry nothing, so signedness, char and endianness
            // are not compared for them.
            has_spec(Node* an) -> bool
            {
                int k = an.kind;
                -> k == NodeKind.IDENTIFIER | k == NodeKind.CAST_EXPRESSION |
                       k == NodeKind.TYPE_CONVERT_EXPRESSION | k == NodeKind.MEMBER_ACCESS |
                       k == NodeKind.ARRAY_ACCESS | k == NodeKind.STRUCT_FIELD_ACCESS;
            };

            // Type of an argument used for overload selection: an object variable is
            // the object itself (the __expr promotion is undone in fcodegen)
            arg_type(Node* an) -> TypeSpec*
            {
                FXC_SYMENTRY* e;
                switch (an.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    switch (an.text != (byte*)0)
                    {
                        case (true) {
                        e = st_lookup_any(this.st, an.text, (byte*)0);
                        switch (e != (FXC_SYMENTRY*)0)
                        {
                            case (true) {
                            switch (e.kind_id == SymbolKind.VARIABLE)
                            {
                                case (true) {
                                switch ((TypeSpec*)e.ts != (TypeSpec*)0)
                                {
                                    case (true) { -> (TypeSpec*)e.ts; }
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
                -> an.ety;
            };

            exact_param(TypeSpec* pt, Node* an) -> bool
            {
                TypeSpec* at = this.arg_type(an);
                TypeSpec* rp;
                TypeSpec* ra;
                switch (pt == (TypeSpec*)0 | at == (TypeSpec*)0)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (!this.arg_matches(pt, at))
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (this.kind_of(pt) != TyKind.INT)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (this.kind_of(at) != TyKind.INT)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (!this.has_spec(an))
                {
                    case (true) { -> true; }
                    default {};
                };
                rp = this.resolve_alias(pt);
                ra = this.resolve_alias(at);
                switch (ts_is_signed(rp) != ts_is_signed(ra))
                {
                    case (true) { -> false; }
                    default {};
                };
                switch ((rp.base_type == DataType.CHAR) != (ra.base_type == DataType.CHAR))
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (rp.endianness != ra.endianness)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> true;
            };

            // The caller may leave out trailing parameters that have defaults
            count_ok(Overload* o, int argc) -> bool
            {
                int i;
                Node* p;
                switch (o.nparams == argc)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (argc > o.nparams)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (o.func == (Node*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                i = argc;
                while (i < o.nparams)
                {
                    p = node_child(o.func, 0, i);
                    switch (p.a == (Node*)0)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    i++;
                };
                -> true;
            };

            // TypeResolver._resolve_from_overloads: the first overload whose parameter
            // types match the arguments, else the first with an acceptable count
            pick_overload(PtrVec* list, NodeVec* args) -> Overload*
            {
                Overload* first = (Overload*)0;
                Overload* o;
                int i, j, np;
                int argc = 0;
                bool ok, vari;
                switch (list == (PtrVec*)0)
                {
                    case (true) { -> first; }
                    default {};
                };
                switch (args != (NodeVec*)0)
                {
                    case (true) { argc = args.len; }
                    default {};
                };
                while (i < list.len)
                {
                    o = (Overload*)list.items[i];
                    i++;
                    vari = false;
                    switch (o.func != (Node*)0)
                    {
                        case (true) {
                        switch ((o.func.flags `& NF_VARIADIC) != 0)
                        {
                            case (true) { vari = true; }
                            default {};
                        };
                    }
                        default {};
                    };
                    np = o.nparams;
                    switch (vari)
                    {
                        case (true) { ok = argc >= np; }
                        default { ok = this.count_ok(o, argc); };
                    };
                    switch (!ok)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (first == (Overload*)0)
                    {
                        case (true) { first = o; }
                        default {};
                    };
                    ok = true;
                    j = 0;
                    while (j < argc & j < np)
                    {
                        switch (!this.exact_param(o.params[j], args.items[j]))
                        {
                            case (true) {
                            ok = false;
                            break;
                        }
                            default {};
                        };
                        j++;
                    };
                    switch (ok)
                    {
                        case (true) { -> o; }
                        default {};
                    };
                };
                -> first;
            };

            // Overload of builtin operator op taking exactly (lt, rt)
            binary_overload(int op, TypeSpec* lt, TypeSpec* rt) -> Overload*
            {
                PtrVec* list;
                Overload* o;
                int i;
                switch (lt == (TypeSpec*)0 | rt == (TypeSpec*)0)
                {
                    case (true) { -> (Overload*)0; }
                    default {};
                };
                this.clear_mb();
                this.mb.put_str(g"operator__\0");
                mangle_builtin_op(@this.mb, operator_text(op));
                list = this.ov_resolve(this.mb.mem);
                switch (list == (PtrVec*)0)
                {
                    case (true) { -> (Overload*)0; }
                    default {};
                };
                while (i < list.len)
                {
                    o = (Overload*)list.items[i];
                    i++;
                    switch (o.nparams != 2)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (o.func == this.cur_fn)
                    {
                        case (true) { continue; }
                        default {};
                    };
                    switch (this.arg_matches(o.params[0], lt))
                    {
                        case (true) {
                        switch (this.arg_matches(o.params[1], rt))
                        {
                            case (true) { -> o; }
                            default {};
                        };
                    }
                        default {};
                    };
                };
                -> (Overload*)0;
            };

            // ----------------------------------------------------------
            // Type functions
            // ----------------------------------------------------------

            // Flux type name of a receiver (_llvm_type_to_flux_type_name). Heap string or null.
            flux_type_name(TypeSpec* t) -> byte*
            {
                TypeSpec* a = this.resolve_alias(t);
                TypeSpec* el;
                int k = this.kind_of(t);
                int w;
                byte* base;
                byte* r;
                switch (a == (TypeSpec*)0)
                {
                    case (true) { -> (byte*)0; }
                    default {};
                };
                switch (k == TyKind.INT)
                {
                    case (true) {
                    w = this.width_of(t);
                    switch (w == 1)
                    {
                        case (true) { -> ts_dup(g"bool\0"); }
                        default {};
                    };
                    switch (w == 8)
                    {
                        case (true) { -> ts_dup(g"byte\0"); }
                        default {};
                    };
                    switch (w == 16 | w == 32)
                    {
                        case (true) { -> ts_dup(g"int\0"); }
                        default {};
                    };
                    switch (w == 64)
                    {
                        case (true) { -> ts_dup(g"long\0"); }
                        default {};
                    };
                    this.clear_mb();
                    this.mb.put_str(g"data\0");
                    this.mb.put_int(w);
                    -> ts_dup(this.mb.mem);
                }
                    default {};
                };
                switch (k == TyKind.FLOAT)
                {
                    case (true) { -> ts_dup(g"float\0"); }
                    default {};
                };
                switch (k == TyKind.DOUBLE)
                {
                    case (true) { -> ts_dup(g"double\0"); }
                    default {};
                };
                switch (k == TyKind.PTR)
                {
                    case (true) {
                    el = this.elem_of(a);
                    switch (el == (TypeSpec*)0)
                    {
                        case (true) { -> (byte*)0; }
                        default {};
                    };
                    switch (this.kind_of(el) == TyKind.INT)
                    {
                        case (true) {
                        switch (this.width_of(el) == 8)
                        {
                            case (true) { -> ts_dup(g"string\0"); }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (this.kind_of(el) == TyKind.VOID)
                    {
                        case (true) { -> ts_dup(g"string\0"); }
                        default {};
                    };
                    switch (this.kind_of(el) == TyKind.AGG)
                    {
                        case (true) {
                        -> ts_dup(this.resolve_alias(el).custom_typename);
                    }
                        default {};
                    };
                    -> (byte*)0;
                }
                    default {};
                };
                switch (k == TyKind.AGG)
                {
                    case (true) { -> ts_dup(a.custom_typename); }
                    default {};
                };
                switch (k == TyKind.ARRAY)
                {
                    case (true) {
                    el = this.elem_of(a);
                    base = this.flux_type_name(el);
                    switch (base == (byte*)0)
                    {
                        case (true) { -> (byte*)0; }
                        default {};
                    };
                    r = join3(base, g"_arr\0", g"\0");
                    ffree(base);
                    -> r;
                }
                    default {};
                };
                -> (byte*)0;
            };

            // Return type of type function ftype.fname called with args, null when none
            typefunc_ret(byte* ftype, byte* fname, NodeVec* args) -> TypeSpec*
            {
                byte* mid = join3(g"__typefunc__\0", ftype, g"__\0");
                byte* key = join3(mid, fname, g"\0");
                PtrVec* list = st_overloads_of(this.st, key);
                Overload* o;
                ffree(mid);
                ffree(key);
                switch (list == (PtrVec*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                o = this.pick_overload(list, args);
                switch (o == (Overload*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                -> o.ret;
            };

            // ----------------------------------------------------------
            // Expressions
            // ----------------------------------------------------------

            type_list(Node* n, int slot) -> void
            {
                int i;
                int cnt = node_count(n, slot);
                while (i < cnt)
                {
                    this.type_of(node_child(n, slot, i));
                    i++;
                };
                ->;
            };

            type_raw(Node* n) -> TypeSpec*
            {
                this.raw = true;
                -> this.type_of(n);
            };

            // Types expression n (and its children) and stores the result in n.ety
            type_of(Node* n) -> TypeSpec*
            {
                switch (n == (Node*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                bool r = this.raw;
                this.raw = false;
                switch (!is_expr_kind(n.kind))
                {
                    case (true) {
                    this.walk(n);
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                TypeSpec* t = this.compute(n, r);
                n.ety = t;
                switch (t != (TypeSpec*)0)
                {
                    case (true) { this.typed++; }
                    default {
                    switch (!is_untyped_kind(n.kind))
                    {
                        case (true) {
                        this.untyped++;
                        pv_push(this.unk, (void*)n);
                    }
                        default {};
                    };
                };
                };
                -> t;
            };

            t_literal(Node* n) -> TypeSpec*
            {
                int op = n.op;
                int w;
                switch (op == DataType.SINT)
                {
                    case (true) {
                    w = infer_int_width(n.ival, op);
                    switch (w == 32)
                    {
                        case (true) { w = -1; }
                        default {};
                    };
                    -> this.mk(DataType.SINT, TS_SIGNED, w);
                }
                    default {};
                };
                switch (op == DataType.UINT)
                {
                    case (true) {
                    w = infer_int_width(n.ival, op);
                    switch (w == 32)
                    {
                        case (true) { w = -1; }
                        default {};
                    };
                    -> this.mk(DataType.UINT, 0, w);
                }
                    default {};
                };
                switch (op == DataType.SLONG)
                {
                    case (true) { -> this.mk(DataType.SLONG, TS_SIGNED, -1); }
                    default {};
                };
                switch (op == DataType.ULONG)
                {
                    case (true) { -> this.mk(DataType.ULONG, 0, -1); }
                    default {};
                };
                switch (op == DataType.FLOAT)
                {
                    case (true) { -> this.mk(DataType.FLOAT, TS_SIGNED, -1); }
                    default {};
                };
                switch (op == DataType.DOUBLE)
                {
                    case (true) { -> this.mk(DataType.DOUBLE, TS_SIGNED, -1); }
                    default {};
                };
                switch (op == DataType.BOOL)
                {
                    case (true) { -> this.mk(DataType.BOOL, 0, -1); }
                    default {};
                };
                switch (op == DataType.CHAR)
                {
                    case (true) { -> this.mk(DataType.CHAR, TS_SIGNED, -1); }
                    default {};
                };
                switch (op == DataType.VOID)
                {
                    case (true) { -> this.mk(DataType.VOID, 0, -1); }
                    default {};
                };
                -> (TypeSpec*)0;
            };

            // byte[len] for string text
            string_type(byte* text) -> TypeSpec*
            {
                int len = 0;
                TypeSpec* t = this.mk(DataType.BYTE, TS_ARRAY, -1);
                switch (text != (byte*)0)
                {
                    case (true) { len = pp_cstrlen(text); }
                    default {};
                };
                switch (this.null_term)
                {
                    case (true) {
                    switch (len == 0)
                    {
                        case (true) { len = 1; }
                        default {
                            switch (text[len - 1] != 0)
                            {
                                case (true) { len = len + 1; }
                                default {};
                            };
                        };
                    };
                }
                    default {};
                };
                t.array_size = this.size_node(len);
                -> t;
            };

            t_ident(Node* n, bool r) -> TypeSpec*
            {
                FXC_SYMENTRY* e;
                TypeSpec* vt;
                TypeSpec* pr;
                TypeSpec* tt;
                switch (n.text == (byte*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                switch (cstr_eq(n.text, g"this\0"))
                {
                    case (true) {
                    switch (this.cur_obj == (byte*)0)
                    {
                        case (true) { -> (TypeSpec*)0; }
                        default {};
                    };
                    tt = this.mk_named(DataType.OBJECT, this.cur_obj);
                    -> this.ptr_to(tt);
                }
                    default {};
                };
                e = st_lookup_any(this.st, n.text, (byte*)0);
                switch (e == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                switch (e.kind_id == SymbolKind.VARIABLE)
                {
                    case (true) {
                    vt = (TypeSpec*)e.ts;
                    switch (r)
                    {
                        case (true) { -> vt; }
                        default {};
                    };
                    pr = this.expr_promote(vt);
                    switch (pr != (TypeSpec*)0)
                    {
                        case (true) { -> pr; }
                        default {};
                    };
                    -> vt;
                }
                    default {};
                };
                switch (e.kind_id == SymbolKind.FUNCTION)
                {
                    case (true) { -> this.fn_value((Node*)e.node); }
                    default {};
                };
                // A type name used as a value operand (sizeof, alignof, typeof)
                switch (e.kind_id == SymbolKind.STRUCT)
                {
                    case (true) { -> this.mk_named(DataType.STRUCT, n.text); }
                    default {};
                };
                switch (e.kind_id == SymbolKind.OBJECT)
                {
                    case (true) { -> this.mk_named(DataType.OBJECT, n.text); }
                    default {};
                };
                switch (e.kind_id == SymbolKind.UNION)
                {
                    case (true) { -> this.mk_named(DataType.UNION, n.text); }
                    default {};
                };
                switch (e.kind_id == SymbolKind.ENUM)
                {
                    case (true) { -> this.mk_named(DataType.ENUM, n.text); }
                    default {};
                };
                switch (e.kind_id == SymbolKind.TYPE)
                {
                    case (true) { -> (TypeSpec*)e.ts; }
                    default {};
                };
                -> (TypeSpec*)0;
            };

            // Object variable promoted by __expr (its value is a byte string for +)
            is_expr_source(Node* x) -> bool
            {
                FXC_SYMENTRY* e;
                switch (x.kind == NodeKind.F_STRING_LITERAL)
                {
                    case (true) { -> true; }
                    default {};
                };
                switch (x.kind != NodeKind.IDENTIFIER)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (x.text == (byte*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                e = st_lookup_any(this.st, x.text, (byte*)0);
                switch (e == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (e.kind_id != SymbolKind.VARIABLE)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> this.expr_promote((TypeSpec*)e.ts) != (TypeSpec*)0;
            };

            // Result of array + array and array - array
            concat(TypeSpec* lt, TypeSpec* rt, int op) -> TypeSpec*
            {
                TypeSpec* le = this.elem_of(lt);
                TypeSpec* c;
                int ln = this.array_len(lt);
                int rn = this.array_len(rt);
                int total;
                switch (le == (TypeSpec*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                c = typespec_clone(this.resolve_alias(lt));
                c.array_dims = (NodeVec*)0;
                c.array_size = (Node*)0;
                this.keep(c);
                switch (ln < 0 | rn < 0)
                {
                    case (true) { -> c; }
                    default {};
                };
                switch (op)
                {
                    case (Operator.ADD)
                    {
                        total = ln + rn;
                        switch (this.null_term & ln >= 1)
                        {
                            case (true) {
                            switch (this.kind_of(le) == TyKind.INT)
                            {
                                case (true) {
                                switch (this.width_of(le) == 8)
                                {
                                    case (true) { total = ln - 1 + rn; }
                                    default {};
                                };
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                    default
                    {
                        total = ln - rn;
                        switch (total < 0)
                        {
                            case (true) { total = 0; }
                            default {};
                        };
                    };
                };
                c.array_size = this.size_node(total);
                -> c;
            };

            t_binary(Node* n) -> TypeSpec*
            {
                int op = n.op;
                TypeSpec* lt;
                TypeSpec* rt;
                Overload* ov;
                int lk, rk, w, lw, rw;
                bool lp, rp, uns;
                switch (op == Operator.ASSIGN)
                {
                    case (true) {
                    lt = this.type_raw(n.a);
                    this.type_of(n.b);
                    this.conv_check(lt, n.b, Site.STORE);
                    -> lt;
                }
                    default {};
                };
                lt = this.type_of(n.a);
                rt = this.type_of(n.b);
                ov = this.binary_overload(op, lt, rt);
                switch (ov != (Overload*)0)
                {
                    case (true) {
                    switch (ov.ret != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (ov.ret.base_type == DataType.THIS)
                        {
                            case (true) { -> this.ret_of_fn(ov.func, this.cur_obj); }
                            default {};
                        };
                    }
                        default {};
                    };
                    -> ov.ret;
                }
                    default {};
                };
                switch (op == Operator.EQUAL | op == Operator.NOT_EQUAL | op == Operator.LESS_THAN |
                    op == Operator.LESS_EQUAL | op == Operator.GREATER_THAN | op == Operator.GREATER_EQUAL)
                {
                    case (true) {
                    -> this.mk(DataType.BOOL, 0, -1);
                }
                    default {};
                };
                lk = this.kind_of(lt);
                rk = this.kind_of(rt);
                switch (op == Operator.ADD)
                {
                    case (true) {
                    switch (this.is_expr_source(n.a) | this.is_expr_source(n.b))
                    {
                        case (true) { -> this.byte_ptr(); }
                        default {};
                    };
                }
                    default {};
                };
                switch (op == Operator.ADD | op == Operator.SUB)
                {
                    case (true) {
                    switch (lk == TyKind.ARRAY & rk == TyKind.ARRAY)
                    {
                        case (true) { -> this.concat(lt, rt, op); }
                        default {};
                    };
                    lp = lk == TyKind.PTR | lk == TyKind.ARRAY;
                    rp = rk == TyKind.PTR | rk == TyKind.ARRAY;
                    switch (lp & rk == TyKind.INT)
                    {
                        case (true) { -> this.addr_of_type(this.elem_of(lt)); }
                        default {};
                    };
                    switch (rp & lk == TyKind.INT & op == Operator.ADD)
                    {
                        case (true) { -> this.addr_of_type(this.elem_of(rt)); }
                        default {};
                    };
                    switch (lp & rp)
                    {
                        case (true) { -> this.mk_int(64, false); }
                        default {};
                    };
                }
                    default {};
                };
                switch (op == Operator.ADD | op == Operator.SUB | op == Operator.MUL | op == Operator.DIV |
                    op == Operator.MOD | op == Operator.POWER)
                {
                    case (true) {
                    switch (lk == TyKind.FLOAT | lk == TyKind.DOUBLE)
                    {
                        case (true) {
                        switch (lk == TyKind.FLOAT & rk == TyKind.DOUBLE)
                        {
                            case (true) { -> rt; }
                            default {};
                        };
                        -> lt;
                    }
                        default {};
                    };
                    switch (lk == TyKind.INT & rk == TyKind.INT)
                    {
                        case (true) {
                        lw = this.width_of(lt);
                        rw = this.width_of(rt);
                        w = lw;
                        switch (rw > lw)
                        {
                            case (true) { w = rw; }
                            default {};
                        };
                        uns = this.uns_of(lt) | this.uns_of(rt);
                        -> this.mk_int(w, uns);
                    }
                        default {};
                    };
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (op == Operator.BITAND | op == Operator.BITOR | op == Operator.BITXOR |
                    op == Operator.AND | op == Operator.OR | op == Operator.XOR)
                {
                    case (true) {
                    switch (lk == TyKind.INT & rk == TyKind.INT)
                    {
                        case (true) {
                        lw = this.width_of(lt);
                        rw = this.width_of(rt);
                        w = lw;
                        switch (rw > lw)
                        {
                            case (true) { w = rw; }
                            default {};
                        };
                        uns = this.uns_of(lt) | this.uns_of(rt);
                        -> this.mk_int(w, uns);
                    }
                        default {};
                    };
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (op == Operator.BITSHIFT_LEFT | op == Operator.BITSHIFT_RIGHT)
                {
                    case (true) {
                    switch (lk == TyKind.INT)
                    {
                        case (true) { -> this.mk_int(this.width_of(lt), this.uns_of(lt)); }
                        default {};
                    };
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (op == Operator.NOR | op == Operator.NAND)
                {
                    case (true) { -> lt; }
                    default {};
                };
                switch (op == Operator.BITNAND | op == Operator.BITNOR | op == Operator.BITXNOR)
                {
                    case (true) {
                    switch (lk == TyKind.INT)
                    {
                        case (true) {
                        uns = this.uns_of(lt) | this.uns_of(rt);
                        -> this.mk_int(this.width_of(lt), uns);
                    }
                        default {};
                    };
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                -> (TypeSpec*)0;
            };

            t_unary(Node* n) -> TypeSpec*
            {
                TypeSpec* ot = this.type_of(n.a);
                int op = n.op;
                switch (op == Operator.NOT)
                {
                    case (true) {
                    switch (this.kind_of(ot) == TyKind.PTR)
                    {
                        case (true) { -> this.mk(DataType.BOOL, 0, -1); }
                        default {};
                    };
                    -> ot;
                }
                    default {};
                };
                -> ot;
            };

            // Branch type of a ternary or null coalesce: the wider integer, else the first
            join_types(TypeSpec* a, TypeSpec* b) -> TypeSpec*
            {
                int ka = this.kind_of(a);
                int kb = this.kind_of(b);
                switch (a == (TypeSpec*)0)
                {
                    case (true) { -> b; }
                    default {};
                };
                switch (b == (TypeSpec*)0)
                {
                    case (true) { -> a; }
                    default {};
                };
                switch (ka == TyKind.INT & kb == TyKind.INT)
                {
                    case (true) {
                    switch (this.width_of(b) > this.width_of(a))
                    {
                        case (true) { -> b; }
                        default {};
                    };
                    -> a;
                }
                    default {};
                };
                switch (ka == TyKind.ARRAY & kb == TyKind.PTR)
                {
                    case (true) { -> b; }
                    default {};
                };
                -> a;
            };

            // Function named by its mangled name (fcodegen finds these in module.globals).
            // The base name is the part before the first double underscore.
            by_mangled(byte* name) -> Overload*
            {
                int i, n;
                byte* base;
                PtrVec* list;
                Overload* o;
                while (name[n] != 0)
                {
                    switch (name[n] == '_' & name[n + 1] == '_')
                    {
                        case (true) { break; }
                        default {};
                    };
                    n++;
                };
                switch (name[n] == 0)
                {
                    case (true) { -> (Overload*)0; }
                    default {};
                };
                base = (byte*)fmalloc((u64)n + (u64)1);
                while (i < n)
                {
                    base[i] = name[i];
                    i++;
                };
                base[n] = (byte)0;
                list = this.ov_resolve(base);
                ffree(base);
                switch (list == (PtrVec*)0)
                {
                    case (true) { -> (Overload*)0; }
                    default {};
                };
                i = 0;
                while (i < list.len)
                {
                    o = (Overload*)list.items[i];
                    switch (cstr_eq(o.mangled, name))
                    {
                        case (true) { -> o; }
                        default {};
                    };
                    i++;
                };
                -> (Overload*)0;
            };

            // Reports the message built in ck.mb at node n
            report(int severity, Node* n) -> void
            {
                switch (this.ck == (Checker*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                this.ck.emit(severity, n.line, n.col);
                ->;
            };

            // First overload for name (the one fcodegen reads the tie, endianness and
            // deprecation contracts from: resolve_overload_entry with no argument values)
            first_overload(PtrVec* list) -> Overload*
            {
                switch (list == (PtrVec*)0)
                {
                    case (true) { -> (Overload*)0; }
                    default {};
                };
                switch (list.len == 0)
                {
                    case (true) { -> (Overload*)0; }
                    default {};
                };
                -> (Overload*)list.items[0];
            };

            // Contracts visit_FunctionCall enforces before resolving the call
            call_contracts(Node* n, PtrVec* list) -> void
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
                switch (this.ck == (Checker*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                while (i < argc)
                {
                    an = node_child(n, 0, i);
                    // A local variable cannot leave its scope through a call
                    switch (an.kind == NodeKind.IDENTIFIER & an.text != (byte*)0)
                    {
                        case (true) {
                        e = st_lookup_any(this.st, an.text, (byte*)0);
                        switch (e != (FXC_SYMENTRY*)0)
                        {
                            case (true) {
                            switch (e.kind_id == SymbolKind.VARIABLE & (TypeSpec*)e.ts != (TypeSpec*)0)
                            {
                                case (true) {
                                switch ((((TypeSpec*)e.ts).flags `& TS_LOCAL) != 0)
                                {
                                    case (true) {
                                    this.ck.clear_msg();
                                    this.ck.mb.put_str(g"local variable '\0");
                                    this.ck.mb.put_str(an.text);
                                    this.ck.mb.put_str(g"' cannot leave its scope via function call\0");
                                    this.report(Severity.ERROR, n);
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
                    i++;
                };
                switch (o == (Overload*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (o.deprecated)
                {
                    case (true) {
                    this.ck.clear_msg();
                    this.ck.mb.put_str(g"call to deprecated function '\0");
                    this.ck.mb.put_str(n.text);
                    this.ck.mb.put_str(g"'\0");
                    this.report(Severity.WARNING, n);
                }
                    default {};
                };
                i = 0;
                while (i < argc & i < o.nparams)
                {
                    an = node_child(n, 0, i);
                    pt = o.params[i];
                    tied_arg = an.kind == NodeKind.TIE_EXPRESSION;
                    switch (pt != (TypeSpec*)0)
                    {
                        case (true) {
                        switch (((pt.flags `& TS_TIED) != 0) & !tied_arg)
                        {
                            case (true) {
                            this.ck.clear_msg();
                            this.ck.mb.put_str(g"parameter \0");
                            this.ck.mb.put_int(i);
                            this.ck.mb.put_str(g" of '\0");
                            this.ck.mb.put_str(n.text);
                            this.ck.mb.put_str(g"' requires a tied argument (~), but a non-tied expression was passed\0");
                            this.report(Severity.ERROR, n);
                        }
                            default {};
                        };
                        switch (((pt.flags `& TS_TIED) == 0) & tied_arg)
                        {
                            case (true) {
                            this.ck.clear_msg();
                            this.ck.mb.put_str(g"parameter \0");
                            this.ck.mb.put_int(i);
                            this.ck.mb.put_str(g" of '\0");
                            this.ck.mb.put_str(n.text);
                            this.ck.mb.put_str(g"' is not a tied parameter, but a tie expression (~) was passed\0");
                            this.report(Severity.ERROR, n);
                        }
                            default {};
                        };
                        // Assignment swaps endianness, parameter passing does not
                        tgt = pt.endianness;
                        src = 1;
                        switch (this.has_spec(an))
                        {
                            case (true) {
                            at = this.arg_type(an);
                            switch (at != (TypeSpec*)0)
                            {
                                case (true) { src = this.resolve_alias(at).endianness; }
                                default {};
                            };
                        }
                            default {};
                        };
                        switch (src != tgt)
                        {
                            case (true) {
                            this.ck.clear_msg();
                            this.ck.mb.put_str(g"passing argument \0");
                            this.ck.mb.put_int(i);
                            this.ck.mb.put_str(g" of function \0");
                            this.ck.mb.put_str(n.text);
                            switch (src)
                            {
                                case (0) { this.ck.mb.put_str(g" is little-endian, but parameter expects big-endian\0"); }
                                default { this.ck.mb.put_str(g" is big-endian, but parameter expects little-endian\0"); };
                            };
                            this.report(Severity.ERROR, n);
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

            // Function name that no overload or symbol accepts (_funcall_not_found)
            call_unresolved(Node* n) -> void
            {
                PtrVec* exact;
                Overload* o;
                int i, argc;
                switch (this.ck == (Checker*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                argc = node_count(n, 0);
                this.ck.clear_msg();
                exact = st_overloads_of(this.st, n.text);
                switch (exact != (PtrVec*)0)
                {
                    case (true) {
                    this.ck.mb.put_str(g"function \0");
                    this.ck.mb.put_str(n.text);
                    this.ck.mb.put_str(g" found but no overload accepts \0");
                    this.ck.mb.put_int(argc);
                    this.ck.mb.put_str(g" arguments. Available overloads accept: [\0");
                    while (i < exact.len)
                    {
                        o = (Overload*)exact.items[i];
                        switch (i > 0)
                        {
                            case (true) { this.ck.mb.put_str(g", \0"); }
                            default {};
                        };
                        this.ck.mb.put_int(o.nparams);
                        i++;
                    };
                    this.ck.mb.put_str(g"]\0");
                }
                    default {
                    this.ck.mb.put_str(g"function '\0");
                    this.ck.mb.put_str(n.text);
                    this.ck.mb.put_str(g"' not found in module or any imported namespaces\0");
                };
                };
                this.report(Severity.ERROR, n);
                ->;
            };

            t_call(Node* n) -> TypeSpec*
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
                switch (n.text == (byte*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                e = st_lookup_any(this.st, n.text, (byte*)0);
                switch (e != (FXC_SYMENTRY*)0)
                {
                    case (true) {
                    switch (e.kind_id == SymbolKind.VARIABLE)
                    {
                        case (true) {
                        vt = this.resolve_alias((TypeSpec*)e.ts);
                        switch (vt != (TypeSpec*)0)
                        {
                            case (true) {
                            switch (vt.base_type == DataType.FUNC_PTR)
                            {
                                case (true) { -> vt.fp_ret; }
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
                list = this.ov_resolve(n.text);
                this.call_contracts(n, list);
                o = this.pick_overload(list, n.l0);
                switch (o != (Overload*)0)
                {
                    case (true) {
                    this.conv_args(o, n.l0);
                    n.text3 = o.mangled;
                    -> o.ret;
                }
                    default {};
                };
                o = this.by_mangled(n.text);
                switch (o != (Overload*)0)
                {
                    case (true) {
                    n.text3 = o.mangled;
                    -> o.ret;
                }
                    default {};
                };
                e = st_lookup_any(this.st, n.text, (byte*)0);
                switch (e != (FXC_SYMENTRY*)0)
                {
                    case (true) {
                    switch (e.kind_id == SymbolKind.FUNCTION & list == (PtrVec*)0)
                    {
                        case (true) { -> (TypeSpec*)e.ts; }
                        default {};
                    };
                    switch (e.kind_id == SymbolKind.STRUCT)
                    {
                        case (true) { -> this.mk_named(DataType.STRUCT, n.text); }
                        default {};
                    };
                    switch (e.kind_id == SymbolKind.OBJECT)
                    {
                        case (true) { -> this.mk_named(DataType.OBJECT, n.text); }
                        default {};
                    };
                    switch (e.kind_id == SymbolKind.VARIABLE)
                    {
                        case (true) {
                        switch (this.kind_of((TypeSpec*)e.ts) == TyKind.AGG)
                        {
                            case (true) { -> (TypeSpec*)e.ts; }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                this.call_unresolved(n);
                -> (TypeSpec*)0;
            };

            t_method(Node* n) -> TypeSpec*
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
                switch (n.text == (byte*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                switch (rt == (TypeSpec*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                e = this.type_entry(rt);
                switch (e != (FXC_SYMENTRY*)0)
                {
                    case (true) {
                    switch (e.kind_id == SymbolKind.OBJECT | e.kind_id == SymbolKind.STRUCT)
                    {
                        case (true) {
                        objkey = mangle_namespace_name(e.ns, e.name);
                        key = join3(objkey, g".\0", n.text);
                        ffree(objkey);
                        list = st_overloads_of(this.st, key);
                        ffree(key);
                        o = this.pick_overload(list, n.l0);
                        switch (o != (Overload*)0)
                        {
                            case (true) {
                            this.conv_args(o, n.l0);
                            n.text3 = o.mangled;
                            -> this.ret_of_fn(o.func, e.name);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                tn = this.flux_type_name(rt);
                switch (tn == (byte*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                r = this.typefunc_ret(tn, n.text, n.l0);
                switch (r == (TypeSpec*)0)
                {
                    case (true) {
                    switch (e != (FXC_SYMENTRY*)0)
                    {
                        case (true) {
                        mk2 = mangle_namespace_name(e.ns, e.name);
                        r = this.typefunc_ret(mk2, n.text, n.l0);
                        ffree(mk2);
                    }
                        default {};
                    };
                }
                    default {};
                };
                ffree(tn);
                -> r;
            };

            t_member(Node* n) -> TypeSpec*
            {
                TypeSpec* ot;
                FXC_SYMENTRY* e;
                switch (n.text == (byte*)0)
                {
                    case (true) {
                    this.type_raw(n.a);
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (n.a != (Node*)0)
                {
                    case (true) {
                    switch (n.a.kind == NodeKind.IDENTIFIER)
                    {
                        case (true) {
                        switch (n.a.text != (byte*)0)
                        {
                            case (true) {
                            e = st_lookup_type(this.st, n.a.text, (byte*)0);
                            switch (e != (FXC_SYMENTRY*)0)
                            {
                                case (true) {
                                switch (e.kind_id == SymbolKind.ENUM)
                                {
                                    case (true) {
                                    -> this.mk_named(DataType.ENUM, n.a.text);
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
                ot = this.type_raw(n.a);
                switch (ot == (TypeSpec*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                -> this.member_type_of(ot, n.text);
            };

            t_index(Node* n) -> TypeSpec*
            {
                TypeSpec* at = this.type_of(n.a);
                TypeSpec* a;
                int k;
                this.type_of(n.b);
                switch (at == (TypeSpec*)0)
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                a = this.resolve_alias(at);
                switch (a.base_type == DataType.DICT)
                {
                    case (true) {
                    switch (a.custom_typename == (byte*)0)
                    {
                        case (true) { -> a.dict_value; }
                        default {};
                    };
                }
                    default {};
                };
                k = this.kind_of(at);
                switch (k == TyKind.INT)
                {
                    case (true) { -> this.mk(DataType.BYTE, 0, -1); }
                    default {};
                };
                switch (n.b != (Node*)0)
                {
                    case (true) {
                    switch (n.b.kind == NodeKind.RANGE_EXPRESSION)
                    {
                        case (true) {
                        -> this.addr_of_type(this.elem_of(at));
                    }
                        default {};
                    };
                }
                    default {};
                };
                -> this.elem_of(at);
            };

            t_bitslice(Node* n) -> TypeSpec*
            {
                TypeSpec* vt = this.type_of(n.a);
                int lo = -1;
                int hi = -1;
                int width;
                this.type_of(n.b);
                this.type_of(n.c);
                switch (n.b != (Node*)0)
                {
                    case (true) {
                    switch (n.b.kind == NodeKind.LITERAL)
                    {
                        case (true) { lo = (int)n.b.ival; }
                        default {};
                    };
                }
                    default {};
                };
                switch (n.c != (Node*)0)
                {
                    case (true) {
                    switch (n.c.kind == NodeKind.LITERAL)
                    {
                        case (true) { hi = (int)n.c.ival; }
                        default {};
                    };
                }
                    default {};
                };
                switch (lo >= 0 & hi >= 0)
                {
                    case (true) {
                    width = hi - lo;
                    switch (width < 0)
                    {
                        case (true) { width = lo - hi; }
                        default {};
                    };
                    -> this.mk_int(width + 1, true);
                }
                    default {};
                };
                -> vt;
            };

            t_address(Node* n) -> TypeSpec*
            {
                TypeSpec* ot = this.type_raw(n.a);
                TypeSpec* a;
                switch (ot == (TypeSpec*)0)
                {
                    case (true) { -> ot; }
                    default {};
                };
                switch (n.a.kind == NodeKind.IDENTIFIER)
                {
                    case (true) {
                    a = this.resolve_alias(ot);
                    switch (this.kind_of(ot) == TyKind.FUNC)
                    {
                        case (true) { -> ot; }
                        default {};
                    };
                    // fcodegen loads a pointer variable: the address of a pointer
                    // variable is the pointer value itself
                    switch (this.kind_of(ot) == TyKind.PTR & !ts_is_array(a))
                    {
                        case (true) { -> ot; }
                        default {};
                    };
                }
                    default {};
                };
                switch (n.a.kind == NodeKind.POINTER_DEREF)
                {
                    case (true) { -> n.a.a.ety; }
                    default {};
                };
                -> this.addr_of_type(ot);
            };

            t_dict(Node* n) -> TypeSpec*
            {
                TypeSpec* t;
                TypeSpec* kt;
                TypeSpec* vt;
                int cnt;
                int step = 1;
                switch (n.kind)
                {
                    case (NodeKind.DICT_LITERAL)
                    {
                        this.type_list(n, 0);
                        cnt = node_count(n, 0);
                        switch (cnt < 2)
                        {
                            case (true) { -> (TypeSpec*)0; }
                            default {};
                        };
                        kt = node_child(n, 0, 0).ety;
                        vt = node_child(n, 0, 1).ety;
                        cnt = cnt / 2;
                    }
                    default
                    {
                        this.type_list(n, 0);
                        this.type_list(n, 1);
                        cnt = node_count(n, 0);
                        switch (cnt < 1)
                        {
                            case (true) { -> (TypeSpec*)0; }
                            default {};
                        };
                        switch (node_count(n, 1) < 1)
                        {
                            case (true) { -> (TypeSpec*)0; }
                            default {};
                        };
                        kt = node_child(n, 0, 0).ety;
                        vt = node_child(n, 1, 0).ety;
                    };
                };
                t = this.mk(DataType.DICT, 0, -1);
                t.dict_key = kt;
                t.dict_value = vt;
                t.dict_capacity = cnt;
                -> t;
            };

            t_array_lit(Node* n) -> TypeSpec*
            {
                TypeSpec* el;
                TypeSpec* c;
                int cnt = node_count(n, 0);
                this.type_list(n, 0);
                switch ((n.flags `& NF_IS_STRING) != 0)
                {
                    case (true) { -> this.string_type(n.text); }
                    default {};
                };
                el = n.ts;
                switch (el == (TypeSpec*)0)
                {
                    case (true) {
                    switch (cnt == 0)
                    {
                        case (true) { -> (TypeSpec*)0; }
                        default {};
                    };
                    el = node_child(n, 0, 0).ety;
                }
                    default {};
                };
                switch (el == (TypeSpec*)0)
                {
                    case (true) { -> el; }
                    default {};
                };
                switch (ts_is_array(el))
                {
                    case (true) { -> (TypeSpec*)0; }
                    default {};
                };
                c = typespec_clone(el);
                c.flags = c.flags `| TS_ARRAY;
                c.array_size = this.size_node(cnt);
                c.array_dims = (NodeVec*)0;
                -> this.keep(c);
            };

            compute(Node* n, bool r) -> TypeSpec*
            {
                int k = n.kind;
                TypeSpec* t;
                TypeSpec* u;
                switch (k == NodeKind.LITERAL)
                {
                    case (true) { -> this.t_literal(n); }
                    default {};
                };
                switch (k == NodeKind.IDENTIFIER)
                {
                    case (true) { -> this.t_ident(n, r); }
                    default {};
                };
                switch (k == NodeKind.STRING_LITERAL)
                {
                    case (true) { -> this.string_type(n.text); }
                    default {};
                };
                switch (k == NodeKind.F_STRING_LITERAL)
                {
                    case (true) {
                    this.type_list(n, 0);
                    -> this.byte_ptr();
                }
                    default {};
                };
                switch (k == NodeKind.ARRAY_LITERAL)
                {
                    case (true) { -> this.t_array_lit(n); }
                    default {};
                };
                switch (k == NodeKind.BINARY_OP)
                {
                    case (true) { -> this.t_binary(n); }
                    default {};
                };
                switch (k == NodeKind.UNARY_OP)
                {
                    case (true) { -> this.t_unary(n); }
                    default {};
                };
                switch (k == NodeKind.CAST_EXPRESSION | k == NodeKind.TYPE_CONVERT_EXPRESSION)
                {
                    case (true) {
                    this.type_of(n.a);
                    -> n.ts;
                }
                    default {};
                };
                switch (k == NodeKind.FUNCTION_CALL)
                {
                    case (true) { -> this.t_call(n); }
                    default {};
                };
                switch (k == NodeKind.METHOD_CALL)
                {
                    case (true) { -> this.t_method(n); }
                    default {};
                };
                switch (k == NodeKind.MEMBER_ACCESS)
                {
                    case (true) { -> this.t_member(n); }
                    default {};
                };
                switch (k == NodeKind.STRUCT_FIELD_ACCESS)
                {
                    case (true) {
                    t = this.type_raw(n.a);
                    switch (t == (TypeSpec*)0)
                    {
                        case (true) { -> t; }
                        default {};
                    };
                    -> this.member_type_of(t, n.text);
                }
                    default {};
                };
                switch (k == NodeKind.ARRAY_ACCESS)
                {
                    case (true) { -> this.t_index(n); }
                    default {};
                };
                switch (k == NodeKind.ARRAY_SLICE)
                {
                    case (true) {
                    t = this.type_of(n.a);
                    this.type_of(n.b);
                    this.type_of(n.c);
                    -> this.addr_of_type(this.elem_of(t));
                }
                    default {};
                };
                switch (k == NodeKind.BIT_SLICE)
                {
                    case (true) { -> this.t_bitslice(n); }
                    default {};
                };
                switch (k == NodeKind.BIT_INDEX_ACCESS)
                {
                    case (true) {
                    this.type_of(n.a);
                    this.type_of(n.b);
                    -> this.mk(DataType.BYTE, 0, -1);
                }
                    default {};
                };
                switch (k == NodeKind.VARIADIC_ACCESS)
                {
                    case (true) {
                    this.type_of(n.a);
                    -> this.mk_int(64, false);
                }
                    default {};
                };
                switch (k == NodeKind.POINTER_DEREF)
                {
                    case (true) {
                    t = this.type_of(n.a);
                    switch (this.kind_of(t) == TyKind.PTR)
                    {
                        case (true) { -> this.pointee_of(this.resolve_alias(t)); }
                        default {};
                    };
                    switch (this.kind_of(t) == TyKind.ARRAY)
                    {
                        case (true) { -> t; }
                        default {};
                    };
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (k == NodeKind.ADDRESS_OF)
                {
                    case (true) { -> this.t_address(n); }
                    default {};
                };
                switch (k == NodeKind.STRINGIFY)
                {
                    case (true) { -> this.byte_ptr(); }
                    default {};
                };
                switch (k == NodeKind.CODIFY)
                {
                    case (true) {
                    this.type_of(n.a);
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (k == NodeKind.SIZE_OF | k == NodeKind.ALIGN_OF | k == NodeKind.ENDIAN_OF)
                {
                    case (true) {
                    switch (n.a != (Node*)0)
                    {
                        case (true) { this.type_raw(n.a); }
                        default {};
                    };
                    -> this.mk_int(32, false);
                }
                    default {};
                };
                switch (k == NodeKind.TYPE_OF)
                {
                    case (true) {
                    switch (n.a != (Node*)0)
                    {
                        case (true) { this.type_raw(n.a); }
                        default {};
                    };
                    -> this.byte_ptr();
                }
                    default {};
                };
                switch (k == NodeKind.TERNARY_OP | k == NodeKind.IF_EXPRESSION)
                {
                    case (true) {
                    switch (k)
                    {
                        case (NodeKind.TERNARY_OP)
                        {
                            this.type_of(n.a);
                            t = this.type_of(n.b);
                            u = this.type_of(n.c);
                        }
                        default
                        {
                            t = this.type_of(n.a);
                            this.type_of(n.b);
                            u = this.type_of(n.c);
                        };
                    };
                    -> this.join_types(t, u);
                }
                    default {};
                };
                switch (k == NodeKind.NULL_COALESCE)
                {
                    case (true) {
                    t = this.type_of(n.a);
                    u = this.type_of(n.b);
                    -> this.join_types(t, u);
                }
                    default {};
                };
                switch (k == NodeKind.NOT_NULL)
                {
                    case (true) {
                    this.type_of(n.a);
                    -> this.mk(DataType.BYTE, 0, -1);
                }
                    default {};
                };
                switch (k == NodeKind.IN_EXPRESSION)
                {
                    case (true) {
                    this.type_of(n.a);
                    this.type_of(n.b);
                    -> this.mk(DataType.BOOL, 0, -1);
                }
                    default {};
                };
                switch (k == NodeKind.HAS_EXPRESSION)
                {
                    case (true) {
                    this.type_of(n.a);
                    -> this.mk(DataType.BOOL, 0, -1);
                }
                    default {};
                };
                switch (k == NodeKind.TIE_EXPRESSION)
                {
                    case (true) { -> this.type_raw(n.a); }
                    default {};
                };
                switch (k == NodeKind.FUNCTION_POINTER_CALL)
                {
                    case (true) {
                    t = this.type_of(n.a);
                    this.type_list(n, 0);
                    switch (t == (TypeSpec*)0)
                    {
                        case (true) { -> t; }
                        default {};
                    };
                    t = this.resolve_alias(t);
                    switch (t.base_type == DataType.FUNC_PTR)
                    {
                        case (true) { -> t.fp_ret; }
                        default {};
                    };
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (k == NodeKind.STRUCT_LITERAL | k == NodeKind.STRUCT_INSTANCE)
                {
                    case (true) {
                    this.type_list(n, 1);
                    this.type_list(n, 2);
                    switch (n.text == (byte*)0)
                    {
                        case (true) { -> (TypeSpec*)0; }
                        default {};
                    };
                    -> this.mk_named(DataType.STRUCT, n.text);
                }
                    default {};
                };
                switch (k == NodeKind.STRUCT_RECAST)
                {
                    case (true) {
                    this.type_of(n.a);
                    switch (n.text == (byte*)0)
                    {
                        case (true) { -> (TypeSpec*)0; }
                        default {};
                    };
                    -> this.ptr_to(this.mk_named(DataType.STRUCT, n.text));
                }
                    default {};
                };
                switch (k == NodeKind.TYPE_FUNC_CALL)
                {
                    case (true) {
                    this.type_raw(n.a);
                    this.type_list(n, 0);
                    switch (n.text == (byte*)0 | n.text2 == (byte*)0)
                    {
                        case (true) { -> (TypeSpec*)0; }
                        default {};
                    };
                    -> this.typefunc_ret(n.text, n.text2, n.l0);
                }
                    default {};
                };
                switch (k == NodeKind.DICT_LITERAL | k == NodeKind.DICT_LITERAL_EXPR)
                {
                    case (true) { -> this.t_dict(n); }
                    default {};
                };
                switch (k == NodeKind.RANGE_EXPRESSION)
                {
                    case (true) {
                    this.type_of(n.a);
                    this.type_of(n.b);
                    this.type_of(n.c);
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (k == NodeKind.ARRAY_COMPREHENSION)
                {
                    case (true) {
                    st_enter_scope(this.st);
                    this.type_of(n.b);
                    switch (n.text != (byte*)0)
                    {
                        case (true) { this.def_var(n.text, n.ts, n); }
                        default {};
                    };
                    this.type_of(n.a);
                    this.type_of(n.c);
                    st_exit_scope(this.st);
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                switch (k == NodeKind.MACRO_CALL)
                {
                    case (true) {
                    this.type_list(n, 0);
                    -> (TypeSpec*)0;
                }
                    default {};
                };
                -> (TypeSpec*)0;
            };

            // ----------------------------------------------------------
            // Implicit conversions (store_with_type_conversion,
            // convert_argument_to_parameter_type, coerce_return_value)
            // ----------------------------------------------------------

            // Object type (or pointer to it) that defines __expr
            has_expr(TypeSpec* t) -> bool
            {
                TypeSpec* p = t;
                FXC_SYMENTRY* e;
                switch (t == (TypeSpec*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (this.kind_of(t) == TyKind.PTR)
                {
                    case (true) { p = this.elem_of(t); }
                    default {};
                };
                e = this.type_entry(p);
                switch (e == (FXC_SYMENTRY*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (e.kind_id != SymbolKind.OBJECT)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> this.find_method0((Node*)e.node, g"__expr\0") != (Node*)0;
            };

            // Conversion the base compiler applies to turn a value of type src into dst
            classify(TypeSpec* dst, TypeSpec* src, int site, Node* sn) -> int
            {
                int kd = this.kind_of(dst);
                int ks = this.kind_of(src);
                int wd, ws;
                TypeSpec* ed;
                TypeSpec* es;
                int ld, ls;
                bool agg_src;
                switch (kd == TyKind.UNKNOWN | ks == TyKind.UNKNOWN)
                {
                    case (true) { -> Conv.NONE; }
                    default {};
                };
                switch (kd == TyKind.VOID | ks == TyKind.VOID)
                {
                    case (true) { -> Conv.NONE; }
                    default {};
                };
                switch (kd == TyKind.FUNC | ks == TyKind.FUNC)
                {
                    case (true) { -> Conv.NONE; }
                    default {};
                };
                switch (kd == TyKind.DICT | ks == TyKind.DICT)
                {
                    case (true) { -> Conv.NONE; }
                    default {};
                };

                switch (site == Site.ARG)
                {
                    case (true) {
                    switch (!this.arg_matches(dst, src))
                    {
                        case (true) {
                        switch (this.has_expr(src))
                        {
                            case (true) {
                            switch (kd != TyKind.AGG | ks != TyKind.AGG)
                            {
                                case (true) { -> Conv.EXPR_CALL; }
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

                switch (kd == TyKind.INT)
                {
                    case (true) {
                    switch (ks == TyKind.INT)
                    {
                        case (true) {
                        wd = this.width_of(dst);
                        ws = this.width_of(src);
                        switch (wd == ws)
                        {
                            case (true) { -> Conv.EXACT; }
                            default {};
                        };
                        switch (ws < wd)
                        {
                            case (true) { -> Conv.INT_WIDEN; }
                            default {};
                        };
                        -> Conv.INT_NARROW;
                    }
                        default {};
                    };
                    switch (ks == TyKind.FLOAT | ks == TyKind.DOUBLE)
                    {
                        case (true) {
                        switch (site == Site.ARG)
                        {
                            case (true) { -> Conv.INVALID; }
                            default {};
                        };
                        -> Conv.FLOAT_TO_INT;
                    }
                        default {};
                    };
                    switch (ks == TyKind.PTR)
                    {
                        case (true) {
                        switch (site == Site.STORE)
                        {
                            case (true) { -> Conv.PTR_TO_INT; }
                            default {};
                        };
                        -> Conv.INVALID;
                    }
                        default {};
                    };
                    switch (ks == TyKind.ARRAY)
                    {
                        case (true) {
                        switch (site == Site.STORE)
                        {
                            case (true) { -> Conv.ARRAY_PACK; }
                            default {};
                        };
                        -> Conv.INVALID;
                    }
                        default {};
                    };
                    -> Conv.INVALID;
                }
                    default {};
                };

                switch (kd == TyKind.FLOAT | kd == TyKind.DOUBLE)
                {
                    case (true) {
                    switch (ks == TyKind.INT)
                    {
                        case (true) {
                        switch (site == Site.ARG)
                        {
                            case (true) { -> Conv.INVALID; }
                            default {};
                        };
                        -> Conv.INT_TO_FLOAT;
                    }
                        default {};
                    };
                    switch (ks == TyKind.FLOAT | ks == TyKind.DOUBLE)
                    {
                        case (true) {
                        switch (kd == ks)
                        {
                            case (true) { -> Conv.EXACT; }
                            default {};
                        };
                        switch (kd == TyKind.DOUBLE)
                        {
                            case (true) { -> Conv.FLOAT_EXT; }
                            default {};
                        };
                        -> Conv.FLOAT_TRUNC;
                    }
                        default {};
                    };
                    -> Conv.INVALID;
                }
                    default {};
                };

                switch (kd == TyKind.PTR)
                {
                    case (true) {
                    switch (ks == TyKind.PTR)
                    {
                        case (true) {
                        switch (this.ptr_same(dst, src))
                        {
                            case (true) { -> Conv.EXACT; }
                            default {};
                        };
                        -> Conv.PTR_CAST;
                    }
                        default {};
                    };
                    switch (ks == TyKind.ARRAY)
                    {
                        case (true) { -> Conv.ARRAY_DECAY; }
                        default {};
                    };
                    switch (ks == TyKind.INT)
                    {
                        case (true) {
                        switch (site == Site.STORE)
                        {
                            case (true) { -> Conv.INT_TO_PTR; }
                            default {};
                        };
                        -> Conv.INVALID;
                    }
                        default {};
                    };
                    -> Conv.INVALID;
                }
                    default {};
                };

                switch (kd == TyKind.ARRAY)
                {
                    case (true) {
                    switch (ks == TyKind.ARRAY)
                    {
                        case (true) {
                        switch (this.ty_same(dst, src))
                        {
                            case (true) { -> Conv.EXACT; }
                            default {};
                        };
                        ed = this.elem_of(dst);
                        es = this.elem_of(src);
                        ld = this.array_len(dst);
                        ls = this.array_len(src);
                        switch (site == Site.STORE)
                        {
                            case (true) {
                            switch (this.ty_same(ed, es))
                            {
                                case (true) {
                                switch (ld < 0 | ls < 0)
                                {
                                    case (true) { -> Conv.ARRAY_COPY; }
                                    default {};
                                };
                                switch (ls <= ld)
                                {
                                    case (true) { -> Conv.ARRAY_COPY; }
                                    default {};
                                };
                            }
                                default {};
                            };
                            -> Conv.INVALID;
                        }
                            default {};
                        };
                        switch (site == Site.RETURN)
                        {
                            case (true) {
                            switch (this.kind_of(ed) == TyKind.INT & this.kind_of(es) == TyKind.INT)
                            {
                                case (true) {
                                switch (ld >= 0 & ls >= 0)
                                {
                                    case (true) {
                                    switch (ld * this.width_of(ed) == ls * this.width_of(es))
                                    {
                                        case (true) { -> Conv.ARRAY_COPY; }
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
                        -> Conv.INVALID;
                    }
                        default {};
                    };
                    switch (ks == TyKind.PTR)
                    {
                        case (true) {
                        switch (sn != (Node*)0)
                        {
                            case (true) {
                            switch (sn.kind == NodeKind.CAST_EXPRESSION)
                            {
                                case (true) { -> Conv.ARRAY_COPY; }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    -> Conv.INVALID;
                }
                    default {};
                };

                switch (kd == TyKind.AGG)
                {
                    case (true) {
                    switch (ks == TyKind.AGG)
                    {
                        case (true) {
                        switch (this.agg_same(dst, src))
                        {
                            case (true) { -> Conv.EXACT; }
                            default {};
                        };
                        -> Conv.INVALID;
                    }
                        default {};
                    };
                    switch (ks == TyKind.PTR)
                    {
                        case (true) {
                        switch (this.resolve_alias(src).pointer_depth == 1)
                        {
                            case (true) {
                            switch (this.agg_same(dst, this.elem_of(src)))
                            {
                                case (true) { -> Conv.STRUCT_LOAD; }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    -> Conv.INVALID;
                }
                    default {};
                };
                -> Conv.NONE;
            };

            // Records the conversion of source expression sn to type dst
            conv_check(TypeSpec* dst, Node* sn, int site) -> void
            {
                int c;
                ConvRec* r;
                switch (dst == (TypeSpec*)0 | sn == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                TypeSpec* sty = sn.ety;
                switch (site == Site.ARG & sn.kind == NodeKind.IDENTIFIER)
                {
                    case (true) { sty = this.arg_type(sn); }
                    default {};
                };
                switch (sty == (TypeSpec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                c = this.classify(dst, sty, site, sn);
                switch (c == Conv.NONE)
                {
                    case (true) { ->; }
                    default {};
                };
                this.convs[c] = this.convs[c] + 1;
                switch (c == Conv.INVALID)
                {
                    case (true) {
                    r = (ConvRec*)fmalloc((u64)(sizeof(ConvRec) / 8));
                    r.at = sn;
                    r.dst = dst;
                    r.site = site;
                    pv_push(this.bad, (void*)r);
                }
                    default {};
                };
                ->;
            };

            conv_args(Overload* o, NodeVec* args) -> void
            {
                int j;
                int argc = 0;
                switch (o == (Overload*)0 | args == (NodeVec*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                argc = args.len;
                while (j < argc & j < o.nparams)
                {
                    this.conv_check(o.params[j], args.items[j], Site.ARG);
                    j++;
                };
                ->;
            };

            // Initializers the base compiler handles outside the store conversion
            init_converts(Node* decl, TypeSpec* ts) -> bool
            {
                Node* a = decl.a;
                int k;
                switch (a == (Node*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                k = a.kind;
                switch (k == NodeKind.NO_INIT | k == NodeKind.ARRAY_LITERAL | k == NodeKind.STRING_LITERAL |
                    k == NodeKind.ARRAY_COMPREHENSION | k == NodeKind.STRUCT_RECAST)
                {
                    case (true) {
                    -> false;
                }
                    default {};
                };
                switch (k == NodeKind.FUNCTION_CALL)
                {
                    case (true) {
                    switch (a.text != (byte*)0)
                    {
                        case (true) {
                        switch (ends_with(a.text, g".__init\0"))
                        {
                            case (true) { -> false; }
                            default {};
                        };
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (ts.storage_class == StorageClass.HEAP | ts.storage_class == StorageClass.SINGINIT)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (ts_is_array(ts) & k == NodeKind.IDENTIFIER)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> true;
            };

            // Prints the conversion counts and, with verbose, the invalid conversions
            print_conv(byte* path, bool verbose) -> void
            {
                int c = 1;
                int i;
                int n;
                ConvRec* r;
                while (c < 17)
                {
                    switch (this.convs[c] != 0)
                    {
                        case (true) {
                        print(g"  \0");
                        print(conv_name(c));
                        print(g": \0");
                        println(this.convs[c]);
                    }
                        default {};
                    };
                    c++;
                };
                switch (!verbose)
                {
                    case (true) { ->; }
                    default {};
                };
                while (i < this.bad.len)
                {
                    switch (i >= 60)
                    {
                        case (true) { break; }
                        default {};
                    };
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
                ->;
            };

            // ----------------------------------------------------------
            // Statements
            // ----------------------------------------------------------

            def_var(byte* name, TypeSpec* ts, Node* decl) -> void
            {
                switch (st_is_global_scope(this.st))
                {
                    case (true) { ->; }
                    default {};
                };
                st_define(this.st, name, SymbolKind.VARIABLE, ts, decl);
                ->;
            };

            // int[] x = [..] and byte[] s = ".." take their size from the initializer
            infer_decl(TypeSpec* ts, Node* init) -> TypeSpec*
            {
                TypeSpec* c;
                int cnt = -1;
                switch (ts == (TypeSpec*)0)
                {
                    case (true) { -> ts; }
                    default {};
                };
                switch (init == (Node*)0)
                {
                    case (true) { -> ts; }
                    default {};
                };
                switch (!ts_is_array(ts))
                {
                    case (true) { -> ts; }
                    default {};
                };
                switch (ts.array_size != (Node*)0)
                {
                    case (true) { -> ts; }
                    default {};
                };
                switch (ts.array_dims != (NodeVec*)0)
                {
                    case (true) { -> ts; }
                    default {};
                };
                switch (init.kind)
                {
                    case (NodeKind.ARRAY_LITERAL)
                    {
                        switch ((init.flags `& NF_IS_STRING) != 0)
                        {
                            case (true) {
                            switch (init.ety != (TypeSpec*)0)
                            {
                                case (true) { cnt = this.array_len(init.ety); }
                                default {};
                            };
                        }
                            default { cnt = node_count(init, 0); };
                        };
                    }
                    case (NodeKind.STRING_LITERAL)
                    {
                        switch (init.ety != (TypeSpec*)0)
                        {
                            case (true) { cnt = this.array_len(init.ety); }
                            default {};
                        };
                    }
                    default {};
                };
                switch (cnt < 0)
                {
                    case (true) { -> ts; }
                    default {};
                };
                c = typespec_clone(ts);
                c.array_size = this.size_node(cnt);
                -> this.keep(c);
            };

            walk_list(Node* n, int slot) -> void
            {
                int i;
                int cnt = node_count(n, slot);
                while (i < cnt)
                {
                    this.walk(node_child(n, slot, i));
                    i++;
                };
                ->;
            };

            walk_children(Node* n) -> void
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
                ->;
            };

            walk_function(Node* fn) -> void
            {
                Node* prev_fn = this.cur_fn;
                TypeSpec* prev_ret = this.cur_ret;
                Node* p;
                int i;
                int cnt = node_count(fn, 0);
                switch ((fn.flags `& NF_TEMPLATE) != 0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (fn.a == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                st_enter_scope(this.st);
                this.cur_fn = fn;
                this.cur_ret = fn.ts;
                while (i < cnt)
                {
                    p = node_child(fn, 0, i);
                    switch (p.text != (byte*)0)
                    {
                        case (true) { this.def_var(p.text, p.ts, p); }
                        default {};
                    };
                    i++;
                };
                this.walk(fn.a);
                this.cur_fn = prev_fn;
                this.cur_ret = prev_ret;
                st_exit_scope(this.st);
                ->;
            };

            walk_type_func(Node* tf) -> void
            {
                Node* prev_fn = this.cur_fn;
                TypeSpec* prev_ret = this.cur_ret;
                Node* p;
                int i;
                int cnt = node_count(tf, 0);
                switch (tf.a == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                st_enter_scope(this.st);
                this.cur_fn = tf;
                this.cur_ret = tf.ts;
                this.def_var(g"_\0", tf.ts2, tf);
                while (i < cnt)
                {
                    p = node_child(tf, 0, i);
                    switch (p.text != (byte*)0)
                    {
                        case (true) { this.def_var(p.text, p.ts, p); }
                        default {};
                    };
                    i++;
                };
                this.walk(tf.a);
                this.cur_fn = prev_fn;
                this.cur_ret = prev_ret;
                st_exit_scope(this.st);
                ->;
            };

            // Struct, object and union definitions: member initializers and methods
            walk_aggregate(Node* d) -> void
            {
                byte* prev_obj = this.cur_obj;
                Node* m;
                int i, cnt;
                switch (d.kind == NodeKind.OBJECT_DEF)
                {
                    case (true) {
                    switch (d.d != (Node*)0)
                    {
                        case (true) { ->; }
                        default {};
                    };
                    switch (d.text != (byte*)0)
                    {
                        case (true) { this.cur_obj = d.text; }
                        default {};
                    };
                }
                    default {};
                };
                switch (d.kind == NodeKind.STRUCT_DEF)
                {
                    case (true) {
                    switch (node_count(d, 4) > 0)
                    {
                        case (true) { ->; }
                        default {};
                    };
                }
                    default {};
                };
                cnt = node_count(d, 0);
                while (i < cnt)
                {
                    m = node_child(d, 0, i);
                    switch (m.a != (Node*)0)
                    {
                        case (true) { this.type_of(m.a); }
                        default {};
                    };
                    i++;
                };
                switch (d.kind == NodeKind.OBJECT_DEF)
                {
                    case (true) {
                    cnt = node_count(d, 1);
                    i = 0;
                    while (i < cnt)
                    {
                        this.walk(node_child(d, 1, i));
                        i++;
                    };
                }
                    default {};
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
                switch (d.kind == NodeKind.OBJECT_DEF)
                {
                    case (true) {
                    while (i < cnt)
                    {
                        this.walk(node_child(d, 4, i));
                        i++;
                    };
                }
                    default {};
                };
                this.cur_obj = prev_obj;
                ->;
            };

            walk_namespace(Node* ns) -> void
            {
                byte* prev = ts_dup(this.st.current_ns);
                byte* full;
                int s, c, e, w;
                Node* lst;
                switch (ns.text == (byte*)0)
                {
                    case (true) {
                    ffree(prev);
                    ->;
                }
                    default {};
                };
                switch (prev[0] == 0)
                {
                    case (true) { full = ts_dup(ns.text); }
                    default { full = join3(prev, g"::\0", ns.text); };
                };
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
                    switch (w)
                    {
                        case (0) { lst = ns.a; }
                        default { lst = ns.b; };
                    };
                    switch (lst != (Node*)0)
                    {
                        case (true) {
                        c = node_count(lst, 0);
                        e = 0;
                        while (e < c)
                        {
                            this.walk(node_child(lst, 0, e));
                            e++;
                        };
                    }
                        default {};
                    };
                    w++;
                };
                st_set_namespace(this.st, prev);
                ffree(prev);
                ffree(full);
                ->;
            };

            walk_var_decl(Node* n) -> void
            {
                TypeSpec* it = (TypeSpec*)0;
                TypeSpec* ts = n.ts;
                bool chk = false;
                switch (n.a != (Node*)0)
                {
                    case (true) { it = this.type_of(n.a); }
                    default {};
                };
                switch (ts != (TypeSpec*)0)
                {
                    case (true) {
                    switch (ts.storage_class == StorageClass.AUTO & ts.base_type == DataType.VOID)
                    {
                        case (true) { ts = it; }
                        default {
                        ts = this.infer_decl(ts, n.a);
                        chk = true;
                    };
                    };
                }
                    default {};
                };
                switch (chk & !st_is_global_scope(this.st))
                {
                    case (true) {
                    switch (this.init_converts(n, ts))
                    {
                        case (true) { this.conv_check(ts, n.a, Site.STORE); }
                        default {};
                    };
                }
                    default {};
                };
                switch (n.text != (byte*)0)
                {
                    case (true) { this.def_var(n.text, ts, n); }
                    default {};
                };
                n.ety = ts;
                ->;
            };

            walk_destructure(Node* n) -> void
            {
                TypeSpec* src = this.type_of(n.a);
                FXC_SYMENTRY* e = this.type_entry(src);
                Node* dn = (Node*)0;
                Node* v;
                Node* m;
                TypeSpec* vt;
                int i;
                int cnt = node_count(n, 0);
                switch (e != (FXC_SYMENTRY*)0)
                {
                    case (true) { dn = (Node*)e.node; }
                    default {};
                };
                while (i < cnt)
                {
                    v = node_child(n, 0, i);
                    vt = (TypeSpec*)0;
                    switch (v.kind == NodeKind.VARIABLE_DECLARATION)
                    {
                        case (true) { vt = v.ts; }
                        default {
                            switch (dn != (Node*)0)
                            {
                                case (true) {
                        switch (i < node_count(dn, 0))
                        {
                            case (true) {
                            m = node_child(dn, 0, i);
                            vt = m.ts;
                        }
                            default {};
                        };
                    }
                                default {};
                            };
                        };
                    };
                    switch (v.text != (byte*)0)
                    {
                        case (true) { this.def_var(v.text, vt, v); }
                        default {};
                    };
                    i++;
                };
                ->;
            };

            walk_for_in(Node* n) -> void
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
                switch ((n.flags `& NF_DESTRUCTURE) != 0)
                {
                    case (true) {
                    e = this.type_entry(et);
                    switch (e != (FXC_SYMENTRY*)0)
                    {
                        case (true) { dn = (Node*)e.node; }
                        default {};
                    };
                }
                    default {};
                };
                while (i < cnt)
                {
                    v = node_child(n, 0, i);
                    vt = et;
                    switch ((n.flags `& NF_DESTRUCTURE) != 0)
                    {
                        case (true) {
                        vt = (TypeSpec*)0;
                        switch (dn != (Node*)0)
                        {
                            case (true) {
                            switch (i < node_count(dn, 0))
                            {
                                case (true) {
                                m = node_child(dn, 0, i);
                                vt = m.ts;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {
                            switch (i > 0)
                            {
                                case (true) { vt = (TypeSpec*)0; }
                                default {};
                            };
                        };
                    };
                    switch (v.text != (byte*)0)
                    {
                        case (true) { this.def_var(v.text, vt, v); }
                        default {};
                    };
                    i++;
                };
                this.walk(n.b);
                st_exit_scope(this.st);
                ->;
            };

            walk_try(Node* n) -> void
            {
                Node* cc;
                int i;
                int cnt = node_count(n, 0);
                this.walk(n.a);
                while (i < cnt)
                {
                    cc = node_child(n, 0, i);
                    st_enter_scope(this.st);
                    switch (cc.text != (byte*)0)
                    {
                        case (true) { this.def_var(cc.text, cc.ts, cc); }
                        default {};
                    };
                    this.walk(cc.a);
                    st_exit_scope(this.st);
                    i++;
                };
                ->;
            };

            walk(Node* n) -> void
            {
                switch (n == (Node*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                int k = n.kind;
                switch (is_expr_kind(k))
                {
                    case (true) {
                    this.type_of(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.BLOCK)
                {
                    case (true) {
                    st_enter_scope(this.st);
                    this.walk_list(n, 0);
                    st_exit_scope(this.st);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.VARIABLE_DECLARATION)
                {
                    case (true) {
                    this.walk_var_decl(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.ASSIGNMENT | k == NodeKind.COMPOUND_ASSIGNMENT | k == NodeKind.TERNARY_ASSIGN)
                {
                    case (true) {
                    this.type_raw(n.a);
                    this.type_of(n.b);
                    switch (k == NodeKind.ASSIGNMENT | k == NodeKind.TERNARY_ASSIGN)
                    {
                        case (true) {
                        switch (n.a != (Node*)0)
                        {
                            case (true) { this.conv_check(n.a.ety, n.b, Site.STORE); }
                            default {};
                        };
                    }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.RETURN_STATEMENT)
                {
                    case (true) {
                    // A function returning an aggregate gets the value itself, not its __expr
                    switch (this.kind_of(this.cur_ret) == TyKind.AGG)
                    {
                        case (true) { this.type_raw(n.a); }
                        default { this.type_of(n.a); };
                    };
                    switch (this.cur_ret != (TypeSpec*)0 & n.a != (Node*)0)
                    {
                        case (true) {
                        switch (this.cur_ret.base_type != DataType.THIS & this.cur_ret.base_type != DataType.VOID)
                        {
                            case (true) {
                            this.conv_check(this.cur_ret, n.a, Site.RETURN);
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.FUNCTION_DEF | k == NodeKind.OBJECT_METHOD)
                {
                    case (true) {
                    this.walk_function(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.TYPE_FUNC_DEF)
                {
                    case (true) {
                    this.walk_type_func(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.FUNCTION_DEF_STATEMENT | k == NodeKind.STRUCT_DEF_STATEMENT |
                    k == NodeKind.OBJECT_DEF_STATEMENT | k == NodeKind.UNION_DEF_STATEMENT |
                    k == NodeKind.NAMESPACE_DEF_STATEMENT | k == NodeKind.ENUM_DEF_STATEMENT |
                    k == NodeKind.MACRO_DEF_STATEMENT)
                {
                    case (true) {
                    this.walk(n.a);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.OBJECT_DEF | k == NodeKind.STRUCT_DEF)
                {
                    case (true) {
                    this.walk_aggregate(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.NAMESPACE_DEF)
                {
                    case (true) {
                    this.walk_namespace(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.EXTERN_BLOCK | k == NodeKind.EXPORT_BLOCK | k == NodeKind.PROGRAM)
                {
                    case (true) {
                    this.walk_list(n, 0);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.USING_STATEMENT)
                {
                    case (true) {
                    switch (n.text != (byte*)0)
                    {
                        case (true) { st_add_using_namespace(this.st, n.text); }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.NOT_USING_STATEMENT)
                {
                    case (true) {
                    switch (n.text != (byte*)0)
                    {
                        case (true) { st_remove_using_namespace(this.st, n.text); }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.FOR_LOOP)
                {
                    case (true) {
                    st_enter_scope(this.st);
                    this.walk_children(n);
                    st_exit_scope(this.st);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.FOR_IN_LOOP)
                {
                    case (true) {
                    this.walk_for_in(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.TRY_BLOCK)
                {
                    case (true) {
                    this.walk_try(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.DESTRUCTURING_ASSIGNMENT)
                {
                    case (true) {
                    this.walk_destructure(n);
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.DUAL_ASSIGN_DECLARATION)
                {
                    case (true) {
                    this.type_of(n.a);
                    switch (n.text != (byte*)0)
                    {
                        case (true) { this.def_var(n.text, n.ts, n); }
                        default {};
                    };
                    switch (n.text2 != (byte*)0)
                    {
                        case (true) { this.def_var(n.text2, n.ts2, n); }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.FUNCTION_POINTER_DECLARATION)
                {
                    case (true) {
                    this.type_of(n.a);
                    switch (n.text != (byte*)0)
                    {
                        case (true) { this.def_var(n.text, n.ts, n); }
                        default {};
                    };
                    ->;
                }
                    default {};
                };
                switch (k == NodeKind.ENUM_DEF | k == NodeKind.UNION_DEF | k == NodeKind.TRAIT_DEF |
                    k == NodeKind.INTERFACE_DEF | k == NodeKind.CONTRACT_DEF | k == NodeKind.CONSTRA_DEF |
                    k == NodeKind.MACRO_DEF | k == NodeKind.EFFECT_DEF | k == NodeKind.EMIT_FLUX |
                    k == NodeKind.COMPTIME_BLOCK | k == NodeKind.INLINE_ASM | k == NodeKind.FLUXVM_BLOCK |
                    k == NodeKind.TYPE_DECLARATION | k == NodeKind.STRUCT_MEMBER | k == NodeKind.UNION_MEMBER)
                {
                    case (true) {
                    ->;
                }
                    default {};
                };
                this.walk_children(n);
                ->;
            };

            // Types every expression of a parsed program
            walk_program(Node* prog) -> void
            {
                this.walk_list(prog, 0);
                ->;
            };

            // Prints up to limit expressions that stayed untyped
            print_unknown(byte* path, int limit) -> void
            {
                int i;
                Node* n;
                while (i < this.unk.len)
                {
                    switch (i >= limit)
                    {
                        case (true) { break; }
                        default {};
                    };
                    n = (Node*)this.unk.items[i];
                    print(path);
                    print(g":\0");
                    print(n.line);
                    print(g":\0");
                    print(n.col);
                    print(g": untyped \0");
                    print(node_kind_name(n.kind));
                    switch (n.text != (byte*)0)
                    {
                        case (true) {
                        print(g" \0");
                        print(n.text);
                    }
                        default {};
                    };
                    println(g"\0");
                    i++;
                };
                ->;
            };
        };
    };
};

#endif;
