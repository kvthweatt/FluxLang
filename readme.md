# Flux
### *A general purpose, statically typed, broadly mid-level, object-oriented compiled programming language for easy control over data.*

<p align="center">
    <img src="https://github.com/kvthweatt/FluxLang/blob/main/resources/logo_cropped.jpg" width="300" height="150">
</p>

## What is Flux?

Flux is a new language that combines the performance and power of C with the readability of Python. It is neither C or Python, nor a true C derivative. It's for everyone, designed for first-class data manipulation, and a growing standard library.

**Characteristics:**
- Manual memory management
- Compiler that does not fight you
- First class data control features
- Consistent grammar and syntax constructs throughout
- Rich operator set with distinct bitwise set
- Everything stack allocated unless otherwise specified
- Everything is zero initialized unless otherwise specified
- Custom infix operator support
- Templates without SFINAE
- Opt-in ownership without a borrow checker


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
- Full compile-time programming capabilities* (coming soon)


## Ideal Use Cases

Flux is well-suited for:
- **Embedded systems** - Direct hardware register access
- **Network protocols** - Zero-copy packet parsing
- **File format handling** - Binary data interpretation
- **Game engines** - Memory-efficient entity systems
- **Device drivers** - Memory-mapped I/O
- **Performance-critical code** - When you need C-level control

## Current Status

Flux is in active development. The language specification is complete, but implementation is ongoing.  
The standard library is the current focus.

**What exists:**
- [Complete language specification](https://github.com/kvthweatt/FluxLang/blob/main/docs/Specs/language_specification.md)
- [Keyword Reference](https://github.com/kvthweatt/FluxLang/blob/main/docs/keyword_reference.md)
- A Flux [style guide](https://github.com/kvthweatt/FluxLang/blob/main/docs/style_guide.md)
- Tutorials for [beginner](https://github.com/kvthweatt/FluxLang/blob/main/docs/style_guide.md) and [adept](https://github.com/kvthweatt/FluxLang/blob/main/docs/learn_flux_adept.md) programmers
- Clear syntax and semantics

**What's being built:**
- Compiler Implementation ✅
- Standard library (In-progress)
- Build tooling
- IDE (In-progress)
- Package manager (In-progress)
- LSP (In-progress)

## Getting Involved

- **Discord:** [Join the Flux community](https://discord.gg/wVAm2E6ymf)
- **Contribute:** The project welcomes contributors
- **Feedback:** Share your thoughts on language design

## Learning Resources

- **[Language Specification](docs/Specs/language_specification.md)** - Complete language reference  
- **[Getting Started Guide](docs/learn_flux_intro.md)** - Tutorial for new users  
- **[Examples](examples/)** - Real-world Flux programs  
- **[Windows Setup Guide](docs/SetupGuides/windows_setup_guide.md)**  
- **[Linux Setup Guide](docs/SetupGuides/linux_setup_guide.md)** 


## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=kvthweatt/FluxLang&type=date&legend=top-left)](https://www.star-history.com/#kvthweatt/FluxLang&type=date&legend=top-left)


## Example: Complete Program

```
#import "standard.fx";

struct Packet
{
    unsigned data{8} type;
    unsigned data{16} length;
    unsigned data{32} timestamp;
};

def main() -> int
{
    byte[7] bytes = [0x01, 0x00, 0x20, 0x5F, 0x12, 0x34, 0x56];
    Packet pkt = Packet from bytes;
    
    print("Type: \0");
    print(pkt.type); print();
    print("Length: \0");
    print(pkt.length); print();
    print("Time: \0");
    print(pkt.timestamp); print();
    
    return 0;
};
```

**Note:** Flux is a systems programming language that assumes you understand memory management and low-level programming concepts. If you're new to systems programming, work through the tutorial documentation carefully.

## 🤝 **Contributing**

Flux is actively developed and approaching self-hosting.  

**Current Status:** Working compiler, real programs running.  
There are still some small compiler issues here and there.

## ⚖️ **License**

Copyright (C) 2024 Karac Von Thweatt. All rights reserved.