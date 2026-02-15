# Learn Flux for Experienced Programmers

This guide assumes you're already comfortable with systems programming concepts and have experience with languages like C++, Rust, or similar. Flux introduces some radically different paradigms that require rethinking how you approach low-level programming.

---

## Core Philosophy: Structs as Data Contracts

**The fundamental shift:** In most languages, structs are lightweight classes. In Flux, they're pure data layout specifications that can act as pointer maps for casting.

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
def allocate() -> ~int {
    heap int ~x = 42;
    (void)~x;
    return ~x;  // Explicit transfer
};

def main() -> int {
    heap int ~value = ~allocate();
    (void)~value;
    return 0;
};
```

**Enforcement:**
- Compiler tracks `~` variables
- Must explicitly move/destroy before scope end
- Escape hatch: `int* raw = @(~owned);` drops tracking

```flux
def oops() -> void {
    heap int ~x = 42;  // ERROR: ~x not moved/destroyed
};

def correct() -> void {
    heap int ~x = 42;
    (void)~x;  // Explicitly freed
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

## Advanced Pointer Techniques

Pointers in Flux are explicit and powerful. Understanding advanced pointer manipulation is essential for systems programming.

### Address-of with Literals

You can take the address of literal values:

```flux
#import "standard.fx";

def main() -> int
{
    int* x = @25;  // Address-of literal integer
    if (*x == 25)
    {
        print("Address of literal integer to pointer working.\0");
    };
    return 0;
};
```

**Why this works:** Literals are materialized in read-only memory, so you can point to them.

### Address Casting: `(@)` Operator

The `(@)` operator reinterprets an integer as a pointer address:

```flux
#import "standard.fx";

def main() -> int
{
    int a = 5;
    int* pa = @a;      // Get address of a
    
    int x = (int)pa;   // Cast pointer to integer
    int* pb = (@)x;    // Cast integer back to pointer
    
    if (*pb == 5)
    {
        print("Success!\0");
    };
    return 0;
};
```

**Key insight:** Pointers are just numbers. `(@)` makes this explicit.

### Pointer Arithmetic and Manipulation

```flux
#import "standard.fx";

def main() -> int
{
    uint x, y = 10, 0;
    uint* px, py = @x, @y;
    
    // Store pointer as integer
    u64 kx = px;
    
    // Reinterpret integer as pointer
    py = (@)kx;  // py now points to x
    
    // Verify
    if (x == 10 & y == 0 & *py == x & px == py & px == (@)kx)
    {
        print("Success, y unchanged, py points to x.\n\0");
        print((uint)*py);
    };
    
    return 0;
};
```

**Pattern:**
1. Pointer → integer: implicit or explicit cast
2. Integer → pointer: `(@)` operator
3. This enables low-level memory manipulation

### Hardware Register Access

```flux
// Memory-mapped I/O
struct GPIO {
    unsigned data{32} control;
    unsigned data{32} data;
    unsigned data{32} direction;
};

// Point to hardware address
volatile GPIO* gpio = (@)0x40020000;

gpio.control = 0x01;     // Write to hardware register
uint state = gpio.data;  // Read from hardware register
```

---

## Function Advanced Features

### Function Chaining: `<-` Operator

The chain operator `<-` passes the result of the right function to the left function:

```flux
#import "standard.fx";

def foo(int x) -> int
{
    return x - 1;
};

def bar() -> int
{
    return 1;
};

def main() -> int
{
    if ((foo() <- bar()) == 0)  // Equivalent to: foo(bar())
    {
        print("Success!\0");
    };
    return 0;
};
```

**Syntax:** `foo() <- bar()` ≡ `foo(bar())`

This enables pipeline-style programming:

```flux
int result = transform() <- validate() <- parse() <- readInput();
// Reads right-to-left: readInput() → parse() → validate() → transform()
```

### Function Pointers: `def{}*` Syntax

Function pointers use the `def{}*` type syntax:

```flux
#import "standard.fx";

def foo(int x) -> int
{
    print("Inside foo!\n\0");
    return 0;
};

def main() -> int
{
    def{}* pfoo(int) -> int = @foo;  // Take address of function
    print("Function pointer created.\n\0");
    print((u32)pfoo);
    print();
    
    pfoo(0);  // Call through pointer
    
    return 0;
};
```

**Pattern:**
- Type: `def{}* name(params) -> return_type`
- Assign: `@function_name`
- Call: `pointer(args)`

### Null Coalesce: `??` Operator

Returns the left value if non-void, otherwise returns the right value:

```flux
#import "standard.fx";

def main() -> int
{
    int x = 0;
    int y = 5;
    
    int z = y ?? 0;  // y is not void, so z = 5
    
    if (z is 5)
    {
        print("Success!\0");
    };
    return 0;
};
```

**Useful for default values:**

```flux
def getValue(bool has_value, int value) -> int
{
    int result = void;
    if (has_value)
    {
        result = value;
    };
    return result ?? -1;  // Return -1 if result is void
};
```

### Ternary Expressions

Standard conditional expressions:

```flux
#import "standard.fx";

def main() -> int
{
    int x = 0;
    int y = 5;
    
    int z = x < y ? y : 0;  // If x < y, z = y, else z = 0
    
    if (z is 5)
    {
        print("Success!\0");
    };
    return 0;
};
```

---

## Tagged Unions

Tagged unions combine an enum tag with a union for type-safe variant storage:

```flux
#import "standard.fx";

enum my_enum
{
    GOOD_RETURN,
    BAD_RETURN_1
};

// Regular union
union reg { int x; };

// Tagged union - enum after union definition
union tag_union
{
    int x;
    char y;
} my_enum;

def main() -> int
{
    reg myU;
    myU.x = 5;
    if (myU.x == 5)
    {
        print("Unions working!\n\0");
    };
    
    tag_union myT;
    
    myT._ = my_enum.GOOD_RETURN;  // ._ accesses the union tag
    
    switch (myT._)
    {
        case (0)
        {
            print("Tagged unions working!\n\0");
        }
        default {};
    };
    
    return my_enum.GOOD_RETURN;
};
```

**Key points:**
- Syntax: `union Name { ... } EnumType;`
- Access tag with `._`
- Enables runtime type tracking for unions
- Pattern matching with switch on `._`

**Advanced pattern:**

```flux
enum ResultType
{
    OK,
    ERROR,
    PENDING
};

union Result
{
    int value;
    int error_code;
    float progress;
} ResultType;

def processResult(Result r) -> void
{
    switch (r._)
    {
        case ResultType.OK:
        {
            print("Value: \0");
            print(r.value);
        };
        case ResultType.ERROR:
        {
            print("Error: \0");
            print(r.error_code);
        };
        case ResultType.PENDING:
        {
            print("Progress: \0");
            print(r.progress);
        };
    };
};
```

---

## Array Packing and Bit Manipulation

Arrays can be concatenated and type-punned for bit-level control:

```flux
#import "standard.fx";

def main() -> int
{
    uint[1] a = [0u];            // 32 bits of zeros
    uint[2] b = [a[0]] + [1u];   // Concatenate: 32 zeros + 32-bit value 1
    
    u64 x = (u64)b;              // Cast array to 64-bit int
    print(x);                    // Prints 1 (bits: 32 zeros + 31 zeros + 1)
    print();
    return 0;
};
```

**What's happening:**
1. `a = [0u]` → 32 bits of zeros
2. `[a[0]] + [1u]` → Create new array by concatenation
3. Result is 64 bits: `00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000001`
4. Cast to `u64` reinterprets these bits as integer 1

**Pattern for bit packing:**

```flux
// Pack two 32-bit values into one 64-bit value
def pack(uint high, uint low) -> u64
{
    uint[2] packed = [high] + [low];
    return (u64)packed;
};

// Unpack
def unpack(u64 value) -> uint[2]
{
    return (uint[2])value;
};

// Usage
u64 combined = pack(0x12345678, 0xABCDEF00);
uint[2] parts = unpack(combined);
// parts[0] = 0x12345678
// parts[1] = 0xABCDEF00
```

---

## Void Semantics

`void` in Flux is a first-class value with special boolean semantics:

```flux
#import "standard.fx";

def main() -> int
{
    // void is equivalent to false
    while (void is false)  // void == false, !void == true
    {
        print("[void is not true]\0");
    };
    return 0;
};
```

**Key properties:**
- `void == false` → true
- `void == 0` → true
- `!void == true` → true
- `void is void` → true

**Using void as a sentinel:**

```flux
def findValue(int[] arr, int target) -> int*
{
    for (int i = 0; i < sizeof(arr) / sizeof(int); i++)
    {
        if (arr[i] == target)
        {
            return @arr[i];
        };
    };
    return (int*)void;  // Return null pointer
};

// Usage
int[] numbers = [1, 2, 3, 4, 5];
int* result = findValue(numbers, 3);

if (result is void)
{
    print("Not found\0");
}
else
{
    print("Found: \0");
    print(*result);
};
```

**Void vs null patterns:**

```flux
// Check if pointer is null
int* ptr = (int*)void;
if (ptr is void) { /* it's null */ };
if (ptr == void) { /* also null */ };
if (!ptr) { /* also null */ };

// Set to null
ptr = void;

// Free memory (DIFFERENT from setting to null!)
int* heap_ptr = malloc(sizeof(int));
(void)heap_ptr;  // Frees memory immediately
```

---

## Namespace System

Namespaces organize code and prevent name collisions:

### Using Directive

```flux
#import "redstandard.fx";

using standard::io;  // Import everything from standard::io

def main() -> int
{
    int MAX = 10;
    char[10] buffer;
    
    print("What's your name? \0");
    int bytes_read = win_input(buffer, MAX);  // win_input from standard::io
    print("Hello, \0");
    print(@buffer, bytes_read);
    print(".\0");
    
    return 0;
};
```

### Selective Import and Exclusion

```flux
// Import specific items
using standard::io::print, standard::io::input;

// Import everything EXCEPT specific items
using standard::io;
!using standard::io::debug_print;  // Exclude debug_print
// OR
not using standard::io::debug_print;  // Same as !using
```

**Pattern for library organization:**

```flux
namespace mylib
{
    namespace core
    {
        def init() -> void { /* ... */ };
        def cleanup() -> void { /* ... */ };
    };
    
    namespace utils
    {
        def helper() -> int { /* ... */ };
    };
};

// Use it
using mylib::core;
using mylib::utils;

def main() -> int
{
    init();
    int x = helper();
    cleanup();
    return 0;
};
```

**Avoiding name conflicts:**

```flux
using network::send;
!using io::send;  // Exclude io::send to avoid conflict

// Or use full qualification
network::send(data);
io::write(data);  // Use write instead of send
```

---

## Memory Management Patterns

### Heap Allocation and File I/O

Real-world pattern for reading files:

```flux
#import "standard.fx";

def main() -> int
{
    // Files can exceed stack limits - use heap
    noopstr f = "src\\stdlib\\redio.fx\0";
    int size = get_file_size(f);
    byte* buffer = malloc((u64)size + 1);  // +1 for null terminator
    
    int bytes_read = read_file(f, buffer, size);
    
    if (bytes_read > 0)
    {
        print("Success!\n\n\0");
    };
    
    print(buffer);
    print();
    
    free(buffer);  // Always free heap memory
    return 0;
};
```

**Critical pattern:**
1. Calculate size needed
2. `malloc()` with proper size
3. Use the buffer
4. `free()` when done

### Stack Limits

```flux
// WRONG - may exceed stack size (not fully wrong, see advanced doc to learn more about stack limits)
def processLargeFile() -> int
{
    byte[1048576] buffer;  // 1MB on stack - DANGEROUS!
    // ...
};

// RIGHT - use heap for large allocations
def processLargeFile() -> int
{
    byte* buffer = malloc(1048576);
    if (buffer is void)
    {
        return -1;  // Allocation failed
    };
    
    // Process file...
    
    free(buffer);
    return 0;
};
```

---

## Real-World Example: HTTP Server

Complete TCP/HTTP server demonstrating systems programming in Flux:

```flux
#import "standard.fx", "rednet_windows.fx";

// Build HTTP response
def build_http_response(byte* content, int content_len, byte* buffer) -> int
{
    byte* header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \0";
    byte* header_end = "\r\n\r\n\0";
    
    int pos = 0;
    int i = 0;
    
    // Copy header
    while (header[i] != 0)
    {
        buffer[pos] = header[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // Add content length
    byte[32] len_str;
    i32str(content_len, @len_str[0]);
    i = 0;
    while (len_str[i] != 0)
    {
        buffer[pos] = len_str[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // Add header end
    i = 0;
    while (header_end[i] != 0)
    {
        buffer[pos] = header_end[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // Add content
    i = 0;
    while (i < content_len)
    {
        buffer[pos] = content[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    return pos;
};

// Parse HTTP request
def parse_request_path(byte* request, byte* path_buffer, int max_len) -> int
{
    int start = 0;
    bool found = false;
    
    // Find "GET "
    int i = 0;
    while (request[i] != 0 & i < 500)
    {
        if (request[i] == 'G' & request[i+1] == 'E' & request[i+2] == 'T' & request[i+3] == ' ')
        {
            start = i + 4;
            found = true;
            break;
        };
        i = i + 1;
    };
    
    if (!found) { return 0; };
    
    // Extract path
    int path_len = 0;
    i = start;
    while (request[i] != 0 & request[i] != ' ' & request[i] != '?' & path_len < max_len - 1)
    {
        path_buffer[path_len] = request[i];
        path_len = path_len + 1;
        i = i + 1;
    };
    path_buffer[path_len] = '\0';
    
    return path_len;
};

// Handle client
def handle_client(int client_sock) -> void
{
    byte[4096] request_buffer;
    byte[8192] response_buffer;
    byte[256] path_buffer;
    
    int bytes_recv = tcp_recv(client_sock, @request_buffer[0], 4096);
    
    if (bytes_recv > 0)
    {
        if (bytes_recv < 4096)
        {
            request_buffer[bytes_recv] = (byte)0;
        };
        
        int path_len = parse_request_path(@request_buffer[0], @path_buffer[0], 256);
        
        print("Request: \0");
        if (path_len > 0)
        {
            print(@path_buffer[0], path_len);
        };
        print("\n\0");
        
        // Route based on path
        byte* content;
        int content_len;
        
        bool is_root = (path_len == 1 & path_buffer[0] == '/');
        
        if (is_root)
        {
            content = "<html><body><h1>Flux HTTP Server</h1><p>Welcome!</p></body></html>\0";
            content_len = 0;
            while (content[content_len] != 0) { content_len = content_len + 1; };
        }
        else
        {
            content = "<html><body><h1>404 Not Found</h1></body></html>\0";
            content_len = 0;
            while (content[content_len] != 0) { content_len = content_len + 1; };
        };
        
        int response_len = build_http_response(content, content_len, @response_buffer[0]);
        tcp_send_all(client_sock, @response_buffer[0], response_len);
    };
    
    tcp_close(client_sock);
};

// Main server
def main() -> int
{
    int init_result = init();
    if (init_result != 0)
    {
        print("Failed to initialize Winsock\n\0");
        return 1;
    };
    
    print("Starting HTTP server on port 8080...\n\0");
    
    int server_sock = tcp_server_create((u16)8080, 10);
    if (server_sock < 0)
    {
        print("Failed to create server socket\n\0");
        cleanup();
        return 1;
    };
    
    print("Server listening on localhost:8080\n\0");
    
    sockaddr_in client_addr;
    while (true)
    {
        int client_sock = tcp_server_accept(server_sock, @client_addr);
        
        if (client_sock >= 0)
        {
            byte* client_ip = get_ip_string(@client_addr);
            u16 client_port = get_port(@client_addr);
            
            print("Connection from: \0");
            int ip_len = 0;
            while (client_ip[ip_len] != 0) { ip_len = ip_len + 1; };
            print(client_ip, ip_len);
            print("\n\0");
            
            handle_client(client_sock);
        };
    };
    
    tcp_close(server_sock);
    cleanup();
    
    return 0;
};
```

**This example demonstrates:**
- TCP socket programming
- HTTP protocol parsing
- String manipulation without stdlib
- Buffer management
- Manual memory handling
- Namespace imports (`#import "standard.fx", "rednet_windows.fx"`)
- Real-world systems programming patterns

---

## Endianness System

Flux has first-class endianness support built into the type system:

### Declaring Endianness

```flux
// Syntax: unsigned data{bits::endianness}
unsigned data{16::0} as little16;  // Little-endian 16-bit (::0)
unsigned data{16::1} as big16;     // Big-endian 16-bit (::1)
unsigned data{32::0} as little32;  // Little-endian 32-bit
unsigned data{32::1} as big32;     // Big-endian 32-bit
```

**Endianness values:**
- `::0` = little-endian
- `::1` = big-endian
- No suffix = platform default (usually little-endian)

### Using `endianof` Operator

```flux
def checkEndianness() -> void
{
    unsigned data{16::0} as le16;
    unsigned data{16::1} as be16;
    
    int le_endian = endianof(le16);  // Returns 0
    int be_endian = endianof(be16);  // Returns 1
    
    print("Little-endian type: \0");
    print(le_endian);
    print("\nBig-endian type: \0");
    print(be_endian);
    print("\n\0");
};
```

### Automatic Byte Swapping

Flux automatically swaps bytes when assigning between different endianness:

```flux
unsigned data{16::1} as be16 net_value = 0x1234;  // Big-endian
unsigned data{16::0} as le16 host_value;          // Little-endian

host_value = net_value;  // Automatic byte swap: 0x1234 → 0x3412

print(net_value);   // 0x1234 (big-endian representation)
print(host_value);  // 0x3412 (byte-swapped to little-endian)
```

### Network Protocol Example

```flux
struct TCPHeader
{
    unsigned data{16::1} as be16 src_port,dst_port;
    unsigned data{32::1} as be32 seq_number,ack_number;
    unsigned data{4} as nibble data_offset;
    unsigned data{6} as tiny flags;
    unsigned data{16::1} as be16 window_size,checksum,urgent_ptr;
};

def parseTCP(byte[] packet) -> TCPHeader
{
    // Zero-cost cast - endianness handled by type system
    TCPHeader* header = (TCPHeader*)@packet[0];
    return *header;
};

def processPacket(byte[] packet) -> void
{
    TCPHeader tcp = parseTCP(packet);
    
    // Access values - no manual byte swapping needed
    print("Source port: \0");
    print(tcp.src_port);  // Automatically converted to host byte order
    print("\nDest port: \0");
    print(tcp.dst_port);
    print("\nSeq: \0");
    print(tcp.seq_number);
    print("\n\0");
};
```

### Mixed Endianness Structs

```flux
struct BinaryFileHeader
{
    unsigned data{32::0} as le32 magic;        // Little-endian magic
    unsigned data{32::1} as be32 file_size;    // Big-endian size
    unsigned data{16::0} as le16 version;      // Little-endian version
    unsigned data{16::1} as be16 flags;        // Big-endian flags
};

def readFileHeader(byte[] data) -> BinaryFileHeader
{
    BinaryFileHeader* header = (BinaryFileHeader*)@data[0];
    return *header;  // Each field converted to proper byte order
};
```

---

## Memory Layout and Alignment

### Struct Packing with Custom Alignment

```flux
// Tightly packed struct (no padding)
struct PackedRGB
{
    unsigned data{5:1} as r5 r;    // 5 bits, byte-aligned
    unsigned data{6:1} as g6 g;    // 6 bits, byte-aligned
    unsigned data{5:1} as b5 b;    // 5 bits, byte-aligned
};  // Total: 16 bits (2 bytes)

// Aligned struct with gaps
struct AlignedData
{
    unsigned data{8:16} as byte16 flag;   // 8 bits, 16-bit aligned
    u32 value;                            // 32 bits, 32-bit aligned
    unsigned data{8:16} as byte16 status; // 8 bits, 16-bit aligned
};  // Total: 64 bits (8 bytes) with padding

sizeof(PackedRGB);    // 16 bits = 2 bytes
sizeof(AlignedData);  // 64 bits = 8 bytes

alignof(PackedRGB);   // 1 byte (byte-aligned)
alignof(AlignedData); // 4 bytes (strictest member)
```

### Manual Offset Calculation

```flux
struct Vector3
{
    float x;
    float y;
    float z;
};

def get_y_ptr(Vector3* vec) -> float*
{
    unsigned data{64} as u64ptr;
    
    // Get base address
    u64ptr base = (u64ptr)vec;
    
    // Manual offset to 'y' (sizeof(float) = 4 bytes = 32 bits)
    u64ptr y_addr = base + 4;
    
    // Return pointer to y member
    return (float*)y_addr;
};

// Usage
Vector3 v = {x = 1.0, y = 2.0, z = 3.0};
float* py = get_y_ptr(@v);
*py = 5.0;
print(v.y);  // 5.0
```

### Pointer Array Traversal

```flux
def traverse_as_bytes(int* ptr, int count) -> void
{
    byte* bp = (byte*)ptr;
    
    for (int i = 0; i < count * sizeof(int); i++)
    {
        print("Byte \0");
        print(i);
        print(": 0x\0");
        print(*(bp + i));
        print("\n\0");
    };
};

int[4] data = [0x12345678, 0x9ABCDEF0, 0x11223344, 0x55667788];
traverse_as_bytes(@data[0], 4);
```

---

## Bit-Field Manipulation

### Unusual Bit Widths

```flux
// 3-bit unsigned value (0-7)
unsigned data{3} as tiny = 5;

// 17-bit signed value
signed data{17} as weird17 = -1000;

// 7-bit with 8-bit alignment (1 bit padding)
unsigned data{7:8} as aligned7 = 127;

// Array of 5-bit values
unsigned data{5}[10] as nibble_array arr;
arr[0] = 0x1F;  // Max value for 5 bits

// Casting between weird widths
unsigned data{13} as u13 a = 8191;
unsigned data{17} as u17 b = (u17)a;  // Zero-extend
signed data{13} as s13 c = (s13)a;    // Reinterpret bits
```

### Extract Specific Bit Ranges

```flux
u32 packed = 0x12345678;

def extract_bits(u32 value, int start, int length) -> u32
{
    u32 mask = ((1 << length) - 1) << start;
    return (value & mask) >> start;
};

u32 nibble0 = extract_bits(packed, 0, 4);   // 0x8
u32 nibble3 = extract_bits(packed, 12, 4);  // 0x5
u32 byte1 = extract_bits(packed, 8, 8);     // 0x56
```

### 13-bit Signed Value

```flux
// 13-bit signed value, 16-bit aligned
signed data{13:16} as strange13;

strange13 value = 0x1FFF;  // Max positive value for 13 bits
print(value);               // 8191

value = 0x1000;            // Sign bit set (bit 12)
print(value);              // -4096 (two's complement)
```

### Mixing Signed/Unsigned in Expressions

```flux
signed data{32} as i32;
unsigned data{32} as u32;

i32 a = -10;
u32 b = 20;

// Mixed arithmetic
i32 result1 = a + (i32)b;    // -10 + 20 = 10 (signed)
u32 result2 = (u32)a + b;    // 4294967286 + 20 (unsigned, wraps)

// Comparison with mixed signs
if (a < (i32)b)  // true: -10 < 20
{
    print("Signed comparison\0");
};

if ((u32)a < b)  // false: 4294967286 > 20
{
    print("Unsigned comparison\0");
};
```

---

## Advanced Control Flow

### Nested Switches

```flux
def classify_value(int x, int y) -> void
{
    switch (x)
    {
        case (0)
        {
            switch (y)
            {
                case (0)
                {
                    print("Both zero\0");
                };
                case (1)
                {
                    print("X zero, Y one\0");
                };
                default
                {
                    print("X zero, Y other\0");
                };
            };
        };
        case (1)
        {
            print("X is one\0");
        };
        default
        {
            print("X is other\0");
        };
    };
};
```

### Nested Loops with Break/Continue

```flux
def find_in_matrix(int[][] matrix, int target) -> bool
{
    for (int i = 0; i < 10; i++)
    {
        for (int j = 0; j < 10; j++)
        {
            if (matrix[i][j] == target)
            {
                print("Found at [\0");
                print(i);
                print("][\0");
                print(j);
                print("]\n\0");
                return true;  // Break out of both loops
            };
            
            if (matrix[i][j] < 0)
            {
                continue;  // Skip negative values
            };
        };
    };
    
    return false;
};
```

### Do-While with Complex Condition

```flux
def wait_for_ready(int* status_reg) -> void
{
    int timeout = 1000;
    do
    {
        if (*status_reg & 0x01)  // Ready bit
        {
            break;
        };
        timeout--;
    } while (timeout > 0 & !(*status_reg & 0x80));  // Not error bit
};
```

---

## Function Pointer Patterns

### Callback Systems

```flux
// Function pointer type for callbacks
def{}* EventHandler(int) -> void;

object EventSystem
{
    EventHandler[10] handlers;
    int handler_count;
    
    def __init() -> this
    {
        this.handler_count = 0;
        return this;
    };
    
    def __exit() -> void { return void; };
    
    def register(EventHandler handler) -> void
    {
        if (this.handler_count < 10)
        {
            this.handlers[this.handler_count] = handler;
            this.handler_count++;
        };
        return void;
    };
    
    def trigger(int event_code) -> void
    {
        for (int i = 0; i < this.handler_count; i++)
        {
            this.handlers[i](event_code);  // Call each handler
        };
        return void;
    };
};

// Handler functions
def on_error(int code) -> void
{
    print("Error: \0");
    print(code);
    print("\n\0");
    return void;
};

def on_warning(int code) -> void
{
    print("Warning: \0");
    print(code);
    print("\n\0");
    return void;
};

// Usage
EventSystem events();
events.register(@on_error);
events.register(@on_warning);
events.trigger(404);  // Calls both handlers
```

### Jump Tables

```flux
enum Oper
{
    ADD,
    SUB,
    MUL,
    DIV
};

def{}* OpFunc(int, int) -> int;
def op_add(int a, int b) -> int { return a + b; };
def op_sub(int a, int b) -> int { return a - b; };
def op_mul(int a, int b) -> int { return a * b; };
def op_div(int a, int b) -> int { return b != 0 ? a / b : 0; };

OpFunc[4] operations;
operations[0] = @op_add;
operations[1] = @op_sub;
operations[2] = @op_mul;
operations[3] = @op_div;

def calculate(int opcode, int a, int b) -> int
{
    if (opcode >= 0 & opcode < 4)
    {
        return operations[opcode](a, b);  // Jump table dispatch
    };
    return 0;
};

// Usage
print(calculate(Oper.ADD, 10, 5));  // 15 (add)
print(calculate(Oper.SUB, 10, 5));  // 5  (sub)
print(calculate(Oper.MUL, 10, 5));  // 50 (mul)
print(calculate(Oper.DIV, 10, 5));  // 2  (div)
```

### Vtable-like Structures

```flux
struct ShapeVTable
{
    def{}* area(void*) -> float;
    def{}* perimeter(void*) -> float;
    def{}* draw(void*) -> void*;
};

struct Shape
{
    ShapeVTable* vtable;
    void* data;
};

// Circle implementation
struct CircleData
{
    float radius;
};

def circle_area(void* data) -> float
{
    CircleData* c = (CircleData*)data;
    return 3.14159 * c.radius * c.radius;
};

def circle_perimeter(void* data) -> float
{
    CircleData* c = (CircleData*)data;
    return 2.0 * 3.14159 * c.radius;
};

def circle_draw(void* data) -> void
{
    CircleData* c = (CircleData*)data;
    print("Drawing circle with radius \0");
    print(c.radius);
    print("\n\0");
    return;
};

ShapeVTable circle_vtable = {
    area = @circle_area,
    perimeter = @circle_perimeter,
    draw = @circle_draw
};

// Usage
CircleData my_circle = {radius = 5.0};
Shape shape = {
    vtable = @circle_vtable,
    data = (@)@my_circle
};

float a = shape.vtable.area(shape.data);
shape.vtable.draw(shape.data);
```

---

## Advanced Error Handling

### Multiple Exception Types

```flux
object ErrorA
{
    int code;
    def __init(int c) -> this { this.code = c; return this; };
    def __exit() -> void { return; };
};

object ErrorB
{
    byte[256] message;
    def __init(byte[] m) -> this
    {
        for (int i = 0; i < 256; i++)
        {
            this.message[i] = m[i];
            if (m[i] == 0) { break; };
        };
        return this;
    };
    def __exit() -> void { return void; };
};

def risky_operation(int mode) -> void
{
    if (mode == 1)
    {
        ErrorA err(100);
        throw(err);
    }
    elif (mode == 2)
    {
        byte[] msg = "Something failed\0";
        ErrorB err(msg);
        throw(err);
    }
    else
    {
        throw("Generic error\0");
    };
};

def main() -> int
{
    try
    {
        risky_operation(1);
    }
    catch (ErrorA e)
    {
        print("ErrorA caught: code \0");
        print(e.code);
        print("\n\0");
    }
    catch (ErrorB e)
    {
        print("ErrorB caught: \0");
        print(@e.message[0]);
        print("\n\0");
    }
    catch (byte[] s)
    {
        print("String error: \0");
        print(s);
        print("\n\0");
    }
    catch (auto x)
    {
        print("Unknown error type\0");
    };
    
    return 0;
};
```

### Nested Try-Catch

```flux
def complex_operation() -> int
{
    try
    {
        try
        {
            // Inner operation that might fail
            throw("Inner error\0");
        }
        catch (byte[] msg)
        {
            print("Caught inner: \0");
            print(msg);
            print("\n\0");
            // Re-throw with different type
            ErrorA err(500);
            throw(err);
        };
    }
    catch (ErrorA e)
    {
        print("Caught outer: \0");
        print(e.code);
        print("\n\0");
        return e.code;
    };
    
    return 0;
};
```

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
