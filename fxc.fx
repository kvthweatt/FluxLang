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
#import <runtime\ffifio.fx>;
#import "src\compiler\flexer.fx";
#import "src\compiler\fpreprocess.fx";
#import "src\compiler\fast.fx";
#import "src\compiler\fparser.fx";
#import "src\compiler\ftypesys.fx";
#import "src\compiler\fcheck.fx";

using standard::io::console;
using standard::io::file;
using flux::lexer;
using flux::preprocessor;
using flux::ast;
using flux::parser;
using flux::types;
using flux::check;

def usage() -> void
{
    println("Flux Compiler (bootstrap)\0");
    println("Usage: fxc <input.fx> [options]\0");
    println("\0");
    println("Options:\0");
    println("  -E, --preprocess  Run the preprocessor and print the result\0");
    println("  --lex           Preprocess, then run the lexer and report tokens\0");
    println("  --parse         Preprocess, lex, then run the bootstrap parser\0");
    println("  --dump          Parse, then print the syntax tree\0");
    println("  --check         Parse, then declare symbols and run the type check pass\0");
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

def main(int argc, byte** argv) -> int
{
    // argc is 2 for a single argument. With no arguments argv must not be indexed.
    if (argc < 2)
    {
        usage();
        return 1;
    };

    bool lex_mode, pp_mode, parse_mode, check_mode, dump_mode, verbose, show_count;
    byte* path = (byte*)0;
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
        println("Nothing to do: no stage selected. Use -E, --lex or --parse.\0");
        usage();
        return 1;
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

    if (parse_mode)
    {
        Node* prog = ps.parse();
        if (ps.failed)
        {
            ps.print_error();
            return 1;
        };
        ps.report();
        print("=== Parse Summary for \0");
        print(path);
        println(" ===\0");
        print("Top-level statements: \0");
        println(node_count(prog, 0));
        if (dump_mode) { dump_node(prog, 0, -1, 0); };
        if (check_mode)
        {
            FXC_SYMTABLE* st = st_new();
            defer st_free(st);
            Checker ck(st);
            defer ck.__exit();
            print("Symbols declared: \0");
            println(ck.declare_program(prog));
            ck.print_diags(path);
            print("Errors: \0");
            print(ck.errors);
            print(", warnings: \0");
            println(ck.warnings);
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
