// Author: Karac V. Thweatt

// streams.fx - Byte stream traits and generic stream algorithms for Flux.
//
//   trait Reader   read(byte* buf, i64 n) -> i64     bytes read, 0 at end, -1 on error
//   trait Writer   write(byte* buf, i64 n) -> i64    bytes written, -1 on error
//                  flush() -> bool
//
// Objects
//   FileReader / FileWriter    over a C FILE* (open by path, or wrap stdin/stdout/stderr)
//   MemReader                  reads from a caller-owned byte buffer
//   MemWriter                  growable in-memory sink (owns its buffer)
//   BufReader<R>               buffered wrapper adding read_byte / read_line
//
// Generic algorithms (work with any object that applies the traits)
//   read_all<R>(R* r, i64* out_len) -> byte*      null-terminated, release with ffree
//   copy<R, W>(R* r, W* w) -> i64                 bytes copied, -1 on error
//   write_str<W>(W* w, byte* s) -> i64
//
// Dependencies: standard::types, standard::memory, standard::fs

#ifndef FLUX_STANDARD_TYPES
#import <types.fx>;
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import <memory.fx>;
#endif;

#ifndef FLUX_STANDARD_FILESYSTEM
#import <filesystem.fx>;
#endif;

#ifndef FLUX_STANDARD_STREAMS
#def FLUX_STANDARD_STREAMS 1;

#ifdef __LINUX__
extern
{
    !!
        fflush(void*)           -> int,
        fdopen(int, byte*)      -> void*;
};
#endif;

#ifdef __WINDOWS__
extern
{
    !!
        fflush(void*)           -> int,
        _fdopen(int, byte*)     -> void*;
};
#endif;

namespace standard
{
    namespace streams
    {
        trait Reader
        {
            read(byte* buf, i64 n) -> i64;
        };

        trait Writer
        {
            write(byte* buf, i64 n) -> i64,
            flush() -> bool;
        };

        // ====================================================================
        // FILE* backed streams
        // ====================================================================

        _open_fd(int fd, byte* mode) -> void*
        {
            #ifdef __LINUX__
            -> fdopen(fd, mode);
            #endif;
            #ifdef __WINDOWS__
            -> _fdopen(fd, mode);
            #endif;
        };

        Reader
        object FileReader
        {
            void* fp;
            bool  owned;

            // Unopened; follow with attach(fd).
            __init() -> this
            {
                this.fp = (void*)STDLIB_GVP;
                this.owned = false;
                -> this;
            };

            // Open by path. valid() is false when the open failed.
            __init(byte* path) -> this
            {
                this.fp = fopen(path, "rb");
                this.owned = true;
                -> this;
            };

            __exit() -> void
            {
                if (this.owned & this.fp != (void*)STDLIB_GVP) { fclose(this.fp); };
                this.fp = (void*)STDLIB_GVP;
                ->;
            };

            __expr() -> FileReader* { -> this; };

            // Wrap an existing descriptor (0 = stdin). The descriptor stays open on __exit.
            attach(int fd) -> bool
            {
                this.fp = _open_fd(fd, "rb");
                this.owned = false;
                -> this.fp != (void*)STDLIB_GVP;
            };

            valid() -> bool { -> this.fp != (void*)STDLIB_GVP; };

            read(byte* buf, i64 n) -> i64
            {
                if (this.fp == (void*)STDLIB_GVP) { -> (i64)-1; };
                -> (i64)fread((void*)buf, (ulong)1, (ulong)n, this.fp);
            };
        };

        Writer
        object FileWriter
        {
            void* fp;
            bool  owned;

            // Unopened; follow with attach(fd).
            __init() -> this
            {
                this.fp = (void*)STDLIB_GVP;
                this.owned = false;
                -> this;
            };

            // Open by path, truncating. Pass append = true to append instead.
            __init(byte* path, bool append) -> this
            {
                this.fp = fopen(path, append ? "ab" : "wb");
                this.owned = true;
                -> this;
            };

            __exit() -> void
            {
                if (this.fp != (void*)STDLIB_GVP)
                {
                    fflush(this.fp);
                    if (this.owned) { fclose(this.fp); };
                };
                this.fp = (void*)STDLIB_GVP;
                ->;
            };

            __expr() -> FileWriter* { -> this; };

            // Wrap an existing descriptor (1 = stdout, 2 = stderr).
            attach(int fd) -> bool
            {
                this.fp = _open_fd(fd, "wb");
                this.owned = false;
                -> this.fp != (void*)STDLIB_GVP;
            };

            valid() -> bool { -> this.fp != (void*)STDLIB_GVP; };

            write(byte* buf, i64 n) -> i64
            {
                if (this.fp == (void*)STDLIB_GVP) { -> (i64)-1; };
                -> (i64)fwrite((void*)buf, (ulong)1, (ulong)n, this.fp);
            };

            flush() -> bool
            {
                if (this.fp == (void*)STDLIB_GVP) { -> false; };
                -> fflush(this.fp) == 0;
            };
        };

        // ====================================================================
        // Memory streams
        // ====================================================================

        Reader
        object MemReader
        {
            byte* src;
            i64   n,
                  pos;

            __init(byte* buf, i64 len) -> this
            {
                this.src = buf;
                this.n   = len;
                this.pos = 0;
                -> this;
            };

            __exit() -> void { ->; };

            __expr() -> MemReader* { -> this; };

            remaining() -> i64 { -> this.n - this.pos; };

            read(byte* buf, i64 cnt) -> i64
            {
                i64 left = this.n - this.pos;
                i64 k = cnt < left ? cnt : left;
                i64 i;
                while (i < k)
                {
                    buf[i] = this.src[this.pos + i];
                    i++;
                };
                this.pos = this.pos + k;
                -> k;
            };
        };

        Writer
        object MemWriter
        {
            byte* buf;
            i64   n,
                  cap;

            __init() -> this
            {
                this.cap = 64;
                this.buf = (byte*)fmalloc((size_t)this.cap);
                this.n   = 0;
                this.buf[0] = (byte)0;
                -> this;
            };

            __exit() -> void
            {
                if (this.buf != (byte*)STDLIB_GVP) { ffree(this.buf); };
                this.buf = (byte*)STDLIB_GVP;
                ->;
            };

            __expr() -> MemWriter* { -> this; };

            // Contents so far, always null-terminated. Owned by the writer.
            bytes() -> byte* { -> this.buf; };

            len() -> i64 { -> this.n; };

            reset() -> void
            {
                this.n = 0;
                this.buf[0] = (byte)0;
                ->;
            };

            write(byte* src, i64 cnt) -> i64
            {
                if (cnt < 0) { -> (i64)-1; };
                if (this.n + cnt + 1 > this.cap)
                {
                    i64 nc = this.cap;
                    while (nc < this.n + cnt + 1) { nc = nc * 2; };
                    byte* nb = (byte*)fmalloc((size_t)nc);
                    i64 i;
                    while (i < this.n)
                    {
                        nb[i] = this.buf[i];
                        i++;
                    };
                    ffree(this.buf);
                    this.buf = nb;
                    this.cap = nc;
                };
                i64 j;
                while (j < cnt)
                {
                    this.buf[this.n + j] = src[j];
                    j++;
                };
                this.n = this.n + cnt;
                this.buf[this.n] = (byte)0;
                -> cnt;
            };

            flush() -> bool { -> true; };
        };

        // ====================================================================
        // Generic algorithms
        // ====================================================================

        // Plain helpers: allocation is kept out of the template bodies below.
        bufalloc(i64 cap) -> byte* { -> (byte*)fmalloc((size_t)cap); };

        bufgrow(byte* old, i64 len, i64 newcap) -> byte*
        {
            byte* nb = (byte*)fmalloc((size_t)newcap);
            i64 i;
            while (i < len)
            {
                nb[i] = old[i];
                i++;
            };
            ffree(old);
            -> nb;
        };

        // Read until end of stream. The result is null-terminated and owned by the caller.
        read_all<R>(R* r, i64* out_len) -> byte*
        {
            i64 cap = 256,
                len = 0,
                got;
            byte* buf = standard::streams::bufalloc(cap);
            while (true)
            {
                if (len + 128 + 1 > cap)
                {
                    i64 nc = cap * 2;
                    buf = standard::streams::bufgrow(buf, len, nc);
                    cap = nc;
                };
                got = r.read(buf + len, cap - len - 1);
                if (got <= 0) { break; };
                len = len + got;
            };
            buf[len] = (byte)0;
            *out_len = len;
            -> buf;
        };

        write_all<W>(W* w, byte* b, i64 n) -> bool
        {
            i64 done,
                k;
            while (done < n)
            {
                k = w.write(b + done, n - done);
                if (k <= 0) { -> false; };
                done = done + k;
            };
            -> true;
        };

        write_str<W>(W* w, byte* s) -> i64
        {
            i64 n;
            while (s[n] != (byte)0) { n++; };
            i64 done,
                k;
            while (done < n)
            {
                k = w.write(s + done, n - done);
                if (k <= 0) { -> (i64)-1; };
                done = done + k;
            };
            -> n;
        };

        // Copy until the reader is exhausted. Returns bytes copied, or -1 on error.
        copy<R, W>(R* r, W* w) -> i64
        {
            byte[4096] tmp;
            i64 total, got, done, k;
            while (true)
            {
                got = r.read(@tmp[0], (i64)4096);
                if (got < 0) { -> (i64)-1; };
                if (got == 0) { break; };
                done = 0;
                while (done < got)
                {
                    k = w.write(@tmp[0] + done, got - done);
                    if (k <= 0) { -> (i64)-1; };
                    done = done + k;
                };
                total = total + got;
            };
            -> total;
        };

        // ====================================================================
        // BufReader<R>
        // ====================================================================

        object BufReader<R>
        {
            R*       src;
            byte*    buf;
            i64      pos,
                     fill;

            __init(R* inner) -> this
            {
                this.src  = inner;
                this.buf  = (byte*)fmalloc((size_t)4096);
                this.pos  = 0;
                this.fill = 0;
                -> this;
            };

            __exit() -> void
            {
                if (this.buf != (byte*)STDLIB_GVP) { ffree(this.buf); };
                this.buf = (byte*)STDLIB_GVP;
                ->;
            };

            __expr() -> BufReader<R>* { -> this; };

            // Next byte into *out. False at end of stream.
            read_byte(byte* out) -> bool
            {
                if (this.pos >= this.fill)
                {
                    i64 got = this.src.read(this.buf, (i64)4096);
                    if (got <= 0) { -> false; };
                    this.pos = 0;
                    this.fill = got;
                };
                *out = this.buf[this.pos];
                this.pos = this.pos + 1;
                -> true;
            };

            read(byte* dst, i64 n) -> i64
            {
                i64 k;
                byte c;
                while (k < n)
                {
                    if (!this.read_byte(@c)) { break; };
                    dst[k] = c;
                    k++;
                };
                -> k;
            };

            // Reads one line (without the line terminator, "\r\n" and "\n" both accepted)
            // into out, truncating to cap - 1 bytes and null-terminating.
            // Returns the line length, or -1 at end of stream with nothing read.
            read_line(byte* out, int cap) -> int
            {
                int n;
                bool any;
                byte c;
                while (this.read_byte(@c))
                {
                    any = true;
                    if (c == (byte)10) { break; };
                    if (n < cap - 1)
                    {
                        out[n] = c;
                        n++;
                    };
                };
                if (!any) { out[0] = (byte)0; -> -1; };
                if (n > 0 & out[n - 1] == (byte)13) { n--; };
                out[n] = (byte)0;
                -> n;
            };
        };
    };
};

#endif;
