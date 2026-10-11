// Author: Karac V. Thweatt
//
// fpreprocess.fx - Flux preprocessor library (port of fpreprocess.py and fmacros.py)
//
// Usage from fxc.fx:
//
//     #import "fpreprocess.fx";
//     using flux::preprocessor;
//
//     Preprocessor pp(path);
//     defer pp.__exit();
//     pp.set_srcdir(srcdir);        // FLUXC_SRCDIR, stdlib is searched under it
//     pp.add_default_macros();      // fmacros.py predefined table
//     if (!pp.process())
//     {
//         // pp.err_kind (PPError), pp.err_text() holds the message
//     };
//     pp.text_ptr(), pp.text_len()  // combined, substituted source
//     pp.line_count                 // number of output lines
//     pp.map_path(i), pp.map_lineno(i)   // line_map entry of output line i (0 based)
//
// The result of process() is the same text FXPreprocessor.process() returns.
// The output is owned by the Preprocessor and stays valid until __exit().

#ifndef FLUX_STANDARD
#import <standard.fx>;
#endif;

#ifndef FLUX_STANDARD_FFI_FIO
#import <runtime\ffifio.fx>;
#endif;

using standard::io::file;

#ifndef FLUX_PREPROCESSOR
#def FLUX_PREPROCESSOR 1;

#ifdef __WINDOWS__
#def FLUX_PP_SEP 92;
#else
#def FLUX_PP_SEP 47;
#endif;

#def FLUX_PP_STRIDE 8;
#def FLUX_PP_PATH_MAX 4096;
#def FLUX_PP_MAX_DEPTH 64;

namespace flux
{
    namespace preprocessor
    {
        extern
        {
            def !!getenv(byte* name) -> byte*;
        };

        #ifdef __WINDOWS__
        extern
        {
            def !!
                _access(byte* path, int mode) -> int,
                _fullpath(byte* absbuf, byte* relpath, size_t maxlen) -> byte*;
        };
        #else
        extern
        {
            def !!
                access(byte* path, int mode) -> int,
                realpath(byte* path, byte* resolved) -> byte*;
        };
        #endif;

        enum PPError
        {
            NONE,
            SYNTAX,
            NOT_FOUND,
            KEY,
            RECURSION,
            STOP,
            ALLOC,
            IO
        };

        // A list of source lines as (offset, length) slices over one text block.
        struct LineList
        {
            byte* text;
            int* off;
            int* len;
            int n;
        };

        // ===== BYTE HELPERS =====

        def pp_cstrlen(byte* s) -> int
        {
            int n;
            while (s[n] != 0) { n++; };
            return n;
        };

        def pp_eq(byte* a, byte* b, int n) -> bool
        {
            int i;
            while (i < n)
            {
                if (a[i] != b[i]) { return false; };
                i++;
            };
            return true;
        };

        // Byte at i, or -1 outside [0, n)
        def pp_at(byte* s, int n, int i) -> int
        {
            if (i < 0) { return -1; };
            if (i >= n) { return -1; };
            return (int)s[i];
        };

        def pp_find(byte* t, int lo, int hi, int ch) -> int
        {
            int i = lo;
            while (i < hi)
            {
                if ((int)t[i] == ch) { return i; };
                i++;
            };
            return -1;
        };

        def pp_starts(byte* t, int lo, int hi, byte* lit, int ln) -> bool
        {
            if (hi - lo < ln) { return false; };
            return pp_eq(t + lo, lit, ln);
        };

        def pp_is_alpha_us(int c) -> bool
        {
            return (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z') | c == '_';
        };

        def pp_is_word(int c) -> bool
        {
            return (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z') | (c >= '0' & c <= '9') | c == '_';
        };

        // Characters that end a token in _substitute_constants
        def pp_is_delim(int c) -> bool
        {
            return c == '.' | c == ',' | c == ';' | c == ':' | c == '(' | c == ')'
                 | c == '[' | c == ']' | c == '{' | c == '}' | c == '+' | c == '-'
                 | c == '*' | c == '/' | c == '%' | c == '=' | c == '!' | c == '<'
                 | c == '>' | c == '|' | c == '&' | c == '^' | c == '~';
        };

        // Length in bytes of the Unicode whitespace character at s[i], 0 if none
        // (the set str.isspace() accepts).
        def pp_ws_fwd(byte* s, int n, int i) -> int
        {
            if (i >= n) { return 0; };
            int c = (int)s[i];
            if (c == 32 | (c >= 9 & c <= 13) | (c >= 28 & c <= 31)) { return 1; };
            if (c < 128) { return 0; };
            int c1 = pp_at(s, n, i + 1);
            int c2 = pp_at(s, n, i + 2);
            if (c == 0xC2)
            {
                if (c1 == 0x85 | c1 == 0xA0) { return 2; };
                return 0;
            };
            if (c == 0xE1)
            {
                if (c1 == 0x9A & c2 == 0x80) { return 3; };
                return 0;
            };
            if (c == 0xE2)
            {
                if (c1 == 0x80)
                {
                    if ((c2 >= 0x80 & c2 <= 0x8A) | c2 == 0xA8 | c2 == 0xA9 | c2 == 0xAF) { return 3; };
                    return 0;
                };
                if (c1 == 0x81 & c2 == 0x9F) { return 3; };
                return 0;
            };
            if (c == 0xE3)
            {
                if (c1 == 0x80 & c2 == 0x80) { return 3; };
                return 0;
            };
            return 0;
        };

        // Length of the whitespace character that ends at s[j - 1], never reading below lo
        def pp_ws_back(byte* s, int lo, int j) -> int
        {
            if (j <= lo) { return 0; };
            int c = (int)s[j - 1];
            if (c == 32 | (c >= 9 & c <= 13) | (c >= 28 & c <= 31)) { return 1; };
            if (c < 128) { return 0; };
            int b1, b2;
            if (j - 2 >= lo)
            {
                b1 = (int)s[j - 2];
                if (b1 == 0xC2 & (c == 0x85 | c == 0xA0)) { return 2; };
            };
            if (j - 3 >= lo)
            {
                b2 = (int)s[j - 3];
                b1 = (int)s[j - 2];
                if (b2 == 0xE1 & b1 == 0x9A & c == 0x80) { return 3; };
                if (b2 == 0xE2 & b1 == 0x80)
                {
                    if ((c >= 0x80 & c <= 0x8A) | c == 0xA8 | c == 0xA9 | c == 0xAF) { return 3; };
                };
                if (b2 == 0xE2 & b1 == 0x81 & c == 0x9F) { return 3; };
                if (b2 == 0xE3 & b1 == 0x80 & c == 0x80) { return 3; };
            };
            return 0;
        };

        // str.strip() on t[*lo, *hi)
        def pp_trim(byte* t, int* lo, int* hi) -> void
        {
            int a = *lo;
            int b = *hi;
            int w;
            while (a < b)
            {
                w = pp_ws_fwd(t, b, a);
                if (w == 0) { break; };
                a = a + w;
            };
            while (b > a)
            {
                w = pp_ws_back(t, a, b);
                if (w == 0) { break; };
                b = b - w;
            };
            *lo = a;
            *hi = b;
            return;
        };

        // Next whitespace separated token in t[pos, hi) (str.split()).
        // Returns the end of the token, or -1 when there is none.
        def pp_next_tok(byte* t, int hi, int pos, int* ts, int* te) -> int
        {
            int p = pos;
            int w;
            while (p < hi)
            {
                w = pp_ws_fwd(t, hi, p);
                if (w == 0) { break; };
                p = p + w;
            };
            if (p >= hi) { return -1; };
            *ts = p;
            while (p < hi)
            {
                w = pp_ws_fwd(t, hi, p);
                if (w != 0) { break; };
                p++;
            };
            *te = p;
            return p;
        };

        // End of the line that starts at p, following str.splitlines().
        // *tl receives the terminator length (0 at end of text).
        def pp_eol(byte* t, int n, int p, int* tl) -> int
        {
            int j = p;
            int c, c1, c2;
            while (j < n)
            {
                c = (int)t[j];
                if (c == 10 | c == 11 | c == 12 | c == 28 | c == 29 | c == 30)
                {
                    *tl = 1;
                    return j;
                };
                if (c == 13)
                {
                    *tl = 1;
                    if (pp_at(t, n, j + 1) == 10) { *tl = 2; };
                    return j;
                };
                if (c == 0xC2)
                {
                    if (pp_at(t, n, j + 1) == 0x85)
                    {
                        *tl = 2;
                        return j;
                    };
                };
                if (c == 0xE2)
                {
                    c1 = pp_at(t, n, j + 1);
                    c2 = pp_at(t, n, j + 2);
                    if (c1 == 0x80 & (c2 == 0xA8 | c2 == 0xA9))
                    {
                        *tl = 3;
                        return j;
                    };
                };
                j++;
            };
            *tl = 0;
            return n;
        };

        // Regex style \b between s[pos - 1] and s[pos] over ASCII word characters
        def pp_boundary(byte* s, int n, int pos) -> bool
        {
            bool a = false;
            bool b = false;
            if (pos > 0) { a = pp_is_word((int)s[pos - 1]); };
            if (pos < n) { b = pp_is_word((int)s[pos]); };
            return (a & !b) | (!a & b);
        };

        def pp_is_abs(byte* r, int n) -> bool
        {
            if (n <= 0) { return false; };
            if ((int)r[0] == FLUX_PP_SEP) { return true; };
            #ifdef __WINDOWS__
            if (n >= 2)
            {
                if (r[1] == ':') { return true; };
            };
            #endif;
            return false;
        };

        // Length of Path(p).parent for an absolute path (0 for a bare name)
        def pp_parent_len(byte* p, int n) -> int
        {
            int i = n - 1;
            while (i >= 0)
            {
                if ((int)p[i] == FLUX_PP_SEP) { break; };
                i--;
            };
            if (i < 0) { return 0; };
            if (i == 0) { return 1; };
            #ifdef __WINDOWS__
            if (i == 2)
            {
                if (p[1] == ':') { return 3; };
            };
            #endif;
            return i;
        };

        def pp_exists(byte* p) -> bool
        {
            #ifdef __WINDOWS__
            return _access(p, 0) == 0;
            #else
            return access(p, 0) == 0;
            #endif;
        };

        def pp_hash(byte* s, int n) -> u64
        {
            u64 h = (u64)5381;
            int i;
            while (i < n)
            {
                h = h * (u64)33 + (u64)s[i];
                i++;
            };
            return h;
        };

        // ===== GROWABLE BYTE BUFFER =====
        // mem is always null terminated while it is allocated; len excludes the terminator.
        // ok turns false once an allocation fails and stays false.

        object Buf
        {
            byte* mem;
            int len, cap;
            bool ok;

            def __init() -> this
            {
                this.len = 0;
                this.cap = 256;
                this.ok = true;
                this.mem = (byte*)fmalloc((u64)this.cap);
                if (this.mem == (byte*)0)
                {
                    this.ok = false;
                    this.cap = 0;
                }
                else
                {
                    this.mem[0] = (byte)0;
                };
                return this;
            };

            def __expr() -> Buf*
            {
                return this;
            };

            def __exit() -> void
            {
                if (this.mem != (byte*)0) { ffree(this.mem); };
                this.mem = (byte*)0;
                this.len = 0;
                this.cap = 0;
                return;
            };

            def reserve(int extra) -> bool
            {
                if (!this.ok) { return false; };
                int need = this.len + extra + 1;
                if (need <= this.cap) { return true; };
                int nc = this.cap;
                if (nc < 256) { nc = 256; };
                while (nc < need) { nc = nc * 2; };
                u64 np;
                if (this.mem == (byte*)0)
                {
                    np = (u64)fmalloc((u64)nc);
                }
                else
                {
                    np = frealloc((u64)this.mem, (size_t)nc);
                };
                if (np == (u64)0)
                {
                    this.ok = false;
                    return false;
                };
                this.mem = (byte*)np;
                this.cap = nc;
                return true;
            };

            def put(int b) -> void
            {
                if (!this.reserve(1)) { return; };
                this.mem[this.len] = (byte)b;
                this.len++;
                this.mem[this.len] = (byte)0;
                return;
            };

            // s must not point into this buffer
            def put_n(byte* s, int n) -> void
            {
                if (n <= 0) { return; };
                if (!this.reserve(n)) { return; };
                int i;
                while (i < n)
                {
                    this.mem[this.len + i] = s[i];
                    i++;
                };
                this.len = this.len + n;
                this.mem[this.len] = (byte)0;
                return;
            };

            def put_str(byte* s) -> void
            {
                this.put_n(s, pp_cstrlen(s));
                return;
            };

            def put_int(int v) -> void
            {
                byte[16] tmp = noinit;
                int n, k;
                if (v < 0)
                {
                    this.put(45);
                    v = 0 - v;
                };
                if (v == 0)
                {
                    this.put(48);
                    return;
                };
                while (v > 0)
                {
                    tmp[n] = (byte)(48 + v % 10);
                    v = v / 10;
                    n++;
                };
                k = n;
                while (k > 0)
                {
                    k--;
                    this.put((int)tmp[k]);
                };
                return;
            };

            def clear() -> void
            {
                this.len = 0;
                if (this.mem != (byte*)0) { this.mem[0] = (byte)0; };
                return;
            };

            def pop() -> void
            {
                if (this.len > 0)
                {
                    this.len--;
                    this.mem[this.len] = (byte)0;
                };
                return;
            };

            // str.rstrip()
            def rstrip_ws() -> void
            {
                if (this.mem == (byte*)0) { return; };
                int w;
                while (this.len > 0)
                {
                    w = pp_ws_back(this.mem, 0, this.len);
                    if (w == 0) { break; };
                    this.len = this.len - w;
                };
                this.mem[this.len] = (byte)0;
                return;
            };

            // FXPreprocessor._strip_comments. Appends the stripped text of c[0, n).
            def put_stripped(byte* c, int n) -> void
            {
                int i, ch, string_char;
                bool in_string = false;
                while (i < n)
                {
                    ch = (int)c[i];
                    if (in_string)
                    {
                        this.put(ch);
                        if (ch == 92 & i + 1 < n)
                        {
                            i++;
                            this.put((int)c[i]);
                        }
                        elif (ch == string_char)
                        {
                            in_string = false;
                        };
                        i++;
                        continue;
                    };

                    if (ch == 34 | ch == 39)
                    {
                        in_string = true;
                        string_char = ch;
                        this.put(ch);
                        i++;
                        continue;
                    };

                    if (i + 2 < n)
                    {
                        if (ch == 47 & c[i + 1] == 47 & c[i + 2] == 47)
                        {
                            i = i + 3;
                            while (i < n)
                            {
                                if (i + 2 < n)
                                {
                                    if (c[i] == 47 & c[i + 1] == 47 & c[i + 2] == 47)
                                    {
                                        i = i + 3;
                                        break;
                                    };
                                };
                                if (c[i] == 10) { this.put(10); };
                                i++;
                            };
                            continue;
                        };
                    };

                    if (i + 1 < n)
                    {
                        if (ch == 47 & c[i + 1] == 47)
                        {
                            while (i < n)
                            {
                                if (c[i] == 10) { break; };
                                i++;
                            };
                            continue;
                        };
                    };

                    this.put(ch);
                    i++;
                };
                return;
            };

            // re.sub(r'\b' + re.escape(pat) + r'\b', rep, src), literal replacement text
            def put_replaced_word(byte* src, int sn, byte* pat, int pn, byte* rep, int rn) -> void
            {
                int i;
                bool hit;
                while (i < sn)
                {
                    hit = false;
                    if (i + pn <= sn)
                    {
                        if (pp_eq(src + i, pat, pn))
                        {
                            if (pp_boundary(src, sn, i))
                            {
                                if (pp_boundary(src, sn, i + pn)) { hit = true; };
                            };
                        };
                    };
                    if (hit)
                    {
                        this.put_n(rep, rn);
                        i = i + pn;
                    }
                    else
                    {
                        this.put((int)src[i]);
                        i++;
                    };
                };
                return;
            };

            // Replaces the content with a source file read the way
            // _read_source_file does: UTF-8 with BOM removed, invalid sequences
            // replaced by U+FFFD, CRLF and CR translated to LF.
            // Returns -1 when the file cannot be read, 1 when replacements were
            // made, 0 otherwise.
            def load_file(byte* path) -> int
            {
                void* f = fopen(path, g"rb\0");
                if (f == (void*)0) { return -1; };

                fseek(f, 0, SEEK_END);
                int size = ftell(f);
                fseek(f, 0, SEEK_SET);
                if (size < 0)
                {
                    fclose(f);
                    return -1;
                };

                byte* raw = (byte*)fmalloc((u64)size + (u64)1);
                if (raw == (byte*)0)
                {
                    fclose(f);
                    return -1;
                };
                int got = fread(raw, 1, size, f);
                fclose(f);
                if (got < 0)
                {
                    ffree(raw);
                    return -1;
                };

                this.clear();
                int i, bad, c, need, lo, hi, k, b1;
                if (got >= 3)
                {
                    if (raw[0] == 0xEF & raw[1] == 0xBB & raw[2] == 0xBF) { i = 3; };
                };

                while (i < got)
                {
                    c = (int)raw[i];
                    if (c < 0x80)
                    {
                        if (c == 13)
                        {
                            this.put(10);
                            if (pp_at(raw, got, i + 1) == 10) { i++; };
                        }
                        else
                        {
                            this.put(c);
                        };
                        i++;
                        continue;
                    };

                    need = 0;
                    lo = 0x80;
                    hi = 0xBF;
                    if (c >= 0xC2 & c <= 0xDF) { need = 1; }
                    elif (c == 0xE0) { need = 2; lo = 0xA0; }
                    elif (c >= 0xE1 & c <= 0xEC) { need = 2; }
                    elif (c == 0xED) { need = 2; hi = 0x9F; }
                    elif (c >= 0xEE & c <= 0xEF) { need = 2; }
                    elif (c == 0xF0) { need = 3; lo = 0x90; }
                    elif (c >= 0xF1 & c <= 0xF3) { need = 3; }
                    elif (c == 0xF4) { need = 3; hi = 0x8F; };

                    if (need == 0)
                    {
                        this.put(0xEF);
                        this.put(0xBF);
                        this.put(0xBD);
                        bad = 1;
                        i++;
                        continue;
                    };

                    k = 1;
                    while (k <= need)
                    {
                        b1 = pp_at(raw, got, i + k);
                        if (b1 < lo | b1 > hi) { break; };
                        lo = 0x80;
                        hi = 0xBF;
                        k++;
                    };

                    if (k > need)
                    {
                        this.put_n(raw + i, need + 1);
                        i = i + need + 1;
                    }
                    else
                    {
                        this.put(0xEF);
                        this.put(0xBF);
                        this.put(0xBD);
                        bad = 1;
                        i = i + k;
                    };
                };

                ffree(raw);
                return bad;
            };
        };

        // ===== GROWABLE INT ARRAY =====

        object IntVec
        {
            int* arr;
            int len, cap;
            bool ok;

            def __init() -> this
            {
                this.len = 0;
                this.cap = 64;
                this.ok = true;
                this.arr = (int*)fmalloc((u64)this.cap * (u64)(sizeof(int) / 8));
                if (this.arr == (int*)0)
                {
                    this.ok = false;
                    this.cap = 0;
                };
                return this;
            };

            def __expr() -> IntVec*
            {
                return this;
            };

            def __exit() -> void
            {
                if (this.arr != (int*)0) { ffree((byte*)this.arr); };
                this.arr = (int*)0;
                this.len = 0;
                this.cap = 0;
                return;
            };

            def push(int v) -> void
            {
                if (!this.ok) { return; };
                if (this.len >= this.cap)
                {
                    int nc = this.cap * 2;
                    if (nc < 64) { nc = 64; };
                    u64 np;
                    if (this.arr == (int*)0)
                    {
                        np = (u64)fmalloc((u64)nc * (u64)(sizeof(int) / 8));
                    }
                    else
                    {
                        np = frealloc((u64)this.arr, (size_t)((u64)nc * (u64)(sizeof(int) / 8)));
                    };
                    if (np == (u64)0)
                    {
                        this.ok = false;
                        return;
                    };
                    this.arr = (int*)np;
                    this.cap = nc;
                };
                this.arr[this.len] = v;
                this.len++;
                return;
            };

            def pop() -> void
            {
                if (this.len > 0) { this.len--; };
                return;
            };

            def clear() -> void
            {
                this.len = 0;
                return;
            };
        };

        // ===== STRING KEYED TABLE =====
        // Open addressing over entries of FLUX_PP_STRIDE ints:
        //   [0] key offset in keys   [1] key length
        //   [2] value offset in vals [3] value length
        //   [4] params offset in vals (psub parameters, each null terminated)
        //   [5] params byte length   [6] params count   [7] unused

        object SymTab
        {
            int* slots;
            int* ents;
            int slot_cap, ent_cap, count;
            Buf keys;
            Buf vals;
            bool ok;

            def __init() -> this
            {
                this.keys.__init();
                this.vals.__init();
                this.count = 0;
                this.ok = true;
                this.slot_cap = 256;
                this.ent_cap = 64;
                this.slots = (int*)fmalloc((u64)this.slot_cap * (u64)(sizeof(int) / 8));
                this.ents = (int*)fmalloc((u64)this.ent_cap * (u64)FLUX_PP_STRIDE * (u64)(sizeof(int) / 8));
                if (this.slots == (int*)0 | this.ents == (int*)0)
                {
                    this.ok = false;
                    return this;
                };
                int z;
                while (z < this.slot_cap)
                {
                    this.slots[z] = 0;
                    z++;
                };
                return this;
            };

            def __expr() -> SymTab*
            {
                return this;
            };

            def __exit() -> void
            {
                if (this.slots != (int*)0) { ffree((byte*)this.slots); };
                if (this.ents != (int*)0) { ffree((byte*)this.ents); };
                this.slots = (int*)0;
                this.ents = (int*)0;
                this.keys.__exit();
                this.vals.__exit();
                return;
            };

            // Entry index of s[0, n), or -1
            def find(byte* s, int n) -> int
            {
                if (!this.ok) { return -1; };
                u64 h = pp_hash(s, n);
                int idx = (int)(h % (u64)this.slot_cap);
                int e, base, j;
                bool same;
                while (true)
                {
                    e = this.slots[idx];
                    if (e == 0) { return -1; };
                    e = e - 1;
                    base = e * FLUX_PP_STRIDE;
                    if (this.ents[base + 1] == n)
                    {
                        same = true;
                        j = 0;
                        while (j < n)
                        {
                            if (this.keys.mem[this.ents[base] + j] != s[j])
                            {
                                same = false;
                                break;
                            };
                            j++;
                        };
                        if (same) { return e; };
                    };
                    idx++;
                    if (idx >= this.slot_cap) { idx = 0; };
                };
                return -1;
            };

            // Links entry e into slots
            def place(int e) -> void
            {
                int base = e * FLUX_PP_STRIDE;
                u64 h = pp_hash(this.keys.mem + this.ents[base], this.ents[base + 1]);
                int idx = (int)(h % (u64)this.slot_cap);
                while (this.slots[idx] != 0)
                {
                    idx++;
                    if (idx >= this.slot_cap) { idx = 0; };
                };
                this.slots[idx] = e + 1;
                return;
            };

            def grow_slots() -> bool
            {
                int nc = this.slot_cap * 2;
                int* ns = (int*)fmalloc((u64)nc * (u64)(sizeof(int) / 8));
                if (ns == (int*)0)
                {
                    this.ok = false;
                    return false;
                };
                int z, e;
                while (z < nc)
                {
                    ns[z] = 0;
                    z++;
                };
                ffree((byte*)this.slots);
                this.slots = ns;
                this.slot_cap = nc;
                while (e < this.count)
                {
                    this.place(e);
                    e++;
                };
                return true;
            };

            def grow_ents() -> bool
            {
                int nc = this.ent_cap * 2;
                u64 np = frealloc((u64)this.ents, (size_t)((u64)nc * (u64)FLUX_PP_STRIDE * (u64)(sizeof(int) / 8)));
                if (np == (u64)0)
                {
                    this.ok = false;
                    return false;
                };
                this.ents = (int*)np;
                this.ent_cap = nc;
                return true;
            };

            // Entry index of s[0, n), created when missing. -1 on allocation failure.
            // s must not point into this table.
            def intern(byte* s, int n) -> int
            {
                int e = this.find(s, n);
                if (e >= 0) { return e; };
                if (!this.ok) { return -1; };
                if (this.count + 1 > this.ent_cap)
                {
                    if (!this.grow_ents()) { return -1; };
                };
                if ((this.count + 1) * 2 > this.slot_cap)
                {
                    if (!this.grow_slots()) { return -1; };
                };
                e = this.count;
                int base = e * FLUX_PP_STRIDE;
                this.ents[base] = this.keys.len;
                this.ents[base + 1] = n;
                this.ents[base + 2] = 0;
                this.ents[base + 3] = 0;
                this.ents[base + 4] = 0;
                this.ents[base + 5] = 0;
                this.ents[base + 6] = 0;
                this.ents[base + 7] = 0;
                this.keys.put_n(s, n);
                this.keys.put(0);
                this.count++;
                this.place(e);
                return e;
            };

            def set_val(int e, byte* v, int n) -> void
            {
                int base = e * FLUX_PP_STRIDE;
                this.ents[base + 2] = this.vals.len;
                this.ents[base + 3] = n;
                this.vals.put_n(v, n);
                this.vals.put(0);
                return;
            };

            // pcount parameter names stored as consecutive null terminated strings,
            // plen bytes in total including the terminators
            def set_params(int e, byte* p, int plen, int pcount) -> void
            {
                int base = e * FLUX_PP_STRIDE;
                this.ents[base + 4] = this.vals.len;
                this.ents[base + 5] = plen;
                this.ents[base + 6] = pcount;
                this.vals.put_n(p, plen);
                return;
            };

            def val_ptr(int e) -> byte*
            {
                return this.vals.mem + this.ents[e * FLUX_PP_STRIDE + 2];
            };

            def val_len(int e) -> int
            {
                return this.ents[e * FLUX_PP_STRIDE + 3];
            };

            def par_ptr(int e) -> byte*
            {
                return this.vals.mem + this.ents[e * FLUX_PP_STRIDE + 4];
            };

            def par_count(int e) -> int
            {
                return this.ents[e * FLUX_PP_STRIDE + 6];
            };
        };

        // ===== PREPROCESSOR =====

        object Preprocessor
        {
            bool verbose;

            Buf pool;       // persistent null terminated strings (paths), addressed by offset
            Buf outb;       // output lines joined with LF
            Buf errb;       // error message
            Buf srcpath;
            Buf fbuf;
            Buf sc;         // _substitute_constants result
            Buf ma;         // macro expansion, current text
            Buf mc;         // macro expansion, pass output
            Buf x1;
            Buf x2;
            Buf psb;        // #psub definition being collected
            Buf pb;         // #psub parameter names
            Buf tmp;
            Buf passb;
            Buf rbuf;       // last resolved path
            Buf jb;         // last joined path
            Buf js;         // json string value
            Buf jv;         // package entrypoint

            IntVec files;       // pool offset of every processed file, index is the file id
            IntVec lib_dirs;    // pool offsets
            IntVec dir_stack;   // pool offsets
            IntVec map_file;    // line_map: file id per output line
            IntVec map_line;    // line_map: local line number per output line
            IntVec aoff;
            IntVec alen;

            SymTab processed;
            SymTab consts;
            SymTab psubs;

            int line_count, cur_file, cur_lineno, err_kind;
            int srcdir_off, cwd_off, root_dir_off;
            int pc_off, pc_len;
            bool pc_inv;
            byte* pathbuf;
            byte* sub_ptr;
            byte* ex_ptr;
            int sub_len, ex_len;

            def __init(byte* source_file) -> this
            {
                this.pool.__init();
                this.outb.__init();
                this.errb.__init();
                this.srcpath.__init();
                this.fbuf.__init();
                this.sc.__init();
                this.ma.__init();
                this.mc.__init();
                this.x1.__init();
                this.x2.__init();
                this.psb.__init();
                this.pb.__init();
                this.tmp.__init();
                this.passb.__init();
                this.rbuf.__init();
                this.jb.__init();
                this.js.__init();
                this.jv.__init();
                this.files.__init();
                this.lib_dirs.__init();
                this.dir_stack.__init();
                this.map_file.__init();
                this.map_line.__init();
                this.aoff.__init();
                this.alen.__init();
                this.processed.__init();
                this.consts.__init();
                this.psubs.__init();

                this.verbose = false;
                this.line_count = 0;
                this.cur_file = -1;
                this.cur_lineno = 0;
                this.err_kind = 0;
                this.root_dir_off = -1;
                this.srcdir_off = -1;
                this.cwd_off = -1;
                this.sub_ptr = (byte*)0;
                this.ex_ptr = (byte*)0;
                this.sub_len = 0;
                this.ex_len = 0;

                this.srcpath.put_str(source_file);
                this.pathbuf = (byte*)fmalloc((u64)FLUX_PP_PATH_MAX);
                if (this.pathbuf == (byte*)0)
                {
                    this.err_kind = PPError.ALLOC;
                    return this;
                };

                if (this.realpath_into(g".\0"))
                {
                    this.cwd_off = this.pool_add(this.rbuf.mem, this.rbuf.len);
                }
                else
                {
                    this.cwd_off = this.pool_add(g".\0", 1);
                };
                this.srcdir_off = this.cwd_off;
                return this;
            };

            def __expr() -> Preprocessor*
            {
                return this;
            };

            def __exit() -> void
            {
                if (this.pathbuf != (byte*)0) { ffree(this.pathbuf); };
                this.pathbuf = (byte*)0;
                this.pool.__exit();
                this.outb.__exit();
                this.errb.__exit();
                this.srcpath.__exit();
                this.fbuf.__exit();
                this.sc.__exit();
                this.ma.__exit();
                this.mc.__exit();
                this.x1.__exit();
                this.x2.__exit();
                this.psb.__exit();
                this.pb.__exit();
                this.tmp.__exit();
                this.passb.__exit();
                this.rbuf.__exit();
                this.jb.__exit();
                this.js.__exit();
                this.jv.__exit();
                this.files.__exit();
                this.lib_dirs.__exit();
                this.dir_stack.__exit();
                this.map_file.__exit();
                this.map_line.__exit();
                this.aoff.__exit();
                this.alen.__exit();
                this.processed.__exit();
                this.consts.__exit();
                this.psubs.__exit();
                return;
            };

            // ===== ACCESSORS =====

            def text_ptr() -> byte*
            {
                return this.outb.mem;
            };

            def text_len() -> int
            {
                return this.outb.len;
            };

            def err_text() -> byte*
            {
                return this.errb.mem;
            };

            // Resolved path of the file output line i came from
            def map_path(int i) -> byte*
            {
                return this.pool.mem + this.files.arr[this.map_file.arr[i]];
            };

            // Local line number of output line i inside map_path(i)
            def map_lineno(int i) -> int
            {
                return this.map_line.arr[i];
            };

            // Number of files processed
            def file_count() -> int
            {
                return this.processed.count;
            };

            // ===== CONFIGURATION =====

            def set_srcdir(byte* dir) -> void
            {
                this.srcdir_off = this.pool_add(dir, pp_cstrlen(dir));
                return;
            };

            // compiler_constants[name] = value
            def define(byte* name, byte* value) -> void
            {
                int e = this.consts.intern(name, pp_cstrlen(name));
                if (e < 0) { return; };
                this.consts.set_val(e, value, pp_cstrlen(value));
                return;
            };

            // fmacros.build_compiler_macros with the host as target and the
            // flux_config.cfg defaults (default_byte_width 8, debug and
            // optimization_level unset).
            def add_default_macros() -> void
            {
                this.define(g"__FLUX__\0", g"1\0");
                this.define(g"__FLUX_MAJOR__\0", g"1\0");
                this.define(g"__FLUX_MINOR__\0", g"0\0");
                this.define(g"__FLUX_PATCH__\0", g"0\0");
                this.define(g"__FLUX_VERSION__\0", g"1\0");
                this.define(g"__LLVM__\0", g"1\0");

                this.define(g"__ARCH_X86__\0", g"0\0");
                this.define(g"__ARCH_X86_64__\0", g"0\0");
                this.define(g"__ARCH_ARM__\0", g"0\0");
                this.define(g"__ARCH_ARM64__\0", g"0\0");
                this.define(g"__ARCH_RISCV__\0", g"0\0");

                this.define(g"__WINDOWS__\0", g"0\0");
                this.define(g"__LINUX__\0", g"0\0");
                this.define(g"__MACOS__\0", g"0\0");
                this.define(g"__POSIX__\0", g"0\0");

                this.define(g"__LITTLE_ENDIAN__\0", g"0\0");
                this.define(g"__BIG_ENDIAN__\0", g"1\0");
                this.define(g"__SIZEOF_PTR__\0", g"8\0");
                this.define(g"__SIZEOF_INT__\0", g"4\0");
                this.define(g"__SIZEOF_LONG__\0", g"8\0");
                this.define(g"__BYTE_WIDTH__\0", g"8\0");

                this.define(g"__DEBUG__\0", g"0\0");
                this.define(g"__RELEASE__\0", g"0\0");
                this.define(g"__OPTIMIZE__\0", g"0\0");

                #ifdef __WINDOWS__
                this.define(g"__WINDOWS__\0", g"1\0");
                this.define(g"__WIN32__\0", g"1\0");
                    #ifdef __ARCH_X86_64__
                    this.define(g"__WIN64__\0", g"1\0");
                    #else
                    this.define(g"__WIN64__\0", g"0\0");
                    #endif;
                #elif __MACOS__
                this.define(g"__MACOS__\0", g"1\0");
                this.define(g"__APPLE__\0", g"1\0");
                this.define(g"__MACH__\0", g"1\0");
                this.define(g"__POSIX__\0", g"1\0");
                #else
                this.define(g"__LINUX__\0", g"1\0");
                this.define(g"__UNIX__\0", g"1\0");
                this.define(g"__POSIX__\0", g"1\0");
                this.define(g"__gnu_linux__\0", g"1\0");
                #endif;

                #ifdef __ARCH_X86_64__
                this.define(g"__ARCH_X86_64__\0", g"1\0");
                this.define(g"__x86_64__\0", g"1\0");
                this.define(g"__amd64__\0", g"1\0");
                #elif __ARCH_X86__
                this.define(g"__ARCH_X86__\0", g"1\0");
                this.define(g"__i386__\0", g"1\0");
                this.define(g"__i686__\0", g"1\0");
                #elif __ARCH_ARM64__
                this.define(g"__ARCH_ARM64__\0", g"1\0");
                this.define(g"__arm64__\0", g"1\0");
                this.define(g"__aarch64__\0", g"1\0");
                #endif;
                return;
            };

            // ===== STRINGS, ERRORS, OUTPUT =====

            // Appends s[0, n) to the pool as a null terminated string, returns its offset.
            // s must not point into the pool.
            def pool_add(byte* s, int n) -> int
            {
                int off = this.pool.len;
                this.pool.put_n(s, n);
                this.pool.put(0);
                return off;
            };

            def e_begin(int kind) -> void
            {
                this.err_kind = kind;
                this.errb.clear();
                return;
            };

            // Prints a + s[0, n) + b on one line
            def vline(byte* a, byte* s, int n, byte* b) -> void
            {
                this.tmp.clear();
                this.tmp.put_str(a);
                this.tmp.put_n(s, n);
                this.tmp.put_str(b);
                standard::io::console::println(this.tmp.mem);
                return;
            };

            // Appends a line to the output together with its line_map entry
            def emit(byte* s, int n, int lineno) -> void
            {
                if (this.line_count > 0) { this.outb.put(10); };
                this.outb.put_n(s, n);
                this.map_file.push(this.cur_file);
                this.map_line.push(lineno);
                this.line_count++;
                return;
            };

            def emit_blank(int lineno) -> void
            {
                this.emit(g"\0", 0, lineno);
                return;
            };

            def alloc_ok() -> bool
            {
                if (!this.pool.ok | !this.outb.ok | !this.errb.ok | !this.fbuf.ok | !this.sc.ok) { return false; };
                if (!this.ma.ok | !this.mc.ok | !this.x1.ok | !this.x2.ok | !this.psb.ok) { return false; };
                if (!this.pb.ok | !this.tmp.ok | !this.passb.ok | !this.rbuf.ok | !this.jb.ok) { return false; };
                if (!this.js.ok | !this.jv.ok | !this.files.ok | !this.lib_dirs.ok | !this.dir_stack.ok) { return false; };
                if (!this.map_file.ok | !this.map_line.ok | !this.aoff.ok | !this.alen.ok) { return false; };
                if (!this.processed.ok | !this.consts.ok | !this.psubs.ok) { return false; };
                return true;
            };

            // ===== PATHS =====

            // Path.resolve() of p into rbuf. False when p does not exist.
            #ifdef __WINDOWS__
            def realpath_into(byte* p) -> bool
            {
                byte* r = _fullpath(this.pathbuf, p, (size_t)FLUX_PP_PATH_MAX);
                if (r == (byte*)0) { return false; };
                this.rbuf.clear();
                this.rbuf.put_str(this.pathbuf);
                return true;
            };
            #else
            def realpath_into(byte* p) -> bool
            {
                byte* r = realpath(p, this.pathbuf);
                if (r == (byte*)0) { return false; };
                this.rbuf.clear();
                this.rbuf.put_str(this.pathbuf);
                return true;
            };
            #endif;

            // Path(base) / rel into jb
            def join_to(byte* base, int bn, byte* rel, int rn) -> void
            {
                this.jb.clear();
                if (pp_is_abs(rel, rn))
                {
                    this.jb.put_n(rel, rn);
                    return;
                };
                this.jb.put_n(base, bn);
                if (bn > 0)
                {
                    if ((int)base[bn - 1] != FLUX_PP_SEP) { this.jb.put(FLUX_PP_SEP); };
                };
                this.jb.put_n(rel, rn);
                return;
            };

            // (base / rel).exists() then resolve into rbuf
            def try_candidate(byte* base, int bn, byte* rel, int rn) -> bool
            {
                this.join_to(base, bn, rel, rn);
                if (!pp_exists(this.jb.mem)) { return false; };
                return this.realpath_into(this.jb.mem);
            };

            // FXPreprocessor._resolve_path_local
            def resolve_local(byte* fp, int n) -> bool
            {
                byte* d;
                int k;
                if (this.dir_stack.len > 0)
                {
                    d = this.pool.mem + this.dir_stack.arr[this.dir_stack.len - 1];
                    if (this.try_candidate(d, pp_cstrlen(d), fp, n)) { return true; };
                };

                d = this.pool.mem + this.root_dir_off;
                if (this.try_candidate(d, pp_cstrlen(d), fp, n)) { return true; };

                d = this.pool.mem + this.cwd_off;
                if (this.try_candidate(d, pp_cstrlen(d), fp, n)) { return true; };

                while (k < this.lib_dirs.len)
                {
                    d = this.pool.mem + this.lib_dirs.arr[k];
                    if (this.try_candidate(d, pp_cstrlen(d), fp, n)) { return true; };
                    k++;
                };
                return false;
            };

            // FXPreprocessor._resolve_path_stdlib: srcdir/src/stdlib and its
            // runtime, functions, builtins and utility folders
            def resolve_stdlib(byte* fp, int n) -> bool
            {
                byte* sd = this.pool.mem + this.srcdir_off;
                int w;
                while (w < 5)
                {
                    this.x1.clear();
                    this.x1.put_str(sd);
                    this.x1.put(FLUX_PP_SEP);
                    this.x1.put_str(g"src\0");
                    this.x1.put(FLUX_PP_SEP);
                    this.x1.put_str(g"stdlib\0");
                    if (w > 0)
                    {
                        this.x1.put(FLUX_PP_SEP);
                        if (w == 1) { this.x1.put_str(g"runtime\0"); }
                        elif (w == 2) { this.x1.put_str(g"functions\0"); }
                        elif (w == 3) { this.x1.put_str(g"builtins\0"); }
                        else { this.x1.put_str(g"utility\0"); };
                    };
                    if (this.try_candidate(this.x1.mem, this.x1.len, fp, n)) { return true; };
                    w++;
                };
                return false;
            };

            // FXPreprocessor._resolve_path
            def resolve_default(byte* fp, int n) -> bool
            {
                if (pp_exists(fp))
                {
                    if (this.realpath_into(fp)) { return true; };
                };
                if (this.resolve_local(fp, n)) { return true; };
                return this.resolve_stdlib(fp, n);
            };

            // ===== #package =====

            def json_ws(byte* t, int n, int p) -> int
            {
                int c = pp_at(t, n, p);
                while (c == 32 | c == 9 | c == 10 | c == 13)
                {
                    p++;
                    c = pp_at(t, n, p);
                };
                return p;
            };

            def json_hex4(byte* t, int n, int p) -> int
            {
                int v, k, c;
                while (k < 4)
                {
                    c = pp_at(t, n, p + k);
                    v = v * 16;
                    if (c >= '0' & c <= '9') { v = v + (c - 48); }
                    elif (c >= 'A' & c <= 'F') { v = v + (c - 55); }
                    elif (c >= 'a' & c <= 'f') { v = v + (c - 87); }
                    else { return -1; };
                    k++;
                };
                return v;
            };

            // Reads the JSON string whose opening quote is at t[p] into js.
            // Returns the position after the closing quote, or -1.
            def json_string(byte* t, int n, int p) -> int
            {
                this.js.clear();
                if (pp_at(t, n, p) != 34) { return -1; };
                p++;
                int c, h, lo;
                while (p < n)
                {
                    c = (int)t[p];
                    if (c == 34) { return p + 1; };
                    if (c == 92)
                    {
                        p++;
                        c = pp_at(t, n, p);
                        if (c == 'n') { this.js.put(10); }
                        elif (c == 't') { this.js.put(9); }
                        elif (c == 'r') { this.js.put(13); }
                        elif (c == 'b') { this.js.put(8); }
                        elif (c == 'f') { this.js.put(12); }
                        elif (c == 'u')
                        {
                            h = this.json_hex4(t, n, p + 1);
                            if (h < 0) { return -1; };
                            p = p + 4;
                            if (h >= 0xD800 & h <= 0xDBFF)
                            {
                                if (pp_at(t, n, p + 1) == 92 & pp_at(t, n, p + 2) == 'u')
                                {
                                    lo = this.json_hex4(t, n, p + 3);
                                    if (lo >= 0xDC00 & lo <= 0xDFFF)
                                    {
                                        h = 0x10000 + (h - 0xD800) * 0x400 + (lo - 0xDC00);
                                        p = p + 6;
                                    };
                                };
                            };
                            if (h < 0x80) { this.js.put(h); }
                            elif (h < 0x800)
                            {
                                this.js.put(0xC0 + h / 64);
                                this.js.put(0x80 + h % 64);
                            }
                            elif (h < 0x10000)
                            {
                                this.js.put(0xE0 + h / 4096);
                                this.js.put(0x80 + (h / 64) % 64);
                                this.js.put(0x80 + h % 64);
                            }
                            else
                            {
                                this.js.put(0xF0 + h / 262144);
                                this.js.put(0x80 + (h / 4096) % 64);
                                this.js.put(0x80 + (h / 64) % 64);
                                this.js.put(0x80 + h % 64);
                            };
                        }
                        elif (c < 0) { return -1; }
                        else { this.js.put(c); };
                        p++;
                        continue;
                    };
                    this.js.put(c);
                    p++;
                };
                return -1;
            };

            // Position after the JSON value starting at t[p], or -1
            def json_skip(byte* t, int n, int p) -> int
            {
                p = this.json_ws(t, n, p);
                int c = pp_at(t, n, p);
                int depth;
                if (c == 34) { return this.json_string(t, n, p); };
                if (c == '{' | c == '[')
                {
                    depth = 0;
                    while (p < n)
                    {
                        c = (int)t[p];
                        if (c == 34)
                        {
                            p = this.json_string(t, n, p);
                            if (p < 0) { return -1; };
                            continue;
                        };
                        if (c == '{' | c == '[') { depth++; };
                        if (c == '}' | c == ']')
                        {
                            depth--;
                            if (depth == 0) { return p + 1; };
                        };
                        p++;
                    };
                    return -1;
                };
                while (p < n)
                {
                    c = (int)t[p];
                    if (c == ',' | c == '}' | c == ']' | c == 32 | c == 9 | c == 10 | c == 13) { break; };
                    p++;
                };
                return p;
            };

            // Scans the JSON object at t[p] for the keys "entries" and "entrypoint".
            // Sets jv to the string value of "entrypoint" when present as a string.
            // want_entries = 1 also returns the offset of the "entries" value in this.pc_off
            // (-1 when absent). Returns 0 on a malformed object.
            def json_object(byte* t, int n, int p, int want_entries) -> int
            {
                int vs, nx;
                bool is_ep, is_en;
                this.jv.clear();
                this.pc_off = -1;
                p = this.json_ws(t, n, p);
                if (pp_at(t, n, p) != '{') { return 0; };
                p++;
                while (true)
                {
                    p = this.json_ws(t, n, p);
                    if (pp_at(t, n, p) == '}') { return 1; };
                    if (pp_at(t, n, p) == ',')
                    {
                        p++;
                        continue;
                    };
                    p = this.json_string(t, n, p);
                    if (p < 0) { return 0; };
                    is_ep = this.js.len == 10 & pp_eq(this.js.mem, g"entrypoint\0", 10);
                    is_en = this.js.len == 7 & pp_eq(this.js.mem, g"entries\0", 7);
                    p = this.json_ws(t, n, p);
                    if (pp_at(t, n, p) != ':') { return 0; };
                    p = this.json_ws(t, n, p + 1);
                    vs = p;
                    if (is_ep)
                    {
                        this.jv.clear();
                        if (pp_at(t, n, p) == 34)
                        {
                            nx = this.json_string(t, n, p);
                            if (nx < 0) { return 0; };
                            this.jv.put_n(this.js.mem, this.js.len);
                            p = nx;
                            continue;
                        };
                    };
                    if (is_en)
                    {
                        this.pc_off = vs;
                    };
                    p = this.json_skip(t, n, p);
                    if (p < 0) { return 0; };
                };
                return 0;
            };

            // FXPreprocessor._process_package. name is name_len bytes at text + name_off.
            def process_package(byte* text, int name_off, int name_len) -> bool
            {
                Buf man();
                defer man.__exit();
                int pk, ep_off, en_off, ok2, w;

                // cwd/.fpm/packages/<name> into x1, packages dir length in w
                byte* cwd = this.pool.mem + this.cwd_off;
                this.x1.clear();
                this.x1.put_str(cwd);
                this.x1.put(FLUX_PP_SEP);
                this.x1.put_str(g".fpm\0");
                this.x1.put(FLUX_PP_SEP);
                this.x1.put_str(g"packages\0");
                w = this.x1.len;
                this.x1.put(FLUX_PP_SEP);
                this.x1.put_n(text + name_off, name_len);

                this.x2.clear();
                this.x2.put_n(this.x1.mem, this.x1.len);
                this.x2.put(FLUX_PP_SEP);
                this.x2.put(46);
                if (!pp_exists(this.x2.mem))
                {
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' not found in \0");
                    this.errb.put_n(this.x1.mem, w);
                    return false;
                };

                this.x2.clear();
                this.x2.put_n(this.x1.mem, this.x1.len);
                this.x2.put(FLUX_PP_SEP);
                this.x2.put_str(g"package.json\0");
                if (!pp_exists(this.x2.mem))
                {
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' is missing package.json\0");
                    return false;
                };

                ok2 = man.load_file(this.x2.mem);
                if (ok2 < 0)
                {
                    this.e_begin(PPError.IO);
                    this.errb.put_str(g"[PREPROCESSOR] Could not read \0");
                    this.errb.put_n(this.x2.mem, this.x2.len);
                    return false;
                };

                // entries = manifest.get("entries", manifest)
                if (this.json_object(man.mem, man.len, 0, 1) == 0)
                {
                    this.e_begin(PPError.KEY);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' package.json is not a valid JSON object\0");
                    return false;
                };
                en_off = this.pc_off;
                if (en_off >= 0)
                {
                    if (this.json_object(man.mem, man.len, en_off, 0) == 0)
                    {
                        this.jv.clear();
                    };
                };

                if (this.jv.len == 0)
                {
                    this.e_begin(PPError.KEY);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' package.json has no 'entrypoint' field\0");
                    return false;
                };

                // (package_dir / entrypoint)
                this.join_to(this.x1.mem, this.x1.len, this.jv.mem, this.jv.len);
                if (!pp_exists(this.jb.mem))
                {
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' entrypoint '\0");
                    this.errb.put_n(this.jv.mem, this.jv.len);
                    this.errb.put_str(g"' not found\0");
                    return false;
                };
                if (!this.realpath_into(this.jb.mem))
                {
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' entrypoint '\0");
                    this.errb.put_n(this.jv.mem, this.jv.len);
                    this.errb.put_str(g"' not found\0");
                    return false;
                };

                if (this.processed.find(this.rbuf.mem, this.rbuf.len) >= 0) { return true; };

                if (this.verbose)
                {
                    this.tmp.clear();
                    this.tmp.put_str(g"[PREPROCESSOR] Package import: \0");
                    this.tmp.put_n(text + name_off, name_len);
                    this.tmp.put_str(g" -> \0");
                    this.tmp.put_n(this.jv.mem, this.jv.len);
                    standard::io::console::println(this.tmp.mem);
                };

                // The package directory is pushed so relative imports inside it resolve
                pk = this.pool_add(this.x1.mem, this.x1.len);
                this.dir_stack.push(pk);
                this.x2.clear();
                this.x2.put_n(this.rbuf.mem, this.rbuf.len);
                if (!this.process_file(this.x2.mem, this.x2.len, 1)) { return false; };
                this.dir_stack.pop();
                return true;
            };

            // ===== FILES =====

            // FXPreprocessor._process_file. resolver: 0 default, 1 local, 2 stdlib.
            // fp_in must not point into the pool.
            def process_file(byte* fp_in, int fp_n, int resolver) -> bool
            {
                Buf raw();
                Buf content();
                IntVec loff();
                IntVec llen();
                defer raw.__exit();
                defer content.__exit();
                defer loff.__exit();
                defer llen.__exit();
                LineList ll;

                int fp_off = this.pool.len;
                int k, c, rc, pos, e0, tl, q, lo, hi, ts, te, fid, path_off, dir_off, pl, prev_file, i;
                bool found;

                while (k < fp_n)
                {
                    c = (int)fp_in[k];
                    if (c == 92 | c == 47) { c = FLUX_PP_SEP; };
                    this.pool.put(c);
                    k++;
                };
                this.pool.put(0);

                if (resolver == 1) { found = this.resolve_local(this.pool.mem + fp_off, fp_n); }
                elif (resolver == 2) { found = this.resolve_stdlib(this.pool.mem + fp_off, fp_n); }
                else { found = this.resolve_default(this.pool.mem + fp_off, fp_n); };

                if (!found)
                {
                    if (resolver == 1)
                    {
                        if (this.resolve_stdlib(this.pool.mem + fp_off, fp_n))
                        {
                            this.vline(g"[PREPROCESSOR] Could not find local import: \0", this.pool.mem + fp_off, fp_n, g"\0");
                            this.vline(g"#import \"\0", this.pool.mem + fp_off, fp_n, g"\";\0");
                            standard::io::console::println(g"--------^\0");
                            this.vline(g"#import <\0", this.pool.mem + fp_off, fp_n, g">; // try this\0");
                        };
                    };
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"Could not find import: \0");
                    this.errb.put_n(this.pool.mem + fp_off, fp_n);
                    return false;
                };

                if (this.processed.find(this.rbuf.mem, this.rbuf.len) >= 0) { return true; };
                this.processed.intern(this.rbuf.mem, this.rbuf.len);
                fid = this.files.len;
                path_off = this.pool_add(this.rbuf.mem, this.rbuf.len);
                this.files.push(path_off);
                pl = pp_parent_len(this.rbuf.mem, this.rbuf.len);
                dir_off = this.pool_add(this.rbuf.mem, pl);

                if (this.verbose)
                {
                    this.vline(g"[PREPROCESSOR] Processing: \0", this.pool.mem + fp_off, fp_n, g"\0");
                };

                rc = raw.load_file(this.pool.mem + path_off);
                if (rc < 0)
                {
                    this.e_begin(PPError.IO);
                    this.errb.put_str(g"[PREPROCESSOR] Could not read file: \0");
                    this.errb.put_str(this.pool.mem + path_off);
                    return false;
                };
                if (rc == 1)
                {
                    this.vline(g"[PREPROCESSOR] WARNING: '\0", this.pool.mem + path_off, pp_cstrlen(this.pool.mem + path_off),
                               g"' contains invalid UTF-8 sequences. Replacement characters (U+FFFD) have been substituted. Save the file as UTF-8 to silence this warning.\0");
                };

                content.put_stripped(raw.mem, raw.len);
                if (!raw.ok | !content.ok | !this.alloc_ok())
                {
                    this.e_begin(PPError.ALLOC);
                    this.errb.put_str(g"[PREPROCESSOR] allocation failed\0");
                    return false;
                };

                while (pos < content.len)
                {
                    e0 = pp_eol(content.mem, content.len, pos, @tl);
                    loff.push(pos);
                    llen.push(e0 - pos);
                    pos = e0 + tl;
                };
                ll.text = content.mem;
                ll.off = loff.arr;
                ll.len = llen.arr;
                ll.n = loff.len;

                // Directives must end with a semicolon
                while (q < ll.n)
                {
                    lo = ll.off[q];
                    hi = lo + ll.len[q];
                    pp_trim(content.mem, @lo, @hi);
                    if (hi > lo)
                    {
                        if (pp_starts(content.mem, lo, hi, g"#import\0", 7) | pp_starts(content.mem, lo, hi, g"#package\0", 8)
                            | pp_starts(content.mem, lo, hi, g"#warn\0", 5) | pp_starts(content.mem, lo, hi, g"#stop\0", 5)
                            | pp_starts(content.mem, lo, hi, g"#def\0", 4) | pp_starts(content.mem, lo, hi, g"#dir\0", 4))
                        {
                            if (content.mem[hi - 1] != 59)
                            {
                                pp_next_tok(content.mem, hi, lo, @ts, @te);
                                this.e_begin(PPError.SYNTAX);
                                this.errb.put_str(g"[PREPROCESSOR] \0");
                                this.errb.put_n(content.mem + ts, te - ts);
                                this.errb.put_str(g" directive missing semicolon in \0");
                                this.errb.put_n(this.pool.mem + fp_off, fp_n);
                                this.errb.put_str(g" at line \0");
                                this.errb.put_int(q + 1);
                                return false;
                            };
                        };
                    };
                    q++;
                };

                prev_file = this.cur_file;
                this.cur_file = fid;
                this.dir_stack.push(dir_off);
                i = 0;
                while (i < ll.n)
                {
                    this.cur_lineno = i + 1;
                    i = this.process_line(@ll, i);
                    if (i < 0) { return false; };
                };
                this.dir_stack.pop();
                this.cur_file = prev_file;
                return true;
            };

            // ===== LINES =====

            // FXPreprocessor._process_line. Returns the next line index, or -1 on error.
            def process_line(LineList* ll, int i) -> int
            {
                byte* text = ll.text;
                int lo = ll.off[i];
                int hi = lo + ll.len[i];
                int s = lo;
                int e = hi;
                int a, b, ts, te, nx, semi, q1, q2, j, k, np, w, pl, tcount;
                int name_off, name_len, paren_open, paren_close, body_off, body_len;
                bool more, have;
                int ent;

                pp_trim(text, @s, @e);

                if (s >= e)
                {
                    this.emit_blank(this.cur_lineno);
                    return i + 1;
                };

                // #dir
                if (pp_starts(text, s, e, g"#dir\0", 4))
                {
                    if (text[e - 1] != 59)
                    {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #dir directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        return -1;
                    };
                    q1 = pp_find(text, lo, hi, 34);
                    if (q1 != -1)
                    {
                        q2 = pp_find(text, q1 + 1, hi, 34);
                        if (q2 != -1)
                        {
                            this.tmp.clear();
                            j = q1 + 1;
                            while (j < q2)
                            {
                                k = (int)text[j];
                                if (k == 92) { k = 47; };
                                this.tmp.put(k);
                                j++;
                            };
                            have = false;
                            k = 0;
                            while (k < this.lib_dirs.len)
                            {
                                if (pp_cstrlen(this.pool.mem + this.lib_dirs.arr[k]) == this.tmp.len)
                                {
                                    if (pp_eq(this.pool.mem + this.lib_dirs.arr[k], this.tmp.mem, this.tmp.len)) { have = true; };
                                };
                                k++;
                            };
                            if (!have)
                            {
                                this.lib_dirs.push(this.pool_add(this.tmp.mem, this.tmp.len));
                                if (this.verbose)
                                {
                                    this.x1.clear();
                                    this.x1.put_n(this.tmp.mem, this.tmp.len);
                                    this.vline(g"[PREPROCESSOR] Added library directory: \0", this.x1.mem, this.x1.len, g"\0");
                                };
                            };
                        };
                    };
                    this.emit_blank(this.cur_lineno);
                    return i + 1;
                };

                // #psub
                if (pp_starts(text, s, e, g"#psub\0", 5))
                {
                    a = s + 5;
                    b = e;
                    pp_trim(text, @a, @b);
                    this.psb.clear();
                    this.psb.put_n(text + a, b - a);
                    more = true;
                    while (more)
                    {
                        more = false;
                        if (this.psb.len > 0)
                        {
                            if (this.psb.mem[this.psb.len - 1] == '#') { more = true; };
                        };
                        if (!more) { break; };
                        this.psb.pop();
                        i++;
                        if (i >= ll.n) { break; };
                        this.emit_blank(this.cur_lineno);
                        this.cur_lineno = i + 1;
                        this.psb.rstrip_ws();
                        this.psb.put(32);
                        a = ll.off[i];
                        b = a + ll.len[i];
                        pp_trim(text, @a, @b);
                        this.psb.put_n(text + a, b - a);
                    };

                    // rest = collected.strip()
                    a = 0;
                    b = this.psb.len;
                    pp_trim(this.psb.mem, @a, @b);
                    paren_open = pp_find(this.psb.mem, a, b, 40);
                    if (paren_open == -1)
                    {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #psub missing parameter list at line \0");
                        this.errb.put_int(i + 1);
                        return -1;
                    };
                    name_off = a;
                    name_len = paren_open;
                    pp_trim(this.psb.mem, @name_off, @name_len);
                    paren_close = pp_find(this.psb.mem, paren_open, b, 41);
                    if (paren_close == -1)
                    {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #psub unclosed parameter list at line \0");
                        this.errb.put_int(i + 1);
                        return -1;
                    };

                    // params = [p.strip() for p in raw_params.split(',') if p.strip()]
                    this.pb.clear();
                    np = 0;
                    j = paren_open + 1;
                    while (j <= paren_close)
                    {
                        k = j;
                        while (k < paren_close)
                        {
                            if (this.psb.mem[k] == ',') { break; };
                            k++;
                        };
                        ts = j;
                        te = k;
                        pp_trim(this.psb.mem, @ts, @te);
                        if (te > ts)
                        {
                            this.pb.put_n(this.psb.mem + ts, te - ts);
                            this.pb.put(0);
                            np++;
                        };
                        j = k + 1;
                    };

                    body_off = paren_close + 1;
                    body_len = b;
                    pp_trim(this.psb.mem, @body_off, @body_len);

                    ent = this.psubs.intern(this.psb.mem + name_off, name_len - name_off);
                    if (ent < 0)
                    {
                        this.e_begin(PPError.ALLOC);
                        this.errb.put_str(g"[PREPROCESSOR] allocation failed\0");
                        return -1;
                    };
                    this.psubs.set_val(ent, this.psb.mem + body_off, body_len - body_off);
                    this.psubs.set_params(ent, this.pb.mem, this.pb.len, np);

                    if (this.verbose)
                    {
                        this.x1.clear();
                        this.x1.put_n(this.psb.mem + name_off, name_len - name_off);
                        this.x1.put(40);
                        k = 0;
                        j = 0;
                        while (j < np)
                        {
                            if (j > 0) { this.x1.put_str(g", \0"); };
                            this.x1.put_str(this.pb.mem + k);
                            k = k + pp_cstrlen(this.pb.mem + k) + 1;
                            j++;
                        };
                        this.x1.put_str(g") = \0");
                        this.x1.put_n(this.psb.mem + body_off, body_len - body_off);
                        this.vline(g"[PREPROCESSOR] Defined PSUB: \0", this.x1.mem, this.x1.len, g"\0");
                    };

                    this.emit_blank(this.cur_lineno);
                    return i + 1;
                };

                // #def
                if (pp_starts(text, s, e, g"#def\0", 4))
                {
                    semi = pp_find(text, lo, hi, 59);
                    if (semi == -1) { semi = hi; };
                    a = lo;
                    b = semi;
                    pp_trim(text, @a, @b);
                    tcount = 0;
                    this.tmp.clear();
                    name_off = 0;
                    name_len = 0;
                    nx = a;
                    while (true)
                    {
                        nx = pp_next_tok(text, b, nx, @ts, @te);
                        if (nx < 0) { break; };
                        if (tcount == 1)
                        {
                            name_off = ts;
                            name_len = te;
                        };
                        if (tcount >= 2)
                        {
                            if (tcount > 2) { this.tmp.put(32); };
                            this.tmp.put_n(text + ts, te - ts);
                        };
                        tcount++;
                    };
                    if (tcount >= 3)
                    {
                        ent = this.consts.intern(text + name_off, name_len - name_off);
                        if (ent < 0)
                        {
                            this.e_begin(PPError.ALLOC);
                            this.errb.put_str(g"[PREPROCESSOR] allocation failed\0");
                            return -1;
                        };
                        w = this.tmp.len;
                        if (w > 0)
                        {
                            if (this.tmp.mem[w - 1] == 59)
                            {
                                while (w > 0)
                                {
                                    if (this.tmp.mem[w - 1] != 59) { break; };
                                    w--;
                                };
                                a = 0;
                                b = w;
                                pp_trim(this.tmp.mem, @a, @b);
                                this.consts.set_val(ent, this.tmp.mem + a, b - a);
                            }
                            else
                            {
                                this.consts.set_val(ent, this.tmp.mem, w);
                            };
                        }
                        else
                        {
                            this.consts.set_val(ent, this.tmp.mem, 0);
                        };
                        if (this.verbose)
                        {
                            this.x1.clear();
                            this.x1.put_n(text + name_off, name_len - name_off);
                            this.x1.put_str(g" = \0");
                            this.x1.put_n(this.consts.val_ptr(ent), this.consts.val_len(ent));
                            this.vline(g"[PREPROCESSOR] Defined constant: \0", this.x1.mem, this.x1.len, g"\0");
                        };
                    };
                    this.emit_blank(this.cur_lineno);
                    return i + 1;
                };

                // #ifnpsub, #ifpsub, #ifdef, #ifndef. Each needs a second token.
                if (pp_starts(text, s, e, g"#ifnpsub\0", 8) | pp_starts(text, s, e, g"#ifpsub\0", 7)
                    | pp_starts(text, s, e, g"#ifdef\0", 6) | pp_starts(text, s, e, g"#ifndef\0", 7))
                {
                    nx = pp_next_tok(text, hi, lo, @ts, @te);
                    if (nx >= 0) { nx = pp_next_tok(text, hi, nx, @ts, @te); };
                    if (nx >= 0)
                    {
                        if (pp_starts(text, s, e, g"#ifnpsub\0", 8) | pp_starts(text, s, e, g"#ifpsub\0", 7))
                        {
                            k = pp_find(text, ts, te, 40);
                            if (k != -1) { te = k; };
                            a = ts;
                            b = te;
                            pp_trim(text, @a, @b);
                            return this.process_conditional(ll, i, a, b - a, pp_starts(text, s, e, g"#ifnpsub\0", 8), true);
                        };
                        return this.process_conditional(ll, i, ts, te - ts, pp_starts(text, s, e, g"#ifndef\0", 7), false);
                    };
                };

                // #package
                if (pp_starts(text, s, e, g"#package\0", 8))
                {
                    if (text[e - 1] != 59)
                    {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #package directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        return -1;
                    };
                    a = s + 8;
                    b = e;
                    while (b > a)
                    {
                        if (text[b - 1] != 59) { break; };
                        b--;
                    };
                    pp_trim(text, @a, @b);
                    j = a;
                    while (j <= b)
                    {
                        k = j;
                        while (k < b)
                        {
                            if (text[k] == ',') { break; };
                            k++;
                        };
                        ts = j;
                        te = k;
                        pp_trim(text, @ts, @te);
                        if (te > ts)
                        {
                            if (!this.process_package(text, ts, te - ts)) { return -1; };
                        };
                        j = k + 1;
                    };
                    this.emit_blank(this.cur_lineno);
                    return i + 1;
                };

                // #import
                if (pp_starts(text, s, e, g"#import\0", 7))
                {
                    if (text[e - 1] != 59)
                    {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #import directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        return -1;
                    };
                    a = s + 7;
                    b = e;
                    while (b > a)
                    {
                        if (text[b - 1] != 59) { break; };
                        b--;
                    };
                    pp_trim(text, @a, @b);
                    j = a;
                    while (j < b)
                    {
                        k = (int)text[j];
                        if (k == '<')
                        {
                            j++;
                            q2 = pp_find(text, j, b, '>');
                            if (q2 == -1)
                            {
                                this.e_begin(PPError.SYNTAX);
                                this.errb.put_str(g"[PREPROCESSOR] Unterminated <> in #import at line \0");
                                this.errb.put_int(i + 1);
                                return -1;
                            };
                            ts = j;
                            te = q2;
                            pp_trim(text, @ts, @te);
                            if (this.verbose) { this.vline(g"[PREPROCESSOR] Stdlib import: \0", text + ts, te - ts, g"\0"); };
                            if (!this.process_file(text + ts, te - ts, 2)) { return -1; };
                            j = q2 + 1;
                        }
                        elif (k == 34)
                        {
                            j++;
                            q2 = pp_find(text, j, b, 34);
                            if (q2 == -1)
                            {
                                this.e_begin(PPError.SYNTAX);
                                this.errb.put_str(g"[PREPROCESSOR] Unterminated \"\" in #import at line \0");
                                this.errb.put_int(i + 1);
                                return -1;
                            };
                            ts = j;
                            te = q2;
                            pp_trim(text, @ts, @te);
                            if (this.verbose) { this.vline(g"[PREPROCESSOR] Local import: \0", text + ts, te - ts, g"\0"); };
                            if (!this.process_file(text + ts, te - ts, 1)) { return -1; };
                            j = q2 + 1;
                        }
                        else
                        {
                            j++;
                        };
                    };
                    this.emit_blank(this.cur_lineno);
                    return i + 1;
                };

                // #warn
                if (pp_starts(text, s, e, g"#warn\0", 5))
                {
                    if (text[e - 1] != 59)
                    {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #warn directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        return -1;
                    };
                    q1 = pp_find(text, lo, hi, 34);
                    if (q1 != -1)
                    {
                        q2 = pp_find(text, q1 + 1, hi, 34);
                        if (q2 != -1)
                        {
                            this.vline(g"[PREPROCESSOR] \0", text + q1 + 1, q2 - q1 - 1, g"\0");
                        };
                    };
                    this.emit_blank(this.cur_lineno);
                    return i + 1;
                };

                // #stop
                if (pp_starts(text, s, e, g"#stop\0", 5))
                {
                    if (text[e - 1] != 59)
                    {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #stop directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        return -1;
                    };
                    q1 = pp_find(text, lo, hi, 34);
                    if (q1 != -1)
                    {
                        q2 = pp_find(text, q1 + 1, hi, 34);
                        if (q2 != -1)
                        {
                            this.vline(g"[PREPROCESSOR] \0", text + q1 + 1, q2 - q1 - 1, g"\0");
                        };
                    };
                    standard::io::console::println(g"Compilation failed, preprocessor stopped by constant.\0");
                    this.e_begin(PPError.STOP);
                    return -1;
                };

                // #endif;
                if (pp_starts(text, s, e, g"#endif;\0", 7))
                {
                    this.emit_blank(this.cur_lineno);
                    return i + 1;
                };

                // #else
                if (e - s == 5)
                {
                    if (pp_eq(text + s, g"#else\0", 5))
                    {
                        this.emit_blank(this.cur_lineno);
                        return i + 1;
                    };
                };

                // Regular line
                if (!this.substitute_constants(text + lo, hi - lo)) { return -1; };
                this.emit(this.sub_ptr, this.sub_len, this.cur_lineno);
                return i + 1;
            };

            // ===== CONDITIONALS =====

            // True when branch condition (name at text + off, len n) holds
            def cond_true(byte* text, int off, int n, bool invert, bool check_macros) -> bool
            {
                bool defined = false;
                int e;
                if (check_macros)
                {
                    defined = this.psubs.find(text + off, n) >= 0;
                }
                else
                {
                    e = this.consts.find(text + off, n);
                    if (e >= 0)
                    {
                        defined = true;
                        if (this.consts.val_len(e) == 1)
                        {
                            if (this.consts.val_ptr(e)[0] == '0') { defined = false; };
                        };
                    };
                };
                if (invert) { return !defined; };
                return defined;
            };

            // FXPreprocessor._parse_ifdef_condition on text[lo, hi). On success the
            // name is pc_off/pc_len and the negation flag pc_inv.
            def parse_condition(byte* text, int lo, int hi, int lineno) -> bool
            {
                int p, q, n, w;
                bool inv = false;
                bool ok3 = false;

                // defined(X) and !defined(X)
                p = lo;
                if (pp_at(text, hi, p) == '!')
                {
                    inv = true;
                    p++;
                    while (true)
                    {
                        w = pp_ws_fwd(text, hi, p);
                        if (w == 0) { break; };
                        p = p + w;
                    };
                };
                if (pp_starts(text, p, hi, g"defined\0", 7))
                {
                    p = p + 7;
                    while (true)
                    {
                        w = pp_ws_fwd(text, hi, p);
                        if (w == 0) { break; };
                        p = p + w;
                    };
                    if (pp_at(text, hi, p) == '(')
                    {
                        p++;
                        while (true)
                        {
                            w = pp_ws_fwd(text, hi, p);
                            if (w == 0) { break; };
                            p = p + w;
                        };
                        q = p;
                        while (q < hi)
                        {
                            if (!pp_is_word((int)text[q])) { break; };
                            q++;
                        };
                        if (q > p)
                        {
                            n = q;
                            while (true)
                            {
                                w = pp_ws_fwd(text, hi, n);
                                if (w == 0) { break; };
                                n = n + w;
                            };
                            if (pp_at(text, hi, n) == ')')
                            {
                                n++;
                                if (n == hi)
                                {
                                    this.pc_off = p;
                                    this.pc_len = q - p;
                                    this.pc_inv = inv;
                                    return true;
                                };
                            };
                        };
                    };
                };

                // plain identifier
                if (hi > lo)
                {
                    ok3 = true;
                    p = lo;
                    while (p < hi)
                    {
                        if (!pp_is_word((int)text[p]))
                        {
                            ok3 = false;
                            break;
                        };
                        p++;
                    };
                };
                if (ok3)
                {
                    this.pc_off = lo;
                    this.pc_len = hi - lo;
                    this.pc_inv = false;
                    return true;
                };

                this.e_begin(PPError.SYNTAX);
                this.errb.put_str(g"[PREPROCESSOR] Unsupported #elif condition '\0");
                this.errb.put_n(text + lo, hi - lo);
                this.errb.put_str(g"' at line \0");
                this.errb.put_int(lineno);
                this.errb.put_str(g". Only 'SYMBOL', 'defined(SYMBOL)', and '!defined(SYMBOL)' are supported.\0");
                return false;
            };

            // FXPreprocessor._process_conditional_block. The condition name is
            // name_n bytes at ll.text + name_off. Returns the index after #endif, or -1.
            def process_conditional(LineList* ll, int start_i, int name_off, int name_n, bool is_ifndef, bool check_macros) -> int
            {
                IntVec c_off();
                IntVec c_len();
                IntVec c_orig();
                IntVec b_start();
                IntVec b_name();
                IntVec b_nlen();
                IntVec b_inv();
                IntVec b_always();
                defer c_off.__exit();
                defer c_len.__exit();
                defer c_orig.__exit();
                defer b_start.__exit();
                defer b_name.__exit();
                defer b_nlen.__exit();
                defer b_inv.__exit();
                defer b_always.__exit();
                LineList sub;

                byte* text = ll.text;
                int entry_local = this.cur_lineno;
                int i, depth, lo, hi, s, e, orig, a, b, ch, bs, be, bi, j, w, nb;
                bool has_else;

                this.emit_blank(this.cur_lineno);

                b_start.push(0);
                b_name.push(name_off);
                b_nlen.push(name_n);
                if (is_ifndef) { b_inv.push(1); } else { b_inv.push(0); };
                b_always.push(0);
                has_else = false;

                i = start_i + 1;
                depth = 1;

                while (i < ll.n)
                {
                    lo = ll.off[i];
                    hi = lo + ll.len[i];
                    s = lo;
                    e = hi;
                    pp_trim(text, @s, @e);
                    orig = entry_local + (i - start_i);

                    if (pp_starts(text, s, e, g"#ifdef\0", 6) | pp_starts(text, s, e, g"#ifndef\0", 7)
                        | pp_starts(text, s, e, g"#ifnpsub\0", 8) | pp_starts(text, s, e, g"#ifpsub\0", 7))
                    {
                        depth++;
                    };

                    if (pp_starts(text, s, e, g"#endif;\0", 7))
                    {
                        depth--;
                        if (depth == 0)
                        {
                            this.emit_blank(orig);

                            nb = b_start.len;
                            ch = -1;
                            bi = 0;
                            while (bi < nb)
                            {
                                if (b_always.arr[bi] == 1)
                                {
                                    ch = bi;
                                    break;
                                };
                                if (this.cond_true(text, b_name.arr[bi], b_nlen.arr[bi], b_inv.arr[bi] == 1, check_macros))
                                {
                                    ch = bi;
                                    break;
                                };
                                bi++;
                            };

                            // Excluded lines become blanks, in branch order
                            bi = 0;
                            while (bi < nb)
                            {
                                if (bi != ch)
                                {
                                    bs = b_start.arr[bi];
                                    be = c_off.len;
                                    if (bi + 1 < nb) { be = b_start.arr[bi + 1]; };
                                    j = bs;
                                    while (j < be)
                                    {
                                        this.emit_blank(c_orig.arr[j]);
                                        j++;
                                    };
                                };
                                bi++;
                            };

                            if (ch >= 0)
                            {
                                bs = b_start.arr[ch];
                                be = c_off.len;
                                if (ch + 1 < nb) { be = b_start.arr[ch + 1]; };
                                if (be > bs)
                                {
                                    sub.text = text;
                                    sub.off = c_off.arr + bs;
                                    sub.len = c_len.arr + bs;
                                    sub.n = be - bs;
                                    j = 0;
                                    while (j < sub.n)
                                    {
                                        this.cur_lineno = c_orig.arr[bs + j];
                                        j = this.process_line(@sub, j);
                                        if (j < 0) { return -1; };
                                    };
                                };
                            };
                            return i + 1;
                        };
                        c_off.push(lo);
                        c_len.push(hi - lo);
                        c_orig.push(orig);
                        i++;
                        continue;
                    };

                    if (depth == 1)
                    {
                        if (pp_starts(text, s, e, g"#elif\0", 5))
                        {
                            if (has_else)
                            {
                                this.e_begin(PPError.SYNTAX);
                                this.errb.put_str(g"[PREPROCESSOR] #elif after #else at line \0");
                                this.errb.put_int(i + 1);
                                return -1;
                            };
                            a = s + 5;
                            b = e;
                            while (b > a)
                            {
                                if (text[b - 1] != 59) { break; };
                                b--;
                            };
                            pp_trim(text, @a, @b);
                            if (!this.parse_condition(text, a, b, i + 1)) { return -1; };
                            b_start.push(c_off.len);
                            b_name.push(this.pc_off);
                            b_nlen.push(this.pc_len);
                            if (this.pc_inv) { b_inv.push(1); } else { b_inv.push(0); };
                            b_always.push(0);
                            this.emit_blank(orig);
                            i++;
                            continue;
                        };

                        w = e - s;
                        if (pp_eq(text + s, g"#else\0", 5) & w == 5 | pp_eq(text + s, g"#else;\0", 6) & w == 6)
                        {
                            if (has_else)
                            {
                                this.e_begin(PPError.SYNTAX);
                                this.errb.put_str(g"[PREPROCESSOR] Multiple #else in same conditional block at line \0");
                                this.errb.put_int(i + 1);
                                return -1;
                            };
                            has_else = true;
                            b_start.push(c_off.len);
                            b_name.push(0);
                            b_nlen.push(0);
                            b_inv.push(0);
                            b_always.push(1);
                            this.emit_blank(orig);
                            i++;
                            continue;
                        };
                    };

                    c_off.push(lo);
                    c_len.push(hi - lo);
                    c_orig.push(orig);
                    i++;
                };

                this.e_begin(PPError.SYNTAX);
                this.errb.put_str(g"Unclosed conditional block starting at line \0");
                this.errb.put_int(start_i + 1);
                return -1;
            };

            // ===== MACROS AND CONSTANTS =====

            // One scan of FXPreprocessor._expand_macros over src[0, n) into mc.
            // Returns 1 when a macro was expanded, 0 when not, -1 on error.
            def macro_pass(byte* src, int n) -> int
            {
                int i, j, k, c, depth, rs, re, ent, np, na, cstart, p, plen, a, b, d, ra, rb;
                bool in_str, changed;
                int str_char;
                byte* ppar;

                this.mc.clear();
                while (i < n)
                {
                    c = (int)src[i];
                    if (!pp_is_alpha_us(c))
                    {
                        this.mc.put(c);
                        i++;
                        continue;
                    };

                    j = i;
                    while (j < n)
                    {
                        if (!pp_is_word((int)src[j])) { break; };
                        j++;
                    };

                    ent = this.psubs.find(src + i, j - i);
                    if (ent < 0)
                    {
                        this.mc.put_n(src + i, j - i);
                        i = j;
                        continue;
                    };
                    if (pp_at(src, n, j) != '(')
                    {
                        this.mc.put_n(src + i, j - i);
                        i = j;
                        continue;
                    };

                    // matching close paren, respecting nesting and strings
                    k = j + 1;
                    depth = 1;
                    in_str = false;
                    str_char = 0;
                    while (k < n & depth > 0)
                    {
                        c = (int)src[k];
                        if (in_str)
                        {
                            if (c == 92) { k++; }
                            elif (c == str_char) { in_str = false; };
                        }
                        else
                        {
                            if (c == 34 | c == 39)
                            {
                                in_str = true;
                                str_char = c;
                            }
                            elif (c == '(') { depth++; }
                            elif (c == ')') { depth--; };
                        };
                        k++;
                    };

                    rs = j + 1;
                    re = k - 1;
                    if (re > n) { re = n; };
                    if (re < rs) { re = rs; };

                    // _split_macro_args
                    this.aoff.clear();
                    this.alen.clear();
                    depth = 0;
                    in_str = false;
                    str_char = 0;
                    cstart = rs;
                    na = 0;
                    p = rs;
                    while (p < re)
                    {
                        c = (int)src[p];
                        if (in_str)
                        {
                            if (c == str_char) { in_str = false; };
                        }
                        elif (c == 34 | c == 39)
                        {
                            in_str = true;
                            str_char = c;
                        }
                        elif (c == '(') { depth++; }
                        elif (c == ')') { depth--; }
                        elif (c == ',' & depth == 0)
                        {
                            this.aoff.push(cstart);
                            this.alen.push(p - cstart);
                            na++;
                            cstart = p + 1;
                        };
                        p++;
                    };
                    if (re - cstart > 0 | na > 0)
                    {
                        this.aoff.push(cstart);
                        this.alen.push(re - cstart);
                        na++;
                    };

                    np = this.psubs.par_count(ent);
                    if (na != np)
                    {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] Macro '\0");
                        this.errb.put_n(src + i, j - i);
                        this.errb.put_str(g"' expects \0");
                        this.errb.put_int(np);
                        this.errb.put_str(g" argument(s), got \0");
                        this.errb.put_int(na);
                        this.errb.put_str(g": '\0");
                        d = k;
                        if (d > n) { d = n; };
                        this.errb.put_n(src + i, d - i);
                        this.errb.put_str(g"'\0");
                        return -1;
                    };

                    // Substitute each parameter into the body in order
                    this.x1.clear();
                    this.x1.put_n(this.psubs.val_ptr(ent), this.psubs.val_len(ent));
                    ppar = this.psubs.par_ptr(ent);
                    p = 0;
                    while (p < np)
                    {
                        plen = pp_cstrlen(ppar);
                        ra = this.aoff.arr[p];
                        rb = ra + this.alen.arr[p];
                        pp_trim(src, @ra, @rb);
                        this.x2.clear();
                        this.x2.put_replaced_word(this.x1.mem, this.x1.len, ppar, plen, src + ra, rb - ra);
                        this.x1.clear();
                        this.x1.put_n(this.x2.mem, this.x2.len);
                        ppar = ppar + plen + 1;
                        p++;
                    };
                    this.mc.put_n(this.x1.mem, this.x1.len);
                    changed = true;
                    i = k;
                };

                if (changed) { return 1; };
                return 0;
            };

            // FXPreprocessor._expand_macros. The result is ex_ptr/ex_len, valid until
            // the next call.
            def expand_macros(byte* s, int n) -> bool
            {
                int depth, rc;
                this.ex_ptr = s;
                this.ex_len = n;
                if (this.psubs.count == 0) { return true; };
                while (true)
                {
                    if (depth > FLUX_PP_MAX_DEPTH)
                    {
                        this.e_begin(PPError.RECURSION);
                        this.errb.put_str(g"[PREPROCESSOR] Macro expansion exceeded depth limit (64). Possible infinite recursion.\0");
                        return false;
                    };
                    rc = this.macro_pass(this.ex_ptr, this.ex_len);
                    if (rc < 0) { return false; };
                    if (rc == 0) { return true; };
                    this.ma.clear();
                    this.ma.put_n(this.mc.mem, this.mc.len);
                    this.ex_ptr = this.ma.mem;
                    this.ex_len = this.ma.len;
                    depth++;
                };
                return true;
            };

            // Appends token s[ts, te) to sc, replaced by its constant when it names one
            def flush_token(byte* s, int ts, int te, bool in_quotes) -> void
            {
                int e = -1;
                int w, a, b;
                byte* v;
                if (!in_quotes) { e = this.consts.find(s + ts, te - ts); };
                if (e < 0)
                {
                    this.sc.put_n(s + ts, te - ts);
                    return;
                };
                v = this.consts.val_ptr(e);
                w = this.consts.val_len(e);
                if (w > 0)
                {
                    if (v[w - 1] == 59)
                    {
                        while (w > 0)
                        {
                            if (v[w - 1] != 59) { break; };
                            w--;
                        };
                        a = 0;
                        b = w;
                        pp_trim(v, @a, @b);
                        this.sc.put_n(v + a, b - a);
                        return;
                    };
                };
                this.sc.put_n(v, w);
                return;
            };

            // FXPreprocessor._substitute_constants. The result is sub_ptr/sub_len,
            // valid until the next call.
            def substitute_constants(byte* s, int n) -> bool
            {
                int i, w, ts, a, b, c;
                bool in_quotes;
                if (!this.expand_macros(s, n)) { return false; };

                byte* t = this.ex_ptr;
                int tn = this.ex_len;
                this.sub_ptr = t;
                this.sub_len = tn;
                if (tn == 0) { return true; };
                a = 0;
                b = tn;
                pp_trim(t, @a, @b);
                if (b - a == 1)
                {
                    if (t[a] == 59) { return true; };
                };

                this.sc.clear();
                ts = -1;
                in_quotes = false;
                while (i < tn)
                {
                    c = (int)t[i];
                    if (c == 34)
                    {
                        in_quotes = !in_quotes;
                        if (ts < 0) { ts = i; };
                        i++;
                        continue;
                    };
                    w = pp_ws_fwd(t, tn, i);
                    if (w == 0)
                    {
                        if (pp_is_delim(c)) { w = 1; };
                    };
                    if (w > 0)
                    {
                        if (ts >= 0)
                        {
                            this.flush_token(t, ts, i, in_quotes);
                            ts = -1;
                        };
                        this.sc.put_n(t + i, w);
                        i = i + w;
                    }
                    else
                    {
                        if (ts < 0) { ts = i; };
                        i++;
                    };
                };
                if (ts >= 0) { this.flush_token(t, ts, tn, in_quotes); };

                this.sub_ptr = this.sc.mem;
                this.sub_len = this.sc.len;
                return true;
            };

            // ===== DRIVER =====

            // FXPreprocessor.process. The combined source is text_ptr()/text_len().
            def process() -> bool
            {
                int pl, iteration, ls, le;
                bool replaced, first;

                if (this.err_kind != 0) { return false; };

                if (this.realpath_into(this.srcpath.mem))
                {
                    pl = pp_parent_len(this.rbuf.mem, this.rbuf.len);
                    this.root_dir_off = this.pool_add(this.rbuf.mem, pl);
                }
                else
                {
                    pl = pp_parent_len(this.srcpath.mem, this.srcpath.len);
                    this.root_dir_off = this.pool_add(this.srcpath.mem, pl);
                };

                if (!this.process_file(this.srcpath.mem, this.srcpath.len, 0)) { return false; };

                replaced = true;
                while (replaced)
                {
                    iteration++;
                    if (this.verbose)
                    {
                        standard::io::console::print(g"[PREPROCESSOR] constant substitution passes: \0");
                        standard::io::console::println(iteration);
                    };
                    replaced = false;
                    this.passb.clear();
                    first = true;
                    ls = 0;
                    while (true)
                    {
                        le = ls;
                        while (le < this.outb.len)
                        {
                            if (this.outb.mem[le] == 10) { break; };
                            le++;
                        };
                        if (!this.substitute_constants(this.outb.mem + ls, le - ls)) { return false; };
                        if (!first) { this.passb.put(10); };
                        first = false;
                        this.passb.put_n(this.sub_ptr, this.sub_len);
                        if (this.sub_len != le - ls)
                        {
                            replaced = true;
                        }
                        elif (!pp_eq(this.sub_ptr, this.outb.mem + ls, this.sub_len))
                        {
                            replaced = true;
                        };
                        if (le >= this.outb.len) { break; };
                        ls = le + 1;
                    };
                    this.outb.clear();
                    this.outb.put_n(this.passb.mem, this.passb.len);
                };

                if (this.verbose)
                {
                    if (iteration > 1)
                    {
                        standard::io::console::print(g"[PREPROCESSOR] Completed after \0");
                        standard::io::console::print(iteration);
                        standard::io::console::println(g" constant passes.\0");
                    }
                    else
                    {
                        standard::io::console::print(g"[PREPROCESSOR] Completed after \0");
                        standard::io::console::print(iteration);
                        standard::io::console::println(g" constant pass.\0");
                    };
                    standard::io::console::print(g"[PREPROCESSOR] Processed \0");
                    standard::io::console::print(this.processed.count);
                    standard::io::console::println(g" file(s)\0");
                };

                if (!this.alloc_ok())
                {
                    this.e_begin(PPError.ALLOC);
                    this.errb.put_str(g"[PREPROCESSOR] allocation failed\0");
                    return false;
                };
                return true;
            };
        };
    };
};

#endif;
