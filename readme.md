# Flux
### *A general purpose, statically typed, object-oriented systems programming language.*

<p align="center">
    <img src="https://github.com/kvthweatt/FluxLang/blob/main/resources/logo_cropped.jpg" width="300" height="150">
</p>

**Flux is the systems programming language designed to answer one question: "What if we built a language today, knowing everything we know now, with zero compromises and without relying on legacy?"**  
Flux also does not rely on the C ABI, going entirely independent.

### **Parsing binary data in C++**
```
// C++ - Parse BMP header (20+ lines of manual parsing)
BMP parseBMP(uint8_t* data) {
    BMP result;
    result.sig = *(uint16_t*)data;
    result.filesize = *(uint32_t*)(data + 2);
    // ... error-prone, slow, lots of code
    return result;
}
```
### **Parsing binary data in Flux**
```
struct BMP {
    Header header;
    InfoHeader info;
};

// Minimal implementation
BMP bitmap = (BMP)file_data;
print((char[2])bitmap.header.sig);  // "BM"
```
**Result:** More coherent, simpler code.

## ⚡ **Features**

### **1. Custom Bit-Width Types**
```
unsigned data{13:16} as custom;     // 13-bit data, 16-bit aligned
signed data{24:32} as audio_sample; // Perfect 24-bit audio
volatile unsigned data{32} as gpio; // Hardware register mapping
```

### **2. First-Class Operators** 
```
// Custom operators that feel native
operator (u32 x, int n)[>>>] -> u32 {
    return (x >> n) | (x << (32 - n));  // Rotate right
};

// Templated with safety contracts
contract NonZero { assert(a != 0 && b != 0); };
operator<T>(T a, T b)[/] -> T : NonZero {
    return a / b;  // Safe division for any type
};

// Usage feels like language extensions
result = value >>> 8;
safe_result = dividend / divisor;  // Contract-checked
```
### **3. Compile-Time Execution**
```
compt {
    // Full Flux runtime in the compiler
    if (def(TARGET_ARM64)) {
        def CACHE_LINE_SIZE 128;
        unsigned data{8}[256] LOOKUP_TABLE = generate_optimized_arm();
    };
    
    // Pre-compute crypto tables, physics constants, etc.
    float[1024] SIN_TABLE = compute_sin_table();
};
```
Move arbitrary complexity from runtime to compile-time.

### **4. Memory Layout Mastery**
```
// Direct hardware programming
struct GPIORegisters {
    volatile unsigned data{32} control;
    volatile unsigned data{32} status;
};
GPIORegisters* gpio = @0x40000000;  // Zero abstraction
gpio.control = 0x1;
```

### **5. Inline Assembly**
```
volatile asm {
    movq $-11, %rcx
    call GetStdHandle
    movq %rax, %rcx
    movq $0, %rdx
} : : "r"(message), "r"(length) : "rax","rcx","memory";
```
**Note:** The assembly syntax currently used is Intel, this will be changed.

## 🏗️ **The Vision: Replace Everything**

### **Phase 1: Bootstrap** *(Months Away)*
- [x] Working compiler for reduced specification (Python → LLVM → executable) (Almost complete)
- [ ] Self-hosting Flux compiler  
- [ ] Direct assembly generation

### **Phase 2: Ecosystem** *(1-2 Years)
- [ ] Standard library for systems programming
- [ ] Developer tooling and IDE support

### **Phase 3: Total Revolution** *(3-5 Years)*
- [ ] Linux kernel rewrite in pure Flux
- [ ] Unified computing stack - no language fragmentation
- [ ] Performance revolution across all computing

**"The good replacement for C that Linus was waiting for."**

## 🚀 **Get Started**

### **Hello World**
```
import "standard.fx";

def main() -> int {
    print("Hello, World!");
    return 0;
};
```
### **Quick Setup**
# Install dependencies
`pip install llvmlite==0.41.0`

# Compile and run
```
python flux_compiler.py hello.fx
./hello
```
### **Try Something Amazing** (Nearing implementation)
```
// Load a bitmap image in one line
struct BMP { Header h; InfoHeader i; };
BMP image = (BMP)file_data;
print(f"Image: {image.i.width}x{image.i.height}");
```
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
