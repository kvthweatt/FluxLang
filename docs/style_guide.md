# Flux Style Guide

A standard for writing clear, consistent, and correct Flux code.
This is not enforced by the compiler. It reflects the conventions
used across the Flux standard library and official examples.

---

## Imports

`#import` statements come first, before any `using`, declarations,
or code. Multi-file imports are on one line, comma-separated,
left to right in dependency order.

```
#import "standard.fx", "math.fx", "windows.fx", "opengl.fx";
```

Platform-conditional imports use `#ifdef`/`#endif` blocks immediately
after any unconditional imports:

```
#import "standard.fx";
#ifdef __WINDOWS__
#import "net_windows.fx";
#endif;
#ifdef __LINUX__
#import "net_linux.fx";
#endif;
```

Include guards use `#ifndef` / `#def` / `#endif` at the top and
bottom of any file that may be imported more than once:

```
#ifndef MY_LIB
#def MY_LIB 1;

// ... file contents ...

#endif;
```

---

## Using Directives

`using` comes after all imports and include guards, before any
declarations or code. Multiple namespaces are comma-separated
and aligned on one `using` keyword:

```
using standard::io::console,
      standard::math,
      standard::threading,
      standard::atomic;
```

---

## Other preprocessor macros

You may add a directory to the preprocessor directory list with (`#dir`),  
extending library access locations.
```
#dir "absolute\\path\\to\\your\\lib";
// You may also use unix-style paths
#dir "absolute/path/to/your/lib";
```

If for some reason you wish to warn the programmer, use (`#warn`):
```
#warn "You have imported something that may cause collisions.";
```

Or if you must entirely stop compilation, use (`#stop`):
```
#stop "Fatal compilation error, library incompatible with this system.";
```

---

## Constants and `#def` Macros

Preprocessor constants (`#def`) are SCREAMING_SNAKE_CASE and appear
at the top of the file after imports and `using`, grouped by purpose
with a comment line above each group:

```
// Simulation dimensions
#def SIM_W     256;
#def SIM_H     192;

// Solver parameters
#def ITER      4;
#def VISCOSITY 0.00008;
```

`const` declarations follow the same naming convention and are grouped
the same way. Related constants share a single `const` declaration with
comma-separated entries, aligned on `=`:

```
const int WIN_W       = 1024,
          WIN_H       = 768,
          MAX_THREADS = 64;
```

Phase or state constants that form a logical set use adjacent integer
values and are declared together:

```
const int PHASE_LINSOLVE_RED   = 0,
          PHASE_LINSOLVE_BLACK = 1,
          PHASE_ADVECT         = 2,
          PHASE_PROJECT_DIV    = 3,
          PHASE_EXIT           = 6;
```

---

## Naming

| Thing                          | Convention          | Example                    |
|--------------------------------|---------------------|----------------------------|
| Functions                      | snake_case          | `send_exact`               |
| Local variables                | snake_case          | `fix_size`                 |
| Global variables               | `g_` prefix         | `g_num_threads`            |
| Structs                        | PascalCase          | `WorkSlice`, `PatchHeader` |
| Objects                        | PascalCase          | `GLContext`                |
| Enums                          | PascalCase          | `TokKind`                  |
| Enum members                   | UPPER_CASE          | `TOK_IDENT`, `PHASE_EXIT`  |
| Type aliases (`as`)            | lowercase or stdint | `u32`, `i64`, `size_t`     |
| Win32 / FFI types              | As-declared         | `HWND`, `DWORD`, `LPCSTR`  |
| Preprocessor constants         | UPPER_CASE          | `PATCH_MAGIC`, `SIM_W`     |
| `const` named values           | UPPER_CASE          | `WIN_W`, `MAX_THREADS`     |
| Object special methods         | double underscore   | `__init`, `__exit`         |

Single-letter names are acceptable for loop indices (`i`, `j`, `t`, `k`),
and for throwaway temporaries in tight math code that will not change (`q`, `r`, `s0`, `s1`).
Avoid them in any other context. especially memory-sensitive contexts.

---

## Sections

Non-trivial files are divided into named sections using banner comments.

```
///  ---------------------------------------------------------------
  SECTION NAME
     ---------------------------------------------------------------
///
```

Shorter dividers (`// ---`) are acceptable inside a section to separate
logical sub-groups without promoting them to full sections. Seen most in
state machine or sequential logic files:

```
///  -----------------
  Helper predicates.
     -----------------
///
```

---

## Structs

Members are aligned on their names, not their types, when the set
is visually dense. Related members that share a type are declared on
one line, comma-separated:

```
struct WorkSlice
{
    int     row_start,
            row_end,
            phase,
            ls_color;
    double* ls_x, ls_x0;
    double  ls_a, ls_c_inv;
};
```

When members represent distinct logical roles, one-per-line is preferred
even if they share a type.

Inline struct initialization uses `{member = value}` syntax and is
reserved for small, obvious cases:

```
struct Point { int x, y; };
Point p = {x = 10, y = 20};
```
You may also place values in member order:
```
Point p = {10, 20};
```

---

## Global Variables

Globals are declared at file scope, outside any function, grouped
by purpose. Related globals share a declaration when their types
are the same:

```
bool mouse_down;
int  mouse_x,
     mouse_y,
     mouse_px,
     mouse_py;
```

Heap pointer globals are initialized to `(T*)0` at declaration
and allocated in `main` or an explicit init function:

```
heap double* g_dens,
             g_dens_prev,
             g_vx;
```

Use `global` for mutable shared state. Use `const` for immutable values.
Do not use bare global declarations for values that change at runtime
without the `global` keyword.

---

## Functions

### Signature style

Return type on the right with `->`. No space between function name
and parameter list. Opening brace on the same line as the signature,
on its own line:

```
def send_exact(int sockfd, byte* buf, int n) -> bool
{
    // ...
};
```

One blank line between function definitions.

### Local variable declarations

All locals are declared at the top of the function body, before any
executable code. This is a correctness requirement (the compiler
allocates stack space per declaration site), not just a style choice.
Group related locals on one line when their relationship is clear:

```
def advect_band(int row_start, int row_end,
                double* d, double* d0, double* u, double* v) -> void
{
    double dt0x, dt0y,
           max_x, max_y,
           bx, by,
           s0, s1, t0, t1;
    int jstart, jend,
        i, j, i0, j0, i1, j1,
        base, base00, base01;

    // executable code starts here

    int some_unused;
    if (cond) { return; } // early return

    // some_unused is a wasted allocation, which is wasted cycles.
    // Try to not allocate something if it is unused before a return point.
};
```

Why This Matters for Performance
Stack allocation is cheap — but not free.

Every declaration:
- adjusts RSP,
- reserves space,
- may require alignment padding, and affects the function’s prologue/epilogue.

If you scatter declarations:
- the compiler must emit multiple stack adjustments,
- the frame becomes fragmented,
- early returns waste allocations, and the generated code becomes harder to reason about.

By forcing all locals to the top, Flux guarantees:
- one contiguous frame
- one prologue
- no mid‑function stack mutations
- predictable layout
- zero wasted allocations

Do not declare variables inside loops or conditional blocks.
The compiler does not hoist them, and in-loop declarations
will cause stack overflows on any non-trivial iteration count.

### Short functions

One-liner bodies are acceptable when the function is genuinely trivial:

```
def IX(int x, int y) -> int
{
    return y * SIM_W + x;
};
```

### Parameters

Long parameter lists break after the opening parenthesis and align
on the first parameter of each continuation line:

```
def hmac_sha256(byte* key, int key_len,
                byte* xdata, int xdata_len,
                byte* out) -> void
{
```

---

## Control Flow

### Braces

All blocks use braces, even single-statement bodies. The opening
brace is on the same line as the control keyword. The closing brace
is on its own line, followed by `;`:

```
if (x < 1) { x = 1; };

while (total < n)
{
    sent = send(sockfd, buf + total, n - total, 0);
    if (sent <= 0) { return false; };
    total = total + sent;
};
```

### `if` / `elif` / `else` chains

Each clause is on its own line. The `elif` and `else` keywords follow
the closing brace of the previous clause on the same line:

```
if (mode == 0)
{
    // ...
}
elif (mode == 1)
{
    // ...
}
else
{
    // ...
};
```

### `switch`

Cases are not indented past the switch body. The final `default` block
carries the terminating `;`. Case bodies that fit on one line may be
written inline:

```
switch (t.kind)
{
    case (kinds.TOK_IDENT)  { kind_name = "IDENT \0"; }
    case (kinds.TOK_NUMBER) { kind_name = "NUMBER\0"; }
    case (kinds.TOK_END)    { kind_name = "END   \0"; }
    default                 { kind_name = "??????\0"; };
};
```

Multi-statement cases use normal block style:

```
switch (e._)
{
    case (ErrorUnionEnum.BOOL_ACTIVE)
    {
        print("Bool active in error union!\n\0");
    }
    default { print("No active tag set!\n\0"); };
};
```

### Early returns

Prefer early returns for guard clauses. Keep the happy path at the
lowest indentation level:

```
def do_open(HWND hwnd) -> void
{
    if (!GetOpenFileNameA((void*)@ofn)) { return; };
    // ... happy path continues at top level ...
};
```

---

## Operators

### Logical vs. bitwise

Use `&` and `|` for logical boolean conditions in `if`, `while`,
and `for`. Use `` `& `` and `` `| `` for bit manipulation on
integer values:

```
if (sent <= 0 | total >= n) { return false; };     // logical
u16 flags = raw `& 0x00FF;                          // bitwise
```

### XOR

Use `^^` for bitwise XOR of values. Never use `^` for XOR — `^` is
exponentiation in Flux:

```
ipad_key[i] = k ^^ byte(0x36);
```

### Address-of

`@` is the address-of operator. Used directly, without spaces:

```
semaphore_init(@g_work_sem, 0);
sha256_update(@inner_ctx, @ipad_key[0], 64);
```

### Comparison

`is` is equivalent to `==` and is preferred for enum and state
comparisons where it reads naturally:

```
if (tok.kind is kinds.TOK_END) { break; };
```

Use `==` for numeric equality in arithmetic contexts.

### Null coalescing and ternary assignment

`??` returns the left operand if non-zero, otherwise the right.
`?=` assigns to the target only if the target is currently zero.
Both are appropriate in initialization and defaulting patterns:

```
int z = y ?? 0;
x ?= fallback_value;
```

---

## Casts

Explicit casts use `(type)expr`. Always cast when narrowing,
converting between signed and unsigned, or converting a pointer
to an integer type for arithmetic:
```
wc.cbSize   = (UINT)(sizeof(WNDCLASSEXA) / 8);
ulong addr  = (ulong)@my_function;
byte* p     = (byte*)patch_page;
```

Pointer-to-integer casts for comparison use the target integer type
explicitly to avoid sign ambiguity:
```
if (g_ref_zr != ulong(0)) { ffree(ulong(g_ref_zr)); };
```

The `(@)` address-cast operator is used to convert an integer value to a pointer address value.  
A pointer's width will always be your configuration's default pointer width.
```
long val = 0x4700FF33324EBA60;
byte* some_byte = (@)val;
```

---

## Strings and Byte Arrays

All string literals used as C strings are null-terminated with `\0`
at the end of the literal:

```
print("Hotpatch Server\n\0");
byte* class_name = "FluidSim\0";
```

Do not rely on implicit null termination. The `\0` is always explicit.

`noopstr` is defined as `byte[] as noopstr;` and `noop` stands for "non-OOP".

```
noopstr cls = "FluxNotepad\0",
        ttl = "Flux Notepad - Untitled\0";
```

---

## Memory

### Heap allocation

Heap allocations use `fmalloc` / `ffree` from `standard::memory::allocators::stdheap`,
or `malloc` / `free` from the C runtime when interfacing with Win32 APIs that
expect C-heap pointers. Do not mix the two for the same allocation.

Byte counts passed to `fmalloc` are computed explicitly. Remember that
`sizeof` returns bits — divide by 8 to get bytes, or by `sizeof(byte)` for guarnteed accuracy.

```
field_bytes = (size_t)(SIM_W * SIM_H * 8);     // 8 bytes per double
g_dens      = (double*)fmalloc(field_bytes);
```

### `defer`

Use `defer` to pair `ffree` calls with their allocations at the top
of the function, immediately after allocation. This keeps cleanup
visible next to the allocation without requiring multiple exit paths:

```
g_dens = (double*)fmalloc(field_bytes);
defer ffree((u64)g_dens);
```

### Null checks

Check heap pointer validity by comparing the integer value to zero,
not the pointer to a typed null:

```
if ((u64)g_pixels != 0) { ffree((u64)g_pixels); };
```

---

## Extern Declarations

FFI functions are declared in `extern` blocks. The `!!` no-mangle operator  
prevents the compiler from mangling the function name, and cascades when  
used in comma-separated prototype lists.

You do not need to directly load the library at runtime, simply declare, link, compile, and use.

```
extern
{
    def !!
        VirtualAlloc(ulong, size_t, u32, u32)    -> ulong,
        VirtualFree(ulong, size_t, u32)          -> bool,
        VirtualProtect(ulong, size_t, u32, u32*) -> bool;
};
```

Platform-conditional externs are wrapped in `#ifdef` blocks.

---

## Comments

### Inline comments

Inline comments explain *why*, not *what*. A comment that just
restates the code in English adds no value:

```
// BAD
i = i + 1;   // increment i

// GOOD
i = i + 1;   // skip the boundary cell
```

### Block comments

Multi-line explanations use `//` on every line, not `/* */`:

```
// Constant-time comparison of two 32-byte buffers.
// Returns true if they are identical, false otherwise.
// Prevents timing side-channels on the signature check.
def sig_equal(byte* a, byte* b) -> bool
```

### Separator comments

`// ---` inline separators group related lines without a full section
banner. Used inside `main` or long functions to mark logical phases:

```
// --- Init Winsock ---
if (init() != 0) { return 1; };

// --- Create server socket ---
int server_sock = tcp_server_create(HOTPATCH_PORT, 1);
```

---

## Indentation and Whitespace

- Indent with **tabs**, not spaces.
- One blank line between top-level declarations (functions, structs, globals).
- Two blank lines before a section banner.
- No trailing whitespace.
- No blank lines at the start or end of a function body.
- Align multi-line declarations on their `=` or name column when
  it aids readability, not mechanically on every declaration.

---

## Function Pointers

Function pointer declarations use the `def{}*` syntax. The signature
follows immediately with no space before the parameter list:

```
def{}* glCreateShader_fp(int)                  -> int;
def{}* glShaderSource_fp(int, int, byte**, int*) -> void;
```

For a local callable function pointer bound to a value:

```
def{}* trampoline(ulong) -> ulong = (byte*)stub_page;
```

You may have function pointers of different calling convention, like so:
```
vectorcall{}* some_simd_fncptr()->vec3**;
```

---

## Enums and Tagged Unions

Enum members are SCREAMING_SNAKE_CASE. The enum name is PascalCase.
Accessing an enum member through an instance variable is the standard idiom:

```
TokKind kinds;
if (tok.kind is kinds.TOK_END) { break; };
```

Tagged unions pair an enum discriminant with a `union` using the enum
name as the tag specifier on the union declaration. Access the tag
via `._`:

```
union ErrorUnion { int iRval; bool bRval; } ErrorUnionEnum;

err._ = ErrorUnionEnum.BOOL_ACTIVE;
switch (e._) { ... };
```

---

## Object Definitions

Objects use PascalCase. `__init` returns `this`. `__exit` returns `void`.
Both are always defined when the object manages any resource:

```
object GLContext
{
    def __init(HDC hdc) -> this
    {
        // ...
        return this;
    };

    def __exit() -> void
    {
        // ...
        return;
    };
};
```

---

## Calling Conventions

`def` is `fastcall` by default and is used for all Flux-to-Flux calls.
`stdcall`, `cdecl`, and other conventions are used only when required
by an external ABI. Declare them explicitly at the function definition:

```
stdcall NotepadWndProc(HWND hwnd, UINT msg, WPARAM w, LPARAM l) -> LRESULT
{
    // ...
};
```

---

## What to Avoid

- **In-loop declarations.** Declare all locals at the top of the function.
  Declaring a variable inside a loop allocates a new stack slot every
  iteration and will overflow the stack on any significant loop count.

- **`^` for XOR.** `^` is exponentiation. Use `^^` for bitwise XOR.

- **Implicit null termination.** Always write `\0` at the end of string
  literals that are treated as C strings.

- **`sizeof` as bytes.** `sizeof` returns bits. Divide by `8` or by
  `sizeof(byte)` to get a byte count.

- **Mixing `fmalloc` and `malloc` for the same allocation.** Allocate
  and free with the same allocator.

- **`local` variables passed to functions.** `local` prevents a variable
  from escaping its scope. Passing it to, or returning them from any function is a compile error.

- **Pointer alias in arithmetic functions.** Never pass the same pointer
  as both input and output to a function that computes a result in-place
  unless the function explicitly documents that it handles aliasing.
  In-place alias bugs produce silent corruption with no compiler warning.