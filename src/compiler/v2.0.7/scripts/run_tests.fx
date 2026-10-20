// Author: Karac V. Thweatt
//
// run_tests.fx - Flux compiler test runner
//
// Compiles every .fx file in tests/ (or examples/) with `fxc file.fx`,
// runs the produced executable, and prints a summary.
//
// Usage:
//     run_tests [options]
//
// Options:
//     --verbose, -v       Show detailed output for each test
//     --keep-artifacts    Keep compiled executables after tests
//     --compile-only      Only compile, don't run the executables
//     --filter PATTERN    Only run tests matching pattern (substring match)
//     --examples          Only test examples
//     --help, -h          Show this help message
//
#import <standard.fx>;
#import <runtime/ffifio.fx>;
#import <runtime/timing.fx>;

using standard::io::console;
using standard::time;
using standard::io::file;

#ifndef __WINDOWS__
extern
{
    def !!
        system(byte*) -> int;
};
#endif;

#ifdef __WINDOWS__
extern
{
    def !!
        system(byte*) -> int;
};
#endif;

#ifdef __WINDOWS__
// Stack probe the linker asks for when a frame is large (no CRT is linked)
def !!__chkstk() -> void {};
#endif;

#def MAX_TESTS   2048;
#def NAME_MAX    256;
#def PATH_MAX    1024;
#def LINE_MAX    128;

#def TMP_LIST    ".run_tests_list.tmp\0";
#def TMP_OUT     ".run_tests_out.tmp\0";
#def TMP_ERR     ".run_tests_err.tmp\0";

struct TestResult
{
    byte[NAME_MAX] name;
    byte[LINE_MAX] msg;     // first line of the compile or run error
    bool compile_ok;
    int  run_state;         // 0 = failed, 1 = passed, 2 = not run
    i64  compile_ns, run_ns;
};

global bool g_verbose, g_keep, g_compile_only, g_examples;
global byte[NAME_MAX] g_filter;
global bool g_has_filter;

// ---------------------------------------------------------------------------
// String helpers
// ---------------------------------------------------------------------------

def slen(byte* s) -> int
{
    int n;
    while (s[n] != 0) { n++; };
    return n;
};

// Appends src to the null terminated dst, which holds cap bytes
def scat(byte* dst, int cap, byte* src) -> void
{
    int n = slen(dst);
    int i;
    while (src[i] != 0 & n + 1 < cap)
    {
        dst[n] = src[i];
        n++;
        i++;
    };
    dst[n] = (byte)0;
    return;
};

def scpy(byte* dst, int cap, byte* src) -> void
{
    dst[0] = (byte)0;
    scat(dst, cap, src);
    return;
};

def seq(byte* a, byte* b) -> bool
{
    int i;
    while (a[i] != 0 & b[i] != 0)
    {
        if (a[i] != b[i]) { return false; };
        i++;
    };
    return a[i] == b[i];
};

// Orders two strings bytewise: negative, zero or positive
def scmp(byte* a, byte* b) -> int
{
    int i;
    while (a[i] != 0 & a[i] == b[i]) { i++; };
    return (int)a[i] - (int)b[i];
};

def lower(byte c) -> byte
{
    if (c >= 'A' & c <= 'Z') { return (byte)(c + 32); };
    return c;
};

// True when hay contains needle, ignoring ASCII case
def contains_nocase(byte* hay, byte* needle) -> bool
{
    int n = slen(needle);
    int h = slen(hay);
    int i, j;
    bool hit;
    while (i + n <= h)
    {
        hit = true;
        j = 0;
        while (j < n)
        {
            if (lower(hay[i + j]) != lower(needle[j])) { hit = false; break; };
            j++;
        };
        if (hit) { return true; };
        i++;
    };
    return false;
};

def ends_with(byte* s, byte* suffix) -> bool
{
    int n = slen(s);
    int m = slen(suffix);
    if (m > n) { return false; };
    return seq(@s[n - m], suffix);
};

// Appends the decimal text of v
def scat_int(byte* dst, int cap, int v) -> void
{
    byte[16] tmp;
    int n, i;
    bool neg;
    byte[16] out;
    if (v < 0) { neg = true; v = 0 - v; };
    if (v == 0) { tmp[0] = '0'; n = 1; };
    while (v > 0)
    {
        tmp[n] = (byte)('0' + v % 10);
        n++;
        v = v / 10;
    };
    if (neg) { out[i] = '-'; i++; };
    while (n > 0)
    {
        n--;
        out[i] = tmp[n];
        i++;
    };
    out[i] = (byte)0;
    scat(dst, cap, @out[0]);
    return;
};

// Appends seconds with two decimals from a nanosecond count, as "%.2f"
def scat_secs(byte* dst, int cap, i64 ns) -> void
{
    i64 cs = (ns + (i64)5000000) / (i64)10000000;
    int whole = (int)(cs / (i64)100);
    int frac = (int)(cs % (i64)100);
    scat_int(dst, cap, whole);
    scat(dst, cap, ".\0");
    if (frac < 10) { scat(dst, cap, "0\0"); };
    scat_int(dst, cap, frac);
    return;
};

// Prints s left-justified in a field of width w
def print_pad(byte* s, int w) -> void
{
    int n = slen(s);
    print(s);
    while (n < w)
    {
        print(" \0");
        n++;
    };
    return;
};

// ---------------------------------------------------------------------------
// Files and processes
// ---------------------------------------------------------------------------

def file_exists(byte* path) -> bool
{
    void* f = fopen(path, "rb\0");
    if (f == (void*)0) { return false; };
    fclose(f);
    return true;
};

// Reads the whole file into a heap buffer. Returns null on failure.
def read_file(byte* path) -> byte*
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
    if (n < 0) { n = 0; };
    buf[n] = (byte)0;
    return buf;
};

// Runs a shell command and returns its exit code. The runtime entry leaves the stack
// 8 bytes off the ABI alignment, which libc's system() cannot tolerate, so the call
// is made through an aligned stack.
def run_cmd(byte* c) -> int
{
    int rc;
    int* rcp = @rc;
    #ifdef __WINDOWS__
    // cmd /c drops the outermost quotes, so the whole command is wrapped once more
    byte[2048] w;
    scpy(@w[0], 2048, "\"\0");
    scat(@w[0], 2048, c);
    scat(@w[0], 2048, "\"\0");
    rc = system(@w[0]);
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
    // system() returns the wait status: the exit code is in the second byte
    if ((rc & 127) != 0) { rc = 128 + (rc & 127); }
    else { rc = (rc >> 8) & 255; };
    #endif;
    return rc;
};

// Removes the first line break and everything after it, replaces non-ASCII bytes with '?'
// and keeps at most LINE_MAX - 1 bytes. Leading blanks are skipped.
def first_line(byte* text, byte* dst) -> void
{
    int i, n;
    dst[0] = (byte)0;
    if (text == (byte*)0) { return; };
    while (text[i] == ' ' | text[i] == 9 | text[i] == 10 | text[i] == 13) { i++; };
    while (text[i] != 0 & text[i] != 10 & text[i] != 13 & n + 1 < LINE_MAX)
    {
        if (text[i] > 127) { dst[n] = '?'; } else { dst[n] = text[i]; };
        n++;
        i++;
    };
    while (n > 0 & dst[n - 1] == ' ') { n--; };
    dst[n] = (byte)0;
    return;
};

// First line of text that contains needle, as plain text in dst (escape sequences removed)
def line_with(byte* text, byte* needle, byte* dst) -> void
{
    byte[LINE_MAX * 4] raw;
    int p, n, i, m;
    bool esc;
    byte[LINE_MAX * 4] plain;
    dst[0] = (byte)0;
    if (text == (byte*)0) { return; };
    while (text[p] != 0)
    {
        n = 0;
        while (text[p] != 0 & text[p] != 10)
        {
            if (n + 1 < LINE_MAX * 4) { raw[n] = text[p]; n++; };
            p++;
        };
        raw[n] = (byte)0;
        if (text[p] == 10) { p++; };
        // drop ANSI color sequences
        m = 0;
        i = 0;
        esc = false;
        while (i < n)
        {
            if (raw[i] == 27) { esc = true; }
            elif (esc)
            {
                if (raw[i] == 'm') { esc = false; };
            }
            else
            {
                plain[m] = raw[i];
                m++;
            };
            i++;
        };
        plain[m] = (byte)0;
        if (contains_nocase(@plain[0], needle))
        {
            first_line(@plain[0], dst);
            return;
        };
    };
    return;
};

// Prints text with surrounding whitespace removed
def print_trimmed(byte* text) -> void
{
    int s, e;
    byte[LINE_MAX] seg;
    int i, n;
    if (text == (byte*)0) { return; };
    e = slen(text);
    while (s < e & (text[s] == ' ' | text[s] == 9 | text[s] == 10 | text[s] == 13)) { s++; };
    while (e > s & (text[e - 1] == ' ' | text[e - 1] == 9 | text[e - 1] == 10 | text[e - 1] == 13)) { e--; };
    // printed in chunks so the segment buffer stays small
    i = s;
    while (i < e)
    {
        n = 0;
        while (i < e & n + 1 < LINE_MAX)
        {
            if (text[i] > 127) { seg[n] = '?'; } else { seg[n] = text[i]; };
            n++;
            i++;
        };
        seg[n] = (byte)0;
        print(@seg[0]);
    };
    println("\0");
    return;
};

// Last path component of a path
def base_name(byte* path) -> byte*
{
    int i;
    int start;
    while (path[i] != 0)
    {
        if (path[i] == '/' | path[i] == 92) { start = i + 1; };
        i++;
    };
    return @path[start];
};

// Name without its extension, written to dst
def stem_of(byte* name, byte* dst, int cap) -> void
{
    int n = slen(name);
    int i = n - 1;
    int end = n;
    while (i > 0)
    {
        if (name[i] == '.') { end = i; break; };
        i--;
    };
    i = 0;
    while (i < end & i + 1 < cap)
    {
        dst[i] = name[i];
        i++;
    };
    dst[i] = (byte)0;
    return;
};

// Executable file name for a test stem
def exe_name_of(byte* stem, byte* dst, int cap) -> void
{
    scpy(dst, cap, stem);
    #ifdef __WINDOWS__
    scat(dst, cap, ".exe\0");
    #endif;
    return;
};

// build/<stem>/<exe>
def build_exe_path(byte* stem, byte* dst, int cap) -> void
{
    byte[NAME_MAX] exe;
    exe_name_of(stem, @exe[0], NAME_MAX);
    scpy(dst, cap, "build/\0");
    scat(dst, cap, stem);
    scat(dst, cap, "/\0");
    scat(dst, cap, @exe[0]);
    return;
};

// ---------------------------------------------------------------------------
// Test discovery
// ---------------------------------------------------------------------------

def dir_exists(byte* dir) -> bool
{
    byte[PATH_MAX] cmd;
    #ifdef __WINDOWS__
    scpy(@cmd[0], PATH_MAX, "if exist \0");
    scat(@cmd[0], PATH_MAX, dir);
    scat(@cmd[0], PATH_MAX, "\\nul (exit 0) else (exit 1)\0");
    #else
    scpy(@cmd[0], PATH_MAX, "test -d \0");
    scat(@cmd[0], PATH_MAX, dir);
    #endif;
    return run_cmd(@cmd[0]) == 0;
};

def make_dir(byte* dir) -> void
{
    byte[PATH_MAX] cmd;
    #ifdef __WINDOWS__
    scpy(@cmd[0], PATH_MAX, "mkdir \0");
    #else
    scpy(@cmd[0], PATH_MAX, "mkdir -p \0");
    #endif;
    scat(@cmd[0], PATH_MAX, dir);
    run_cmd(@cmd[0]);
    return;
};

def remove_file(byte* path) -> void
{
    byte[PATH_MAX] cmd;
    #ifdef __WINDOWS__
    scpy(@cmd[0], PATH_MAX, "del /q \"\0");
    scat(@cmd[0], PATH_MAX, path);
    scat(@cmd[0], PATH_MAX, "\" >nul 2>nul\0");
    #else
    scpy(@cmd[0], PATH_MAX, "rm -f \"\0");
    scat(@cmd[0], PATH_MAX, path);
    scat(@cmd[0], PATH_MAX, "\" 2>/dev/null\0");
    #endif;
    run_cmd(@cmd[0]);
    return;
};

def remove_dir(byte* path) -> void
{
    byte[PATH_MAX] cmd;
    #ifdef __WINDOWS__
    scpy(@cmd[0], PATH_MAX, "rmdir /s /q \"\0");
    scat(@cmd[0], PATH_MAX, path);
    scat(@cmd[0], PATH_MAX, "\" >nul 2>nul\0");
    #else
    scpy(@cmd[0], PATH_MAX, "rm -rf \"\0");
    scat(@cmd[0], PATH_MAX, path);
    scat(@cmd[0], PATH_MAX, "\" 2>/dev/null\0");
    #endif;
    run_cmd(@cmd[0]);
    return;
};

// Finds the .fx files of dir (names only, sorted, filtered). Returns the count.
// names receives MAX_TESTS entries of NAME_MAX bytes each.
def find_test_files(byte* dir, byte* names) -> int
{
    byte[PATH_MAX] cmd;
    byte* text;
    byte[NAME_MAX] line;
    byte* nm;
    int count, i, j, k, n, p;
    byte[NAME_MAX] tmp;

    #ifdef __WINDOWS__
    scpy(@cmd[0], PATH_MAX, "dir /b \0");
    scat(@cmd[0], PATH_MAX, dir);
    scat(@cmd[0], PATH_MAX, "\\*.fx > \0");
    scat(@cmd[0], PATH_MAX, TMP_LIST);
    scat(@cmd[0], PATH_MAX, " 2>nul\0");
    #else
    scpy(@cmd[0], PATH_MAX, "ls -1 \0");
    scat(@cmd[0], PATH_MAX, dir);
    scat(@cmd[0], PATH_MAX, "/*.fx > \0");
    scat(@cmd[0], PATH_MAX, TMP_LIST);
    scat(@cmd[0], PATH_MAX, " 2>/dev/null\0");
    #endif;
    run_cmd(@cmd[0]);

    text = read_file(TMP_LIST);
    remove_file(TMP_LIST);
    if (text == (byte*)0) { return 0; };

    p = 0;
    while (text[p] != 0 & count < MAX_TESTS)
    {
        n = 0;
        while (text[p] != 0 & text[p] != 10)
        {
            if (text[p] != 13 & n + 1 < NAME_MAX)
            {
                line[n] = text[p];
                n++;
            };
            p++;
        };
        line[n] = (byte)0;
        if (text[p] == 10) { p++; };
        if (n > 0)
        {
            nm = base_name(@line[0]);
            if (ends_with(nm, ".fx\0"))
            {
                if (!g_has_filter | contains_nocase(nm, @g_filter[0]))
                {
                    scpy(@names[count * NAME_MAX], NAME_MAX, nm);
                    count++;
                };
            };
        };
    };
    ffree(text);

    // Insertion sort, bytewise like sorted() on the file names
    i = 1;
    while (i < count)
    {
        scpy(@tmp[0], NAME_MAX, @names[i * NAME_MAX]);
        j = i - 1;
        while (j >= 0 & scmp(@names[j * NAME_MAX], @tmp[0]) > 0)
        {
            scpy(@names[(j + 1) * NAME_MAX], NAME_MAX, @names[j * NAME_MAX]);
            j--;
        };
        scpy(@names[(j + 1) * NAME_MAX], NAME_MAX, @tmp[0]);
        i++;
    };
    return count;
};

// ---------------------------------------------------------------------------
// Compile and run
// ---------------------------------------------------------------------------

// Compiles dir/name with `fxc`. On success exe_out receives the executable path.
// err_out receives the first line of the compiler's stderr on failure.
def run_compiler(byte* dir, byte* name, byte* exe_out, byte* err_out, i64* ns_out) -> bool
{
    byte[PATH_MAX] cmd;
    byte[NAME_MAX] stem;
    byte[NAME_MAX] exe;
    byte* errtext;
    byte* outtext;
    i64 t0, t1;
    int rc;

    print("Compiling: \0");
    print(name);
    print("...\0");

    stem_of(name, @stem[0], NAME_MAX);

    scpy(@cmd[0], PATH_MAX, "fxc \0");
    scat(@cmd[0], PATH_MAX, dir);
    scat(@cmd[0], PATH_MAX, "/\0");
    scat(@cmd[0], PATH_MAX, name);
    scat(@cmd[0], PATH_MAX, " > \0");
    scat(@cmd[0], PATH_MAX, TMP_OUT);
    scat(@cmd[0], PATH_MAX, " 2> \0");
    scat(@cmd[0], PATH_MAX, TMP_ERR);

    if (g_verbose)
    {
        println("\0");
        print("   Command: fxc \0");
        print(dir);
        print("/\0");
        println(name);
    };

    t0 = time_now();
    rc = run_cmd(@cmd[0]);
    t1 = time_now();
    *ns_out = t1 - t0;

    errtext = read_file(TMP_ERR);

    if (rc == 0)
    {
        // The executable lands in the project root or in build/<stem>/
        exe_name_of(@stem[0], @exe[0], NAME_MAX);
        if (file_exists(@exe[0]))
        {
            scpy(exe_out, PATH_MAX, @exe[0]);
        }
        else
        {
            build_exe_path(@stem[0], exe_out, PATH_MAX);
        };
        if (file_exists(exe_out))
        {
            print("OK (\0");
            byte[32] ts;
            scat_secs(@ts[0], 32, *ns_out);
            print(@ts[0]);
            println("s)\0");
            if (errtext != (byte*)0) { ffree(errtext); };
            return true;
        };
        println("FAILED (executable not found)\0");
        scpy(err_out, LINE_MAX, "Executable not generated\0");
        if (errtext != (byte*)0) { ffree(errtext); };
        return false;
    };

    byte[32] ts2;
    scat_secs(@ts2[0], 32, *ns_out);
    println("\0");
    print("FAILED (\0");
    print(@ts2[0]);
    println("s)\0");
    if (errtext != (byte*)0 & errtext[0] != 0)
    {
        first_line(errtext, err_out);
    }
    else
    {
        // The compiler reports some errors on stdout
        outtext = read_file(TMP_OUT);
        line_with(outtext, "error\0", err_out);
        if (outtext != (byte*)0) { ffree(outtext); };
    };
    if (err_out[0] == 0 & rc == 127)
    {
        scpy(err_out, LINE_MAX, "fxc not found, it must be on PATH\0");
    };
    if (g_verbose)
    {
        println("   Error output:\0");
        if (errtext != (byte*)0 & errtext[0] != 0) { print_trimmed(errtext); }
        else { print_trimmed(err_out); };
    };
    if (errtext != (byte*)0) { ffree(errtext); };
    return false;
};

// Runs the executable. err_out receives the first line of stderr on failure.
def run_executable(byte* exe_path, byte* name, byte* err_out, i64* ns_out) -> bool
{
    byte[PATH_MAX] cmd;
    byte* outtext;
    byte* errtext;
    byte[32] ts;
    i64 t0, t1;
    int rc;
    bool ok;

    if (!file_exists(exe_path))
    {
        scpy(err_out, LINE_MAX, "Executable not found\0");
        return false;
    };

    print("   Running \0");
    print(name);
    print(" ...\0");

    #ifdef __WINDOWS__
    scpy(@cmd[0], PATH_MAX, "\0");
    #else
    scpy(@cmd[0], PATH_MAX, "timeout 5 \0");
    #endif;
    scat(@cmd[0], PATH_MAX, exe_path);
    scat(@cmd[0], PATH_MAX, " > \0");
    scat(@cmd[0], PATH_MAX, TMP_OUT);
    scat(@cmd[0], PATH_MAX, " 2> \0");
    scat(@cmd[0], PATH_MAX, TMP_ERR);

    t0 = time_now();
    rc = run_cmd(@cmd[0]);
    t1 = time_now();
    *ns_out = t1 - t0;
    scat_secs(@ts[0], 32, *ns_out);

    outtext = read_file(TMP_OUT);
    errtext = read_file(TMP_ERR);
    ok = rc == 0;

    #ifndef __WINDOWS__
    if (rc == 124)
    {
        print("FAILED (timeout after \0");
        print(@ts[0]);
        println("s)\0");
        scpy(err_out, LINE_MAX, "Timeout expired\0");
        if (outtext != (byte*)0) { ffree(outtext); };
        if (errtext != (byte*)0) { ffree(errtext); };
        return false;
    };
    #endif;

    if (ok)
    {
        print("OK (\0");
        print(@ts[0]);
        println("s)\0");
        if (g_verbose & outtext != (byte*)0 & outtext[0] != 0)
        {
            print("   Output: \0");
            print_trimmed(outtext);
        };
    }
    else
    {
        print("RAN (exit code: \0");
        byte[16] code;
        code[0] = (byte)0;
        scat_int(@code[0], 16, rc);
        print(@code[0]);
        println(") ERR\0");
        if (errtext != (byte*)0) { first_line(errtext, err_out); };
        if (g_verbose)
        {
            if (outtext != (byte*)0 & outtext[0] != 0)
            {
                print("   Stdout: \0");
                print_trimmed(outtext);
            };
            if (errtext != (byte*)0 & errtext[0] != 0)
            {
                print("   Stderr: \0");
                print_trimmed(errtext);
            };
        };
    };
    if (outtext != (byte*)0) { ffree(outtext); };
    if (errtext != (byte*)0) { ffree(errtext); };
    return ok;
};

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

// Removes what the compiler generated. build/ itself is left alone because the
// compiler may live inside it.
def cleanup_artifacts(byte* dir, byte* names, int count) -> void
{
    byte[NAME_MAX] stem;
    byte[NAME_MAX] exe;
    byte[PATH_MAX] path;
    int i, removed;

    if (g_keep)
    {
        println("\nArtifacts preserved (--keep-artifacts)\0");
        return;
    };

    println("\nCleaning up artifacts...\0");

    while (i < count)
    {
        stem_of(@names[i * NAME_MAX], @stem[0], NAME_MAX);
        exe_name_of(@stem[0], @exe[0], NAME_MAX);

        if (file_exists(@exe[0]))
        {
            remove_file(@exe[0]);
            print("   Removed: \0");
            println(@exe[0]);
            removed++;
        };

        scpy(@path[0], PATH_MAX, dir);
        scat(@path[0], PATH_MAX, "/\0");
        scat(@path[0], PATH_MAX, @exe[0]);
        if (file_exists(@path[0]))
        {
            remove_file(@path[0]);
            print("   Removed: \0");
            println(@path[0]);
            removed++;
        };

        build_exe_path(@stem[0], @path[0], PATH_MAX);
        if (file_exists(@path[0]))
        {
            scpy(@path[0], PATH_MAX, "build/\0");
            scat(@path[0], PATH_MAX, @stem[0]);
            remove_dir(@path[0]);
            print("   Removed: build/\0");
            print(@stem[0]);
            println("/\0");
            removed++;
        };
        i++;
    };

    if (removed == 0) { println("   No artifacts to clean up\0"); };
    return;
};

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

def print_status_line(TestResult* r) -> void
{
    byte[64] ts;
    bool pass = r.compile_ok & (g_compile_only | r.run_state == 1);

    if (pass) { print_pad("PASS\0", 5); } else { print_pad("FAIL\0", 5); };
    print(" \0");
    print_pad(@r.name[0], 30);
    print(" \0");

    ts[0] = (byte)0;
    scat_secs(@ts[0], 64, r.compile_ns);
    if (g_compile_only)
    {
        print("Compile: \0");
        if (r.compile_ok) { print("PASS\0"); } else { print("FAIL\0"); };
        print(" (\0");
        print(@ts[0]);
        println("s)\0");
        return;
    };

    if (!r.compile_ok)
    {
        print("Compile: FAIL (\0");
        print(@ts[0]);
        println("s)\0");
        return;
    };

    print("Compile: PASS (\0");
    print(@ts[0]);
    print("s), Run: \0");
    if (r.run_state == 1) { print("PASS\0"); } else { print("FAIL\0"); };
    print(" (\0");
    ts[0] = (byte)0;
    scat_secs(@ts[0], 64, r.run_ns);
    print(@ts[0]);
    println("s)\0");
    return;
};

def run_tests(byte* dir) -> bool
{
    byte* names = (byte*)fmalloc((u64)(MAX_TESTS * NAME_MAX));
    TestResult* results = (TestResult*)fmalloc((u64)(MAX_TESTS * sizeof(TestResult) / 8 + 1) * (u64)8);
    int count = find_test_files(dir, names);
    int i, passed;
    i64 total_compile, total_run;
    byte[PATH_MAX] exe_path;
    byte[64] ts;
    TestResult* r;
    bool compile_ok, run_ok;

    if (count == 0)
    {
        print("No .fx files found in \0");
        println(dir);
        println("   Add your test files to the tests/ directory\0");
        ffree(names);
        ffree((byte*)results);
        return true;
    };

    print("Running \0");
    scat_int(@ts[0], 64, count);
    print(@ts[0]);
    print(" test(s) from \0");
    println(dir);
    print("   Verbose: \0");
    if (g_verbose) { println("True\0"); } else { println("False\0"); };
    print("   Keep artifacts: \0");
    if (g_keep) { println("True\0"); } else { println("False\0"); };
    print("   Compile only: \0");
    if (g_compile_only) { println("True\0"); } else { println("False\0"); };
    if (g_has_filter)
    {
        print("   Filter: '\0");
        print(@g_filter[0]);
        println("'\0");
    };
    println("\0");

    while (i < count)
    {
        r = @results[i];
        scpy(@r.name[0], NAME_MAX, @names[i * NAME_MAX]);
        r.msg[0] = (byte)0;
        r.run_state = 2;

        compile_ok = run_compiler(dir, @r.name[0], @exe_path[0], @r.msg[0], @r.compile_ns);
        r.compile_ok = compile_ok;
        total_compile = total_compile + r.compile_ns;

        if (compile_ok)
        {
            if (!g_compile_only)
            {
                run_ok = run_executable(@exe_path[0], @r.name[0], @r.msg[0], @r.run_ns);
                total_run = total_run + r.run_ns;
                if (run_ok) { r.run_state = 1; passed++; }
                else { r.run_state = 0; };
            }
            else
            {
                passed++;
            };
        };
        println("\0");
        i++;
    };

    println("\n============================================================\0");
    println("TEST SUMMARY\0");
    println("============================================================\0");

    i = 0;
    while (i < count)
    {
        r = @results[i];
        print_status_line(r);
        if (g_verbose & r.msg[0] != 0 & (!r.compile_ok | (r.run_state == 0 & !g_compile_only)))
        {
            print("     Error: \0");
            print(@r.msg[0]);
            println("...\0");
        };
        i++;
    };

    println("============================================================\0");
    print("Total Tests: \0");
    ts[0] = (byte)0;
    scat_int(@ts[0], 64, count);
    println(@ts[0]);

    print("Passed: \0");
    ts[0] = (byte)0;
    scat_int(@ts[0], 64, passed);
    print(@ts[0]);
    print(" (\0");
    // one decimal place of the percentage
    int tenths = (passed * 1000 + count / 2) / count;
    ts[0] = (byte)0;
    scat_int(@ts[0], 64, tenths / 10);
    scat(@ts[0], 64, ".\0");
    scat_int(@ts[0], 64, tenths % 10);
    print(@ts[0]);
    println("%)\0");

    print("Failed: \0");
    ts[0] = (byte)0;
    scat_int(@ts[0], 64, count - passed);
    println(@ts[0]);

    print("Total compile time: \0");
    ts[0] = (byte)0;
    scat_secs(@ts[0], 64, total_compile);
    print(@ts[0]);
    println("s\0");
    if (!g_compile_only)
    {
        print("Total run time: \0");
        ts[0] = (byte)0;
        scat_secs(@ts[0], 64, total_run);
        print(@ts[0]);
        println("s\0");
        print("Total time: \0");
        ts[0] = (byte)0;
        scat_secs(@ts[0], 64, total_compile + total_run);
        print(@ts[0]);
        println("s\0");
    };
    println("============================================================\0");

    cleanup_artifacts(dir, names, count);
    remove_file(TMP_OUT);
    remove_file(TMP_ERR);

    ffree(names);
    ffree((byte*)results);
    return passed == count;
};

def print_usage() -> void
{
    println("Flux Compiler Test Runner\0");
    println("\0");
    println("Usage:\0");
    println("    run_tests [options]\0");
    println("\0");
    println("Options:\0");
    println("    --verbose, -v       Show detailed output for each test\0");
    println("    --keep-artifacts    Keep compiled executables after tests\0");
    println("    --compile-only      Only compile, don't run the executables\0");
    println("    --filter PATTERN    Only run tests matching pattern (substring match)\0");
    println("    --examples          Only test examples\0");
    println("    --help, -h          Show this help message\0");
    println("\0");
    println("Examples:\0");
    println("  run_tests                  # Run all tests\0");
    println("  run_tests -v               # Run with verbose output\0");
    println("  run_tests --filter hello   # Only run tests with 'hello' in filename\0");
    println("  run_tests --compile-only   # Only compile, don't run executables\0");
    println("  run_tests --keep-artifacts # Keep compiled executables\0");
    return;
};

def main(int argc, byte** argv) -> int
{
    int i = 1;
    byte* a;
    byte* dir;
    byte[NAME_MAX] hello;
    void* f;
    bool ok;

    // Referenced so the memset used for zero initialization is kept in the link
    memset((void*)@g_filter[0], 0, (size_t)NAME_MAX);

    while (i < argc)
    {
        a = argv[i];
        if (seq(a, "--verbose\0") | seq(a, "-v\0")) { g_verbose = true; }
        elif (seq(a, "--keep-artifacts\0")) { g_keep = true; }
        elif (seq(a, "--compile-only\0")) { g_compile_only = true; }
        elif (seq(a, "--examples\0")) { g_examples = true; }
        elif (seq(a, "--help\0") | seq(a, "-h\0"))
        {
            print_usage();
            return 0;
        }
        elif (seq(a, "--filter\0"))
        {
            i++;
            if (i >= argc)
            {
                println("error: --filter requires a pattern\0");
                return 2;
            };
            scpy(@g_filter[0], NAME_MAX, argv[i]);
            g_has_filter = true;
        }
        else
        {
            print("error: unrecognized argument: \0");
            println(a);
            return 2;
        };
        i++;
    };

    if (g_examples) { dir = "examples\0"; } else { dir = "tests\0"; };

    if (!dir_exists(dir))
    {
        print("Warning: Test directory not found at \0");
        println(dir);
        println("   Creating tests/ directory...\0");
        make_dir(dir);
        print("   Created \0");
        println(dir);
        println("   Please add your .fx test files to this directory\0");

        // A simple test file as an example
        scpy(@hello[0], NAME_MAX, dir);
        scat(@hello[0], NAME_MAX, "/hello.fx\0");
        if (!file_exists(@hello[0]))
        {
            f = fopen(@hello[0], "wb\0");
            if (f != (void*)0)
            {
                byte* src = "#import <standard.fx>;\n\ndef main() -> int\n{\n    println(\"Hello from test!\\0\");\n    return 0;\n};\n\0";
                fwrite(src, 1, slen(src), f);
                fclose(f);
                print("   Created example test: \0");
                println(@hello[0]);
            };
        };
    };

    ok = run_tests(dir);
    if (ok) { return 0; };
    return 1;
};
