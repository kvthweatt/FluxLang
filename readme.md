# Flux

<p align="center">
    <img src="https://github.com/kvthweatt/FluxLang/blob/main/resources/logo_cropped.jpg" width="300" height="150">
</p>

Flux is a systems programming language that combines the low-level control of C with Python-like readability, designed for performance-critical applications where data manipulation is key.

## Why Flux Stands Out  
### 1. Unparalleled Data Control  
Flux gives you direct, zero-overhead access to memory with powerful features like:  
- Bit-precise data types: Create custom types of any width (e.g., unsigned data{13:16} for 13-bit values with 16-bit alignment).  
- True serialization/deserialization: Cast structs to raw bits and back with no marshalling overhead.  
- Memory model you control: Explicit memory management with RAII support.
```
// Model hardware registers precisely
struct GPIORegisters {
    unsigned data{32} control;
    unsigned data{32} status;
    unsigned data{64} buffer;
};

// Direct memory mapping
volatile const GPIORegisters* GPIO = @0x40000000;
```

### 2. File Format Magic  
Flux makes working with binary formats trivial by mapping structs directly to file layouts:
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
    unsigned data{8}[sizeof(bmpfile.content)] buffer = bmpfile.readall();
    bmpfile.close()

    // We now have the file in the buffer. Time to capture that data.
    Header hdata;
    int hdlen = sizeof(hdata) / ( 2 + (4 * 3) );  // 2 bytes + 4x3 bytes
    InfoHeader ihdata;
    int ihdlen = sizeof(ihdata) / ( (4 * 9) + (2 * 2) ); // 9x4 bytes + 2x2 bytes

    hdata = (Header)buffer[0:hdlen - 1];            // Capture header
    ihdata = (InfoHeader)buffer[hdlen:ihdlen - 1];  // Capture info header
    print((char[2])hdata.sig);
    return 0;
};
```
Result:  
`BM`

### 3. Modern Features with Bare-Metal Performance  
- Python-inspired syntax with C++-like power.  
- Compile-time execution (compt blocks) for zero-cost abstractions.  
- Ownership system (~ syntax) for memory safety where you need it.  
- Full operator overloading with contracts for safe arithmetic.
```
// Smart pointer with move semantics
operator (unique_ptr<T> a, unique_ptr<T> b)[=] -> unique_ptr<T> {
    a.ptr = b.ptr;    // Transfer ownership
    (void)b.ptr;      // Clean up
    return a;
};
```

### 5. Dual-Personality Language  
Flux is ready for your needs - write high-level code when you want, drop to bare metal when you need:
```
// High-level
int[] evens = [x for (x in 1..20) if (x % 2 == 0)];

// Low-level
volatile asm {
    mov eax, 1
    mov ebx, 0
    int 0x80
};
```

### 6. Hello World
```
import "standard.fx";

def main() -> int {
    print("Hello World!");
    return 0;
};
```

### Why Developers Love Flux
- No hidden costs: What you write is what executes

- True data freedom: Reinterpret memory safely and efficiently

- Readable systems code: Python-like syntax for low-level work

- Compile-time power: Execute code during compilation for optimizations

### Join the Flux Revolution
Flux is currently in active development. We're building:  
- A compiler with full LLVM backend support.  
- Another, bootstrapped compiler, entirely written in Flux.  
- A standard library for systems programming and general purpose programming tasks.  
- Tooling for embedded and high-performance applications.


## Compiling Flux

**Linux instructions:**  
You will need:

- LLVM Toolchain

```bash
sudo apt install llvm-14 clang-14 lld-14
```

- Assembler & Linker

```bash
sudo apt install binutils gcc g++ make     # GNU toolchain
```

- Python Packages

```bash
pip install llvmlite==0.41.0 dataclasses
```

```bash
sudo apt install binutils gcc g++ make     # GNU toolchain
```

- Python Packages

```bash
pip install llvmlite==0.41.0 dataclasses

```bash
pip install llvmlite==0.41.0 dataclasses
```

_Verify your installation:_

```bash
python3 --version        # Should show 3.8+
llc --version            # Should show LLVM 14.x
as --version             # Should show GNU assembler
gcc --version            # Should show GCC
```

**_Compilation:_**

1. Compile Flux to LLVM IR  
   `python3 fc.py input.fx > output.ll`

2. Compile LLVM IR to assembly  
   `llc output.ll -o output.s`

3. Assemble to object file  
   `as output.s -o output.o`

4. Link executable  
   `gcc output.o -o program`

5. Run
   `./program`
