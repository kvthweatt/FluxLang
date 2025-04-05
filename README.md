Flux is a mix of C++, Zig, and Python.

Whitespace is ignored, and semicolons **must** follow `code_braces{};` or `state = ments;`

All Flux code and examples will be written with Allman style braces.

Flux has literal ***object*-oriented programming** by having an `object` keyword.

--------

**What's the difference between `object` and `class` types?**

**Objects:**
- Prototype / forward declaration: `object myObj;`
- Definition: `object myObj {};`
- Instance: `myObj(){} newObj;`
- Member access: `newObj.x`

Example usage:
```
object myObj
{
	def __init(x, y) -> void
	{
		this.a = x;
		this.b = y;
		return;
	};
};

myObj(data1, data2){} testObject;
```

Inheritance:
```
object anotherObj<myObj>
{
	def __init() -> void
	{
		super.myObj.__init();
		return;
	};
};
```

Objects cannot be defined inside of a function, they must be within a namespace, a class, another object, or global scope.
`__init` is always called on object instantiation.

**Classes:**
- Prototype / forward declartion: `class myClass;`
- Definition: `class myClass {};`
- Instantiation: `myClass(x,y){} newClass;`
- Member access: `newClass.newObj.x`

Example usage:
```
class myClass
{
	object __construct              // Specialized dunder object for class construction
	{
		def _(x,y) -> void          // Mandatory default method for constructors / destructors
		{
			return;
		};
	};

	object __destruct               // Specialized dunder object for class destruction
	{
		def _() -> void
		{
			return void:super;      // Destroy this parent class
		};
	};
};
```

Classes cannot be defined inside of a function, they must be within a namespace, another class, an object, or global scope.

Classes cannot contain functions or anonymous blocks.

Classes must contain objects that modify the class members.


Classes can only inherit from classes, and objects can only inherit from objects.

**Namespaces:**
- Definition: `namespace myNamespace {};`
- Scope access: `myNamespace::myClass`

Namespace example:
```
namespace std
{
	class myClass1
	{
		object myObj
		{
			def __init() -> void
			{
				return;
			};
		};
	};
};

namespace std
{
	class myClass2<myClass1>
	{
		object myObj
		{
			def __init() -> void
			{
				return;
			};
		};
	};
};
```

Namespaces **MUST** be in global scope.

Duplicate namespace definitions do not redefine the namespace, the members

of both combine as if they were one namespace. This is so the standard

library or any library can have a core namespace across multiple files.

Namespaces are the only container that have this functionality.

Namespaces can only directly contain classes at their root scope.



The reason classes, objects, and structs cannot be defined inside of functions

is to make functions cleanly written. You can define them globally,

or organize them into a namespace, but not in functions.

Structs can contain instances of objects and classes, but you cannot instance them inside the struct.

Structs cannot contain functions, templates, or anonymous blocks, but they may contain pointers to functions and templates.
```
object myObj
{
	def __init() -> void
	{
		return;
	};
};

myObj{} newObj1, newObj2;  // Must be instanced outside of the struct

struct myStruct
{
	newObj1;
	newObj2;
};

struct newStruct
{
	myStruct;              // structs can contain structs
}
```

A Flux program must have a main() function, and must be defined in global scope.

**Function definition:**
```
def name (parameters) -> return_type
{
	return return_value;                      // A `return` statement must be found somewhere within a function body.
};

// Example function
def myAdd(int x, int y) -> int
{
	return x + y;
};

// Overloading
def myAdd(float x, float y) -> float
{
	return x + y;
}

// Templates can accomplish the same thing without multiple functions.
```

Functions cannot contain functions, another syntactic rule to keep code clean.
If a function's return type is void nothing will be returned, regardless if your return statement provides something.

// Small example Flux program
```
namespace Program
{
	class AnotherApp
	{
		bool myFlag = false;

		object myObj
		{
			def __init() -> void
			{
				this.myFlag = true;
				return;
			};
		};
	};
};

namespace Program
{
	class App<AnotherApp>
	{
		object Engine
		{
			def __init() -> void
			{
				if (super.AnotherApp.myFlag == false)
				{
					print("Not instanced.");
					return;
				};
			};

			def state() -> bool
			{
				return super.AnotherApp.myFlag;
			};
		};
	};
};

def main() -> !void
{
	Program::App.Engine{} myEngine;
	print(myEngine.state()); // 1
	return 0;
};
```


Class and object inheritance:
```
class First
{
	object obj1                           // This object cannot be instanced, it has no __init() method
	{
		int x = 5;
	};
};

class Second
{
	object obj2
	{
		def __init(int x) -> void
		{
			this.x = x;
			return;
		};
	};
};

class Third<First,Second>
{
	object Program<obj1>
	{
		def __init() -> void
		{
			print(this.x);   // 5
			return;
		};
	};
};

def main() -> !void
{
	obj2(3){} myObj;
	print(myObj.x);  // 3
	return 0;
};
```

This is inheritance exclusion:
```
class First
{
	object firstObj
	{
		int x;
		def __init(int x) -> int
		{
			this.x = x;
			return this.x;
		};
	};

	object secondObj
	{
		int z;
		def __init(z) -> int
		{
			this.z = z;
			return --this.z;
		};
	};

	object thirdObj
	{
		int y;
		def __init(k) -> int
		{
			this.y = k;
			return ++this.k;
		};
	};
};

class Second<First{!firstObj}>
{
	object Program
	{
		def __init() -> void
		{
			secondObj(3){} myObj;
			print(myObj.z); // 2
			return;
		};
	};
};
```

You can also use assembly directly:

```
asm {
mov eax, 1
mov ebx, 0
int 0x80
};
```

Python uses f-strings, C++ uses a complicated format, Zig syntax is overly verbose.
Flux uses "injectable" strings, and tries to fix Zig's syntax a bit.
The syntax in Flux would be: `i"{}{}{}":{x;y;z;};`
The brackets are replaced with the results of the statements in order respective
to the statements' position in the statement list.

**i-string Example:**
```
def bar() -> !void { return "World"; };
print(i"Hello {} {}":
              {
              	bar() + "!";
                "test";
              };                            // Whitespace is ignored, this is just for positioning
     );
```

This allows you to write clean injectable strings without strange formatting.
Every code block must be ended with a semicolon. The only exception is within the i-string "quoted {} injected {} text"


Example 2:
```
def concat(string a, string b) -> string
{
    return a+b;           // string array addition is native so we really don't need this function
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
```
Result: "Testing!"

**Pointers to variables:**
```
int data = 0;
int *p_data = @data;

p_data += 3;
print(data);  // 3
```

**Pointers to functions:**
```
def add(int x, int y) -> int
{
	return x + y;
};

def sub(int x, int y) -> int
{
	return x - y;
};

int *p_add(int,int) = @add;  // Similar to C++ syntax but no syntactic sugar
int *p_sub(int,int) = @sub;

print(p_add(0,3)); // 3
print(p_sub(5,2)); // -3

list func_list = [p_add,p_sub];
```


**Pointers to objects, classes, structs, arrays, and dictionaries:**
```
class myClass {};                   // Definition
class* p_myClass = @myClass;        // Pointer

object myObj {};                    // Definition
object* p_myObj = @myObj;           // Pointer

struct myStruct {};                 // Definition
struct* p_myStruct = @myStruct;     // Pointer

int[] i_array;                      // Definition
int[]* pi_array = @i_array;         // Pointer

// Arrays that have multiple datatypes contained are void[] arrays
void[] v_array;                     // Definition
void[]* pv_array = @v_array;        // Pointer

dict myDict;                        // Definition
dict* p_myDict = @myDict;           // Pointer
```


**Recursive function:**
```
def rsub(int x, int y) -> int
{
	if (x == 0 || y == 0) { return 0; };

	rsub(--x,--y);
	return 0;
};
```


**Import:**
```
import "std.fx" as std;
using std.io, std.types;          // Only use `io` from std.fx (std.fx imports `input.fx` and `output.fx`
//import "math.fx";               // Direct import of all the contents of math.fx as if the source replaced this line
```


!void is merely a way of telling the compiler you don't know what type you'll return. You may have a function that is complex and returns various - or compound - types. Flux does not support the Python-like syntax of specifying multiple return types, so we use !void instead. However, specifying the type does allow for optimization.


**Example of the `data` type and casting:**
```
import "std.fx" as std;  // `std` becomes an immutable identifier
using std.types;         // Standard types like int, uint, float, ufloat, byte, string, string, and so on.

byte someByte = {0, 1, 0, 0, 0, 0, 0, 1};     // "A" but in binary
// Example of casting to string:
string somestring = i"{s}":{someByte;};       // "A" - This is the standard way to cast to string in Flux
// Back to data
somestring = data:somestring;                 // {0, 1, 0, 0, 0, 0, 0, 1}
string anotherstring = "B";                   // {0, 1, 0, 0, 0, 0, 1, 0}

somestring<<;                                 // {1, 0, 0, 0, 0, 0, 1, 0}  // Bit-shift left  (binary doubling)
somestring>>;                                 // {0, 1, 0, 0, 0, 0, 0, 1}  // Bit-shift right (binary halving)

string newstring = xor(somestring);           // {1, 0, 1, 1, 1, 1, 1, 0}  // Bit-flip (binary XOR)
newstring = xor(somestring,anotherstring);    // {0, 0, 0, 0, 0, 0, 1, 1}  // XOR two or more values ('A' XOR 'B' = 3)

// This 0's out all the data and re-casts back to data from void.
// The temporary void casted type is the same width as the original type.
data v = void:somestring;                     // {0, 0, 0, 0, 0, 0, 0, 0}

class someClass
{
	string x = "Hello World!";                 // 12 bytes long (96 bits)
	data {3} some3bitDatatype;                 // 3 bits long
};

data d_someClass = data:someClass              // 99 bits long with no alignment, aligns to class members if cast
someClass{} c_newInst = someClass:d_someClass; // Cast back to someClass (only works if class definition has members to fill)

someClass{} nulled = void:c_newInst;           // You can only void instances of classes, and objects.

// The same casting behavior applies to objects and structs
```

Casting anything to `void` is the functional equivalent of nulling the memory occupied by that thing.



Data is a variable bit width, primitive binary data type. Anything can cast to it,

and it can cast to any standard Flux type like string, int, float, etcetera.

It is intended to allow Flux programmers to build complex custom types to

fit their needs that are flexible.


All standard Flux types are built from the data type.

These types are defined in the standard library.

- int is defined as `signed data {32} int;`
- uint is defined as `unsigned data {32} uint;`
- bit is defined as `signed data {1} bit;`
- float is defined as `signed data {64} float;`
- ufloat is defined as `unsigned data {64} ufloat;`
- string is defined as `signed data{8}[] string;`


**The void keyword:**
void is equivalent to Python's None as well as C++'s void and can be used in both contexts such as:

`if (x is void) {...};`

- or

`x = void;` which is equivalent to `void x;`

`x = int;` is equivalent to `int x;`


**Templates:**
```
template <T> myMax(T x, T y) -> T
{
    return (x > y) ? x : y;
};

// Pointer to template function:
template <T*> t_myMax(T,T) = @myMax;
```


Flux allows defining custom operators with `operator` and their use with `op<LH operator RH>;`.

You cannot redefine Flux built-in operators (+,-,*,/,&,==,+=,++,-=,-- etc)

You define operators in the following manner:
```
operator(int x, int y)[e+] -> float  // Or any return type
{
	return (x * (10 ** y))
};

operator(int x, int y)[e-] -> float
{
    return (x * (10 ** (y * -1)))
};

// To use an operator in code, you write:
def main() -> !void
{
	print(op<1 e+ 20>-1); // Result of (1 * 10^20) - 1
	return 0;
};

// Compound op<> usage example
op<op<1 e+ 20> e- op<1 e+ 20>>;   // (1 * 10^20) * (10 ^ ((1 * 10^20) * -1)) equivalent
```


**Arrays:**
```
signed data {32} int;

int[] ia_myArray = [3, 92, 14, 30, 6, 5, 11, 400];

int[][] ia_my2D = [3,6,9][1,2,4,5,7,8];
int[][][] ia_my3D = [...][...][...];             // This extends up to 256 "dimensions", the same number of parameters a function can take.

// int cause_an_error = ia_myArray[10];          // Length is only 8, accessing index 11, undefined result

int[] ia_mySorted = []
int tmp, lowest;

for (x in ia_myArray)
{
	if (x < _.next())   // Built-in next getter method for iterables (iterable denoted with `_`)
	{
		x in ia_mySorted ? continue : ia_mySorted.append(x);
	};

	if (ia_myArray.len() < ia_mySorted.len())    // Lengths unequal, not done sorting
	{
		_.setpos(0);    // Reset the iterator position to 0, allowing the loop to continue
	}
	else if (ia_myArray.len() == ia_mySorted.len())
	{
		break;
	};
};
```

**Dictionaries:**
```
signed data {32} int;

dict myDict1 = {0: "First",
               1: "Second,
               2: "Third"}

dict myDict2 = {"test_1": "Test phrase 1.",
                "test_2": "The void stares back.",
                "test_3": "Hello World!"}

for (x,y in myDict1)
{
	switch (y)
	{
		case("Second")
		{
			print("Second!");
		};
		case(default)
		{
			print("Not the second index in this dictionary.");
		};
	};
};
```


**Logic:**
```
import "std.fx" as std;

using std.exceptions;

signed data {32} int;
signed data {1} bool;
signed data {8}[] string;

def main() -> int
{
	bool myFlag = false;
	string fname, lname = "John", "Doe";

	if ("Do" in lname)
	{
		myFlag = true;
	}
	else
	{
		throw("\"Do\" not found in last name!");
	};

	try
	{
		while (true)
		{
			switch (fname)
			{
				case ("John")
				{
					break;
				};
				case (default)
				{
					throw("The name ain't John."){__exception = std.exceptions.base;};
					// Can throw anything, caught from while, switch, or case(default) as `e` in this example is a string.
					// Acts as a `break;` equivalent but is not the same.
				};
			};
		};
	}
	catch (__exception as e)    // Special dunder for catching the exception from throw
	{
		if (e == std.exceptions.base)
		{
			print(i"throw chain: while -> switch -> case(default)\nException: {}":{e;});
			return 1;
		}
	};

	return 0;
};
```


Keyword list:
as, asm, and, break, case, catch, class, const, continue, data, def, default, do
else, enum, false, for, if, import, in, is, namespace, not, object, op, operator,
or, return, signed, sizeof, struct, super, switch, template, this, throw, true,
try, typeof, unsigned, using, void, while, xor


Literal types:
array `[a,b,c,d,...]`, dictionary `{a:b,c:d,...}`, integer `5`, float `3.14`, string `""`


Types:
data, list, dict, void, const


- Member access .
- Scope resolution ::
- Function call (), array subscript []
- Prefix/Postfix increment/decrement ++, --
- Unary plus/minus +, -
- Logical NOT and bitwise NOT !, ~
- Address-of and dereference &, *                   // Switch & to @ -- it's more logical (at memory location duh)
- Type casting type:identifier
- Exponentiation **
- Multiplication, division, modulo *, /, %
- Addition, subtraction +, -
- Bit shift <<, >>
- Relational <, <=, >, >=
- Equality, inequality ==, !=
- Identity is, not, as
- Bitwise AND &
- Bitwise XOR ^
- Bitwise OR |
- Logical AND and, &&
- Logical OR or, ||
- Conditional expression ? :
- Assignment =, +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=, **=
- Comma operator ,
