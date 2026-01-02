# Learn Flux for Experienced Programmers

This guide assumes you're already comfortable with systems programming concepts and have experience with languages like C++, Rust, or similar. Flux introduces some radically different paradigms that require rethinking how you approach low-level programming.

---

## Core Philosophy: Structs as Data Contracts

**The fundamental shift:** In most languages, structs are lightweight classes. In Flux, they're pure data layout specifications—pointer maps that exist at compile time to enable zero-cost data transformation.

### Struct Declarations vs Instances

```flux
struct Header {
    unsigned data{16} magic;
    unsigned data{32} offset;
};  // Declaration: creates a vtable describing bit layout

Header h1;  // Instance: raw data container, no vtable pointer, just bits
```

**Critical distinction:**
- **Declarations** allocate a virtual pointer table describing the memory layout
- **Instances** are pure data with zero overhead—no vtable pointers, no padding unless explicitly specified
- This enables `(StructType)rawBytes` to be a zero-cost operation

### Why This Matters

```flux
// Read arbitrary binary data
byte[] fileData = readFile("mystery.dat");

// Zero-cost reinterpretation
struct NetworkPacket {
    unsigned data{16} port;
    unsigned data{32} addr;
    unsigned data{64} timestamp;
};

NetworkPacket pkt = (NetworkPacket)fileData[0:14];  // Instant, no copying
```

The cast doesn't parse or validate—it's a compile-time assertion that "these bits match this layout." Runtime undefined behavior if they don't.

---

## The `data` Keyword: Custom Primitives

Flux has one primitive type: `data`. Everything else is built on it.

```flux
unsigned data{13:16} as weirdInt;  // 13-bit value, 16-bit aligned
signed data{7:8} as smallInt;      // 7-bit signed, byte-aligned

weirdInt x = 42;
byte[] raw = (byte[])x;  // Direct bit manipulation
```

**Implications:**
- You control exact bit widths and alignment
- No hidden padding or compiler decisions
- Perfect for hardware registers, network protocols, custom encodings

```flux
// Model a hardware register exactly
struct GPIO {
    unsigned data{1} pin0;
    unsigned data{1} pin1;
    unsigned data{6} reserved;
    unsigned data{8:32} control;  // 8 bits, 32-bit aligned
};

volatile GPIO* gpio = @0x40000000;  // Direct memory mapping
gpio.pin0 = 1;
```

---

## Pointers: Explicit Everything

```flux
int x = 10;
int* px = @x;      // @ is address-of
*px = 20;          // * dereferences

// Function pointers
def add(int a, int b) -> int { return a + b; };
int* fp(int, int) = @add;
int result = *fp(5, 3);  // Must dereference to call
```

**No implicit conversions.** Arrays don't decay to pointers. Functions require explicit `@` to take their address.

---

## Objects: Functional Containers

Unlike structs, objects can have methods and behavior.

```flux
object SmartPtr {
    int* ptr;
    
    def __init(int* p) -> this {
        this.ptr = p;
        return this;
    };
    
    def __exit() -> void {
        (void)this.ptr;  // Cast to void = free memory
        return void;
    };
    
    def get() -> int {
        return *this.ptr;
    };
};
```

**RAII is manual but explicit:**
- `__init()` must return `this`
- `__exit()` is destructor, called on scope exit or manually
- No automatic move semantics—you control ownership

### Object vs Struct: When to Use Which

```flux
// Use structs for pure data
struct Vec3 {
    float x, y, z;
};

// Use objects for behavior
object Vector {
    float x, y, z;
    
    def __init(float x, float y, float z) -> this {
        this.x = x; this.y = y; this.z = z;
        return this;
    };
    
    def __exit() -> void { return void; };
    
    def length() -> float {
        return sqrt(this.x^2 + this.y^2 + this.z^2);
    };
};
```

---

## Ownership with `~`

Flux has optional ownership tracking with the `~` prefix:

```flux
def ~allocate() -> ~int {
    int ~x = new int(42);
    return ~x;  // Explicit transfer
};

def main() -> int {
    ~int value = ~allocate();
    // value auto-freed at scope end via __exit()
    return 0;
};
```

**Enforcement:**
- Compiler tracks `~` variables
- Must explicitly move/destroy before scope end
- Escape hatch: `int* raw = (~)owned;` drops tracking

```flux
def ~oops() -> void {
    int ~x = new int(42);  // ERROR: ~x not moved/destroyed
};

def ~correct() -> void {
    int ~x = new int(42);
    (void)x;  // Explicitly freed
};
```

---

## Compile-Time Execution with `compt`

```flux
compt {
    def fibonacci(int n) -> int {
        if (n <= 1) return n;
        return fibonacci(n-1) + fibonacci(n-2);
    };
    
    global def FIB_10 fibonacci(10);  // Computed at compile time
};

int array[FIB_10];  // Array size known at compile time
```

**Key points:**
- Full Flux runtime available at compile time
- Can run arbitrary code, even infinite loops (compilation hangs)
- Use for metaprogramming, code generation, build-time validation

### Macros and Conditional Compilation

```flux
compt {
    if (!def(MY_CONSTANT)) {
        global def MY_CONSTANT 0x1000;
    };
};

// Operator macros
def MASK_SET `&;   // Define custom operators
gpio_reg MASK_SET 0x0F;  // Expands to: gpio_reg & 0x0F;
```

---

## Casting: The Universal Converter

Casting in Flux is **data reinterpretation**, not type conversion.

```flux
float pi = 3.14159;
int bits = (int)pi;  // Reinterpret float bits as int, not convert

// Casting to void = free memory
int* ptr = malloc(100);
(void)ptr;  // Memory freed immediately

// Struct casting
byte[14] raw = readBytes(14);
NetworkHeader hdr = (NetworkHeader)raw;  // Zero-cost reinterpretation
```

**Void casting vs assignment:**
```flux
int* ptr = malloc(100);

(void)ptr;       // Frees the memory immediately
ptr = void;      // Sets ptr to null, memory NOT freed

if (ptr is void) { /* null check */ };
```

---

## Contracts: Design by Contract

Contracts are assertion collections for preconditions and postconditions.

```flux
contract NonZero {
    assert(a != 0, "Parameter must be non-zero");
};

contract Positive {
    assert(result > 0);
};

def divide(int a, int b) -> int : NonZero {
    return a / b;
} : Positive;  // Pre-contract before body, post-contract after
```

**Strategic use:**
- Contracts have runtime overhead—use sparingly in hot paths
- In `compt` blocks, contract failures halt compilation
- Perfect for validating complex invariants

```flux
contract NotSame {
    assert(@a != @b, "Cannot assign to self");
};

contract ValidTransfer {
    assert(a.ptr != void);
    assert(b.ptr == void);
};

operator (UniquePtr a, UniquePtr b)[=] -> UniquePtr : NotSame {
    b.ptr = a.ptr;
    a.ptr = void;
    return b;
} : ValidTransfer;
```

---

## Memory Model: Manual and Explicit

```flux
// Stack allocation (automatic)
int x = 42;

// Heap allocation (manual)
int* heap = malloc(sizeof(int));
*heap = 42;
(void)heap;  // Must free explicitly

// Struct instances are always tightly packed
struct Data {
    byte a;
    int b;   // No padding between a and b
};

sizeof(Data);  // 40 bits (8 + 32), not 64
```

**Platform-specific allocation:**

```flux
if (def(WINDOWS)) {
    // Use HeapAlloc
} elif (def(LINUX)) {
    // Use mmap
};
```

---

## Inline Assembly

```flux
def syscall_write(int fd, void* buf, size_t len) -> size_t {
    size_t result;
    volatile asm {
        movq    $1, %rax        // syscall: write
        movq    fd, %rdi
        movq    buf, %rsi
        movq    len, %rdx
        syscall
        movq    %rax, result
    };
    return result;
};
```

**volatile asm:** Prevents compiler optimization of assembly blocks.

---

## Templates

```flux
def max<T>(T a, T b) -> T {
    return (a > b) ? a : b;
};

object Vector<T> {
    T* data;
    size_t len;
    
    def __init(size_t size) -> this {
        this.data = malloc(sizeof(T) * size);
        this.len = size;
        return this;
    };
    
    def __exit() -> void {
        (void)this.data;
        return void;
    };
};
```

---

## Operator Overloading

```flux
object Complex {
    float real, imag;
    
    def __init(float r, float i) -> this {
        this.real = r; this.imag = i;
        return this;
    };
    
    def __exit() -> void { return void; };
};

operator (Complex a, Complex b)[+] -> Complex {
    Complex result(a.real + b.real, a.imag + b.imag);
    return result;
};

// Custom operators
def CHAIN `<-;
operator (int a, int b)[<-] -> int {
    return a + b;
};

int x = 5 CHAIN 10;  // x = 15
```

---

## Array Comprehensions

```flux
// Basic
int[] squares = [x^2 for (int x in 1..10)];

// With condition
int[] evens = [x for (int x in 1..100) if (x % 2 == 0)];

// With transformation
float[] normalized = [(float)x / 100.0 for (int x in data)];
```

---

## Error Handling

```flux
object FileError {
    string msg;
    
    def __init(string m) -> this {
        this.msg = m;
        return this;
    };
    
    def __exit() -> void { return void; };
};

def readFile(string path) -> string {
    try {
        // Attempt to read
        if (file_not_found) {
            FileError err("File not found");
            throw(err);
        };
    }
    catch (FileError e) {
        print(e.msg);
    }
    catch (auto e) {
        // Catch all
    };
    
    return "";
};
```

---

## Traits: Interface Contracts

```flux
trait Drawable {
    def draw() -> void;
};

Drawable object Shape {
    def __init() -> this { return this; };
    def __exit() -> void { return void; };
    
    def draw() -> void {
        // Must implement or compilation fails
        print("Drawing shape");
        return;
    };
};
```

---

## FFI: C Interop

```flux
extern("C") {
    def malloc(ui64 size) -> void*;
    def free(void* ptr) -> void;
    def printf(string fmt, ...) -> int;
};

def main() -> int {
    void* mem = malloc(1024);
    printf("Allocated %d bytes\n", 1024);
    free(mem);
    return 0;
};
```

---

## Key Differences from Other Languages

### vs C++
- No implicit conversions or hidden overhead
- Structs are pure data, objects are for behavior
- Manual memory management, but with optional ownership tracking
- Compile-time execution is first-class

### vs Rust
- No borrow checker by default (use `~` for ownership tracking)
- More explicit pointer operations
- Structs as zero-cost data reinterpretation contracts
- `compt` blocks for compile-time metaprogramming

### vs C
- Type-safe bit manipulation with `data`
- Objects for encapsulation when needed
- Array comprehensions and modern conveniences
- Built-in contract system

---

## Common Patterns

### Smart Pointer

```flux
object UniquePtr<T> {
    T* ptr;
    
    def __init(T* p) -> this {
        this.ptr = p;
        return this;
    };
    
    def __exit() -> void {
        if (this.ptr != void) {
            (void)this.ptr;
        };
        return void;
    };
    
    def get() -> T* {
        return this.ptr;
    };
    
    def release() -> T* {
        T* temp = this.ptr;
        this.ptr = void;
        return temp;
    };
};
```

### Binary Protocol Parsing

```flux
struct PacketHeader {
    unsigned data{8} version;
    unsigned data{8} type;
    unsigned data{16} length;
    unsigned data{32} checksum;
};

def parsePacket(byte[] raw) -> PacketHeader {
    return (PacketHeader)raw[0:7];  // Zero-cost cast
};
```

### Compile-Time Configuration

```flux
compt {
    if (def(DEBUG)) {
        global def LOG_LEVEL 3;
    } else {
        global def LOG_LEVEL 0;
    };
};

def log(string msg) -> void {
    if (LOG_LEVEL > 0) {
        print(msg);
    };
};
```

---

## Performance Considerations

1. **Struct casts are free** - Use them liberally for data reinterpretation
2. **Contracts have overhead** - Use sparingly in hot paths
3. **Objects have vtables** - Structs don't, use structs for POD
4. **`compt` runs at compile time** - Move expensive computations there
5. **No implicit copies** - Everything is explicit

---

## Best Practices

1. Use structs for data layout specifications
2. Use objects for behavior and state management
3. Leverage `data` for exact bit control
4. Use `~` ownership for critical resources
5. Move invariant checks to `compt` blocks when possible
6. Be explicit with memory management
7. Use contracts to document preconditions/postconditions
8. Prefer compile-time computation with `compt`

---

## Resources

- Full language spec: `lang_spec_full.md`
- Beginner tutorial: `learn_flux_intro.md`
- Standard library: `import "standard.fx"`
- Flux Discord: https://discord.gg/RAHjbYuNUc