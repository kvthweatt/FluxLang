// Author: Karac V. Thweatt
//
// ftypesys.fx - Flux type model (bootstrap)
//
// Port of the pure (non-LLVM) parts of ftypesys.py:
//     get_builtin_bit_width, infer_int_width, mangle_function_name tokens.
// Adds predicates and equality over TypeSpec for the future check pass.
//
#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_AST
#import "fast.fx";
#endif;

#ifndef FLUX_PREPROCESSOR
#import "fpreprocess.fx";
#endif;

#ifndef FLUX_TYPES
#def FLUX_TYPES 1;

// FXC_* reflection structs, PtrVec and NameMap are global structs defined in runtime.fx.

using flux::ast;
using flux::preprocessor;

namespace flux
{
    namespace types
    {

        // Text of a DataType, identical to DataType.value in ftypesys.py
        def datatype_text(int t) -> byte*
        {
            switch (t)
            {
                case (DataType.SINT)     { return g"int\0"; }
                case (DataType.UINT)     { return g"uint\0"; }
                case (DataType.SLONG)    { return g"long\0"; }
                case (DataType.ULONG)    { return g"ulong\0"; }
                case (DataType.FLOAT)    { return g"float\0"; }
                case (DataType.DOUBLE)   { return g"double\0"; }
                case (DataType.CHAR)     { return g"char\0"; }
                case (DataType.BOOL)     { return g"bool\0"; }
                case (DataType.DATA)     { return g"data\0"; }
                case (DataType.BYTE)     { return g"byte\0"; }
                case (DataType.STRUCT)   { return g"struct\0"; }
                case (DataType.ENUM)     { return g"enum\0"; }
                case (DataType.UNION)    { return g"union\0"; }
                case (DataType.OBJECT)   { return g"object\0"; }
                case (DataType.VOID)     { return g"void\0"; }
                case (DataType.THIS)     { return g"this\0"; }
                case (DataType.FUNC_PTR) { return g"def{}*\0"; }
                case (DataType.DICT)     { return g"dict\0"; }
                default                  { return g"?\0"; };
            };
            return g"?\0";
        };

        // Width in bits of a builtin type, -1 when it has none
        // (mirrors get_builtin_bit_width, which raises instead).
        def builtin_bit_width(int t) -> int
        {
            switch (t)
            {
                case (DataType.SINT)   { return 32; }
                case (DataType.UINT)   { return 32; }
                case (DataType.SLONG)  { return 64; }
                case (DataType.ULONG)  { return 64; }
                case (DataType.FLOAT)  { return 32; }
                case (DataType.DOUBLE) { return 64; }
                case (DataType.CHAR)   { return 8; }
                case (DataType.BYTE)   { return 8; }
                case (DataType.BOOL)   { return 1; }
                case (DataType.VOID)   { return 0; }
                default                { return -1; };
            };
            return -1;
        };

        // Literal width: 32 unless the value needs 64 bits (mirrors infer_int_width).
        // Returns 0 when t is not an integer literal type.
        def infer_int_width(i64 value, int t) -> int
        {
            if (t == DataType.SLONG | t == DataType.ULONG) { return 64; };
            if (t == DataType.SINT)
            {
                if (value >= -2147483648 & value <= 2147483647) { return 32; };
                return 64;
            };
            if (t == DataType.UINT)
            {
                if (value >= 0)
                {
                    if (value <= 4294967295) { return 32; };
                    return 64;
                };
                if (value >= -4294967296) { return 32; };
                return 64;
            };
            return 0;
        };

        def is_integer_base(int t) -> bool
        {
            return t == DataType.SINT | t == DataType.UINT | t == DataType.SLONG |
                   t == DataType.ULONG | t == DataType.CHAR | t == DataType.BYTE |
                   t == DataType.BOOL | t == DataType.DATA;
        };

        def is_float_base(int t) -> bool
        {
            return t == DataType.FLOAT | t == DataType.DOUBLE;
        };

        def is_numeric_base(int t) -> bool
        {
            return is_integer_base(t) | is_float_base(t);
        };

        def is_user_type(TypeSpec* t) -> bool
        {
            return t.custom_typename != (byte*)0;
        };

        def ts_is_pointer(TypeSpec* t) -> bool
        {
            return (t.flags `& TS_POINTER) != 0;
        };

        def ts_is_array(TypeSpec* t) -> bool
        {
            return (t.flags `& TS_ARRAY) != 0;
        };

        def ts_is_signed(TypeSpec* t) -> bool
        {
            return (t.flags `& TS_SIGNED) != 0;
        };

        // Effective width in bits of a scalar TypeSpec (not counting pointers/arrays).
        // DATA and BYTE honour an explicit bit_width. -1 when unknown.
        def typespec_bit_width(TypeSpec* t) -> int
        {
            if (t.custom_typename != (byte*)0) { return -1; };
            if (t.bit_width > 0) { return t.bit_width; };
            return builtin_bit_width(t.base_type);
        };

        def cstr_eq(byte* a, byte* b) -> bool
        {
            int i;
            if (a == (byte*)0 | b == (byte*)0) { return a == b; };
            while (a[i] == b[i])
            {
                if (a[i] == 0) { return true; };
                i++;
            };
            return false;
        };

        // Structural type equality: base type, name, pointer depth, array-ness,
        // width, signedness and endianness.
        def typespec_equal(TypeSpec* a, TypeSpec* b) -> bool
        {
            if (a == b) { return true; };
            if (a == (TypeSpec*)0 | b == (TypeSpec*)0) { return false; };
            if (a.base_type != b.base_type) { return false; };
            if (!cstr_eq(a.custom_typename, b.custom_typename)) { return false; };
            if (a.pointer_depth != b.pointer_depth) { return false; };
            if (ts_is_pointer(a) != ts_is_pointer(b)) { return false; };
            if (ts_is_array(a) != ts_is_array(b)) { return false; };
            if (a.bit_width != b.bit_width) { return false; };
            if (ts_is_signed(a) != ts_is_signed(b)) { return false; };
            if (a.endianness != b.endianness) { return false; };
            if (a.base_type == DataType.FUNC_PTR)
            {
                if (a.fp_nparams != b.fp_nparams) { return false; };
                if (!typespec_equal(a.fp_ret, b.fp_ret)) { return false; };
                int i;
                while (i < a.fp_nparams)
                {
                    if (!typespec_equal(a.fp_params[i], b.fp_params[i])) { return false; };
                    i++;
                };
            };
            return true;
        };

        // Appends the mangled token of one type: name + E0/E1, _arr, _ptrN, _sbitsN/_ubitsN.
        // Mirrors _mangle_type in mangle_function_name. The array size suffix is
        // only emitted when array_size is an integer literal node.
        def mangle_type(Buf* out, TypeSpec* t) -> void
        {
            byte c;
            int i;
            if (t.custom_typename != (byte*)0)
            {
                i = 0;
                while (t.custom_typename[i] != 0)
                {
                    c = t.custom_typename[i];
                    if (c == ':' | c == '.') { c = '_'; };
                    out.put((int)c);
                    i++;
                };
            }
            else
            {
                out.put_str(datatype_text(t.base_type));
            };

            if (t.endianness == 0) { out.put_str(g"E0\0"); }
            else { out.put_str(g"E1\0"); };

            if (ts_is_array(t))
            {
                out.put_str(g"_arr\0");
                if (t.array_size != (Node*)0)
                {
                    if (t.array_size.kind == NodeKind.LITERAL)
                    {
                        out.put_int((int)t.array_size.ival);
                    };
                };
            };

            if (ts_is_pointer(t))
            {
                out.put_str(f"_ptr{t.pointer_depth}\0");
            };

            if (t.base_type == DataType.DATA & t.bit_width > 0)
            {
                if (ts_is_signed(t)) { out.put_str(g"_sbits\0"); }
                else { out.put_str(g"_ubits\0"); };
                out.put_int(t.bit_width);
            };
            return;
        };

        // Builds base__N__p1__p2__ret_R. params is an array of n TypeSpec*.
        def mangle_function(Buf* out, byte* base, TypeSpec** params, int n, TypeSpec* ret) -> void
        {
            int i;
            out.put_str(f"{base}__{n}\0");
            while (i < n)
            {
                out.put_str(g"__\0");
                mangle_type(out, params[i]);
                i++;
            };
            out.put_str(g"__ret_\0");
            mangle_type(out, ret);
            return;
        };

        // ------------------------------------------------------------------
        // Small containers (heap, plain structs)
        // ------------------------------------------------------------------

        // Heap string a + b + c
        def join3(byte* a, byte* b, byte* c) -> byte*
        {
            int la = pp_cstrlen(a);
            int lb = pp_cstrlen(b);
            int lc = pp_cstrlen(c);
            byte* r = (byte*)fmalloc((u64)(la + lb + lc + 1));
            int i, j, k;
            while (i < la)
            {
                r[i] = a[i];
                i++;
            };
            while (j < lb)
            {
                r[la + j] = b[j];
                j++;
            };
            while (k < lc)
            {
                r[la + lb + k] = c[k];
                k++;
            };
            r[la + lb + lc] = (byte)0;
            return r;
        };

        // join3 that also frees the heap arguments named by mask: 1 for a, 2 for b, 4 for c
        def join3_f(byte* a, byte* b, byte* c, int mask) -> byte*
        {
            byte* r = join3(a, b, c);
            if ((mask `& 1) != 0) { ffree(a); };
            if ((mask `& 2) != 0) { ffree(b); };
            if ((mask `& 4) != 0) { ffree(c); };
            return r;
        };

        // Heap copy of a null terminated string
        def ts_dup(byte* s) -> byte*
        {
            int n = pp_cstrlen(s);
            byte* r = (byte*)fmalloc((u64)n + (u64)1);
            int i;
            while (i < n)
            {
                r[i] = s[i];
                i++;
            };
            r[n] = (byte)0;
            return r;
        };

        def pv_new() -> PtrVec*
        {
            PtrVec* v = (PtrVec*)fmalloc((u64)(sizeof(PtrVec) / 8));
            v.len = 0;
            v.cap = 8;
            v.items = (void**)fmalloc((u64)v.cap * (u64)(sizeof(void*) / 8));
            return v;
        };

        def pv_push(PtrVec* v, void* p) -> void
        {
            if (v.len >= v.cap)
            {
                int nc = v.cap * 2;
                u64 np = frealloc((u64)v.items, (size_t)((u64)nc * (u64)(sizeof(void*) / 8)));
                v.items = (void**)np;
                v.cap = nc;
            };
            v.items[v.len] = p;
            v.len++;
            return;
        };

        def pv_insert(PtrVec* v, int at, void* p) -> void
        {
            int i;
            pv_push(v, p);
            i = v.len - 1;
            while (i > at)
            {
                v.items[i] = v.items[i - 1];
                i--;
            };
            v.items[at] = p;
            return;
        };

        def pv_free(PtrVec* v) -> void
        {
            if (v == (PtrVec*)0) { return; };
            ffree((byte*)v.items);
            ffree((byte*)v);
            return;
        };

        // True when the string list v (of byte*) holds s
        def sv_has(PtrVec* v, byte* s) -> bool
        {
            int i;
            while (i < v.len)
            {
                if (cstr_eq((byte*)v.items[i], s)) { return true; };
                i++;
            };
            return false;
        };

        // Appends a copy of s unless already present
        def sv_add(PtrVec* v, byte* s) -> void
        {
            if (sv_has(v, s)) { return; };
            pv_push(v, (void*)ts_dup(s));
            return;
        };

        def sv_free(PtrVec* v) -> void
        {
            int i;
            while (i < v.len)
            {
                ffree((byte*)v.items[i]);
                i++;
            };
            pv_free(v);
            return;
        };

        def nm_hash(byte* s) -> u64
        {
            return pp_hash(s, pp_cstrlen(s));
        };

        def nm_new() -> NameMap*
        {
            NameMap* m = (NameMap*)fmalloc((u64)(sizeof(NameMap) / 8));
            m.count = 0;
            m.ent_cap = 16;
            m.slot_cap = 64;
            m.keys = (byte**)fmalloc((u64)m.ent_cap * (u64)(sizeof(byte*) / 8));
            m.vals = (void**)fmalloc((u64)m.ent_cap * (u64)(sizeof(void*) / 8));
            m.slots = (int*)fmalloc((u64)m.slot_cap * (u64)(sizeof(int) / 8));
            int z;
            while (z < m.slot_cap)
            {
                m.slots[z] = 0;
                z++;
            };
            return m;
        };

        def nm_free(NameMap* m) -> void
        {
            if (m == (NameMap*)0) { return; };
            int i;
            while (i < m.count)
            {
                ffree(m.keys[i]);
                i++;
            };
            ffree((byte*)m.keys);
            ffree((byte*)m.vals);
            ffree((byte*)m.slots);
            ffree((byte*)m);
            return;
        };

        // Entry index of key, or -1
        def nm_find(NameMap* m, byte* key) -> int
        {
            int idx = (int)(nm_hash(key) % (u64)m.slot_cap);
            int e;
            while (true)
            {
                e = m.slots[idx];
                if (e == 0) { return -1; };
                e = e - 1;
                if (cstr_eq(m.keys[e], key)) { return e; };
                idx++;
                if (idx >= m.slot_cap) { idx = 0; };
            };
            return -1;
        };

        def nm_place(NameMap* m, int e) -> void
        {
            int idx = (int)(nm_hash(m.keys[e]) % (u64)m.slot_cap);
            while (m.slots[idx] != 0)
            {
                idx++;
                if (idx >= m.slot_cap) { idx = 0; };
            };
            m.slots[idx] = e + 1;
            return;
        };

        def nm_rehash(NameMap* m) -> void
        {
            int nc = m.slot_cap * 2;
            ffree((byte*)m.slots);
            m.slots = (int*)fmalloc((u64)nc * (u64)(sizeof(int) / 8));
            m.slot_cap = nc;
            int z, e;
            while (z < nc)
            {
                m.slots[z] = 0;
                z++;
            };
            while (e < m.count)
            {
                nm_place(m, e);
                e++;
            };
            return;
        };

        def nm_get(NameMap* m, byte* key) -> void*
        {
            int e = nm_find(m, key);
            if (e < 0) { return (void*)0; };
            return m.vals[e];
        };

        def nm_has(NameMap* m, byte* key) -> bool
        {
            return nm_get(m, key) != (void*)0;
        };

        def nm_put(NameMap* m, byte* key, void* v) -> void
        {
            int e = nm_find(m, key);
            if (e >= 0)
            {
                m.vals[e] = v;
                return;
            };
            if (m.count >= m.ent_cap)
            {
                int nc = m.ent_cap * 2;
                u64 nk = frealloc((u64)m.keys, (size_t)((u64)nc * (u64)(sizeof(byte*) / 8)));
                u64 nv = frealloc((u64)m.vals, (size_t)((u64)nc * (u64)(sizeof(void*) / 8)));
                m.keys = (byte**)nk;
                m.vals = (void**)nv;
                m.ent_cap = nc;
            };
            if ((m.count + 1) * 2 > m.slot_cap) { nm_rehash(m); };
            m.keys[m.count] = ts_dup(key);
            m.vals[m.count] = v;
            nm_place(m, m.count);
            m.count++;
            return;
        };

        // Removes the value for key. Returns false when it was not present.
        def nm_del(NameMap* m, byte* key) -> bool
        {
            int e = nm_find(m, key);
            if (e < 0) { return false; };
            if (m.vals[e] == (void*)0) { return false; };
            m.vals[e] = (void*)0;
            return true;
        };

        // ------------------------------------------------------------------
        // Namespace name helpers
        // ------------------------------------------------------------------

        // True when s contains "::"
        def has_scope_sep(byte* s) -> bool
        {
            int i;
            while (s[i] != 0)
            {
                if (s[i] == ':' & s[i + 1] == ':') { return true; };
                i++;
            };
            return false;
        };

        // Heap copy of s with every "::" replaced by "__"
        def colons_to_underscores(byte* s) -> byte*
        {
            byte* r = ts_dup(s);
            int i;
            while (r[i] != 0)
            {
                if (r[i] == ':' & r[i + 1] == ':')
                {
                    r[i] = '_';
                    r[i + 1] = '_';
                    i++;
                };
                i++;
            };
            return r;
        };

        // Heap string ns__name with "::" in ns turned into "__". Just name when ns is empty.
        // Mirrors TypeResolver.mangle_namespace_name.
        def mangle_namespace_name(byte* ns, byte* name) -> byte*
        {
            if (ns == (byte*)0) { return ts_dup(name); };
            if (ns[0] == 0) { return ts_dup(name); };
            byte* a = colons_to_underscores(ns);
            int la = pp_cstrlen(a);
            int lb = pp_cstrlen(name);
            byte* r = (byte*)fmalloc((u64)(la + lb + 3));
            int i, j;
            while (i < la)
            {
                r[i] = a[i];
                i++;
            };
            r[i] = '_';
            r[i + 1] = '_';
            i = i + 2;
            while (j < lb)
            {
                r[i + j] = name[j];
                j++;
            };
            r[i + lb] = (byte)0;
            ffree(a);
            return r;
        };

        // Heap copy of ns without its last "::" component ("" when it has one component)
        def namespace_parent(byte* ns) -> byte*
        {
            int n = pp_cstrlen(ns);
            int i = n - 1;
            byte* r;
            int j;
            while (i > 0)
            {
                if (ns[i] == ':' & ns[i - 1] == ':')
                {
                    r = (byte*)fmalloc((u64)i);
                    while (j < i - 1)
                    {
                        r[j] = ns[j];
                        j++;
                    };
                    r[i - 1] = (byte)0;
                    return r;
                };
                i--;
            };
            byte* e = (byte*)fmalloc((u64)1);
            e[0] = (byte)0;
            return e;
        };

        // ------------------------------------------------------------------
        // Symbols
        // ------------------------------------------------------------------

        // Reflection kind string for a SymbolKind (FXC_SYMENTRY.kind). Heap copy.
        def symkind_text(int k) -> byte*
        {
            switch (k)
            {
                case (SymbolKind.TYPE)      { return ts_dup(g"type\0"); }
                case (SymbolKind.VARIABLE)  { return ts_dup(g"variable\0"); }
                case (SymbolKind.FUNCTION)  { return ts_dup(g"function\0"); }
                case (SymbolKind.NAMESPACE) { return ts_dup(g"namespace\0"); }
                case (SymbolKind.OBJECT)    { return ts_dup(g"object\0"); }
                case (SymbolKind.STRUCT)    { return ts_dup(g"struct\0"); }
                case (SymbolKind.UNION)     { return ts_dup(g"union\0"); }
                case (SymbolKind.ENUM)      { return ts_dup(g"enum\0"); }
                case (SymbolKind.TRAIT)     { return ts_dup(g"trait\0"); }
                case (SymbolKind.OPERATOR)  { return ts_dup(g"operator\0"); }
                case (SymbolKind.INTERFACE) { return ts_dup(g"interface\0"); }
                default                     { return ts_dup(g"\0"); };
            };
            return ts_dup(g"\0");
        };

        // Heap ns__name, or name when there is no namespace (SymbolEntry.mangled_name)
        def sym_mangled(FXC_SYMENTRY* e) -> byte*
        {
            return mangle_namespace_name(e.ns, e.name);
        };

        // Heap ns::name, or name when there is no namespace (SymbolEntry.full_name)
        def sym_full_name(FXC_SYMENTRY* e) -> byte*
        {
            if (e.ns[0] == 0) { return ts_dup(e.name); };
            int la = pp_cstrlen(e.ns);
            int lb = pp_cstrlen(e.name);
            byte* r = (byte*)fmalloc((u64)(la + lb + 3));
            int i, j;
            while (i < la)
            {
                r[i] = e.ns[i];
                i++;
            };
            r[i] = ':';
            r[i + 1] = ':';
            i = i + 2;
            while (j < lb)
            {
                r[i + j] = e.name[j];
                j++;
            };
            r[i + lb] = (byte)0;
            return r;
        };

        // One function overload registered under its base name
        struct Overload
        {
            byte* mangled;
            Node* func;
            TypeSpec** params;
            int nparams;
            TypeSpec* ret;
            bool deprecated;
        };

        // Shallow copy of a TypeSpec. Child pointers are shared with the source.
        def typespec_clone(TypeSpec* s) -> TypeSpec*
        {
            TypeSpec* t = typespec_new();
            t.base_type = s.base_type;
            t.flags = s.flags;
            t.bit_width = s.bit_width;
            t.alignment = s.alignment;
            t.endianness = s.endianness;
            t.pointer_depth = s.pointer_depth;
            t.storage_class = s.storage_class;
            t.dict_capacity = s.dict_capacity;
            t.fp_nparams = s.fp_nparams;
            t.array_size = s.array_size;
            t.array_dims = s.array_dims;
            t.array_elem = s.array_elem;
            t.dict_key = s.dict_key;
            t.dict_value = s.dict_value;
            t.fp_ret = s.fp_ret;
            t.fp_params = s.fp_params;
            t.custom_typename = s.custom_typename;
            t.calling_conv = s.calling_conv;
            return t;
        };

        // ------------------------------------------------------------------
        // Symbol table (port of ftypesys.SymbolTable), operating on FXC_SYMTABLE
        // ------------------------------------------------------------------
        def st_new() -> FXC_SYMTABLE*
        {
            FXC_SYMTABLE* st = (FXC_SYMTABLE*)fmalloc((u64)(sizeof(FXC_SYMTABLE) / 8));
            st.entries = 0;
        st.entry = (FXC_SYMENTRY*)0;
        st.scopes = pv_new();
            st.owned = pv_new();
            st.owned_ts = pv_new();
            st.using_ns = pv_new();
            st.registered_ns = pv_new();
            st.overload_lists = pv_new();
            st.globals = nm_new();
            st.overloads = nm_new();
            st.nofunc = nm_new();
            st.current_ns = ts_dup(g"\0");
            pv_push(st.scopes, (void*)nm_new());
            return st;
        };

        def st_free(FXC_SYMTABLE* st) -> void
        {
            int i, j;
            FXC_SYMENTRY* e;
            PtrVec* ol;
            Overload* o;
            while (i < st.scopes.len)
            {
                nm_free((NameMap*)st.scopes.items[i]);
                i++;
            };
            i = 0;
            while (i < st.owned.len)
            {
                e = (FXC_SYMENTRY*)st.owned.items[i];
                ffree(e.name);
                ffree(e.kind);
                ffree(e.ns);
                ffree((byte*)e);
                i++;
            };
            i = 0;
            while (i < st.owned_ts.len)
            {
                ffree((byte*)st.owned_ts.items[i]);
                i++;
            };
            i = 0;
            while (i < st.overload_lists.len)
            {
                ol = (PtrVec*)st.overload_lists.items[i];
                j = 0;
                while (j < ol.len)
                {
                    o = (Overload*)ol.items[j];
                    ffree(o.mangled);
                    ffree((byte*)o.params);
                    ffree((byte*)o);
                    j++;
                };
                pv_free(ol);
                i++;
            };
            pv_free(st.scopes);
            pv_free(st.owned);
            pv_free(st.owned_ts);
            pv_free(st.overload_lists);
            sv_free(st.using_ns);
            sv_free(st.registered_ns);
            nm_free(st.globals);
            nm_free(st.overloads);
            nm_free(st.nofunc);
            ffree(st.current_ns);
            ffree((byte*)st);
            return;
        };

        // 0 = global scope
        def st_scope_level(FXC_SYMTABLE* st) -> int
        {
            return st.scopes.len - 1;
        };

        def st_is_global_scope(FXC_SYMTABLE* st) -> bool
        {
            return st.scopes.len == 1;
        };

        def st_enter_scope(FXC_SYMTABLE* st) -> void
        {
            pv_push(st.scopes, (void*)nm_new());
            return;
        };

        def st_exit_scope(FXC_SYMTABLE* st) -> void
        {
            if (st.scopes.len > 1)
            {
                st.scopes.len--;
                nm_free((NameMap*)st.scopes.items[st.scopes.len]);
            };
            return;
        };

        def st_set_namespace(FXC_SYMTABLE* st, byte* ns) -> void
        {
            ffree(st.current_ns);
            st.current_ns = ts_dup(ns);
            if (ns[0] != 0) { sv_add(st.registered_ns, ns); };
            return;
        };

        def st_add_using_namespace(FXC_SYMTABLE* st, byte* ns) -> void
        {
            sv_add(st.using_ns, ns);
            return;
        };

        def st_remove_using_namespace(FXC_SYMTABLE* st, byte* ns) -> void
        {
            int i;
            while (i < st.using_ns.len)
            {
                if (cstr_eq((byte*)st.using_ns.items[i], ns))
                {
                    ffree((byte*)st.using_ns.items[i]);
                    st.using_ns.items[i] = st.using_ns.items[st.using_ns.len - 1];
                    st.using_ns.len--;
                    return;
                };
                i++;
            };
            return;
        };

        def st_register_namespace(FXC_SYMTABLE* st, byte* ns) -> void
        {
            sv_add(st.registered_ns, ns);
            return;
        };

        def st_mark_nofunc(FXC_SYMTABLE* st, byte* type_name) -> void
        {
            nm_put(st.nofunc, type_name, (void*)st);
            return;
        };

        def st_is_nofunc(FXC_SYMTABLE* st, byte* type_name) -> bool
        {
            return nm_has(st.nofunc, type_name);
        };

        // Defines name in the innermost scope. Top level symbols also enter the
        // global table under the mangled name and, when free, the bare name.
        def st_define(FXC_SYMTABLE* st, byte* name, int kind, TypeSpec* ts, Node* node) -> FXC_SYMENTRY*
        {
            FXC_SYMENTRY* e = (FXC_SYMENTRY*)fmalloc((u64)(sizeof(FXC_SYMENTRY) / 8));
            e.kind_id = kind;
            e.kind = symkind_text(kind);
            e.flags = 0;
            e.name = ts_dup(name);
            if (st.scopes.len == 1) { e.ns = ts_dup(st.current_ns); }
            else { e.ns = ts_dup(g"\0"); };
            e.ts = (void*)ts;
            e.node = (void*)node;
            pv_push(st.owned, (void*)e);

            nm_put((NameMap*)st.scopes.items[st.scopes.len - 1], name, (void*)e);

            if (st.scopes.len == 1)
            {
                byte* m = sym_mangled(e);
                nm_put(st.globals, m, (void*)e);
                ffree(m);
                if (!nm_has(st.globals, name)) { nm_put(st.globals, name, (void*)e); };
            };
            return e;
        };

        // Looks name up through the namespace walk against the global table:
        // qualified, exact, current namespace, parents, using, registered.
        def st_resolve_with_namespaces(FXC_SYMTABLE* st, byte* name, byte* cur) -> FXC_SYMENTRY*
        {
            void* r;
            byte* m;
            int i;

            // 0. fully qualified
            if (has_scope_sep(name))
            {
                m = colons_to_underscores(name);
                r = nm_get(st.globals, m);
                ffree(m);
                if (r != (void*)0) { return (FXC_SYMENTRY*)r; };
            };

            // 1. exact
            r = nm_get(st.globals, name);
            if (r != (void*)0) { return (FXC_SYMENTRY*)r; };

            // 2. current namespace
            if (cur[0] != 0)
            {
                m = mangle_namespace_name(cur, name);
                r = nm_get(st.globals, m);
                ffree(m);
                if (r != (void*)0) { return (FXC_SYMENTRY*)r; };

                // 3. parents, nearest first, ending at the top level
                byte* walk = ts_dup(cur);
                byte* p;
                bool more = true;
                while (more)
                {
                    more = has_scope_sep(walk);
                    p = namespace_parent(walk);
                    m = mangle_namespace_name(p, name);
                    r = nm_get(st.globals, m);
                    ffree(m);
                    ffree(walk);
                    walk = p;
                    if (r != (void*)0)
                    {
                        ffree(walk);
                        return (FXC_SYMENTRY*)r;
                    };
                };
                ffree(walk);
            };

            // 4. using namespaces
            while (i < st.using_ns.len)
            {
                m = mangle_namespace_name((byte*)st.using_ns.items[i], name);
                r = nm_get(st.globals, m);
                ffree(m);
                if (r != (void*)0) { return (FXC_SYMENTRY*)r; };
                i++;
            };

            // 5. every registered namespace
            i = 0;
            while (i < st.registered_ns.len)
            {
                m = mangle_namespace_name((byte*)st.registered_ns.items[i], name);
                r = nm_get(st.globals, m);
                ffree(m);
                if (r != (void*)0) { return (FXC_SYMENTRY*)r; };
                i++;
            };
            return (FXC_SYMENTRY*)0;
        };

        // Innermost scope first, then the namespace walk. cur may be null.
        def st_lookup_any(FXC_SYMTABLE* st, byte* name, byte* cur) -> FXC_SYMENTRY*
        {
            if (cur == (byte*)0) { cur = st.current_ns; };
            int i = st.scopes.len - 1;
            void* r;
            while (i >= 0)
            {
                r = nm_get((NameMap*)st.scopes.items[i], name);
                if (r != (void*)0) { return (FXC_SYMENTRY*)r; };
                i--;
            };
            return st_resolve_with_namespaces(st, name, cur);
        };

        def st_lookup_type(FXC_SYMTABLE* st, byte* name, byte* cur) -> FXC_SYMENTRY*
        {
            FXC_SYMENTRY* e = st_lookup_any(st, name, cur);
            if (e == (FXC_SYMENTRY*)0) { return e; };
            if (e.kind_id == SymbolKind.TYPE | e.kind_id == SymbolKind.STRUCT | e.kind_id == SymbolKind.OBJECT |
                e.kind_id == SymbolKind.UNION | e.kind_id == SymbolKind.ENUM) { return e; };
            return (FXC_SYMENTRY*)0;
        };

        def st_lookup_variable(FXC_SYMTABLE* st, byte* name, byte* cur) -> FXC_SYMENTRY*
        {
            FXC_SYMENTRY* e = st_lookup_any(st, name, cur);
            if (e == (FXC_SYMENTRY*)0) { return e; };
            if (e.kind_id == SymbolKind.VARIABLE) { return e; };
            return (FXC_SYMENTRY*)0;
        };

        def st_lookup_function(FXC_SYMTABLE* st, byte* name, byte* cur) -> FXC_SYMENTRY*
        {
            FXC_SYMENTRY* e = st_lookup_any(st, name, cur);
            if (e == (FXC_SYMENTRY*)0) { return e; };
            if (e.kind_id == SymbolKind.FUNCTION) { return e; };
            return (FXC_SYMENTRY*)0;
        };

        def st_get_type_spec(FXC_SYMTABLE* st, byte* name) -> TypeSpec*
        {
            FXC_SYMENTRY* e = st_lookup_any(st, name, (byte*)0);
            if (e == (FXC_SYMENTRY*)0) { return (TypeSpec*)0; };
            return (TypeSpec*)e.ts;
        };

        // Removes name from the innermost scope
        def st_delete_variable(FXC_SYMTABLE* st, byte* name) -> bool
        {
            return nm_del((NameMap*)st.scopes.items[st.scopes.len - 1], name);
        };

        // Records an overload of base. A parameter whose type is a named alias
        // takes its signedness from the alias (ftypesys.register_function_overload).
        def st_register_function_overload(FXC_SYMTABLE* st, byte* base, byte* mangled, TypeSpec** ptypes, int n,
                                       TypeSpec* ret, Node* fn, bool deprecated) -> Overload*
        {
            PtrVec* list = (PtrVec*)nm_get(st.overloads, base);
            if (list == (PtrVec*)0)
            {
                list = pv_new();
                pv_push(st.overload_lists, (void*)list);
                nm_put(st.overloads, base, (void*)list);
            };

            Overload* o = (Overload*)fmalloc((u64)(sizeof(Overload) / 8));
            o.mangled = ts_dup(mangled);
            o.func = fn;
            o.nparams = n;
            o.ret = ret;
            o.deprecated = deprecated;
            o.params = (TypeSpec**)fmalloc((u64)(n + 1) * (u64)(sizeof(TypeSpec*) / 8));

            int i;
            TypeSpec* p;
            FXC_SYMENTRY* al;
            TypeSpec* c;
            while (i < n)
            {
                p = ptypes[i];
                if (p.custom_typename != (byte*)0)
                {
                    al = st_lookup_type(st, p.custom_typename, (byte*)0);
                    if (al != (FXC_SYMENTRY*)0)
                    {
                        if (al.kind_id == SymbolKind.TYPE & (TypeSpec*)al.ts != (TypeSpec*)0)
                        {
                            if (ts_is_signed((TypeSpec*)al.ts) != ts_is_signed(p))
                            {
                                c = typespec_clone(p);
                                if (ts_is_signed((TypeSpec*)al.ts)) { c.flags = c.flags `| TS_SIGNED; }
                                else { c.flags = c.flags - TS_SIGNED; };
                                pv_push(st.owned_ts, (void*)c);
                                p = c;
                            };
                        };
                    };
                };
                o.params[i] = p;
                i++;
            };
            pv_push(list, (void*)o);
            return o;
        };

        // All overloads registered under base, or null
        def st_overloads_of(FXC_SYMTABLE* st, byte* base) -> PtrVec*
        {
            return (PtrVec*)nm_get(st.overloads, base);
        };
    };
};

#endif;
