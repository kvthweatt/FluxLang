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

## Fundamentals  
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

<table>
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

<table>
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
Integers (`int`) types in Flux are 32 bits by default. 32 divided by 8 equals 4, so an `int`  is 4 bytes long. Let's start at address 2 and read an integer, we get `0xBEEFDEAD`.  
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

#### Code:
```
def main() -> int
{
    return 0;
};
```
This program does nothing. It will start and immediately stop. If you compile and run this, you will think something is broken, or did not work. This is actually expected behavior, we shouldn't see anything because the program didn't do anything.

This is what you could call the skeleton of a Flux program. Any program you compile into an executable must have a main function defined in **global scope**.

- **What are *global* and *scope*? What is *global scope*?**  
A global is something that can be referred to anywhere in the program. It exists so long as it isn't destroyed or invalidated in some way. Scope is like visibility, imagine it like a one-way mirror. I can look one way, but not the other. Here's an example:
#### Code
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
#### Code
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