<h1 align="center">IDEKA v2 "Dangling Ditto"</h1>

<p align="center">
    <img width="512" height="512" alt="IDEKA Logo" src="https://github.com/user-attachments/assets/58da57a7-1924-48a2-ba29-c2040d9343eb" />
</p>

<p align="center">
  <a href="https://discord.gg/wVAm2E6ymf">Discord</a> ·
  <a href="https://fluxspl.org/ide">Online Compiler</a> ·
  <a href="docs/Specs/language_specification.md">Language Specification</a> ·
  <a href="docs/learn_flux_intro.md">Getting Started</a>
</p>

---

IDEKA ("I Don't Even Know Anymore") is a compiled, statically typed systems programming language with the performance of C and a type system that goes further than C in every direction that matters.

- **Operators are part of the grammar.** Every operator you declare, made of punctuation or words, becomes part of the language's grammar, the same as the built-in ones.
- **Bits are first class.** Bit slices, bit indexing, arbitrary-width integers, and endianness live in the type system.
- **Compile-time code generation.** A built-in VM runs IDEKA at compile time and `emitflux` writes new definitions into your program.
- **Interfaces** that govern which objects may call, feed, and be called from which other objects, enforced by the compiler.
- **A module system** with per-module build settings, declared dependencies, and overrides.
- **Contracts, templates with type geometry constraints, opt-in ownership, and a completely optional borrow checker.**

It is not a C derivative, and it is not a safe language in the Rust sense. It is a high-trust language that gives you sharp tools and expects you to use them correctly. It is dense, with a low learning curve and a high skill ceiling.

The language was previously called Flux. Some names in the compiler still carry it (`fxc.py`, `emitflux`, `FLUXC_SRCDIR`) and will follow the new name in an upcoming patch.

As of 10/12/2026, **IDEKA is bootstrapped and can compile itself**. It is recommended you bootstrap your compiler by running `python fxc.py fxc.fx` for faster compile times.

---

## A first look

A struct filled in with a block, a byte pulled apart with bit slices, the bits reversed in one assignment, and a three-way comparison operator the language does not ship with:

```
struct Pixel { byte r, g, b, a; };

operator (int L, int R) [<=>] -> int
{
    if (L < R) { return -1; };
    if (L > R) { return  1; };
    return 0;
};

def main() -> int
{
    data{4} as u4;

    Pixel p;
    p { .r = 0xB4; .g = 3; .b = 7; .a = 255; };       // block assignment

    byte r  = p.r;
    u4   hi = r[0``3];                                // bit slice: top nibble
    u4   lo = r[4``7];                                // bottom nibble
    r[0``7] = r[7``0];                                // reverse all eight bits

    println(f"{int(hi)} {int(lo)} {int(r)} {p.g <=> p.b}");
    return 0;
};
```

```
11 4 45 -1
```

Every one of those lines is a feature the rest of this page takes apart.

---

## Define your own operators

Declaring an operator extends the grammar. It can be punctuation or a word, and it can take any types you like.

```
struct Vec2 { float x, y; };

// A new operator made of punctuation
operator (int L, int R) [<=>] -> int
{
    if (L < R) { return -1; };
    if (L > R) { return  1; };
    return 0;
};

// A new operator made of a word
operator (int L, int R) [NAND] -> int
{
    return !(L & R);
};

// Operators take any type: here, two Vec2 pointers
operator (Vec2* L, Vec2* R) [DOT] -> float
{
    return L.x * R.x + L.y * R.y;
};

def main() -> int
{
    Vec2 a = {1.0, 2.0};
    Vec2 b = {3.0, 4.0};
    Vec2* pa = @a;
    Vec2* pb = @b;

    println(f"{pa DOT pb}");                       // 11.0
    println(f"{7 <=> 3} {3 <=> 7} {5 <=> 5}");     // 1 -1 0
    println(f"{6 NAND 1} {6 NAND 2}");             // -1 -3  (bitwise: ! is complement on integers)
    return 0;
};
```

Custom operators parse at one fixed precedence tier, between `+`/`-` and `*`/`/`, always left-associative. Parenthesize at the call site to bind them tighter or looser. Contracts attach to operators exactly as they do to functions, and built-in operators can be overloaded for your own types.

---

## Block assignment

Stop repeating the name. Any struct variable, or any indexed element of an array of structs, takes a block:

```
struct Entry { int key, size; byte* name; };

def main() -> int
{
    Entry[4] table;

    // Block assignment works on a variable...
    Entry first;
    first
    {
        .key  = 1;
        .size = 64;
        .name = "alpha\0";
    };

    // ...and on an indexed element
    table[2]
    {
        .key  = first.key + 1;
        .size = first.size * 2;
        .name = "beta\0";
    };

    // Struct literals use the same shape
    Entry third = {3, 256, "gamma\0"};

    println(f"{table[2].key} {table[2].size} {table[2].name} {third.name}");
    return 0;
};
```

```
2 128 beta gamma
```

---

## Bits are first class

### Bit slices and bit indexing

`x[a``b]` reads or writes bits `a` through `b`. `x[`i]` addresses a single bit. Bit 0 is always the most significant bit, and numbering runs straight through struct field boundaries because structs have no hidden padding. A reversed range, like `x[7``0]`, reads the bits in reverse order.

```
struct Pair { int a, b; };
def main() -> int
{
    data{4} as u4;
    data{1} as bit;
    byte x = 0xA5;
    u4 hi = x[0``3];
    u4 lo = x[4``7];
    println(f"{int(hi)} {int(lo)}");

    u32 packed = 0x12345678;
    packed[24``31] = 0xFF;
    println(f"{packed}");

    u16 w = 0xABCD;
    u4 n = w[4``7];
    println(f"{int(n)}");

    byte r = 0b11010010;
    r[0``3] = r[3``0];
    println(f"{int(r)}");

    Pair p = {5, 10};
    u4 nib = p[60``63];
    println(f"{int(nib)}");
    return 0;
};
```

```
10 5
305420031
11
178
10
```

```
def main() -> int
{
    byte flags = 0b10100000;
    int a = flags[`0];
    int b = flags[`1];
    int c = flags[`2];
    println(f"{a} {b} {c}");
    flags[`7] = 1;
    flags[`0] = 0;
    println(f"{int(flags)}");
    u16 w = 0x8001;
    int hi = w[`0];
    int lo = w[`15];
    println(f"{hi} {lo}");
    return 0;
};
```

```
1 0 1
33
1 1
```

```
#import <standard.fx>;

using standard::io::console;

def main() -> int
{
    byte b;

    b[`7] = 1;

    println("Success!") if (b == 1);

    int i = 420691337;

    data{13} as d13;

    d13 d = 0b1010101010101;

    for (`x in i)  // "for bit x in i"
    {
        print((int)x);  // x is a data{1} type
    };

    print();

    for (`x in d)
    {
        print((int)x);
    };

    -> b[`0];
};
```

```
Success!
00011001000100110011110110001001
1010101010101
```

### Width, alignment, and endianness are part of the type

```
signed   data{13:16} as strange13;   // 13-bit signed, 16-bit aligned
unsigned data{3}     as tiny;        // 3-bit unsigned (0-7)
unsigned data{7:8}   as aligned7;    // 7-bit with 8-bit alignment
unsigned data{5}[10] as 5b_array;    // Array of ten 5-bit values

data{16}    as be16;   // Big-endian 16-bit  (default)
data{16::0} as le16;   // Little-endian 16-bit

// Assigning between endian types emits a byte swap automatically
le16 host   = (be16)network_value;
```

You are not masking bits out of a `uint32_t`. You are working with the type you actually have.

### 16 lines of C become 2 lines of IDEKA

This is real cryptography code. The C version is a manual byte-by-byte extraction. The IDEKA version is a direct consequence of how the type system works.

**C:**
```c
len_block[0]  = (byte)((aad_bits >> 56) & 0xFF);
len_block[1]  = (byte)((aad_bits >> 48) & 0xFF);
len_block[2]  = (byte)((aad_bits >> 40) & 0xFF);
len_block[3]  = (byte)((aad_bits >> 32) & 0xFF);
len_block[4]  = (byte)((aad_bits >> 24) & 0xFF);
len_block[5]  = (byte)((aad_bits >> 16) & 0xFF);
len_block[6]  = (byte)((aad_bits >>  8) & 0xFF);
len_block[7]  = (byte)( aad_bits        & 0xFF);
len_block[8]  = (byte)((cipher_bits >> 56) & 0xFF);
// ... 8 more identical lines
```

**IDEKA:**
```
len_block[0..7]  = (byte[8])(u64)aad_bits;
len_block[8..15] = (byte[8])(u64)cipher_bits;
```

Casting an integer to a fixed-size byte array packs the bytes big-endian into the array. No masking. No shifting. No loop. And with `be32` as a real type, the SHA-256 finalisation loop becomes eight lines with no `htonl` in sight:

```
hash[0..3]   = (byte[4])(be32)ctx.state[0];
hash[4..7]   = (byte[4])(be32)ctx.state[1];
// ...
hash[28..31] = (byte[4])(be32)ctx.state[7];
```

### Zero-copy packet parsing

```
struct Packet
{
    data{8}  type;
    data{16} length;
    data{32} timestamp;
    data{32} checksum;
};

def parse(byte* buf) -> void
{
    Packet pkt from buf;   // Reinterpret buf's bytes as a Packet in place. buf is consumed.

    println(f"Type:      {int(pkt.type)}");
    println(f"Length:    {pkt.length}");
    println(f"Timestamp: {pkt.timestamp}");
};
```

`from` recasts a byte buffer into a struct without copying. What you declare is what you get in memory.

---

## Interfaces

An interface says how objects may interact, and the compiler holds them to it. `A : B` lists the methods an `A` may call on a `B`. Call anything else and the program does not compile. Two more forms control which return values may be passed across the boundary (`B(A)`) and which methods may be called from inside the other object's methods (`A -> B`).

```
trait Queryable  { def query(byte* sql) -> byte*; };
trait Connectable { def connect() -> bool, disconnect() -> bool; };

interface Database(A: Connectable, B: Queryable)
{
    A : B { connect() -> bool };
};

object Client, Store;

object Store
{
    def __init() -> this { return this; };
    def __exit() -> void {};
    def __expr() -> int { return 0; };
    def query(byte* sql) -> byte* { return sql; };
    def connect() -> bool { return true; };
    def disconnect() -> bool { return true; };
} : Database(Client, this);

object Client
{
    def __init() -> this { return this; };
    def __exit() -> void {};
    def __expr() -> int { return 0; };
    def connect() -> bool { return true; };
    def disconnect() -> bool { return true; };

    def go(Store* s) -> void
    {
        s.connect();      // listed in A : B, allowed
        s.disconnect();   // not listed, compile error
    };
} : Database(this, Store);

def main() -> int
{
    Client c();
    Store  s();
    return 0;
};
```

```
Interface violation: Client is not permitted to call disconnect from Store
```

Attaching an interface also requires both sides to satisfy the traits it names, checked at compile time.

---

## Compile-time execution

IDEKA runs itself at compile time. A `comptime` block executes inside the compiler, in the built-in VM, with file and console I/O available. Its results can become part of your program.

```
comptime
{
    // Runs inside the compiler. Nothing here exists in the binary.
    int a = 0;
    int b = 1;
    int t, n;
    while (n < 30)
    {
        t = a + b;
        a = b;
        b = t;
        n++;
    };
    compiler.io.console.println(f"[comptime] fib(30) = {a}");

    emitflux
    {
        def fib30() -> int { return ~$f"{a}"; };
    };
};

def main() -> int
{
    println(f"{fib30()}");     // a constant, computed before the program existed
    return 0;
};
```

```
[comptime] fib(30) = 832040      <- printed by the compiler
832040                           <- printed by the program
```

### Generate code with `emitflux`

`emitflux` injects real IDEKA definitions into the program from inside a comptime block. Combine it with comptime loops and you get code generation without a macro preprocessor. Here a loop writes four functions, then builds a `dispatch` function whose `switch` is assembled one case at a time:

```
#def NUM_OPS 4;

comptime
{
    byte*[NUM_OPS] op_names = ["add", "sub", "mul", "div"];
    byte*[NUM_OPS] op_exprs = ["a + b", "a - b", "a * b", "a / b"];

    // One function per operation: op_add, op_sub, op_mul, op_div
    int i;
    byte* nm;
    byte* expr;
    while (i < NUM_OPS)
    {
        nm   = op_names[i];
        expr = op_exprs[i];
        emitflux
        {
            def ~$i"op_{}":{nm} (int a, int b) -> int { return ~$expr; };
        };
        i++;
    };

    // Open dispatch() and its switch, then drop back into comptime with }#;
    emitflux
    {
        def dispatch(int id, int a, int b) -> int
        {
            switch (id)
            {
    }#;

    // One case per operation, emitted from a loop
    int j, jv;
    while (j < NUM_OPS)
    {
        nm = op_names[j];
        jv = j;
        emitflux
        {
                case (~$f"{jv}") { return ~$i"op_{}":{nm;} (a, b); }
        };
        j++;
    };

    // Close the switch and the function
    emitflux
    {
                default { return -1; };
           #};
       #};
    };
};

def main() -> int
{
    println(f"{dispatch(0, 12, 4)} {dispatch(1, 12, 4)} {dispatch(2, 12, 4)} {dispatch(3, 12, 4)} {dispatch(9, 1, 1)}");
    return 0;
};
```

```
16 8 48 3 -1
```

`}#;` leaves an `emitflux` block without closing the construct being built, so you can run ordinary comptime code between pieces. `#};` closes a brace inside generated code. The finished function is parsed like any other and is part of the AST.

### Drop into VM assembly

You can write VM assembly inside a comptime block and modify comptime variables directly:

```
comptime
{
    int x = 5;

    fluxvm
    {
        LOCAL_GET x
        PUSH 10
        ADD
        LOCAL_SET x
    };

    compiler.io.console.print(f"x is now {x}\n");   // Prints: x is now 15
};
```

(`emitflux` and `fluxvm` are becoming `emitideka` and `idekavm`.)

### Comptime control flow

Named comptime blocks are `goto` targets, so you can build loops out of them:

```
comptime A
{
    // per-iteration setup
    goto B;
};

comptime B
{
    // more work
    if (condition) { goto A; };   // Loop back to A
};
```

---

## Modules

A module is a named group of declarations with its own build settings. Settings are set by the module itself, and a module sees only what it asks for with `#[requires]`.

```
module Math
{
    square(int x) -> int -> x * x;
    cube(int x)   -> int -> x * x * x;
}
# build
{
    !+#[borrow_check] = true        // locked: no other module can switch this off
};

module Logging
{
    log(byte* msg) -> void -> println(msg);
}
# build
{
    #[dce] = true
};

module App
{
    main() -> int
    {
        log("starting\0");
        println(f"{square(7)} {cube(3)}");
        return 0;
    };
}
# build
{
    #[entrypoint] = this,
    #[name]       = "app",
    #[requires]   = {Math, Logging},
    #[override for Logging] = { #[effect_check] = false }
};
```

```
starting
49 27
```

Each `# build` block is plain data the compiler reads:

| Tag | What it does |
|---|---|
| `#[entrypoint] = this` | Marks the program's entry module. A file with several modules that define `main` builds each as its own program. |
| `#[name]`, `#[target]`, `#[debug]` | Output name, kind (`executable`, `library`, `bootloader`, `compact`, `driver`), and Debug or Release layout. |
| `#[requires] = {A, B}` | The modules this one uses. Only these, and what `from "file.fx"` pulls in, are built into it. |
| `#[borrow_check]`, `#[effect_check]`, `#[dce]` | Per-module checks and dead code elimination. |
| `#[using]`, `#[platform]` | Namespaces made visible to the module, and the platforms it builds for. |
| `!+#[tag]` | Locks a setting so no other module can override it. |
| `#[override for {M}] = { ... }` | Changes `M`'s settings as `M` is built into this program. The module closest to the entry wins. |

Dependencies are enforced. A module cannot call into a module it does not require, and it cannot override one:

```
module B
{
    main() -> int { foo(); return 0; };    // foo() lives in module A
}
# build
{
    #[entrypoint] = this,
    #[override for A] = { #[borrow_check] = false }
};
```
```
Module error: module 'B': cannot override module 'A' because 'B' does not use it.
Add '#[requires] = {A}' to the build settings of 'B' first
```

---

## And more

### Contracts

```
contract NonZero(a, b)
{
    assert(a != 0, "a must be nonzero");
    assert(b != 0, "b must be nonzero");
};

def divide(int a, int b) -> int : NonZero(a, b)
{
    return a / b;
};

operator (int L, BigInt R) [+] -> BigInt : NonZero(L, R)
{
    // Contracts apply to operators too
};
```

Contracts are pre- and post-condition blocks attached to functions and operators as part of their specification, not their implementation. They transform into assertions at the call boundary, and can contain any statement that can go inside a function.

### Templates with type geometry constraints

```
constraint NoNarrowing(A)
{
    A !`< A    // A must never be narrowed anywhere in this template body
};

def serialize<T: int, :{NoNarrowing}>(T x) -> byte
{
    return 5 + x;   // Compile error: narrowing T to byte violates NoNarrowing
};
```

`!`<` is not a predicate on a concrete type. The compiler walks the instantiated function body and finds the actual narrowing. Template constraints express relationships between types, not just properties of a single type.

### Opt-in ownership

```
def consume(~int z) -> void {};   // Takes a tied parameter

def main() -> int
{
    ~int x;   // Tied variable

    consume(~x);   // Transfer ownership into consume
    consume(~x);   // Compile error: x has already been untied

    return 0;
};
```

Ownership is opt-in per type. Apply it where you need move semantics. The rest of your program has no borrow checker.

### Inline assembly with architecture guards

```
def exchange64(i64* ptr, i64 value, i64* out) -> void
{
    #ifdef __ARCH_X86_64__
    volatile asm
    {
        movq $0, %rsi
        movq $2, %rdi
        movq $1, %rax
        xchgq %rax, (%rsi)
        movq %rax, (%rdi)
    } : : "r"(ptr), "r"(value), "r"(out) : "rax", "rsi", "rdi", "memory";
    #endif;

    #ifdef __ARCH_ARM64__
    volatile asm
    {
    .retry:
        ldaxr x0, [$0]
        stlxr w3, x1, [$0]
        cbnz  w3, .retry
        str   x0, [$2]
    } : : "r"(ptr), "r"(value), "r"(out) : "x0", "w3", "memory";
    #endif;
};
```

### Raw bytecode functions

```
byte[] some_bytecode = [0x48, 0x31, 0xC0, 0xC3];  // xor rax,rax ; ret
def{}* fp()->void = @some_bytecode;
fp();
```

---

## What IDEKA is not

- **Not a Rust alternative.** Rust's borrow checker is global and mandatory. IDEKA ownership is opt-in per type. If you want the compiler to enforce memory safety everywhere, use Rust.
- **Not a Python-syntax language.** "C performance with Python readability" means the language is clean, not that it looks like Python. It is a C-family language.
- **Not garbage collected.** Everything is stack allocated by default. Heap allocation is explicit with `heap`. Cleanup is explicit with `(void)ptr` or `defer`.

---

## Design principles

- Everything is stack allocated unless you write `heap`
- Everything is zero-initialized on declaration unless you specify otherwise
- Struct fields have no hidden padding - layout is exactly what you declare
- The compiler does not add safety overhead you did not ask for
- Endianness, alignment, and bit width are type properties, not runtime concerns
- Explicit is better than implicit

---

## Current status

The syntax and grammar are stable and will not change. The compiler works. Real programs run. The standard library is the current focus of development.

**What exists:**
- Base compiler (LLVM backend)
- Bootstrapped compiler source
- Language Server Protocol (LSP)
- Package Manager (FPM)
- [Online Compiler / IDE](https://fluxspl.org/ide)
- [Language Specification](docs/Specs/language_specification.md)
- [Beginner Tutorial](docs/learn_flux_intro.md) and [Adept Tutorial](docs/learn_flux_adept.md)
- Style Guide, Keyword Reference
- Windows, Linux, and macOS setup guides
- C->IDEKA translation utility

**In progress:**
- Standard library expansion
- Build tooling
- IDE

---

## Requirements

- Python 3.12+ (can be removed once you bootstrap IDEKA)
- LLVM 21+

---

## Get involved

- **Discord:** [discord.gg/wVAm2E6ymf](https://discord.gg/wVAm2E6ymf)
- **Online IDE:** [fluxspl.org/ide](https://fluxspl.org/ide)
- **GitHub:** [github.com/kvthweatt/FluxLang](https://github.com/kvthweatt/FluxLang)

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=kvthweatt/FluxLang&type=date&legend=top-left)](https://www.star-history.com/#kvthweatt/FluxLang&type=date&legend=top-left)

---

*Copyright (C) 2024 Karac Von Thweatt. All rights reserved.*