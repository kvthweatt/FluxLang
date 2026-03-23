# Flux Operator Reference

This document covers every operator available in Flux, organized by category.
For keyword operators (`and`, `or`, `not`, `is`, `xor`), see also the Keyword Reference.

---

## Arithmetic

**`+`** — Addition
```
int z = x + y;
```

**`-`** — Subtraction
```
int z = x - y;
```

**`*`** — Multiplication
```
int z = x * y;
```

**`/`** — Division
```
int z = x / y;
```

**`%`** — Modulo
```
int z = x % y;
```

**`^`** — Exponentiation
Note: `^` is **not** XOR. Use `^^` or the `xor` keyword for XOR.
```
float z = 2.0 ^ 10.0;   // 1024.0
```

**`++`** — Increment (prefix and postfix)
```
x++;    // postfix: use then increment
++x;    // prefix: increment then use
```

**`--`** — Decrement (prefix and postfix)
```
x--;    // postfix: use then decrement
--x;    // prefix: decrement then use
```

---

## Assignment

**`=`** — Assign
```
int x = 10;
```

**`+=`** — Add and assign
```
x += 5;   // x = x + 5
```

**`-=`** — Subtract and assign
```
x -= 3;
```

**`*=`** — Multiply and assign
```
x *= 2;
```

**`/=`** — Divide and assign
```
x /= 4;
```

**`%=`** — Modulo and assign
```
x %= 7;
```

**`^=`** — Exponentiate and assign
```
x ^= 2;   // x = x ^ 2
```

**`?=`** — Conditional assign (assign only if target is zero/null)
Assigns the right-hand value to the left-hand target only if the target is currently zero or null. The target is left unchanged if it already holds a non-zero value.
```
int x = 10,
    y;

x ?= 50;   // x stays 10 — already non-zero
y ?= x;    // y becomes 10 — was zero
```

---

## Comparison

**`==`** — Equal
```
if (x == y) { ... };
```

**`!=`** — Not equal
```
if (x != y) { ... };
```

**`<`** — Less than
```
if (x < y) { ... };
```

**`<=`** — Less than or equal
```
if (x <= y) { ... };
```

**`>`** — Greater than
```
if (x > y) { ... };
```

**`>=`** — Greater than or equal
```
if (x >= y) { ... };
```

**`is`** — Equality (keyword alias for `==`)
Preferred for enum, state, and type comparisons where it reads naturally.
```
if (x is 5) { ... };
if (tok.kind is kinds.TOK_END) { ... };
```

---

## Logical

Logical operators work on boolean truth values. Short-circuit evaluation applies.

**`&`** — Logical AND
```
if (x > 0 & y > 0) { ... };
```

**`|`** — Logical OR
```
if (x == 0 | y == 0) { ... };
```

**`!`** — Logical NOT
```
if (!flag) { ... };
```

**`!&`** — Logical NAND
```
if (x !& y) { ... };   // true unless both are true
```

**`!|`** — Logical NOR
```
if (x !| y) { ... };   // true only if both are false
```

**`^^`** — Logical XOR
```
if (x ^^ y) { ... };   // true if exactly one is true
```

**`and`** — Logical AND (keyword alias for `&`)
```
if (x > 0 and y > 0) { ... };
```

**`or`** — Logical OR (keyword alias for `|`)
```
if (x == 0 or y == 0) { ... };
```

**`not`** — Logical NOT (keyword alias for `!`)
```
if (not flag) { ... };
```

**`xor`** — Bitwise XOR (keyword form)
Note: `xor` operates on integer values as bitwise XOR. `^^` is its symbolic equivalent in logical context.
```
int result = a xor b;
byte k = ipad_key[i] xor byte(0x36);
```

---

## Logical Assignment

**`&=`** — AND and assign
```
x &= mask;
```

**`|=`** — OR and assign
```
x |= flag;
```

**`^^=`** — XOR and assign
```
x ^^= y;
```

---

## Bitwise

Bitwise operators are prefixed with a backtick (`` ` ``) to distinguish them from logical operators.

**`` `! ``** — Bitwise NOT
```
int inv = `!x;
```

**`` `& ``** — Bitwise AND
```
int masked = a `& 0xFF;
```

**`` `| ``** — Bitwise OR
```
int flags = a `| b;
```

**`` `!& ``** — Bitwise NAND
```
int result = a `!& b;
```

**`` `!| ``** — Bitwise NOR
```
int result = a `!| b;
```

**`` `^^ ``** — Bitwise XOR
```
int result = a `^^ b;
```

**`` `^^! ``** — Bitwise XNOT (XOR then NOT)
```
int result = a `^^! b;
```

**`` `^^!& ``** — Bitwise XNAND
```
int result = a `^^!& b;
```

**`` `^^!| ``** — Bitwise XNOR
```
int result = a `^^!| b;
```

---

## Bitwise Assignment

**`` `&= ``** — Bitwise AND and assign
```
x `&= 0x0F;
```

**`` `|= ``** — Bitwise OR and assign
```
x `|= 0x80;
```

**`` `!&= ``** — Bitwise NAND and assign
```
x `!&= y;
```

**`` `!|= ``** — Bitwise NOR and assign
```
x `!|= y;
```

**`` `^^= ``** — Bitwise XOR and assign
```
x `^^= y;
```

**`` `^^!= ``** — Bitwise XNOT and assign
```
x `^^!= y;
```

**`` `^^!&= ``** — Bitwise XNAND and assign
```
x `^^!&= y;
```

**`` `^^!|= ``** — Bitwise XNOR and assign
```
x `^^!|= y;
```

---

## Shift

**`<<`** — Bit-shift left
When used as a postfix with no operand, shifts left by one.
```
int shifted = x << 3;
byte b;
b<<;          // shift left by 1 (postfix form)
byte c = b << 2;
```

**`>>`** — Bit-shift right
When used as a postfix with no operand, shifts right by one.
```
int shifted = x >> 2;
b>>;          // shift right by 1 (postfix form)
```

**`<<=`** — Shift left and assign
```
x <<= 4;
```

**`>>=`** — Shift right and assign
```
x >>= 1;
```

---

## Pointer and Address

**`@`** — Address-of
Returns a pointer to the operand. Used without spaces between the operator and its operand.
```
int x = 10;
int* p = @x;

sha256_update(@inner_ctx, @ipad_key[0], 64);
int* p = @42;   // Address of a literal
```

**`*`** — Dereference
When applied as a prefix to a pointer, yields the value at that address.
```
int val = *p;
*p = 20;
```

**`(@)`** — Address-cast (integer to pointer)
Reinterprets an integer value as a pointer address. The resulting pointer has the width of the configured default pointer width.
```
uint* px = @x;
u64 kx = px;        // Store address as integer
uint* py = (@)kx;   // Reinterpret integer as address

long val = 0x4700FF33324EBA60;
byte* some_byte = (@)val;
```

---

## Ternary and Coalescing

**`? :`** — Ternary conditional
Evaluates the condition; yields the first expression if true, the second if false.
```
int z = x < y ? y : 0;
int y = x if (x > 5) else noinit;   // if-expression form
int y = x ? (x > 5) : noinit;       // ternary form
```

**`??`** — Null coalesce
Returns the left operand if it is non-zero, otherwise returns the right operand.
```
int z = y ?? 0;   // z = y if y != 0, else 0
```

---

## Function and Call

**`->`** — Return arrow
Separates a function's parameter list from its return type in a signature.
```
def add(int x, int y) -> int { return x + y; };
```

**`<-`** — Chain arrow
Pipes the return value of the right-hand function as the argument to the left-hand function. Equivalent to wrapping a call.
```
int z = foo() <- bar();   // equivalent to: int z = foo(bar());
```

**`<~`** — Recurse arrow
Used in place of `->` to declare a strictly-recursive (tail-call) function. Every `return` inside such a function re-enters itself. Stack frame never grows. Use `escape` to exit.
```
def factorial <~ int (int n)
{
    if (n <= 1) { escape some_other_function(); };
    return factorial(n - 1, acc * n);
};
```

**`{}*`** — Function pointer type marker
Used as part of `def{}*` to declare a function pointer variable. The calling convention keyword precedes it for non-default conventions.
```
def{}* pfoo(int) -> int = @foo;
vectorcall{}* some_simd_fn() -> u64*;
```

**`...`** — Variadic parameter / ellipsis
Declares that a function accepts a variable number of arguments. Arguments are accessed by indexing `...`.
```
def variadic(...) -> void
{
    print(...[0]); // 1
    print(...[1]); // 2
};

variadic(1, 2, 3, 4);
```

---

## Scope and Member Access

**`::`** — Scope resolution
Accesses a member of a namespace, object, or type.
```
standard::io::console;
```

**`.`** — Member access
Accesses a member of a struct, object, enum instance, or union.
```
newStruct.x;
myObj.method();
tok.kind;
err._;   // Tagged union discriminant
```

**`._`** — Tagged union discriminant access
Accesses or sets the active tag of a tagged union.
```
err._ = ErrorUnionEnum.BOOL_ACTIVE;
switch (e._) { ... };
```

---

## String and Interpolation

**`$`** — Stringify
Converts an identifier name to its string representation at compile time.
```
int Hello = 5;
print($Hello);   // prints the string \"Hello\"
```

**`f\"...\"`** — f-string (format string)
Interpolates variable values inline using `{variable}` syntax. Must be null-terminated with `\\0`.
```
string y = f\"{a} {b}\\0\";
print(f\"Value: {x}\\n\\0\");
```

**`i\"...\":{...};`** — i-string (indexed interpolation string)
Interpolates the results of expressions in order. Brackets in the string correspond to statements in the block.
```
print(i\"Hello {} {}\" : { bar() + \"!\\0\"; \"test\\0\"; });
string x = i\"Bar {}\":{bar();};
```

---

## Range

**`..`** — Range
Defines an inclusive integer range. Used in for-in loops and array comprehensions.
```
for (int x in 1..10) { ... };
int[10] squares = [x ^ 2 for (int x in 1..10)];
```

---

## Type System

**`(type)`** — Cast
Explicitly reinterprets a value as another type. There is no implicit narrowing conversion.
```
i32 y = (i32)x;
byte* p = (byte*)patch_page;
ulong addr = (ulong)@my_function;
```

**`(void)`** — Free / deallocate cast
Frees the memory occupied by the operand immediately. Works on both stack and heap allocations. After a `(void)` cast, any access to the freed variable is a use-after-free.
```
heap int x = 5;
(void)x;   // x is now freed
```

**`~`** — Tie
Binds a type alias to another alias, chaining type definitions.
```
unsigned data{16} as dbyte;
dbyte as xbyte;
xbyte as ybyte;
ybyte as zbyte = 0xFF;
```

**`as`** — Type alias declaration (keyword)
Gives a `data` type declaration a named alias. See also `~` for chaining aliases.
```
unsigned data{32} as u32;
signed data{64} as i64;
```

**`!!`** — No-mangle
Prevents the compiler from mangling the name of a function declared in an `extern` block. Cascades across comma-separated prototype lists.
```
extern def !!foo() -> void;

extern
{
    def !!
        malloc(size_t) -> void*,
        free(void*)   -> void;
};
```

---

## Built-in Built-ins

**`sizeof(x)`** — Size in bits
Returns the size of a type or value in **bits**, not bytes. Divide by `8` or `sizeof(byte)` to get bytes.
```
sizeof(int)    // 32
sizeof(byte)   // 8 (default; configurable via __BYTE_WIDTH__)

size_t n = (size_t)(SIM_W * SIM_H * sizeof(double) / 8);
```

**`alignof(x)`** — Alignment in bits
Returns the alignment requirement of a type in bits.
```
alignof(int)      // 32
alignof(string)   // 8
```

**`typeof(x)`** — Type kind constant
Resolves a type name to its kind constant at compile time. Useful for type comparisons.
```
if (typeof(x) == typeof(int)) { ... };
```

**`endianof(x)`** — Endianness
Returns the endianness of a type. `1` is big-endian (default for `data` types), `0` is little-endian.
```
endianof(string)   // 1
```

---

## Operator Overloading and Custom Operators

Flux allows defining new infix operators and overloading existing ones.

**Custom symbol operator:**
```
operator (int L, int R) [+++] -> int
{
    return ++L + ++R;
};

a +++ b;   // usage
```

**Identifier-based operator:**
```
operator (int L, int R) [NOPOR] -> bool
{
    return !L | !R;
};

a NOPOR b;   // usage
```

**Overloading a built-in operator:**
At least one parameter must be a non-built-in type. Precedence and associativity cannot be changed.
```
operator (int L, BigInt R) [+] -> BigInt
{
    // addition between int and BigInt
};
```

---

## Operator Precedence

Higher rows bind more tightly. Within a row, associativity is left-to-right unless noted.

| Precedence | Operators | Notes |
|---|---|---|
| Highest | `()` `[]` `.` `._` `::` | Grouping, indexing, member access |
| | `@` `*` (unary) `!` `` `! `` `++` `--` `$` `(type)` | Unary / prefix |
| | `^` | Exponentiation (right-associative) |
| | `*` `/` `%` | Multiplicative |
| | `+` `-` | Additive |
| | `<<` `>>` | Shift |
| | `` `& `` `` `| `` `` `^^ `` `` `!& `` `` `!| `` `` `^^! `` `` `^^!& `` `` `^^!| `` | Bitwise |
| | `<` `<=` `>` `>=` | Relational |
| | `==` `!=` `is` | Equality |
| | `&` `!&` | Logical AND / NAND |
| | `^^` | Logical XOR |
| | `|` `!|` | Logical OR / NOR |
| | `??` | Null coalesce |
| | `? :` | Ternary conditional |
| | `<-` | Chain arrow |
| Lowest | `=` `+=` `-=` `*=` `/=` `%=` `^=` `?=` `&=` `|=` `^^=` `` `&= `` `` `|= `` `` `^^= `` `` `!&= `` `` `!|= `` `` `^^!= `` `` `^^!&= `` `` `^^!|= `` `<<=` `>>=` | Assignment (right-associative) |

---

## Quick Reference Table

| Operator | Category | Description |
|---|---|---|
| `+` `-` `*` `/` `%` | Arithmetic | Basic math |
| `^` | Arithmetic | Exponentiation |
| `++` `--` | Arithmetic | Increment / decrement |
| `=` | Assignment | Assign |
| `+=` `-=` `*=` `/=` `%=` `^=` | Assignment | Compound arithmetic assignment |
| `?=` | Assignment | Assign if zero/null |
| `==` `!=` `<` `<=` `>` `>=` | Comparison | Relational |
| `is` | Comparison | Equality (keyword alias for `==`) |
| `&` `\\|` `!` `!&` `!\\|` `^^` | Logical | Boolean logic |
| `and` `or` `not` | Logical | Keyword aliases |
| `xor` | Logical/Bitwise | XOR (keyword form) |
| `&=` `\\|=` `^^=` | Logical assignment | Compound logical assignment |
| `` `! `` `` `& `` `` `\\| `` `` `!& `` `` `!\\| `` `` `^^ `` `` `^^! `` `` `^^!& `` `` `^^!\\| `` | Bitwise | Bit-level logic |
| `` `&= `` `` `\\|= `` `` `^^= `` `` `!&= `` `` `!\\|= `` `` `^^!= `` `` `^^!&= `` `` `^^!\\|= `` | Bitwise assignment | Compound bitwise assignment |
| `<<` `>>` `<<=` `>>=` | Shift | Bit shift |
| `@` | Pointer | Address-of |
| `*` (unary) | Pointer | Dereference |
| `(@)` | Pointer | Integer-to-pointer cast |
| `? :` | Conditional | Ternary |
| `??` | Conditional | Null coalesce |
| `->` | Function | Return type arrow |
| `<-` | Function | Chain call arrow |
| `<~` | Function | Strict-recursion arrow |
| `{}*` | Function | Function pointer marker |
| `...` | Function | Variadic parameter/index |
| `::` | Scope | Namespace/scope resolution |
| `.` | Member | Member access |
| `._` | Member | Tagged union discriminant |
| `$` | String | Stringify identifier |
| `..` | Range | Inclusive range |
| `(type)` | Type | Cast |
| `(void)` | Type | Free / deallocate |
| `~` | Type | Tie (alias chain) |
| `!!` | FFI | No-mangle |
| `sizeof` | Built-in | Size in bits |
| `alignof` | Built-in | Alignment in bits |
| `typeof` | Built-in | Type kind constant |
| `endianof` | Built-in | Endianness of type |