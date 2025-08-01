# Flux

Flux is a systems programming language resembling C++ and Python.  
This is the _full_ language specification.  
If you like Flux, please consider contributing to the project or joining the [Flux Discord server](https://discord.gg/RAHjbYuNUc) where you can ask questions, provide feedback, and talk with other Flux enjoyers!

Flux is a systems programming language, resembling C++ and Python.  
It borrows elements from C++, Python, Zig, and Rust.  
Flux supports RAII.  
Python makes dealing with arrays simplistic, but doesn't have pointers natively. Flux solves this problem.  
Flux has a manual memory model. Memory management is up to the programmer.  
A Flux program must have a main() function, and must be defined in global scope.

---

## **Functions:**
**Syntax:**
```
def name (parameters) -> return_type
{
	return return_value;
};
```

**Example:**
```
def myAdd(int x, int y) -> int
{
	return x + y;
};
```

**Overloading:**
```
def myAdd(float x, float y) -> float
{
	return x + y;
};
```

**Recursion:**
```
def rsub(int x, int y) -> int
{
	if (x == 0 || y == 0) { return 0; }; // Return statement found somewhere in function body

	rsub(--x,--y);
};
```

---

## **Import:**
Import works by replacing the code of the import statement with the imported file.
```
import "standard.fx";
```
Multi-line imports work in the order they appear.
```
import "types.fx", "binops.fx";
```

**types.fx module:**  
The standard types found in Flux that are not included keywords.  
This is an excerpt and not a complete list of all types defined in the standard library of types.

**32-bit wide types**
```
signed   data{32} as  i32;
unsigned data{32} as ui32;
```

**64-bit wide types**
```
signed   data{64} as  i64;
unsigned data{64} as ui64;
```

---

## **Namespaces:**
Definition: `namespace myNamespace {};`  
Inheritance: `namespace myNS : baseNS {};`  
Scope access: `myNamespace::myMember;`
```
namespace myNamespace
{
	def foo() -> void;
};

namespace myNamespace               // Gains foo()
{
	namespace myNestedNamespace
	{
		def bar() -> void;
	};
};

namespace someNS : myNamespace {};  // Gains myNestedNamespace
```

Namespaces **MUST** be in global scope, or nested within a namespace scope.
Duplicate namespace definitions do not redefine the namespace, the members of both combine as if they were one namespace.  
This is so the standard library or any library can have a core namespace across multiple files.  
Namespaces are the only container that have this functionality.

---

## **Objects:**  
Prototype / forward declaration: `object myObj;`  
Definition: `object myObj {};`  
Instance: `myObj newObj();`  
Inheritance: `object myO : baseO {};`  
Member access: `newObj.x`  

**Object Methods:**  
`this` never needs to be a parameter as it is always local to its object.

**Object Constructor & Destructor Functions:**
```
__init()       -> this               Example: thisObj newObj();            // Constructor
__exit()       -> void               Example: newObj.__exit();             // Destructor
```

`__init` is always called on object instantiation.  
`__exit` is always called on object destruction, or called manually to destroy the object.  

Inheritance:

```
object XYZ;

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

object anotherObj : myObj, XYZ         // Can perform multiple inheritance
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

	// virtual in Flux is used to fully qualify a name
	virtual::myObj z3();
};
```

---

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

struct myStruct1
{
    unsigned data {8} as status;
    unsigned data {32} as address;
};  // This struct is exactly 40 bits wide

struct myStruct2
{
    unsigned data {8:16} as status;
    unsigned data {32:8} as address;
};  // This struct is exactly 48 bits wide because we specified alignment

// Structs also support inheritance, multiple comma separated
struct myStruct3 : myStruct2, newStruct
{
	unsigned data{8} as timestamp;
};
```

Structs are non-executable.  
Structs cannot contain function definitions, or object definitions, or anonymous blocks because structs are data-only with no behavior.  
Objects are functional with behavior and are executable.  
Structs cannot contain objects, but objects can contain structs. This means struct template parameters cannot be objects.  
Objects and structs cannot be defined inside of a function, they must be within a namespace, another object, or global scope.  
This is to make functions easier to read.

---

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

---

## **f-Strings and i-Strings:**  
Flux uses f-strings, similar to Python but without formatting.  
**i-strings** or interpolated strings look like `i"{}{}{}":{x;y;z;};` where in the string literal are replaced with the results of the statements in order respective to the statements' position in the statement block after the colon.

**i-string Example:**
```
import "standard.fx";

using standard::io, standard::types;

def bar() -> string { return "World"; };  // string defined in the types module
print(i"Hello {} {}":
		              {
		              	bar() + "!";
		                "test";
		              }  // This is the only block which does not require a semicolon
     );
```
This allows you to write clean interpolated strings without strange formatting.

**f-string Example:**
```
import "standard.fx";

using standard::io, standard::types;

def main() -> int
{
    string h = "Hello";
    string w = "World";
    print(f"{h} {w}!");
    return 0;
};
```
Result: Hello World!

---

## **Logic with if/elif/else:**
```
int x = 10;

if (x < 10)
{
	doThis();
}
elif (x > 10)
{
	doThat();
}
else
{
	doThings();
};                  // Semicolon trails the end of the full if/elif/else block
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

---

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
`ybyte zbyte = 0xFF;`

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
```
signed data{32} as i32;

float x = 3.14;              // 01000000010010001111010111000010b   binary representation of 3.14
i32 y = (i32)x;              // 01000000010010001111010111000010b   but now treated as an integer  1078523330 == 0x4048F5C2
```

Casting anything to `void` is the functional equivalent of freeing the memory occupied by that thing.  
If the width of the data type is 512 bits, that many bits will be freed.  
This is dangerous on purpose, it is equivalent to free(ptr) in C. This syntax is considered explicit in Flux once you understand the convention.

This goes for functions which return void. If you declare a function's return type as void, you're explicitly saying **"this function frees its return value"**.

Example:
```
def foo() -> void
{
	return 5;   // void returned anyways.
};

def bar() -> float
{
	return 5 / 3;    // Math performed with integers but float 1.6666666666 returned
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

**Difference between void casting and void assignment:**  
There is a strict difference between void casting and assignment.  
Casting frees the item literally, as in it is wiped from the stack/heap, whatever its origin is.  
Assigning something to `void` makes it nullified, `void` also equals `false` in boolean cases because if a byte is all zeros, it equals zero. This does not free the item from the stack or heap, rather, you can now do `if (x is void)` which is also `if (x is false)` or `if (!x)`.

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

---

## **Pointers:**
```
string a = "Test";
string* pa = @a;
*pa += "ing!";
print(a);
```
Result: "Testing!"


**Pointers to variables:**
```
int idata = 0;
int *p_idata = @idata;

*p_idata += 3;
print(idata);
```
Result: 3

**Pointers to functions:**
```
def add(int x, int y) -> int { return x + y; };
def sub(int x, int y) -> int { return x - y; };

// Function pointer declarations
int *p_add(int,int) = @add;
int *p_sub(int,int) = @sub;
```

**Must dereference to call**
```
print(*p_add(0,3));
print(*p_sub(5,2));
```
Result:  
3  
3

**Pointers to objects, structs, arrays:**
```
object    myObj {};                 // Definition
object* p_myObj = @myObj;           // Pointer

struct    myStruct {};              // Definition
struct* p_myStruct = @myStruct;     // Pointer

int[]   i_array;                    // Definition
int[]* pi_array = @i_array;         // Pointer
```

**Pointer Arithmetic:**
```
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

## **Using `asm` to do in-line assembly:**
```
asm
{
mov eax, 1
mov ebx, 0
int 0x80
};
```

If you don't want the compiler to optimize/touch your assembly, use `volatile`:
```
volatile asm
{
	// The compiler will not touch anything in here.
};
```

You can also write volatile constant expressions like so,  
`const volatile def foo() -> void {};`

---

## **alignof, sizeof, typeof:**  
All of these can be performed at comptime or runtime.
```
unsigned data{8:8}[] as noopstr;
signed data{13:16} as strange;

sizeof(noopstr);   // 8
alignof(noopstr);  // 8
typeof(noopstr);   // unsigned data{8:8}*

sizeof(strange);  // 13
alignof(strange); // 16
typeof(strange);  // signed data{13:16}
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

**Array Comprehension:**  
This is where Flux starts to get good.
```
// Basic comprehension
int[] squares = [x ^ 2 for (int x in 1..10)];

// With condition
int[] evens = [x for (int x in 1..20) if (x % 2 == 0)];

// With type conversion
float[] floats = [(float)x for (int x in int_array)];
```

---

## **Loops:**  
Flux supports 2 styles of for loops, Python style and C++ style
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
Destructuring is only done with structs. Structure / Destructure. No confusion.
```
struct Point1 { int x; int y; };

Point1 myPoint1 = {x = 10, y = 20};

auto {t, m} = myPoint1{x,y};        // int t=10, int m=20
```

**Serializing/Deserializing structs:**
```
unsigned data{sizeof(Point1)} as container;

container serialized = (data)myPoint1;        // Serialize

Point1 newPoint1 = serialized from myPoint1;  // Deserialize
```

**Deserializing to a different struct:**
Since deserialization only cares that the size of the serialized data equals the size of the struct.  
For example, struct `Point2` has the same size as `Point1`, but the internal datatypes are different.
```
struct Point2 { i16 a, b, c, d; };             // Still 64 bits wide

Point2 myPoint2 = {a = 5, b = 10, c = 20, d = 40};

Point2 newPoint2 = serialized from myPoint2;   // Now restructured as i16 types
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

## **Compile-Time with `compt`:**
`compt` is used to create anonymous blocks that are inline executed.  
Any variable declarations become global definitions in the resulting program.  
compt blocks can only be declared in global scope, never inside a function or namespace or anywhere else.  
You cannot use compt as part of grammar like `compt def x()` or `compt if()`, but you can put functions and if-statements inside your compt block.  
The Flux compiler will have the runtime built into it allowing for full Flux capabilities during comptime.  
`compt` blocks act as guard rails that guarantees everything inside resolves at compile time.
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
```

**You can also macro operators like so:**
```
def MASK_SET `&;       // Set bits with mask
def MASK_CLEAR `!&;    // Clear bits with mask
def TOGGLE `^^;        // Toggle bits

// Usage becomes incredibly clean
gpio_control MASK_SET 0x0F;     // Set lower 4 bits
status_reg MASK_CLEAR 0xF0;     // Clear upper 4 bits
led_state TOGGLE 0x01;          // Toggle LED bit

// Network byte order operations
def HTONSL <<8;
def HTONSR >>8;    // Host to network short
def ROTL <<;       // Rotate left
def ROTR >>;       // Rotate right
def SBOX `^;       // S-box substitution
def PERMUTE `!&;   // Bit permutation
def NTOHSR >>8;    // Network to host short
def NTOHSL <<8;    // Network to host short

// Checksum operations
def CHECKSUM_ADD `+;
def CHECKSUM_XOR `^^;
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

If you define a macro inside a function, it will not be global because it is locally scoped to the function. You must use `global` to make the macro global.  

This means if you want pre-processor behavior, just wrap all your behavior inside an anonymous block marked `compt` anywhere in your code.  
This also means you can write entire compile-time programs, the Flux runtime is built into the compiler for this purpose.  
`compt` gives you more access to zero-cost abstractions and build time validation to catch errors before deployment.  
Bad comptime code will result in slow compile times, example writing an infinite loop in a `compt` block that doesn't resolve means it never compiles.  
If you want to write an entire Bitcoin miner in compile time, that's up to you. Your miner will run, but it will never compile unless a natural program end is reached.

---

## **Assertion:**  
`assert` automatically performs `throw` if the condition is false if it's inside a try/catch block, otherwise it automatically writes to standard error output if a string is provided.
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

## **External FFI:**
Flux will support FFI to make adoption easier.  
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

---

## **Runtime type-checking:**
```
Animal* pet = @Dog();
if (typeof(pet) == Dog) { /* Legal */ };
// or
if (pet is Dog) { /* Legal, syntactic sugar for `typeof(pet) == Dog` */ };
```

---

## **Templates:**
You can template functions, structs, objects, and `operator`s.  
Examples of template syntax with prototypes:
```
def myFunc<T>() -> void;

object myO<T>;

struct myS<T>;

operator<T>(T L, T R)[==] -> T;
```

---

**Operator Overloading:**

```
object myObj
{
	int x;

	def __init(int a) -> this
	{
		this.x = a;
	};

	def __exit() -> void
	{
		return (void)this;
	};
};

myObj j(1), k(2);

operator (myObj a, myObj b)[+] -> myObj
{
	myObj newObj(a.x + b.x);
	return newObj;
};

print(j + k);   // 3

// This allows you to create operators like a chain operator:

operator (int a, int b)[<-] -> int()
{
	return a(b());
};

// You can now do `a() <- b();` if both are integer type functions.

// Valid operator characters:    `~!@#$%%^&*-+=|<>

// You can do operator contracts as well
contract opAddNonZeroInts
{
	assert(a != 0);
	assert(b != 0);
}

operator (int a, int b)[+] -> int
{
	return a + b;
} : opAddNonZeroInts;

// Now + will only add non-zero integers in the case of two integer operand addition.
```

---

## **Contracts:**  
Contracts are a collection of assertion statements. They can only be attached to functions, structs, and objects since they are assertions on data.  
Contracts must refer to valid members of the function, struct, or object they are contracting.

Pre-contracts must refer to valid parameters being passed.  
Post-contracts must refer to valid members of the function at the time of contract execution.

Example, if you void cast anything and a contract refers to it, that will result in a use-after-free bug.
```
// Prototype
contract MyContract;

// Definition
contract PreContract
{
	assert(typeof(a) == int, f"Invalid type passed to {this}.");
	assert(a != 0, "Parameter must be non-zero.");
};

contract Inheritable
{
	assert(b != 0);
};

contract PostContract : Inheritable  // Can perform contract inheritance
{
	assert(typeof(a) == int, f"Invalid type passed to {this}.");
	assert(a != 10);  // Automatically raises ContractError
	assert(b == 5);   // ''
};

// Implementation
def foo(int a) -> int : PreContract // Checks parameters
{
	int b = 5;
	return a * 10;
} : PostContract;   // Check just before the return

// Example
def bar(int a) -> int
{
	return foo(a);
};

int x = bar(1);   // Fails PostContract in foo()

contract BasicContract
{
	assert(a != 0, "Value must be non-zero.");
};

// Contracts for structs or objects go after the definition, because : after the name is for inheritance.
// Contracts for structs or objects only apply AFTER instantiation. They are always considered post-contracts.

struct MyStruct
{
	int a = 0;
} : BasicContract; // Valid until instanced.

object MyObject
{
	int a = 0;

	def __init() -> this
	{
		return this;
	};
} : BasicContract;  // Valid until instanced.

MyObject someObj(); // ContractError: Object instantiation prevented.
```

Overuse of contracts can add significant overhead to a Flux program. If you don't have a good reason to use them, you shouldn't. 
Contracts in compt blocks behave identically to runtime contracts, but since compt executes at compile time, a contract failure halts compilation.  
Use this for compile-time validation without runtime cost.

**Enhanced unique pointer with operators and contracts:**
```
contract notSame {
	assert(@a != @b, "Cannot assign unique_ptr to itself.");
};

contract canMove : notSame {
	assert(a.ptr != void, "Cannot move from empty unique_ptr.");
	assert(b.ptr == void, "Destination must be void.")
};

contract didMove {
	assert(a.ptr == void, "Move must invalidate source.");
	assert(b.ptr != void, "Destination must now own the resource.");
};

operator (unique_ptr<int> a, unique_ptr<int> b)[=] -> unique_ptr<int> : canMove
{
	b.ptr = a.ptr;    // Transfer
	a.ptr = void;     // Invalidate source
	return b;
} : didMove;
```

In the context of developing smart pointers and unique pointers, operators combined with contracts shine.
This creates a selective runtime pseudo-borrow-checker. You borrow check what you want borrow checked.

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
	};

	// ... other methods ...
};
```

---

## Ownership  
Ownership in Flux is made possible with `~`. Here's how:
```
def ~make() -> ~int 
{
    int ~x = new int(42);
    return ~x;
};
```
The compiler checks, like so:
```
def ~make() -> ~int 
{
    int ~x = new int(42);
    return x;  // ❌ ERROR: Must use ~x
};
```
Leaked ownership:
```
def ~oops() -> void 
{
    int ~x = new int(42);  // ❌ ERROR: ~x not moved/destroyed
};
```
Full example:
```
def ~read_file(string path) -> ~string 
{
    ~File f = new File(path);
    ~string data = read_all(f.fd);
    return ~data;  // Explicit transfer
};

def main() -> int 
{
    ~string content = ~read_file("log.txt");
    print(*content);
    // content auto-freed here via __exit()
    return 0;
};
```
Escape hatch:
```
int* raw = (~)my_owned;
```

Full specification hell in a function:
```
const volatile def ~foo<T>(T a) -> ~T : PreContract  // don't hurt me i'm scared
{
	T ~b = new T(5);
	return ~b + a;
} : PostContract;
```

---

Keyword list:

```
alignof, and, as, asm, assert, auto, break, bool, case, catch, compt, const, continue, data, def, default, do,
elif, else, extern, false, float, for, from, global, if, import, in, is, int, local, namespace, new, not, object,
operator, private, public, return, signed, sizeof, struct, super, switch, this, throw, true, try, trait, typeof,
union, unsigned, using, void, volatile, while, xor
```

Literal types:
bool, int `5`, float `3.14`, char `"B"` == `66` - `65` == `'A'`, data
