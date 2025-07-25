# Flux

Flux is a systems programming language resembling C++ and Python.  
This is the _reduced_ language specification.  
The purpose of this reduced specification is to make Flux easier to write an AST and parser for, and less work to integrate with LLVM.  
The goal is to create a version 1 of Flux which can be used to rewrite itself.  
Python makes dealing with arrays simplistic, but doesn't have pointers natively. Flux solves this problem.  
If you like Flux, please consider contributing to the project or joining the [Flux Discord server](https://discord.gg/RAHjbYuNUc) where you can ask questions, provide feedback, and talk with other Flux enjoyers!

---

## **Functions:**

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
    if (x == 0 || y == 0) { return 0; };

    rsub(--x,--y);
};
```

---

## **Importing with `import`:**

Any file you import will take the place of the import statement.

```
import "standard.fx";
import "mylib.fx", "foobar.fx";  // Multi-line imports are processed from left to right in the order they appear.
```

Example:  
**`somefile.fx`**

```
int myVar = 10;
```

**`main.fx`**

```
import "somefile.fx";  // int myVar = 10;

def main() -> int
{
    if (myVar < 20)
    {
        // Do something ...
    };
    return 0;
};
```

---

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

**Object Magic Methods:**  
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
        return void;
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
        return void;
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
**f-string Example:**

```
import "standard.fx"; // standard::io::print()

unsigned data{8}[] as string;

def main() -> int
{
    string h = "Hello";
    string w = "World!";
    print(f"{h} {w}");
    return 0;
};
```

`Result: Hello World!`

---

## **Pointers:**

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
elif (condition2)
{
    doThat();
}
else
{
    doThings();
};
```

## **The `data` keyword:**

Data is a variable bit width, primitive binary data type. Anything can cast to it, and it can cast to any primitive like char, int, float.  
It is intended to allow Flux programmers to build complex flexible custom types to fit their needs.  
Data types use big-endian byte order by default. Manipulate bits as needed.  
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
import "standard.fx";

unsigned data{8} as byte;   // optionally `unsigned data{8}[] as noopstr;`
byte[] as noopstring;

byte someByte = 0x41;                         // "A" but in binary
noopstring somestring = (noopstring)((char)someByte); // "A"
// Back to data
somestring = (data)somestring;                // 01000001b
string anotherstring = "B";                   // 01000010b

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
import "standard.fx";
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

## **Destructure syntax with auto:**

```
// Destructuring is only done with structs. Structure / Destructure. No confusion.
struct Point { int x; int y; };

Point myPoint = {x = 10, y = 20};  // Struct initialization

auto t, m = myPoint{x,y};          // int t=10, int m=20
```

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
int* ptr = new int;  // Allocate
(void)ptr;           // Deallocate
```

(void) casting works on both stack and heap allocated items. It can be used like `delete` or `free()`.

---

# Keyword list:

```
alignof, and, as, asm, assert, auto, break, bool, case, catch, const, continue, data, def, default,
do, elif, else, false, float, for, global, if, import, in, is, int, namespace, new, not, object, or,
private, public, return, signed, sizeof, struct, super, switch, this, throw, true, try, typeof,
union, unsigned, void, volatile, while, xor
```

---

## Primitive types:

bool, int `5`, float `3.14`, char `"B"` == `66` - `65` == `'A'`, data

## All types:

bool, int, float, char, data, void, const, object, struct, union
