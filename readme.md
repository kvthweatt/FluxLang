# Flux
### *A general purpose, statically typed, broadly mid-level, object-oriented systems programming language for precise control over binary data.*

<p align="center">
    <img src="https://github.com/kvthweatt/FluxLang/blob/main/resources/logo_cropped.jpg" width="300" height="150">
</p>

## What is Flux?

Flux is a compiled systems language that combines C-like performance with Python-inspired syntax. It's designed for programmers who need direct memory control and bit-level precision without fighting complex abstractions.

**Key characteristics:**
- Manual memory management
- Explicit control over data layout
- Zero-cost binary data manipulation
- Compile-time execution capabilities
- Clean, readable syntax

```
// Single-line comments

///
Multi
line
comments
///
```

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
#def MY_MACRO 1;
#def NOT_DEFINED 0;

#ifdef NOT_DEFINED // False
#ifndef MY_MACRO   // False
```

### Bit-Precise Data Types

Define types with exact bit widths and alignment:

```flux
unsigned data{1} as bit;           // 1-bit type
unsigned data{13:16} as custom;    // 13 bits, 16-bit aligned
unsigned data{32} as u32;          // Standard 32-bit unsigned
```

### Zero-Copy Struct Casting

Map structs directly onto raw bytes without parsing:

```flux
struct Header {
    unsigned data{16} magic;
    unsigned data{32} filesize;
    unsigned data{32} offset;
};

byte[] buffer = file.readall();
Header header = (Header)buffer;
print(header.filesize);  // Direct access, no parsing
```
Struct specification can be read [here](https://github.com/kvthweatt/FluxLang/blob/main/docs/struct_specification.md).

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
if (f.enabled && !f.error) { /* ... */ }
```

### Compile-Time Execution

Run actual Flux code during compilation:

```flux
compt {
    def MY_CONSTANT 42;
    
    if (!def(DEBUG_MODE)) {
        global def DEBUG_MODE true;
    };
};
```

## Practical Examples

**Network Protocol Parsing:**
```flux
struct TCPHeader {
    unsigned data{16} src_port, dst_port;
    unsigned data{32} seq_num;
    unsigned data{4} data_offset;
    unsigned data{6} flags;
    unsigned data{16} window;
};

byte[] packet = recv();
TCPHeader tcp = (TCPHeader)packet;
```

**Hardware Register Access:**
```flux
struct GPIOControl {
    unsigned data{2} mode;
    unsigned data{1} pull_up;
    unsigned data{3} drive_strength;
    unsigned data{2} reserved;
};

volatile byte* gpio = @0x40000000;
GPIOControl ctrl = (GPIOControl)(*gpio);
ctrl.mode = 0b01;  // Set to output
*gpio = (byte)ctrl;
```

**Memory-Efficient Game Data:**
```flux
struct Entity {
    unsigned data{1} active;
    unsigned data{1} visible;
    unsigned data{2} team;
    unsigned data{4} type;
};
// 8 properties in 1 byte per entity
```

## Language Basics

**Functions:**
```flux
def add(int x, int y) -> int {
    return x + y;
};
```

**Objects (OOP):**
```flux
object Vector3 {
    float x, y, z;
    
    def __init(float x, float y, float z) -> this {
        this.x = x; this.y = y; this.z = z;
        return this;
    };
    
    def length() -> float {
        return sqrt(this.x^2 + this.y^2 + this.z^2);
    };
};
```

**Structs (Data-only):**
```flux
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

**Ownership (Optional):**
```flux
def ~make() -> ~int {
    int ~x = 42;
    return ~x;  // Explicit transfer
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

- **[Language Specification](docs/lang_spec_full.md)** - Complete language reference
- **[Getting Started Guide](docs/learn_flux_intro.md)** - Tutorial for new users  
- **[Examples](examples/)** - Real-world Flux programs
- **[Setup Guide](docs/windows_setup_guide.md)** - Platform-specific installation

## 🤝 **Contributing**

Flux is actively developed and approaching self-hosting. We're building the future of systems programming.

**Current Status:** ~95% of reduced specification complete, working compiler, real programs running.

## ⚖️ **License**

Copyright (C) 2024 Karac Von Thweatt. All rights reserved.

*Flux: Casual disregard for the impossible, one revolution at a time.*
