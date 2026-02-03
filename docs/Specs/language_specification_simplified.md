# Flux

Flux is a systems programming language resembling C++ and Python.  
This is the _reduced_ language specification.  
The purpose of this reduced specification is to make Flux easier to write an AST and parser for, and less work to integrate with LLVM.  
The goal is to create a version 1 of Flux which can be used to rewrite itself.  
- This goal has been achieved as of 1/30/2026

Python makes dealing with arrays simplistic, but doesn't have pointers natively. Flux solves this problem.  
If you like Flux, please consider contributing to the project or joining the [Flux Discord server](https://discord.gg/RAHjbYuNUc) where you can ask questions, provide feedback, and talk with other Flux enjoyers!

---

## **Functions:**

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

Recursion example:
```
def rsub(int x, int y) -> int
{
    if (x == 0 | y == 0) { return 0; };

    rsub(--x,--y);
};
```

Ternary logic:
```
#import "standard.fx";

def main() -> int
{
    int x = 0;
    int y = 5;

    int z = x < y ? y : 0;

    if (z is 5)
    {
        print("Success!\0\0");
    };
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
        print("Success!\0\0");
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
Structs cannot contain functions, or objects. This includes prototypes and definitions, but pointers are ok.  
Anonymous blocks in structs make data inside them inaccessible.  
Objects are functional with behavior and are executable.  
Structs cannot contain objects, but objects can contain structs. This means struct template parameters cannot be objects.

**Public/Private with Objects/Structs:**  
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

using standard::io;

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
#import "standard.fx"; // standard::io::print()

unsigned data{8}[] as string;

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


// Pointers to functions:
def add(int x, int y) -> int { return x + y; };
def sub(int x, int y) -> int { return x - y; };

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

using standard::io, standard::types;

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

```
asm
{
mov eax, 1
mov ebx, 0
int 0x80
};
```

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

## **The `data` keyword:**

Data is a variable bit width, primitive binary data type. Anything can cast to it, and it can cast to any primitive like char, int, float.  
It is intended to allow Flux programmers to build complex flexible custom types to fit their needs.  
Data types use little-endian byte order by default. Manipulate bits as needed.  
Bit-width bust always be specified.

Syntax for declaring a datatype:

```
    (const) (signed | unsigned) data {bit-width:alignment} as your_new_type

//    Example of a non-OOP string:

      unsigned data {8}[] as noopstr;    // Unsigned byte array, default alignment
```

This allows the creation of primitive, non-OOP types that can construct other types.  
`data` creates user-defined types.

For example, you can just keep type-chaining:
`unsigned data{16} as dbyte;`  
`dbyte as xbyte;`  
`xbyte as ybyte;`  
`ybyte as zbyte = 0xFF;`

Data decays to an integer type under the hood. All data is binary, and is therefore an integer.

```
#import "standard.fx";

unsigned data{8} as byte;   // optionally `unsigned data{8}[] as noopstr;`
byte[] as noopstring;

byte someByte = 0x41;                         // "A" but in binary
noopstring somestring = (noopstring)((char)someByte); // "A"
// Back to data
somestring = (data)somestring;                // 01000001b
string anotherstring = "B\0";                   // 01000010b

somestring<<;                                 // 10000100b  // Bit-shift left  (binary doubling)
somestring>>;                                 // 01000010b  // Bit-shift right (binary halving)
somestring<<2;                                // 00001000b  // Information lost
somestring>>2;                                // 00000010b

newstring = somestring xor anotherstring;     // 01000000b  // XOR two or more values
```

Casting objects or structs to `data` results in a new data variable with bit width equal to the size of the object/struct's length.  
If the object took up 1KB of memory, the resulting `data` variable will be 1024 bits wide.  
You cannot do the reverse with objects or structs unless **ALL** of their member types are explicitly aligned, otherwise you risk corrupting your resulting object/struct.

**Minimal specification:**
`unsigned data{8} as byte;         // 8-bit, packed`

**Full specification:**
`unsigned data{13:16} as custom;   // 13-bit, 16-bit aligned`

---

## **Casting:**

Casting in Flux is C-like

```
float x = 3.14;                  // 01000000010010001111010111000010b   binary representation of 3.14
i32 y = (i32)x;                  // 01000000010010001111010111000010b   but now treated as an integer  1078523330 == 0x4048F5C2
```

Casting anything to `void` is the functional equivalent of freeing the memory occupied by that thing.
If the width of the data type is 512 bits, that many bits will be freed.
This is dangerous on purpose, it is equivalent to free(ptr) in C. This syntax is considered explicit in Flux once you understand the convention.

This goes for functions which return void. If you declare a function's return type as void, you're explicitly saying "this function frees its return value".

Example:

```
def foo() -> void
{
    return 5;     // Imagine you wrote `return;` here instead. You could also imagine `return (void)5;` as well.
};

// This means a return type is syntactic sugar for casting the return value automatically,
// thereby guaranteeing the return value's type. Example:

def bar() -> float
{
    return 5 / 3;    // Math performed with integers, float 1.6666666666... returned.
};
```

If you try to return data with the `return` statement and the function definition declares the return type as `void`, nothing is returned.  
The compiler will ignore the return value and treat it as if only `return;` were present.

**Void casting in relation to the stack and heap:**
```
def example() -> void {
    int stackVar = 42;          // Stack allocated
    heap int heapVar = 67;      // Heap allocated

    (void)stackVar;  // What happens here?
    (void)heapVar;   // And here?
}
```

In either place, the stack or the heap, the memory is freed.
(void) is essentially a "free this memory now" no matter where it is or how it got there.
If you want to free something early, you can, but if you attempt to use it later you'll get a use-after-free bug.
If you're not familiar with a use-after-free, it is something that shows up in runtime, not comptime.
However in Flux, they can show up in comptime as well.
All of this is runtime behavior, but can also happen in comptime.

---

## **Array and pointer operations based on data types:**
```
unsigned data{16::0}[] as larray3 little_array[3] = {0x1234, 0x5678, 0x9ABC};
// Memory: [34 12] [78 56] [BC 9A]

unsigned data{16::0}* as ptr myptr = @little_array;
*myptr;     // 0x1234 (correct little-endian interpretation)
myptr++;    // Advances 2 bytes
*myptr;     // 0x5678 (correct little-endian interpretation)

// But if you reinterpret...
unsigned data{16::1}* as big_ptr mybigptr = (unsigned data{16::1}*)myptr;
*mybigptr; // 0x7856 (raw bytes [78 56] interpreted as big-endian)

// Reading network data (big-endian protocol)
unsigned data{16::1} as word network_port = {0x1F90};
// Gets 0x1F90 from network bytes [1F 90]

// Need to store in little-endian local format?
word local_port = (unsigned data{16::0})((network_port >> 8) | (network_port << 8)); // Explicit byte swap - you write exactly what you want
```

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

---

## **The `sizeof`, `typeof`, and `alignof` keywords:**
```
unsigned data{8:8}[] as string;
signed data{13:16} as strange;

sizeof(string);   // 8
alignof(string);  // 8
typeof(string);   // unsigned data{8:8}*

sizeof(strange);  // 13
alignof(strange); // 16
typeof(strange);  // signed data{13:16}
```

---

## **`void` as a literal and a keyword:**
```
if (x == void) {...code...};    // If it's nothing, do something
void x;
if (x == !void) {...code...};   // If it's not nothing, do something
```

---

## **Arrays:**
```
#import "standard.fx";
using standard::io, standard::types;

int[] ia_myArray = [3, 92, 14, 30, 6, 5, 11, 400];

// int undefined_behavior = ia_myArray[10];          // Length is only 8, accessing index 11

def len(int[] array) -> int
{
    return sizeof(array) / sizeof(int);
};
```

**Array comprehension:**
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

## **Destructuring with auto:**  
Destructuring is only done with structs. Structure / Destructure. No confusion.
```
struct Point1 { int x; int y; };

Point1 myPoint1 = {x = 10, y = 20};

auto {t, m} = myPoint1{x,y};        // int t=10, int m=20
```

**Restructuring with from:**
Since deserialization only cares that the size of the serialized data equals the size of the struct.  
For example, struct `Point2` has the same size as `Point1`, but the internal datatypes are different.
```
struct Point2 { i16 a, b, c, d; };             // Still 64 bits wide

Point2 myPoint2 = {a = 5, b = 10, c = 20, d = 40};

Point2 newPoint2 = serialized from myPoint2;   // Now restructured as i16 types
```

Since structures are data-only, they are already serialized.

---

## **Error handling with try/throw/catch:**
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

## **Assertion:**
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

## **Runtime type-checking:**
```
Animal* pet = @Dog();
if (typeof(pet) == Dog) { /* Legal */ };
// or
if (pet is Dog) { /* Legal, syntactic sugar for `typeof(pet) == Dog` */ };
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
(void)ptr;           // Deallocate
```

(void) casting works on both stack and heap allocated items. It can be used like `delete` or `free()`.

---

## **Advanced Pointer Manipulation**

### Taking Address of Literals
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

### Pointer-Integer Conversions
```
unsigned data{64} as u64ptr;
unsigned data{32} as uint32;

def manipulate_pointer(int* ptr) -> int*
{
    // Convert pointer to integer
    u64ptr addr = (u64ptr)ptr;
    
    // Perform integer arithmetic
    addr = addr & 0xFFFFFFF0;  // Align to 16-byte boundary
    addr += 0x100;              // Offset by 256 bytes
    
    // Convert back to pointer
    return (int*)addr;
};

// Round-trip pointer manipulation
int x = 42;
int* px = @x;
u64ptr addr = (u64ptr)px;
addr `&= `!0xF;  // Clear lower 4 bits (align to 16 bytes)
int* aligned_px = (int*)addr;
```

### Manual Struct Offsetting
```
struct Vector3
{
    float x;
    float y;
    float z;
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
        print(f"Byte {i}: 0x{*(bp + i):02X}\0\0");
    };
};

int[4] data = [0x12345678, 0x9ABCDEF0, 0x11223344, 0x55667788];
traverse_as_bytes(@data[0], 4);
```

---

## **Memory Layout and Alignment Tricks**

### Struct Packing with Custom Alignment
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

uint32 nibble0 = extract_bits(packed, 0, 4);   // 0x8
uint32 nibble3 = extract_bits(packed, 12, 4);  // 0x5
uint32 byte1 = extract_bits(packed, 8, 8);     // 0x56
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
    print("Unsigned comparison\0\0");
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
                    print("Both zero\0\0");
                }
                case (1)
                {
                    print("X zero, Y one\0\0");
                }
                default
                {
                    print("X zero, Y other\0\0");
                };
            };
        }
        case (1)
        {
            print("X is one\0\0");
        }
        default
        {
            print("X is other\0\0");
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
        throw(ErrorB("Something failed\0\0"));
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
        print(f"ErrorA caught: code {e.code}\0\0");
    }
    catch (ErrorB e)
    {
        print(f"ErrorB caught: {e.message}\0\0");
    }
    catch (string s)
    {
        print(f"String error: {s}\0\0");
    }
    catch (auto x)
    {
        print("Unknown error type\0\0");
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
                print(f"Found at [{i}][{j}]\0\0");
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

## **Function Pointer Patterns**

### Callback Systems

```flux
// Function pointer type for callbacks
def{}* callback(int)->void = eventHandler;

object EventSystem
{
    EventHandler[10] handlers;
    int handler_count;
    
    def __init() -> this
    {
        this.handler_count = 0;
        return this;
    };
    
    def register(EventHandler handler) -> void
    {
        if (this.handler_count < 10)
        {
            this.handlers[this.handler_count] = handler;
            this.handler_count++;
        };
    };
    
    def trigger(int event_code) -> void
    {
        for (int i = 0; i < this.handler_count; i++)
        {
            *this.handlers[i](event_code);  // Call each handler
        };
    };
};

// Handler functions
def on_error(int code) -> void
{
    print(f"Error: {code}\0\0");
};

def on_warning(int code) -> void
{
    print(f"Warning: {code}\0\0");
};

// Usage
EventSystem events = EventSystem();
events.register(@on_error);
events.register(@on_warning);
events.trigger(404);  // Calls both handlers
```

### Function Pointer Arrays (Jump Tables)
```
int* operations[4](int, int) as OpTable;

def op_add(int a, int b) -> int { return a + b; };
def op_sub(int a, int b) -> int { return a - b; };
def op_mul(int a, int b) -> int { return a * b; };
def op_div(int a, int b) -> int { return b != 0 ? a / b : 0; };

OpTable ops = [@op_add, @op_sub, @op_mul, @op_div];

def calculate(int opcode, int a, int b) -> int
{
    if (opcode >= 0 & opcode < 4)
    {
        return *ops[opcode](a, b);  // Jump table dispatch
    };
    return 0;
};

// Usage
print(calculate(0, 10, 5));  // 15 (add)
print(calculate(1, 10, 5));  // 5  (sub)
print(calculate(2, 10, 5));  // 50 (mul)
print(calculate(3, 10, 5));  // 2  (div)
```

### Vtable-like Structures
```
struct ShapeVTable
{
    float *area(void*) as area_fn;
    float *perimeter(void*) as perim_fn;
};

object Circle
{
    float radius;
    ShapeVTable* vtable;
    
    def __init(float r) -> this
    {
        this.radius = r;
        this.vtable = @{
            area_fn = @Circle::calc_area,
            perim_fn = @Circle::calc_perimeter
        };
        return this;
    };
};

def Circle::calc_area(void* self_ptr) -> float
{
    Circle* self = (Circle*)self_ptr;
    return 3.14159 * self.radius * self.radius;
};

def Circle::calc_perimeter(void* self_ptr) -> float
{
    Circle* self = (Circle*)self_ptr;
    return 2.0 * 3.14159 * self.radius;
};

// Usage
Circle c = Circle(5.0);
float area = *c.vtable.area_fn(@c);
print(f"Area: {area}\0");  // approx 78.54
```

---

## **Array Comprehension Advanced Examples**

### Multi-dimensional Comprehension
```
// Generate 2D grid
int[10][10] grid = [
    [x * y for (int y = 0; y < 10; y++)]
    for (int x = 0; x < 10; x++)
];

print(grid[5][5]);  // 25

// Conditional 2D comprehension
int[10][10] chess_pattern = [
    [(x + y) % 2 for (int y = 0; y < 10; y++)]
    for (int x = 0; x < 10; x++)
];
```

### Comprehension with Complex Expressions
```
// Fibonacci sequence
int[20] fib = [
    x == 0 ? 0 : (x == 1 ? 1 : fib[x-1] + fib[x-2])
    for (int x = 0; x < 20; x++)
];

// Prime number sieve (simplified)
bool[100] is_prime = [
    x < 2 ? false : (x == 2 ? true : x % 2 != 0)
    for (int x = 0; x < 100; x++)
];

// Transformation with filtering
int[] source = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
int[5] evens_squared = [
    x * x 
    for (int x in source) 
    if (x % 2 == 0)
];  // [4, 16, 36, 64, 100]
```

---

## **Memory Management Patterns**

### Manual Memory Pools
```
struct MemoryBlock
{
    unsigned data{8}[1024] as byte_array bytes;
    bool in_use;
};

object MemoryPool
{
    MemoryBlock[100] blocks;
    
    def __init() -> this
    {
        for (int i = 0; i < 100; i++)
        {
            this.blocks[i].in_use = false;
        };
        return this;
    };
    
    def allocate() -> byte*
    {
        for (int i = 0; i < 100; i++)
        {
            if (!this.blocks[i].in_use)
            {
                this.blocks[i].in_use = true;
                return @this.blocks[i].bytes[0];
            };
        };
        return (byte*)0;  // null
    };
    
    def free(byte* ptr) -> void
    {
        unsigned data{64}* as u64ptr;
        u64ptr block_base = (u64ptr)@this.blocks[0];
        u64ptr ptr_addr = (u64ptr)ptr;
        
        int index = (int)((ptr_addr - block_base) / sizeof(MemoryBlock));
        if (index >= 0 & index < 100)
        {
            this.blocks[index].in_use = false;
        };
    };
};
```

### Stack vs Heap Allocation
```
def test_allocation() -> void
{
    // Stack allocation (automatic)
    stack int stack_var = 42;
    stack int[1000] stack_array;
    
    // Heap allocation (manual)
    heap int heap_var = 22;
    *heap_var = 42;
    
    heap int[] heap_array = void;
    
    // Use the variables
    print(stack_var);
    print(*heap_var);
    
    // Manual cleanup for heap
    (void)heap_var;
    (void)heap_array;
    
    // stack_var automatically cleaned up on return
};
```

---

## **Practical Real-World Examples**

### Simple Packet Parser
```
unsigned data{8}[] as bytes;
unsigned data{16::1} as be16;  // Big-endian 16-bit
unsigned data{32::1} as be32;  // Big-endian 32-bit

struct IPHeader
{
    unsigned data{4} as nibble version;
    unsigned data{4} as nibble ihl;
    unsigned data{8} as byte tos;
    be16 total_length;
    be16 identification;
    be16 flags_offset;
    unsigned data{8} as byte ttl;
    unsigned data{8} as byte protocol;
    be16 checksum;
    be32 src_addr;
    be32 dst_addr;
};

def parse_ip_header(bytes* packet) -> IPHeader
{
    IPHeader* header = (IPHeader*)packet;
    return *header;
};

def format_ip(be32 addr) -> string
{
    bytes* bp = (bytes*)@addr;
    return f"{bp[0]}.{bp[1]}.{bp[2]}.{bp[3]}\0\0";
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
fixed16_16 a = to_fixed(3.14159);
fixed16_16 b = to_fixed(2.0);
fixed16_16 result = fixed_mul(a, b);
print(from_fixed(result));  // approx 6.28318
```

### Circular Buffer
```
object CircularBuffer
{
    unsigned data{8}[256] as byte buffer;
    int read_pos;
    int write_pos;
    int count;
    
    def __init() -> this
    {
        this.read_pos = 0;
        this.write_pos = 0;
        this.count = 0;
        return this;
    };
    
    def write(unsigned data{8} value) -> bool
    {
        if (this.count >= 256)
        {
            return false;  // Buffer full
        };
        
        this.buffer[this.write_pos] = value;
        this.write_pos = (this.write_pos + 1) % 256;
        this.count++;
        return true;
    };
    
    def read() -> unsigned data{8}
    {
        if (this.count == 0)
        {
            return 0;  // Buffer empty
        };
        
        unsigned data{8} value = this.buffer[this.read_pos];
        this.read_pos = (this.read_pos + 1) % 256;
        this.count--;
        return value;
    };
    
    def available() -> int
    {
        return this.count;
    };
};
```

---

## **Type System Edge Cases**

### Void Semantics
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

### Auto Type Inference
```
// Auto infers from right-hand side
auto x = 42;           // int
auto y = 3.14;         // float
auto z = "hello\0\0";  // unsigned data{8}[]
auto w = @x;           // int*

// Auto with complex types
auto result = calculate_something();  // Infers return type

// Auto in loops
for (auto val in array)
{
    // val type inferred from array element type
    print(val);
};

// Auto destructuring
struct Pair { int first; int second; };
Pair p = {first = 10, second = 20};
auto {a, b} = p{first, second};  // a=10, b=20
```

---

# Keyword list:
```
alignof, and, as, asm, assert, auto, break, bool, case, catch, const, continue, data, def, default,
do, elif, else, enum, false, float, for, global, heap, if, in, is, int, local, namespace, new, not, object, or,
private, public, register, return, signed, sizeof, stack, struct, switch, this, throw, true, try, typeof, uint,
union, unsigned, void, volatile, while, xor
```

# Operator list:
```
ADD = "+"
SUB = "-"
MUL = "*"
DIV = "/"
MOD = "%"
POWER = "^"
XOR = "^^"
OR = "|"
AND = "&"
NOR = "!|"
NAND = "!&"

INCREMENT = "++"
DECREMENT = "--"

EQUAL = "=="
NOT_EQUAL = "!="
LESS_THAN = "<"
LESS_EQUAL = "<="
GREATER_THAN = ">"
GREATER_EQUAL = ">="

BITSHIFT_LEFT = "<<"
BITSHIFT_RIGHT = ">>"

ASSIGN = "="
PLUS_ASSIGN = "+="
MINUS_ASSIGN = "-="
MULTIPLY_ASSIGN = "*="
DIVIDE_ASSIGN = "/="
MODULO_ASSIGN = "%="
POWER_ASSIGN = "^="
XOR_ASSIGN = "^^="
BITSHIFT_LEFT_ASSIGN = "<<="
BITSHIFT_RIGHT_ASSIGN = ">>="

ADDRESS_CAST = "(@)"
ADDRESS_OF = "@"
RANGE = ".."
SCOPE = "::"
TERNARY = "?:"
NULL_COALESCE = "??"
NO_MANGLE = "!!"
```

---

## Primitive types:

bool, int `5`, float `3.14`, char `"B"` == `66` - `65` == `'A'`, data

## All types:

bool, int, uint, float, char, data, void, object, struct, union, enum