// Author: Karac V. Thweatt
//
// fxc.fx - Flux compiler entrypoint (bootstrap stage 1: lexer only)
//
// Usage:
//     fxc file.fx --lex          token total
//     fxc file.fx --lex -v       detailed token listing
//     fxc file.fx --lex -c       token count summary
//     fxc file.fx --lex -v -c    both
//
#import <standard.fx>;
#import <runtime/ffifio.fx>;
#import "src/compiler/flexer.fx";
#import "src/compiler/fpreprocess.fx";
#import "src/compiler/ferrors.fx";
#import "src/compiler/fast.fx";
#import "src/compiler/fparser.fx";
#import "src/compiler/ftypesys.fx";
#import "src/compiler/fcheck.fx";
#import "src/compiler/ftyper.fx";
#import "src/compiler/f_llvmir.fx";
#import "src/compiler/fcodegen.fx";
#import "src/compiler/fdce.fx";
#import "src/compiler/funused.fx";
#import "src/compiler/fborrow.fx";
#import "src/compiler/fasync.fx";
#import "src/compiler/feffects.fx";
#import "src/compiler/fmodules.fx";

using standard::io::console;
using standard::io::file;
using flux::lexer;
using flux::preprocessor;
using flux::errors;
using flux::ast;
using flux::parser;
using flux::types;
using flux::check;
using flux::typer;
using flux::ir;
using flux::codegen;
using flux::dce;
using flux::borrow;
using flux::asyncl;
using flux::effects;
using flux::modules;

print_version()->void;

usage() -> void
{
    print_version();
    println("Usage: fxc <input.fx> [options]\0");
    println("\0");
    println("  (no stage)        Full chain: write build/<name>/<name>.ll, LLVM IR to .o, then link\n\0");
    println("Options:\0");
    println("  -o <output>       Output binary name (second positional argument also works)\0");
    println("  -E, --preprocess  Run the preprocessor and print the result\0");
    println("  --lex             Preprocess, then run the lexer and report tokens\0");
    println("  --parse           Preprocess, lex, then run the bootstrap parser\0");
    println("  --dump            Parse, then print the syntax tree\0");
    println("  --check           Parse, then declare symbols and run the type check pass\0");
    println("  --emit-ll         Parse, declare symbols, then print LLVM IR (types and declarations)\0");
    println("  -v, --verbose     Show detailed token information\0");
    println("  -c, --count       Show token count summary\0");
    println("  --warn-as-error   Treat all warnings as errors\0");
    print();
    println("Additional:\0");
    println("  --effects           Check the program's effects");
    println("  --effects-warn      Emit errors as warnings, permits compilation\0");
    println("  --borrowcheck       Borrow check the program\0");
    println("  --borrowcheck-warn  Emit errors as warnings, permits compilation\0");
    ->;
};

// True when the null terminated argument a is exactly lit[0..n)
arg_eq(byte* a, byte* lit, int n) -> bool
{
    if (!bytes_eq(a, lit, n)) { -> false; };
    -> a[n] == 0;
};

// Reads the whole file into a heap buffer. Returns null on failure.
// *out_len receives the number of bytes read.
read_source(byte* path, int* out_len) -> byte*
{
    void* f = fopen(path, "rb\0");
    if (f == (void*)0) { -> (byte*)0; };

    fseek(f, 0, SEEK_END);
    int size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0)
    {
        fclose(f);
        -> (byte*)0;
    };

    byte* buf = (byte*)fmalloc((u64)size + (u64)1);
    if (buf == (byte*)0)
    {
        fclose(f);
        -> (byte*)0;
    };

    int n = fread(buf, 1, size, f);
    fclose(f);
    if (n < 0)
    {
        ffree(buf);
        -> (byte*)0;
    };
    buf[n] = (byte)0;
    *out_len = n;
    -> buf;
};

// Text mode newline translation: \r\n and lone \r both become \n.
// Works in place and returns the new length.
normalize_newlines(byte* b, int n) -> int
{
    int r, w;
    while (r < n)
    {
        switch (b[r] == 13)
        {
            case (true) {
            b[w] = (byte)10;
            w++;
            if (r + 1 < n & b[r + 1] == 10) { r++; };
        }
            default {
            b[w] = b[r];
            w++;
        };
        };
        r++;
    };
    b[w] = (byte)0;
    -> w;
};

#ifndef __WINDOWS__
extern
{
    def !!
        system(byte*) -> int,
        isatty(int) -> int,
        getcwd(byte*, u64) -> byte*;
};
#endif;

#ifdef __WINDOWS__
// Console code page, so the UTF-8 bytes of the log symbols display correctly
extern
{
    def !!
        SetConsoleOutputCP(u32) -> int,
        GetConsoleOutputCP() -> u32,
        _isatty(int) -> int,
        _getcwd(byte*, int) -> byte*;
};
#endif;

// ---------------------------------------------------------------------------
// Logger (mirrors flogger.py: the whole line is wrapped in the level color)
//     [INFO] blue 94, [WARN] yellow 93, [ERROR] red 91, success green 92
// ---------------------------------------------------------------------------
global bool LOG_ON;
global bool LOG_COLOR;

// UTF-8 log symbols are built from bytes: the base compiler encodes string literals as ASCII.
// 1 = arrow (U+25BA), 2 = check mark (U+2713), 3 = cross mark (U+2717)
print_sym(int which) -> void
{
    Buf sb;
    sb.__init();
    defer sb.__exit();
    sb.put(226);
    switch (which)
    {
        case (1)
        {
            sb.put(150);
            sb.put(186);
        }
        case (2)
        {
            sb.put(156);
            sb.put(147);
        }
        default
        {
            sb.put(156);
            sb.put(151);
        };
    };
    sb.put(32);
    sb.put(0);
    print(sb.mem);
    ->;
};

log_begin(byte* code) -> void
{
    if (LOG_COLOR) { print(code); };
    ->;
};

log_end() -> void
{
    if (LOG_COLOR) { print("\x1b[0m\0"); };
    println("\0");
    ->;
};

// [TAG] [component] sym msg, component may be null, sym is 0 or a print_sym symbol
log_line(byte* color, byte* tag, byte* comp, int sym, byte* msg) -> void
{
    if (!LOG_ON) { ->; };
    log_begin(color);
    print(tag);
    print(" \0");
    if (comp != (byte*)0)
    {
        print("[\0");
        print(comp);
        print("] \0");
    };
    if (sym != 0) { print_sym(sym); };
    print(msg);
    log_end();
    ->;
};

log_info(byte* comp, byte* msg) -> void -> log_line("\x1b[94m\0", "[INFO]\0", comp, 0, msg);

log_step(byte* comp, byte* msg) -> void -> log_line("\x1b[94m\0", "[INFO]\0", comp, 1, msg);

log_warn(byte* comp, byte* msg) -> void -> log_line("\x1b[93m\0", "[WARN]\0", comp, 0, msg);

log_error(byte* comp, byte* msg) -> void -> log_line("\x1b[91m\0", "[ERROR]\0", comp, 0, msg);

// Border of '=' as long as the title plus 4, at most 50, then the title, then the border
log_section(byte* title) -> void
{
    Buf b;
    int bn = pp_cstrlen(title) + 4;
    int k;
    if (!LOG_ON) { ->; };
    b.__init();
    defer b.__exit();
    if (bn > 50) { bn = 50; };
    while (k < bn)
    {
        b.put(61);
        k++;
    };
    b.put(0);
    log_info((byte*)0, b.mem);
    b.clear();
    b.put_str("  \0");
    b.put_str(title);
    b.put(0);
    log_info((byte*)0, b.mem);
    b.clear();
    k = 0;
    while (k < bn)
    {
        b.put(61);
        k++;
    };
    b.put(0);
    log_info((byte*)0, b.mem);
    ->;
};

// fxc.py's logger: success and failure lines are colored on a terminal and carry
// their [INFO] / [ERROR] tag otherwise
log_success(byte* msg) -> void
{
    if (!LOG_ON) { ->; };
    if (!LOG_COLOR)
    {
        log_line("\0", "[INFO]\0", (byte*)0, 2, msg);
        ->;
    };
    log_begin("\x1b[92m\0");
    print_sym(2);
    print(msg);
    log_end();
    ->;
};

log_failure_line(byte* msg) -> void
{
    if (!LOG_COLOR)
    {
        log_line("\0", "[ERROR]\0", (byte*)0, 3, msg);
        ->;
    };
    log_begin("\x1b[91m\0");
    print_sym(3);
    print(msg);
    log_end();
    ->;
};

// Failures are always shown, also in the --lex/--parse/--check stage modes
log_failure(byte* msg) -> void
{
    bool was = LOG_ON;
    LOG_ON = true;
    log_failure_line(msg);
    LOG_ON = was;
    ->;
};

// Frees a heap string; a null pointer is allowed
release(byte* p) -> void
{
    if (p != (byte*)0) { ffree(p); };
    ->;
};

// Frees a copy of the program made for analysis; the program itself is left alone
free_clone(Node* copy, Node* orig) -> void
{
    if (copy != orig) { node_free(copy); };
    ->;
};

// The three part forms join their parts, log the text and free it
log_failure3(byte* a, byte* b, byte* c) -> void
{
    byte* m = join3(a, b, c);
    log_failure(m);
    ffree(m);
    ->;
};

log_error3(byte* comp, byte* a, byte* b, byte* c) -> void
{
    byte* m = join3(a, b, c);
    log_error(comp, m);
    ffree(m);
    ->;
};

log_step3(byte* comp, byte* a, byte* b, byte* c) -> void
{
    byte* m = join3(a, b, c);
    log_step(comp, m);
    ffree(m);
    ->;
};

// flogger.py: value of an environment variable lowered and compared with 1 / true / yes
env_is_on(byte* v) -> bool
{
    Buf lo;
    int i;
    int c;
    bool r;
    lo.__init();
    defer lo.__exit();
    while (v[i] != 0)
    {
        c = (int)v[i];
        if (c >= 'A' & c <= 'Z') { c = c + 32; };
        lo.put(c);
        i++;
    };
    lo.put(0);
    r = bytes_eq(lo.mem, "1\0", 1) & lo.len == 2;
    if (!r) { r = bytes_eq(lo.mem, "true\0", 4) & lo.len == 5; };
    if (!r) { r = bytes_eq(lo.mem, "yes\0", 3) & lo.len == 4; };
    -> r;
};

// Appends v as at least four uppercase hex digits (Python's U+{:04X})
put_hex4(Buf* b, int v) -> void
{
    int d = 28;
    int started = 0;
    int n;
    while (d >= 0)
    {
        n = (v >> d) & 15;
        if (n > 0 | started != 0 | d <= 12)
        {
            started = 1;
            if (n < 10) { b.put(48 + n); } else { b.put(55 + n); };
        };
        d = d - 4;
    };
    ->;
};

// ferrors._color_enabled: diagnostics are colored unless NO_COLOR is set, when FORCE_COLOR is 1
// or stderr is a terminal
diag_color() -> bool
{
    bool tty;
    #ifdef __WINDOWS__
    tty = _isatty(2) != 0;
    #else
    tty = isatty(2) != 0;
    #endif;
    -> diag_color_enabled(tty, getenv(g"NO_COLOR\0"), getenv(g"FORCE_COLOR\0"));
};

// flogger.py: colors only when FLUX_LOG_NO_COLOR is not set to 1/true/yes and
// stdout is a terminal or FORCE_COLOR is 1
log_color_enabled() -> bool
{
    byte* nc = getenv(g"FLUX_LOG_NO_COLOR\0");
    byte* fc = getenv(g"FORCE_COLOR\0");
    if (nc != (byte*)0) { if (env_is_on(nc)) { -> false; }; };
    if (fc != (byte*)0) { if (fc[0] == '1' & fc[1] == 0) { -> true; }; };
    #ifdef __WINDOWS__
    -> _isatty(1) != 0;
    #else
    -> isatty(1) != 0;
    #endif;
};

// ---------------------------------------------------------------------------
// Configuration (config/flux_config.cfg, parsed the way fconfig.py does)
// ---------------------------------------------------------------------------
global byte* CFG_TEXT;
global bool CFG_LOADED;

cfg_load() -> void
{
    byte* srcdir;
    Buf pth;
    int len;
    if (CFG_LOADED) { ->; };
    CFG_LOADED = true;
    pth.__init();
    defer pth.__exit();
    srcdir = getenv(g"FLUXC_SRCDIR\0");
    if (srcdir != (byte*)0)
    {
        pth.put_str(srcdir);
        pth.put_str("/\0");
    };
    pth.put_str("config/flux_config.cfg\0");
    CFG_TEXT = read_source(pth.mem, @len);
    if (CFG_TEXT != (byte*)0) { len = normalize_newlines(CFG_TEXT, len); };
    ->;
};

// Returns a heap copy of the value for key, or null when the key is not set
cfg_get(byte* key) -> byte*
{
    int p = 0;
    int ls;
    int eq;
    int ke;
    int vs;
    int ve;
    int kn = 0;
    int i;
    bool same;
    byte* r;
    cfg_load();
    if (CFG_TEXT == (byte*)0) { -> (byte*)0; };
    while (key[kn] != 0) { kn++; };
    while (CFG_TEXT[p] != 0)
    {
        ls = p;
        while (CFG_TEXT[p] != 0 & CFG_TEXT[p] != 10) { p++; };
        // [ls, p) is one line
        i = ls;
        while (i < p & (CFG_TEXT[i] == ' ' | CFG_TEXT[i] == 9)) { i++; };
        if (i < p)
        {
            if (CFG_TEXT[i] != ';')
            {
                eq = i;
                while (eq < p & CFG_TEXT[eq] != '=') { eq++; };
                if (eq < p)
                {
                    ke = eq;
                    while (ke > i & (CFG_TEXT[ke - 1] == ' ' | CFG_TEXT[ke - 1] == 9)) { ke--; };
                    same = (ke - i) == kn;
                    if (same) { same = bytes_eq(@CFG_TEXT[i], key, kn); };
                    if (same)
                    {
                        vs = eq + 1;
                        ve = vs;
                        while (ve < p & CFG_TEXT[ve] != ';') { ve++; };
                        while (vs < ve & (CFG_TEXT[vs] == ' ' | CFG_TEXT[vs] == 9)) { vs++; };
                        while (ve > vs & (CFG_TEXT[ve - 1] == ' ' | CFG_TEXT[ve - 1] == 9 | CFG_TEXT[ve - 1] == 13)) { ve--; };
                        r = (byte*)fmalloc((u64)(ve - vs + 1));
                        i = 0;
                        while (vs + i < ve)
                        {
                            r[i] = CFG_TEXT[vs + i];
                            i++;
                        };
                        r[i] = (byte)0;
                        -> r;
                    };
                };
            };
        };
        if (CFG_TEXT[p] == 10) { p++; };
    };
    -> (byte*)0;
};

cfg_str(byte* key, byte* dflt) -> byte*
{
    byte* v = cfg_get(key);
    if (v == (byte*)0) { -> dflt; };
    -> v;
};

// Integer value of a config key (decimal, optional leading minus)
cfg_int(byte* key, int dflt) -> int
{
    byte* v = cfg_get(key);
    int i = 0;
    int r = 0;
    bool neg = false;
    if (v == (byte*)0) { -> dflt; };
    if (v[0] == '-')
    {
        neg = true;
        i = 1;
    };
    while (v[i] >= '0' & v[i] <= '9')
    {
        r = r * 10 + (int)(v[i] - '0');
        i++;
    };
    if (neg) { r = 0 - r; };
    ffree(v);
    -> r;
};

is_none(byte* v) -> bool
{
    if (v == (byte*)0) { -> true; };
    if (v[0] == 0) { -> true; };
    -> bytes_eq(v, "none\0", 4) & v[4] == 0;
};

// True when a file can be opened for reading
can_open(byte* path) -> bool
{
    void* f = fopen(path, "rb\0");
    if (f == (void*)0) { -> false; };
    fclose(f);
    -> true;
};

#import "version.fx";
print_version() -> void
{
    ->println(f"Flux Compiler {FLUX_VERSION_NAME} v{FLUX_COMPILER_VERSION}\nRelease date: {FLUX_COMPILER_RELEASE_DATE} // YYYYMMDD\n");
};

// "Working directory:" line of the debug block: the compiler's source directory, else the current one
print_working_dir() -> void
{
    byte* srcdir = getenv(g"FLUXC_SRCDIR\0");
    byte[1024] cwd;
    print("Working directory: \0");
    if (srcdir != (byte*)0)
    {
        println(srcdir);
        ->;
    };
    #ifdef __WINDOWS__
    if (_getcwd(@cwd[0], 1024) != (byte*)0) { println(@cwd[0]); ->; };
    #else
    if (getcwd(@cwd[0], (u64)1024) != (byte*)0) { println(@cwd[0]); ->; };
    #endif;
    println(".\0");
    ->;
};

// The debug block fxc.py prints before compiling
print_debug_block(int argc, byte** argv) -> void
{
    int i;
    println("=== Flux Compiler Debug Log ===\0");
    print_working_dir();
    print("Arguments:\0");
    while (i < argc)
    {
        print(" \0");
        print(argv[i]);
        i++;
    };
    println("\0");
    println("========================================\0");
    println("START DEBUG\0");
    #ifdef __WINDOWS__
    println("Target platform: Windows\0");
    println("Module triple: x86_64-pc-windows-msvc\0");
    #else
    println("Target platform: Linux\0");
    println("Module triple: x86_64-pc-linux-gnu\0");
    #endif;
    println("END DEBUG\0");
    ->;
};

// fcodegen._src_loc_with_source: "[file:line:col]", then the source line (tabs expanded,
// leading spaces dropped) and a caret, for a node of the preprocessed program
append_src_loc(Buf* out, Preprocessor* pp, int line, int col) -> void
{
    int i = line - 1;
    byte* path;
    byte* text;
    byte* base;
    int len, k, ln, ls, le, vcol, w, a, wlen;
    byte c;
    Buf ex;
    if (i < 0 | i >= pp.map_line.len)
    {
        out.put_str("[\0");
        out.put_int(line);
        out.put_str(":\0");
        out.put_int(col);
        out.put_str("]\0");
        ->;
    };
    path = pp.map_path(i);
    ln = pp.map_lineno(i);
    base = path;
    k = 0;
    while (path[k] != 0)
    {
        if (path[k] == '/' | path[k] == '\\') { base = path + k + 1; };
        k++;
    };
    text = read_source(path, @len);
    if (text == (byte*)0)
    {
        out.put_str("[\0");
        out.put_str(base);
        out.put_str(":\0");
        out.put_int(ln);
        out.put_str(":\0");
        out.put_int(col);
        out.put_str("]\0");
        ->;
    };
    // The ln-th line of the file
    k = 1;
    ls = 0;
    while (k < ln & ls < len)
    {
        if (text[ls] == 10) { k++; };
        ls++;
    };
    le = ls;
    while (le < len & text[le] != 10 & text[le] != 13) { le++; };
    // Tab expansion to stops of 4 and the visual column of col
    ex.__init();
    defer ex.__exit();
    vcol = 1;
    k = ls;
    while (k < le)
    {
        c = text[k];
        if (c == 9)
        {
            w = 4 - (ex.len % 4);
            a = 0;
            while (a < w) { ex.put(32); a++; };
            if (k - ls + 1 < col) { vcol = vcol + w; };
        }
        else
        {
            ex.put((int)c);
            if (k - ls + 1 < col) { vcol++; };
        };
        k++;
    };
    ex.put(0);
    out.put_str("[\0");
    out.put_str(base);
    out.put_str(":\0");
    out.put_int(ln);
    out.put_str(":\0");
    out.put_int(vcol);
    out.put_str("]\n    \0");
    wlen = 0;
    while (ex.mem[wlen] == 32) { wlen++; };
    out.put_str(ex.mem + wlen);
    out.put_str("\n    ^\0");
    ffree(text);
    ->;
};

// A codegen error as fxc.py reports it: "Compilation failed: <message>" and, when the
// node is known, its source location
report_codegen_error(Preprocessor* pp, byte* msg, int line, int col) -> void
{
    Buf m;
    m.__init();
    defer m.__exit();
    m.put_str("Compilation failed: \0");
    m.put_str(msg);
    if (col > 0)
    {
        m.put_str("\n\0");
        append_src_loc(@m, pp, line, col);
    };
    m.put(0);
    log_failure(m.mem);
    ->;
};

// Runs a shell command. The runtime entry leaves the stack 8 bytes off the ABI alignment,
// which libc's system() cannot tolerate, so the call is made through an aligned stack.
run_cmd(byte* c) -> int
{
    int rc;
    #ifdef __WINDOWS__
    // cmd /c drops the outermost quotes, so the whole command is wrapped once more
    Buf w;
    w.__init();
    defer w.__exit();
    w.put_str("\"\0");
    w.put_str(c);
    w.put_str("\"\0");
    rc = system(w.mem);
    #else
    volatile asm
    {
        movq %rsp, %r12
        andq $$-16, %rsp
        movq $0, %rdi
        call system@PLT
        movq %r12, %rsp
        movl %eax, ($1)
    } : : "r"(c), "r"(rcp) : "rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "memory", "cc";
    #endif;
    -> rc;
};

// File name without directory and extension, as a new heap string
path_stem(byte* path) -> byte*
{
    int n = 0;
    int start = 0;
    int end;
    int i;
    byte* r;
    while (path[n] != 0) { n++; };
    end = n;
    i = 0;
    while (i < n)
    {
        if (path[i] == '/' | path[i] == 92) { start = i + 1; };
        i++;
    };
    i = n - 1;
    while (i > start)
    {
        if (path[i] == '.') { end = i; break; };
        i--;
    };
    r = (byte*)fmalloc((u64)(end - start + 1));
    i = 0;
    while (start + i < end)
    {
        r[i] = path[start + i];
        i++;
    };
    r[i] = (byte)0;
    -> r;
};

// Appends the path of an LLVM tool to out, resolved as fc.py's resolve_llvm_tool does on
// Windows: llvm_path from the config, then PATH, then the default install directory.
// Returns false when the tool cannot be found.
resolve_tool(Buf* out, byte* name) -> bool
{
    #ifdef __WINDOWS__
    byte* dir = cfg_get("llvm_path\0");
    Buf t;
    Buf probe;
    t.__init();
    probe.__init();
    defer t.__exit();
    defer probe.__exit();
    if (!is_none(dir))
    {
        t.put_str(dir);
        t.put_str("\\\0");
        t.put_str(name);
        t.put_str(".exe\0");
        if (can_open(t.mem))
        {
            out.put_str("\"\0");
            out.put_str(t.mem);
            out.put_str("\"\0");
            -> true;
        };
    };
    probe.put_str("where \0");
    probe.put_str(name);
    probe.put_str(" >nul 2>&1\0");
    if (run_cmd(probe.mem) == 0)
    {
        out.put_str(name);
        -> true;
    };
    t.clear();
    t.put_str("C:\\Program Files\\LLVM\\bin\\\0");
    t.put_str(name);
    t.put_str(".exe\0");
    if (can_open(t.mem))
    {
        out.put_str("\"\0");
        out.put_str(t.mem);
        out.put_str("\"\0");
        -> true;
    };
    -> false;
    #else
    out.put_str(name);
    -> true;
    #endif;
};

// Appends a flag when the config integer key equals 1
flag_if(Buf* cmd, byte* key, byte* flag) -> void
{
    if (cfg_int(key, 0) == 1)
    {
        cmd.put_str(" \0");
        cmd.put_str(flag);
    };
    ->;
};

// Windows libraries the base links, as listed in fc.py
put_win_libs(Buf* cmd) -> void -> cmd.put_str(" legacy_stdio_definitions.lib kernel32.lib ucrt.lib opengl32.lib Ws2_32.lib shell32.lib freetype.lib ole32.lib mmdevapi.lib comdlg32.lib d2d1.lib dwrite.lib user32.lib gdi32.lib secur32.lib crypt32.lib bcrypt.lib ncrypt.lib\0");

// Reports what the linker wrote to its redirected stderr file, as fc.py does:
// a failure is [ERROR] [linker] Linking failed: <stderr>, and stderr text on a
// successful link is [WARN] [linker] Linker stderr: <stderr>
report_link(byte* errpath, int rc) -> void
{
    byte* txt;
    Buf m;
    int len;
    txt = read_source(errpath, @len);
    if (txt == (byte*)0) { ->; };
    len = normalize_newlines(txt, len);
    if (rc != 0 | len > 0)
    {
        m.__init();
        defer m.__exit();
        switch (rc != 0)
        {
            case (true) { m.put_str("Linking failed: \0"); }
            default { m.put_str("Linker stderr: \0"); };
        };
        m.put_str(txt);
        m.put(0);
        switch (rc != 0)
        {
            case (true) { log_error("linker\0", m.mem); }
            default { log_warn("linker\0", m.mem); };
        };
    };
    ffree(txt);
    ->;
};

// Source -> build/<stem>/<stem>.ll -> (opt) -> llc -> object -> linked executable, as fc.py does
// Set once a module's '#[test] = { #[expect_build_fail] }' is known: a failing build is then the expected result
bool BUILD_EXPECT_FAIL;

build_output(byte* path, byte* ir_text, byte* outname, byte* layout) -> bool
{
    byte* stem = path_stem(path);
    byte* ostem = stem;
    byte* tmp;
    byte* march;
    byte* mcpu;
    Buf cmd;
    Buf ll;
    Buf optll;
    Buf obj;
    Buf exe;
    Buf tool;
    Buf errp;
    Buf msg;
    void* f;
    int len = 0;
    int rc;
    int k;
    bool opt_ok;
    if (outname != (byte*)0) { ostem = path_stem(outname); };
    // A module build keeps every file in build/<name>/<Platform>/<Release|Debug>, named after the module
    byte* bd_s = stem;
    byte* ed_s = ostem;
    if (layout != (byte*)0)
    {
        bd_s = layout;
        ed_s = layout;
        stem = ostem;
    };
    cmd.__init();
    ll.__init();
    optll.__init();
    obj.__init();
    exe.__init();
    tool.__init();
    errp.__init();
    msg.__init();
    defer cmd.__exit();
    defer ll.__exit();
    defer optll.__exit();
    defer obj.__exit();
    defer exe.__exit();
    defer tool.__exit();
    defer errp.__exit();
    defer msg.__exit();

    #ifdef __WINDOWS__
    ll.put_str("build\\\0");
    ll.put_str(bd_s);
    ll.put_str("\\\0");
    ll.put_str(stem);
    ll.put_str(".ll\0");
    optll.put_str("build\\\0");
    optll.put_str(bd_s);
    optll.put_str("\\\0");
    optll.put_str(stem);
    optll.put_str(".opt.ll\0");
    obj.put_str("build\\\0");
    obj.put_str(bd_s);
    obj.put_str("\\\0");
    obj.put_str(stem);
    obj.put_str(".obj\0");
    exe.put_str("build\\\0");
    exe.put_str(ed_s);
    exe.put_str("\\\0");
    exe.put_str(ostem);
    exe.put_str(".exe\0");
    errp.put_str("build\\\0");
    errp.put_str(ed_s);
    errp.put_str("\\\0");
    errp.put_str(ostem);
    errp.put_str(".link.err\0");
    cmd.put_str("if not exist build\\\0");
    cmd.put_str(bd_s);
    cmd.put_str(" mkdir build\\\0");
    cmd.put_str(bd_s);
    #else
    ll.put_str("build/\0");
    ll.put_str(bd_s);
    ll.put_str("/\0");
    ll.put_str(stem);
    ll.put_str(".ll\0");
    optll.put_str("build/\0");
    optll.put_str(bd_s);
    optll.put_str("/\0");
    optll.put_str(stem);
    optll.put_str(".opt.ll\0");
    obj.put_str("build/\0");
    obj.put_str(bd_s);
    obj.put_str("/\0");
    obj.put_str(stem);
    obj.put_str(".o\0");
    exe.put_str("build/\0");
    exe.put_str(ed_s);
    exe.put_str("/\0");
    exe.put_str(ostem);
    errp.put_str("build/\0");
    errp.put_str(ed_s);
    errp.put_str("/\0");
    errp.put_str(ostem);
    errp.put_str(".link.err\0");
    cmd.put_str("mkdir -p build/\0");
    cmd.put_str(bd_s);
    #endif;
    run_cmd(cmd.mem);
    if (ostem != stem)
    {
        cmd.clear();
        #ifdef __WINDOWS__
        cmd.put_str("if not exist build\\\0");
        cmd.put_str(ed_s);
        cmd.put_str(" mkdir build\\\0");
        cmd.put_str(ed_s);
        #else
        cmd.put_str("mkdir -p build/\0");
        cmd.put_str(ed_s);
        #endif;
        run_cmd(cmd.mem);
    };

    f = fopen(ll.mem, "wb\0");
    if (f == (void*)0)
    {
        print("Cannot write \0");
        println(ll.mem);
        ffree(stem);
        -> false;
    };
    while (ir_text[len] != 0) { len++; };
    fwrite(ir_text, 1, len, f);
    fclose(f);

    #ifdef __WINDOWS__
    log_step("compiler\0", "Compiling to object file (Windows)\0");
    #else
    log_step("compiler\0", "Compiling to object file (Linux)\0");
    #endif;

    // opt cleans the IR before llc: first available of opt-21, opt-20, opt-19, opt-18, opt
    tmp = (byte*)ll.mem;
    k = 0;
    while (k < 5 & !opt_ok)
    {
        tool.clear();
        if (k == 0) { opt_ok = resolve_tool(@tool, "opt-21\0"); };
        if (k == 1) { opt_ok = resolve_tool(@tool, "opt-20\0"); };
        if (k == 2) { opt_ok = resolve_tool(@tool, "opt-19\0"); };
        if (k == 3) { opt_ok = resolve_tool(@tool, "opt-18\0"); };
        if (k == 4) { opt_ok = resolve_tool(@tool, "opt\0"); };
        #ifndef __WINDOWS__
        if (opt_ok)
        {
            // PATH probe, as `which` does in fc.py
            cmd.clear();
            cmd.put_str("which \0");
            cmd.put_str(tool.mem);
            cmd.put_str(" >/dev/null 2>&1\0");
            opt_ok = run_cmd(cmd.mem) == 0;
        };
        #endif;
        if (!opt_ok) { k++; };
    };
    switch (opt_ok)
    {
        case (true) {
        cmd.clear();
        cmd.put_str(tool.mem);
        cmd.put_str(" -passes=mem2reg,sroa,dce,simplifycfg -S \0");
        cmd.put_str(ll.mem);
        cmd.put_str(" -o \0");
        cmd.put_str(optll.mem);
        switch (run_cmd(cmd.mem) == 0)
        {
            case (true) {
            tmp = (byte*)optll.mem;
            log_info("llc\0", "opt IR optimization pass complete\0");
        }
            default { log_warn("llc\0", "opt pass failed, continuing with the unoptimized IR\0"); };
        };
    }
        default { log_warn("llc\0", "opt pass skipped (not available)\0"); };
    };

    // llc
    tool.clear();
    if (!resolve_tool(@tool, "llc\0"))
    {
        println("Cannot find llc. Set llvm_path in config/flux_config.cfg or add LLVM to PATH.\0");
        ffree(stem);
        -> false;
    };
    cmd.clear();
    cmd.put_str(tool.mem);
    cmd.put_str(" -O3 -filetype=obj\0");
    #ifdef __WINDOWS__
    cmd.put_str(" -mtriple=x86_64-pc-windows-msvc\0");
    #endif;
    march = cfg_get("architecture\0");
    mcpu = cfg_get("cpu\0");
    #ifndef __WINDOWS__
    if (is_none(march)) { march = "x86-64\0"; };
    if (is_none(mcpu)) { mcpu = "native\0"; };
    #endif;
    if (!is_none(march))
    {
        cmd.put_str(" -march=\0");
        cmd.put_str(march);
    };
    if (!is_none(mcpu))
    {
        cmd.put_str(" -mcpu=\0");
        cmd.put_str(mcpu);
    };
    cmd.put_str(" -enable-misched -enable-tail-merge -optimize-regalloc -relocation-model=pic -tail-dup-size=3 -tailcallopt -no-x86-call-frame-opt -x86-use-base-pointer -disable-verify \0");
    #ifdef __WINDOWS__
    cmd.put_str("-x86-asm-syntax=intel \0");
    #endif;
    cmd.put_str(tmp);
    cmd.put_str(" -o \0");
    cmd.put_str(obj.mem);
    rc = run_cmd(cmd.mem);
    if (rc != 0)
    {
        msg.put_str("llc failed with code \0");
        msg.put_int(rc);
        msg.put(0);
        log_error("llc\0", msg.mem);
        ffree(stem);
        -> false;
    };

    // Link
    msg.clear();
    msg.put_str("Linking executable: \0");
    msg.put_str(exe.mem);
    msg.put(0);
    log_step("linker\0", msg.mem);
    cmd.clear();
    #ifdef __WINDOWS__
    tool.clear();
    if (!resolve_tool(@tool, cfg_str("linker\0", "lld-link\0")))
    {
        println("Cannot find the linker. Set llvm_path in config/flux_config.cfg or add LLVM to PATH.\0");
        ffree(stem);
        -> false;
    };
    cmd.put_str(tool.mem);
    cmd.put_str(" /entry:\0");
    cmd.put_str(cfg_str("entrypoint\0", "FRTStartup\0"));
    cmd.put_str(" /stack:67108864\0");
    if (cfg_int("no_default_libraries\0", 0) == 1) { cmd.put_str(" /nodefaultlib\0"); };
    cmd.put_str(" /subsystem:\0");
    cmd.put_str(cfg_str("subsystem\0", "console\0"));
    flag_if(@cmd, "remove_unused_funcs\0", "/opt:ref\0");
    flag_if(@cmd, "comdat_folding\0", "/opt:icf\0");
    cmd.put_str(" /section:.text,ERW\0");
    flag_if(@cmd, "marge_data_and_code\0", "/merge:.data=.text\0");
    if (cfg_int("memory_alignment\0", 0) != 0)
    {
        cmd.put_str(" /align:\0");
        cmd.put_int(cfg_int("memory_alignment\0", 0));
    };
    if (cfg_int("bin_disk_alignment\0", 0) != 0)
    {
        cmd.put_str(" /filealign:\0");
        cmd.put_int(cfg_int("bin_disk_alignment\0", 0));
    };
    flag_if(@cmd, "driver_mode\0", "/driver\0");
    cmd.put_str(" /\0");
    cmd.put_str(cfg_str("mode\0", "release\0"));
    flag_if(@cmd, "fixed_base_address\0", "/fixed\0");
    flag_if(@cmd, "incremental_linking\0", "/incremental:no\0");
    flag_if(@cmd, "strip_executable\0", "/strip\0");
    flag_if(@cmd, "control_flow_guard\0", "/guard:no\0");
    flag_if(@cmd, "aslr\0", "/dynamicbase:no\0");
    flag_if(@cmd, "dep_compatibility\0", "/nxcompat:no\0");
    cmd.put_str(" /opt:lldlto=\0");
    cmd.put_int(cfg_int("lto_optimization_level\0", 3));
    flag_if(@cmd, "all_cores_for_lto\0", "/opt:lldltojobs=all\0");
    cmd.put_str(" \0");
    cmd.put_str(obj.mem);
    put_win_libs(@cmd);
    cmd.put_str(" /out:\0");
    cmd.put_str(exe.mem);
    cmd.put_str(" 2>\0");
    cmd.put_str(errp.mem);
    rc = run_cmd(cmd.mem);
    report_link(errp.mem, rc);
    if (rc != 0)
    {
        log_step("linker\0", "Falling back to clang...\0");
        tool.clear();
        if (resolve_tool(@tool, "clang\0"))
        {
            cmd.clear();
            cmd.put_str(tool.mem);
            cmd.put_str(" \0");
            cmd.put_str(obj.mem);
            cmd.put_str(" -o \0");
            cmd.put_str(exe.mem);
            cmd.put_str(" -fuse-ld=lld-link -Os -flto -fvisibility=hidden -fmerge-all-constants -fno-unwind-tables -fno-asynchronous-unwind-tables -nodefaultlibs -Wl,/OPT:REF -Wl,/OPT:ICF -Wl,/DEBUG:NONE -Wl,/INCREMENTAL:NO -Wl,/LTCG -Wl,/MERGE:.rdata=.text -Wl,/ENTRY:\0");
            cmd.put_str(cfg_str("entrypoint\0", "FRTStartup\0"));
            cmd.put_str(" -Wl,/SUBSYSTEM:CONSOLE -lkernel32 -lntdll -ldwmapi -lucrt -lWs2_32 -luser32 -lgdi32 -lopengl32 -lcomdlg32 -lole32 -lmmdevapi -ld2d1 -ldwrite -lmsvcrt -lsecur32 -lcrypt32 -lbcrypt -lncrypt -llegacy_stdio_definitions\0");
            rc = run_cmd(cmd.mem);
        };
    };
    #else
    cmd.put_str("ld --gc-sections --as-needed --strip-all --build-id=none --no-eh-frame-hdr --no-ld-generated-unwind-info -z noseparate-code -z norelro -z now -z noexecstack -z max-page-size=0x1000 -z common-page-size=0x1000 -z defs --hash-style=gnu --sort-section=alignment --compress-debug-sections=none --fatal-warnings -Map \0");
    cmd.put_str(exe.mem);
    cmd.put_str(".map --orphan-handling=place -Ttext-segment=0x400000 --section-start .rodata=0x500000 --section-start .data=0x600000 --section-start .bss=0x700000 -dynamic-linker /lib64/ld-linux-x86-64.so.2 -e _start \0");
    cmd.put_str(obj.mem);
    cmd.put_str(" -L/usr/lib/x86_64-linux-gnu -L/usr/lib -L/lib/x86_64-linux-gnu -L/lib --start-group -lc --end-group -o \0");
    cmd.put_str(exe.mem);
    cmd.put_str(" 2>\0");
    cmd.put_str(errp.mem);
    rc = run_cmd(cmd.mem);
    report_link(errp.mem, rc);
    #endif;
    if (rc != 0)
    {
        msg.clear();
        msg.put_str("Compilation failed: Linking failed with code \0");
        msg.put_int(rc);
        msg.put(0);
        log_failure(msg.mem);
        ffree(stem);
        -> false;
    };
    msg.clear();
    msg.put_str("Compilation completed: \0");
    msg.put_str(exe.mem);
    msg.put(0);
    log_success(msg.mem);
    if (!BUILD_EXPECT_FAIL)
    {
        print_sym(2);
        print("Compilation successful: \0");
        print(exe.mem);
        println(" (executable)\0");
    };
    ffree(stem);
    -> true;
};

fxc_run(int argc, byte** argv) -> int
{
    // argc is 2 for a single argument. With no arguments argv must not be indexed.
    if (argc < 2)
    {
        usage();
        -> 1;
    };

    bool lex_mode, pp_mode, parse_mode, check_mode, dump_mode, verbose, show_count, emit_mode, full_mode;
    bool borrow_mode, borrow_warn;
    bool effects_mode, effects_warn, warn_as_error;
    byte* entry_name = (byte*)0;
    byte* module_sel;
    byte* path = (byte*)0;
    byte* outname = (byte*)0;
    byte* a;
    int i = 1;
    while (i < argc)
    {
        a = argv[i];
        if (arg_eq(a, "--warn-as-error", 15)) { warn_as_error = true; i++; continue; };
        if (arg_eq(a, "--effects-warn", 14)) { effects_mode = true; effects_warn = true; i++; continue; };
        if (arg_eq(a, "--effects", 9)) { effects_mode = true; i++; continue; };
        if (arg_eq(a, "--borrowcheck-warn", 18)) { borrow_mode = true; borrow_warn = true; i++; continue; };
        if (arg_eq(a, "--borrowcheck", 13)) { borrow_mode = true; i++; continue; };
        if (arg_eq(a, "--module", 8))
        {
            i++;
            if (i < argc) { module_sel = argv[i]; };
            i++;
            continue;
        };
        if (arg_eq(a, "--entrypoint", 12))
        {
            i++;
            if (i < argc) { entry_name = argv[i]; };
            i++;
            continue;
        };
        switch (arg_eq(a, "--lex", 5))
        {
            case (true) {
            lex_mode = true;
        }
            default {
                switch (arg_eq(a, "--parse", 7))
                {
                    case (true) {
            parse_mode = true;
        }
                    default {
                        switch (arg_eq(a, "--dump", 6))
                        {
                            case (true) {
            dump_mode = true;
            parse_mode = true;
        }
                            default {
                                switch (arg_eq(a, "--check", 7))
                                {
                                    case (true) {
            check_mode = true;
            parse_mode = true;
        }
                                    default {
                                        switch (arg_eq(a, "--emit-ll", 9))
                                        {
                                            case (true) {
            emit_mode = true;
            parse_mode = true;
        }
                                            default {
                                                switch (arg_eq(a, "-E", 2) | arg_eq(a, "--preprocess", 12))
                                                {
                                                    case (true) {
            pp_mode = true;
        }
                                                    default {
                                                        switch (arg_eq(a, "-v", 2) | arg_eq(a, "--verbose", 9))
                                                        {
                                                            case (true) {
            verbose = true;
        }
                                                            default {
                                                                switch (arg_eq(a, "-c", 2) | arg_eq(a, "--count", 7))
                                                                {
                                                                    case (true) {
            show_count = true;
        }
                                                                    default {
                                                                        switch (arg_eq(a, "-o", 2) | arg_eq(a, "--output", 8))
                                                                        {
                                                                            case (true) {
            i++;
            if (i < argc) { outname = argv[i]; };
        }
                                                                            default {
                                                                                switch (a[0] == '-')
                                                                                {
                                                                                    case (true) {
            print("Unknown option: \0");
            println(a);
            usage();
            -> 1;
        }
                                                                                    default {
                                                                                        switch (path == (byte*)0)
                                                                                        {
                                                                                            case (true) {
            path = a;
        }
                                                                                            default {
                                                                                                switch (outname == (byte*)0)
                                                                                                {
                                                                                                    case (true) {
            outname = a;
        }
                                                                                                    default {
            print("Warning: Unexpected argument \0");
            println(a);
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
        i++;
    };

    if (path == (byte*)0)
    {
        usage();
        -> 1;
    };

    if (!lex_mode & !pp_mode & !parse_mode)
    {
        // No stage selected: run the full chain (source -> build/<name>/<name>.ll -> llc -> .o)
        full_mode = true;
        emit_mode = true;
        parse_mode = true;
    };

    // The compiler log is only shown for the full chain. Stage modes print their own reports.
    LOG_ON = full_mode;
    LOG_COLOR = log_color_enabled();
    if (full_mode)
    {
        print_version();
        print_debug_block(argc, argv);
        Buf title;
        title.__init();
        defer title.__exit();
        title.put_str("Preprocessing Flux file: \0");
        title.put_str(path);
        title.put(0);
        log_section(title.mem);
    };

    Preprocessor pp(path);
    defer pp.__exit();
    pp.verbose = verbose & pp_mode;
    byte* srcdir = getenv(g"FLUXC_SRCDIR\0");
    if (srcdir != (byte*)0) { pp.set_srcdir(srcdir); };
    if (pp_mode | parse_mode) { pp.add_default_macros(); };

    if (!pp.process())
    {
        log_failure3("Compilation failed: \0", pp.err_text(), "\0");
        -> 1;
    };

    if (pp_mode)
    {
        println(pp.text_ptr());
        if (!lex_mode & !parse_mode) { -> 0; };
    };

    byte* source = pp.text_ptr();
    int len = pp.text_len();

    log_step("lexer\0", "Lexical analysis\0");
    Lexer lx(source, len);
    defer lx.__exit();

    if (!lx.tokenize())
    {
        Buf lerr;
        lerr.__init();
        if (lx.err_code == LexError.NON_ASCII)
        {
            // flexer.py: non-ASCII character 'x' (U+XXXX) is only valid inside string literals, located like any diagnostic
            Buf lmsg;
            lmsg.__init();
            lmsg.put_str("non-ASCII character '\0");
            lmsg.put_n(source + lx.err_start, lx.err_nbytes);
            lmsg.put_str("' (U+\0");
            put_hex4(@lmsg, lx.err_cp);
            lmsg.put_str(") is only valid inside string literals\0");
            render(@lerr, diag_color(), SEV_ERROR, lmsg.mem, lx.err_line, lx.err_col, source, len, pp.map_line.arr, pp.map_line.len, pp.line_files(), -1, 0, 0, 0, (byte*)0);
            lmsg.__exit();
        }
        else
        {
            render(@lerr, diag_color(), SEV_ERROR, error_message(lx.err_code), lx.err_line, lx.err_col, source, len, pp.map_line.arr, pp.map_line.len, pp.line_files(), -1, 0, 0, 0, (byte*)0);
        };
        log_failure3("Compilation failed: \0", lerr.mem, "\0");
        lerr.__exit();
        -> 1;
    };

    Parser ps(@lx);
    defer ps.__exit();
    ps.verbose = verbose;
    ps.lmap = pp.map_line.arr;
    ps.lmapn = pp.map_line.len;
    ps.lfiles = pp.line_files();
    flux::errors::DIAG_COLOR_ON = diag_color();
    ps.diag_color = flux::errors::DIAG_COLOR_ON;
    ps.st = st_new();
    defer st_free(ps.st);

    if (parse_mode)
    {
        log_step("parser\0", "Parsing\0");
        Node* prog = ps.parse();
        if (ps.failed)
        {
            if (ps.err_kind == ParseErr.SILENT) { -> 1; };
            Buf perr;
            perr.__init();
            ps.render_error(@perr);
            log_failure3("Compilation failed: \0", perr.mem, "\0");
            perr.__exit();
            -> 1;
        };
        log_step("parser\0", "AST generated.\0");
        // Modules: pull every module reachable through 'from' into this compilation unit,
        // resolve each module's build settings and flatten the bodies into the program.
        ModUnit* munit;
        ModMap* mmap;
        defer mm_free(mmap);
        defer mu_free(munit);
        byte* layout, merr, ltmp;
        defer release(merr);
        byte* build_name = outname;
        byte* entry_heap;
        defer release(entry_heap);
        defer release(layout);
        if (mu_has_modules(prog))
        {
            munit = mu_load(prog, path, module_sel, "main\0", srcdir);
            if (munit.err != (byte*)0)
            {
                log_error3("modules\0", "Module error: \0", munit.err, "\0");
                -> 1;
            };
            #ifdef __WINDOWS__
            byte* plat_name = "Windows\0";
            #else
            byte* plat_name = "Linux\0";
            #endif;
            merr = mu_resolve_settings(munit, borrow_mode, effects_mode, plat_name);
            if (merr != (byte*)0)
            {
                log_error3("modules\0", "Module error: \0", merr, "\0");
                -> 1;
            };
            if (!(module_sel == (byte*)0 & munit.programs.len > 1))
            {
                if (munit.entry != (ModInfo*)0) { BUILD_EXPECT_FAIL = munit.entry.expect_build_fail; };
            };
            if (module_sel == (byte*)0 & munit.programs.len > 1)
            {
                // A file with several programs: build each one in its own process
                int pk, prc, ai, ci;
                Buf pc;
                bool qt;
                while (pk < munit.programs.len)
                {
                    log_step3("modules\0", "Building module program '\0", (byte*)munit.programs.items[pk], "'\0");
                    pc.__init();
                    ai = 0;
                    while (ai < argc)
                    {
                        qt = false;
                        ci = 0;
                        while (argv[ai][ci] != 0)
                        {
                            if (argv[ai][ci] == ' ') { qt = true; };
                            ci++;
                        };
                        if (ai > 0) { pc.put_str(" \0"); };
                        if (qt) { pc.put_str("\"\0"); };
                        pc.put_str(argv[ai]);
                        if (qt) { pc.put_str("\"\0"); };
                        ai++;
                    };
                    pc.put_str(" --module \0");
                    pc.put_str((byte*)munit.programs.items[pk]);
                    prc = run_cmd(pc.mem);
                    pc.__exit();
                    if (prc != 0) { -> prc; };
                    pk++;
                };
                print_sym(2);
                print("Compilation successful: build/{\0");
                pk = 0;
                while (pk < munit.programs.len)
                {
                    if (pk > 0) { print(", \0"); };
                    print((byte*)munit.programs.items[pk]);
                    pk++;
                };
                println("} (executable)\0");
                -> 0;
            };
            int wi;
            while (wi < munit.warnings.len)
            {
                log_warn("modules\0", (byte*)munit.warnings.items[wi]);
                wi++;
            };
            mu_flatten(prog, munit, "main\0");
            mmap = mu_func_map(munit);
            build_name = munit.entry.oname;
            byte* cfg_dir = "Release\0";
            if (munit.entry.debug) { cfg_dir = "Debug\0"; };
            #ifdef __WINDOWS__
            ltmp = join3(build_name, "\\\0", plat_name);
            layout = join3(ltmp, "\\\0", cfg_dir);
            #else
            ltmp = join3(build_name, "/\0", plat_name);
            layout = join3(ltmp, "/\0", cfg_dir);
            #endif;
            ffree(ltmp);
        };
        flux::unused::unused_warnings(prog, ps.lx.src, ps.lx.length, ps.lmap, ps.lmapn, ps.lfiles, ps.diag_color);
        if (warn_as_error)
        {
            // the warning-only checks become errors too
            borrow_warn = false;
            effects_warn = false;
            if (flux::errors::WARN_COUNT > 0)
            {
                Buf wm;
                wm.__init();
                wm.put_str("Compilation failed: \0");
                wm.put_int(flux::errors::WARN_COUNT);
                wm.put_str(" warning(s) treated as errors (--warn-as-error)\0");
                log_error("compiler\0", wm.mem);
                wm.__exit();
                -> 1;
            };
        };
        log_step("dce\0", "Dead code elimination\0");
        if (entry_name == (byte*)0)
        {
            entry_heap = cfg_get("entrypoint\0");
            entry_name = entry_heap;
            if (entry_name == (byte*)0) { entry_name = "FRTStartup\0"; };
        };
        // One DCE pass. A program that uses async keeps the runtime declarations the
        // lowering will reference.
        bool has_async = program_has_async(prog);
        int dce_n;
        PtrVec* droots;
        if (has_async) { droots = al_roots(); };
        if (munit != (ModUnit*)0)
        {
            PtrVec* mroots = mu_dce_roots(munit, mmap);
            if (mroots.len > 0)
            {
                if (droots == (PtrVec*)0) { droots = mroots; }
                else
                {
                    int mk;
                    while (mk < mroots.len) { pv_push(droots, mroots.items[mk]); mk++; };
                    pv_free(mroots);
                };
            };
        };
        if (droots != (PtrVec*)0) { dce_n = eliminate_roots(prog, entry_name, droots); }
        else { dce_n = eliminate(prog, entry_name); };
        if (droots != (PtrVec*)0) { pv_free(droots); };
        if (LOG_ON)
        {
            switch (dce_n)
            {
                case (0)
                {
                    println("[DCE] No dead namespace declarations found.\0");
                }
                default
                {
                    print("[DCE] Eliminated \0");
                    print(dce_n);
                    println(" unreferenced namespace declaration(s).\0");
                };
            };
        };
        bool eff_on = effects_mode;
        bool bc_on = borrow_mode;
        if (munit != (ModUnit*)0)
        {
            if (mmap.on_effect.count > 0) { eff_on = true; };
            if (mmap.on_borrow.count > 0) { bc_on = true; };
        };
        if (eff_on)
        {
            log_step("effects\0", "Effect analysis\0");
            int ef_n;
            if (munit != (ModUnit*)0) { ef_n = effects_check_filtered(prog, !effects_warn, mmap.own, mmap.on_effect); }
            else { ef_n = effects_check_program(prog, !effects_warn); };
            if (ef_n < 0) { println("Effect pass error\0"); };
            if (ef_n > 0 & !effects_warn)
            {
                log_error("effects\0", "Effect check failed -- compilation aborted.\0");
                -> 1;
            };
        };
        // The borrow check analyses a copy of the pruned program as written; the
        // lowering rewrites the original.
        Node* check_prog = prog;
        defer free_clone(check_prog, prog);
        if (has_async)
        {
            if (bc_on) { check_prog = node_clone(prog); };
            log_step("async\0", "Async lowering\0");
            int lw = lower_program(prog, entry_name, @pp, !bc_on);
            if (lw < 0) { -> 1; };
        };
        if (bc_on)
        {
            int bc_n;
            if (munit != (ModUnit*)0)
            {
                NameMap* live = mu_live_modules(mmap, check_prog);
                int lm;
                ModInfo* lmi;
                while (lm < munit.order.len)
                {
                    lmi = (ModInfo*)munit.order.items[lm];
                    lm++;
                    if (nm_has(live, lmi.name) & nm_has(mmap.on_borrow, lmi.name))
                    {
                        log_step3("FBC\0", "Borrow checking \0", lmi.name, "\0");
                    };
                };
                bc_n = borrow_check_filtered(check_prog, @pp, entry_name, borrow_warn, mmap.own, mmap.on_borrow);
                nm_free(live);
            }
            else
            {
                log_step("FBC\0", "Borrow checking\0");
                bc_n = borrow_check_program(check_prog, @pp, entry_name, borrow_warn);
            };
            if (bc_n > 0 & !borrow_warn)
            {
                log_error("FBC\0", "Borrow check failed -- compilation aborted.\0");
                -> 1;
            };
        };
        if (!emit_mode)
        {
            ps.report();
            print("=== Parse Summary for \0");
            print(path);
            println(" ===\0");
            print("Top-level statements: \0");
            println(node_count(prog, 0));
        };
        if (dump_mode) { dump_node(prog, 0, -1, 0); };
        if (check_mode)
        {
            FXC_SYMTABLE* st = st_new();
            defer st_free(st);
            Checker ck(st);
            defer ck.__exit();
            print("Symbols declared: \0");
            println(ck.declare_program(prog));
            ExprTyper ty(st);
            defer ty.__exit();
            ty.ck = @ck;
            ty.null_term = cfg_int("null_terminate_strings\0", 0) == 1;
            ty.walk_program(prog);
            ck.print_diags(path);
            print("Errors: \0");
            print(ck.errors);
            print(", warnings: \0");
            println(ck.warnings);
            print("Expressions typed: \0");
            print(ty.typed);
            print(", untyped: \0");
            println(ty.untyped);
            if (verbose) { ty.print_unknown(path, 40); };
            println("Implicit conversions:\0");
            ty.print_conv(path, verbose);
        };
        if (emit_mode)
        {
            log_step("codegen\0", "LLVM IR code generation\0");
            FXC_SYMTABLE* est = st_new();
            defer st_free(est);
            Checker eck(est);
            defer eck.__exit();
            eck.declare_program(prog);
            ExprTyper ety(est);
            defer ety.__exit();
            ety.ck = @eck;
            ety.null_term = cfg_int("null_terminate_strings\0", 0) == 1;
            ety.walk_program(prog);
            CodeGen cg(est);
            defer cg.__exit();
            cg.null_term = cfg_int("null_terminate_strings\0", 0) == 1;
            cg.pst = ps.st;
            cg.gen_program(prog);
            Buf ob;
            ob.__init();
            defer ob.__exit();
            cg.mod.emit(@ob);
            if (full_mode)
            {
                if (cg.nerrors > 0 | cg.nskipped > 0)
                {
                    switch (cg.err_msg != (byte*)0)
                    {
                        case (true) { report_codegen_error(@pp, cg.err_msg, cg.err_line, cg.err_col); }
                        default {};
                    };
                    switch (cg.err_msg == (byte*)0)
                    {
                        case (true) {
                    print("Codegen incomplete: \0");
                    print(cg.nskipped);
                    print(" function(s) skipped, \0");
                    print(cg.nerrors);
                    println(" error(s). Not invoking llc.\0");
                    }
                        default {};
                    };
                    node_free(prog);
                    -> 1;
                };
                if (!build_output(path, ob.mem, build_name, layout)) { node_free(prog); -> 1; };
                node_free(prog);
                -> 0;
            };
            println(ob.mem);
            print("; Bodies generated: \0");
            print(cg.nbodies);
            print(", left as declarations: \0");
            println(cg.nskipped);
            int ui;
            while (ui < cg.ucounts.count)
            {
                print("; not generated yet: \0");
                print((byte*)cg.ucounts.keys[ui]);
                print(" x \0");
                println((int)*(i64*)cg.ucounts.vals[ui]);
                ui++;
            };
            if (cg.nerrors > 0)
            {
                print("Codegen errors: \0");
                print(cg.nerrors);
                print(", first at line \0");
                print(cg.err_line);
                print(": \0");
                println(cg.err_msg);
            };
        };
        node_free(prog);
        if (!lex_mode) { -> 0; };
    };

    int total = lx.count - 1;
    int k;

    if (show_count)
    {
        int[256] counts = noinit;
        int types;
        k = 0;
        while (k < 256)
        {
            counts[k] = 0;
            k++;
        };
        k = 0;
        while (k < lx.count)
        {
            if (lx.tokens[k].type != TokenType.EOF)
            {
                if (counts[lx.tokens[k].type] == 0) { types++; };
                counts[lx.tokens[k].type] = counts[lx.tokens[k].type] + 1;
            };
            k++;
        };

        print("=== Token Summary for \0");
        print(path);
        println(" ===\0");
        print("Total tokens: \0");
        println(total);
        print("Token types: \0");
        println(types);
        println("\0");
        println("Token counts:\0");
        k = 0;
        while (k < 256)
        {
            if (counts[k] != 0)
            {
                print("  \0");
                print(token_name(k));
                print(" : \0");
                println(counts[k]);
            };
            k++;
        };
        println("\0");
    };

    switch (verbose)
    {
        case (true) {
        print("=== Detailed Tokens for \0");
        print(path);
        println(" ===\0");
        k = 0;
        while (k < lx.count)
        {
            print(k + 1);
            print(": \0");
            print(token_name(lx.tokens[k].type));
            print(" | \0");
            print(lx.token_value(k));
            print(" | Line \0");
            print(lx.tokens[k].line);
            print(", Col \0");
            println(lx.tokens[k].column);
            k++;
        };
    }
        default {
        print("=== Token Summary for \0");
        print(path);
        println(" ===\0");
        print("Total tokens: \0");
        println(total);
    };
    };

    -> 0;
};

fxc_main(int argc, byte** argv) -> int
{
    int rc = fxc_run(argc, argv);
    if (BUILD_EXPECT_FAIL)
    {
        if (rc != 0)
        {
            if (LOG_COLOR)
            {
                log_begin("\x1b[92m\0");
                print("[BUILD] Failed as expected - #[expect_build_fail] in #[test]\0");
                log_end();
            }
            else
            {
                println("[BUILD] Failed as expected - #[expect_build_fail] in #[test]\0");
            };
            -> 0;
        };
        println("[BUILD] Expected the build to fail (#[expect_build_fail] in #[test]), but it succeeded\0");
        -> 1;
    };
    -> rc;
};

main(int argc, byte** argv) -> int
{
    int rc;
    #ifdef __WINDOWS__
    u32 old_cp = GetConsoleOutputCP();
    SetConsoleOutputCP((u32)65001);
    rc = fxc_main(argc, argv);
    SetConsoleOutputCP(old_cp);
    #else
    rc = fxc_main(argc, argv);
    #endif;
    -> rc;
};
