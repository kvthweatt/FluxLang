# Intro to Programming with Flux

For the purposes of this document, it is assumed this is your first language.  
If it isn't, or if you're a pro, that's ok too!  

- **What is programming?**  
Programming is the art of writing software with a programming language like C, Haskell, Python, Fortran, and others. We say art because anyone can program, but it takes skill to write good code.  
Software is virtual, non-physical. You can't physically touch it. Software lives in and on hardware.  
Hardware is physical, like your hard drive, keyboard, or monitor.  
Firmware is a kind of software which lives *in* your hardware.  
Software, specifically applications, live *on* your hard drive.

- **How does code actually run?**  
To put it simply, all devices have a central processing unit (CPU).  
The CPU is responsible for decoding and executing instructions.  
Programs or applications are a collection of instructions.  
The operating system follows the rules of the CPU to create extended rules. The operating system uses the extended rules to execute programs. This is a simplified explanation and the reality is more nuanced than this.

- **How do you make programs?**  
Every program starts with source code. Source code is the human-readable code written in a programming language.  
If the language is a *compiled* language, you *compile* your source code into an executable program file.  
If the language is an *interpreted* language, you pass your source code to an *interpreter* which executes your program in memory.  
Programs written for one operating system will not work on a different operating system.  
A program compiled for Linux will not execute on Windows.  
CPU architecture also affects whether a program will run or not.  
A program compiled on a RISC CPU will not run on an ARM CPU.

- **Why won't Windows programs run on Linux?**  
Operating systems have different architectures, and as a result, different *system calls*.  
Every operating system does the same basic functions like reading and writing files, but have different function names for these tasks.  
Most languages have *libraries* which allow you to call these functions. They expose your kernel to the application binary interface or *ABI*.

If you're still keeping up, excellent. If not, [Google](https://google.com/) is your friend. Look up the italicized terms.

All of this information will become useful later. For now, let's begin learning how to program.

---

## 1 - Fundamentals  
Flux sits broadly between high and low level. What is that you ask?  
High level languages are languages that are very close to human language. A good example is Python.  
While Python isn't compiled, it still creates programs.
Python looks like:
```
if (user not in userlist):
    userlist.append(user)
```
It is almost like speaking.

Low level languages are more similar to machine code in regard to how it translates to machine code.  
There are still human-readable terms like `if` and `true`/`false` but how it relates to machine code will be explained later.  
C++ is a low level language, here's an example:
```
for (int x = 0; x < 100; x++)
{
    *ptr->value = x; foo(*ptr);
};
```

As you can see, Python and C++ are very different.  
Flux sits right between the two in terms of grammar and syntax, which we will see shortly.  

To work with a language like Flux you need to understand computer memory.  
We're going to start from the smallest unit and work our way up.

The smallest unit of memory (or data) is a bit. A bit is a single digit, 1 or 0.  
A group of 8 bits is called a byte. An example: `01000001` equals 65. Here's an example of a memory segment that is 8 bits long:

<table align="center">
  <tr>
    <th>2 ^ 8 (128)</th>
    <th>2 ^ 6 (64)</th>
    <th>2 ^ 5 (32)</th>
    <th>2 ^ 4 (16)</th>
    <th>2 ^ 3 (8)</th>
    <th>2 ^ 2 (4)</th>
    <th>2 ^ 1 (2)</th>
    <th>2 ^ 0 (1)</th>
  </tr>
  <tr>
    <td>0</td>
    <td>1</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>1</td>
  </tr>
  <tr>
    <td>0</td>
    <td><b>64</b> * 1 = 64</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td><b>1</b> * 1 = 1</td>
  </tr>
</table>

Above we see 1 in the 64's place, and a 1 in the 1's place. We add 64 + 1 and get 65.

- **What does `01000001` mean though?**  
All data is inherently meaningless. It is up to you, the programmer, to give meaning to data.  
- **How do we make `01000001` mean something?**  
We do something like this:  
`years_old = 65;` (remember it equals 65 so you can imagine binary here)  
`miles_per_hour = 65;`  
`percent_complete = 65;`  
Notice anything? We have variables that all equal 65. They're all the same data, but clearly they should be used differently. We're not going to say someone is 65 miles per hour, we say they're 65 years old.  

Some very smart people at **[NIST](https://www.nist.gov/)** (formerly known as **ASA**) engineered a way to represent characters on screens so you and I can read, known as **[ASCII](https://asciitable.com/)**. It is a table of values ranging 0-255. The value range of a byte is also 0-255.

<p align="center">
<img src="https://www.asciitable.com/asciifull.gif">
<img src="https://www.asciitable.com/extend.gif">
</p>

- **How does this relate to programming?**  
It's dangerous  to go alone, take this. Generally speaking you will not be needing this table, but it's a good thing to have. When you start to learn string manipulation this will become relevant again.

- **Diving into memory:**  
You can imagine computer memory to be linear. Whether you want to visualize it horizontally or vertically, it doesn't matter. What matters is understanding memory is made up of bits. If I have 1 GB of memory, that's 1 billion bytes; multiplied by 8 and you get 8 billion bits. We always count in bytes (groups of 8) when we count memory spaces.

<table align="center">
  <tr>
    <th>Address</th>
    <th>0</th>
    <th>1</th>
    <th>2</th>
    <th>3</th>
    <th>4</th>
    <th>5</th>
    <th>...</th>
    <th>1,073,741,824</th>
  </tr>
  <tr>
    <td>Value</td>
    <td>0xDE</td>
    <td>0xAD</td>
    <td>0xBE</td>
    <td>0xEF</td>
    <td>0xDE</td>
    <td>0xAD</td>
    <td>...</td>
    <td>0xEF</td>
  </tr>
</table>

- **Data types:**  
There is 1 byte per address. So now, say I want to get the value of some bytes. Welcome to data types.  
Integer (`int`) types in Flux are 32 bits by default. 32 divided by 8 equals 4, so an `int`  is 4 bytes long. Let's start at address 2 and read an integer, we get `0xBEEFDEAD`.  
When we convert to base 10 (what we can read) we get: **3,203,391,149**.  
Let's say we're using a half-sized `int` that is only 2 bytes, starting at address 2, we get `0xBEEF`.  
Converted to base 10: **48,879**. A much smaller number.

- **How did we convert 0xBEEFDEAD to a number? What even is that?**  
A value like 0x5A206AE0 (**0x** prefix) is known as a hexidecimal number, or base 16. Humans read numbers in decimal or base 10. Binary is base 2. The base number represents how many numbers are available to make other numbers. Binary has 2 numbers available, 0 and 1. Decimal has 10 numbers, 0 through 9. Hexadecimal uses 6 more values, we call them A, B, C, D, E and F. This means hexadecimal ranges from 0-F, or 0 1 2 3 4 5 6 7 8 9 A B C D E F. This is essentially 0-15 which if you include the 0, is 16 numbers. **The value 10 in any numbering system is equal to the base of the numbering system.** In binary, 10 equals 2, there's a 1 in the 2's place. In hexadecimal the number 10 equals 16, here's how:

<table align="center">
  <tr>
    <th>16 ^ 3 = <br>(4096)</th>
    <th>16 ^ 2 = <br>(256)</th>
    <th>16 ^ 1 = <br>(16)</th>
    <th>16 ^ 0 = <br>(1)</th>
  </tr>
  <tr>
    <td></td>
    <td></td>
    <td>1</td>
    <td>0</td>
  </tr>
  <tr>
    <td></td>
    <td></td>
    <td>1 * 16<br>= 16</td>
    <td>0 * 1<br>= 0</td>
  </tr>
</table>
Another example using 0xFF:
<table align="center">
  <tr>
    <th>16 ^ 3 = <br>(4096)</th>
    <th>16 ^ 2 = <br>(256)</th>
    <th>16 ^ 1 = <br>(16)</th>
    <th>16 ^ 0 = <br>(1)</th>
  </tr>
  <tr>
    <td></td>
    <td></td>
    <td>F</td>
    <td>F</td>
  </tr>
  <tr>
    <td></td>
    <td></td>
    <td>F * 16<br>=<br>15 * 16<br>= 240</td>
    <td>F * 1<br>=<br>15 * 1<br>= 15</td>
  </tr>
</table>

240 + 15 = 255, or the max value of a byte. Bytes in hexadecimal have 2 digits, like 0xFF or 0xA3.

In Flux there are 3 primitive types known as `int`, `float`, and `char`.  
- `int` types are 32 bits long (4 bytes)
- `float` types are 64 bits long (8 bytes)
- `char` types are 8 bits long (1 byte)

We also have a **super-primitive** known as `data`. Any primitive type can convert to `data` and back.  
We will go over the `data` keyword in depth later in this guide.

This is the fundamental understanding of data required going into Flux.   
If you're still following, congratulations. Now we get to actually learn to code.

---

## Your first program.

We're going to start off doing something very simple. We're not going to see anything happen, but the purpose of this excercise is to familiarize you with the process of compilation.

Flux program have a `main()` function. `main()` is called by your operating system automatically.  
Not having a `main()` function will result in a compilation error. Compiling programs without a `main()` function is how we create libraries. As far as we're concerned - and until we get to libraries - all programs we write **must** have a `main()` function.

#### f1.1:
```
def main() -> int
{
    return 0;
};
```
This program does nothing. It will start and immediately stop. If you compile and run this, you will think something is broken, or did not work. This is actually expected behavior, we shouldn't see anything because the program didn't do anything.

This is what you could call the skeleton of a Flux program. Any program you compile into an executable must have a main function defined in **global scope**.

- **What are *global* and *scope*? What is *global scope*?**  
A global is something that can be referred to anywhere in the program. It exists so long as it isn't destroyed or invalidated in some way. Imagine a tree:
 <ul id="myUL">
  <li><span class="caret">Program</span>
    <ul class="nested">
      <li>int a = 1</li>
      <li><span class="caret">myFunction()</span>
        <ul class="nested">
          <li>int b = 0</li>
        </ul>
      </li>
      <li><span class="caret">main()</span>
        <ul class="nested">
          <li>int c = a + b</li>
        </ul>
      </li>
    </ul>
  </li>
</ul>

If we look at this tree, we can see `int a`, `myFunction()` and `main()` exist at the same level as each other.  
Figure 2.2 demonstrates this program.

#### f1.2
```
// Double slashes are comments, the compiler ignores this as if it doesn't exist

int a = 1;      // This is in global scope.

def myFunction() -> int
{
    int b = 0;  // This is in myFunction's scope.
    return b;
};

def main() -> int
{
    int c = a + b;  // Error here
    return c;
};
```

If we try to compile this program, we will get an unknown identifier error at line 13 column 16. The unknown identifier is `b`.  
Why is `b` unknown? As far as `main()` is aware, the only things that exist to it are `a` and `myFunction`.  
`myFunction` is totally aware of `b` because it's in scope. How would we fix this? Like so,
#### f1.3
```
int a = 1;

def myFunction() -> int
{
    int b = 0;
    return b;
};

def main() -> int
{
    int c = a + myFunction();  // myFunction returns the value of b
    return c;
};
```

- **What exactly is a function?**  
A function is a section of your program which does something. A function might check if two things are equal to each other, or it might handle authorization. It does whatever you write the function to do. Algorithms are a collection of functions that when executed in a specific order achieve a desired result.

In figure 1.3 we see two functions, `main()` and `myFunction()`.

Program execution always begins at `main()`. The first thing that happens is we create a new integer variable named `c` and assign it the value `a + myFunction()`. In order to evaluate this, we need to know what `myFunction()` equals, so we call the function (execute it), and it returns the value `0`. Then `a + 0` is evaluated as `1 + 0` and becomes `1`. After evaluating everything to the right of the `=`, we assign the result to `c`.

Take the time to make your own functions, play around and name them whatever you like, then compile your program.

---

## 2 - Simple Functions

### Temperature Conversion (C / F)
We're going to write a program to convert centigrade to fahrenheit.  
The formula for fahrenheit is °F = (°C * 9/5) + 32  
The formula for centigrade is °C = (°F - 32) * 9/5

Here's how we implement this:
#### f2.1
```
def c_to_f(float temp) -> float
{
    return (temp * (9/5)) + 32;
};

def f_to_c(float temp) -> float
{
    return (temp - 32) * (9/5);
};

def main() -> int
{
    c = -40;
    f = c_to_f(c);  // -40 °C == -40 °F
    return 0;
};
```

### Calculating distance
#### f2.2
```
def get_distance(float speed, float time) -> float
{
    return speed * time;
};

def to_meters(float distance) -> float
{
    return distance / 3.28084;
};

def main() -> int
{
    float speed = 88;    // Calculating in feet per second
    float time = 60;     // 1 second
    float d = get_distance(speed, time);  // 5,280 feet = 1 mile
    float m = to_meters(d);               // 1,609.34 meters
    return 0;
};
```

### Performing logic
#### f2.3
```
int a = 0;
int b = 100;

def main() -> int
{
    if (a < b)
    {
        a = b;
    };

    return 0;
}
```

`if` statements evaluate truth. All that is really happening is the expression inside of the parenthesis is evaluated, and if it's true, we do the code inside the `if` block.
- Blocks are `{}` and the code within it. In figure 2.3 there are 2 blocks.  

### Logically performing logic
#### f2.4
```
int a = 0;
int b = 100;
int c = 1000;

def main() -> int
{
    if (a < b)
    {
        a = b;
    }
    elif (a < c)
    {
        a = c;
    };

    return 0;
}
```
#### f2.5
```
int a = 0;
int b = 100;
int c = 1000;

def main() -> int
{
    if (a < b)
    {
        a = b;
    };
    if (a < c)
    {
        a = c;
    };

    return 0;
}
```
- **Figures 2.4 and 2.5 are identical as far as their result, but their execution is  different, and the assembly (machine code) resulting from these figures also differs.**

Our goal is to make `a` equal to `b`. Here's how we do that:
#### f2.6
```
int a = 0;
int b = 100;
int c = 1000;

def main() -> int
{
    if (a < b)               // Condition 1 (true) (completely true)
    {
        a = b;
    }
    elif (a >= b and a < c)  // Condition 2 (false and true) (not completely true)
    {
        a = c;
    };

    return 0;
}
```
Now execution won't continue into the `elif` block, because only one of the two conditions are completely true.

---

## 3 - Hello World
We now have a basic understanding of functions, and logical operations. Now it's time we see something happen on the screen.

#### f3.1 Hello World
```
import "io.fx";

using io::output::print;

def main() -> int
{
    print("Hello World!");
    return 0;
};
```
Result:  
`Hello World!`

The `print()` function will output a string to standard output. It takes 1 argument, the type of the argument is `unsigned data{8}[]` which is an unsigned byte array.

- **What's the difference between `signed` and `unsigned`?**  
Signed integers can have a positive or negative value. The *sign* is 0 for positive, 1 for negative. Typically the most significant bit (largest value) represent the signedness of an integer.  
Example if we have a binary value `10000000` and we treat it as signed it equals `-128`.  
If this value was unsigned, it would equal `128`.  
This means if we tried to interpret a character like the capital letter `A` as signed, we would still get A, but as soon as we go higher than `127` the value wraps around to the negatives and counts upwards towards zero. The ASCII table does not have negative values, only `0-255`.

#### f3.2 What's your name?
```
import "io.fx";
import "types.fx";

using io::output::print, io::input::input;
using types::string;

def main() -> int
{
    string s();
    s = input("What's your name? ");
    print("\n");
    print("Hello, ); print(s); print("!")
    return 0;
};
```
Result:
```
What's your name? John
Hello, John!
```

That code was a little ugly, don't you think? Hard to read unless you take the time to look.  
Also, what was that `\n` thing we printed? That is called an escape character. We "escape" the string with the backslash (`\`). There are a few escape characters to go over, but for now, `\n` is all we need.  
This character represents a new line, or "carriage return". In reality, no text file you have ever read actually breaks words onto a new line  
like this.  
What's actually happening is there is an invisible character which instructs a text editor to move to a new line. In memory, the file spans linearly, it doesn't break into lines. We write programs to show these line breaks.
#### f3.3 Introducing `f-strings`:
```
import "io.fx", "types.fx";  // You can do multiple imports on one line.

using io::output::print, io::input::input;
using types::string;

def main() -> int
{
    string s();
    s = input("What's your name? ");
    print(f"\nHello, {s}!");
    return 0;
};
```
That's better. Here we see a string `"\nHello, {s}!"` but it is prefixed with an `f`. This makes this string an `f-string`. Flux also has something called an `i-string` but those are more advanced, we'll save them for later.

---

## 4 - String Manipulation
We will now learn different ways we can play with strings, starting by slicing them up.
#### f4.1 Slices
```
import "io.fx", "types.fx";

using io::output::print;
using types::string;

def main() -> int
{
    string s();
    s = "Testing!";
    print(s[0:3]);
    return 0;
};
```
Result:  
`Test`

What did we just do? What is that `[0:3]` notation?  
This is known as array slice notation.  
It translates to "start at position 0, end at position 3". That totals 4 bytes, or `"Test"`.  
- `[x:y]`  
**x** is the starting point, and **y** is the ending point.

#### f4.2 Reverse a String
```
import "io.fx", "types.fx";

using io::output::print;
using types::string;

def main() -> int
{
    string s();
    s = "Testing!";
    len = (sizeof(s) / 8) - 1;
    print(s[len:0]);
    return 0;
};
```
Result:  
`!gnitseT`

To reverse an array, which is what a string is, we do `[len - 1:0]`.
If the first parameter is larger than the second, it means we're traversing the array in descending order.

- **Why do we subtract 1 from the length of the string?**  
Computers count starting at 0, meaning 9 is the 10th number when computers count. If my string length is 10, that means the last element is at position 9. Position 10 is outside of the array, and as far as the computer is concerned, position 10 is undefined. It's like saying:  
**[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]** 10  
You can do this, but it may result in a crash or undefined behavior.  
This is why we must always be aware of our data types, sizes, and array lengths.

#### f4.3 The `sizeof()` Keyword
Characters are one byte in size. Strings are an array of bytes, interpreted as characters.  
If I have 40 characters, that's 40 bytes.  
`sizeof()` returns the size of something in bits, not bytes.  
This means we must be aware of the bit length of our types.
```
import "io.fx", "types.fx";

using io::output::print, io::input::input;
using types::string;

def main() -> int
{
    string s();
    s = "Testing!";
    len = sizeof(s) / 8;
    print(f"The size of s is {len} bytes long.");
    return 0;
};
```
Result:  
`The size of s is 8 bytes long.`

Why didn't we subtract 1 from `len` this time?  
Because we're not using `len` to index the string.  
Why did we divide by 8? Because if the size of a byte is 8 bits, and our data length is 80 bits, that means there are 10 bytes.

#### f4.4 Constant Values
Sometimes we want to make sure there's no possible way a value can change.  
We do that by using the `const` keyword, like so:
```
const int myAge = 21;  // Forever 21!
```
If we try to change the value of `myAge` we will get a runtime error. Example:
```
const bool authorized = false;

def main() -> int
{
    if (!authorized)    // false == false, therefore true
    {
        authorized = true;  // Runtime error.
    };
    return 0;
};
```
---

## 5 - `data` and `struct`
Remember that `data` keyword from a few segments ago? Here's what it looks like:
```
unsigned data{32} as u32;
```
This new `u32` type is unsigned, and 32 bits wide.  
`data` is used to create new data types. These types are primitives, and are not functional.  
We'll expand more about `data` after you learn about structures.

- **What exactly is a `struct`?**  
"struct" is short for structure. In other OOP languages, structs can be functional. In Flux, this is not the case. Structs are strictly data-only containers, bringing us back to the land of pure data structures.

#### f5.1 Primitive Data Structures in Flux
```
import "io.fx", "types.fx";

using io::output::print, types::string;

struct Point
{
    float x, y, z;
};

def main() -> int
{
    sizeitems = sizeof(Point) / sizeof(float);
    sizebytes = (sizeof(Point) / sizeof(float)) * (sizeof(float) / 8);
    print(f"The size of the Point structure in bytes is {sizebytes}.");
    print(f"The size of the Point structure is {sizeitems} items.");
    return 0;
};
```
Result:  
```
The size of the Point structure in bytes is 24.
The size of the Point structure is 3 items.
```

Here we have a basic structure representing 3D point. We create 3 floats, `x`,`y`, and `z`.  
You do not need to initialize or create an instance of a struct to yield information about it.  
Struct sizes cannot be modified, meaning once we declare the struct we cannot add new members to it.

#### f5.2 Calculating the distance between two 3D points
```
import "io.fx", "types.fx";

using io::output::print, types::string;

struct Point
{
    float x, y, z;
};

def sqrt(float x) -> float
{
    return x ^ 0.5;
};

def distance(Point a, Point b) -> float
{
    return sqrt( ((b.x - a.x) ^ 2) + ((b.y - a.y) ^ 2) + ((b.z - a.z) ^ 2) );
};

def main() -> int
{
    Point p1 = {x = 4.1, y = 5.05, z = -3.9};
    Point p2 = {x = 10, y = -7.33, z = 2.12};

    float dist = distance(p1, p2);
    
    print(f"The distance between p1 and p2 is {dist}");
    return 0;
};
```
Result:  
`The distance between p1 and p2 is 14.977142584618734`

Here we take `Point` and *instance* (*create*) two independent copies of it called `p1` and `p2`. Whenever we refer to an instance of something, we are talking about an independent copy that has the same attributes as the `struct` or `object` it was made from. Objects are too advanced yet, so let's continue with structures.

- **Why can't structures have new members added to them?**  
This has to do with how programs compile. In other languages, structs have a lot of functionality which makes them very similar to classes with some key changes. However, structs having functionality requires the compiler to generate **virtual call tables** or `vtables` for them. This increases complexity for the resulting executable. Flux's goal is to create fast, small executables; to do this, we made structures non-flexible data-only containers.

#### f5.3 Modelling a File Format Header with `struct`
For this example we will be modeling the [Bitmap File Format](https://www.ece.ualberta.ca/~elliott/ee552/studentAppNotes/2003_w/misc/bmp_file_format/bmp_file_format.htm).
##### f5.3.1
<p align="center">
<img src="https://upload.wikimedia.org/wikipedia/commons/7/75/BMPfileFormat.svg">
</p>

Using this schematic we will capture the header of a `.bmp` image but not the color table.  
```
import "types.fx", "io.fx", "fio.fx";

using fio::File, fio::input::open;
using io::output::print;
using types::string;

struct Header
{
    unsigned data{16} sig;  // Not a type declaration, sig is a variable of this type
    unsigned data{32} filesize, reserved, dataoffset;  // Structured in the order they appear
};

struct InfoHeader
{
    unsigned data{32} size, width, height;
    unsigned data{16} planes, bitsperpixel;
    unsigned data{32} compression, imagesize, xpixelsperm, ypixelsperm, colorsused, importantcolors;
};

struct BMP
{
    Header header;
    InfoHeader infoheader;
    // If we create this structure after opening the file, we can get the colorspace properly.
    // We would do this in main() after reading the file into the buffer.
};

def main() -> int
{
    File bmpfile = open("image.bmp", "r");
    bmpfile.seek(0);
    unsigned data{8}[sizeof(bmpfile.bytes)] buffer = bmpfile.readall();
    bmpfile.close()

    // We now have the file in the buffer. Time to capture that data.
    Header hdata;
    int hdlen = sizeof(hdata) / ( 2 + (4 * 3) );  // 2 bytes + 4x3 bytes
    InfoHeader ihdata;
    int ihdlen = sizeof(ihdata) / ( (4 * 9) + (2 * 2) ); // 9x4 bytes + 2x2 bytes

    hdata = (Header)buffer[0:hdlen - 1];            // Capture header
    ihdata = (InfoHeader)buffer[hdlen:ihdlen - 1];  // Capture info header
    print((char[2])hdata.sig)
    return 0;
};
```
Result:  
`BM`

Alternatively, on the lines we capture the data into our structs, if we had all the information about the file such as the file size, image size, etc, we could dynamically create the BMP struct, and capture like so:
```
BMP bitmap;
bitmap = (BMP)buffer;
```
Since the BMP struct would 100% reflect the file's dimensions, it perfectly captures all data into the members of the struct accordingly.

- **(What) is this? What's (that)thing there?**  
What you're seeing is called **cast notation**. Casting converts one type to another.  
In this case, casting data to a structure results in the data aligning to the struct - this is also known as **data structuring**.

#### f5.4 Restructuring
```
import "types.fx", "io.fx";

using io::output::print;
using types::string;

struct Values32
{
    i32 a, b, c, d;
};

struct Values16
{
    i16 a, b, c, d, e, f, g, h;
}

def main() -> int
{
    Values32 v1 = {a=10, b=20, c=30, d=40};
    
    Values16 v2 = (Values16)v1;

    print(f"v2.a = {v2.a}\n");
    print(f"v2.b = {v2.b});
    return 0;
};
```
Result:  
```
0
10
```

- **Why does v2.a equal 0?**  
We converted a struct that contained 32 bit integers into a struct of 16 bit integers.  
Here's what the value 10 looks like in 32 bits:

<table align="center">
  <tr>
    <th>(2,147,483,648)</th>
    <th>(1,073,741,824)</th>
    <th>(536,870,912)</th>
    <th>(268,435,456)</th>
    <th>(134,217,728)</th>
    <th>(67,108,864)</th>
    <th>(33,554,432)</th>
    <th>(16,777,216)</th>
    <th>(8,388,608)</th>
    <th>(4,194,304)</th>
    <th>(2,097,152)</th>
    <th>(1,048,576)</th>
    <th>(524,288)</th>
    <th>(262,144)</th>
    <th>(131,072)</th>
    <th>(65,536)</th>
    <th>(32,769)</th>
    <th>(16,384)</th>
    <th>(8,192)</th>
    <th>(4,096)</th>
    <th>(2,048)</th>
    <th>(1,024)</th>
    <th>(512)</th>
    <th>(256)</th>
    <th>(128)</th>
    <th>(64)</th>
    <th>(32)</th>
    <th>(16)</th>
    <th>(8)</th>
    <th>(4)</th>
    <th>(2)</th>
    <th>(1)</th>
  </tr>
  <tr>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>0</td>
    <td>1</td>
    <td>0</td>
    <td>1</td>
    <td>0</td>
  </tr>
</table>

What we're doing is splitting one 32 bit integer into two 16 bit integers.  
The first 16 bits of the array above are 0. The last are `0000000000001010`.  
So `v2.a` which is `i16` type (16 bits wide) gets all zeros, `v2.b` gets the remainder `0000000000001010`.

Say we use `Values16` to create a new instance called `v3`, and we swap the order of `a` and `b`. Then we cast it to a new instance `v4` which is type `Values32`.
```
import "types.fx", "io.fx";

using io::output::print;
using types::string;

struct Values32
{
    i32 a, b, c, d;
};

struct Values16
{
    i16 a, b, c, d, e, f, g, h;
}

def main() -> int
{
    Values32 v1 = {a=10, b=20, c=30, d=40};
    Values16 v2 = (Values16)v1;    // Restructure
    Values16 v3 = {a=v2.b, b=v2.a, c=v2.c, d=v2.d, e=v2.e, f=v2.f, g=v2.g, h=v2.h};
    Values32 v4 = (Values32)v3;    // Restructure

    print(f"v4.a = {v4.a}\n");
    return 0;
};
```
Result:  
`327680`

- **Why is the value so much larger than 10?**  
We swapped the order of the bits, essentially rotating them left 16 spaces.

## 6 - Warming Up
Logical flow can be handled two ways. The slow way, or the fast way.  
What's the difference?

- `if` statements are extremely slow.  
Every condition of an `if/elif/else` chain needs to be evaluated. If there are 10 conditions, that requires 10 additional evaluations which consume CPU cycles. If you have some heavy duty algorithm, you should opt for `switch` statements.

- `switch` statements are extremely fast.  
Every condition is known at compile time, so a more optimized jump table can be created.

#### f6.1 A little game.
```
import "types.fx", "io.fx", "random.fx";

using io::input::input, io::output::print;
using types::string;
using random::rand_int;

def main() -> int
{
    string s();
    int value;
    int rand;

    while (true)
    {
        s = input("Enter a value from 0-10: ");
        value = s.as_int();
        rand = rand_int(0,10);

        switch (value)
        {
            case (rand)
            {
                print("You win! Keep going!");
                continue;
            }
            default
            {
                print(f"You lose! The value was {rand}. Game over.");
                break;
            };
        };
    };
    return 0;
};
```
Result:  
```
Enter a value from 0-10: 7
You win! Keep going!
Enter a value from 0-10: 9
You lose! The value was 2. Game over.
```

Here we're introduced to 2 new keywords, `switch` and `while`.

`while` is a keyword that means while the condition is true, execute this block repeatedly.  
`break` exits the loop immediately. You may use `break` in any loop.  
`continue` goes to the next iteration (cycle) of the loop.

`switch` statements have 2 sub-keywords, called `case` and `default`.  
All switches **must** have a default, the default branch executes when no cases match the condition.

#### f6.2 `for`, `do`, `while`, and `do`-`while` loops
We can do loops a few different ways. Loops repeat themselves until a condition is met.  

`while` is like an `if` statement + a loop, they continue to loop while the condition is true.  
A `while` loop will check the condition first, and if it's true it will execute the block.

A `do`-`while` loop will execute its block before checking the condition. Here's an example of the difference.

#### f6.2.1 `do`-`while`
```
import "types.fx", "io.fx";

using types::string;
using io::output::print;

def main() -> int
{
    int start = 0;
    int end = 3;

    do
    {
        if (start >= end)
        {
            print("You fell off the cliff!");
            break;
        };
        print("You take a step.")
        start++;
    }
    while (start < end);

    return 0;
};
```
Result:
```
You take a step.
You take a step.
You take a step.
You fell off the cliff!
```

#### f6.2.2 `while` without `do`
```
import "types.fx", "io.fx";

using types::string;
using io::output::print;

def main() -> int
{
    int start = 0;
    int end = 3;

    while (start < end)
    {
        if (start >= end)
        {
            print("You fell off the cliff!");
            break;
        };
        print("You take a step.")
        start++;
    };

    return 0;
};
```
Result:
```
You take a step.
You take a step.
You take a step.
```

As you can see, there's a difference in the output of these two programs.  
In figure 6.2.1 we go past the end and fall off the imaginary cliff.  
In figure 6.2.2 we make sure we're not at the end before taking a step.

#### f6.3.1 `for` Style 1: initializer, condition, expression
```
import "types.fx", "io.fx";

using types::string;
using io::output::print;

def main() -> int
{
    for (int counter = 0; counter < 3; counter++)
    {
        print(f"All you're base are belong to us.\n");
    };
    return 0;
};
```
Result:
```
All you're base are belong to us.
All you're base are belong to us.
All you're base are belong to us.
```

#### f6.3.2 `for` Style 2: element in array
```
import "types.fx", "io.fx";

using types::string;
using io::output::print;

def main() -> int
{
    int[] int_array = [11, 22, 33, 44, 55, 66, 77, 88, 99, 00];

    for (x in int_array)
    {
        print(f"{x}\n");
    };
    return 0;
};
```
Result:
```
11
22
33
44
55
66
77
88
99
0
```