# Flux

<p align="center">
    <img src="https://github.com/kvthweatt/FluxLang/blob/main/resources/logo_cropped.jpg" width="300" height="150">
</p>

Flux is a broadly mid-level systems OOP language.  
Designed based on the question: "What if there was a language made which benefits from all we know now?"  
[Full Specification](https://github.com/kvthweatt/FluxLang/blob/main/docs/lang_spec_full.md)  
[Intro to Flux](https://github.com/kvthweatt/FluxLang/blob/main/docs/learn_flux_intro.md)

## Why Flux Stands Out  
### 1. Unparalleled Data Control  
Flux gives you direct, zero-overhead access, manual memory with RAII.  
Create variable bit-width custom primitive data types.  
No need to perform gymnastics for serialization/deserialization, structures are data-only primitives so they're already serialized as they are.

### 2. File Format Magic  
Flux makes working with binary formats trivial by enforcing data-only structs.  
Serialization and deserialization become native operations.
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
    // ...
};

def main() -> int
{
    File bmpfile = open("image.bmp", "r");
    bmpfile.seek(0);
    byte[bmpfile.length] buffer = bmpfile.readall();
    bmpfile.close();

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
- Compile-time execution (`compt` blocks) for zero-cost abstractions.  
```
compt
{
    if (def(MY_MACRO))
    {
        // ... do things
    };
};
```
- Ownership system (`~` syntax) for memory safety where you need it.  
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
- Trait system for objects.
```
trait Drawable
{
    def draw() -> void;
};

Drawable object Square
{
    def __init() -> this { return this; };
    def __exit() -> void { return void; };

    def draw() -> void
    {
        // Implementation
        return void;
    };
};
```
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
int[] evens = [x for (int x in 1..20) if (x % 2 == 0)];

// Low-level
volatile asm
{
    mov eax, 1
    mov ebx, 0
    int 0x80
};
```

### 6. Hello World
```
import "standard.fx";

def main() -> int
{
    print("Hello World!");
    return 0;
};
```

### Restructuring
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
v2.a = 0
v2.b = 10
```

### Why Developers Love Flux
- No hidden costs: What you write is what executes.  
- True data freedom: Reinterpret memory safely and efficiently.  
- Readable systems code: Python-like syntax for low-level work.  
- Compile-time power: Execute code during compilation for optimizations.

### Join the Flux Revolution
Flux is currently in active development. We're building:  
- A compiler with full LLVM backend support.  
- Another, bootstrapped compiler, entirely written in Flux.  
- A standard library for systems programming and general purpose programming tasks.  
- Tooling for embedded and high-performance applications.


## Compiling Flux

We are still working on Windows & Mac compilation instructions.

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
```
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
