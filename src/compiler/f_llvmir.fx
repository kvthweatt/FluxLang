// Author: Karac V. Thweatt
//
// f_llvmir.fx - LLVM IR text builder (bootstrap code generator, stage 1)
//
// A port of the llvmlite.ir subset that fcodegen.py uses. The module is built
// in memory and printed as textual LLVM IR (typed pointers), so the output of
// the Flux compiler can be compared with the output of the Python compiler.
//
// Ownership: every IRType, IRValue, string and block made through an IRModule
// belongs to that module and is released by IRModule.__exit.
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
#def FLUX_LLVMIR 1;

// IRValue.flags
#def VF_FROM_EXPR 1;
#def VF_TYPEFUNC_STR 2;
#def VF_ALLOCA 4;
#def VF_GLOBAL 8;

using flux::ast;
using flux::preprocessor;
using flux::types;

namespace flux
{
    namespace ir
    {
        enum LK
        {
            VOID,
            INT,
            FLOAT,
            DOUBLE,
            PTR,
            ARRAY,
            STRUCT,     // literal struct { a, b }
            ISTRUCT,    // identified struct %"name"
            FUNC
        };

        // LLVM type. elem is the return type of a FUNC, the pointee of a PTR and
        // the element of an ARRAY; items are struct fields or function parameters.
        struct IRType
        {
            int kind;
            int width;
            int count;
            IRType* elem;
            IRType** items;
            int nitems;
            byte* name;
            bool vararg;
            bool defined;
        };

        // A value: ty and the operand text (without the type), plus the Flux type
        // the value was derived from when known.
        struct IRValue
        {
            IRType* ty;
            byte* text;
            TypeSpec* spec;
            TypeSpec* espec;    // array element spec carried by a member array pointer
            int flags;
            bool is_const;
        };

        struct IRBlock
        {
            byte* name;
            PtrVec* lines;
            bool terminated;
        };

        struct IRFunc
        {
            byte* name;
            IRType* ftype;
            IRValue** args;
            int nargs;
            PtrVec* blocks;
            byte* cconv;
            byte* linkage;
            PtrVec* attrs;
            NameMap* names;
            int counter;
            bool is_decl;
            IRValue* self;      // the function as a value (pointer to its type)
        };

        struct IRGlobal
        {
            byte* name;
            IRType* ty;
            byte* init;         // initializer text, null when none
            byte* linkage;
            bool constant;
            IRValue* self;
        };

        // ------------------------------------------------------------------
        // Text helpers
        // ------------------------------------------------------------------

        def put_i64(Buf* b, i64 v) -> void
        {
            byte[24] tmp = noinit;
            int n, k;
            u64 u;
            if (v < (i64)0)
            {
                b.put(45);
                u = (u64)0 - (u64)v;
            }
            else { u = (u64)v; };
            if (u == (u64)0)
            {
                b.put(48);
                return;
            };
            while (u > (u64)0)
            {
                tmp[n] = (byte)((int)(u % (u64)10) + 48);
                u = u / (u64)10;
                n++;
            };
            k = n - 1;
            while (k >= 0)
            {
                b.put((int)tmp[k]);
                k--;
            };
            return;
        };

        def put_u64(Buf* b, u64 u) -> void
        {
            byte[24] tmp = noinit;
            int n, k;
            if (u == (u64)0)
            {
                b.put(48);
                return;
            };
            while (u > (u64)0)
            {
                tmp[n] = (byte)((int)(u % (u64)10) + 48);
                u = u / (u64)10;
                n++;
            };
            k = n - 1;
            while (k >= 0)
            {
                b.put((int)tmp[k]);
                k--;
            };
            return;
        };

        def hexdig(int v) -> int
        {
            if (v < 10) { return 48 + v; };
            return 65 + v - 10;
        };

        // 0x followed by 16 uppercase hex digits
        // llvmlite formats float constants with {:#16x}: 0x prefix, no leading
        // zeros, right justified in 16 columns
        def put_hex64(Buf* b, u64 u) -> void
        {
            int nd = 1;
            int i;
            int d;
            int pad;
            while (nd < 16)
            {
                if ((u >> (u64)(nd * 4)) == (u64)0) { break; };
                nd++;
            };
            pad = 16 - (nd + 2);
            while (pad > 0)
            {
                b.put(32);
                pad--;
            };
            b.put_str(g"0x\0");
            i = nd - 1;
            while (i >= 0)
            {
                d = (int)((u >> (u64)(i * 4)) `& (u64)15);
                if (d < 10) { b.put(48 + d); } else { b.put(87 + d); };
                i--;
            };
            return;
        };

        // "name" with the characters llvmlite escapes
        def put_quoted(Buf* b, byte* s) -> void
        {
            int i;
            int c;
            b.put(34);
            while (s[i] != 0)
            {
                c = (int)s[i];
                if (c < 32 | c > 126 | c == 34 | c == 92)
                {
                    b.put(92);
                    b.put(hexdig(c / 16));
                    b.put(hexdig(c % 16));
                }
                else { b.put(c); };
                i++;
            };
            b.put(34);
            return;
        };

        // Block label line: name followed by a colon
        def put_quoted_label(Buf* out, byte* name) -> void
        {
            int i;
            bool plain = true;
            int c;
            while (name[i] != 0)
            {
                c = (int)name[i];
                if (!((c >= 48 & c <= 57) | (c >= 65 & c <= 90) | (c >= 97 & c <= 122) | c == 95 | c == 46 | c == 36 | c == 45))
                {
                    plain = false;
                };
                i++;
            };
            if (plain) { out.put_str(name); }
            else { put_quoted(out, name); };
            out.put_str(g":\n\0");
            return;
        };

        // ------------------------------------------------------------------
        // Types
        // ------------------------------------------------------------------

        def lt_text(Buf* b, IRType* t) -> void
        {
            int i;
            int k = t.kind;
            if (k == LK.VOID) { b.put_str(g"void\0"); return; };
            if (k == LK.INT)
            {
                b.put(105);
                b.put_int(t.width);
                return;
            };
            if (k == LK.FLOAT) { b.put_str(g"float\0"); return; };
            if (k == LK.DOUBLE) { b.put_str(g"double\0"); return; };
            if (k == LK.PTR)
            {
                lt_text(b, t.elem);
                b.put(42);
                return;
            };
            if (k == LK.ARRAY)
            {
                b.put(91);
                b.put_int(t.count);
                b.put_str(g" x \0");
                lt_text(b, t.elem);
                b.put(93);
                return;
            };
            if (k == LK.STRUCT)
            {
                b.put_str(g"{\0");
                while (i < t.nitems)
                {
                    if (i > 0) { b.put_str(g", \0"); };
                    lt_text(b, t.items[i]);
                    i++;
                };
                b.put_str(g"}\0");
                return;
            };
            if (k == LK.ISTRUCT)
            {
                b.put(37);
                put_quoted(b, t.name);
                return;
            };
            // FUNC
            lt_text(b, t.elem);
            b.put_str(g" (\0");
            while (i < t.nitems)
            {
                if (i > 0) { b.put_str(g", \0"); };
                lt_text(b, t.items[i]);
                i++;
            };
            if (t.vararg)
            {
                if (t.nitems > 0) { b.put_str(g", \0"); };
                b.put_str(g"...\0");
            };
            b.put(41);
            return;
        };

        def lt_eq(IRType* a, IRType* b) -> bool
        {
            int i;
            if (a == b) { return true; };
            if (a == (IRType*)0 | b == (IRType*)0) { return false; };
            if (a.kind != b.kind) { return false; };
            int k = a.kind;
            if (k == LK.VOID | k == LK.FLOAT | k == LK.DOUBLE) { return true; };
            if (k == LK.INT) { return a.width == b.width; };
            if (k == LK.PTR) { return lt_eq(a.elem, b.elem); };
            if (k == LK.ARRAY)
            {
                if (a.count != b.count) { return false; };
                return lt_eq(a.elem, b.elem);
            };
            if (k == LK.ISTRUCT) { return cstr_eq(a.name, b.name); };
            if (a.nitems != b.nitems) { return false; };
            if (k == LK.FUNC)
            {
                if (a.vararg != b.vararg) { return false; };
                if (!lt_eq(a.elem, b.elem)) { return false; };
            };
            while (i < a.nitems)
            {
                if (!lt_eq(a.items[i], b.items[i])) { return false; };
                i++;
            };
            return true;
        };

        def lt_is_int(IRType* t) -> bool { return t.kind == LK.INT; };
        def lt_is_ptr(IRType* t) -> bool { return t.kind == LK.PTR; };
        def lt_is_fp(IRType* t) -> bool { return t.kind == LK.FLOAT | t.kind == LK.DOUBLE; };
        def lt_is_agg(IRType* t) -> bool
        {
            return t.kind == LK.ARRAY | t.kind == LK.STRUCT | t.kind == LK.ISTRUCT;
        };

        // ------------------------------------------------------------------
        // Module
        // ------------------------------------------------------------------

        object IRModule
        {
            byte* mod_name;
            byte* triple;
            byte* layout;
            PtrVec* types;      // IRType* made here
            PtrVec* values;     // IRValue* made here
            PtrVec* strs;       // byte* made here
            PtrVec* blobs;      // raw allocations (item arrays, blocks)
            PtrVec* named;      // identified struct types in creation order
            PtrVec* globals;    // IRGlobal*
            PtrVec* funcs;      // IRFunc*
            NameMap* gnames;    // global and function names in use
            NameMap* fmap;      // function name to IRFunc*
            NameMap* gmap;      // global name to IRGlobal*
            Buf tb;             // text scratch
            Buf ib;             // instruction body scratch
            Buf lb;             // instruction line scratch
            IRFunc* cf;         // function being built
            IRBlock* cb;        // insertion block
            IRBlock* entry_b;   // entry block of cf
            IRValue** ia;       // small operand scratch
            IRType* nul;        // elem of types that have none, so elem.kind is always readable

            def __init(byte* name) -> this
            {
                this.mod_name = ts_dup(name);
                this.triple = (byte*)0;
                this.layout = (byte*)0;
                this.nul = (IRType*)0;
                this.types = pv_new();
                this.values = pv_new();
                this.strs = pv_new();
                this.blobs = pv_new();
                this.named = pv_new();
                this.globals = pv_new();
                this.funcs = pv_new();
                this.gnames = nm_new();
                this.fmap = nm_new();
                this.gmap = nm_new();
                this.tb.__init();
                this.ib.__init();
                this.lb.__init();
                this.cf = (IRFunc*)0;
                this.cb = (IRBlock*)0;
                this.entry_b = (IRBlock*)0;
                this.ia = (IRValue**)fmalloc((u64)8 * (u64)((sizeof(IRValue*) + 7) / 8));
                this.nul = this.new_type(LK.VOID);
                this.nul.elem = this.nul;
                return this;
            };

            def __expr() -> IRModule*
            {
                return this;
            };

            def __exit() -> void
            {
                int i, j;
                IRFunc* f;
                IRBlock* bl;
                while (i < this.types.len)
                {
                    ffree((byte*)this.types.items[i]);
                    i++;
                };
                i = 0;
                while (i < this.values.len)
                {
                    ffree((byte*)this.values.items[i]);
                    i++;
                };
                i = 0;
                while (i < this.strs.len)
                {
                    ffree((byte*)this.strs.items[i]);
                    i++;
                };
                i = 0;
                while (i < this.blobs.len)
                {
                    ffree((byte*)this.blobs.items[i]);
                    i++;
                };
                i = 0;
                while (i < this.funcs.len)
                {
                    f = (IRFunc*)this.funcs.items[i];
                    j = 0;
                    while (j < f.blocks.len)
                    {
                        bl = (IRBlock*)f.blocks.items[j];
                        pv_free(bl.lines);
                        ffree((byte*)bl);
                        j++;
                    };
                    pv_free(f.blocks);
                    pv_free(f.attrs);
                    nm_free(f.names);
                    ffree((byte*)f.args);
                    ffree((byte*)f);
                    i++;
                };
                i = 0;
                while (i < this.globals.len)
                {
                    ffree((byte*)this.globals.items[i]);
                    i++;
                };
                pv_free(this.types);
                pv_free(this.values);
                pv_free(this.strs);
                pv_free(this.blobs);
                pv_free(this.named);
                pv_free(this.globals);
                pv_free(this.funcs);
                nm_free(this.gnames);
                nm_free(this.fmap);
                nm_free(this.gmap);
                ffree(this.mod_name);
                if (this.triple != (byte*)0) { ffree(this.triple); };
                if (this.layout != (byte*)0) { ffree(this.layout); };
                this.tb.__exit();
                this.ib.__exit();
                this.lb.__exit();
                ffree((byte*)this.ia);
                return;
            };

            def set_target(byte* triple, byte* layout) -> void
            {
                this.triple = ts_dup(triple);
                this.layout = ts_dup(layout);
                return;
            };

            // Owned copy of s
            def own(byte* s) -> byte*
            {
                byte* r = ts_dup(s);
                pv_push(this.strs, (void*)r);
                return r;
            };

            def alloc_items(int n) -> IRType**
            {
                IRType** p = (IRType**)fmalloc((u64)(n + 1) * (u64)((sizeof(IRType*) + 7) / 8));
                pv_push(this.blobs, (void*)p);
                return p;
            };

            def new_type(int kind) -> IRType*
            {
                IRType* t = (IRType*)fmalloc((u64)((sizeof(IRType) + 7) / 8));
                t.kind = kind;
                t.width = 0;
                t.count = 0;
                t.elem = this.nul;
                t.items = (IRType**)0;
                t.nitems = 0;
                t.name = (byte*)0;
                t.vararg = false;
                t.defined = true;
                pv_push(this.types, (void*)t);
                return t;
            };

            def t_void() -> IRType* { return this.new_type(LK.VOID); };
            def t_float() -> IRType* { return this.new_type(LK.FLOAT); };
            def t_double() -> IRType* { return this.new_type(LK.DOUBLE); };

            def t_int(int width) -> IRType*
            {
                IRType* t = this.new_type(LK.INT);
                t.width = width;
                return t;
            };

            def t_ptr(IRType* elem) -> IRType*
            {
                IRType* t = this.new_type(LK.PTR);
                t.elem = elem;
                return t;
            };

            def t_array(IRType* elem, int count) -> IRType*
            {
                IRType* t = this.new_type(LK.ARRAY);
                t.elem = elem;
                t.count = count;
                return t;
            };

            // Literal struct over the first n entries of items (copied)
            def t_struct(IRType** items, int n) -> IRType*
            {
                int i;
                IRType* t = this.new_type(LK.STRUCT);
                t.items = this.alloc_items(n);
                while (i < n)
                {
                    t.items[i] = items[i];
                    i++;
                };
                t.nitems = n;
                return t;
            };

            def t_func(IRType* ret, IRType** params, int n, bool vararg) -> IRType*
            {
                int i;
                IRType* t = this.new_type(LK.FUNC);
                t.elem = ret;
                t.items = this.alloc_items(n);
                while (i < n)
                {
                    t.items[i] = params[i];
                    i++;
                };
                t.nitems = n;
                t.vararg = vararg;
                return t;
            };

            // Identified struct, body set later with set_body. Returns the existing one
            // when the name is already in use.
            def t_named(byte* name) -> IRType*
            {
                int i;
                IRType* t;
                while (i < this.named.len)
                {
                    t = (IRType*)this.named.items[i];
                    if (cstr_eq(t.name, name)) { return t; };
                    i++;
                };
                t = this.new_type(LK.ISTRUCT);
                t.name = this.own(name);
                t.defined = false;
                pv_push(this.named, (void*)t);
                return t;
            };

            def set_body(IRType* t, IRType** items, int n) -> void
            {
                int i;
                t.items = this.alloc_items(n);
                while (i < n)
                {
                    t.items[i] = items[i];
                    i++;
                };
                t.nitems = n;
                t.defined = true;
                return;
            };

            def type_str(IRType* t) -> byte*
            {
                this.tb.clear();
                lt_text(@this.tb, t);
                return this.own(this.tb.mem);
            };

            // ----------------------------------------------------------
            // Values
            // ----------------------------------------------------------

            def new_value(IRType* ty, byte* text) -> IRValue*
            {
                IRValue* v = (IRValue*)fmalloc((u64)((sizeof(IRValue) + 7) / 8));
                v.ty = ty;
                v.text = this.own(text);
                v.spec = (TypeSpec*)0;
                v.espec = (TypeSpec*)0;
                v.flags = 0;
                v.is_const = false;
                pv_push(this.values, (void*)v);
                return v;
            };

            def c_int(IRType* ty, i64 val) -> IRValue*
            {
                IRValue* v;
                this.tb.clear();
                if (ty.width == 1)
                {
                    if (val != (i64)0) { this.tb.put_str(g"true\0"); }
                    else { this.tb.put_str(g"false\0"); };
                }
                else { put_i64(@this.tb, val); };
                v = this.new_value(ty, this.tb.mem);
                v.is_const = true;
                return v;
            };

            // Unsigned 64 bit constant: a Python int above INT64_MAX prints as is
            def c_u64(IRType* ty, u64 val) -> IRValue*
            {
                IRValue* v;
                this.tb.clear();
                put_u64(@this.tb, val);
                v = this.new_value(ty, this.tb.mem);
                v.is_const = true;
                return v;
            };

            def c_null(IRType* ty) -> IRValue*
            {
                IRValue* v;
                if (ty.kind == LK.PTR) { v = this.new_value(ty, g"null\0"); }
                elif (ty.kind == LK.INT)
                {
                    v = this.c_int(ty, (i64)0);
                    // llvmlite formats Constant(i1, 0) as 0, only a Python bool prints false
                    if (ty.width == 1) { v.text = g"0\0"; };
                    return v;
                }
                elif (ty.kind == LK.FLOAT | ty.kind == LK.DOUBLE)
                {
                    v = this.c_fp(ty, 0.0);
                    return v;
                }
                else { v = this.new_value(ty, g"zeroinitializer\0"); };
                v.is_const = true;
                return v;
            };

            def c_undef(IRType* ty) -> IRValue*
            {
                IRValue* v = this.new_value(ty, g"undef\0");
                v.is_const = true;
                return v;
            };

            // Floating point constant. llvmlite prints the double bit pattern for both
            // float and double.
            def c_fp(IRType* ty, double d) -> IRValue*
            {
                IRValue* v;
                float f;
                double dd = d;
                u64 bits;
                u64* bp;
                if (ty.kind == LK.FLOAT)
                {
                    f = (float)d;
                    dd = (double)f;
                };
                bp = (u64*)@dd;
                bits = *bp;
                this.tb.clear();
                put_hex64(@this.tb, bits);
                v = this.new_value(ty, this.tb.mem);
                v.is_const = true;
                return v;
            };

            // c"..." constant over n bytes
            def c_bytes(IRType* ty, byte* bytes_in, int n) -> IRValue*
            {
                IRValue* v;
                int i;
                int c;
                this.tb.clear();
                this.tb.put_str(g"c\"\0");
                while (i < n)
                {
                    c = (int)bytes_in[i];
                    if (c < 32 | c > 126 | c == 34 | c == 92)
                    {
                        this.tb.put(92);
                        this.tb.put(hexdig(c / 16));
                        this.tb.put(hexdig(c % 16));
                    }
                    else { this.tb.put(c); };
                    i++;
                };
                this.tb.put(34);
                v = this.new_value(ty, this.tb.mem);
                v.is_const = true;
                return v;
            };

            // Operand text "type value"
            def op_text(Buf* b, IRValue* v) -> void
            {
                lt_text(b, v.ty);
                b.put(32);
                b.put_str(v.text);
                return;
            };

            // ----------------------------------------------------------
            // Globals and functions
            // ----------------------------------------------------------

            def unique_global(byte* name) -> byte*
            {
                int n = 1;
                byte* cand;
                if (!nm_has(this.gnames, name)) { return this.own(name); };
                while (true)
                {
                    this.tb.clear();
                    this.tb.put_str(name);
                    this.tb.put(46);
                    this.tb.put_int(n);
                    cand = this.tb.mem;
                    if (!nm_has(this.gnames, cand)) { return this.own(cand); };
                    n++;
                };
                return this.own(name);
            };

            // Global variable of type ty. init is the initializer operand text or null.
            def add_global(IRType* ty, byte* name, byte* init) -> IRGlobal*
            {
                IRGlobal* g = (IRGlobal*)fmalloc((u64)((sizeof(IRGlobal) + 7) / 8));
                g.name = this.unique_global(name);
                nm_put(this.gnames, g.name, (void*)g);
                nm_put(this.gmap, g.name, (void*)g);
                g.ty = ty;
                g.init = (byte*)0;
                if (init != (byte*)0) { g.init = this.own(init); };
                g.linkage = (byte*)0;
                g.constant = false;
                this.tb.clear();
                this.tb.put(64);
                put_quoted(@this.tb, g.name);
                g.self = this.new_value(this.t_ptr(ty), this.tb.mem);
                g.self.flags = VF_GLOBAL;
                pv_push(this.globals, (void*)g);
                return g;
            };

            def find_global(byte* name) -> IRGlobal*
            {
                return (IRGlobal*)nm_get(this.gmap, name);
            };

            // Function with the given type. A function becomes a declaration until a
            // block is appended to it.
            def add_function(IRType* ftype, byte* name) -> IRFunc*
            {
                int i;
                IRFunc* f = (IRFunc*)fmalloc((u64)((sizeof(IRFunc) + 7) / 8));
                f.name = this.unique_global(name);
                nm_put(this.gnames, f.name, (void*)f);
                nm_put(this.fmap, f.name, (void*)f);
                f.ftype = ftype;
                f.nargs = ftype.nitems;
                f.args = (IRValue**)fmalloc((u64)(f.nargs + 1) * (u64)((sizeof(IRValue*) + 7) / 8));
                f.blocks = pv_new();
                f.attrs = pv_new();
                f.names = nm_new();
                f.counter = 0;
                f.cconv = (byte*)0;
                f.linkage = (byte*)0;
                f.is_decl = true;
                while (i < f.nargs)
                {
                    f.counter = f.counter + 1;
                    this.tb.clear();
                    this.tb.put(37);
                    this.tb.put_str(g"\".\0");
                    this.tb.put_int(f.counter);
                    this.tb.put(34);
                    f.args[i] = this.new_value(ftype.items[i], this.tb.mem);
                    i++;
                };
                this.tb.clear();
                this.tb.put(64);
                put_quoted(@this.tb, f.name);
                f.counter = f.counter + 1;
                f.self = this.new_value(this.t_ptr(ftype), this.tb.mem);
                pv_push(this.funcs, (void*)f);
                return f;
            };

            def find_function(byte* name) -> IRFunc*
            {
                return (IRFunc*)nm_get(this.fmap, name);
            };

            // Names parameter i (llvmlite Argument.name = ...)
            def name_arg(IRFunc* f, int i, byte* name) -> void
            {
                this.tb.clear();
                this.tb.put(37);
                put_quoted(@this.tb, name);
                f.args[i].text = this.own(this.tb.mem);
                nm_put(f.names, name, (void*)f);
                return;
            };

            // Gives parameter i a new name, kept unique inside f
            def rename_arg(IRFunc* f, int i, byte* name) -> void
            {
                byte* nm = this.fresh_name(f, name);
                f.args[i].text = this.result_text(nm);
                return;
            };

            // A name unique inside f: base when free, else base.N
            def fresh_name(IRFunc* f, byte* base) -> byte*
            {
                int n = 1;
                byte* cand;
                if (base == (byte*)0)
                {
                    f.counter = f.counter + 1;
                    this.tb.clear();
                    this.tb.put(46);
                    this.tb.put_int(f.counter);
                    return this.own(this.tb.mem);
                };
                if (base[0] == 0)
                {
                    f.counter = f.counter + 1;
                    this.tb.clear();
                    this.tb.put(46);
                    this.tb.put_int(f.counter);
                    return this.own(this.tb.mem);
                };
                if (!nm_has(f.names, base))
                {
                    nm_put(f.names, base, (void*)f);
                    return this.own(base);
                };
                while (true)
                {
                    this.tb.clear();
                    this.tb.put_str(base);
                    this.tb.put(46);
                    this.tb.put_int(n);
                    cand = this.tb.mem;
                    if (!nm_has(f.names, cand))
                    {
                        nm_put(f.names, cand, (void*)f);
                        return this.own(cand);
                    };
                    n++;
                };
                return this.own(base);
            };

            def append_block(IRFunc* f, byte* name) -> IRBlock*
            {
                IRBlock* bl = (IRBlock*)fmalloc((u64)((sizeof(IRBlock) + 7) / 8));
                bl.name = this.fresh_name(f, name);
                bl.lines = pv_new();
                bl.terminated = false;
                pv_push(f.blocks, (void*)bl);
                f.is_decl = false;
                return bl;
            };

            // ----------------------------------------------------------
            // Instruction builder
            // ----------------------------------------------------------

            def position(IRFunc* f, IRBlock* b) -> void
            {
                this.cf = f;
                this.cb = b;
                return;
            };

            def set_entry(IRBlock* b) -> void
            {
                this.entry_b = b;
                return;
            };

            def is_terminated() -> bool
            {
                if (this.cb == (IRBlock*)0) { return true; };
                return this.cb.terminated;
            };

            def const_val(IRValue* v) -> i64
            {
                int i;
                bool neg = false;
                i64 r;
                if (v.text[0] == 45) { neg = true; i = 1; };
                while (v.text[i] >= 48 & v.text[i] <= 57)
                {
                    r = r * (i64)10 + (i64)((int)v.text[i] - 48);
                    i++;
                };
                if (neg) { return (i64)0 - r; };
                return r;
            };

            // Operand text "%name" for a fresh result
            def result_text(byte* name) -> byte*
            {
                this.tb.clear();
                this.tb.put(37);
                put_quoted(@this.tb, name);
                return this.own(this.tb.mem);
            };

            // Ends the instruction held in ib. A typed result gets a name (hint, or the
            // next .N); a void one still takes the next .N.
            def fin(IRType* rty, byte* hint) -> IRValue*
            {
                byte* nm;
                byte* txt;
                IRValue* v;
                if (rty == (IRType*)0)
                {
                    // A named void instruction registers its name instead of taking a number
                    if (hint != (byte*)0)
                    {
                        if (hint[0] != 0) { this.fresh_name(this.cf, hint); }
                        else { this.cf.counter = this.cf.counter + 1; };
                    }
                    else { this.cf.counter = this.cf.counter + 1; };
                    pv_push(this.cb.lines, (void*)this.own(this.ib.mem));
                    return (IRValue*)0;
                };
                nm = this.fresh_name(this.cf, hint);
                txt = this.result_text(nm);
                this.lb.clear();
                this.lb.put_str(txt);
                this.lb.put_str(g" = \0");
                this.lb.put_str(this.ib.mem);
                nm = this.own(this.lb.mem);
                pv_push(this.cb.lines, (void*)nm);
                v = this.new_value(rty, txt);
                return v;
            };

            def fin_term() -> void
            {
                this.cf.counter = this.cf.counter + 1;
                pv_push(this.cb.lines, (void*)this.own(this.ib.mem));
                this.cb.terminated = true;
                return;
            };

            def binop(byte* op, IRValue* a, IRValue* b, byte* hint) -> IRValue*
            {
                this.ib.clear();
                this.ib.put_str(op);
                this.ib.put(32);
                lt_text(@this.ib, a.ty);
                this.ib.put(32);
                this.ib.put_str(a.text);
                this.ib.put_str(g", \0");
                this.ib.put_str(b.text);
                return this.fin(a.ty, hint);
            };

            def cmp(byte* kind, byte* pred, IRValue* a, IRValue* b, byte* hint) -> IRValue*
            {
                this.ib.clear();
                this.ib.put_str(kind);
                this.ib.put(32);
                this.ib.put_str(pred);
                this.ib.put(32);
                lt_text(@this.ib, a.ty);
                this.ib.put(32);
                this.ib.put_str(a.text);
                this.ib.put_str(g", \0");
                this.ib.put_str(b.text);
                return this.fin(this.t_int(1), hint);
            };

            def icmp(byte* pred, IRValue* a, IRValue* b, byte* hint) -> IRValue*
            {
                return this.cmp(g"icmp\0", pred, a, b, hint);
            };

            def fcmp(byte* pred, IRValue* a, IRValue* b, byte* hint) -> IRValue*
            {
                return this.cmp(g"fcmp\0", pred, a, b, hint);
            };

            def cast(byte* op, IRValue* v, IRType* to, byte* hint) -> IRValue*
            {
                if (lt_eq(v.ty, to)) { return v; };
                this.ib.clear();
                this.ib.put_str(op);
                this.ib.put(32);
                this.op_text(@this.ib, v);
                this.ib.put_str(g" to \0");
                lt_text(@this.ib, to);
                return this.fin(to, hint);
            };

            def alloca(IRType* ty, byte* name) -> IRValue*
            {
                IRValue* av;
                int pos;
                byte* nm = this.fresh_name(this.cf, name);
                byte* txt = this.result_text(nm);
                IRBlock* eb = this.entry_b;
                this.lb.clear();
                this.lb.put_str(txt);
                this.lb.put_str(g" = alloca \0");
                lt_text(@this.lb, ty);
                pos = eb.lines.len;
                if (eb.terminated) { pos = pos - 1; };
                pv_insert(eb.lines, pos, (void*)this.own(this.lb.mem));
                av = this.new_value(this.t_ptr(ty), txt);
                av.flags = VF_ALLOCA;
                return av;
            };

            // builder.alloca at the current insertion point (not hoisted to entry)
            def alloca_here(IRType* ty, byte* name) -> IRValue*
            {
                IRValue* av;
                this.ib.clear();
                this.ib.put_str(g"alloca \0");
                lt_text(@this.ib, ty);
                av = this.fin(this.t_ptr(ty), name);
                av.flags = VF_ALLOCA;
                return av;
            };

            def load(IRValue* p, byte* hint) -> IRValue*
            {
                this.ib.clear();
                this.ib.put_str(g"load \0");
                lt_text(@this.ib, p.ty.elem);
                this.ib.put_str(g", \0");
                this.op_text(@this.ib, p);
                return this.fin(p.ty.elem, hint);
            };

            def store_ex(IRValue* v, IRValue* p, bool vol) -> void
            {
                this.ib.clear();
                if (vol) { this.ib.put_str(g"store volatile \0"); }
                else { this.ib.put_str(g"store \0"); };
                this.op_text(@this.ib, v);
                this.ib.put_str(g", \0");
                this.op_text(@this.ib, p);
                this.fin((IRType*)0, (byte*)0);
                return;
            };

            def store(IRValue* v, IRValue* p) -> void
            {
                this.store_ex(v, p, false);
                return;
            };

            // Type reached by indexing t with idx (struct needs a constant)
            def index_type(IRType* t, IRValue* idx) -> IRType*
            {
                if (t.kind == LK.ARRAY) { return t.elem; };
                if (t.kind == LK.PTR) { return t.elem; };
                return t.items[(int)this.const_val(idx)];
            };

            def struct_items(IRType* t) -> IRType**
            {
                return t.items;
            };

            def gep(IRValue* p, IRValue** idx, int n, bool inbounds, byte* hint) -> IRValue*
            {
                int i = 1;
                IRType* t = p.ty.elem;
                this.ib.clear();
                this.ib.put_str(g"getelementptr \0");
                if (inbounds) { this.ib.put_str(g"inbounds \0"); };
                lt_text(@this.ib, p.ty.elem);
                this.ib.put_str(g", \0");
                this.op_text(@this.ib, p);
                this.ib.put_str(g", \0");
                this.op_text(@this.ib, idx[0]);
                while (i < n)
                {
                    this.ib.put_str(g", \0");
                    this.op_text(@this.ib, idx[i]);
                    if (t.kind == LK.ISTRUCT)
                    {
                        t = this.struct_body_item(t, (int)this.const_val(idx[i]));
                    }
                    else { t = this.index_type(t, idx[i]); };
                    i++;
                };
                return this.fin(this.t_ptr(t), hint);
            };

            // Member i of an identified struct
            def struct_body_item(IRType* t, int i) -> IRType*
            {
                return t.items[i];
            };

            // gep p, 0, i  (struct field address)
            def gep_field(IRValue* p, int i, bool inbounds, byte* hint) -> IRValue*
            {
                this.ia[0] = this.c_int(this.t_int(32), (i64)0);
                this.ia[1] = this.c_int(this.t_int(32), (i64)i);
                return this.gep(p, this.ia, 2, inbounds, hint);
            };

            // gep p, i  (pointer arithmetic)
            def gep_ptr(IRValue* p, IRValue* i, bool inbounds, byte* hint) -> IRValue*
            {
                this.ia[0] = i;
                return this.gep(p, this.ia, 1, inbounds, hint);
            };

            def call_ex(IRValue* callee, IRValue** args, int n, byte* hint, byte* cconv, bool tail) -> IRValue*
            {
                int i;
                IRType* fty = callee.ty.elem;
                this.ib.clear();
                if (tail) { this.ib.put_str(g"tail \0"); };
                this.ib.put_str(g"call \0");
                if (cconv != (byte*)0)
                {
                    this.ib.put_str(cconv);
                    this.ib.put(32);
                };
                if (fty.vararg)
                {
                    lt_text(@this.ib, fty.elem);
                    this.ib.put_str(g" (\0");
                    while (i < fty.nitems)
                    {
                        if (i > 0) { this.ib.put_str(g", \0"); };
                        lt_text(@this.ib, fty.items[i]);
                        i++;
                    };
                    if (fty.nitems > 0) { this.ib.put_str(g", \0"); };
                    this.ib.put_str(g"...)\0");
                }
                else { lt_text(@this.ib, fty.elem); };
                this.ib.put(32);
                this.ib.put_str(callee.text);
                this.ib.put(40);
                i = 0;
                while (i < n)
                {
                    if (i > 0) { this.ib.put_str(g", \0"); };
                    this.op_text(@this.ib, args[i]);
                    i++;
                };
                this.ib.put(41);
                if (fty.elem.kind == LK.VOID) { return this.fin((IRType*)0, hint); };
                return this.fin(fty.elem, hint);
            };

            def call(IRValue* callee, IRValue** args, int n, byte* hint) -> IRValue*
            {
                return this.call_ex(callee, args, n, hint, (byte*)0, false);
            };

            def phi(IRType* ty, IRValue** vals, IRBlock** blocks, int n, byte* hint) -> IRValue*
            {
                int i;
                this.ib.clear();
                this.ib.put_str(g"phi  \0");
                lt_text(@this.ib, ty);
                this.ib.put(32);
                while (i < n)
                {
                    if (i > 0) { this.ib.put_str(g", \0"); };
                    this.ib.put_str(g"[\0");
                    this.ib.put_str(vals[i].text);
                    this.ib.put_str(g", %\0");
                    put_quoted(@this.ib, blocks[i].name);
                    this.ib.put(93);
                    i++;
                };
                return this.fin(ty, hint);
            };

            def select(IRValue* c, IRValue* a, IRValue* b, byte* hint) -> IRValue*
            {
                this.ib.clear();
                this.ib.put_str(g"select  \0");
                this.op_text(@this.ib, c);
                this.ib.put_str(g", \0");
                this.op_text(@this.ib, a);
                this.ib.put_str(g", \0");
                this.op_text(@this.ib, b);
                return this.fin(a.ty, hint);
            };

            def extractvalue(IRValue* agg, int i, byte* hint) -> IRValue*
            {
                IRType* t = this.index_type(agg.ty, this.c_int(this.t_int(32), (i64)i));
                this.ib.clear();
                this.ib.put_str(g"extractvalue \0");
                this.op_text(@this.ib, agg);
                this.ib.put_str(g", \0");
                this.ib.put_int(i);
                return this.fin(t, hint);
            };

            def insertvalue(IRValue* agg, IRValue* v, int i, byte* hint) -> IRValue*
            {
                this.ib.clear();
                this.ib.put_str(g"insertvalue \0");
                this.op_text(@this.ib, agg);
                this.ib.put_str(g", \0");
                this.op_text(@this.ib, v);
                this.ib.put_str(g", \0");
                this.ib.put_int(i);
                return this.fin(agg.ty, hint);
            };

            def br(IRBlock* target) -> void
            {
                this.ib.clear();
                this.ib.put_str(g"br label %\0");
                put_quoted(@this.ib, target.name);
                this.fin_term();
                return;
            };

            def cbr(IRValue* c, IRBlock* t, IRBlock* f) -> void
            {
                this.ib.clear();
                this.ib.put_str(g"br \0");
                this.op_text(@this.ib, c);
                this.ib.put_str(g", label %\0");
                put_quoted(@this.ib, t.name);
                this.ib.put_str(g", label %\0");
                put_quoted(@this.ib, f.name);
                this.fin_term();
                return;
            };

            def ret(IRValue* v) -> void
            {
                this.ib.clear();
                this.ib.put_str(g"ret \0");
                this.op_text(@this.ib, v);
                this.fin_term();
                return;
            };

            def ret_void() -> void
            {
                this.ib.clear();
                this.ib.put_str(g"ret void\0");
                this.fin_term();
                return;
            };

            def unreachable() -> void
            {
                this.ib.clear();
                this.ib.put_str(g"unreachable\0");
                this.fin_term();
                return;
            };

            def switch_to(IRValue* v, IRBlock* dflt, IRValue** vals, IRBlock** blocks, int n) -> void
            {
                int i;
                this.ib.clear();
                this.ib.put_str(g"switch \0");
                this.op_text(@this.ib, v);
                this.ib.put_str(g", label %\0");
                put_quoted(@this.ib, dflt.name);
                this.ib.put_str(g" [\0");
                while (i < n)
                {
                    if (i > 0) { this.ib.put(32); };
                    this.op_text(@this.ib, vals[i]);
                    this.ib.put_str(g", label %\0");
                    put_quoted(@this.ib, blocks[i].name);
                    i++;
                };
                this.ib.put(93);
                this.fin_term();
                return;
            };

            // ----------------------------------------------------------
            // Printing
            // ----------------------------------------------------------

            def put_function(Buf* out, IRFunc* f) -> void
            {
                int i;
                int j;
                int k;
                IRBlock* bl;
                IRType* ft = f.ftype;
                if (f.is_decl) { out.put_str(g"declare \0"); }
                else { out.put_str(g"define \0"); };
                if (f.linkage != (byte*)0)
                {
                    out.put_str(f.linkage);
                    out.put(32);
                };
                if (f.cconv != (byte*)0)
                {
                    out.put_str(f.cconv);
                    out.put(32);
                };
                lt_text(out, ft.elem);
                out.put(32);
                out.put(64);
                put_quoted(out, f.name);
                out.put(40);
                while (i < f.nargs)
                {
                    if (i > 0) { out.put_str(g", \0"); };
                    lt_text(out, ft.items[i]);
                    out.put(32);
                    out.put_str(f.args[i].text);
                    i++;
                };
                if (ft.vararg)
                {
                    if (f.nargs > 0) { out.put_str(g", \0"); };
                    out.put_str(g"...\0");
                };
                out.put(41);
                while (j < f.attrs.len)
                {
                    out.put(32);
                    out.put_str((byte*)f.attrs.items[j]);
                    j++;
                };
                if (f.is_decl)
                {
                    out.put(10);
                    return;
                };
                out.put_str(g"\n{\n\0");
                j = 0;
                while (j < f.blocks.len)
                {
                    bl = (IRBlock*)f.blocks.items[j];
                    put_quoted_label(out, bl.name);
                    k = 0;
                    while (k < bl.lines.len)
                    {
                        out.put_str(g"  \0");
                        out.put_str((byte*)bl.lines.items[k]);
                        out.put(10);
                        k++;
                    };
                    j++;
                };
                out.put_str(g"}\n\0");
                return;
            };

            // Prints the whole module into out
            def emit(Buf* out) -> void
            {
                int i;
                int j;
                IRType* t;
                IRGlobal* g;
                out.put_str(g"; ModuleID = \0");
                put_quoted(out, this.mod_name);
                out.put(10);
                if (this.triple != (byte*)0)
                {
                    out.put_str(g"target triple = \0");
                    put_quoted(out, this.triple);
                    out.put(10);
                };
                if (this.layout != (byte*)0)
                {
                    out.put_str(g"target datalayout = \0");
                    put_quoted(out, this.layout);
                    out.put(10);
                };
                out.put(10);
                while (i < this.named.len)
                {
                    t = (IRType*)this.named.items[i];
                    out.put(37);
                    put_quoted(out, t.name);
                    if (t.defined)
                    {
                        out.put_str(g" = type {\0");
                        j = 0;
                        while (j < t.nitems)
                        {
                            if (j > 0) { out.put_str(g", \0"); };
                            lt_text(out, t.items[j]);
                            j++;
                        };
                        out.put_str(g"}\n\0");
                    }
                    else { out.put_str(g" = type opaque\n\0"); };
                    i++;
                };
                i = 0;
                while (i < this.funcs.len)
                {
                    out.put(10);
                    this.put_function(out, (IRFunc*)this.funcs.items[i]);
                    i++;
                };
                out.put(10);
                i = 0;
                while (i < this.globals.len)
                {
                    g = (IRGlobal*)this.globals.items[i];
                    out.put(64);
                    put_quoted(out, g.name);
                    out.put_str(g" = \0");
                    if (g.linkage != (byte*)0)
                    {
                        out.put_str(g.linkage);
                        out.put(32);
                    };
                    if (g.constant) { out.put_str(g"constant \0"); }
                    else { out.put_str(g"global \0"); };
                    lt_text(out, g.ty);
                    if (g.init != (byte*)0)
                    {
                        out.put(32);
                        out.put_str(g.init);
                    };
                    out.put(10);
                    i++;
                };
                return;
            };
        };

    };
};

#endif;
