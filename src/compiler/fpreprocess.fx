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

        pp_cstrlen(byte* s) -> int
        {
            int n;
            while (s[n] != 0) { n++; };
            -> n;
        };

        pp_eq(byte* a, byte* b, int n) -> bool
        {
            int i;
            while (i < n)
            {
                switch (a[i] != b[i])
                {
                    case (true) { -> false; }
                    default {};
                };
                i++;
            };
            -> true;
        };

        // Byte at i, or -1 outside [0, n)
        pp_at(byte* s, int n, int i) -> int
        {
            switch (i < 0)
            {
                case (true) { -> -1; }
                default {};
            };
            switch (i >= n)
            {
                case (true) { -> -1; }
                default {};
            };
            -> (int)s[i];
        };

        pp_find(byte* t, int lo, int hi, int ch) -> int
        {
            int i = lo;
            while (i < hi)
            {
                switch ((int)t[i] == ch)
                {
                    case (true) { -> i; }
                    default {};
                };
                i++;
            };
            -> -1;
        };

        pp_starts(byte* t, int lo, int hi, byte* lit, int ln) -> bool
        {
            switch (hi - lo < ln)
            {
                case (true) { -> false; }
                default {};
            };
            -> pp_eq(t + lo, lit, ln);
        };

        pp_is_alpha_us(int c) -> bool -> (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z') | c == '_';

        pp_is_word(int c) -> bool -> (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z') | (c >= '0' & c <= '9') | c == '_';

        // Characters that end a token in _substitute_constants
        pp_is_delim(int c) -> bool -> c == '.' | c == ',' | c == ';' | c == ':' | c == '(' | c == ')' | c == '[' | c == ']' | c == '{' | c == '}' | c == '+' | c == '-' | c == '*' | c == '/' | c == '%' | c == '=' | c == '!' | c == '<' | c == '>' | c == '|' | c == '&' | c == '^' | c == '~';

        // Length in bytes of the Unicode whitespace character at s[i], 0 if none
        // (the set str.isspace() accepts).
        pp_ws_fwd(byte* s, int n, int i) -> int
        {
            switch (i >= n)
            {
                case (true) { -> 0; }
                default {};
            };
            int c = (int)s[i];
            switch (c == 32 | (c >= 9 & c <= 13) | (c >= 28 & c <= 31))
            {
                case (true) { -> 1; }
                default {};
            };
            switch (c < 128)
            {
                case (true) { -> 0; }
                default {};
            };
            int c1 = pp_at(s, n, i + 1);
            int c2 = pp_at(s, n, i + 2);
            switch (c == 0xC2)
            {
                case (true) {
                switch (c1 == 0x85 | c1 == 0xA0)
                {
                    case (true) { -> 2; }
                    default {};
                };
                -> 0;
            }
                default {};
            };
            switch (c == 0xE1)
            {
                case (true) {
                switch (c1 == 0x9A & c2 == 0x80)
                {
                    case (true) { -> 3; }
                    default {};
                };
                -> 0;
            }
                default {};
            };
            switch (c == 0xE2)
            {
                case (true) {
                switch (c1 == 0x80)
                {
                    case (true) {
                    switch ((c2 >= 0x80 & c2 <= 0x8A) | c2 == 0xA8 | c2 == 0xA9 | c2 == 0xAF)
                    {
                        case (true) { -> 3; }
                        default {};
                    };
                    -> 0;
                }
                    default {};
                };
                switch (c1 == 0x81 & c2 == 0x9F)
                {
                    case (true) { -> 3; }
                    default {};
                };
                -> 0;
            }
                default {};
            };
            switch (c == 0xE3)
            {
                case (true) {
                switch (c1 == 0x80 & c2 == 0x80)
                {
                    case (true) { -> 3; }
                    default {};
                };
                -> 0;
            }
                default {};
            };
            -> 0;
        };

        // Length of the whitespace character that ends at s[j - 1], never reading below lo
        pp_ws_back(byte* s, int lo, int j) -> int
        {
            switch (j <= lo)
            {
                case (true) { -> 0; }
                default {};
            };
            int c = (int)s[j - 1];
            switch (c == 32 | (c >= 9 & c <= 13) | (c >= 28 & c <= 31))
            {
                case (true) { -> 1; }
                default {};
            };
            switch (c < 128)
            {
                case (true) { -> 0; }
                default {};
            };
            int b1, b2;
            switch (j - 2 >= lo)
            {
                case (true) {
                b1 = (int)s[j - 2];
                switch (b1 == 0xC2 & (c == 0x85 | c == 0xA0))
                {
                    case (true) { -> 2; }
                    default {};
                };
            }
                default {};
            };
            switch (j - 3 >= lo)
            {
                case (true) {
                b2 = (int)s[j - 3];
                b1 = (int)s[j - 2];
                switch (b2 == 0xE1 & b1 == 0x9A & c == 0x80)
                {
                    case (true) { -> 3; }
                    default {};
                };
                switch (b2 == 0xE2 & b1 == 0x80)
                {
                    case (true) {
                    switch ((c >= 0x80 & c <= 0x8A) | c == 0xA8 | c == 0xA9 | c == 0xAF)
                    {
                        case (true) { -> 3; }
                        default {};
                    };
                }
                    default {};
                };
                switch (b2 == 0xE2 & b1 == 0x81 & c == 0x9F)
                {
                    case (true) { -> 3; }
                    default {};
                };
                switch (b2 == 0xE3 & b1 == 0x80 & c == 0x80)
                {
                    case (true) { -> 3; }
                    default {};
                };
            }
                default {};
            };
            -> 0;
        };

        // str.strip() on t[*lo, *hi)
        pp_trim(byte* t, int* lo, int* hi) -> void
        {
            int a = *lo;
            int b = *hi;
            int w;
            while (a < b)
            {
                w = pp_ws_fwd(t, b, a);
                switch (w == 0)
                {
                    case (true) { break; }
                    default {};
                };
                a = a + w;
            };
            while (b > a)
            {
                w = pp_ws_back(t, a, b);
                switch (w == 0)
                {
                    case (true) { break; }
                    default {};
                };
                b = b - w;
            };
            *lo = a;
            *hi = b;
            ->;
        };

        // Next whitespace separated token in t[pos, hi) (str.split()).
        // Returns the end of the token, or -1 when there is none.
        pp_next_tok(byte* t, int hi, int pos, int* ts, int* te) -> int
        {
            int p = pos;
            int w;
            while (p < hi)
            {
                w = pp_ws_fwd(t, hi, p);
                switch (w == 0)
                {
                    case (true) { break; }
                    default {};
                };
                p = p + w;
            };
            switch (p >= hi)
            {
                case (true) { -> -1; }
                default {};
            };
            *ts = p;
            while (p < hi)
            {
                w = pp_ws_fwd(t, hi, p);
                switch (w != 0)
                {
                    case (true) { break; }
                    default {};
                };
                p++;
            };
            *te = p;
            -> p;
        };

        // End of the line that starts at p, following str.splitlines().
        // *tl receives the terminator length (0 at end of text).
        pp_eol(byte* t, int n, int p, int* tl) -> int
        {
            int j = p;
            int c, c1, c2;
            while (j < n)
            {
                c = (int)t[j];
                switch (c == 10 | c == 11 | c == 12 | c == 28 | c == 29 | c == 30)
                {
                    case (true) {
                    *tl = 1;
                    -> j;
                }
                    default {};
                };
                switch (c == 13)
                {
                    case (true) {
                    *tl = 1;
                    switch (pp_at(t, n, j + 1) == 10)
                    {
                        case (true) { *tl = 2; }
                        default {};
                    };
                    -> j;
                }
                    default {};
                };
                switch (c == 0xC2)
                {
                    case (true) {
                    switch (pp_at(t, n, j + 1) == 0x85)
                    {
                        case (true) {
                        *tl = 2;
                        -> j;
                    }
                        default {};
                    };
                }
                    default {};
                };
                switch (c == 0xE2)
                {
                    case (true) {
                    c1 = pp_at(t, n, j + 1);
                    c2 = pp_at(t, n, j + 2);
                    switch (c1 == 0x80 & (c2 == 0xA8 | c2 == 0xA9))
                    {
                        case (true) {
                        *tl = 3;
                        -> j;
                    }
                        default {};
                    };
                }
                    default {};
                };
                j++;
            };
            *tl = 0;
            -> n;
        };

        // Regex style \b between s[pos - 1] and s[pos] over ASCII word characters
        pp_boundary(byte* s, int n, int pos) -> bool
        {
            bool a = false;
            bool b = false;
            switch (pos > 0)
            {
                case (true) { a = pp_is_word((int)s[pos - 1]); }
                default {};
            };
            switch (pos < n)
            {
                case (true) { b = pp_is_word((int)s[pos]); }
                default {};
            };
            -> (a & !b) | (!a & b);
        };

        pp_is_abs(byte* r, int n) -> bool
        {
            switch (n <= 0)
            {
                case (true) { -> false; }
                default {};
            };
            switch ((int)r[0] == FLUX_PP_SEP)
            {
                case (true) { -> true; }
                default {};
            };
            #ifdef __WINDOWS__
            switch (n >= 2)
            {
                case (true) {
                switch (r[1] == ':')
                {
                    case (true) { -> true; }
                    default {};
                };
            }
                default {};
            };
            #endif;
            -> false;
        };

        // Length of Path(p).parent for an absolute path (0 for a bare name)
        pp_parent_len(byte* p, int n) -> int
        {
            int i = n - 1;
            while (i >= 0)
            {
                switch ((int)p[i] == FLUX_PP_SEP)
                {
                    case (true) { break; }
                    default {};
                };
                i--;
            };
            switch (i < 0)
            {
                case (true) { -> 0; }
                default {};
            };
            switch (i == 0)
            {
                case (true) { -> 1; }
                default {};
            };
            #ifdef __WINDOWS__
            switch (i == 2)
            {
                case (true) {
                switch (p[1] == ':')
                {
                    case (true) { -> 3; }
                    default {};
                };
            }
                default {};
            };
            #endif;
            -> i;
        };

        pp_exists(byte* p) -> bool
        {
            #ifdef __WINDOWS__
            -> _access(p, 0) == 0;
            #else
            -> access(p, 0) == 0;
            #endif;
        };

        pp_hash(byte* s, int n) -> u64
        {
            u64 h = (u64)5381;
            int i;
            while (i < n)
            {
                h = h * (u64)33 + (u64)s[i];
                i++;
            };
            -> h;
        };

        // ===== GROWABLE BYTE BUFFER =====
        // mem is always null terminated while it is allocated; len excludes the terminator.
        // ok turns false once an allocation fails and stays false.

        object Buf
        {
            byte* mem;
            int len, cap;
            bool ok;

            __init() -> this
            {
                this.len = 0;
                this.cap = 256;
                this.ok = true;
                this.mem = (byte*)fmalloc((u64)this.cap);
                switch (this.mem == (byte*)0)
                {
                    case (true) {
                    this.ok = false;
                    this.cap = 0;
                }
                    default {
                    this.mem[0] = (byte)0;
                };
                };
                -> this;
            };

            __expr() -> Buf* -> this;

            __exit() -> void
            {
                switch (this.mem != (byte*)0)
                {
                    case (true) { ffree(this.mem); }
                    default {};
                };
                this.mem = (byte*)0;
                this.len = 0;
                this.cap = 0;
                ->;
            };

            reserve(int extra) -> bool
            {
                switch (!this.ok)
                {
                    case (true) { -> false; }
                    default {};
                };
                int need = this.len + extra + 1;
                switch (need <= this.cap)
                {
                    case (true) { -> true; }
                    default {};
                };
                int nc = this.cap;
                switch (nc < 256)
                {
                    case (true) { nc = 256; }
                    default {};
                };
                while (nc < need) { nc = nc * 2; };
                u64 np;
                switch (this.mem == (byte*)0)
                {
                    case (true) {
                    np = (u64)fmalloc((u64)nc);
                }
                    default {
                    np = frealloc((u64)this.mem, (size_t)nc);
                };
                };
                switch (np == (u64)0)
                {
                    case (true) {
                    this.ok = false;
                    -> false;
                }
                    default {};
                };
                this.mem = (byte*)np;
                this.cap = nc;
                -> true;
            };

            put(int b) -> void
            {
                switch (!this.reserve(1))
                {
                    case (true) { ->; }
                    default {};
                };
                this.mem[this.len] = (byte)b;
                this.len++;
                this.mem[this.len] = (byte)0;
                ->;
            };

            // s must not point into this buffer
            put_n(byte* s, int n) -> void
            {
                switch (n <= 0)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (!this.reserve(n))
                {
                    case (true) { ->; }
                    default {};
                };
                int i;
                while (i < n)
                {
                    this.mem[this.len + i] = s[i];
                    i++;
                };
                this.len = this.len + n;
                this.mem[this.len] = (byte)0;
                ->;
            };

            put_str(byte* s) -> void -> this.put_n(s, pp_cstrlen(s));

            put_int(int v) -> void
            {
                byte[16] tmp = noinit;
                int n, k;
                switch (v < 0)
                {
                    case (true) {
                    this.put(45);
                    v = 0 - v;
                }
                    default {};
                };
                switch (v == 0)
                {
                    case (true) {
                    this.put(48);
                    ->;
                }
                    default {};
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
                ->;
            };

            clear() -> void
            {
                this.len = 0;
                switch (this.mem != (byte*)0)
                {
                    case (true) { this.mem[0] = (byte)0; }
                    default {};
                };
                ->;
            };

            pop() -> void
            {
                switch (this.len > 0)
                {
                    case (true) {
                    this.len--;
                    this.mem[this.len] = (byte)0;
                }
                    default {};
                };
                ->;
            };

            // str.rstrip()
            rstrip_ws() -> void
            {
                switch (this.mem == (byte*)0)
                {
                    case (true) { ->; }
                    default {};
                };
                int w;
                while (this.len > 0)
                {
                    w = pp_ws_back(this.mem, 0, this.len);
                    switch (w == 0)
                    {
                        case (true) { break; }
                        default {};
                    };
                    this.len = this.len - w;
                };
                this.mem[this.len] = (byte)0;
                ->;
            };

            // FXPreprocessor._strip_comments. Appends the stripped text of c[0, n).
            put_stripped(byte* c, int n) -> void
            {
                int i, ch, string_char;
                bool in_string = false;
                while (i < n)
                {
                    ch = (int)c[i];
                    switch (in_string)
                    {
                        case (true) {
                        this.put(ch);
                        switch (ch == 92 & i + 1 < n)
                        {
                            case (true) {
                            i++;
                            this.put((int)c[i]);
                        }
                            default {
                                switch (ch == string_char)
                                {
                                    case (true) {
                            in_string = false;
                        }
                                    default {};
                                };
                            };
                        };
                        i++;
                        continue;
                    }
                        default {};
                    };

                    switch (ch == 34 | ch == 39)
                    {
                        case (true) {
                        in_string = true;
                        string_char = ch;
                        this.put(ch);
                        i++;
                        continue;
                    }
                        default {};
                    };

                    switch (i + 2 < n)
                    {
                        case (true) {
                        switch (ch == 47 & c[i + 1] == 47 & c[i + 2] == 47)
                        {
                            case (true) {
                            i = i + 3;
                            while (i < n)
                            {
                                switch (i + 2 < n)
                                {
                                    case (true) {
                                    switch (c[i] == 47 & c[i + 1] == 47 & c[i + 2] == 47)
                                    {
                                        case (true) {
                                        i = i + 3;
                                        break;
                                    }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                                switch (c[i] == 10)
                                {
                                    case (true) { this.put(10); }
                                    default {};
                                };
                                i++;
                            };
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };

                    switch (i + 1 < n)
                    {
                        case (true) {
                        switch (ch == 47 & c[i + 1] == 47)
                        {
                            case (true) {
                            while (i < n)
                            {
                                switch (c[i] == 10)
                                {
                                    case (true) { break; }
                                    default {};
                                };
                                i++;
                            };
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };

                    this.put(ch);
                    i++;
                };
                ->;
            };

            // re.sub(r'\b' + re.escape(pat) + r'\b', rep, src), literal replacement text
            put_replaced_word(byte* src, int sn, byte* pat, int pn, byte* rep, int rn) -> void
            {
                int i;
                bool hit;
                while (i < sn)
                {
                    hit = false;
                    switch (i + pn <= sn)
                    {
                        case (true) {
                        switch (pp_eq(src + i, pat, pn))
                        {
                            case (true) {
                            switch (pp_boundary(src, sn, i))
                            {
                                case (true) {
                                switch (pp_boundary(src, sn, i + pn))
                                {
                                    case (true) { hit = true; }
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
                    switch (hit)
                    {
                        case (true) {
                        this.put_n(rep, rn);
                        i = i + pn;
                    }
                        default {
                        this.put((int)src[i]);
                        i++;
                    };
                    };
                };
                ->;
            };

            // Replaces the content with a source file read the way
            // _read_source_file does: UTF-8 with BOM removed, invalid sequences
            // replaced by U+FFFD, CRLF and CR translated to LF.
            // Returns -1 when the file cannot be read, 1 when replacements were
            // made, 0 otherwise.
            load_file(byte* path) -> int
            {
                void* f = fopen(path, g"rb\0");
                switch (f == (void*)0)
                {
                    case (true) { -> -1; }
                    default {};
                };

                fseek(f, 0, SEEK_END);
                int size = ftell(f);
                fseek(f, 0, SEEK_SET);
                switch (size < 0)
                {
                    case (true) {
                    fclose(f);
                    -> -1;
                }
                    default {};
                };

                byte* raw = (byte*)fmalloc((u64)size + (u64)1);
                switch (raw == (byte*)0)
                {
                    case (true) {
                    fclose(f);
                    -> -1;
                }
                    default {};
                };
                int got = fread(raw, 1, size, f);
                fclose(f);
                switch (got < 0)
                {
                    case (true) {
                    ffree(raw);
                    -> -1;
                }
                    default {};
                };

                this.clear();
                int i, bad, c, need, lo, hi, k, b1;
                switch (got >= 3)
                {
                    case (true) {
                    switch (raw[0] == 0xEF & raw[1] == 0xBB & raw[2] == 0xBF)
                    {
                        case (true) { i = 3; }
                        default {};
                    };
                }
                    default {};
                };

                while (i < got)
                {
                    c = (int)raw[i];
                    switch (c < 0x80)
                    {
                        case (true) {
                        switch (c)
                        {
                            case (13)
                            {
                                this.put(10);
                                switch (pp_at(raw, got, i + 1) == 10)
                                {
                                    case (true) { i++; }
                                    default {};
                                };
                            }
                            default
                            {
                                this.put(c);
                            };
                        };
                        i++;
                        continue;
                    }
                        default {};
                    };

                    need = 0;
                    lo = 0x80;
                    hi = 0xBF;
                    switch (c >= 0xC2 & c <= 0xDF)
                    {
                        case (true) { need = 1; }
                        default {
                            switch (c == 0xE0)
                            {
                                case (true) { need = 2; lo = 0xA0; }
                                default {
                                    switch (c >= 0xE1 & c <= 0xEC)
                                    {
                                        case (true) { need = 2; }
                                        default {
                                            switch (c == 0xED)
                                            {
                                                case (true) { need = 2; hi = 0x9F; }
                                                default {
                                                    switch (c >= 0xEE & c <= 0xEF)
                                                    {
                                                        case (true) { need = 2; }
                                                        default {
                                                            switch (c == 0xF0)
                                                            {
                                                                case (true) { need = 3; lo = 0x90; }
                                                                default {
                                                                    switch (c >= 0xF1 & c <= 0xF3)
                                                                    {
                                                                        case (true) { need = 3; }
                                                                        default {
                                                                            switch (c == 0xF4)
                                                                            {
                                                                                case (true) { need = 3; hi = 0x8F; }
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

                    switch (need == 0)
                    {
                        case (true) {
                        this.put(0xEF);
                        this.put(0xBF);
                        this.put(0xBD);
                        bad = 1;
                        i++;
                        continue;
                    }
                        default {};
                    };

                    k = 1;
                    while (k <= need)
                    {
                        b1 = pp_at(raw, got, i + k);
                        switch (b1 < lo | b1 > hi)
                        {
                            case (true) { break; }
                            default {};
                        };
                        lo = 0x80;
                        hi = 0xBF;
                        k++;
                    };

                    switch (k > need)
                    {
                        case (true) {
                        this.put_n(raw + i, need + 1);
                        i = i + need + 1;
                    }
                        default {
                        this.put(0xEF);
                        this.put(0xBF);
                        this.put(0xBD);
                        bad = 1;
                        i = i + k;
                    };
                    };
                };

                ffree(raw);
                -> bad;
            };
        };

        // ===== GROWABLE INT ARRAY =====

        object IntVec
        {
            int* arr;
            int len, cap;
            bool ok;

            __init() -> this
            {
                this.len = 0;
                this.cap = 64;
                this.ok = true;
                this.arr = (int*)fmalloc((u64)this.cap * (u64)(sizeof(int) / 8));
                switch (this.arr == (int*)0)
                {
                    case (true) {
                    this.ok = false;
                    this.cap = 0;
                }
                    default {};
                };
                -> this;
            };

            __expr() -> IntVec* -> this;

            __exit() -> void
            {
                switch (this.arr != (int*)0)
                {
                    case (true) { ffree((byte*)this.arr); }
                    default {};
                };
                this.arr = (int*)0;
                this.len = 0;
                this.cap = 0;
                ->;
            };

            push(int v) -> void
            {
                switch (!this.ok)
                {
                    case (true) { ->; }
                    default {};
                };
                switch (this.len >= this.cap)
                {
                    case (true) {
                    int nc = this.cap * 2;
                    switch (nc < 64)
                    {
                        case (true) { nc = 64; }
                        default {};
                    };
                    u64 np;
                    switch (this.arr == (int*)0)
                    {
                        case (true) {
                        np = (u64)fmalloc((u64)nc * (u64)(sizeof(int) / 8));
                    }
                        default {
                        np = frealloc((u64)this.arr, (size_t)((u64)nc * (u64)(sizeof(int) / 8)));
                    };
                    };
                    switch (np == (u64)0)
                    {
                        case (true) {
                        this.ok = false;
                        ->;
                    }
                        default {};
                    };
                    this.arr = (int*)np;
                    this.cap = nc;
                }
                    default {};
                };
                this.arr[this.len] = v;
                this.len++;
                ->;
            };

            pop() -> void
            {
                switch (this.len > 0)
                {
                    case (true) { this.len--; }
                    default {};
                };
                ->;
            };

            clear() -> void
            {
                this.len = 0;
                ->;
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

            __init() -> this
            {
                this.keys.__init();
                this.vals.__init();
                this.count = 0;
                this.ok = true;
                this.slot_cap = 256;
                this.ent_cap = 64;
                this.slots = (int*)fmalloc((u64)this.slot_cap * (u64)(sizeof(int) / 8));
                this.ents = (int*)fmalloc((u64)this.ent_cap * (u64)FLUX_PP_STRIDE * (u64)(sizeof(int) / 8));
                switch (this.slots == (int*)0 | this.ents == (int*)0)
                {
                    case (true) {
                    this.ok = false;
                    -> this;
                }
                    default {};
                };
                int z;
                while (z < this.slot_cap)
                {
                    this.slots[z] = 0;
                    z++;
                };
                -> this;
            };

            __expr() -> SymTab* -> this;

            __exit() -> void
            {
                switch (this.slots != (int*)0)
                {
                    case (true) { ffree((byte*)this.slots); }
                    default {};
                };
                switch (this.ents != (int*)0)
                {
                    case (true) { ffree((byte*)this.ents); }
                    default {};
                };
                this.slots = (int*)0;
                this.ents = (int*)0;
                this.keys.__exit();
                this.vals.__exit();
                ->;
            };

            // Entry index of s[0, n), or -1
            find(byte* s, int n) -> int
            {
                switch (!this.ok)
                {
                    case (true) { -> -1; }
                    default {};
                };
                u64 h = pp_hash(s, n);
                int idx = (int)(h % (u64)this.slot_cap);
                int e, base, j;
                bool same;
                while (true)
                {
                    e = this.slots[idx];
                    switch (e == 0)
                    {
                        case (true) { -> -1; }
                        default {};
                    };
                    e = e - 1;
                    base = e * FLUX_PP_STRIDE;
                    switch (this.ents[base + 1] == n)
                    {
                        case (true) {
                        same = true;
                        j = 0;
                        while (j < n)
                        {
                            switch (this.keys.mem[this.ents[base] + j] != s[j])
                            {
                                case (true) {
                                same = false;
                                break;
                            }
                                default {};
                            };
                            j++;
                        };
                        switch (same)
                        {
                            case (true) { -> e; }
                            default {};
                        };
                    }
                        default {};
                    };
                    idx++;
                    switch (idx >= this.slot_cap)
                    {
                        case (true) { idx = 0; }
                        default {};
                    };
                };
                -> -1;
            };

            // Links entry e into slots
            place(int e) -> void
            {
                int base = e * FLUX_PP_STRIDE;
                u64 h = pp_hash(this.keys.mem + this.ents[base], this.ents[base + 1]);
                int idx = (int)(h % (u64)this.slot_cap);
                while (this.slots[idx] != 0)
                {
                    idx++;
                    switch (idx >= this.slot_cap)
                    {
                        case (true) { idx = 0; }
                        default {};
                    };
                };
                this.slots[idx] = e + 1;
                ->;
            };

            grow_slots() -> bool
            {
                int nc = this.slot_cap * 2;
                int* ns = (int*)fmalloc((u64)nc * (u64)(sizeof(int) / 8));
                switch (ns == (int*)0)
                {
                    case (true) {
                    this.ok = false;
                    -> false;
                }
                    default {};
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
                -> true;
            };

            grow_ents() -> bool
            {
                int nc = this.ent_cap * 2;
                u64 np = frealloc((u64)this.ents, (size_t)((u64)nc * (u64)FLUX_PP_STRIDE * (u64)(sizeof(int) / 8)));
                switch (np == (u64)0)
                {
                    case (true) {
                    this.ok = false;
                    -> false;
                }
                    default {};
                };
                this.ents = (int*)np;
                this.ent_cap = nc;
                -> true;
            };

            // Entry index of s[0, n), created when missing. -1 on allocation failure.
            // s must not point into this table.
            intern(byte* s, int n) -> int
            {
                int e = this.find(s, n);
                switch (e >= 0)
                {
                    case (true) { -> e; }
                    default {};
                };
                switch (!this.ok)
                {
                    case (true) { -> -1; }
                    default {};
                };
                switch (this.count + 1 > this.ent_cap)
                {
                    case (true) {
                    switch (!this.grow_ents())
                    {
                        case (true) { -> -1; }
                        default {};
                    };
                }
                    default {};
                };
                switch ((this.count + 1) * 2 > this.slot_cap)
                {
                    case (true) {
                    switch (!this.grow_slots())
                    {
                        case (true) { -> -1; }
                        default {};
                    };
                }
                    default {};
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
                -> e;
            };

            set_val(int e, byte* v, int n) -> void
            {
                int base = e * FLUX_PP_STRIDE;
                this.ents[base + 2] = this.vals.len;
                this.ents[base + 3] = n;
                this.vals.put_n(v, n);
                this.vals.put(0);
                ->;
            };

            // pcount parameter names stored as consecutive null terminated strings,
            // plen bytes in total including the terminators
            set_params(int e, byte* p, int plen, int pcount) -> void
            {
                int base = e * FLUX_PP_STRIDE;
                this.ents[base + 4] = this.vals.len;
                this.ents[base + 5] = plen;
                this.ents[base + 6] = pcount;
                this.vals.put_n(p, plen);
                ->;
            };

            val_ptr(int e) -> byte* -> this.vals.mem + this.ents[e * FLUX_PP_STRIDE + 2];

            val_len(int e) -> int -> this.ents[e * FLUX_PP_STRIDE + 3];

            par_ptr(int e) -> byte* -> this.vals.mem + this.ents[e * FLUX_PP_STRIDE + 4];

            par_count(int e) -> int -> this.ents[e * FLUX_PP_STRIDE + 6];
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

            __init(byte* source_file) -> this
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
                switch (this.pathbuf == (byte*)0)
                {
                    case (true) {
                    this.err_kind = PPError.ALLOC;
                    -> this;
                }
                    default {};
                };

                switch (this.realpath_into(g".\0"))
                {
                    case (true) {
                    this.cwd_off = this.pool_add(this.rbuf.mem, this.rbuf.len);
                }
                    default {
                    this.cwd_off = this.pool_add(g".\0", 1);
                };
                };
                this.srcdir_off = this.cwd_off;
                -> this;
            };

            __expr() -> Preprocessor* -> this;

            __exit() -> void
            {
                switch (this.pathbuf != (byte*)0)
                {
                    case (true) { ffree(this.pathbuf); }
                    default {};
                };
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
                ->;
            };

            // ===== ACCESSORS =====

            text_ptr() -> byte* -> this.outb.mem;

            text_len() -> int -> this.outb.len;

            err_text() -> byte* -> this.errb.mem;

            // Resolved path of the file output line i came from
            map_path(int i) -> byte* -> this.pool.mem + this.files.arr[this.map_file.arr[i]];

            // Local line number of output line i inside map_path(i)
            map_lineno(int i) -> int -> this.map_line.arr[i];

            // Number of files processed
            file_count() -> int -> this.processed.count;

            // ===== CONFIGURATION =====

            set_srcdir(byte* dir) -> void
            {
                this.srcdir_off = this.pool_add(dir, pp_cstrlen(dir));
                ->;
            };

            // compiler_constants[name] = value
            define(byte* name, byte* value) -> void
            {
                int e = this.consts.intern(name, pp_cstrlen(name));
                switch (e < 0)
                {
                    case (true) { ->; }
                    default {};
                };
                this.consts.set_val(e, value, pp_cstrlen(value));
                ->;
            };

            // fmacros.build_compiler_macros with the host as target and the
            // flux_config.cfg defaults (default_byte_width 8, debug and
            // optimization_level unset).
            add_default_macros() -> void
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
                ->;
            };

            // ===== STRINGS, ERRORS, OUTPUT =====

            // Appends s[0, n) to the pool as a null terminated string, returns its offset.
            // s must not point into the pool.
            pool_add(byte* s, int n) -> int
            {
                int off = this.pool.len;
                this.pool.put_n(s, n);
                this.pool.put(0);
                -> off;
            };

            e_begin(int kind) -> void
            {
                this.err_kind = kind;
                this.errb.clear();
                ->;
            };

            // Prints a + s[0, n) + b on one line
            vline(byte* a, byte* s, int n, byte* b) -> void
            {
                this.tmp.clear();
                this.tmp.put_str(a);
                this.tmp.put_n(s, n);
                this.tmp.put_str(b);
                standard::io::console::println(this.tmp.mem);
                ->;
            };

            // Appends a line to the output together with its line_map entry
            emit(byte* s, int n, int lineno) -> void
            {
                switch (this.line_count > 0)
                {
                    case (true) { this.outb.put(10); }
                    default {};
                };
                this.outb.put_n(s, n);
                this.map_file.push(this.cur_file);
                this.map_line.push(lineno);
                this.line_count++;
                ->;
            };

            emit_blank(int lineno) -> void -> this.emit(g"\0", 0, lineno);

            alloc_ok() -> bool
            {
                switch (!this.pool.ok | !this.outb.ok | !this.errb.ok | !this.fbuf.ok | !this.sc.ok)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (!this.ma.ok | !this.mc.ok | !this.x1.ok | !this.x2.ok | !this.psb.ok)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (!this.pb.ok | !this.tmp.ok | !this.passb.ok | !this.rbuf.ok | !this.jb.ok)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (!this.js.ok | !this.jv.ok | !this.files.ok | !this.lib_dirs.ok | !this.dir_stack.ok)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (!this.map_file.ok | !this.map_line.ok | !this.aoff.ok | !this.alen.ok)
                {
                    case (true) { -> false; }
                    default {};
                };
                switch (!this.processed.ok | !this.consts.ok | !this.psubs.ok)
                {
                    case (true) { -> false; }
                    default {};
                };
                -> true;
            };

            // ===== PATHS =====

            // Path.resolve() of p into rbuf. False when p does not exist.
            #ifdef __WINDOWS__
            realpath_into(byte* p) -> bool
            {
                byte* r = _fullpath(this.pathbuf, p, (size_t)FLUX_PP_PATH_MAX);
                switch (r == (byte*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                this.rbuf.clear();
                this.rbuf.put_str(this.pathbuf);
                -> true;
            };
            #else
            realpath_into(byte* p) -> bool
            {
                byte* r = realpath(p, this.pathbuf);
                switch (r == (byte*)0)
                {
                    case (true) { -> false; }
                    default {};
                };
                this.rbuf.clear();
                this.rbuf.put_str(this.pathbuf);
                -> true;
            };
            #endif;

            // Path(base) / rel into jb
            join_to(byte* base, int bn, byte* rel, int rn) -> void
            {
                this.jb.clear();
                switch (pp_is_abs(rel, rn))
                {
                    case (true) {
                    this.jb.put_n(rel, rn);
                    ->;
                }
                    default {};
                };
                this.jb.put_n(base, bn);
                switch (bn > 0)
                {
                    case (true) {
                    switch ((int)base[bn - 1] != FLUX_PP_SEP)
                    {
                        case (true) { this.jb.put(FLUX_PP_SEP); }
                        default {};
                    };
                }
                    default {};
                };
                this.jb.put_n(rel, rn);
                ->;
            };

            // (base / rel).exists() then resolve into rbuf
            try_candidate(byte* base, int bn, byte* rel, int rn) -> bool
            {
                this.join_to(base, bn, rel, rn);
                switch (!pp_exists(this.jb.mem))
                {
                    case (true) { -> false; }
                    default {};
                };
                -> this.realpath_into(this.jb.mem);
            };

            // FXPreprocessor._resolve_path_local
            resolve_local(byte* fp, int n) -> bool
            {
                byte* d;
                int k;
                switch (this.dir_stack.len > 0)
                {
                    case (true) {
                    d = this.pool.mem + this.dir_stack.arr[this.dir_stack.len - 1];
                    switch (this.try_candidate(d, pp_cstrlen(d), fp, n))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                }
                    default {};
                };

                d = this.pool.mem + this.root_dir_off;
                switch (this.try_candidate(d, pp_cstrlen(d), fp, n))
                {
                    case (true) { -> true; }
                    default {};
                };

                d = this.pool.mem + this.cwd_off;
                switch (this.try_candidate(d, pp_cstrlen(d), fp, n))
                {
                    case (true) { -> true; }
                    default {};
                };

                while (k < this.lib_dirs.len)
                {
                    d = this.pool.mem + this.lib_dirs.arr[k];
                    switch (this.try_candidate(d, pp_cstrlen(d), fp, n))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    k++;
                };
                -> false;
            };

            // FXPreprocessor._resolve_path_stdlib: srcdir/src/stdlib and its
            // runtime, functions, builtins and utility folders
            resolve_stdlib(byte* fp, int n) -> bool
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
                    switch (w > 0)
                    {
                        case (true) {
                        this.x1.put(FLUX_PP_SEP);
                        switch (w)
                        {
                            case (1) { this.x1.put_str(g"runtime\0"); }
                            case (2) { this.x1.put_str(g"functions\0"); }
                            case (3) { this.x1.put_str(g"builtins\0"); }
                            default { this.x1.put_str(g"utility\0"); };
                        };
                    }
                        default {};
                    };
                    switch (this.try_candidate(this.x1.mem, this.x1.len, fp, n))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    w++;
                };
                -> false;
            };

            // FXPreprocessor._resolve_path
            resolve_default(byte* fp, int n) -> bool
            {
                switch (pp_exists(fp))
                {
                    case (true) {
                    switch (this.realpath_into(fp))
                    {
                        case (true) { -> true; }
                        default {};
                    };
                }
                    default {};
                };
                switch (this.resolve_local(fp, n))
                {
                    case (true) { -> true; }
                    default {};
                };
                -> this.resolve_stdlib(fp, n);
            };

            // ===== #package =====

            json_ws(byte* t, int n, int p) -> int
            {
                int c = pp_at(t, n, p);
                while (c == 32 | c == 9 | c == 10 | c == 13)
                {
                    p++;
                    c = pp_at(t, n, p);
                };
                -> p;
            };

            json_hex4(byte* t, int n, int p) -> int
            {
                int v, k, c;
                while (k < 4)
                {
                    c = pp_at(t, n, p + k);
                    v = v * 16;
                    switch (c >= '0' & c <= '9')
                    {
                        case (true) { v = v + (c - 48); }
                        default {
                            switch (c >= 'A' & c <= 'F')
                            {
                                case (true) { v = v + (c - 55); }
                                default {
                                    switch (c >= 'a' & c <= 'f')
                                    {
                                        case (true) { v = v + (c - 87); }
                                        default { -> -1; };
                                    };
                                };
                            };
                        };
                    };
                    k++;
                };
                -> v;
            };

            // Reads the JSON string whose opening quote is at t[p] into js.
            // Returns the position after the closing quote, or -1.
            json_string(byte* t, int n, int p) -> int
            {
                this.js.clear();
                switch (pp_at(t, n, p) != 34)
                {
                    case (true) { -> -1; }
                    default {};
                };
                p++;
                int c, h, lo;
                while (p < n)
                {
                    c = (int)t[p];
                    switch (c == 34)
                    {
                        case (true) { -> p + 1; }
                        default {};
                    };
                    switch (c == 92)
                    {
                        case (true) {
                        p++;
                        c = pp_at(t, n, p);
                        switch (c)
                        {
                            case ('n') { this.js.put(10); }
                            case ('t') { this.js.put(9); }
                            case ('r') { this.js.put(13); }
                            case ('b') { this.js.put(8); }
                            case ('f') { this.js.put(12); }
                            case ('u')
                            {
                                h = this.json_hex4(t, n, p + 1);
                                switch (h < 0)
                                {
                                    case (true) { -> -1; }
                                    default {};
                                };
                                p = p + 4;
                                switch (h >= 0xD800 & h <= 0xDBFF)
                                {
                                    case (true) {
                                    switch (pp_at(t, n, p + 1) == 92 & pp_at(t, n, p + 2) == 'u')
                                    {
                                        case (true) {
                                        lo = this.json_hex4(t, n, p + 3);
                                        switch (lo >= 0xDC00 & lo <= 0xDFFF)
                                        {
                                            case (true) {
                                            h = 0x10000 + (h - 0xD800) * 0x400 + (lo - 0xDC00);
                                            p = p + 6;
                                        }
                                            default {};
                                        };
                                    }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                                switch (h < 0x80)
                                {
                                    case (true) { this.js.put(h); }
                                    default {
                                        switch (h < 0x800)
                                        {
                                            case (true) {
                                    this.js.put(0xC0 + h / 64);
                                    this.js.put(0x80 + h % 64);
                                }
                                            default {
                                                switch (h < 0x10000)
                                                {
                                                    case (true) {
                                    this.js.put(0xE0 + h / 4096);
                                    this.js.put(0x80 + (h / 64) % 64);
                                    this.js.put(0x80 + h % 64);
                                }
                                                    default {
                                    this.js.put(0xF0 + h / 262144);
                                    this.js.put(0x80 + (h / 4096) % 64);
                                    this.js.put(0x80 + (h / 64) % 64);
                                    this.js.put(0x80 + h % 64);
                                };
                                                };
                                            };
                                        };
                                    };
                                };
                            }
                            default
                            {
                                switch (c < 0)
                                {
                                    case (true) { -> -1; }
                                    default { this.js.put(c); };
                                };
                            };
                        };
                        p++;
                        continue;
                    }
                        default {};
                    };
                    this.js.put(c);
                    p++;
                };
                -> -1;
            };

            // Position after the JSON value starting at t[p], or -1
            json_skip(byte* t, int n, int p) -> int
            {
                p = this.json_ws(t, n, p);
                int c = pp_at(t, n, p);
                int depth;
                switch (c == 34)
                {
                    case (true) { -> this.json_string(t, n, p); }
                    default {};
                };
                switch (c == '{' | c == '[')
                {
                    case (true) {
                    depth = 0;
                    while (p < n)
                    {
                        c = (int)t[p];
                        switch (c == 34)
                        {
                            case (true) {
                            p = this.json_string(t, n, p);
                            switch (p < 0)
                            {
                                case (true) { -> -1; }
                                default {};
                            };
                            continue;
                        }
                            default {};
                        };
                        switch (c == '{' | c == '[')
                        {
                            case (true) { depth++; }
                            default {};
                        };
                        switch (c == '}' | c == ']')
                        {
                            case (true) {
                            depth--;
                            switch (depth == 0)
                            {
                                case (true) { -> p + 1; }
                                default {};
                            };
                        }
                            default {};
                        };
                        p++;
                    };
                    -> -1;
                }
                    default {};
                };
                while (p < n)
                {
                    c = (int)t[p];
                    switch (c == ',' | c == '}' | c == ']' | c == 32 | c == 9 | c == 10 | c == 13)
                    {
                        case (true) { break; }
                        default {};
                    };
                    p++;
                };
                -> p;
            };

            // Scans the JSON object at t[p] for the keys "entries" and "entrypoint".
            // Sets jv to the string value of "entrypoint" when present as a string.
            // want_entries = 1 also returns the offset of the "entries" value in this.pc_off
            // (-1 when absent). Returns 0 on a malformed object.
            json_object(byte* t, int n, int p, int want_entries) -> int
            {
                int vs, nx;
                bool is_ep, is_en;
                this.jv.clear();
                this.pc_off = -1;
                p = this.json_ws(t, n, p);
                switch (pp_at(t, n, p) != '{')
                {
                    case (true) { -> 0; }
                    default {};
                };
                p++;
                while (true)
                {
                    p = this.json_ws(t, n, p);
                    switch (pp_at(t, n, p) == '}')
                    {
                        case (true) { -> 1; }
                        default {};
                    };
                    switch (pp_at(t, n, p) == ',')
                    {
                        case (true) {
                        p++;
                        continue;
                    }
                        default {};
                    };
                    p = this.json_string(t, n, p);
                    switch (p < 0)
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    is_ep = this.js.len == 10 & pp_eq(this.js.mem, g"entrypoint\0", 10);
                    is_en = this.js.len == 7 & pp_eq(this.js.mem, g"entries\0", 7);
                    p = this.json_ws(t, n, p);
                    switch (pp_at(t, n, p) != ':')
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                    p = this.json_ws(t, n, p + 1);
                    vs = p;
                    switch (is_ep)
                    {
                        case (true) {
                        this.jv.clear();
                        switch (pp_at(t, n, p) == 34)
                        {
                            case (true) {
                            nx = this.json_string(t, n, p);
                            switch (nx < 0)
                            {
                                case (true) { -> 0; }
                                default {};
                            };
                            this.jv.put_n(this.js.mem, this.js.len);
                            p = nx;
                            continue;
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (is_en)
                    {
                        case (true) {
                        this.pc_off = vs;
                    }
                        default {};
                    };
                    p = this.json_skip(t, n, p);
                    switch (p < 0)
                    {
                        case (true) { -> 0; }
                        default {};
                    };
                };
                -> 0;
            };

            // FXPreprocessor._process_package. name is name_len bytes at text + name_off.
            process_package(byte* text, int name_off, int name_len) -> bool
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
                switch (!pp_exists(this.x2.mem))
                {
                    case (true) {
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' not found in \0");
                    this.errb.put_n(this.x1.mem, w);
                    -> false;
                }
                    default {};
                };

                this.x2.clear();
                this.x2.put_n(this.x1.mem, this.x1.len);
                this.x2.put(FLUX_PP_SEP);
                this.x2.put_str(g"package.json\0");
                switch (!pp_exists(this.x2.mem))
                {
                    case (true) {
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' is missing package.json\0");
                    -> false;
                }
                    default {};
                };

                ok2 = man.load_file(this.x2.mem);
                switch (ok2 < 0)
                {
                    case (true) {
                    this.e_begin(PPError.IO);
                    this.errb.put_str(g"[PREPROCESSOR] Could not read \0");
                    this.errb.put_n(this.x2.mem, this.x2.len);
                    -> false;
                }
                    default {};
                };

                // entries = manifest.get("entries", manifest)
                switch (this.json_object(man.mem, man.len, 0, 1) == 0)
                {
                    case (true) {
                    this.e_begin(PPError.KEY);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' package.json is not a valid JSON object\0");
                    -> false;
                }
                    default {};
                };
                en_off = this.pc_off;
                switch (en_off >= 0)
                {
                    case (true) {
                    switch (this.json_object(man.mem, man.len, en_off, 0) == 0)
                    {
                        case (true) {
                        this.jv.clear();
                    }
                        default {};
                    };
                }
                    default {};
                };

                switch (this.jv.len == 0)
                {
                    case (true) {
                    this.e_begin(PPError.KEY);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' package.json has no 'entrypoint' field\0");
                    -> false;
                }
                    default {};
                };

                // (package_dir / entrypoint)
                this.join_to(this.x1.mem, this.x1.len, this.jv.mem, this.jv.len);
                switch (!pp_exists(this.jb.mem))
                {
                    case (true) {
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' entrypoint '\0");
                    this.errb.put_n(this.jv.mem, this.jv.len);
                    this.errb.put_str(g"' not found\0");
                    -> false;
                }
                    default {};
                };
                switch (!this.realpath_into(this.jb.mem))
                {
                    case (true) {
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"[PREPROCESSOR] Package '\0");
                    this.errb.put_n(text + name_off, name_len);
                    this.errb.put_str(g"' entrypoint '\0");
                    this.errb.put_n(this.jv.mem, this.jv.len);
                    this.errb.put_str(g"' not found\0");
                    -> false;
                }
                    default {};
                };

                switch (this.processed.find(this.rbuf.mem, this.rbuf.len) >= 0)
                {
                    case (true) { -> true; }
                    default {};
                };

                switch (this.verbose)
                {
                    case (true) {
                    this.tmp.clear();
                    this.tmp.put_str(g"[PREPROCESSOR] Package import: \0");
                    this.tmp.put_n(text + name_off, name_len);
                    this.tmp.put_str(g" -> \0");
                    this.tmp.put_n(this.jv.mem, this.jv.len);
                    standard::io::console::println(this.tmp.mem);
                }
                    default {};
                };

                // The package directory is pushed so relative imports inside it resolve
                pk = this.pool_add(this.x1.mem, this.x1.len);
                this.dir_stack.push(pk);
                this.x2.clear();
                this.x2.put_n(this.rbuf.mem, this.rbuf.len);
                switch (!this.process_file(this.x2.mem, this.x2.len, 1))
                {
                    case (true) { -> false; }
                    default {};
                };
                this.dir_stack.pop();
                -> true;
            };

            // ===== FILES =====

            // FXPreprocessor._process_file. resolver: 0 default, 1 local, 2 stdlib.
            // fp_in must not point into the pool.
            process_file(byte* fp_in, int fp_n, int resolver) -> bool
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
                    switch (c == 92 | c == 47)
                    {
                        case (true) { c = FLUX_PP_SEP; }
                        default {};
                    };
                    this.pool.put(c);
                    k++;
                };
                this.pool.put(0);

                switch (resolver)
                {
                    case (1) { found = this.resolve_local(this.pool.mem + fp_off, fp_n); }
                    case (2) { found = this.resolve_stdlib(this.pool.mem + fp_off, fp_n); }
                    default { found = this.resolve_default(this.pool.mem + fp_off, fp_n); };
                };

                switch (!found)
                {
                    case (true) {
                    switch (resolver == 1)
                    {
                        case (true) {
                        switch (this.resolve_stdlib(this.pool.mem + fp_off, fp_n))
                        {
                            case (true) {
                            this.vline(g"[PREPROCESSOR] Could not find local import: \0", this.pool.mem + fp_off, fp_n, g"\0");
                            this.vline(g"#import \"\0", this.pool.mem + fp_off, fp_n, g"\";\0");
                            standard::io::console::println(g"--------^\0");
                            this.vline(g"#import <\0", this.pool.mem + fp_off, fp_n, g">; // try this\0");
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    this.e_begin(PPError.NOT_FOUND);
                    this.errb.put_str(g"Could not find import: \0");
                    this.errb.put_n(this.pool.mem + fp_off, fp_n);
                    -> false;
                }
                    default {};
                };

                switch (this.processed.find(this.rbuf.mem, this.rbuf.len) >= 0)
                {
                    case (true) { -> true; }
                    default {};
                };
                this.processed.intern(this.rbuf.mem, this.rbuf.len);
                fid = this.files.len;
                path_off = this.pool_add(this.rbuf.mem, this.rbuf.len);
                this.files.push(path_off);
                pl = pp_parent_len(this.rbuf.mem, this.rbuf.len);
                dir_off = this.pool_add(this.rbuf.mem, pl);

                switch (this.verbose)
                {
                    case (true) {
                    this.vline(g"[PREPROCESSOR] Processing: \0", this.pool.mem + fp_off, fp_n, g"\0");
                }
                    default {};
                };

                rc = raw.load_file(this.pool.mem + path_off);
                switch (rc < 0)
                {
                    case (true) {
                    this.e_begin(PPError.IO);
                    this.errb.put_str(g"[PREPROCESSOR] Could not read file: \0");
                    this.errb.put_str(this.pool.mem + path_off);
                    -> false;
                }
                    default {};
                };
                switch (rc == 1)
                {
                    case (true) {
                    this.vline(g"[PREPROCESSOR] WARNING: '\0", this.pool.mem + path_off, pp_cstrlen(this.pool.mem + path_off),
                               g"' contains invalid UTF-8 sequences. Replacement characters (U+FFFD) have been substituted. Save the file as UTF-8 to silence this warning.\0");
                }
                    default {};
                };

                content.put_stripped(raw.mem, raw.len);
                switch (!raw.ok | !content.ok | !this.alloc_ok())
                {
                    case (true) {
                    this.e_begin(PPError.ALLOC);
                    this.errb.put_str(g"[PREPROCESSOR] allocation failed\0");
                    -> false;
                }
                    default {};
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
                    switch (hi > lo)
                    {
                        case (true) {
                        switch (pp_starts(content.mem, lo, hi, g"#import\0", 7) | pp_starts(content.mem, lo, hi, g"#package\0", 8)
                            | pp_starts(content.mem, lo, hi, g"#warn\0", 5) | pp_starts(content.mem, lo, hi, g"#stop\0", 5)
                            | pp_starts(content.mem, lo, hi, g"#def\0", 4) | pp_starts(content.mem, lo, hi, g"#dir\0", 4))
                        {
                            case (true) {
                            switch (content.mem[hi - 1] != 59)
                            {
                                case (true) {
                                pp_next_tok(content.mem, hi, lo, @ts, @te);
                                this.e_begin(PPError.SYNTAX);
                                this.errb.put_str(g"[PREPROCESSOR] \0");
                                this.errb.put_n(content.mem + ts, te - ts);
                                this.errb.put_str(g" directive missing semicolon in \0");
                                this.errb.put_n(this.pool.mem + fp_off, fp_n);
                                this.errb.put_str(g" at line \0");
                                this.errb.put_int(q + 1);
                                -> false;
                            }
                                default {};
                            };
                        }
                            default {};
                        };
                    }
                        default {};
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
                    switch (i < 0)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                };
                this.dir_stack.pop();
                this.cur_file = prev_file;
                -> true;
            };

            // ===== LINES =====

            // FXPreprocessor._process_line. Returns the next line index, or -1 on error.
            process_line(LineList* ll, int i) -> int
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

                switch (s >= e)
                {
                    case (true) {
                    this.emit_blank(this.cur_lineno);
                    -> i + 1;
                }
                    default {};
                };

                // #dir
                switch (pp_starts(text, s, e, g"#dir\0", 4))
                {
                    case (true) {
                    switch (text[e - 1] != 59)
                    {
                        case (true) {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #dir directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        -> -1;
                    }
                        default {};
                    };
                    q1 = pp_find(text, lo, hi, 34);
                    switch (q1 != -1)
                    {
                        case (true) {
                        q2 = pp_find(text, q1 + 1, hi, 34);
                        switch (q2 != -1)
                        {
                            case (true) {
                            this.tmp.clear();
                            j = q1 + 1;
                            while (j < q2)
                            {
                                k = (int)text[j];
                                switch (k == 92)
                                {
                                    case (true) { k = 47; }
                                    default {};
                                };
                                this.tmp.put(k);
                                j++;
                            };
                            have = false;
                            k = 0;
                            while (k < this.lib_dirs.len)
                            {
                                switch (pp_cstrlen(this.pool.mem + this.lib_dirs.arr[k]) == this.tmp.len)
                                {
                                    case (true) {
                                    switch (pp_eq(this.pool.mem + this.lib_dirs.arr[k], this.tmp.mem, this.tmp.len))
                                    {
                                        case (true) { have = true; }
                                        default {};
                                    };
                                }
                                    default {};
                                };
                                k++;
                            };
                            switch (!have)
                            {
                                case (true) {
                                this.lib_dirs.push(this.pool_add(this.tmp.mem, this.tmp.len));
                                switch (this.verbose)
                                {
                                    case (true) {
                                    this.x1.clear();
                                    this.x1.put_n(this.tmp.mem, this.tmp.len);
                                    this.vline(g"[PREPROCESSOR] Added library directory: \0", this.x1.mem, this.x1.len, g"\0");
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
                    this.emit_blank(this.cur_lineno);
                    -> i + 1;
                }
                    default {};
                };

                // #psub
                switch (pp_starts(text, s, e, g"#psub\0", 5))
                {
                    case (true) {
                    a = s + 5;
                    b = e;
                    pp_trim(text, @a, @b);
                    this.psb.clear();
                    this.psb.put_n(text + a, b - a);
                    more = true;
                    while (more)
                    {
                        more = false;
                        switch (this.psb.len > 0)
                        {
                            case (true) {
                            switch (this.psb.mem[this.psb.len - 1] == '#')
                            {
                                case (true) { more = true; }
                                default {};
                            };
                        }
                            default {};
                        };
                        switch (!more)
                        {
                            case (true) { break; }
                            default {};
                        };
                        this.psb.pop();
                        i++;
                        switch (i >= ll.n)
                        {
                            case (true) { break; }
                            default {};
                        };
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
                    switch (paren_open == -1)
                    {
                        case (true) {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #psub missing parameter list at line \0");
                        this.errb.put_int(i + 1);
                        -> -1;
                    }
                        default {};
                    };
                    name_off = a;
                    name_len = paren_open;
                    pp_trim(this.psb.mem, @name_off, @name_len);
                    paren_close = pp_find(this.psb.mem, paren_open, b, 41);
                    switch (paren_close == -1)
                    {
                        case (true) {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #psub unclosed parameter list at line \0");
                        this.errb.put_int(i + 1);
                        -> -1;
                    }
                        default {};
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
                            switch (this.psb.mem[k] == ',')
                            {
                                case (true) { break; }
                                default {};
                            };
                            k++;
                        };
                        ts = j;
                        te = k;
                        pp_trim(this.psb.mem, @ts, @te);
                        switch (te > ts)
                        {
                            case (true) {
                            this.pb.put_n(this.psb.mem + ts, te - ts);
                            this.pb.put(0);
                            np++;
                        }
                            default {};
                        };
                        j = k + 1;
                    };

                    body_off = paren_close + 1;
                    body_len = b;
                    pp_trim(this.psb.mem, @body_off, @body_len);

                    ent = this.psubs.intern(this.psb.mem + name_off, name_len - name_off);
                    switch (ent < 0)
                    {
                        case (true) {
                        this.e_begin(PPError.ALLOC);
                        this.errb.put_str(g"[PREPROCESSOR] allocation failed\0");
                        -> -1;
                    }
                        default {};
                    };
                    this.psubs.set_val(ent, this.psb.mem + body_off, body_len - body_off);
                    this.psubs.set_params(ent, this.pb.mem, this.pb.len, np);

                    switch (this.verbose)
                    {
                        case (true) {
                        this.x1.clear();
                        this.x1.put_n(this.psb.mem + name_off, name_len - name_off);
                        this.x1.put(40);
                        k = 0;
                        j = 0;
                        while (j < np)
                        {
                            switch (j > 0)
                            {
                                case (true) { this.x1.put_str(g", \0"); }
                                default {};
                            };
                            this.x1.put_str(this.pb.mem + k);
                            k = k + pp_cstrlen(this.pb.mem + k) + 1;
                            j++;
                        };
                        this.x1.put_str(g") = \0");
                        this.x1.put_n(this.psb.mem + body_off, body_len - body_off);
                        this.vline(g"[PREPROCESSOR] Defined PSUB: \0", this.x1.mem, this.x1.len, g"\0");
                    }
                        default {};
                    };

                    this.emit_blank(this.cur_lineno);
                    -> i + 1;
                }
                    default {};
                };

                // #def
                switch (pp_starts(text, s, e, g"#def\0", 4))
                {
                    case (true) {
                    semi = pp_find(text, lo, hi, 59);
                    switch (semi == -1)
                    {
                        case (true) { semi = hi; }
                        default {};
                    };
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
                        switch (nx < 0)
                        {
                            case (true) { break; }
                            default {};
                        };
                        switch (tcount == 1)
                        {
                            case (true) {
                            name_off = ts;
                            name_len = te;
                        }
                            default {};
                        };
                        switch (tcount >= 2)
                        {
                            case (true) {
                            switch (tcount > 2)
                            {
                                case (true) { this.tmp.put(32); }
                                default {};
                            };
                            this.tmp.put_n(text + ts, te - ts);
                        }
                            default {};
                        };
                        tcount++;
                    };
                    switch (tcount >= 3)
                    {
                        case (true) {
                        ent = this.consts.intern(text + name_off, name_len - name_off);
                        switch (ent < 0)
                        {
                            case (true) {
                            this.e_begin(PPError.ALLOC);
                            this.errb.put_str(g"[PREPROCESSOR] allocation failed\0");
                            -> -1;
                        }
                            default {};
                        };
                        w = this.tmp.len;
                        switch (w > 0)
                        {
                            case (true) {
                            switch (this.tmp.mem[w - 1] == 59)
                            {
                                case (true) {
                                while (w > 0)
                                {
                                    switch (this.tmp.mem[w - 1] != 59)
                                    {
                                        case (true) { break; }
                                        default {};
                                    };
                                    w--;
                                };
                                a = 0;
                                b = w;
                                pp_trim(this.tmp.mem, @a, @b);
                                this.consts.set_val(ent, this.tmp.mem + a, b - a);
                            }
                                default {
                                this.consts.set_val(ent, this.tmp.mem, w);
                            };
                            };
                        }
                            default {
                            this.consts.set_val(ent, this.tmp.mem, 0);
                        };
                        };
                        switch (this.verbose)
                        {
                            case (true) {
                            this.x1.clear();
                            this.x1.put_n(text + name_off, name_len - name_off);
                            this.x1.put_str(g" = \0");
                            this.x1.put_n(this.consts.val_ptr(ent), this.consts.val_len(ent));
                            this.vline(g"[PREPROCESSOR] Defined constant: \0", this.x1.mem, this.x1.len, g"\0");
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    this.emit_blank(this.cur_lineno);
                    -> i + 1;
                }
                    default {};
                };

                // #ifnpsub, #ifpsub, #ifdef, #ifndef. Each needs a second token.
                switch (pp_starts(text, s, e, g"#ifnpsub\0", 8) | pp_starts(text, s, e, g"#ifpsub\0", 7)
                    | pp_starts(text, s, e, g"#ifdef\0", 6) | pp_starts(text, s, e, g"#ifndef\0", 7))
                {
                    case (true) {
                    nx = pp_next_tok(text, hi, lo, @ts, @te);
                    switch (nx >= 0)
                    {
                        case (true) { nx = pp_next_tok(text, hi, nx, @ts, @te); }
                        default {};
                    };
                    switch (nx >= 0)
                    {
                        case (true) {
                        switch (pp_starts(text, s, e, g"#ifnpsub\0", 8) | pp_starts(text, s, e, g"#ifpsub\0", 7))
                        {
                            case (true) {
                            k = pp_find(text, ts, te, 40);
                            switch (k != -1)
                            {
                                case (true) { te = k; }
                                default {};
                            };
                            a = ts;
                            b = te;
                            pp_trim(text, @a, @b);
                            -> this.process_conditional(ll, i, a, b - a, pp_starts(text, s, e, g"#ifnpsub\0", 8), true);
                        }
                            default {};
                        };
                        -> this.process_conditional(ll, i, ts, te - ts, pp_starts(text, s, e, g"#ifndef\0", 7), false);
                    }
                        default {};
                    };
                }
                    default {};
                };

                // #package
                switch (pp_starts(text, s, e, g"#package\0", 8))
                {
                    case (true) {
                    switch (text[e - 1] != 59)
                    {
                        case (true) {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #package directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        -> -1;
                    }
                        default {};
                    };
                    a = s + 8;
                    b = e;
                    while (b > a)
                    {
                        switch (text[b - 1] != 59)
                        {
                            case (true) { break; }
                            default {};
                        };
                        b--;
                    };
                    pp_trim(text, @a, @b);
                    j = a;
                    while (j <= b)
                    {
                        k = j;
                        while (k < b)
                        {
                            switch (text[k] == ',')
                            {
                                case (true) { break; }
                                default {};
                            };
                            k++;
                        };
                        ts = j;
                        te = k;
                        pp_trim(text, @ts, @te);
                        switch (te > ts)
                        {
                            case (true) {
                            switch (!this.process_package(text, ts, te - ts))
                            {
                                case (true) { -> -1; }
                                default {};
                            };
                        }
                            default {};
                        };
                        j = k + 1;
                    };
                    this.emit_blank(this.cur_lineno);
                    -> i + 1;
                }
                    default {};
                };

                // #import
                switch (pp_starts(text, s, e, g"#import\0", 7))
                {
                    case (true) {
                    switch (text[e - 1] != 59)
                    {
                        case (true) {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #import directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        -> -1;
                    }
                        default {};
                    };
                    a = s + 7;
                    b = e;
                    while (b > a)
                    {
                        switch (text[b - 1] != 59)
                        {
                            case (true) { break; }
                            default {};
                        };
                        b--;
                    };
                    pp_trim(text, @a, @b);
                    j = a;
                    while (j < b)
                    {
                        k = (int)text[j];
                        switch (k)
                        {
                            case ('<')
                            {
                                j++;
                                q2 = pp_find(text, j, b, '>');
                                switch (q2 == -1)
                                {
                                    case (true) {
                                    this.e_begin(PPError.SYNTAX);
                                    this.errb.put_str(g"[PREPROCESSOR] Unterminated <> in #import at line \0");
                                    this.errb.put_int(i + 1);
                                    -> -1;
                                }
                                    default {};
                                };
                                ts = j;
                                te = q2;
                                pp_trim(text, @ts, @te);
                                switch (this.verbose)
                                {
                                    case (true) { this.vline(g"[PREPROCESSOR] Stdlib import: \0", text + ts, te - ts, g"\0"); }
                                    default {};
                                };
                                switch (!this.process_file(text + ts, te - ts, 2))
                                {
                                    case (true) { -> -1; }
                                    default {};
                                };
                                j = q2 + 1;
                            }
                            case (34)
                            {
                                j++;
                                q2 = pp_find(text, j, b, 34);
                                switch (q2 == -1)
                                {
                                    case (true) {
                                    this.e_begin(PPError.SYNTAX);
                                    this.errb.put_str(g"[PREPROCESSOR] Unterminated \"\" in #import at line \0");
                                    this.errb.put_int(i + 1);
                                    -> -1;
                                }
                                    default {};
                                };
                                ts = j;
                                te = q2;
                                pp_trim(text, @ts, @te);
                                switch (this.verbose)
                                {
                                    case (true) { this.vline(g"[PREPROCESSOR] Local import: \0", text + ts, te - ts, g"\0"); }
                                    default {};
                                };
                                switch (!this.process_file(text + ts, te - ts, 1))
                                {
                                    case (true) { -> -1; }
                                    default {};
                                };
                                j = q2 + 1;
                            }
                            default
                            {
                                j++;
                            };
                        };
                    };
                    this.emit_blank(this.cur_lineno);
                    -> i + 1;
                }
                    default {};
                };

                // #warn
                switch (pp_starts(text, s, e, g"#warn\0", 5))
                {
                    case (true) {
                    switch (text[e - 1] != 59)
                    {
                        case (true) {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #warn directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        -> -1;
                    }
                        default {};
                    };
                    q1 = pp_find(text, lo, hi, 34);
                    switch (q1 != -1)
                    {
                        case (true) {
                        q2 = pp_find(text, q1 + 1, hi, 34);
                        switch (q2 != -1)
                        {
                            case (true) {
                            this.vline(g"[PREPROCESSOR] \0", text + q1 + 1, q2 - q1 - 1, g"\0");
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    this.emit_blank(this.cur_lineno);
                    -> i + 1;
                }
                    default {};
                };

                // #stop
                switch (pp_starts(text, s, e, g"#stop\0", 5))
                {
                    case (true) {
                    switch (text[e - 1] != 59)
                    {
                        case (true) {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] #stop directive missing semicolon at line \0");
                        this.errb.put_int(i + 1);
                        -> -1;
                    }
                        default {};
                    };
                    q1 = pp_find(text, lo, hi, 34);
                    switch (q1 != -1)
                    {
                        case (true) {
                        q2 = pp_find(text, q1 + 1, hi, 34);
                        switch (q2 != -1)
                        {
                            case (true) {
                            this.vline(g"[PREPROCESSOR] \0", text + q1 + 1, q2 - q1 - 1, g"\0");
                        }
                            default {};
                        };
                    }
                        default {};
                    };
                    standard::io::console::println(g"Compilation failed, preprocessor stopped by constant.\0");
                    this.e_begin(PPError.STOP);
                    -> -1;
                }
                    default {};
                };

                // #endif;
                switch (pp_starts(text, s, e, g"#endif;\0", 7))
                {
                    case (true) {
                    this.emit_blank(this.cur_lineno);
                    -> i + 1;
                }
                    default {};
                };

                // #else
                switch (e - s == 5)
                {
                    case (true) {
                    switch (pp_eq(text + s, g"#else\0", 5))
                    {
                        case (true) {
                        this.emit_blank(this.cur_lineno);
                        -> i + 1;
                    }
                        default {};
                    };
                }
                    default {};
                };

                // Regular line
                switch (!this.substitute_constants(text + lo, hi - lo))
                {
                    case (true) { -> -1; }
                    default {};
                };
                this.emit(this.sub_ptr, this.sub_len, this.cur_lineno);
                -> i + 1;
            };

            // ===== CONDITIONALS =====

            // True when branch condition (name at text + off, len n) holds
            cond_true(byte* text, int off, int n, bool invert, bool check_macros) -> bool
            {
                bool defined = false;
                int e;
                switch (check_macros)
                {
                    case (true) {
                    defined = this.psubs.find(text + off, n) >= 0;
                }
                    default {
                    e = this.consts.find(text + off, n);
                    switch (e >= 0)
                    {
                        case (true) {
                        defined = true;
                        switch (this.consts.val_len(e) == 1)
                        {
                            case (true) {
                            switch (this.consts.val_ptr(e)[0] == '0')
                            {
                                case (true) { defined = false; }
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
                switch (invert)
                {
                    case (true) { -> !defined; }
                    default {};
                };
                -> defined;
            };

            // FXPreprocessor._parse_ifdef_condition on text[lo, hi). On success the
            // name is pc_off/pc_len and the negation flag pc_inv.
            parse_condition(byte* text, int lo, int hi, int lineno) -> bool
            {
                int p, q, n, w;
                bool inv = false;
                bool ok3 = false;

                // defined(X) and !defined(X)
                p = lo;
                switch (pp_at(text, hi, p) == '!')
                {
                    case (true) {
                    inv = true;
                    p++;
                    while (true)
                    {
                        w = pp_ws_fwd(text, hi, p);
                        switch (w == 0)
                        {
                            case (true) { break; }
                            default {};
                        };
                        p = p + w;
                    };
                }
                    default {};
                };
                switch (pp_starts(text, p, hi, g"defined\0", 7))
                {
                    case (true) {
                    p = p + 7;
                    while (true)
                    {
                        w = pp_ws_fwd(text, hi, p);
                        switch (w == 0)
                        {
                            case (true) { break; }
                            default {};
                        };
                        p = p + w;
                    };
                    switch (pp_at(text, hi, p) == '(')
                    {
                        case (true) {
                        p++;
                        while (true)
                        {
                            w = pp_ws_fwd(text, hi, p);
                            switch (w == 0)
                            {
                                case (true) { break; }
                                default {};
                            };
                            p = p + w;
                        };
                        q = p;
                        while (q < hi)
                        {
                            switch (!pp_is_word((int)text[q]))
                            {
                                case (true) { break; }
                                default {};
                            };
                            q++;
                        };
                        switch (q > p)
                        {
                            case (true) {
                            n = q;
                            while (true)
                            {
                                w = pp_ws_fwd(text, hi, n);
                                switch (w == 0)
                                {
                                    case (true) { break; }
                                    default {};
                                };
                                n = n + w;
                            };
                            switch (pp_at(text, hi, n) == ')')
                            {
                                case (true) {
                                n++;
                                switch (n == hi)
                                {
                                    case (true) {
                                    this.pc_off = p;
                                    this.pc_len = q - p;
                                    this.pc_inv = inv;
                                    -> true;
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

                // plain identifier
                switch (hi > lo)
                {
                    case (true) {
                    ok3 = true;
                    p = lo;
                    while (p < hi)
                    {
                        switch (!pp_is_word((int)text[p]))
                        {
                            case (true) {
                            ok3 = false;
                            break;
                        }
                            default {};
                        };
                        p++;
                    };
                }
                    default {};
                };
                switch (ok3)
                {
                    case (true) {
                    this.pc_off = lo;
                    this.pc_len = hi - lo;
                    this.pc_inv = false;
                    -> true;
                }
                    default {};
                };

                this.e_begin(PPError.SYNTAX);
                this.errb.put_str(g"[PREPROCESSOR] Unsupported #elif condition '\0");
                this.errb.put_n(text + lo, hi - lo);
                this.errb.put_str(g"' at line \0");
                this.errb.put_int(lineno);
                this.errb.put_str(g". Only 'SYMBOL', 'defined(SYMBOL)', and '!defined(SYMBOL)' are supported.\0");
                -> false;
            };

            // FXPreprocessor._process_conditional_block. The condition name is
            // name_n bytes at ll.text + name_off. Returns the index after #endif, or -1.
            process_conditional(LineList* ll, int start_i, int name_off, int name_n, bool is_ifndef, bool check_macros) -> int
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
                switch (is_ifndef)
                {
                    case (true) { b_inv.push(1); }
                    default { b_inv.push(0); };
                };
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

                    switch (pp_starts(text, s, e, g"#ifdef\0", 6) | pp_starts(text, s, e, g"#ifndef\0", 7)
                        | pp_starts(text, s, e, g"#ifnpsub\0", 8) | pp_starts(text, s, e, g"#ifpsub\0", 7))
                    {
                        case (true) {
                        depth++;
                    }
                        default {};
                    };

                    switch (pp_starts(text, s, e, g"#endif;\0", 7))
                    {
                        case (true) {
                        depth--;
                        switch (depth == 0)
                        {
                            case (true) {
                            this.emit_blank(orig);

                            nb = b_start.len;
                            ch = -1;
                            bi = 0;
                            while (bi < nb)
                            {
                                switch (b_always.arr[bi] == 1)
                                {
                                    case (true) {
                                    ch = bi;
                                    break;
                                }
                                    default {};
                                };
                                switch (this.cond_true(text, b_name.arr[bi], b_nlen.arr[bi], b_inv.arr[bi] == 1, check_macros))
                                {
                                    case (true) {
                                    ch = bi;
                                    break;
                                }
                                    default {};
                                };
                                bi++;
                            };

                            // Excluded lines become blanks, in branch order
                            bi = 0;
                            while (bi < nb)
                            {
                                switch (bi != ch)
                                {
                                    case (true) {
                                    bs = b_start.arr[bi];
                                    be = c_off.len;
                                    switch (bi + 1 < nb)
                                    {
                                        case (true) { be = b_start.arr[bi + 1]; }
                                        default {};
                                    };
                                    j = bs;
                                    while (j < be)
                                    {
                                        this.emit_blank(c_orig.arr[j]);
                                        j++;
                                    };
                                }
                                    default {};
                                };
                                bi++;
                            };

                            switch (ch >= 0)
                            {
                                case (true) {
                                bs = b_start.arr[ch];
                                be = c_off.len;
                                switch (ch + 1 < nb)
                                {
                                    case (true) { be = b_start.arr[ch + 1]; }
                                    default {};
                                };
                                switch (be > bs)
                                {
                                    case (true) {
                                    sub.text = text;
                                    sub.off = c_off.arr + bs;
                                    sub.len = c_len.arr + bs;
                                    sub.n = be - bs;
                                    j = 0;
                                    while (j < sub.n)
                                    {
                                        this.cur_lineno = c_orig.arr[bs + j];
                                        j = this.process_line(@sub, j);
                                        switch (j < 0)
                                        {
                                            case (true) { -> -1; }
                                            default {};
                                        };
                                    };
                                }
                                    default {};
                                };
                            }
                                default {};
                            };
                            -> i + 1;
                        }
                            default {};
                        };
                        c_off.push(lo);
                        c_len.push(hi - lo);
                        c_orig.push(orig);
                        i++;
                        continue;
                    }
                        default {};
                    };

                    switch (depth == 1)
                    {
                        case (true) {
                        switch (pp_starts(text, s, e, g"#elif\0", 5))
                        {
                            case (true) {
                            switch (has_else)
                            {
                                case (true) {
                                this.e_begin(PPError.SYNTAX);
                                this.errb.put_str(g"[PREPROCESSOR] #elif after #else at line \0");
                                this.errb.put_int(i + 1);
                                -> -1;
                            }
                                default {};
                            };
                            a = s + 5;
                            b = e;
                            while (b > a)
                            {
                                switch (text[b - 1] != 59)
                                {
                                    case (true) { break; }
                                    default {};
                                };
                                b--;
                            };
                            pp_trim(text, @a, @b);
                            switch (!this.parse_condition(text, a, b, i + 1))
                            {
                                case (true) { -> -1; }
                                default {};
                            };
                            b_start.push(c_off.len);
                            b_name.push(this.pc_off);
                            b_nlen.push(this.pc_len);
                            switch (this.pc_inv)
                            {
                                case (true) { b_inv.push(1); }
                                default { b_inv.push(0); };
                            };
                            b_always.push(0);
                            this.emit_blank(orig);
                            i++;
                            continue;
                        }
                            default {};
                        };

                        w = e - s;
                        switch (pp_eq(text + s, g"#else\0", 5) & w == 5 | pp_eq(text + s, g"#else;\0", 6) & w == 6)
                        {
                            case (true) {
                            switch (has_else)
                            {
                                case (true) {
                                this.e_begin(PPError.SYNTAX);
                                this.errb.put_str(g"[PREPROCESSOR] Multiple #else in same conditional block at line \0");
                                this.errb.put_int(i + 1);
                                -> -1;
                            }
                                default {};
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
                        }
                            default {};
                        };
                    }
                        default {};
                    };

                    c_off.push(lo);
                    c_len.push(hi - lo);
                    c_orig.push(orig);
                    i++;
                };

                this.e_begin(PPError.SYNTAX);
                this.errb.put_str(g"Unclosed conditional block starting at line \0");
                this.errb.put_int(start_i + 1);
                -> -1;
            };

            // ===== MACROS AND CONSTANTS =====

            // One scan of FXPreprocessor._expand_macros over src[0, n) into mc.
            // Returns 1 when a macro was expanded, 0 when not, -1 on error.
            macro_pass(byte* src, int n) -> int
            {
                int i, j, k, c, depth, rs, re, ent, np, na, cstart, p, plen, a, b, d, ra, rb;
                bool in_str, changed;
                int str_char;
                byte* ppar;

                this.mc.clear();
                while (i < n)
                {
                    c = (int)src[i];
                    switch (!pp_is_alpha_us(c))
                    {
                        case (true) {
                        this.mc.put(c);
                        i++;
                        continue;
                    }
                        default {};
                    };

                    j = i;
                    while (j < n)
                    {
                        switch (!pp_is_word((int)src[j]))
                        {
                            case (true) { break; }
                            default {};
                        };
                        j++;
                    };

                    ent = this.psubs.find(src + i, j - i);
                    switch (ent < 0)
                    {
                        case (true) {
                        this.mc.put_n(src + i, j - i);
                        i = j;
                        continue;
                    }
                        default {};
                    };
                    switch (pp_at(src, n, j) != '(')
                    {
                        case (true) {
                        this.mc.put_n(src + i, j - i);
                        i = j;
                        continue;
                    }
                        default {};
                    };

                    // matching close paren, respecting nesting and strings
                    k = j + 1;
                    depth = 1;
                    in_str = false;
                    str_char = 0;
                    while (k < n & depth > 0)
                    {
                        c = (int)src[k];
                        switch (in_str)
                        {
                            case (true) {
                            switch (c == 92)
                            {
                                case (true) { k++; }
                                default {
                                    switch (c == str_char)
                                    {
                                        case (true) { in_str = false; }
                                        default {};
                                    };
                                };
                            };
                        }
                            default {
                            switch (c == 34 | c == 39)
                            {
                                case (true) {
                                in_str = true;
                                str_char = c;
                            }
                                default {
                                    switch (c == '(')
                                    {
                                        case (true) { depth++; }
                                        default {
                                            switch (c == ')')
                                            {
                                                case (true) { depth--; }
                                                default {};
                                            };
                                        };
                                    };
                                };
                            };
                        };
                        };
                        k++;
                    };

                    rs = j + 1;
                    re = k - 1;
                    switch (re > n)
                    {
                        case (true) { re = n; }
                        default {};
                    };
                    switch (re < rs)
                    {
                        case (true) { re = rs; }
                        default {};
                    };

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
                        switch (in_str)
                        {
                            case (true) {
                            switch (c == str_char)
                            {
                                case (true) { in_str = false; }
                                default {};
                            };
                        }
                            default {
                                switch (c == 34 | c == 39)
                                {
                                    case (true) {
                            in_str = true;
                            str_char = c;
                        }
                                    default {
                                        switch (c == '(')
                                        {
                                            case (true) { depth++; }
                                            default {
                                                switch (c == ')')
                                                {
                                                    case (true) { depth--; }
                                                    default {
                                                        switch (c == ',' & depth == 0)
                                                        {
                                                            case (true) {
                            this.aoff.push(cstart);
                            this.alen.push(p - cstart);
                            na++;
                            cstart = p + 1;
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
                        p++;
                    };
                    switch (re - cstart > 0 | na > 0)
                    {
                        case (true) {
                        this.aoff.push(cstart);
                        this.alen.push(re - cstart);
                        na++;
                    }
                        default {};
                    };

                    np = this.psubs.par_count(ent);
                    switch (na != np)
                    {
                        case (true) {
                        this.e_begin(PPError.SYNTAX);
                        this.errb.put_str(g"[PREPROCESSOR] Macro '\0");
                        this.errb.put_n(src + i, j - i);
                        this.errb.put_str(g"' expects \0");
                        this.errb.put_int(np);
                        this.errb.put_str(g" argument(s), got \0");
                        this.errb.put_int(na);
                        this.errb.put_str(g": '\0");
                        d = k;
                        switch (d > n)
                        {
                            case (true) { d = n; }
                            default {};
                        };
                        this.errb.put_n(src + i, d - i);
                        this.errb.put_str(g"'\0");
                        -> -1;
                    }
                        default {};
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

                switch (changed)
                {
                    case (true) { -> 1; }
                    default {};
                };
                -> 0;
            };

            // FXPreprocessor._expand_macros. The result is ex_ptr/ex_len, valid until
            // the next call.
            expand_macros(byte* s, int n) -> bool
            {
                int depth, rc;
                this.ex_ptr = s;
                this.ex_len = n;
                switch (this.psubs.count == 0)
                {
                    case (true) { -> true; }
                    default {};
                };
                while (true)
                {
                    switch (depth > FLUX_PP_MAX_DEPTH)
                    {
                        case (true) {
                        this.e_begin(PPError.RECURSION);
                        this.errb.put_str(g"[PREPROCESSOR] Macro expansion exceeded depth limit (64). Possible infinite recursion.\0");
                        -> false;
                    }
                        default {};
                    };
                    rc = this.macro_pass(this.ex_ptr, this.ex_len);
                    switch (rc < 0)
                    {
                        case (true) { -> false; }
                        default {};
                    };
                    switch (rc == 0)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                    this.ma.clear();
                    this.ma.put_n(this.mc.mem, this.mc.len);
                    this.ex_ptr = this.ma.mem;
                    this.ex_len = this.ma.len;
                    depth++;
                };
                -> true;
            };

            // Appends token s[ts, te) to sc, replaced by its constant when it names one
            flush_token(byte* s, int ts, int te, bool in_quotes) -> void
            {
                int e = -1;
                int w, a, b;
                byte* v;
                switch (!in_quotes)
                {
                    case (true) { e = this.consts.find(s + ts, te - ts); }
                    default {};
                };
                switch (e < 0)
                {
                    case (true) {
                    this.sc.put_n(s + ts, te - ts);
                    ->;
                }
                    default {};
                };
                v = this.consts.val_ptr(e);
                w = this.consts.val_len(e);
                switch (w > 0)
                {
                    case (true) {
                    switch (v[w - 1] == 59)
                    {
                        case (true) {
                        while (w > 0)
                        {
                            switch (v[w - 1] != 59)
                            {
                                case (true) { break; }
                                default {};
                            };
                            w--;
                        };
                        a = 0;
                        b = w;
                        pp_trim(v, @a, @b);
                        this.sc.put_n(v + a, b - a);
                        ->;
                    }
                        default {};
                    };
                }
                    default {};
                };
                this.sc.put_n(v, w);
                ->;
            };

            // FXPreprocessor._substitute_constants. The result is sub_ptr/sub_len,
            // valid until the next call.
            substitute_constants(byte* s, int n) -> bool
            {
                int i, w, ts, a, b, c;
                bool in_quotes;
                switch (!this.expand_macros(s, n))
                {
                    case (true) { -> false; }
                    default {};
                };

                byte* t = this.ex_ptr;
                int tn = this.ex_len;
                this.sub_ptr = t;
                this.sub_len = tn;
                switch (tn == 0)
                {
                    case (true) { -> true; }
                    default {};
                };
                a = 0;
                b = tn;
                pp_trim(t, @a, @b);
                switch (b - a == 1)
                {
                    case (true) {
                    switch (t[a] == 59)
                    {
                        case (true) { -> true; }
                        default {};
                    };
                }
                    default {};
                };

                this.sc.clear();
                ts = -1;
                in_quotes = false;
                while (i < tn)
                {
                    c = (int)t[i];
                    switch (c == 34)
                    {
                        case (true) {
                        in_quotes = !in_quotes;
                        switch (ts < 0)
                        {
                            case (true) { ts = i; }
                            default {};
                        };
                        i++;
                        continue;
                    }
                        default {};
                    };
                    w = pp_ws_fwd(t, tn, i);
                    switch (w == 0)
                    {
                        case (true) {
                        switch (pp_is_delim(c))
                        {
                            case (true) { w = 1; }
                            default {};
                        };
                    }
                        default {};
                    };
                    switch (w > 0)
                    {
                        case (true) {
                        switch (ts >= 0)
                        {
                            case (true) {
                            this.flush_token(t, ts, i, in_quotes);
                            ts = -1;
                        }
                            default {};
                        };
                        this.sc.put_n(t + i, w);
                        i = i + w;
                    }
                        default {
                        switch (ts < 0)
                        {
                            case (true) { ts = i; }
                            default {};
                        };
                        i++;
                    };
                    };
                };
                switch (ts >= 0)
                {
                    case (true) { this.flush_token(t, ts, tn, in_quotes); }
                    default {};
                };

                this.sub_ptr = this.sc.mem;
                this.sub_len = this.sc.len;
                -> true;
            };

            // ===== DRIVER =====

            // FXPreprocessor.process. The combined source is text_ptr()/text_len().
            process() -> bool
            {
                int pl, iteration, ls, le;
                bool replaced, first;

                switch (this.err_kind != 0)
                {
                    case (true) { -> false; }
                    default {};
                };

                switch (this.realpath_into(this.srcpath.mem))
                {
                    case (true) {
                    pl = pp_parent_len(this.rbuf.mem, this.rbuf.len);
                    this.root_dir_off = this.pool_add(this.rbuf.mem, pl);
                }
                    default {
                    pl = pp_parent_len(this.srcpath.mem, this.srcpath.len);
                    this.root_dir_off = this.pool_add(this.srcpath.mem, pl);
                };
                };

                switch (!this.process_file(this.srcpath.mem, this.srcpath.len, 0))
                {
                    case (true) { -> false; }
                    default {};
                };

                replaced = true;
                while (replaced)
                {
                    iteration++;
                    switch (this.verbose)
                    {
                        case (true) {
                        standard::io::console::print(g"[PREPROCESSOR] constant substitution passes: \0");
                        standard::io::console::println(iteration);
                    }
                        default {};
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
                            switch (this.outb.mem[le] == 10)
                            {
                                case (true) { break; }
                                default {};
                            };
                            le++;
                        };
                        switch (!this.substitute_constants(this.outb.mem + ls, le - ls))
                        {
                            case (true) { -> false; }
                            default {};
                        };
                        switch (!first)
                        {
                            case (true) { this.passb.put(10); }
                            default {};
                        };
                        first = false;
                        this.passb.put_n(this.sub_ptr, this.sub_len);
                        switch (this.sub_len != le - ls)
                        {
                            case (true) {
                            replaced = true;
                        }
                            default {
                                switch (!pp_eq(this.sub_ptr, this.outb.mem + ls, this.sub_len))
                                {
                                    case (true) {
                            replaced = true;
                        }
                                    default {};
                                };
                            };
                        };
                        switch (le >= this.outb.len)
                        {
                            case (true) { break; }
                            default {};
                        };
                        ls = le + 1;
                    };
                    this.outb.clear();
                    this.outb.put_n(this.passb.mem, this.passb.len);
                };

                switch (this.verbose)
                {
                    case (true) {
                    switch (iteration > 1)
                    {
                        case (true) {
                        standard::io::console::print(g"[PREPROCESSOR] Completed after \0");
                        standard::io::console::print(iteration);
                        standard::io::console::println(g" constant passes.\0");
                    }
                        default {
                        standard::io::console::print(g"[PREPROCESSOR] Completed after \0");
                        standard::io::console::print(iteration);
                        standard::io::console::println(g" constant pass.\0");
                    };
                    };
                    standard::io::console::print(g"[PREPROCESSOR] Processed \0");
                    standard::io::console::print(this.processed.count);
                    standard::io::console::println(g" file(s)\0");
                }
                    default {};
                };

                switch (!this.alloc_ok())
                {
                    case (true) {
                    this.e_begin(PPError.ALLOC);
                    this.errb.put_str(g"[PREPROCESSOR] allocation failed\0");
                    -> false;
                }
                    default {};
                };
                -> true;
            };
        };
    };
};

#endif;
