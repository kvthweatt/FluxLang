# Flux
### *A general purpose, statically typed, broadly mid-level, object-oriented systems programming language for precise control over binary data.*

<p align="center">
    <img src="https://github.com/kvthweatt/FluxLang/blob/main/resources/logo_cropped.jpg" width="300" height="150">
</p>

## What is Flux?

Flux is a compiled systems language that combines C-like performance with Python-inspired syntax. It's for everyone, designed to have all the bells and whistles you could want in one place. Gone now are the days of writing your performance critical code in one language and calling it from another.

**Characteristics:**
- Manual memory management
- Compiler that does not fight you
- First class data control features
- Consistent grammar and syntax constructs throughout


## Core Features

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
Macro definitions must have a value, 0 included. Example:
```
// Defined:
#def MY_MACRO 1;     // Considered defined.
#def NOT_DEFINED 0;  // Considered undefined.

#ifdef NOT_DEFINED   // False
#ifndef MY_MACRO     // False
```

### Bit-Precise Data Types

Define types with exact bit widths and alignment:

```flux
unsigned data{1} as bit;           // 1-bit type
unsigned data{13:16} as custom;    // 13 bits, 16-bit aligned
unsigned data{32} as u32;          // Standard 32-bit unsigned
```

### Bit-Level Field Access

Extract individual bits from bytes as named fields:

```flux
struct Flags {
    unsigned data{1} enabled;
    unsigned data{1} error;
    unsigned data{1} ready;
    unsigned data{1} busy;
    unsigned data{4} mode;
};

byte status = 0b10110001;
Flags f = (Flags)status;
if (f.enabled && !f.error) { /* ... */ };
```

### Compile-Time Execution

Run actual Flux code during compilation:

```flux
compt {
    def MY_CONSTANT 42;
    
    if (!def(DEBUG_MODE)) {
        global def DEBUG_MODE true;  // MUST use {} blocks, even for single line side-effects.
    };
};
```

## Language Basics
**Functions:**
```flux
def add(int x, int y) -> int {
    return x + y;
};
```

**Function Prototypes:**
```
// Single def, multiple signatures.
def foo() -> void,
    foo() -> int,     // Can declare multiple signatures on one line.
    foo() -> float;   // Identical names are recommended.

def abc() -> void,
    jki() -> void,    // Even with different names!
    xyz() -> void;    // Different names are not recommended.
```

**Universal External FFI:**  
Flux has an operator called the "no mangle" operator, `!!`, which instructs the compiler to not mangle the function name to its right. This only applies to function names.
```
extern def stcmp(byte*,byte*)->int;  // Single-line

extern                               // Multi-line
{
    def foo() -> void;
    def zad() -> void;
};

// !! cascades when performing multi-signature def
extern
{
    def !!
        foo() -> void,
        bar() -> void,
        baz() -> void;     // All safe from name mangling
};
```

**Objects (OOP):**
```
object Vector3 {
    float x, y, z;
    
    def __init(float x, float y, float z) -> this {
        this.x = x; this.y = y; this.z = z;
        return this;
    };
    
    def __exit() -> void {};   // Explicit returns for void functions unnecessary.
    
    def length() -> float {
        return sqrt(this.x^2 + this.y^2 + this.z^2);
    };
};
```

**Structs (Data-only):**
```
struct Point {
    float x, y, z;
};
```

**Memory Management:**
```flux
int* ptr;                // Allocate
*ptr = 42;
(void)ptr;               // Deallocate explicitly
```
Skip declaring a variable:
```
int* px = @55;           // Allocate 55 and get its address. 
```
Round trip (pointer, to int, and back):
```
int  x   = 5;
int* px  = @x;
int  pxk = px;      // Address as integer
int* py  = (@)pxk;  // Address as pointer
```
This can segfault or crash if your default pointer width is 64 bits.  
The safe way to do this round trip with 64 bit pointers is this:  
```
int  x   = 5;
int* px  = @x;
u64  pxk = px;      // Address as integer, pxk is big enough to hold a 64 bit pointer
int* py  = (@)pxk;  // Address as pointer, pointer will be 64 bits and can accept pxk
```

Flux treats all data the same. It's all just numbers.

**Ownership (Optional):**
```flux
def make() -> int {
    int ~x = 42; // Mark with "tie" operator ~
    return ~x;   // Explicit transfer
};
```

## Design Philosophy

Flux follows a "high-trust" model:
- The language provides powerful tools
- The programmer is responsible for using them correctly
- Explicit is better than implicit
- Performance and control over safety guarantees

This means:
- Manual memory management (no garbage collection)
- No borrow checker (you manage lifetimes)
- Direct hardware access when needed
- Full compile-time programming capabilities

## Ideal Use Cases

Flux is well-suited for:
- **Embedded systems** - Direct hardware register access
- **Network protocols** - Zero-copy packet parsing
- **File format handling** - Binary data interpretation
- **Game engines** - Memory-efficient entity systems
- **Device drivers** - Memory-mapped I/O
- **Performance-critical code** - When you need C-level control

Flux may not be the best choice for:
- Applications where memory safety is critical
- Projects requiring a mature ecosystem
- Teams new to systems programming
- Rapid prototyping of business logic

## Current Status

Flux is in active development. The language specification is complete, but implementation is ongoing.

**What exists:**
- Complete language specification (reduced and full versions)
- Comprehensive tutorial documentation
- Clear syntax and semantics

**What's being built:**
- Compiler implementation
- Standard library
- Build tooling
- Package manager

## Getting Involved

- **Discord:** [Join the Flux community](https://discord.gg/RAHjbYuNUc)
- **Contribute:** The project welcomes contributors
- **Feedback:** Share your thoughts on language design

## Learning Resources

- **Intro to Programming with Flux** - Start here if new to programming
- **Reduced Specification** - Core language features
- **Full Specification** - Complete language reference

## Example: Complete Program

```flux
import "standard.fx";

using standard::io;

struct Packet {
    unsigned data{8} type;
    unsigned data{16} length;
    unsigned data{32} timestamp;
};

def main() -> int {
    byte[] data = [0x01, 0x00, 0x20, 0x5F, 0x12, 0x34, 0x56];
    Packet pkt = (Packet)data;
    
    print(f"Type: {pkt.type}");
    print(f"Length: {pkt.length}");
    print(f"Time: {pkt.timestamp}");
    
    return 0;
};
```

**Note:** Flux is a systems programming language that assumes you understand memory management and low-level programming concepts. If you're new to systems programming, work through the tutorial documentation carefully.

## 📚 **Learn More**

- **[Language Specification](docs/Specs/lang_spec_full.md)** - Complete language reference
- **[Getting Started Guide](docs/learn_flux_intro.md)** - Tutorial for new users  
- **[Examples](examples/)** - Real-world Flux programs
- **[Windows Setup Guide](docs/SetupGuides/windows_setup_guide.md)**
- **[Linux Setup Guide](docs/SetupGuides/linux_setup_guide.md)**

## 🤝 **Contributing**

Flux is actively developed and approaching self-hosting. We're building the future of systems programming.

**Current Status:** 100% of reduced specification complete, working compiler, real programs running.  
Bug fixing and refactoring are currently the names of the games. There are still some small issues here and there.

## ⚖️ **License**

Copyright (C) 2024 Karac Von Thweatt. All rights reserved.