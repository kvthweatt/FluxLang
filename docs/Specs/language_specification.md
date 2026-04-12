# Flux

Flux is a compiled, general purpose programming language.

It provides power with ease of writing.

If you like Flux, please consider contributing to the project or joining the [Flux Discord server](https://discord.gg/RAHjbYuNUc) where you can ask questions, provide feedback, and talk with other Flux enjoyers!

**Creator note:** Everything in Flux is **stack allocated** unless specified.  
- This means you are likely to introduce stack overflows if you perform stack allocations inside loops such as declaring a new variable each time a loop passes.

---

## **Functions:**

You cannot define a function within a function. They must be module, namespace, or object level.

Prototype:
```
// Single declaration
def name(parameters) -> void;

// Multi-declaration
def name(int) -> bool,
    name(float) -> void,
    name(char*) -> int;   // Can prototype multiple functions at once, comma separated signatures.
```
Prototype signatures do not need a variable name, only types like `def foo(int,int,void*)->bool;`

Signature:
```
def name (parameters) -> return_type
{
    return return_value;
};
```

Example:
```
def myAdd(int x, int y) -> int
{
    return x + y;
};
```
Definitions require a variable name.

Overloading example:
```
def myAdd(float x, float y) -> float
{
    return x + y;
};
```

Ternary logic:
```
#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int x = 0;
    int y = 5;

    int z = x < y ? y : 0;

    if (z is 5)
    {
        print("Success!\0");
    };
    return 0;
};
```

Ternary assignment:
```
#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int x = 10,
        y;

    x ?= 50;
    y ?= x;

    if (x == y) { print("Success!\n\0"); };

    return 0;
};
```

Null coalesce operator:
```
#import "standard.fx";

def main() -> int
{
    int x = 0;
    int y = 5;

    int z = y ?? 0;

    if (z is 5)
    {
        print("Success!\0");
    };
    return 0;
};
```

Chain functions:
```
def foo(int x) -> int
{
    return x / 2;
};

def bar () -> int
{
    return 0xFF;
};

int z = foo() <- bar(); // == // int z = foo(bar());
```

---

## **Importing with `import`:**

Any file you import will take the place of the import statement.

```
#import "standard.fx";
#import "mylib.fx", "foobar.fx";  // Multi-line imports are processed from left to right in the order they appear.
```

Example:  
**`somefile.fx`**

```
int myVar = 10;
```

**`main.fx`**

```
#import "somefile.fx";  // int myVar = 10;

def main() -> int
{
    if (myVar < 20)
    {
        // Do something ...
    };
    return 0;
};
```

### Very simple preprocessor
```
#import "standard.fx";

#ifdef __WINDOWS__
def some_win_generic() -> LPCSTR*;
#else
#ifdef __LINUX__
def some_nix_generic() -> void*;
#endif;
#endif;

#warn "This will show a warning message.";

#stop "This will hard-stop compilation.";

#dir "C:\\path\\to\\some\\lib";
// Adds a path to the preprocessor's search list
```

---

## **External Functions (FFI):**
Single-line:
```
extern def foo() -> void;
extern def !!foo() -> void;  // !! tells the compiler do not mangle this function name
```
Block-based:
```
extern
{
    def foo() -> void;
    def bar() -> void;
    def !!zed() -> void;
};
```
Or multiple prototypes at once:
```
extern
{
    // Memory allocation
    def !!
        malloc(size_t) -> void*,
        memcpy(void*, void*, size_t) -> void*,
        free(void*) -> void,
        calloc(size_t, size_t) -> void*,
        realloc(void*, size_t) -> void*,
        memcpy(void*, void*, size_t) -> void*,
        memmove(void*, void*, size_t) -> void*,
        memset(void*, int, size_t) -> void*,
        memcmp(void*, void*, size_t) -> int,
        abort() -> void,
        exit(int) -> void,
        atexit(void*) -> int;
};
```
String-literal based function name support to target any compiled library function:
```
def "??foo@"()->void;
```

## **Namespaces:**

Prototype: `namespace myNamespace;`
Definition: `namespace myNamespace {};`  
Scope access: `myNamespace::myMember;`

Example:

```
namespace myNamespace
{
    def myFoo() -> void; // Legal
};

namespace myNamespace
{
    def myBar() -> void;        // namespace myNamespace now has myFoo() and myBar()
};

namespace myNamespace
{
    namespace myNestedNamespace
    {
        def myFooBar() -> void;
    };
};
```

Duplicate namespace definitions do not redefine the namespace, the members of both combine as if they were one namespace. This is so the standard library or any library can have a core namespace across multiple files.  
Namespaces are the only container that have this functionality.

---

## **Objects:**

Prototype / forward declaration: `object myObj;`  
Definition: `object myObj {};`  
Instance: `myObj newObj();`  
Member access: `newObj.x`

**Object Methods:**  
`this` never needs to be a parameter as it is always local to its object.

```
__init()       -> this               Example: thisObj newObj();            // Constructor
__exit()       -> void               Example: newObj.__exit();             // Destructor
```

`__init` is always called on object instantiation.  
`__exit` is always called on object destruction, or called manually to destroy the object.

Inheritance:

```
object XYZ;   // Forward declaration

object myObj
{
    def __init() -> this
    {
        return this;
    };

    def __exit() -> void
    {
        return;
    };
};

object anotherObj
{
    def __init() -> this
    {
        this newObj(10,2);
        return this;
    };

    def __exit() -> void
    {
        return;
    };
};
```

If an object's `__init` method takes **only one parameter**, you may instance it like sO:
```
object SomeOBJ
{
    def __init(int) -> this { return this; };

    def __exit() -> void {};
};

SomeOBJ sobj = 5;
```
It is syntactic sugar for `SomeObj sobj(5);`

---

## Traits
Traits are contracts imposed on objects dictating they __must__ implement the defined prototypes.
```
trait Drawable
{
    def draw() -> void;
};


// Implementation
Drawable object myObj
{
    def draw() -> void
    {
        // Implementation code, if the block is empty the compiler throws an error.
        return void;
    };

    // ... other methods ...
};
```

---

## **Structs:**

Prototype / forward declaration: `struct myStruct;`  
Definition: `struct myStruct {int x,y,z;};`  
Instance: `myStruct newStruct;`  
Instance with assignment: `myStruct newStruct {x = 10, y = 20, z = -5};`  
Member access: `newStruct.x;`

Structs are packed and have no padding naturally. There is no way to change this.  
You set up padding with alignment in your data types.  
Members of structs are aligned and tightly packed according to their width unless the types have specific alignment.  
Structs are non-executable, and therefore cannot contain functions or objects.  
Placing a for, do/while, if/elif/else, try/catch, or any executable statements other than variable declarations will result in a compilation error.

Example:

```
struct xyzStruct
{
    int x,y,z;
};

struct newStruct
{
    xyzStruct myStruct {x = 1, y = 1, z = 1};              // structs can contain structs
};
```

Structs are non-executable.  
Structs cannot contain functions, or objects. This includes prototypes and definitions. Pointers are ok, including function pointers.  

Structs support composition via prepending and appending other structs. Example:
```
struct Header
{
    data{16} sig;
    data{32} filesize, reserved, dataoffset;
};

struct InfoHeader
{
    data{32} size, width, height;
    data{16} planes, bitsperpixel;
    data{32} compression, imagesize, xpixelsperm, ypixelsperm, colorsused, importantcolors;
};

struct ExtraData
{
    byte[64] author;
};

struct BMP : Header, InfoHeader
{
    // More bitmap fields
} : ExtraData;
```


---

Objects are functional with behavior and are executable.  
Structs cannot contain objects, but objects can contain structs. This means struct template parameters cannot be objects.

## **Public/Private with Objects/Structs:**  
Struct public and private works by only allowing access to private sections by the parent object/struct that "owns" the struct.  
The struct is still data where public members are visible anywhere, but its private members are only visible/modifiable by the object immediately containing it.

```
object Obj1
{
    object Obj2
    {
        struct myStruct
        {
            public
            {
                int x = 10;
            };

            private
            {
                int y = 100;
            };
        };

        myStruct.y;                  // Safe - Access is in the same scope (immediate `this` Obj2, not `super` Obj1)
    };

    Obj2 myObject;

    myObject.myStruct.y;             // ERROR - Need to use a public getter of Obj2
};
```

---

## **Enumerated Lists:**

Definition: `enum myEnum {val1, val2, val3, val4, ...};`  
Instance: `myEnum newEnum;`
Member access: `newEnum.val1;`

Enumerated lists are type `int`, but in a later update when full RTTI is added to Flux there will be more specification around enums and type sizes.

---

## **Unions:**

Prototype: `union myUnion;`
Definition: `union myUnion {int iVal; float fVal;};`
Insance: `myUnion newUnion;`
Instance with assignment: `myUnion newUnion {iVal = 10};`  
Member access: `newUnion.iVal;`

Unions are similar to structs, the difference is only one of its members can be initialized at any time.  
Initializing another member changes the actively initialized member.  
Attempting to access an uninitialized member results in undefined behavior.

Example:

```
union myUnion
{
    int iVal;
    float fVal;
};

myUnion u {iVal = 10};

def main() -> int
{
    u.iVal = 10;   // iVal is the active member
    u.fVal = 3.14; // iVal overwritten by fVal in memory
};
```

---

## **i-Strings and f-Strings:**

The syntax in Flux would be: `i"{}{}{}":{x;y;z;};` for an i-string, and `f"{var1}{var2}\0";` for an f-string.

The brackets are replaced with the results of the statements in order respective to the statements' position in the statement array in i-strings.  
**i-string Example:**

```
#import "standard.fx";

using standard::io::console;

unsigned data{8}[] as string;

def bar() -> string { return "World\0"; };    // We get the basic string type from the types module
print(i"Hello {} {}" : // whitespace is ignored
              {
                  bar() + "!\0";
                "test\0";
              }                             // Whitespace is ignored, this is just for positioning
     );
x = i"Bar {}":{bar()};                      // "Bar World!"

string a = "Hello", b = "World!\0";
string y = f"{a} {b}\0";                      // "Hello World!"
```

This allows you to write clean interpolated strings without strange formatting.  
**f-string Example:**

```
#import "standard.fx";

using standard::io::console;
using standard::strings;

def main() -> int
{
    string h = "Hello\0";
    string w = "World!\0";
    print(f"{h} {w}\0");
    return 0;
};
```

`Result: Hello World!`

---

## **Pointers:**

```
string a = "Test\0";
string* pa = @a;
*pa += "ing!\0";
print(a);
// Result: "Testing!"


// Pointers to variables:
int idata = 0;
int* p_idata = @idata;

*p_idata += 3;
print(idata);  // 3

// Function pointer declarations
def{}* p_add(int,int)->int = @add;
def{}* p_sub(int,int)->int = @sub;

// Must dereference to call
print(p_add(0,3)); // 3
print(p_sub(5,2)); // 3

// Pointers to objects, structs, arrays:
object    myObj {};                 // Definition
object* p_myObj = @myObj;           // Pointer

struct    myStruct {};              // Definition
struct* p_myStruct = @myStruct;     // Pointer

int[]* pi_array = @i_array;         // Array of pointer

const* int x;  // Constant pointer

const* int* x; // Constant pointer to int pointer

// Pointer Arithmetic:
#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int[] arr = [10, 20, 30, 40, 50];
    int[]* ptr = @arr;                         // ptr points to the first element of arr

    print(f"Value at ptr: {*ptr}\0");            // Output: 10

    ptr++;    // Increment ptr to point to the next element
    print(f"Value at ptr: {*ptr}\0");            // Output: 20

    ptr += 2; // Increment ptr by 2 positions
    print(f"Value at ptr: {*ptr}\0");            // Output: 40

    int* ptr2 = @arr[4]; // ptr2 points to the last element of arr
    print(f"Elements between ptr and ptr2: {ptr2 - ptr}\0"); // Output: 1

    return 0;
};
```

---

## You can also use in-line assembly directly:
Assembly in Flux is done AT&T style.  
The constraints follow the block in the pattern `outputs : inputs : clobbers`
Here's an example:
```
def _exchange64(i64* ptr, i64 value, i64* out) -> void
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
    .retry_xchg64:
        ldaxr x0, [$0]
        stlxr w3, x1, [$0]
        cbnz  w3, .retry_xchg64
        str   x0, [$2]
    } : : "r"(ptr), "r"(value), "r"(out) : "x0", "w3", "memory";
    #endif;
};
```
Here, the clobber list is `"r"(ptr), "r"(value), "r"(out) : "x0", "w3", "memory";`  
Using `volatile` tags the assembly block for the compiler, saying do not touch this for any reason.

---

## **Logic with if/elif/else:**
```
if (condition1)
{
    doThis();
}
elif (condition2)      // You can also use `else if`
{
    doThat();
}
else if (condition 3)  // Equivalent to `elif`
{
    doAnythingElse();
}
else
{
    doThings();
};
```

You can also do `if` expressions:
```
int x = 0;
int y = x if (x > 5) else noinit;
```
Alternatively, you can use a ternary `?:`
`int y = x ?  (x > 5) :   noinit;`

---

## **The `data` keyword:**

Data is a variable bit width, primitive binary data-type creation keyword.  
Anything can cast to it, and it can cast to any primitive like char, int, float.  
It is intended to allow Flux programmers to build any basic integer type to fit their needs.  
Data types use big-endian byte order by default. Manipulate bits as needed.  
Bit-width bust always be specified.

Syntax for declaring a datatype:

```
(const) (signed | unsigned) data {bit-width:alignment} (as) your_new_type

//    Example of a non-OOP string:

      unsigned data {8}[] as noopstr;    // Unsigned byte array, default alignment
```

This allows the creation of primitive, non-OOP types that can construct other types.  
`data` creates user-defined types.

For example, you can just keep type-punning:
`unsigned data{16} as dbyte;`  
`dbyte as xbyte;`  
`xbyte as ybyte;`  
You can pun and declare a variable as well:  
`ybyte as zbyte zbx = 0xFF;`

Data decays to an integer type under the hood. All data is binary, and is therefore an integer.

**Minimal specification:**
`unsigned data{8} as byte;            // 8-bit`

**Full specification:**
`data{width : alignment : endianness}`

**Example:**
`unsigned data{16::0} as custom_le;   // 16-bit, 16-bit aligned, little endian`

---

## **Casting:**

Casting in Flux is C-like

```
float x = 3.14;                  // 01000000010010001111010111000010b   binary representation of 3.14
i32 y = (i32)x;                  // 01000000010010001111010111000010b   but now treated as an integer  1078523330 == 0x4048F5C2
```
There are only two types. Integers, and floating point decimals. `float` and `double` are floating point types. All other types are integer types.

Casting anything to `void` is the functional equivalent of freeing the memory occupied by that thing.  
This is dangerous on purpose, it is equivalent to free(ptr) in C. This syntax is considered explicit in Flux once you understand the convention.  
It calls `ffree()` under the hood, which uses the standard heap allocator. You should not `void` cast free anything unless it was allocated with `fmalloc()`

**Void casting in relation to the stack and heap:**
```
def example() -> void {
    int stackVar = 42; // Stack allocated

    (void)stackVar;    // What happens here?
}
```

In this case, `stackVar` is zeroed out and the reference invalidated.

---

## Stringification:
```
#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int Hello = 5;

    println($Hello);
    return 0;
};
```
Result:
`Hello`

---

## Direct type conversion:
You can do function-like conversion only with built-in types like `int`, `long`, `double`, `bool`, etc.
```
#import "standard.fx";

using standard::io::console;

def main() -> int
{
    double d = 3.1415925658;

    int i = int(d);

    print(i);

    return 0;
};
```
Result:
`3`

---

## **types.fx module:**

Imported by `standard.fx`
```
// The standard types found in Flux that are not included keywords
// This is an excerpt and not a complete list of all types defined in the standard library of types
signed   data{32} as  i32;
unsigned data{32} as ui32;
signed   data{64} as  i64;
unsigned data{64} as ui64;
```

Note: `data` primitives are **unsigned by default.**
`data{30} as my30t;` is identical to `unsigned data{30} as my30t;`

---

## **Namespace elimination with `!using` or `not using`:**
```
!using standard::io::file;
not using some::specific::namespace;
```

---

## **The `sizeof`, `typeof`, `alignof`, and `endianof` built-ins:**
```
unsigned data{8:8}[] as string;
signed data{13:16} as strange;

sizeof(string);    // 8
alignof(string);   // 8
typeof(string);    // unsigned data{8:8}*
endianof(string);  // 1

sizeof(strange);   // 13
alignof(strange);  // 16
typeof(strange);   // signed data{13:16}
endianof(strange); // 1
```

---

## **`void` as a literal:**
```
if (x == void) {...code...};    // If it's nothing, do something
void x;
if (x == !void) {...code...};   // If it's not nothing, do something
```
In literal context, `void` is `0`. `false` is also `0`, which means `void == false;`. Therefore, anything can be `void`-checked. 

---

## **Arrays:**
```
#import "standard.fx";

using standard::io::console;

int[] ia_myArray = [3, 92, 14, 30, 6, 5, 11, 400];

def len(int[] array) -> int
{
    return sizeof(array) / sizeof(int);
};

def main() -> int
{
    print(len(ia_myArray));
    return 0;
};
```

**Static array comprehension:**
```
// Python-style comprehension
int[10] squares = [x ^ 2 for (int x in 1..10)];

// With condition
int[20] evens = [x for (int x in 1..20) if (x % 2 == 0)];

// With type conversion
float[sizeof(int_array)] floats = [(float)x for (int x in int_array)];

// C++-style comprehension
int[10] squares = [x ^ 2 for (int x = 1; x <= 10; x++)];

// With condition
int[20] events = [x for (int x= 1; x <= 20; x++) if (x % 2 == 0)];
```

**Static array comprehension using a dynamic type:**
```
#import "standard.fx";

using standard::collections; // For the dynamic array 'Array'

Array[] myArr = [x.name for (Array x in oldArr) if (x.name.len() > 5)];
```

---

## **Loops:**

Flux supports 2 styles of for loops, it uses Python style and C++ style
```
for (x in y)                     // Python style
{
    // ... code ...
};

for (x,y in z)                   // Python style
{
    // ... code ...
};

for (int c = 0; c < 10; c++)     // C++ style
{
    // ... code ...
};

do
{
    // ... code ...
}
while (x in y);

while (condition)
{
    // ... code ...
};
```

---

## Recursion:
```
def rsub(int x, int y) -> int
{
    if (x == 0 | y == 0) { return 0; };

    rsub(--x,--y);
};
```

## **Single-initialized variables with `singinit`:**
```
#import "standard.fx";

using standard::io::console;

def foo() -> void
{
    singinit int x;
    x += 1;
    print(x); print();
};

def call(int y) -> void
{
    if (y == 0) { return; };
    foo();
    call(--y);
};

def main() -> int
{
    call(10);
    return 0;
};
```

## Strict Recursion with `<~`:
Functions that have the recurse return operator will always return to themselves. Their stack frame never grows because they become tail calls, and get optimized as such.
```
#import "standard.fx";

using standard::io::console;

noopstr m1 = "[recurse \0",
        m2 = "]\0";

def recurse1(int x) <~ int
{
    singinit int y;
    print(m1); print(y); println(m2);
    return ++y;
};


def recurse2() <~ void
{
    singinit int z;
    print(m1); print(++z); println(m2);
};


def main() -> int
{
    recurse2(); // Step into tail function
    return 0;
};
```

## **Escaping strict recursion with `escape`:**
`escape` can only be used inside a strictly-recursive function defined with a recurse arrow `<~`. Example:
```
def recurse2() <~ void
{
    if (!entered_flag) {entered_flag = true;};
    singinit int z;
    print(m1); print(++z); println(m2);
    if (z >= 10) { escape main(); }; // or any other function
};
```

---

## **Error handling with `try`/`throw`/`catch`:**
```
unsigned data{8}[] as string;  // Basic string implementation with no functionality (non-OOP string)

object ERR
{
    string e;

    def __init(string e) -> this
    {
        this.e = e;
        return this;
    };

    def __expr() -> string
    {
        return this.e;
    };
};

def myErr(int e) -> void
{
    switch (e)
    {
        case (0)
        {
            ERR myErrObj("Custom error from object myE\0");
            throw(myErrObj);
        }
        default
        {
            throw("Default error from function myErr()\0");
        };                                                  // Semicolons only follow the default case.
    };
};

def thisFails() -> bool
{
    return true;
};

def main() -> int
{
    string error = "\0";
    try
    {
        try
        {
            if(thisFails())
            {
                myErr(0);
            };
        }
        catch (ERR e)                                     // Specifically catch our ERR object
        {
            string err = e.e;
        }                                                 // No semicolon here because this is not the last catch in the try statement
        catch (string x)                                  // Only catch a primitive string (unsigned data{8}[]) thrown
        {
        }                                                 // No semicolon here because this is not the last catch in the try statement
        catch (auto x)
        {
        };                                                // Semicolon follows because it's the last catch in the try/catch sequence.
    }
    catch (string x)
    {
        error = x;  // "Thrown from nested try-catch block."
    };

    return 0;
};
```

## **Tagged unions:**
```
#import "standard.fx";

using standard::io::console;

enum ErrorUnionEnum
{
    INACTIVE,
    INT_ACTIVE,
    LONG_ACTIVE,
    BOOL_ACTIVE,
    CHAR_ACTIVE,
    FLOAT_ACTIVE,
    DOUBLE_ACTIVE   
};

union ErrorUnion
{
    int  iRval;
    long lRval;
    bool bRval;
    char cRval;
    float fRval;
    double dRval;
} ErrorUnionEnum;


def foo() -> ErrorUnion
{
    ErrorUnion err;

    err.bRval = false; // Set bool to active element
    err._ = ErrorUnionEnum.BOOL_ACTIVE;

    return err;
};


def main() -> int
{
    ErrorUnion e = foo();

    switch (e._)
    {
        case (ErrorUnionEnum.INT_ACTIVE)
        {
            print("Integer active in error union!\n\0");
        }
        case (ErrorUnionEnum.LONG_ACTIVE)
        {
            print("Long active in error union!\n\0");
        }
        case (ErrorUnionEnum.BOOL_ACTIVE)
        {
            print("Bool active in error union!\n\0");
        }
        case (ErrorUnionEnum.CHAR_ACTIVE)
        {
            print("Char active in error union!\n\0");
        }
        case (ErrorUnionEnum.FLOAT_ACTIVE)
        {
            print("Float active in error union!\n\0");
        }
        case (ErrorUnionEnum.DOUBLE_ACTIVE)
        {
            print("Double active in error union!\n\0");
        }

        default { print("No active tag set!\n\0"); };
    };

    return 0;
};
```

---

## **Switching:**
`switch` is static, value-based, and non-flexible. Switch statements are for speed.
```
switch (e)
{
    case (0)
    {
        // Do something
    }
    case (1)
    {
        // Another thing
    }
    default
    {
        // Something else
    };
};
```

---

## **Deprecation with `deprecate`:**
```
#import "standard.fx";

namespace test1
{
    namespace test2
    {
        def foo() -> void {};
    };
};

deprecate test1::test2;

def main() -> int
{
    test1::test2::foo();

    return 0;
};
```
Compiling gives this output:
```
✗ Compilation failed: Deprecated namespace 'test1::test2' is still referenced:
Function call test1__test2__foo()
```

---

## **Assertion with `assert()`:**
`assert` automatically performs `throw` if the condition is false if it's inside a try/catch block,
otherwise it automatically writes to standard error output.
```
def main() -> int
{
    int x = 0;
    try
    {
        assert(x == 0, "Something is fatally wrong with your computer.\0");
    }
    catch (string e)
    {
        print(e);
        return -1;
    };
    return x;
};
```

---

## **Constant Expressions:**
```
const def myconstexpr(int x, int y) -> int {return x * y;};  // Basic syntax
```

---

## **Heap allocation:**
```
heap int x = 5;      // Allocate
(void)x;             // Deallocate
```

`(void)` casting works on both stack and heap allocated items.  
If you do this to a stack element, it is nulled, and all references invalidated. You will need to redeclare `x`.

---

## **Templates**

```
#import "standard.fx";


def foo<T>(T x) -> T
{
    return x;
};


def main() -> int
{
    float y = foo<float>(5.5f);
    int z = foo<int>(3);

    print(y); print();
    print(z); print();

    system("pause\0");
    return 0;
};
```

---

## **Custom infix operators and overloading**
- Custom:
```
operator (int L, int R) [+++] -> int
{
    return ++L + ++R;
};
```
Usage: `a +++ b`

- Identifier-based:
```
operator (int L, int R) [NOPOR] -> bool
{
    return !L | !R;
};
```
Usage: `a NOPOR b`

- Overloading:
Overloading built-in operators is allowed, with rules.
1. One parameter must not be a built-in type.  
2. The precedence and associativity cannot be changed.
```
operator (int L, BigInt R) [+] -> bool
{
    // Implementation for adding an int and a BigInt
};
```

---

## **Variadic functions**
Variadics in Flux are very straightforward, and use the `...` elipse operator.  
You can index the elipse operator to yield the arguments passed, example:
```
#import "standard.fx";

using standard::io::console;

def variadic(...) -> void
{
    print(...[0]); print();
    print(...[1]); print();
    print(...[2]); print();
    print(...[3]); print();
};



def main() -> int
{
    variadic(1,2,3,4);

    return 0;
};
```
Result:
```
1
2
3
4
```

---

## **Advanced pointer manipulation**

### Taking address of literals
```
// You can take the address of a literal value
int* p = @42;
print(*p);  // 42

// The address can be manipulated as an integer
unsigned data{64}* as u64ptr;
u64ptr addr = (u64ptr)p;
addr += 8;  // Move 8 bytes forward in memory
int* p2 = (int*)addr;

// Pointer arithmetic on literal addresses
int* base = @100;
int* offset = base + 5;
*offset = 200;  // Writing to calculated memory location
```

### Pointer to integer conversions
```
#import "standard.fx";

using standard::io::console;

def main() -> int
{
    uint x, y = 10, 0;

    uint* px, py = @x, @y;

    // A pointer is simply a variable and its value is an address
    // An address is a number.
    // Therefore, we can store that address
    //
    u64 kx = px;

    // (@) is address-cast. It reinterprets the number as an address
    // When we treat a number as an address, we call that a pointer.
    // Therefore, we can assign this to another pointer.
    //
    py = (@)kx;

    // py now points to x

    // Dereference py to get the value at the address
    // Cast to make sure it's the proper type to print

    if (x == 10 & y == 0 & *py == x & px == py & px == (@)kx)
    {
        print("Success, y unchanged, py points to x.\n\0");
        print((uint)*py);
        return 0;
    };

        return 0;
};
```

### Manual Struct Offsetting
```
struct Vector3
{
    float x,
          y,
          z;
};

def get_y_ptr(Vector3* vec) -> float*
{
    unsigned data{64} as u64ptr;
    
    // Get base address
    u64ptr base = (u64ptr)vec;
    
    // Manually calculate offset to 'y' (sizeof(float) = 4 bytes)
    u64ptr y_addr = base + 4;
    
    // Return pointer to y member
    return (float*)y_addr;
};

// Usage
Vector3 v = {x = 1.0, y = 2.0, z = 3.0};
float* py = get_y_ptr(@v);
*py = 5.0;
print(v.y);  // 5.0
```

### Pointer Array Traversal
```
def traverse_as_bytes(int* ptr, int count) -> void
{
    byte* bp = (byte*)ptr;
    
    for (int i = 0; i < count * sizeof(int); i++)
    {
        print(f"Byte {i}: 0x{*(bp + i):02X}\0");
    };
};

int[4] data = [0x12345678, 0x9ABCDEF0, 0x11223344, 0x55667788];
traverse_as_bytes(@data[0], 4);
```

---

## **Memory Layout and Alignment Tricks**

### Struct packing with  ustom alignment
```
// Tightly packed struct (no padding)
struct PackedRGB
{
    unsigned data{5:1} as r5 r;    // 5 bits, byte-aligned
    unsigned data{6:1} as g6 g;    // 6 bits, byte-aligned
    unsigned data{5:1} as b5 b;    // 5 bits, byte-aligned
};  // Total: 16 bits (2 bytes)

// Aligned struct with gaps
struct AlignedData
{
    unsigned data{8:16} as byte16 flag;   // 8 bits, 16-bit aligned (1 byte data, 1 byte padding)
    u32 value;                            // 32 bits, 32-bit aligned
    unsigned data{8:16} as byte16 status; // 8 bits, 16-bit aligned
};  // Total: 64 bits (8 bytes) with padding

sizeof(PackedRGB);    // 2 bytes
sizeof(AlignedData);  // 8 bytes

// Verify alignment requirements
alignof(PackedRGB);   // 1 byte
alignof(AlignedData); // 4 bytes (strictest member alignment)
```

### Endianness Handling
```
unsigned data{16::0} as little16;  // Little-endian 16-bit
unsigned data{16} as big16;        // Big-endian default 16-bit

def swap_endian_16(unsigned data{16} value) -> unsigned data{16}
{
    return ((value & 0xFF) << 8) | ((value >> 8) & 0xFF);
};

// Network byte order (big-endian) to host (little-endian)
def network_to_host(big16 net_value) -> little16
{
    // Explicit byte swap
    return (little16)swap_endian_16((unsigned data{16})net_value);
};

// Reading from network buffer
unsigned data{8}[] as byte_array buffer = [0x12, 0x34, 0x56, 0x78];
big16* net_ptr = (big16*)@buffer[0];

print(*net_ptr);           // 0x1234 (interpreted as big-endian)
print(*(net_ptr + 1));     // 0x5678

// Convert to little-endian
little16 host_value = network_to_host(*net_ptr);
print(host_value);         // 0x3412 (byte-swapped for little-endian)
```

### Bit-Field Manipulation
```
// 13-bit signed value, 16-bit aligned
signed data{13:16} as strange13;

strange13 value = 0x1FFF;  // Max positive value for 13 bits
print(value);               // 8191

value = 0x1000;            // Sign bit set (bit 12)
print(value);              // -4096 (two's complement)

// Extract specific bit ranges
u32 packed = 0x12345678;

def extract_bits(uint32 value, int start, int length) -> uint32
{
    uint32 mask = ((1 << length) - 1) << start;
    return (value & mask) >> start;
};

uint32 nibble0 = extract_bits(packed, 0, 4);   // 0x80
uint32 nibble3 = extract_bits(packed, 12, 4);  // 0x50
uint32 byte1 = extract_bits(packed, 8, 8);     // 0x56
```

### ***Advanced data manipulation techniques:***
***C***:
```
len_block[0]  = (byte)((aad_bits    >> 56) & 0xFF);
len_block[1]  = (byte)((aad_bits    >> 48) & 0xFF);
len_block[2]  = (byte)((aad_bits    >> 40) & 0xFF);
len_block[3]  = (byte)((aad_bits    >> 32) & 0xFF);
len_block[4]  = (byte)((aad_bits    >> 24) & 0xFF);
len_block[5]  = (byte)((aad_bits    >> 16) & 0xFF);
len_block[6]  = (byte)((aad_bits    >>  8) & 0xFF);
len_block[7]  = (byte)( aad_bits           & 0xFF);
len_block[8]  = (byte)((cipher_bits >> 56) & 0xFF);
len_block[9]  = (byte)((cipher_bits >> 48) & 0xFF);
len_block[10] = (byte)((cipher_bits >> 40) & 0xFF);
len_block[11] = (byte)((cipher_bits >> 32) & 0xFF);
len_block[12] = (byte)((cipher_bits >> 24) & 0xFF);
len_block[13] = (byte)((cipher_bits >> 16) & 0xFF);
len_block[14] = (byte)((cipher_bits >>  8) & 0xFF);
len_block[15] = (byte)( cipher_bits        & 0xFF);
```

***Flux equivalent:***
```
len_block[0..7]  = (byte[8])(u64)aad_bits;
len_block[8..15] = (byte[8])(u64)cipher_bits;
```

```
uint* pd = @p.digits[0];

// Proper Flux
pd = [0xFFFFFFEDu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu,
      0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu];

/// C-like
pd[0] = 0xFFFFFFED;
pd[1] = 0xFFFFFFFF;
pd[2] = 0xFFFFFFFF;
pd[3] = 0xFFFFFFFF;
pd[4] = 0xFFFFFFFF;
pd[5] = 0xFFFFFFFF;
pd[6] = 0xFFFFFFFF;
pd[7] = 0x7FFFFFFF;
///
```

### **Reworking a loop:**
```
for (i = 0; i < 4; i++)
{
    hash[i] = (byte)((ctx.state[0] >> (24 - i * 8)) & 0xFF);
    hash[i + 4] = (byte)((ctx.state[1] >> (24 - i * 8)) & 0xFF);
    hash[i + 8] = (byte)((ctx.state[2] >> (24 - i * 8)) & 0xFF);
    hash[i + 12] = (byte)((ctx.state[3] >> (24 - i * 8)) & 0xFF);
    hash[i + 16] = (byte)((ctx.state[4] >> (24 - i * 8)) & 0xFF);
    hash[i + 20] = (byte)((ctx.state[5] >> (24 - i * 8)) & 0xFF);
    hash[i + 24] = (byte)((ctx.state[6] >> (24 - i * 8)) & 0xFF);
    hash[i + 28] = (byte)((ctx.state[7] >> (24 - i * 8)) & 0xFF);
};
```
Turns into:
```
hash[0..3]   = (byte[4])(be32)ctx.state[0];
hash[4..7]   = (byte[4])(be32)ctx.state[1];
hash[8..11]  = (byte[4])(be32)ctx.state[2];
hash[12..15] = (byte[4])(be32)ctx.state[3];
hash[16..19] = (byte[4])(be32)ctx.state[4];
hash[20..23] = (byte[4])(be32)ctx.state[5];
hash[24..27] = (byte[4])(be32)ctx.state[6];
hash[28..31] = (byte[4])(be32)ctx.state[7];
```

### ***Bit slices:***
```
#import "standard.fx";

using standard::io::console;

def main() -> int
{
    byte x = 55;

    x[0``7] = x[7``0]; // Reverse the bits

    println(int(x)); // 236

    return 0;
};
```

### ***Taking bit slices from structs:***
Bit slicing structs can cross member boundaries, because structs members are packed tightly in memory.
```
#import "standard.fx";

using standard::io::console;

struct xx { int a, b; };

def main() -> int
{
    data{4} as u4;
    xx yy = {5,10};
    u4 a = yy[59``63]; // 10 because 0b1010

    print((int)a);

    return 0;
};
```

### ***Bit slices of bit slices:***
```
#import "standard.fx";

using standard::io::console;

struct xx { int a, b; };

def main() -> int
{
    data{4} as u4;
    data{2} as u2;
    xx yy = {5,10};
    u4 a = yy[59``63]; // 10 because 0b1010
    u2 b = a[0``1];

    print((int)b); // 2, because 0b10

    return 0;
};
```

---

## **Advanced Data Type Features**

### Unusual Bit Widths
```
// 3-bit unsigned value (0-7)
unsigned data{3} as tiny = 5;

// 17-bit signed value
signed data{17} as weird17 = -1000;

// 7-bit with 8-bit alignment (1 bit padding)
unsigned data{7:8} as aligned7 = 127;

// Array of 5-bit values
unsigned data{5}[10] as nibble_array arr;
arr[0] = 0x1F;  // Max value for 5 bits

// Casting between weird widths
unsigned data{13} as u13 a = 8191;
unsigned data{17} as u17 b = (u17)a;  // Zero-extend
signed data{13} as s13 c = (s13)a;    // Reinterpret bits
```

You may take arbitrary width slices as well, stored in your arbitrarily sized types.

---

## **Function Pointers:**
```
#import "standard.fx";

using standard::io::console;

def foo(int x) -> int
{
    print("Inside foo!\n\0");
    return 0;   
};


def main() -> int
{
    def{}* pfoo(int)->int = @foo;
    print("Function pointer created.\n\0");
    print();

    pfoo(0); // Compiler auto dereferences

    return 0;
};
```


## **Callbacks:**
One of a few ways you can set up callbacks:
```
#import "standard.fx";

using standard::io::console;

def foo() -> void
{
    println("In foo()!");
};

def callback(long x) -> int
{
    def{}* cb()->void = x;
    cb();
    return 0;
};

def main() -> int
{
    callback(long(@foo));
    return 0;
};
```

## **Raw bytecode functions**
```
#import "standard.fx";

using standard::io::console;

def main() -> int
{
    byte[] some_bytecode = [0x48, 0x31, 0xC0, 0xC3];  // xor rax,rax ; ret
    def{}* fp()->void = @some_bytecode;
    fp();
    
    return 0;
};
```

---

### Mixing Signed/Unsigned in Expressions
```
signed data{32} as i32;
unsigned data{32} as u32;

i32 a = -10;
u32 b = 20;

// Mixed arithmetic (result type determined by widest type)
i32 result1 = a + (i32)b;    // -10 + 20 = 10 (signed)
u32 result2 = (u32)a + b;    // 4294967286 + 20 (unsigned, wraps)

// Comparison with mixed signs
if (a < (i32)b)  // true: -10 < 20
{
    print("Signed comparison\0");
};

if ((u32)a < b)  // false: 4294967286 > 20
{
    print("Unsigned comparison\0");
};
```

---

## **Ownership with the tie operator `~`**

Ownership only occurs if you use `~` to tell the compiler to perform a very simple set of rules:
- A tied value requires it to be untied on-use
- A tied value can only move to a tied type
- One-time use, old reference invalidated on use

A function returning a tied type cannot return to a variable of non-tied type.  
Similarly, you cannot pass a non-tied variable to a tied parameter.

```
#import "standard.fx";

def foo(~int z) -> void  // accepts a tied parameter
{
    return;
};

def main() -> int
{
    ~int x;
    int  y;  // Non-tied var

    foo(~x); // Untie from main, tie to foo()

    foo(~x); // Compile error, use after untie

    foo(y);  // Compile error, foo expects tied param

    return 0;
};
```

---

## **Control Flow Edge Cases**

### Nested Switches with Fallthrough
```
def classify_value(int x, int y) -> void
{
    switch (x)
    {
        case (0)
        {
            switch (y)
            {
                case (0)
                {
                    print("Both zero\0");
                }
                case (1)
                {
                    print("X zero, Y one\0");
                }
                default
                {
                    print("X zero, Y other\0");
                };
            };
        }
        case (1)
        {
            print("X is one\0");
        }
        default
        {
            print("X is other\0");
        };
    };
};
```

### Complex Try/Catch with Multiple Types
```
object ErrorA
{
    int code;
    def __init(int c) -> this { this.code = c; return this; };
    def __exit() -> void {return;};
};

object ErrorB
{
    string message;
    def __init(string m) -> this { this.message = m; return this; };
    def __exit() -> void {return;};
};

def risky_operation(int mode) -> void
{
    if (mode == 1)
    {
        throw(ErrorA(100));
    }
    elif (mode == 2)
    {
        throw(ErrorB("Something failed\0"));
    }
    else
    {
        throw("Generic error\0");
    };
};

def main() -> int
{
    try
    {
        risky_operation(1);
    }
    catch (ErrorA e)
    {
        print(f"ErrorA caught: code {e.code}\0");
    }
    catch (ErrorB e)
    {
        print(f"ErrorB caught: {e.message}\0");
    }
    catch (string s)
    {
        print(f"String error: {s}\0");
    }
    catch (auto x)
    {
        print("Unknown error type\0");
    };
    
    return 0;
};
```

### Nested Loops with Break/Continue
```
def find_in_matrix(int[][] matrix, int target) -> bool
{
    for (int i = 0; i < 10; i++)
    {
        for (int j = 0; j < 10; j++)
        {
            if (matrix[i][j] == target)
            {
                print(f"Found at [{i}][{j}]\0");
                return true;  // Break out of both loops
            };
            
            if (matrix[i][j] < 0)
            {
                continue;  // Skip negative values
            };
        };
    };
    
    return false;
};

// Do-while with complex condition
def wait_for_ready(int* status_reg) -> void
{
    int timeout = 1000;
    do
    {
        if (*status_reg & 0x01)  // Ready bit
        {
            break;
        };
        timeout--;
    }
    while (timeout > 0 & !(*status_reg & 0x80));  // Not error bit
};
```

---

### Simple Packet Parser
```

struct IPHeader
{
    nybble version, ihl;
    byte tos;
    be16 total_length, identification, flags_offset;
    byte ttl, protocol;
    be16 checksum;
    be32 src_addr, dst_addr;
};

def parse_ip_header(bytes* packet) -> IPHeader
{
    IPHeader* header = (IPHeader*)packet;
    return *header;
};

def format_ip(be32 addr) -> string
{
    bytes* bp = (bytes*)@addr;
    return f"{bp[0]}.{bp[1]}.{bp[2]}.{bp[3]}\0";
};

// Usage
bytes packet_data = [
    0x45, 0x00, 0x00, 0x3c,  // Version=4, IHL=5, ToS=0, Length=60
    0x1c, 0x46, 0x40, 0x00,  // ID, Flags
    0x40, 0x06, 0xb1, 0xe6,  // TTL=64, Protocol=TCP, Checksum
    0xc0, 0xa8, 0x01, 0x01,  // Source: 192.168.1.1
    0xc0, 0xa8, 0x01, 0x02   // Dest: 192.168.1.2
];

IPHeader hdr = parse_ip_header(@packet_data[0]);
print(f"Source: {format_ip(hdr.src_addr)}\0");
print(f"Dest: {format_ip(hdr.dst_addr)}\0");
```

### Fixed-Point Math
```
// 16.16 fixed-point format
signed data{32} as fixed16_16;

def to_fixed(float value) -> fixed16_16
{
    return (fixed16_16)(value * 65536.0);
};

def from_fixed(fixed16_16 value) -> float
{
    return (float)value / 65536.0;
};

def fixed_mul(fixed16_16 a, fixed16_16 b) -> fixed16_16
{
    signed data{64} as i64 temp = ((i64)a * (i64)b) >> 16;
    return (fixed16_16)temp;
};

def fixed_div(fixed16_16 a, fixed16_16 b) -> fixed16_16
{
    signed data{64} as i64 temp = ((i64)a << 16) / (i64)b;
    return (fixed16_16)temp;
};

// Usage
fixed16_16 a = to_fixed(3.14159),
           b = to_fixed(2.0);
fixed16_16 result = fixed_mul(a, b);
print(from_fixed(result));  // approx 6.28318
```

---

## **Type System Edge Cases**

### `void` semantics
```
// Void as a value
void x = void;

if (x == void)
{
    print("x is void\0");
};

// Conditional void assignment
void y = condition ? void : some_value;

// Void in arrays (creates holes)
int[] sparse = [1, 2, void, 4, void, 6];
if (sparse[2] == void)
{
    sparse[2] = 3;  // Fill the hole
};

// Function returning void pointer
def get_nullable() -> int*
{
    if (error_condition)
    {
        return (int*)void;  // Return null
    };
    return @some_value;
};
```

---

# **Calling Conventions:**
Flux allows you to use different calling conventions at the language level.
```
stdcall foobar() -> void;
```
`def` is `fastcall` by default. You may change this in the configuration.
You may also create function pointers of different calling conventions:
```
vectorcall{}* someSIMDfunc() -> u64*;
```

---

---

# Keyword list:
```
alignof, and, as, asm, assert, auto, break, bool, byte, case, catch, cdecl, const, continue, data, def, default, deprecate, 
do, double, elif, else, enum, false, fastcall, float, for, global, goto, heap, if, in, is, int, jump, label, local, long, namespace, noinit, noreturn, not, object, or,
private, public, register, return, signed, singinit, sizeof, stack, stdcall, struct, switch, this, thiscall, throw, true, try, typeof, uint, ulong,
union, unsigned, vectorcall, void, volatile, while, xor
```

# Operator list:
```
ADD = "+"
SUB = "-"
INCREMENT = "++"
DECREMENT = "--"
MUL = "*"
DIV = "/"
MOD = "%"
NOT = "!"
POWER = "^"
# Logical
AND = "&"
OR = "|"
NAND = "!&"
NOR = "!|"
XOR = "^^"
# Comparison
EQUAL = "=="
NOT_EQUAL = "!="
LESS_THAN = "<"
LESS_EQUAL = "<="
GREATER_THAN = ">"
GREATER_EQUAL = ">="
# Assignment
ASSIGN = "="
PLUS_ASSIGN = "+="
MINUS_ASSIGN = "-="
MULTIPLY_ASSIGN = "*="
DIVIDE_ASSIGN = "/="
MODULO_ASSIGN = "%="
POWER_ASSIGN = "^="
# Bitwise operators
# Logical
BITNOT = "`!"
BITAND = "`&"
BITOR = "`|"
BITNAND = "`!&"
BITNOR = "`!|"
BITXOR = "`^^"
BITXNOT = "`^^!"
BITXNAND = "`^^!&"
BITXNOR = "`^^!|"
# Assignment
AND_ASSIGN = "&="
OR_ASSIGN = "|="
XOR_ASSIGN = "^^="
BITAND_ASSIGN = "`&="
BITOR_ASSIGN = "`|="
BITNAND_ASSIGN = "`!&="
BITNOR_ASSIGN = "`!|="
BITXOR_ASSIGN = "`^^="
BITXNOT_ASSIGN = "`^^!="
BITXNAND_ASSIGN = "`^^!&="
BITXNOR_ASSIGN = "`^^!|="

# Ternary assignment, assign if left side is null.
TERN_ASSIGN = "?="

# Shift
BITSHIFT_LEFT = "<<"
BITSHIFT_RIGHT = ">>"
BITSHIFT_LEFT_ASSIGN = "<<="
BITSHIFT_RIGHT_ASSIGN = ">>="

BITSLICE = "``"

ADDRESS_OF = "@"
RANGE = ".."
SCOPE = "::"
QUESTION = "?"
COLON = ":"
TIE = "~"
STRINGIFY = "$"
LAMBDA_ARROW = "<:-"
RETURN_ARROW = "->"
CHAIN_ARROW = "<-"
RECURSE_ARROW = "<~" // def foo() <~ void;  // Emits musttail, 0 stack growth
NULL_COALESCE = "??"
NO_MANGLE = "!!"
FUNCTION_POINTER = "{}*"
ADDRESS_CAST = "(@)"
```

---

## Primitive types:

bool, byte `0xFF`, int `5`, float `3.14159`, double `3.1415926585`, char `"B"` == `66` - `65` == `'A'`, data

## All types:

bool, byte, int, uint, long, ulong, float, double, char, data, void, object, struct, union, enum

## Preprocesor directives:
`#import`, `#dir`, `#def`, `#ifdef`, `#ifndef`, `#else`, `#warn`, `#stop`