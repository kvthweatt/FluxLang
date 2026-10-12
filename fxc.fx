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

def usage() -> void
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
    return;
};

// True when the null terminated argument a is exactly lit[0..n)
def arg_eq(byte* a, byte* lit, int n) -> bool
{
    if (!bytes_eq(a, lit, n)) { return false; };
    return a[n] == 0;
};

// Reads the whole file into a heap buffer. Returns null on failure.
// *out_len receives the number of bytes read.
def read_source(byte* path, int* out_len) -> byte*
{
    void* f = fopen(path, "rb\0");
    if (f == (void*)0) { return (byte*)0; };

    fseek(f, 0, SEEK_END);
    int size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0)
    {
        fclose(f);
        return (byte*)0;
    };

    byte* buf = (byte*)fmalloc((u64)size + (u64)1);
    if (buf == (byte*)0)
    {
        fclose(f);
        return (byte*)0;
    };

    int n = fread(buf, 1, size, f);
    fclose(f);
    if (n < 0)
    {
        ffree(buf);
        return (byte*)0;
    };
    buf[n] = (byte)0;
    *out_len = n;
    return buf;
};

// Text mode newline translation: \r\n and lone \r both become \n.
// Works in place and returns the new length.
def normalize_newlines(byte* b, int n) -> int
{
    int r, w;
    while (r < n)
    {
        if (b[r] == 13)
        {
            b[w] = (byte)10;
            w++;
            if (r + 1 < n & b[r + 1] == 10) { r++; };
        }
        else
        {
            b[w] = b[r];
            w++;
        };
        r++;
    };
    b[w] = (byte)0;
    return w;
};

#ifndef __WINDOWS__
extern
{
    def !!
        system(byte*) -> int;
};
#endif;

// ---------------------------------------------------------------------------
// Configuration (config/flux_config.cfg, parsed the way fconfig.py does)
// ---------------------------------------------------------------------------
global byte* CFG_TEXT;
global bool CFG_LOADED;

def cfg_load() -> void
{
    byte* srcdir;
    Buf pth;
    int len;
    if (CFG_LOADED) { return; };
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
    return;
};

// Returns a heap copy of the value for key, or null when the key is not set
def cfg_get(byte* key) -> byte*
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
    if (CFG_TEXT == (byte*)0) { return (byte*)0; };
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
                    if (same)
                    {
                        same = bytes_eq(@CFG_TEXT[i], key, kn);
                    };
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
                        return r;
                    };
                };
            };
        };
        if (CFG_TEXT[p] == 10) { p++; };
    };
    return (byte*)0;
};

def cfg_str(byte* key, byte* dflt) -> byte*
{
    byte* v = cfg_get(key);
    if (v == (byte*)0) { return dflt; };
    return v;
};

// Integer value of a config key (decimal, optional leading minus)
def cfg_int(byte* key, int dflt) -> int
{
    byte* v = cfg_get(key);
    int i = 0;
    int r = 0;
    bool neg = false;
    if (v == (byte*)0) { return dflt; };
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
    return r;
};

def is_none(byte* v) -> bool
{
    if (v == (byte*)0) { return true; };
    if (v[0] == 0) { return true; };
    return bytes_eq(v, "none\0", 4) & v[4] == 0;
};

// True when a file can be opened for reading
def can_open(byte* path) -> bool
{
    void* f = fopen(path, "rb\0");
    if (f == (void*)0) { return false; };
    fclose(f);
    return true;
};

// Runs a shell command. The runtime entry leaves the stack 8 bytes off the ABI alignment,
// which libc's system() cannot tolerate, so the call is made through an aligned stack.
def run_cmd(byte* c) -> int
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
    return rc;
};

// File name without directory and extension, as a new heap string
def path_stem(byte* path) -> byte*
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
    return r;
};

// Appends the path of an LLVM tool to out, resolved as fc.py's resolve_llvm_tool does on
// Windows: llvm_path from the config, then PATH, then the default install directory.
// Returns false when the tool cannot be found.
def resolve_tool(Buf* out, byte* name) -> bool
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
            return true;
        };
    };
    probe.put_str("where \0");
    probe.put_str(name);
    probe.put_str(" >nul 2>&1\0");
    if (run_cmd(probe.mem) == 0)
    {
        out.put_str(name);
        return true;
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
        return true;
    };
    return false;
    #else
    out.put_str(name);
    return true;
    #endif;
};

// Appends a flag when the config integer key equals 1
def flag_if(Buf* cmd, byte* key, byte* flag) -> void
{
    if (cfg_int(key, 0) == 1)
    {
        cmd.put_str(" \0");
        cmd.put_str(flag);
    };
    return;
};

// Windows libraries the base links, as listed in fc.py
def put_win_libs(Buf* cmd) -> void
{
    cmd.put_str(" legacy_stdio_definitions.lib kernel32.lib ucrt.lib opengl32.lib Ws2_32.lib shell32.lib freetype.lib ole32.lib mmdevapi.lib comdlg32.lib d2d1.lib dwrite.lib user32.lib gdi32.lib secur32.lib crypt32.lib bcrypt.lib ncrypt.lib\0");
    return;
};

// Source -> build/<stem>/<stem>.ll -> (opt) -> llc -> object -> linked executable, as fc.py does
def build_output(byte* path, byte* ir_text, byte* outname) -> bool
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
    void* f;
    int len = 0;
    int rc;
    int k;
    bool opt_ok;
    if (outname != (byte*)0) { ostem = path_stem(outname); };
    cmd.__init();
    ll.__init();
    optll.__init();
    obj.__init();
    exe.__init();
    tool.__init();
    defer cmd.__exit();
    defer ll.__exit();
    defer optll.__exit();
    defer obj.__exit();
    defer exe.__exit();
    defer tool.__exit();

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
    cmd.put_str("mkdir -p build/\0");
    cmd.put_str(stem);
    #endif;
    run_cmd(cmd.mem);
    if (ostem != stem)
    {
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
    };

    f = fopen(ll.mem, "wb\0");
    if (f == (void*)0)
    {
        print("Cannot write \0");
        println(ll.mem);
        ffree(stem);
        return false;
    };
    while (ir_text[len] != 0) { len++; };
    fwrite(ir_text, 1, len, f);
    fclose(f);

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
    if (opt_ok)
    {
        cmd.clear();
        cmd.put_str(tool.mem);
        cmd.put_str(" -passes=mem2reg,sroa,dce,simplifycfg -S \0");
        cmd.put_str(ll.mem);
        cmd.put_str(" -o \0");
        cmd.put_str(optll.mem);
        if (run_cmd(cmd.mem) == 0) { tmp = (byte*)optll.mem; }
        else { println("opt pass failed, continuing with the unoptimized IR\0"); };
    }
    else { println("opt pass skipped (not available)\0"); };

    // llc
    tool.clear();
    if (!resolve_tool(@tool, "llc\0"))
    {
        println("Cannot find llc. Set llvm_path in config/flux_config.cfg or add LLVM to PATH.\0");
        ffree(stem);
        return false;
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
        print("llc failed with code \0");
        println(rc);
        ffree(stem);
        return false;
    };

    // Link
    cmd.clear();
    #ifdef __WINDOWS__
    tool.clear();
    if (!resolve_tool(@tool, cfg_str("linker\0", "lld-link\0")))
    {
        println("Cannot find the linker. Set llvm_path in config/flux_config.cfg or add LLVM to PATH.\0");
        ffree(stem);
        return false;
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
    rc = run_cmd(cmd.mem);
    if (rc != 0)
    {
        println("Linking failed, falling back to clang\0");
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
    rc = run_cmd(cmd.mem);
    #endif;
    if (rc != 0)
    {
        print("Linking failed with code \0");
        println(rc);
        ffree(stem);
        return false;
    };
    print("Compilation completed: \0");
    println(exe.mem);
    ffree(stem);
    return true;
};

def main(int argc, byte** argv) -> int
{
    // argc is 2 for a single argument. With no arguments argv must not be indexed.
    if (argc < 2)
    {
        usage();
        return 1;
    };

    bool lex_mode, pp_mode, parse_mode, check_mode, dump_mode, verbose, show_count, emit_mode, full_mode;
    byte* path = (byte*)0;
    byte* outname = (byte*)0;
    byte* a;
    int i = 1;
    while (i < argc)
    {
        a = argv[i];
        if (arg_eq(a, "--lex", 5))
        {
            lex_mode = true;
        }
        elif (arg_eq(a, "--parse", 7))
        {
            parse_mode = true;
        }
        elif (arg_eq(a, "--dump", 6))
        {
            dump_mode = true;
            parse_mode = true;
        }
        elif (arg_eq(a, "--check", 7))
        {
            check_mode = true;
            parse_mode = true;
        }
        elif (arg_eq(a, "--emit-ll", 9))
        {
            emit_mode = true;
            parse_mode = true;
        }
        elif (arg_eq(a, "-E", 2) | arg_eq(a, "--preprocess", 12))
        {
            pp_mode = true;
        }
        elif (arg_eq(a, "-v", 2) | arg_eq(a, "--verbose", 9))
        {
            verbose = true;
        }
        elif (arg_eq(a, "-c", 2) | arg_eq(a, "--count", 7))
        {
            show_count = true;
        }
        elif (arg_eq(a, "-o", 2) | arg_eq(a, "--output", 8))
        {
            i++;
            if (i < argc) { outname = argv[i]; };
        }
        elif (a[0] == '-')
        {
            print("Unknown option: \0");
            println(a);
            usage();
            return 1;
        }
        elif (path == (byte*)0)
        {
            path = a;
        }
        elif (outname == (byte*)0)
        {
            outname = a;
        }
        else
        {
            print("Warning: Unexpected argument \0");
            println(a);
        };
        i++;
    };

    if (path == (byte*)0)
    {
        usage();
        return 1;
    };

    if (!lex_mode & !pp_mode & !parse_mode)
    {
        // No stage selected: run the full chain (source -> build/<name>/<name>.ll -> llc -> .o)
        full_mode = true;
        emit_mode = true;
        parse_mode = true;
    };

    Preprocessor pp(path);
    defer pp.__exit();
    pp.verbose = verbose & pp_mode;
    byte* srcdir = getenv(g"FLUXC_SRCDIR\0");
    if (srcdir != (byte*)0) { pp.set_srcdir(srcdir); };
    if (pp_mode | parse_mode) { pp.add_default_macros(); };

    if (!pp.process())
    {
        print("Preprocessor error: \0");
        println(pp.err_text());
        return 1;
    };

    if (pp_mode)
    {
        println(pp.text_ptr());
        if (!lex_mode & !parse_mode) { return 0; };
    };

    byte* source = pp.text_ptr();
    int len = pp.text_len();

    Lexer lx(source, len);
    defer lx.__exit();

    if (!lx.tokenize())
    {
        print("Lexer error: \0");
        print(error_message(lx.err_code));
        print(" at \0");
        print(lx.err_line);
        print(":\0");
        println(lx.err_col);
        return 1;
    };

    if (lx.warn_count > 0)
    {
        print("[LEXER] WARNING: \0");
        print(lx.warn_count);
        print(" non-ASCII character(s) outside string literals skipped, first U+\0");
        print_hex((u32)lx.warn_cp);
        print(" at line \0");
        print(lx.warn_line);
        print(", col \0");
        print(lx.warn_col);
        println(".\0");
    };

    Parser ps(@lx);
    defer ps.__exit();
    ps.verbose = verbose;
    ps.st = st_new();
    defer st_free(ps.st);

    if (parse_mode)
    {
        Node* prog = ps.parse();
        if (ps.failed)
        {
            ps.print_error();
            return 1;
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
            FXC_SYMTABLE* est = st_new();
            defer st_free(est);
            Checker eck(est);
            defer eck.__exit();
            eck.declare_program(prog);
            ExprTyper ety(est);
            defer ety.__exit();
            ety.ck = @eck;
            ety.walk_program(prog);
            CodeGen cg(est);
            defer cg.__exit();
            cg.gen_program(prog);
            Buf ob;
            ob.__init();
            defer ob.__exit();
            cg.mod.emit(@ob);
            if (full_mode)
            {
                if (cg.nerrors > 0 | cg.nskipped > 0)
                {
                    print("Codegen incomplete: \0");
                    print(cg.nskipped);
                    print(" function(s) skipped, \0");
                    print(cg.nerrors);
                    println(" error(s). Not invoking llc.\0");
                    node_free(prog);
                    return 1;
                };
                if (!build_output(path, ob.mem, outname)) { node_free(prog); return 1; };
                node_free(prog);
                return 0;
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
        if (!lex_mode) { return 0; };
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

    if (verbose)
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
    else
    {
        print("=== Token Summary for \0");
        print(path);
        println(" ===\0");
        print("Total tokens: \0");
        println(total);
    };

    return 0;
};
