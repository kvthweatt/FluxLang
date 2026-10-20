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
#import "src/compiler/fast.fx";
#import "src/compiler/fparser.fx";
#import "src/compiler/ftypesys.fx";
#import "src/compiler/fcheck.fx";
#import "src/compiler/ftyper.fx";
#import "src/compiler/f_llvmir.fx";
#import "src/compiler/fcodegen.fx";
#import "src/compiler/fdce.fx";

using standard::io::console;
using standard::io::file;
using flux::lexer;
using flux::preprocessor;
using flux::ast;
using flux::parser;
using flux::types;
using flux::check;
using flux::typer;
using flux::ir;
using flux::codegen;
using flux::dce;

// ---------------------------------------------------------------------------
// Configuration (config/flux_config.cfg, parsed the way fconfig.py does)
// ---------------------------------------------------------------------------
global byte* CFG_TEXT;
global bool CFG_LOADED;

// ---------------------------------------------------------------------------
// Logger (mirrors flogger.py: the whole line is wrapped in the level color)
//     [INFO] blue 94, [WARN] yellow 93, [ERROR] red 91, success green 92
// ---------------------------------------------------------------------------
global bool LOG_ON;
global bool LOG_COLOR;

#ifdef __WINDOWS__
// Console code page, so the UTF-8 bytes of the log symbols display correctly
extern
{
    def !!
        SetConsoleOutputCP(u32) -> int,
        GetConsoleOutputCP() -> u32;
};
#endif;

usage() -> void
{
    println("Flux Compiler (bootstrap)\0");
    println("Usage: fxc <input.fx> [options]\0");
    println("\0");
    println("Options:\0");
    println("  -o <output>     Output binary name (second positional argument also works)\0");
    println("  -E, --preprocess  Run the preprocessor and print the result\0");
    println("  --lex           Preprocess, then run the lexer and report tokens\0");
    println("  --parse         Preprocess, lex, then run the bootstrap parser\0");
    println("  --dump          Parse, then print the syntax tree\0");
    println("  --check         Parse, then declare symbols and run the type check pass\0");
    println("  --emit-ll       Parse, declare symbols, then print LLVM IR (types and declarations)\0");
    println("  (no stage)      Full chain: write build/<name>/<name>.ll, llc to .o, then link\0");
    println("  -v, --verbose   Show detailed token information\0");
    println("  -c, --count     Show token count summary\0");
    ->;
};

// True when the null terminated argument a is exactly lit[0..n)
arg_eq(byte* a, byte* lit, int n) -> bool
{
    switch (!bytes_eq(a, lit, n))
    {
        case (true) { -> false; }
        default {};
    };
    -> a[n] == 0;
};

// Reads the whole file into a heap buffer. Returns null on failure.
// *out_len receives the number of bytes read.
read_source(byte* path, int* out_len) -> byte*
{
    void* f = fopen(path, "rb\0");
    switch (f == (void*)0)
    {
        case (true) { -> (byte*)0; }
        default {};
    };

    fseek(f, 0, SEEK_END);
    int size = ftell(f);
    fseek(f, 0, SEEK_SET);
    switch (size < 0)
    {
        case (true) {
        fclose(f);
        -> (byte*)0;
    }
        default {};
    };

    byte* buf = (byte*)fmalloc((u64)size + (u64)1);
    switch (buf == (byte*)0)
    {
        case (true) {
        fclose(f);
        -> (byte*)0;
    }
        default {};
    };

    int n = fread(buf, 1, size, f);
    fclose(f);
    switch (n < 0)
    {
        case (true) {
        ffree(buf);
        -> (byte*)0;
    }
        default {};
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
            case (true)
            {
                b[w] = (byte)10;
                w++;
                switch (r + 1 < n & b[r + 1] == 10)
                {
                    case (true) { r++; }
                    default {};
                };
        	}
            default
            {
                b[w] = b[r];
                w++;
            };
        };
        r++;
    };
    b[w] = 0;
    -> w;
};


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
    switch (LOG_COLOR)
    {
        case (true) { print(code); }
        default {};
    };
    ->;
};

log_end() -> void
{
    switch (LOG_COLOR)
    {
        case (true) { print("\x1b[0m\0"); }
        default {};
    };
    println("\0");
    ->;
};

// [TAG] [component] sym msg, component may be null, sym is 0 or a print_sym symbol
log_line(byte* color, byte* tag, byte* comp, int sym, byte* msg) -> void
{
    switch (!LOG_ON)
    {
        case (true) { ->; }
        default {};
    };
    log_begin(color);
    print(tag);
    print(" \0");
    switch (comp != (byte*)0)
    {
        case (true) {
        print("[\0");
        print(comp);
        print("] \0");
    }
        default {};
    };
    switch (sym!?)
    {
        case (true) { print_sym(sym); }
        default {};
    };
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
    switch (!LOG_ON)
    {
        case (true) { ->; }
        default {};
    };
    b.__init();
    defer b.__exit();
    switch (bn > 50)
    {
        case (true) { bn = 50; }
        default {};
    };
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

log_success(byte* msg) -> void
{
    switch (!LOG_ON)
    {
        case (true) { ->; }
        default {};
    };
    log_begin("\x1b[92m\0");
    print_sym(2);
    print(msg);
    log_end();
    ->;
};

log_failure(byte* msg) -> void
{
    switch (!LOG_ON)
    {
        case (true) { ->; }
        default {};
    };
    log_begin("\x1b[91m\0");
    print_sym(3);
    print(msg);
    log_end();
    ->;
};


cfg_load() -> void
{
    byte* srcdir;
    Buf pth;
    int len;
    switch (CFG_LOADED)
    {
        case (true) { ->; }
        default {};
    };
    CFG_LOADED = true;
    pth.__init();
    defer pth.__exit();
    srcdir = getenv(g"FLUXC_SRCDIR\0");
    switch (srcdir != (byte*)0)
    {
        case (true) {
        pth.put_str(srcdir);
        pth.put_str("/\0");
    }
        default {};
    };
    pth.put_str("config/flux_config.cfg\0");
    CFG_TEXT = read_source(pth.mem, @len);
    switch (CFG_TEXT != (byte*)0)
    {
        case (true) { len = normalize_newlines(CFG_TEXT, len); }
        default {};
    };
    ->;
};

// Returns a heap copy of the value for key, or null when the key is not set
cfg_get(byte* key) -> byte*
{
    int p,
        ls,
        eq,
        ke,
        vs,
        ve,
        kn,
        i;
    bool same;
    byte* r;
    cfg_load();
    switch (CFG_TEXT == (byte*)0)
    {
        case (true) { -> (byte*)0; }
        default {};
    };
    while (key[kn]!?) { kn++; };
    while (CFG_TEXT[p]!?)
    {
        ls = p;
        while (CFG_TEXT[p]!? & CFG_TEXT[p] != 10) { p++; };
        // [ls, p) is one line
        i = ls;
        while (i < p & (CFG_TEXT[i] == ' ' | CFG_TEXT[i] == 9)) { i++; };
        switch (i < p)
        {
            case (true) {
            switch (CFG_TEXT[i] != ';')
            {
                case (true) {
                eq = i;
                while (eq < p & CFG_TEXT[eq] != '=') { eq++; };
                switch (eq < p)
                {
                    case (true) {
                    ke = eq;
                    while (ke > i & (CFG_TEXT[ke - 1] == ' ' | CFG_TEXT[ke - 1] == 9)) { ke--; };
                    same = (ke - i) == kn;
                    switch (same)
                    {
                        case (true) {
                        same = bytes_eq(@CFG_TEXT[i], key, kn);
                    }
                        default {};
                    };
                    switch (same)
                    {
                        case (true) {
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
        switch (CFG_TEXT[p] == 10)
        {
            case (true) { p++; }
            default {};
        };
    };
    -> (byte*)0;
};

cfg_str(byte* key, byte* dflt) -> byte*
{
    byte* v = cfg_get(key);
    switch (v == (byte*)0)
    {
        case (true) { -> dflt; }
        default {};
    };
    -> v;
};

// Integer value of a config key (decimal, optional leading minus)
cfg_int(byte* key, int dflt) -> int
{
    byte* v = cfg_get(key);
    int i,r;
    bool neg = false;
    switch (v == (byte*)0)
    {
        case (true) { -> dflt; }
        default {};
    };
    switch (v[0] == '-')
    {
        case (true) {
        neg = true;
        i = 1;
    }
        default {};
    };
    while (v[i] >= '0' & v[i] <= '9')
    {
        r = r * 10 + (int)(v[i] - '0');
        i++;
    };
    switch (neg)
    {
        case (true) { r = 0 - r; }
        default {};
    };
    -> r;
};

is_none(byte* v) -> bool
{
    switch (v == (byte*)0)
    {
        case (true) { -> true; }
        default {};
    };
    switch (v[0] == 0)
    {
        case (true) { -> true; }
        default {};
    };
    -> bytes_eq(v, "none\0", 4) & v[4] == 0;
};

// True when a file can be opened for reading
can_open(byte* path) -> bool
{
    void* f = fopen(path, "rb\0");
    switch (f == (void*)0)
    {
        case (true) { -> false; }
        default {};
    };
    fclose(f);
    -> true;
};

// Prints version.txt (found next to config/ under FLUXC_SRCDIR), as fxc.py does first
print_version() -> void
{
    byte* srcdir, txt;
    Buf pth;
    int len;
    pth.__init();
    defer pth.__exit();
    srcdir = getenv(g"FLUXC_SRCDIR\0");
    switch (srcdir != (byte*)0)
    {
        case (true) {
        pth.put_str(srcdir);
        pth.put_str("/\0");
    }
        default {};
    };
    pth.put_str("version.txt\0");
    txt = read_source(pth.mem, @len);
    switch (txt == (byte*)0)
    {
        case (true) { ->; }
        default {};
    };
    len = normalize_newlines(txt, len);
    print(txt);
    switch (len > 0)
    {
        case (true) {
        switch (txt[len - 1] != 10)
        {
            case (true) { println("\0"); }
            default {};
        };
    }
        default {};
    };
    ffree(txt);
    ->;
};

// The debug block fxc.py prints before compiling
print_debug_block(int argc, byte** argv) -> void
{
    int i;
    println("=== Flux Compiler Debug Log ===\0");
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
    println("Module triple: x86_64-unknown-linux-gnu\0");
    #endif;
    println("END DEBUG\0");
    ->;
};

// Runs a shell command. The runtime entry leaves the stack 8 bytes off the ABI alignment,
// which libc's system() cannot tolerate, so the call is made through an aligned stack.
run_cmd(byte* c) -> int
{
    int rc;
    int* rcp = @rc;
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
    int n, start, end, i;
    byte* r;
    while (path[n]!?) { n++; };
    end = n;
    i = 0;
    while (i < n)
    {
        switch (path[i] == '/' | path[i] == 92)
        {
            case (true) { start = i + 1; }
            default {};
        };
        i++;
    };
    i = n - 1;
    while (i > start)
    {
        switch (path[i] == '.')
        {
            case (true) { end = i; break; }
            default {};
        };
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
    switch (!is_none(dir))
    {
        case (true) {
        t.put_str(dir);
        t.put_str("\\\0");
        t.put_str(name);
        t.put_str(".exe\0");
        switch (can_open(t.mem))
        {
            case (true) {
            out.put_str("\"\0");
            out.put_str(t.mem);
            out.put_str("\"\0");
            -> true;
        }
            default {};
        };
    }
        default {};
    };
    probe.put_str("where \0");
    probe.put_str(name);
    probe.put_str(" >nul 2>&1\0");
    switch (run_cmd(probe.mem) == 0)
    {
        case (true) {
        out.put_str(name);
        -> true;
    }
        default {};
    };
    t.clear();
    t.put_str("C:\\Program Files\\LLVM\\bin\\\0");
    t.put_str(name);
    t.put_str(".exe\0");
    switch (can_open(t.mem))
    {
        case (true) {
        out.put_str("\"\0");
        out.put_str(t.mem);
        out.put_str("\"\0");
        -> true;
    }
        default {};
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
    switch (cfg_int(key, 0) == 1)
    {
        case (true) {
        cmd.put_str(" \0");
        cmd.put_str(flag);
    }
        default {};
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
    switch (txt == (byte*)0)
    {
        case (true) { ->; }
        default {};
    };
    len = normalize_newlines(txt, len);
    switch (rc!? | len > 0)
    {
        case (true) {
        m.__init();
        defer m.__exit();
        switch (rc!?)
        {
            case (true) { m.put_str("Linking failed: \0"); }
            default { m.put_str("Linker stderr: \0"); };
        };
        m.put_str(txt);
        m.put(0);
        switch (rc!?)
        {
            case (true) { log_error("linker\0", m.mem); }
            default { log_warn("linker\0", m.mem); };
        };
    }
        default {};
    };
    ffree(txt);
    ->;
};

operator ()

// Source -> build/<stem>/<stem>.ll -> (opt) -> llc -> object -> linked executable, as fc.py does
build_output(byte* path, byte* ir_text, byte* outname) -> bool
{
    byte* stem = path_stem(path),
          ostem = stem,
          tmp,
          march,
          mcpu;
    Buf cmd,
        ll,
        optll,
        obj,
        exe,
        tool,
        errp,
        msg;
    void* f;
    int len, rc, k;
    bool opt_ok;
    switch (outname != (byte*)0)
    {
        case (true) { ostem = path_stem(outname); }
        default {};
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
    ll.put_str(stem);
    ll.put_str("\\\0");
    ll.put_str(stem);
    ll.put_str(".ll\0");
    optll.put_str("build\\\0");
    optll.put_str(stem);
    optll.put_str("\\\0");
    optll.put_str(stem);
    optll.put_str(".opt.ll\0");
    obj.put_str("build\\\0");
    obj.put_str(stem);
    obj.put_str("\\\0");
    obj.put_str(stem);
    obj.put_str(".obj\0");
    exe.put_str("build\\\0");
    exe.put_str(ostem);
    exe.put_str("\\\0");
    exe.put_str(ostem);
    exe.put_str(".exe\0");
    errp.put_str("build\\\0");
    errp.put_str(ostem);
    errp.put_str("\\\0");
    errp.put_str(ostem);
    errp.put_str(".link.err\0");
    cmd.put_str("if not exist build\\\0");
    cmd.put_str(stem);
    cmd.put_str(" mkdir build\\\0");
    cmd.put_str(stem);
    #else
    ll.put_str("build/\0");
    ll.put_str(stem);
    ll.put_str("/\0");
    ll.put_str(stem);
    ll.put_str(".ll\0");
    optll.put_str("build/\0");
    optll.put_str(stem);
    optll.put_str("/\0");
    optll.put_str(stem);
    optll.put_str(".opt.ll\0");
    obj.put_str("build/\0");
    obj.put_str(stem);
    obj.put_str("/\0");
    obj.put_str(stem);
    obj.put_str(".o\0");
    exe.put_str("build/\0");
    exe.put_str(ostem);
    exe.put_str("/\0");
    exe.put_str(ostem);
    errp.put_str("build/\0");
    errp.put_str(ostem);
    errp.put_str("/\0");
    errp.put_str(ostem);
    errp.put_str(".link.err\0");
    cmd.put_str("mkdir -p build/\0");
    cmd.put_str(stem);
    #endif;
    run_cmd(cmd.mem);
    switch (ostem != stem)
    {
        case (true) {
        cmd.clear();
        #ifdef __WINDOWS__
        cmd.put_str("if not exist build\\\0");
        cmd.put_str(ostem);
        cmd.put_str(" mkdir build\\\0");
        cmd.put_str(ostem);
        #else
        cmd.put_str("mkdir -p build/\0");
        cmd.put_str(ostem);
        #endif;
        run_cmd(cmd.mem);
    }
        default {};
    };

    f = fopen(ll.mem, "wb\0");
    switch (f == (void*)0)
    {
        case (true) {
        print("Cannot write \0");
        println(ll.mem);
        ffree(stem);
        -> false;
    }
        default {};
    };
    while (ir_text[len]!?) { len++; };
    fwrite(ir_text, 1, len, f);
    fclose(f);

    #ifdef __WINDOWS__
    log_step("compiler\0", "Compiling to object file (Windows)\0");
    #else
    log_step("compiler\0", "Compiling to object file (Linux)\0");
    #endif;

    // opt cleans the IR before llc: first available of opt-21, opt-20, opt-19, opt-18, opt
    tmp = (byte*)ll.mem;

    ///
    // THIS DOES NOT WORK FOR SOME REASON?
    while (k < 5 & !opt_ok)
    {
        tool.clear();
        switch(k)
        {
            case (0)
            {
                opt_ok = resolve_tool(@tool, "opt-21\0");
            }
            case (1)
            {
                opt_ok = resolve_tool(@tool, "opt-20\0");
            }
            case (2)
            {
                opt_ok = resolve_tool(@tool, "opt-19\0");
            }
            case (3)
            {
                opt_ok = resolve_tool(@tool, "opt-18\0");
            }
            case (4)
            {
                opt_ok = resolve_tool(@tool, "opt\0");
            }
            default
            {
                #ifdef __WINDOWS__
                switch(opt_ok)
                {
                    case (true)
                    {
                        // PATH probe, as `which` does in fc.py
                        println("--- DEBUG --- GOT HERE");
                        cmd.clear();
                        cmd.put_str("which \0");
                        cmd.put_str(tool.mem);
                        cmd.put_str(" >/dev/null 2>&1\0");
                        opt_ok = run_cmd(cmd.mem) == 0;
                    }
                    default
                    {
                        k++;
                    };
                };
                #endif;
            };
        };
    };

    ///
    while (k < 5 & !opt_ok)
    {
        tool.clear();

        switch (k == 0)
        {
            case (true) { opt_ok = resolve_tool(@tool, "opt-21\0"); }
            default {};
        };
        switch (k == 1)
        {
            case (true) { opt_ok = resolve_tool(@tool, "opt-20\0"); }
            default {};
        };
        switch (k == 2)
        {
            case (true) { opt_ok = resolve_tool(@tool, "opt-19\0"); }
            default {};
        };
        switch (k == 3)
        {
            case (true) { opt_ok = resolve_tool(@tool, "opt-18\0"); }
            default {};
        };
        switch (k == 4)
        {
            case (true) { opt_ok = resolve_tool(@tool, "opt\0"); }
            default {};
        };
        #ifndef __WINDOWS__
        switch (opt_ok)
        {
            case (true) {
            // PATH probe, as `which` does in fc.py
            cmd.clear();
            cmd.put_str("which \0");
            cmd.put_str(tool.mem);
            cmd.put_str(" >/dev/null 2>&1\0");
            opt_ok = run_cmd(cmd.mem) == 0;
        }
            default {};
        };
        #endif;
        switch (!opt_ok)
        {
            case (true) { k++; }
            default {};
        };
    };

    switch (opt_ok)
    {
        case (true)
        {
            cmd.clear();
            cmd.put_str(tool.mem);
            cmd.put_str(" -passes=mem2reg,sroa,dce,simplifycfg -S \0");
            cmd.put_str(ll.mem);
            cmd.put_str(" -o \0");
            cmd.put_str(optll.mem);
            switch (run_cmd(cmd.mem) == 0)
            {
                case (true)
                {
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
    switch (!resolve_tool(@tool, "llc\0"))
    {
        case (true)
        {
            println("Cannot find llc. Set llvm_path in config/flux_config.cfg or add LLVM to PATH.\0");
            ffree(stem);
            -> false;
        }
        default {};
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
    switch (is_none(march))
    {
        case (true)
        {
            march = "x86-64\0";
        }
        default {};
    };
    switch (is_none(mcpu))
    {
        case (true)
        {
            mcpu = "native\0";
        }
        default {};
    };
    #endif;
    switch (!is_none(march))
    {
        case (true)
        {
            cmd.put_str(" -march=\0");
            cmd.put_str(march);
        }
        default {};
    };
    switch (!is_none(mcpu))
    {
        case (true)
        {
            cmd.put_str(" -mcpu=\0");
            cmd.put_str(mcpu);
        }
        default {};
    };
    cmd.put_str(" -enable-misched -enable-tail-merge -optimize-regalloc -relocation-model=pic -tail-dup-size=3 -tailcallopt -no-x86-call-frame-opt -x86-use-base-pointer -disable-verify \0");
    #ifdef __WINDOWS__
    cmd.put_str("-x86-asm-syntax=intel \0");
    #endif;
    cmd.put_str(tmp);
    cmd.put_str(" -o \0");
    cmd.put_str(obj.mem);
    rc = run_cmd(cmd.mem);
    switch (rc!?)
    {
        case (true)
        {
            msg.put_str("llc failed with code \0");
            msg.put_int(rc);
            msg.put(0);
            log_error("llc\0", msg.mem);
            ffree(stem);
            -> false;
        }
        default {};
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
    switch (!resolve_tool(@tool, cfg_str("linker\0", "lld-link\0")))
    {
        case (true)
        {
            println("Cannot find the linker. Set llvm_path in config/flux_config.cfg or add LLVM to PATH.\0");
            ffree(stem);
            -> false;
        }
        default {};
    };
    cmd.put_str(tool.mem);
    cmd.put_str(" /entry:\0");
    cmd.put_str(cfg_str("entrypoint\0", "FRTStartup\0"));
    cmd.put_str(" /stack:67108864\0");
    switch (cfg_int("no_default_libraries\0", 0) == 1)
    {
        case (true) { cmd.put_str(" /nodefaultlib\0"); }
        default {};
    };
    cmd.put_str(" /subsystem:\0");
    cmd.put_str(cfg_str("subsystem\0", "console\0"));
    flag_if(@cmd, "remove_unused_funcs\0", "/opt:ref\0");
    flag_if(@cmd, "comdat_folding\0", "/opt:icf\0");
    cmd.put_str(" /section:.text,ERW\0");
    flag_if(@cmd, "marge_data_and_code\0", "/merge:.data=.text\0");
    switch (cfg_int("memory_alignment\0", 0)!?)
    {
        case (true)
        {
            cmd.put_str(" /align:\0");
            cmd.put_int(cfg_int("memory_alignment\0", 0));
        }
        default {};
    };
    switch (cfg_int("bin_disk_alignment\0", 0)!?)
    {
        case (true)
        {
            cmd.put_str(" /filealign:\0");
            cmd.put_int(cfg_int("bin_disk_alignment\0", 0));
        }
        default {};
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
    switch (rc!?)
    {
        case (true)
        {
            log_step("linker\0", "Falling back to clang...\0");
            tool.clear();
            switch (resolve_tool(@tool, "clang\0"))
            {
                case (true)
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
                }
                default {};
            };
        }
        default {};
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
    switch (rc!?)
    {
        case (true) {
        msg.clear();
        msg.put_str(f"Compilation failed: Linking failed with code {rc}\0");
        msg.put(0);
        log_failure(msg.mem);
        ffree(stem);
        -> false;
    }
        default {};
    };
    msg.clear();
    msg.put_str(f"Compilation completed: {exe.mem}\0");
    msg.put(0);
    log_success(msg.mem);
    print_sym(2);
    print(f"Compilation successful: {exe.mem} (executable)\0");
    ffree(stem);
    -> true;
};

fxc_main(int argc, byte** argv) -> int
{
    // argc is 2 for a single argument. With no arguments argv must not be indexed.
    switch (argc < 2)
    {
        case (true)
        {
            usage();
            -> 1;
        }
        default {};
    };

    bool lex_mode, pp_mode, parse_mode, check_mode, dump_mode, verbose, show_count, emit_mode, full_mode;
    byte* path,
          outname,
          a;
    int i = 1;
    while (i < argc)
    {
        a = argv[i];

        switch (arg_eq(a, "--lex", 5))
        {
            case (true)
            {
                lex_mode = true;
            }
            default
            {
                switch (arg_eq(a, "--parse", 7))
                {
                    case (true)
                    {
                        parse_mode = true;
                    }
                    default
                    {
                        switch (arg_eq(a, "--dump", 6))
                        {
                            case (true)
                            {
                                dump_mode = true;
                                parse_mode = true;
                            }
                            default {
                                switch (arg_eq(a, "--check", 7))
                                {
                                    case (true)
                                    {
                                        check_mode = true;
                                        parse_mode = true;
                                    }
                                    default
                                    {
                                        switch (arg_eq(a, "--emit-ll", 9))
                                        {
                                            case (true)
                                            {
                                                emit_mode = true;
                                                parse_mode = true;
                                            }
                                            default
                                            {
                                                switch (arg_eq(a, "-E", 2) | arg_eq(a, "--preprocess", 12))
                                                {
                                                    case (true)
                                                    {
                                                        pp_mode = true;
                                                    }
                                                    default
                                                    {
                                                        switch (arg_eq(a, "-v", 2) | arg_eq(a, "--verbose", 9))
                                                        {
                                                            case (true)
                                                            {
                                                                verbose = true;
                                                            }
                                                            default
                                                            {
                                                                switch (arg_eq(a, "-c", 2) | arg_eq(a, "--count", 7))
                                                                {
                                                                    case (true)
                                                                    {
                                                                        show_count = true;
                                                                    }
                                                                    default
                                                                    {
                                                                        switch (arg_eq(a, "-o", 2) | arg_eq(a, "--output", 8))
                                                                        {
                                                                            case (true)
                                                                            {
                                                                                i++;
                                                                                switch (i < argc)
                                                                                {
                                                                                    case (true) { outname = argv[i]; }
                                                                                    default {};
                                                                                };
                                                                            }
                                                                            default
                                                                            {
                                                                                switch (a[0] == '-')
                                                                                {
                                                                                    case (true)
                                                                                    {
                                                                                        print(f"Unknown option: {a}\0");;
                                                                                        usage();
                                                                                        -> 1;
                                                                                    }
                                                                                    default
                                                                                    {
                                                                                        switch (path == (byte*)0)
                                                                                        {
                                                                                            case (true)
                                                                                            {
                                                                                                path = a;
                                                                                            }
                                                                                            default
                                                                                            {
                                                                                                switch (outname == (byte*)0)
                                                                                                {
                                                                                                    case (true)
                                                                                                    {
                                                                                                        outname = a;
                                                                                                    }
                                                                                                    default
                                                                                                    {
                                                                                                        print(f"Warning: Unexpected argument {a}\0");
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

    switch (path == (byte*)0)
    {
        case (true) {
        usage();
        -> 1;
    }
        default {};
    };

    switch (!lex_mode & !pp_mode & !parse_mode)
    {
        case (true) {
        // No stage selected: run the full chain (source -> build/<name>/<name>.ll -> llc -> .o)
        full_mode = true;
        emit_mode = true;
        parse_mode = true;
    }
        default {};
    };

    // The compiler log is only shown for the full chain. Stage modes print their own reports.
    LOG_ON = full_mode;
    LOG_COLOR = getenv(g"FLUX_LOG_NO_COLOR\0") == (byte*)0;
    switch (full_mode)
    {
        case (true) {
        print_version();
        print_debug_block(argc, argv);
        Buf title;
        title.__init();
        defer title.__exit();
        title.put_str("Preprocessing Flux file: \0");
        title.put_str(path);
        title.put(0);
        log_section(title.mem);
    }
        default {};
    };

    Preprocessor pp(path);
    defer pp.__exit();
    pp.verbose = verbose & pp_mode;
    byte* srcdir = getenv(g"FLUXC_SRCDIR\0");
    switch (srcdir != (byte*)0)
    {
        case (true) { pp.set_srcdir(srcdir); }
        default {};
    };
    switch (pp_mode | parse_mode)
    {
        case (true) { pp.add_default_macros(); }
        default {};
    };

    switch (!pp.process())
    {
        case (true) {
        print("Preprocessor error: \0");
        println(pp.err_text());
        -> 1;
    }
        default {};
    };

    switch (pp_mode)
    {
        case (true) {
        println(pp.text_ptr());
        switch (!lex_mode & !parse_mode)
        {
            case (true) { -> 0; }
            default {};
        };
    }
        default {};
    };

    byte* source = pp.text_ptr();
    int len = pp.text_len();

    log_step("lexer\0", "Lexical analysis\0");
    Lexer lx(source, len);
    defer lx.__exit();

    switch (!lx.tokenize())
    {
        case (true) {
        print("Lexer error: \0");
        print(error_message(lx.err_code));
        print(" at \0");
        print(lx.err_line);
        print(":\0");
        println(lx.err_col);
        -> 1;
    }
        default {};
    };

    switch (lx.warn_count > 0)
    {
        case (true) {
        print("[LEXER] WARNING: \0");
        print(lx.warn_count);
        print(" non-ASCII character(s) outside string literals skipped, first U+\0");
        print_hex((u32)lx.warn_cp);
        print(" at line \0");
        print(lx.warn_line);
        print(", col \0");
        print(lx.warn_col);
        println(".\0");
    }
        default {};
    };

    Parser ps(@lx);
    defer ps.__exit();
    ps.verbose = verbose;
    ps.st = st_new();
    defer st_free(ps.st);

    switch (parse_mode)
    {
        case (true) {
        log_step("parser\0", "Parsing\0");
        Node* prog = ps.parse();
        switch (ps.failed)
        {
            case (true) {
            ps.print_error();
            -> 1;
        }
            default {};
        };
        log_step("parser\0", "AST generated.\0");
        log_step("dce\0", "Dead code elimination\0");
        int dce_n = eliminate(prog, cfg_str("entrypoint\0", "FRTStartup\0"));
        switch (LOG_ON)
        {
            case (true) {
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
        }
            default {};
        };
        switch (!emit_mode)
        {
            case (true) {
            ps.report();
            print("=== Parse Summary for \0");
            print(path);
            println(" ===\0");
            print("Top-level statements: \0");
            println(node_count(prog, 0));
        }
            default {};
        };
        switch (dump_mode)
        {
            case (true) { dump_node(prog, 0, -1, 0); }
            default {};
        };
        switch (check_mode)
        {
            case (true) {
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
            switch (verbose)
            {
                case (true) { ty.print_unknown(path, 40); }
                default {};
            };
            println("Implicit conversions:\0");
            ty.print_conv(path, verbose);
        }
            default {};
        };
        switch (emit_mode)
        {
            case (true) {
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
            cg.gen_program(prog);
            Buf ob;
            ob.__init();
            defer ob.__exit();
            cg.mod.emit(@ob);
            switch (full_mode)
            {
                case (true) {
                switch (cg.nerrors > 0 | cg.nskipped > 0)
                {
                    case (true) {
                    print("Codegen incomplete: \0");
                    print(cg.nskipped);
                    print(" function(s) skipped, \0");
                    print(cg.nerrors);
                    println(" error(s). Not invoking llc.\0");
                    node_free(prog);
                    -> 1;
                }
                    default {};
                };
                switch (!build_output(path, ob.mem, outname))
                {
                    case (true) { node_free(prog); -> 1; }
                    default {};
                };
                node_free(prog);
                -> 0;
            }
                default {};
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
            switch (cg.nerrors > 0)
            {
                case (true) {
                print("Codegen errors: \0");
                print(cg.nerrors);
                print(", first at line \0");
                print(cg.err_line);
                print(": \0");
                println(cg.err_msg);
            }
                default {};
            };
        }
            default {};
        };
        node_free(prog);
        switch (!lex_mode)
        {
            case (true) { -> 0; }
            default {};
        };
    }
        default {};
    };

    int total = lx.count - 1;
    int k;

    switch (show_count)
    {
        case (true) {
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
            switch (lx.tokens[k].type != TokenType.EOF)
            {
                case (true)
                {
                    switch (counts[lx.tokens[k].type] == 0)
                    {
                        case (true) { types++; }
                        default {};
                    };
                    counts[lx.tokens[k].type] = counts[lx.tokens[k].type] + 1;
                }
                default {};
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
            switch (counts[k]!?)
            {
                case (true) {
                print("  \0");
                print(token_name(k));
                print(" : \0");
                println(counts[k]);
            }
                default {};
            };
            k++;
        };
        println("\0");
    }
        default {};
    };

    switch (verbose)
    {
        case (true)
        {
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
        default
        {
            print("=== Token Summary for \0");
            print(path);
            println(" ===\0");
            print("Total tokens: \0");
            println(total);
        };
    };

    -> 0;
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
