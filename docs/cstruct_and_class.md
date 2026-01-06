# Flux: `cstruct` and `class` Specification

## Abstract

This document defines `cstruct` and `class`—two language constructs in Flux designed to maintain clear boundaries between:
1. **C ABI-compatible data layouts** (`cstruct`)
2. **Traditional object-oriented programming** (`class`)
3. **Flux's native zero-cost struct model** (`struct`)

The primary design goal is to preserve Flux's unique struct semantics while providing familiar OOP and C interop without compromising either.

---

## 1. `cstruct`: C ABI Compatibility Layer

### 1.1 Definition and Purpose

A `cstruct` is a data type that guarantees C ABI compatibility. It is designed exclusively for:
- Interoperation with C libraries
- Stable memory layouts across compiler versions
- Conventional pointer-based semantics
- No zero-cost reinterpretation

### 1.2 Syntax

```flux
cstruct Name {
    Type field1;
    Type field2;
    // ... more fields
};
```

### 1.3 Example

```flux
cstruct sockaddr_in {
    unsigned short sin_family;
    unsigned short sin_port;
    unsigned int   sin_addr;
    char           sin_zero[8];
};
```

### 1.4 LLVM Lowering

```llvm
; Direct C-compatible layout
%sockaddr_in = type { i16, i16, i32, [8 x i8] }
```

### 1.5 Mandatory Guarantees

1. **Compiler-chosen padding**: The compiler may insert padding for alignment as specified by the target C ABI
2. **Stable field offsets**: Field addresses are fixed and follow C struct rules
3. **No bit-level fields**: Only C-compatible primitive types (unless using `unsigned data{N}` with `N ∈ {8,16,32,64}`)
4. **No destructive casting**: Cannot be cast to/from `struct` without explicit copy
5. **No consumption semantics**: No automatic pointer advancement on access

### 1.6 Prohibited Features

```flux
cstruct Example {
    unsigned data{13} custom;  // ERROR: Non-standard width
};

cstruct Another {
    int x;
    // No methods allowed
    def foo() -> void { }  // ERROR: cstruct cannot have methods
};
```

### 1.7 Interoperation Rules

**Explicit copy required between `cstruct` and `struct`:**

```flux
cstruct CPoint {
    float x, y, z;
};

struct SPoint {
    float x, y, z;
};

def convert(CPoint c) -> SPoint {
    // MUST copy manually
    SPoint s = {x = c.x, y = c.y, z = c.z};
    return s;
};

// NOT ALLOWED:
// SPoint s = (SPoint)c;  // COMPILE ERROR
```

---

## 2. `class`: Traditional Object-Oriented Programming

### 2.1 Definition and Purpose

A `class` is built on `cstruct` (not `struct`) and provides:
- Stable object identity
- Reference semantics
- Virtual dispatch (optional)
- Traditional OOP inheritance
- Explicit lifetime management

**Critical Design Decision:** `class` extends `cstruct`, not `struct`. This maintains a clean separation between Flux's zero-cost data model and traditional OOP.

### 2.2 Syntax

```flux
class ClassName [: BaseClass] {
    // Member variables
    Type field;
    
    // Constructor
    def __init([params]) -> this;
    
    // Destructor
    def __exit() -> void;
    
    // Methods
    def method([params]) -> ReturnType;
    
    // Virtual methods (optional)
    virtual def vmethod([params]) -> ReturnType;
};
```

### 2.3 Example

```flux
class File {
    int fd;
    
    def __init(string path, string mode) -> this {
        this.fd = fopen(path, mode);
        return this;
    };
    
    def __exit() -> void {
        if (this.fd != -1) {
            fclose(this.fd);
        };
        return void;
    };
    
    def read(byte[] buf) -> int {
        return fread(buf.data, 1, buf.len, this.fd);
    };
    
    def close() -> void {
        fclose(this.fd);
        this.fd = -1;
        return void;
    };
};
```

### 2.4 LLVM Lowering (Conceptual)

```llvm
; With vtable (if virtual methods exist)
%File = type {
    %File.vtable*,  ; vtable pointer (optional)
    i32             ; fd field
}

; Without vtable (no virtual methods)
%File = type {
    i32             ; fd field only
}
```

### 2.5 Memory Layout Guarantees

1. **Stable `this` pointer**: Object identity preserved throughout lifetime
2. **Reference semantics**: Assignment copies references, not data
3. **Optional vtable**: Only present if virtual methods declared
4. **No bit reinterpretation**: Cannot be cast to `data` or `struct` without explicit serialization

### 2.6 Inheritance Model

```flux
class Shape {
    float x, y;
    
    def __init(float x, float y) -> this {
        this.x = x;
        this.y = y;
        return this;
    };
    
    virtual def area() -> float {
        return 0.0;
    };
    
    def __exit() -> void {
        return void;
    };
};

class Circle : Shape {
    float radius;
    
    def __init(float x, float y, float r) -> this {
        this.Shape::__init(x, y);  // Explicit base call
        this.radius = r;
        return this;
    };
    
    def area() -> float {
        return 3.14159 * this.radius * this.radius;
    };
    
    def __exit() -> void {
        this.Shape::__exit();
        return void;
    };
};
```

### 2.7 Object Creation and Destruction

```flux
def create_and_use() -> void {
    // Stack allocation (RAII)
    Circle c(10.0, 20.0, 5.0);
    
    // Heap allocation
    Circle* pc = new Circle(0.0, 0.0, 1.0);
    
    // Method calls
    float a = c.area();
    float b = pc->area();
    
    // Manual destruction (heap)
    (void)pc;  // Calls __exit() and frees memory
    // c.__exit() automatically called here
};
```

---

## 3. Semantic Boundaries and Conversions

### 3.1 The Three-Tier Type System

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     struct      │    │     cstruct     │    │      class      │
│                 │    │                 │    │                 │
│ • Zero-cost     │    │ • C ABI         │    │ • OOP semantics │
│ • Bit-level     │    │ • Stable layout │    │ • Identity      │
│ • Consumption   │    │ • No methods    │    │ • Inheritance   │
│ • Reinterpret   │    │ • Interop only  │    │ • Virtual       │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         │    Explicit copy     │      Built on        │
         └──────────────────────┘      top of          │
                            (wall)                     │
                                                       │
                                       Reference semantics
```

### 3.2 Conversion Rules

**Allowed:**
- `class` → `cstruct` (view base layout)
- `cstruct` → C code (direct interop)

**Explicit copy required:**
- `struct` ↔ `cstruct`
- `struct` ↔ `class`

**Never allowed:**
- Direct bit reinterpretation between `struct` and `cstruct`/`class`
- Consumption semantics on `cstruct` or `class`

### 3.3 Example Conversions

```flux
// C interop scenario
cstruct timeval {
    long tv_sec;
    long tv_usec;
};

extern("C") {
    def gettimeofday(timeval* tv, void* tz) -> int;
};

def get_time() -> (long, long) {
    timeval tv;
    gettimeofday(@tv, void);
    
    // Convert to Flux struct for processing
    struct TimeSpec {
        unsigned data{64} seconds;
        unsigned data{64} microseconds;
    };
    
    // EXPLICIT COPY REQUIRED
    TimeSpec ts = {
        seconds = (unsigned data{64})tv.tv_sec,
        microseconds = (unsigned data{64})tv.tv_usec
    };
    
    return (ts.seconds, ts.microseconds);
};
```

---

## 4. Implementation Guidelines

### 4.1 Compiler Requirements

1. **Separate type hierarchies**: Maintain distinct metadata for `struct`, `cstruct`, and `class`
2. **ABI compliance verification**: Validate `cstruct` layouts against target C ABI
3. **Explicit copy enforcement**: Prevent implicit conversions between incompatible type families
4. **Vtable optimization**: Omit vtable pointer when no virtual methods exist

### 4.2 Runtime Behavior

```flux
// Memory layout examples
class WithVtable {
    int data;
    virtual def foo() -> void;
};
// Layout: [vptr: 8 bytes][data: 4 bytes][padding: 4 bytes] (64-bit)

class WithoutVtable {
    int data;
    def bar() -> void;  // Non-virtual
};
// Layout: [data: 4 bytes] (no vptr overhead)

cstruct CStruct {
    int a;
    char b;
};
// Layout: [a: 4 bytes][b: 1 byte][padding: 3 bytes] (typical C)
```

### 4.3 Debugging Support

```flux
def inspect_class<T>() -> void {
    print(f"Class: {typeof(T)}");
    print(f"Size: {sizeof(T)} bytes");
    print(f"Has vtable: {T.has_vtable}");
    print(f"Base classes: {T.base_classes}");
};

def inspect_cstruct<T>() -> void {
    print(f"CStruct: {typeof(T)}");
    print(f"C-compatible: {T.is_c_compatible}");
    print(f"Field offsets:");
    for (field in T.fields) {
        print(f"  {field.name}: offset={field.offset}, size={field.size}");
    };
};
```

---

## 5. Use Cases and Examples

### 5.1 C Library Wrapping

```flux
cstruct dirent {
    unsigned long d_ino;
    long          d_off;
    unsigned short d_reclen;
    char           d_type;
    char           d_name[256];
};

extern("C") {
    def opendir(string path) -> void*;
    def readdir(void* dirp) -> dirent*;
    def closedir(void* dirp) -> int;
};

class Directory {
    void* handle;
    
    def __init(string path) -> this {
        this.handle = opendir(path);
        return this;
    };
    
    def __exit() -> void {
        if (this.handle != void) {
            closedir(this.handle);
        };
        return void;
    };
    
    def next() -> string {
        dirent* entry = readdir(this.handle);
        if (entry == void) return "";
        
        // Convert C string to Flux string
        return string(entry.d_name);
    };
};
```

### 5.2 Mixed Data Processing

```flux
// High-performance processing with struct
struct Packet {
    unsigned data{32} timestamp;
    unsigned data{16} length;
    unsigned data{8}  protocol;
    // ... more fields
};

// C-compatible storage
cstruct StoredPacket {
    unsigned int timestamp;
    unsigned short length;
    unsigned char protocol;
    char data[1500];
};

class PacketBuffer {
    Packet[] buffer;
    
    def save_to_c_format() -> StoredPacket[] {
        StoredPacket[] result = new StoredPacket[this.buffer.len];
        
        for (i in 0..this.buffer.len-1) {
            // EXPLICIT conversion required
            result[i].timestamp = this.buffer[i].timestamp;
            result[i].length = this.buffer[i].length;
            result[i].protocol = this.buffer[i].protocol;
            // ... copy other fields
        };
        
        return result;
    };
};
```

---

## 6. Summary of Key Design Decisions

1. **`cstruct` for C ABI only**: No Flux-specific features, no compromises
2. **`class` built on `cstruct`**: Preserves traditional OOP expectations
3. **Absolute boundary with `struct`**: Zero-cost reinterpretation stays in its own domain
4. **Explicit conversions required**: No hidden costs or surprises
5. **Optional vtables**: Pay-for-what-you-use performance model

This design ensures that:
- C interop remains simple and reliable
- OOP code behaves as expected from other languages
- Flux's unique `struct` capabilities remain uncompromised
- Programmers always know when data conversion occurs