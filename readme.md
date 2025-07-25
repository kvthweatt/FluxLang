# Flux

**Note:** This language is still in development. A simplified version of Flux will be the first to release. It will not support templates, inheritance, `operator`, `contract`, `compt`, `trait`, macros, or the _full_ built-in operator set (all logical/bitwise operators). This is not a complete list of all that will not be supported. The reduced language specification can be found [here](https://github.com/kvthweatt/FluxLang/blob/main/docs/language_specification_simplified.md).

Flux is a systems programming language, visually resembling C++, Rust, and Python.

For the full specification, go [here](https://github.com/kvthweatt/FluxLang/blob/main/docs/lang_spec.md).

---

**Please note,** the following are example programs demonstrating what Flux looks like.  
The Standard Library is not implemented yet, so these programs will not compile.

#### Hello World

```
import "standard.fx";

def main() -> int
{
    print("Hello World!");
};
```

#### Basic string (Non-OOP):

```
unsigned data{8}[] as noopstr;
```

#### An example of [SHA256](https://github.com/kvthweatt/FluxLang/blob/main/examples/sha256.fx)

#### Full-specification Smart Pointers (includes use of templates, and operators)

```
object unique_ptr<T>
{
    T* ptr;

    def __init(T* p) -> this
    {
        this.ptr = p;
        return this;
    };

    def __exit() -> void
    {
        if (this.ptr == !void)
        {
            (void)this.ptr;  // Explicit deallocation, very readable
        };
    };
};

operator (unique_ptr<T> L, unique_ptr<T> R)[=] -> unique_ptr<T>
{
    if (L.ptr != void) { L.ptr = void; };
    L.ptr = R.ptr;  // Transfer ownership
    (void)R.ptr;    // Clean up
    return L;
};

int x = 5;

unique_ptr<int> a(@x);   // Alternatively `a(@new int);`
unique_ptr<int> b;

b = a;         // Ownership moved to b, a.ptr is now void

doThing(a);    // Use-after-free, a no longer exists.
```

---

## Implemented Keywords

This is a list of keywords which do have LLVM `codegen()` methods attached to their AST counterparts.

i. All primitive types: `int`, `float`, `bool`, `char`, `data`  
ii. `Type` types: `union`, `struct`, `object` - and instances of each  
iii. Namespaces  
iv. Functions  
v. Prototypes / Forward Declarations  
vi. `if/elif/else`
vii. `while`
viii. `asm`

By using assembly you can do system calls.  
`extern` for FFI is planned. Please be patient.

---

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
