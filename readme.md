# Flux

**Note:** This language is still in development. A simplified version of Flux will be the first to release. It will not support templates, inheritance, `operator`, `contract`, `compt`, the *full* built-in operator set (all logical/bitwise operators), or macros. This is not a complete list of all that will not be supported. The reduced language specification can be found [here](https://github.com/kvthweatt/FluxLang/blob/main/language_specification_simplified.txt).

Flux is a systems programming language, visually resembling C++ and Python.

It borrows elements from C++, Python, Zig, and Rust to create a unified language to achieve expressiveness with low level control.

Flux is case-sensitive, ignores whitespace, and is statically typed.

Flux has a manual memory model. Memory management is up to the programmer.

A Flux program must have a main() function, and must be defined in global scope.

----

## **Function definition:**
```
def foo(int x, int y) -> int
{
    return (x + y) / (x - y);
};
```

**Overloading:**
```
def myAdd(float x, float y) -> float
{
    return x + y;
};
```

**Recursive function:**
```
def rsub(int x, int y) -> int
{
    if (x == 0 || y == 0) { return 0; };

    rsub(--x,--y);
};
```

----



**Namespaces:**

Definition: `namespace myNamespace {};`

Scope access: `myNamespace::myMember;`

Example:
```
namespace myNamespace
{
    def myFoo() -> void;
};

namespace myNamespace
{
    for (x = 0; x < 1; x++) {}; // Illegal, logical statements cannot be at the root of containers
}

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

Namespaces **MUST** be in global scope.
Duplicate namespace definitions do not redefine the namespace, the members
of both combine as if they were one namespace. This is so the standard
library or any library can have a core namespace across multiple files.
Namespaces are the only container that have this functionality.

----

## **Objects:**
Prototype / forward declaration: `object myObj;`
Definition: `object myObj {};`
Instance: `myObj newObj();`
Member access: `newObj.x`

Example:
```
object myObject
{
    def __init() -> this
    {
    };
};
```

**Object Magic Methods:**
```
__init()       -> this               Example: thisObj newObj();            // Constructor
__exit()       -> void               Example: newObj.__exit();             // Destructor
```


Objects and structs cannot be defined inside of a function, they must be within a namespace, another object, or global scope.
This is to make functions easier to read.
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
        return void;
    };
};

object anotherObj : myObj, XYZ             // Can perform multiple inheritance
{
    def __init() -> this
    {
        this newObj(10,2);
        return this;
    };

    def __exit() -> void
    {
        return void;
    };
};

object obj1 : anotherObj, myObj
{
    // __init() is not defined in this object
    // We inherit the __init() from anotherObj (first in the inheritance list)
    // If we want to inherit __init() from myObj, we put myObj first in the inheritance list.
    // If __init() was defined here, obj1 uses that __init()

    object obj2
    {
        super z1();                // Create instance of obj1
        super.myObj z2();          // Fails, makes no sense, obj1 inherited properties of myObj
        super.virtual::myObj z2(); // Succeeds, myObj is inherited and a virtual member of obj1
    };

    // Flux's version of C++'s `virtual` is used to fully qualify inherited names like so:
    virtual::myObj z3();
};
```

----

## **Structs:**
Structs are packed and have no padding naturally. There is no way to change this.
You set up padding with alignment in your data types.
Members of structs are aligned and tightly packed according to their width unless the types have specific alignment.
Structs are non-executable, and therefore cannot contain functions or objects.
Placing a for, do/while, if/elif/else, try/catch, or any executable statements other than variable declarations will result in a compilation error.
```
struct myStruct
{
    myObject newObj1, newObj2;
};

struct newStruct
{
    myStruct xStruct;              // structs can contain structs
};

// You can even do struct templates
struct myTstruct<T>
{
    T x, y;
};

struct myStruct1
{
    unsigned data {8} as status;
    unsigned data {32} as address;
};  // This struct is exactly 40 bits wide

struct myStruct2
{
    unsigned data {8:16} as status;
    unsigned data {32:8} as address;
};                                  // This struct is exactly 48 bits wide because we specified alignment introducing padding

// Structs also support inheritance
struct myStruct3 : myStruct2        // or multiple separated by a comma
{
    unsigned data{8} as timestamp;
};
```

Structs are non-executable.
Structs cannot contain function definitions, or object definitions, or anonymous blocks because structs are data-only with no behavior.
Objects are functional with behavior and are executable.
Structs cannot contain objects, but objects can contain structs. This means struct template parameters cannot be objects.


**Public/Private with Objects/Structs:**
Object public and private works exactly like C++ public/private does.
Struct public and private works by only allowing access to private sections by the parent object that "owns" the struct.
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


Logical statements (if/else, try/catch, do/while, for, assert, etc...) cannot be at the root scope of containers such as namespaces, objects, and structs.
It is illogical for them to exist there as that is not considered execution space.
Evaluations can happen, such as:
```
object X
{
    int a = 5;
    int b = 10;
    int c = a + b;    // Logical evaluation, but legal.
    int c = foo(a);   // Functional evaluation, but legal.
    try {int d = c;}; // Illegal, out of context, makes no sense in Flux.
}

struct MyStruct 
{
    int a = 5;
    int b = helper(a);        // Legal - calls external function during construction.
    
    def localFunc() -> int    // Illegal - no function definitions in structs, define it somewhere else.
    {
        return 10;
    };
};
```


Python uses f-strings, C++ uses a complicated format, Zig syntax is overly verbose.
Flux uses "interpolated" strings and Python f-strings but without formatting, and tries to fix Zig's syntax a bit.
The syntax in Flux would be: `i"{}{}{}":{x;y;z;};` for an i-string, and `f"{var1}{var2}";` for an f-string.
The brackets are replaced with the results of the statements in order respective to the statements' position in the statement array in i-strings.


**i-string Example:**
```
import "standard.fx";

using standard::io;

unsigned data{8}[] as string;

def bar() -> string { return "World"; };    // We get the basic string type from the types module
print(i"Hello {} {}" : // whitespace is ignored
              {
                  bar() + "!";
                "test";
              }                             // Whitespace is ignored, this is just for positioning
     );
x = i"Bar {}":{bar()};                      // "Bar World!"

string a = "Hello", b = "World!";
string y = f"{a} {b}";                      // "Hello World!"
```

This allows you to write clean interpolated strings without strange formatting.


Example 2:
```
import "standard.fx";

using standard::io;

unsigned data{8}[] as string;

def concat(string a, string b) -> string
{
    return a+b;           // array concatination is native so we really don't need this function
};

def main() -> int
{
    string h = "Hello ";
    string w = "World";   // strings are arrays of data{8} (bytes), so we can do `w[3] == 'l'`
    string x = "of ";
    string y = "Coding";
    print(i"{} {}":{concat(h,w);concat(x,y);});
    return 0;
};
```
Result: Hello World of Coding


**Pointers:**
```
string a = "Test";
string* pa = @a;
*pa += "ing!";
print(a);
// Result: "Testing!"


// Pointers to variables:
int idata = 0;
int *p_idata = @idata;

*p_idata += 3;
print(idata);  // 3


// Pointers to functions:
def add(int x, int y) -> int { return x + y; };
def sub(int x, int y) -> int { return x - y; };

// Function pointer declarations
int *p_add(int,int) = @add;
int *p_sub(int,int) = @sub;

// Pointer to template function:
def *tp_myMax<T>(T,T) -> T = @myMax<T>;
// Usage
*tp_myMax<int>(12,12);                   // 144

// Must dereference to call
print(*p_add(0,3)); // 3
print(*p_sub(5,2)); // 3

// Pointers to objects, structs, arrays:
object    myObj {};                 // Definition
object* p_myObj = @myObj;           // Pointer

struct    myStruct {};              // Definition
struct* p_myStruct = @myStruct;     // Pointer

int[]   i_array;                    // Definition
int[]* pi_array = @i_array;         // Pointer

// Pointer Arithmetic:
import "standard.fx";

using standard::io, standard::types;

def main() -> int
{
    int[] arr = [10, 20, 30, 40, 50];
    int[]* ptr = @arr;                         // ptr points to the first element of arr
    
    print(f"Value at ptr: {*ptr}");            // Output: 10
    
    ptr++;    // Increment ptr to point to the next element
    print(f"Value at ptr: {*ptr}");            // Output: 20
    
    ptr += 2; // Increment ptr by 2 positions
    print(f"Value at ptr: {*ptr}");            // Output: 40
    
    int *ptr2 = @arr[4]; // ptr2 points to the last element of arr
    print(f"Elements between ptr and ptr2: {ptr2 - ptr}"); // Output: 1
    
    return 0;
};
```


You can also use in-line assembly directly:

```
asm
{
mov eax, 1
mov ebx, 0
int 0x80
};
```


**if/elif/else:**
```
if (condition1)
{
    doThis();
}
elif (condition2)
{
    doThat();
}
else
{
    doThings();
};
```


**Import:**
// The way import works is C-like, where its as if the source code of the file you're importing
// takes the place of the import statement.
//
// However that does not mean you will have access to namespaces. You must "use" them with `using`
// This is to prevent binary bloat after compilation
```
import "standard.fx";
using standard::io, standard::types;          // Only use `io` and `types` namespaces from the `std` namespace.
```


**The `data` keyword:**
//
// Data is a variable bit width, primitive binary data type. Anything can cast to it,
// and it can cast to any literal Flux type like char, int, or float.
// It is intended to allow Flux programmers to build complex flexible custom types to fit their needs.
// Data types use big-endian byte order by default.
// Use bit manipulation operators to reorder as needed.
//
// Syntax for declaring a datatype:
//
//    (const) (signed | unsigned) data {bit-width:alignment:endianness} as your_new_type
//
//    Example of a non-OOP string:
//
//        unsigned data {8:8:1}[] as noopstr;    // Unsigned byte array
//
// This allows the creation of primitive, non-OOP types that can construct other types.
// `data` creates types, and types create types until an assignment occurs.
//
// For example, you can just keep inventing types until you assign a value like so:
//
// `unsigned data{16} as dbyte;`
// `dbyte as xbyte;`      // Type-definition with as
// `xbyte ybyte = 0xFF;`  // ybyte is now a variable because it is assigned the value 0xFF, not a type like xbyte
//
// The endianness value can be 0 or 1 for little or big respectively.
// Therefore `unsigned data{13:16:1} mytype;` makes an unsigned 13-bit wide, 16 bit aligned, big endian type called mytype
// If alignment isn't specified, it is packed tightly in memory. If endianness is not specified it is big endian.
// Bit-width must always be specified.
```
import "standard.fx";

unsigned data{8} as byte;
byte[] as string;

byte someByte = 0x41;                         // "A" but in binary
string somestring = (string)((char)someByte); // "A"
// Back to data
somestring = (data)somestring;                // 01000001b
string anotherstring = "B";                   // 01000010b

somestring<<;                                 // 10000100b  // Bit-shift left  (binary doubling)
somestring>>;                                 // 01000010b  // Bit-shift right (binary halving)
somestring<<2;                                // 00001000b  // Information lost
somestring>>2;                                // 00000010b

newstring = somestring xor anotherstring;     // 01000000b  // XOR two or more values

// Casting objects or structs to `data` results in a new data variable with bit width equal to the size of the object/struct's length.
// If the object took up 1KB of memory, the resulting `data` variable will be 1024 bits wide.
// You cannot do the reverse with objects or structs unless **ALL** of their member types are explicitly aligned, otherwise you risk corrupting your resulting object/struct.
// Minimal specification
unsigned data{8} as byte;           // 8-bit, packed, big-endian

// With alignment
unsigned data{16:16} as word;       // 16-bit, 16-bit aligned, big-endian

// Full specification  
unsigned data{13:16:0} as custom;   // 13-bit, 16-bit aligned, little-endian

// Skip alignment, specify endianness
unsigned data{24::0} as triple;     // 24-bit, packed, little-endian
```


**Casting:**
// Casting in Flux is C-like
```
signed data{32} as i32;

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
    return 5;     // Imagine you wrote `return void;` here instead. You could also imagine `return (void)5;` as well.
};

// This means a return type is syntactic sugar for casting the return value automatically,
// thereby guaranteeing the return value's type. Example:

def bar() -> float
{
    return 5 / 3;    // Math performed with integers, float 1.6666666666... returned.
};
```

If you try to return data with the `return` statement and the function definition declares the return type as void, nothing is returned.

**Void casting in relation to the stack and heap:**
```
def example() -> void {
    int stackVar = 42;                    // Stack allocated
    int* heapVar = malloc(sizeof(int));   // Heap allocated
    
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


**Array and pointer operations based on data types:**
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

**types.fx module:**
// imported by standard.fx
```
// The standard types found in Flux that are not included keywords
// This is an excerpt and not a complete list of all types defined in the standard library of types
signed   data{32} as  i32;
unsigned data{32} as ui32;
signed   data{64} as  i64;
unsigned data{64} as ui64;
```


**alignof, sizeof, typeof:**
// typeof() operates both at compile time, and runtime.
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


**Example of bare-metal register access:**
```
// Define a struct for a hardware register map
struct GPIORegisters {
    unsigned data {32} as control;
    unsigned data {32} as status;
    unsigned data {64} as buffer;
};

// Map to a fixed hardware address
volatile const GPIORegisters* GPIO = @0x40000000;  // Specifically an address value

def main() -> int {
    GPIO.control = 0x1;  // Write to control register (aligned access)
    asm { cli };         // Disable interrupts (assembly inline)
    return 0;
};
```


**The void literal and void keywords:**
```
if (x == void) {...code...};    // If it's nothing, do something
void x;
if (x == !void) {...code...};   // If it's not nothing, do something
```


**Arrays:**
```
import "standard.fx";
using standard::io, standard::types;

int[] ia_myArray = [3, 92, 14, 30, 6, 5, 11, 400];

// int undefined_behavior = ia_myArray[10];          // Length is only 8, accessing index 11

def len(int[] array) -> int
{
    return sizeof(array) / sizeof(int);
};
```

**Array Comprehension:**
```
// Basic comprehension
int[] squares = [x ^ 2 for (x in 1..10)];

// With condition
int[] evens = [x for (x in 1..20) if (x % 2 == 0)];

// With type conversion
float[] floats = [(float)x for (x in int_array)];
```

**Loops:**
// Flux supports 2 styles of for loops, it uses Python style and C++ style
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


**Destructure syntax with auto:**
```
// Destructuring is only done with structs. Structure / Destructure. No confusion.
struct Point { int x; int y; };

Point myPoint = {x = 10, y = 20};  // Struct initialization

// auto followed by { indicates destructuring assignment.
auto {t, m} = myPoint{x,y};        // int t=10, int m=20
```


**Error handling with try/throw/catch:**
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
            ERR myErrObj("Custom error from object myE");
            throw(myErrObj);
        }
        default
        {
            throw("Default error from function myErr()");
        };                                                  // Semicolons only follow the default case.
    };
};

def thisFails() -> bool
{
    return true;
};

def main() -> int
{
    string error = "";
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


**Switching:**
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


**Compile-Time with `compt`:**
compt is used to create anonymous blocks that are inline executed.
Any variable declarations become global definitions in the resulting program.
compt blocks can only be declared in global scope, never inside a function or namespace or anywhere else.
You cannot use compt as part of grammar like `compt def x()` or `compt if()`, but you can put functions and if-statements inside your compt block.
The Flux compiler will have the runtime built into it allowing for full Flux capabilities during comptime.
compt blocks act as guard rails that guarantees everything inside is resolvable at compile time.
```
compt {
    // This anonymous compt block will execute in-line at compile time.
    def test1() -> void
    {
        global def MY_MACRO 1;
        return;
    };

    if (!def(MY_MACRO))
    {
        test1();
    };
};
```


**Macros:**
The `def` keyword has two abilities, making functions, and making macros. Example:
```
def SOME_MACRO 0x4000000;

def myFunc() -> int
{
    if (MY_CONST_MACRO < 10)                         // Replaced with 5 at compile time
    {
        return -1;
    };
    return 0;
};

// You can also macro operators like so:

def MASK_SET `&       // Set bits with mask
def MASK_CLEAR `!&    // Clear bits with mask  
def TOGGLE `^^        // Toggle bits

// Usage becomes incredibly clean
gpio_control MASK_SET 0x0F;     // Set lower 4 bits
status_reg MASK_CLEAR 0xF0;     // Clear upper 4 bits
led_state TOGGLE 0x01;          // Toggle LED bit

// Network byte order operations
def HTONSL <<8
def HTONSR >>8    // Host to network short
def ROTL <<       // Rotate left
def ROTR >>       // Rotate right  
def SBOX `^       // S-box substitution
def PERMUTE `!&   // Bit permutation
def NTOHSR >>8    // Network to host short
def NTOHSL <<8    // Network to host short

// Checksum operations
def CHECKSUM_ADD `+
def CHECKSUM_XOR `^^

def ROTL <<         // Rotate left
def ROTR >>         // Rotate right  
def SBOX `^          // S-box substitution
def PERMUTE `!&      // Bit permutation
```
It can also work to act like C++'s `#ifdef` and `#ifndef`, in Flux you do `if(def)` and `if(!def)` inside a compt block:
```
compt
{
    if (def(MY_CONST_MACRO))
    {
        // Do something ...
    }
    elif (!def(MY_CONST_MACRO))
    {
        global def MY_CONST_MACRO 1;
    };
};
```

Macro definitions are the only thing that become global and therefore are persistent after exiting the scope of a compt function or anonymous block.
If you define a macro inside a function, it will not be global because it is locally scoped to the function. You must use `global` to make the macro global.

This means if you want pre-processor behavior, just wrap all your behavior inside an anonymous block marked `compt` anywhere in your code.
This also means you can write entire compile-time programs, the Flux runtime is built into the compiler for this purpose.
`compt` gives you more access to zero-cost abstractions and build time validation to catch errors before deployment.
Bad comptime code will result in slow compile times, example writing an infinite loop in a `compt` block that doesn't resolve means it never compiles.
If you want to write an entire Bitcoin miner in compile time, that's up to you. Your miner will run, but it will never compile unless a natural program end is reached.


**Assertion:**
`assert` automatically performs `throw` if the condition is false if it's inside a try/catch block,
otherwise it automatically writes to standard error output.
```
def main() -> int
{
    int x = 0;
    try
    {
        assert(x == 0, "Something is fatally wrong with your computer.");
    }
    catch (string e)
    {
        print(e);
        return -1;
    };
    return x;
};
```


**External FFI:**
Flux will support FFI with C to make adoption easier.
You may only place extern blocks globally.
```
extern("C")
{
    // Memory management
    def malloc(ui64 size) -> void*;
    def free(void* ptr) -> void;
    def memcpy(void* dest, void* src, ui64 n) -> void*;
    def memset(void* s, int c, ui64 n) -> void*;
    
    // File I/O
    def fopen(string filename, string mode) -> void*;
    def fclose(void* stream) -> int;
    def fread(void* ptr, ui64 size, ui64 count, void* stream) -> ui64;
    def fwrite(void* ptr, ui64 size, ui64 count, void* stream) -> ui64;
    
    // String operations
    def strlen(string s) -> ui64;
    def strcpy(string dest, string src) -> string;
    def strcmp(string s1, string s2) -> int;
};
```
extern will make these definitions global. You can only prototype functions inside extern blocks, nothing else.


**Runtime type-checking:**
```
Animal* pet = @Dog();
if (typeof(pet) == Dog) { /* Legal */ };
// or
if (pet is Dog) { /* Legal, syntactic sugar for `typeof(pet) == Dog` */ };
```


**Constant Expressions:**
```
const def myconstexpr(int x, int y) -> int {return x * y;};  // Basic syntax
```


**Custom Smart Pointers:**
```
object unique_ptr<T> {
    T* ptr;
    
    def __init(T* p) -> this {
        this.ptr = p;
        return this;
    };
    
    def __exit() -> void {
        if (this.ptr == !void) {
            (void)this.ptr;  // Explicit deallocation
        };
    };
    
    def __eq(unique_ptr<T> other) -> this {
        if (this.ptr == !void) { (void)this.ptr; };
        this.ptr = other.ptr;  // Transfer ownership
        (void)other.ptr;       // Clean up
        return this;
    };
};

int x = 5;

unique_ptr<int> a(@x);   // Alternatively `a(@new int);`
unique_ptr<int> b;

b = a;         // Ownership moved to b, a.ptr is now void

doThing(a);    // Use-after-free, a no longer exists.
```


**Heap allocation:**
```
int* ptr = new int;  // Allocate
(void)ptr;           // Deallocate
```

(void) casting works on both stack and heap allocated items. It can be used like `delete` or `free()`.


Keyword list:
```
alignof, and, as, asm, assert, auto, break, bool, case, catch,
const, continue, data, def, default, do, elif, else, false, float, for, global, if, import, in,
is, int, namespace, new, not, object, operator, or, private, public, return, signed, sizeof,
struct, super, switch, this, throw, true, try, typeof, unsigned, virtual, void, volatile, while, xor
```

Literal types:
bool, int `5`, float `3.14`, char `"B"` == `66` - `65` == `'A'`, data
