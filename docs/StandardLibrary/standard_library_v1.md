# Flux Standard Library Documentation

Version: 1.0 (Reduced Specification)  
Date: February 2026

---

## Table of Contents

1. [Overview](#overview)
2. [Library Structure](#library-structure)
3. [Core Modules](#core-modules)
   - [standard.fx](#standardfx)
   - [redstandard.fx](#redstandardfx)
   - [redtypes.fx](#redtypesfx)
   - [redio.fx](#rediofx)
   - [redmath.fx](#redmathfx)
4. [Runtime System](#runtime-system)
   - [redruntime.fx](#redruntimefx)
   - [redmemory.fx](#redmemoryfx)
   - [ffifio.fx](#ffifiofx)
5. [String Utilities](#string-utilities)
   - [red_string_utilities.fx](#red_string_utilitiesfx)
   - [string_object_raw.fx](#string_object_rawfx)
6. [Import Guidelines](#import-guidelines)
7. [Platform Support](#platform-support)

---

## Overview

The Flux Standard Library provides a comprehensive set of tools and utilities for systems programming, designed to work across Windows, Linux, and macOS platforms. The library is currently implemented using the reduced specification to support the language bootstrap process.

### Design Philosophy

- **Cross-platform compatibility**: Supports Windows, Linux, and macOS through conditional compilation
- **Low-level control**: Direct access to system calls and memory management
- **Type safety**: Comprehensive type system with platform-specific definitions
- **Minimal dependencies**: Core functionality with optional FFI support
- **Performance-oriented**: Assembly-level optimizations where needed

---

## Library Structure

```
stdlib/
  ├── standard.fx              # Main entry point
  ├── redstandard.fx           # Reduced specification standard library
  ├── redtypes.fx              # Type definitions and utilities
  ├── redio.fx                 # Input/output operations
  ├── redmath.fx               # Mathematical functions
  ├── runtime/
  │   ├── ffifio.fx            # FFI-based file I/O (C runtime)
  │   ├── redmemory.fx         # Memory management (FFI)
  │   └── redruntime.fx        # Runtime initialization
  ├── functions/
  │   └── red_string_utilities.fx  # String manipulation functions
  └── builtins/
      └── string_object_raw.fx     # String object implementation
```

---

## Core Modules

### standard.fx

**Purpose**: Main entry point for the Flux Standard Library

**Usage**:
```flux
#import "standard.fx";
```

**Description**:  
The `standard.fx` file serves as the primary import point for applications using the Flux Standard Library. It automatically includes the reduced specification implementation and sets up the necessary namespace structure.

**Features**:
- Defines `FLUX_STANDARD` and `FLUX_REDUCED_SPECIFICATION` preprocessor flags
- Imports the complete reduced specification standard library
- Provides foundation for future full specification implementation

**Note**: This file is designed to remain stable during the transition from reduced to full specification.  
All libraries "use" themselves currently, so you do not need to perform `using`.  
In a future update, a macro called `__NO_DEFAULT_USING__` will allow more programmer control.

---

### redstandard.fx

**Purpose**: Core implementation of the reduced specification standard library

**Location**: `stdlib/redstandard.fx`

**Dependencies**:
- `redruntime.fx` (conditionally imported if `FLUX_RUNTIME` is enabled)

**Namespace**: `standard`

**Description**:  
Provides the base implementation of the standard library for the reduced specification. This module serves as a container for runtime initialization and namespace organization.

**Configuration**:
```flux
#def FLUX_RUNTIME 1;  // Enable runtime (default)
#def FLUX_RUNTIME 0;  // Disable runtime
```

---

### redtypes.fx

**Purpose**: Comprehensive type system definitions and utilities

**Location**: `stdlib/redtypes.fx`

**Namespace**: `standard::types`

#### Type Definitions

##### Primitive Types

| Type Alias | Definition | Description |
|------------|------------|-------------|
| `nybble` | `unsigned data{4}` | 4-bit unsigned integer |
| `byte` | `unsigned data{8}` | 8-bit unsigned integer |
| `u16` | `unsigned data{16}` | 16-bit unsigned integer |
| `u32` | `unsigned data{32}` | 32-bit unsigned integer |
| `u64` | `unsigned data{64}` | 64-bit unsigned integer |
| `i8` | `signed data{8}` | 8-bit signed integer |
| `i16` | `signed data{16}` | 16-bit signed integer |
| `i32` | `signed data{32}` | 32-bit signed integer |
| `i64` | `signed data{64}` | 64-bit signed integer |

##### String Types

| Type | Definition | Description |
|------|------------|-------------|
| `noopstr` | `byte[]` | Null-terminated byte string |

##### Pointer Types

| Type | Definition | Description |
|------|------------|-------------|
| `byte_ptr` | `byte*` | Pointer to byte |
| `i32_ptr` | `i32*` | Pointer to 32-bit signed integer |
| `i64_ptr` | `i64*` | Pointer to 64-bit signed integer |
| `void_ptr` | `void*` | Generic pointer |
| `noopstr_ptr` | `noopstr*` | Pointer to string |

##### Platform-Specific Types

**x86_64 and ARM64**:
```flux
intptr    // i64* - Pointer-sized signed integer
uintptr   // u64* - Pointer-sized unsigned integer
ssize_t   // i64  - Signed size type
size_t    // u64  - Unsigned size type
```

**x86 (32-bit)**:
```flux
intptr    // i32* - Pointer-sized signed integer
uintptr   // u32* - Pointer-sized unsigned integer
ssize_t   // i32  - Signed size type
size_t    // u32  - Unsigned size type
```

**Windows-Specific**:
```flux
wchar     // i16  - Wide character (UTF-16)
```

##### Network/Endian Types

**Big-Endian (Network Byte Order)**:
```flux
be16  // unsigned data{16::1}
be32  // unsigned data{32::1}
be64  // unsigned data{64::1}
```

**Little-Endian (Host Byte Order)**:
```flux
le16  // unsigned data{16::0}
le32  // unsigned data{32::0}
le64  // unsigned data{64::0}
```

#### Utility Functions

##### Byte Swapping

```flux
def bswap16(u16 value) -> u16
def bswap32(u32 value) -> u32
def bswap64(u64 value) -> u64
```

Swap byte order for endianness conversion.

**Example**:
```flux
u16 net_value = bswap16(0x1234);  // 0x3412
```

##### Network/Host Conversion

```flux
def ntoh16(be16 net_value) -> le16  // Network to host (16-bit)
def ntoh32(be32 net_value) -> le32  // Network to host (32-bit)
def hton16(le16 host_value) -> be16 // Host to network (16-bit)
def hton32(le32 host_value) -> be32 // Host to network (32-bit)
```

Convert between network (big-endian) and host (little-endian) byte order.

##### Bit Manipulation

```flux
def bit_set(u32* value, u32 bit) -> void    // Set bit to 1
def bit_clear(u32* value, u32 bit) -> void  // Clear bit to 0
def bit_toggle(u32* value, u32 bit) -> void // Toggle bit
def bit_test(u32 value, u32 bit) -> bool    // Test if bit is set
```

**Example**:
```flux
u32 flags = 0;
bit_set(@flags, 3);      // Set bit 3
bool is_set = bit_test(flags, 3);  // true
```

##### Alignment Utilities

```flux
def align_up(u64 value, u64 alignment) -> u64
def align_down(u64 value, u64 alignment) -> u64
def is_aligned(u64 value, u64 alignment) -> bool
```

**Example**:
```flux
u64 aligned = align_up(137, 16);  // 144
bool check = is_aligned(144, 16);  // true
```

---

### redio.fx

**Purpose**: Cross-platform input/output operations

**Location**: `stdlib/redio.fx`

**Namespace**: `standard::io`

**Sub-namespaces**:
- `standard::io::console` - Console I/O operations
- `standard::io::file` - File I/O operations

#### Console I/O

##### Input Functions

```flux
def input(byte[] buffer, int max_len) -> int
```

Read user input from console. Platform-agnostic wrapper that calls the appropriate platform-specific implementation.

**Parameters**:
- `buffer`: Byte array to store input
- `max_len`: Maximum number of bytes to read

**Returns**: Number of bytes read (excluding null terminators)

**Platform Implementations**:
- Windows: `win_input()` - Uses Windows API (ReadFile)
- Linux: `nix_input()` - Uses Linux syscalls
- macOS: `mac_input()` - Uses macOS syscalls

##### Output Functions

```flux
def print(noopstr s, int len) -> void
def print(noopstr s) -> void
def print(byte s) -> void
```

Print to console output.

**Overloads**:
- `print(noopstr s, int len)`: Print string with explicit length
- `print(noopstr s)`: Print null-terminated string
- `print(byte s)`: Print single character

**Example**:
```flux
print("Hello, World!\0\0");
print('A');  // Print single character
```

**Platform Implementations**:
- Windows: `win_print()` - Uses Windows API (WriteFile)
- Linux: `nix_print()` - Uses Linux syscalls (write)
- macOS: `mac_print()` - Uses macOS syscalls

#### File I/O (Native Implementation)

The file I/O system provides both native syscall-based and FFI-based implementations.

##### Windows File I/O

**Constants**:
```flux
GENERIC_READ          = 0x80000000
GENERIC_WRITE         = 0x40000000
GENERIC_READ_WRITE    = 0xC0000000
FILE_SHARE_READ       = 0x00000001
FILE_SHARE_WRITE      = 0x00000002
CREATE_NEW            = 1
CREATE_ALWAYS         = 2
OPEN_EXISTING         = 3
OPEN_ALWAYS           = 4
FILE_ATTRIBUTE_NORMAL = 0x00000080
INVALID_HANDLE_VALUE  = -1
```

**Core Functions**:

```flux
def win_open(byte* path, i32 access, i32 share, i32 create, i32 flags) -> i64
```

Open a file with specified parameters.

**Returns**: File handle or `INVALID_HANDLE_VALUE` on error

```flux
def win_read(i64 handle, byte* buffer, u32 bytes_to_read, u32* bytes_read) -> i32
```

Read from a file.

**Returns**: 1 on success, 0 on failure

```flux
def win_write(i64 handle, byte* buffer, u32 bytes_to_write, u32* bytes_written) -> i32
```

Write to a file.

**Returns**: 1 on success, 0 on failure

```flux
def win_close(i64 handle) -> i32
```

Close a file handle.

**Returns**: 1 on success, 0 on failure

**Helper Functions**:

```flux
def open_read(byte* path) -> i64
def open_write(byte* path) -> i64
def open_append(byte* path) -> i64
def open_read_write(byte* path) -> i64
```

Simplified file opening functions.

##### Linux File I/O

**System Call Numbers**:
```flux
SYS_OPEN  = 2
SYS_READ  = 0
SYS_WRITE = 1
SYS_CLOSE = 3
SYS_EXIT  = 60
```

**Open Flags**:
```flux
O_RDONLY = 0x0000
O_WRONLY = 0x0001
O_RDWR   = 0x0002
O_CREAT  = 0x0040
O_TRUNC  = 0x0200
O_APPEND = 0x0400
```

**Permission Modes**:
```flux
S_IRUSR = 0x0400  // User read
S_IWUSR = 0x0200  // User write
S_IXUSR = 0x0100  // User execute
S_IRGRP = 0x0040  // Group read
S_IWGRP = 0x0020  // Group write
S_IXGRP = 0x0010  // Group execute
S_IROTH = 0x0004  // Others read
S_IWOTH = 0x0002  // Others write
S_IXOTH = 0x0001  // Others execute
DEFAULT_PERM = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
```

**Core Functions**:

```flux
open(byte* path, i32 flags, i32 mode) -> i64
read(i64 fd, byte* buffer, u64 count) -> i64
write(i64 fd, byte* buffer, u64 count) -> i64
close(i64 fd) -> i32
```

**Helper Functions**:

```flux
open_read(byte* path) -> i64
dopen_write(byte* path) -> i64
open_append(byte* path) -> i64
open_read_write(byte* path) -> i64
read32(i64 fd, byte* buffer, u32 count) -> i32
write32(i64 fd, byte* buffer, u32 count) -> i32
```

**Example Usage**:
```flux
#import "standard.fx";

def main() -> int
{
    // Open file for writing
    i64 fd = open_write("output.txt\0");
    if (fd == INVALID_FD)
    {
        print("Failed to open file\0");
        return 1;
    };
    
    // Write data
    byte[] data = "Hello, File!\0";
    i64 written = write(fd, @data[0], 13);
    
    // Close file
    close(fd);
    return 0;
};
```

---

### redmath.fx

**Purpose**: Comprehensive mathematical functions with type overloading

**Location**: `stdlib/redmath.fx`

**Namespace**: `standard::math`

#### Mathematical Constants

```flux
// Integer approximations
PI8, PI16, PI32, PI64 = 3
E8, E16, E32, E64 = 2

// Floating-point constants
PIF = 3.14159265358979323846
EF  = 2.71828182845904523536
```

#### Core Mathematical Functions

All functions are overloaded for types: `i8`, `i16`, `i32`, `i64`, `float`

##### Absolute Value

```flux
def abs(T x) -> T  // T ∈ {i8, i16, i32, i64, float}
```

Returns the absolute value of `x`.

##### Minimum and Maximum

```flux
def min(T a, T b) -> T
def max(T a, T b) -> T
```

Returns the minimum or maximum of two values.

##### Clamp

```flux
def clamp(T value, T low, T high) -> T
```

Constrains `value` to be within the range [`low`, `high`].

**Example**:
```flux
i32 clamped = clamp(150, 0, 100);  // Returns 100
```

##### Square Root

```flux
def sqrt(T x) -> T
```

Computes the square root using Newton's method.

- Integer versions: Use integer arithmetic
- Float version: Uses iterative refinement with epsilon tolerance

**Example**:
```flux
i32 root = sqrt(144);      // Returns 12
float precise = sqrt(2.0); // Returns ~1.414
```

##### Factorial

```flux
def factorial(T n) -> T  // T ∈ {i8, i16, i32, i64}
```

Computes `n!` iteratively.

**Note**: Results overflow quickly; use appropriate type sizes.

##### Greatest Common Divisor (GCD)

```flux
def gcd(T a, T b) -> T  // T ∈ {i8, i16, i32, i64}
```

Computes GCD using Euclidean algorithm.

##### Least Common Multiple (LCM)

```flux
def lcm(T a, T b) -> T  // T ∈ {i8, i16, i32, i64}
```

Computes LCM using the formula: `lcm(a,b) = |a*b| / gcd(a,b)`.

##### Power Function

```flux
def pow(T base, T exp) -> T  // T ∈ {i8, i16, i32, i64, float}
```

Computes `base^exp`.

- Integer versions: Use repeated multiplication
- Float version: Supports fractional exponents using exp/log

#### Trigonometric Functions

```flux
def sin(float x) -> float
def cos(float x) -> float
def tan(float x) -> float
```

Trigonometric functions using Taylor series approximations.

**Note**: Input `x` should be in radians.

**Example**:
```flux
float sine = sin(PIF / 2.0);  // Returns ~1.0
```

#### Logarithmic Functions

```flux
def log(float x) -> float    // Natural logarithm
def log10(float x) -> float  // Base-10 logarithm
```

Logarithm functions using series approximations.

#### Additional Utilities

##### Linear Interpolation

```flux
def lerp(T a, T b, float t) -> T  // T ∈ {i8, i16, i32, i64, float}
```

Linearly interpolates between `a` and `b` by factor `t` (where `t` ∈ [0, 1]).

**Example**:
```flux
float mid = lerp(0.0, 100.0, 0.5);  // Returns 50.0
```

##### Sign Function

```flux
def sign(T x) -> T  // T ∈ {i8, i16, i32, i64, float}
```

Returns:
- `1` if `x > 0`
- `-1` if `x < 0`
- `0` if `x == 0`

##### Population Count (Hamming Weight)

```flux
def popcount(T x) -> T  // T ∈ {i8, i16, i32, i64, byte, u16, u32, u64}
```

Counts the number of set bits (1s) in the binary representation.

**Example**:
```flux
i32 count = popcount(0b11010110);  // Returns 5
```

##### Bit Reversal

```flux
def reverse_bits(T x) -> T  // T ∈ {byte, i8, i16, i32, i64}
```

Reverses the bits in the value.

**Example**:
```flux
byte reversed = reverse_bits(0b11010010);  // Returns 0b01001011
```

---

## Runtime System

### redruntime.fx

**Purpose**: Runtime initialization and program entry point management

**Location**: `stdlib/runtime/redruntime.fx`

**Description**:  
Manages the startup sequence for Flux programs across different platforms. Handles command-line argument parsing, platform detection, and calls the appropriate `main()` function.

#### Platform Detection

The runtime automatically detects the operating system:
```flux
CURRENT_OS values:
  1 = Windows
  2 = Linux
  3 = macOS
```

#### Entry Points

**User-Defined Main Functions**:
```flux
def main() -> int
def main(int* argc, byte** argv) -> int
```

**Runtime Entry Point** (Do not redefine):
```flux
def FRTStartup() -> int
```

The `FRTStartup()` function is the actual entry point called by the operating system. It handles:
1. Platform detection
2. Command-line argument extraction
3. Calling user's `main()` function
4. Process cleanup

**Linux Entry**:
```flux
def _start() -> int  // Calls FRTStartup()
```

#### Command-Line Arguments (Windows)

Windows-specific FFI declarations:
```flux
extern def GetCommandLineW() -> wchar*
extern def CommandLineToArgvW(wchar* cmdline, int* argc) -> wchar**
extern def LocalFree(void* ptr) -> void*
```

**Example**:
```flux
#import "standard.fx";

def main(int* argc, byte** argv) -> int
{
    print("Arguments:\0");
    for (int i = 0; i < *argc; i++)
    {
        print(argv[i]);
        print("\n\0");
    };
    return 0;
};
```

#### Exit Functions

```flux
extern def exit(int code) -> void
extern def abort() -> void
```

---

### redmemory.fx

**Purpose**: Memory management through C runtime FFI

**Location**: `stdlib/runtime/redmemory.fx`

**Description**:  
Provides access to standard C memory management functions through Foreign Function Interface (FFI).

#### Memory Allocation

```flux
extern def malloc(size_t size) -> void*
```

Allocate `size` bytes of uninitialized memory.

**Returns**: Pointer to allocated memory, or `null` on failure

```flux
extern def calloc(size_t num, size_t size) -> void*
```

Allocate memory for an array of `num` elements of `size` bytes each, initialized to zero.

```flux
extern def realloc(void* ptr, size_t size) -> void*
```

Resize previously allocated memory block.

```flux
extern def free(void* ptr) -> void
```

Free previously allocated memory.

**Example**:
```flux
// Allocate 100 bytes
void* buffer = malloc(100);
if (buffer == 0)
{
    print("Allocation failed\0");
    return 1;
};

// Use the buffer...

// Free the memory
free(buffer);
```

#### Memory Operations

```flux
extern 
{
    def !!
        memcpy(void* dest, void* src, size_t n) -> void*,
        memmove(void* dest, void* src, size_t n) -> void*,
        memset(void* ptr, int value, size_t n) -> void*,
        memcmp(void* ptr1, void* ptr2, size_t n) -> int;
};
```

- `memcpy`: Copy `n` bytes from `src` to `dest` (non-overlapping)
- `memmove`: Copy `n` bytes from `src` to `dest` (handles overlap)
- `memset`: Fill `n` bytes of `ptr` with `value`
- `memcmp`: Compare `n` bytes of `ptr1` and `ptr2`

#### String Operations (C Runtime)

```flux
extern
{
    def !!
        strlen(const char* str) -> size_t,

        strcpy(char* dest, const char* src) -> char*,
        strncpy(char* dest, const char* src, size_t n) -> char*,

        strcat(char* dest, const char* src) -> char*,
        strncat(char* dest, const char* src, size_t n) -> char*,

        strcmp(const char* s1, const char* s2) -> int,
        strncmp(const char* s1, const char* s2, size_t n) -> int,

        strchr(const char* str, int ch) -> char*,
        strstr(const char* haystack, const char* needle) -> char*;
};
```

**Note**: These are FFI declarations to C runtime functions. For native Flux implementations, see `red_string_utilities.fx`.  
Using `!!` prevents name mangling, and when performed with multiple prototype declaration, it cascades to the `;`

#### Process Control

```flux
extern
{
    def !!
        abort() -> void,
        exit(int status) -> void,
        atexit(void* callback) -> int;
};
```

---

### ffifio.fx

**Purpose**: File I/O through C standard library FFI

**Location**: `stdlib/runtime/ffifio.fx`

**Namespace**: `standard::io::file`

**Description**:  
Provides high-level file I/O operations using C's stdio.h through FFI. This is an alternative to the native syscall-based file I/O.

#### C stdio FFI Declarations

```flux
extern
{
    def !!
        fopen(byte* filename, byte* mode) -> void*,
        fclose(void* stream) -> int,
        fread(void* ptr, int size, int count, void* stream) -> int,
        fwrite(void* ptr, int size, int count, void* stream) -> int,
        fseek(void* stream, int offset, int whence) -> int,
        ftell(void* stream) -> int,
        rewind(void* stream) -> void,
        feof(void* stream) -> int,
        ferror(void* stream) -> int;
};
```

#### File Modes

| Mode | Description |
|------|-------------|
| `"r"` | Read |
| `"w"` | Write (truncate) |
| `"a"` | Append |
| `"r+"` | Read/write |
| `"w+"` | Read/write (truncate) |
| `"rb"` | Read binary |
| `"wb"` | Write binary |
| `"ab"` | Append binary |

#### Seek Constants

```flux
SEEK_SET = 0  // Beginning of file
SEEK_CUR = 1  // Current position
SEEK_END = 2  // End of file
```

#### High-Level Helper Functions

```flux
def read_file(byte* filename, byte[] buffer, int buffer_size) -> int
```

Read entire file into buffer.

**Returns**: Number of bytes read, or -1 on error

```flux
def write_file(byte* filename, byte[] data, int data_size) -> int
```

Write buffer to file (creates/truncates).

**Returns**: Number of bytes written, or -1 on error

```flux
def append_file(byte* filename, byte[] data, int data_size) -> int
```

Append buffer to file.

**Returns**: Number of bytes written, or -1 on error

```flux
def get_file_size(byte* filename) -> int
```

Get file size in bytes.

**Returns**: File size, or -1 on error

```flux
def file_exists(byte* filename) -> bool
```

Check if file exists.

**Returns**: `true` if file exists, `false` otherwise

**Example**:
```flux
#import "standard.fx";

def main() -> int
{
    // Write to file
    byte[] data = "Hello, World!\0";
    int written = write_file("test.txt\0", data, 13);
    
    if (written < 0)
    {
        print("Failed to write file\0");
        return 1;
    };
    
    // Read from file
    byte[1024] buffer;
    int read_bytes = read_file("test.txt\0", buffer, 1024);
    
    if (read_bytes > 0)
    {
        print(buffer);
    };
    
    return 0;
};
```

---

## String Utilities

### red_string_utilities.fx

**Purpose**: Comprehensive string manipulation functions

**Location**: `stdlib/functions/red_string_utilities.fx`

**Description**:  
Native Flux implementations of string operations without C runtime dependencies.

#### Core String Functions

##### String Length

```flux
def strlen(byte* ps) -> int
```

Calculate the length of a null-terminated string.

##### String Copy

```flux
def strcpy(noopstr dest, noopstr src) -> noopstr
```

Copy string from `src` to `dest`.

**Returns**: Pointer to `dest`

#### Integer to String Conversion

```flux
def i32str(i32 value, byte* buffer) -> i32
def i64str(i64 value, byte* buffer) -> i64
def u32str(u32 value, byte* buffer) -> u32
def u64str(u64 value, byte* buffer) -> u64
```

Convert integers to string representation.

**Parameters**:
- `value`: Integer to convert
- `buffer`: Buffer to write the string (should be at least 32 bytes)

**Returns**: Number of characters written (excluding null terminator)

**Example**:
```flux
byte[32] buffer;
i32 len = i32str(-12345, @buffer[0]);
print(buffer);  // Prints "-12345"
```

#### String to Integer Conversion

```flux
def str2i32(byte* str) -> int
def str2u32(byte* str) -> uint
def str2i64(byte* str) -> i64
def str2u64(byte* str) -> u64
```

Convert string to integer.

**Features**:
- Skips leading whitespace
- Handles sign (`+` or `-`)
- Stops at first non-digit character

**Example**:
```flux
int value = str2i32("  -42\0");  // Returns -42
```

#### Float Conversion

```flux
def fstr(float value, byte* buffer, int precision) -> int
def str2f(byte* str) -> float
```

Convert between float and string.

**Parameters for `fstr`**:
- `value`: Float to convert
- `buffer`: Output buffer
- `precision`: Number of decimal places

**Example**:
```flux
byte[64] buffer;
fstr(3.14159, @buffer[0], 2);  // "3.14"
float pi = str2f("3.14159\0");
```

#### Character Classification

```flux
def is_digit(byte c) -> bool         // Is '0'-'9'
def is_alpha(byte c) -> bool         // Is 'a'-'z' or 'A'-'Z'
def is_alnum(byte c) -> bool         // Is alphanumeric
def is_whitespace(byte c) -> bool    // Is ' ', '\t', '\n', '\r'
def is_upper(byte c) -> bool         // Is 'A'-'Z'
def is_lower(byte c) -> bool         // Is 'a'-'z'
def is_hex_digit(byte c) -> bool     // Is '0'-'9', 'a'-'f', 'A'-'F'
def is_identifier_start(byte c) -> bool
def is_identifier_char(byte c) -> bool
```

#### Character Conversion

```flux
def to_upper(byte c) -> byte
def to_lower(byte c) -> byte
def hex_to_int(byte c) -> int
```

#### String Comparison

```flux
def str_equals(byte* s1, byte* s2) -> bool
def str_equals_n(byte* s1, byte* s2, int n) -> bool
def starts_with(byte* str, byte* prefix) -> bool
def ends_with(byte* str, byte* suffix) -> bool
```

**Example**:
```flux
bool match = str_equals("hello\0", "hello\0");  // true
bool prefix = starts_with("hello world\0", "hello\0");  // true
```

#### String Search

```flux
def find_char(byte* str, byte ch, int start_pos) -> int
def find_char_last(byte* str, byte ch) -> int
def find_substring(byte* haystack, byte* needle, int start_pos) -> int
def count_char(byte* str, byte ch) -> int
```

**Returns**: Index of found character/substring, or -1 if not found

**Example**:
```flux
int pos = find_char("hello\0", 'l', 0);  // Returns 2
```

#### String Manipulation

```flux
def skip_whitespace(byte* str, int pos) -> int
def trim_start(byte* str) -> int
def trim_end(byte* str) -> int
```

**Memory-Allocating Functions**:

```flux
def copy_string(byte* src) -> byte*
def copy_n(byte* src, int n) -> byte*
def substring(byte* str, int start, int length) -> byte*
def concat(byte* s1, byte* s2) -> byte*
```

**Note**: Functions that return `byte*` allocate memory using `malloc()`. Caller is responsible for freeing.

**Example**:
```flux
byte* combined = concat("Hello, \0", "World!\0");
print(combined);
free(combined);
```

#### Parsing Functions

```flux
def parse_int(byte* str, int start_pos, int* end_pos) -> int
def parse_hex(byte* str, int start_pos, int* end_pos) -> int
```

Parse integers from strings and update position.

**Example**:
```flux
int end;
int value = parse_int("  123 abc\0", 0, @end);  // value=123, end=5
```

#### Line and Word Operations

```flux
def count_lines(byte* str) -> int
def get_line(byte* str, int line_num) -> byte*
def count_words(byte* str) -> int
```

**Example**:
```flux
byte* text = "Line 1\nLine 2\nLine 3\0";
int lines = count_lines(text);  // Returns 3
byte* line = get_line(text, 1); // Returns "Line 2"
```

#### String Replacement

```flux
def replace_first(byte* str, byte* find, byte* replace) -> byte*
```

Replace first occurrence of substring.

**Returns**: New allocated string (caller must free)

#### Tokenization Helpers

```flux
def skip_until(byte* str, int pos, char ch) -> int
def skip_while_digit(byte* str, int pos) -> int
def skip_while_alnum(byte* str, int pos) -> int
def skip_while_identifier(byte* str, int pos) -> int
def match_at(byte* str, int pos, byte* pattern) -> bool
```

These functions are useful for lexical analysis and parsing.

---

### string_object_raw.fx

**Purpose**: Object-oriented string wrapper

**Location**: `stdlib/builtins/string_object_raw.fx`

**Description**:  
Provides an object-oriented interface for string manipulation.

#### String Object

```flux
object string
{
    noopstr value;
    
    def __init(byte* x) -> this;
    def __exit() -> void;
    
    def val() -> byte*;
    def len() -> int;
    def set(noopstr s) -> bool;
};
```

**Methods**:

- `__init(byte* x)`: Constructor, initialize with string
- `__exit()`: Destructor
- `val()`: Get the underlying string value
- `len()`: Get string length
- `set(noopstr s)`: Set new string value (with exception handling)

**Example**:
```flux
#import "standard.fx";

def main() -> int
{
    string myStr("Hello, World!\0");
    
    print("String: \0");
    print(myStr.val());
    print("\n\0");
    
    int length = myStr.len();
    byte[32] len_buffer;
    i32str(length, @len_buffer[0]);
    print("Length: \0");
    print(len_buffer);
    print("\n\0");
    
    return 0;
};
```

---

## Import Guidelines

### Basic Import

To use the standard library:

```flux
#import "standard.fx";
```

This automatically imports:
- Type definitions (`redtypes.fx`)
- Runtime system (`redruntime.fx`)
- Memory management (`redmemory.fx`)
- I/O operations (`redio.fx`)
- File I/O via FFI (`ffifio.fx`)
- String utilities (`red_string_utilities.fx`)
- Math library dependencies

### Selective Imports

For more control, import specific modules:

```flux
// Types only
#import "redtypes.fx";

// I/O only
#import "redio.fx";

// Math operations
#import "redmath.fx";

// String utilities
#import "red_string_utilities.fx";
```

### Namespace Usage

After importing, use namespaces explicitly or with `using`:

```flux
#import "standard.fx";

// Explicit namespace
int result = standard::math::abs(-42);

// Using directive
using standard::math;
int result = abs(-42);
```

### Conditional Compilation

Control which parts of the standard library are included:

```flux
// Disable runtime
#def FLUX_RUNTIME 0;
#import "standard.fx";

// Use specific features
#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;
```

---

## Platform Support

### Supported Platforms

| Platform | Architecture | Status |
|----------|--------------|--------|
| Windows | x86_64 (64-bit) | Support, viable for now |
| Linux | x86_64 (64-bit) | Support, viable for now |
| macOS | x86_64 (64-bit) | Partial Support, needs improvement |
| -     | ARM (64-bit)    | Minimal Support, needs major improvement

### Platform Detection

The standard library uses preprocessor definitions for platform detection:

```flux
#ifdef __WINDOWS__
    // Windows-specific code
#endif;

#ifdef __LINUX__
    // Linux-specific code
#endif;

#ifdef __MACOS__
    // macOS-specific code
#endif;

#ifdef __ARCH_X86_64__
    // 64-bit x86 code
#endif;

#ifdef __ARCH_ARM64__
    // ARM64 code
#endif;
```

### OS Detection at Runtime

```flux
CURRENT_OS  // Set by runtime
  1 = Windows
  2 = Linux
  3 = macOS
```

**Example**:
```flux
switch (CURRENT_OS)
{
    case (1)
    {
        print("Running on Windows\0");
    }
    case (2)
    {
        print("Running on Linux\0");
    }
    case (3)
    {
        print("Running on macOS\0");
    }
};
```

### Platform-Specific Notes

#### Windows

- Uses Windows API for console I/O (GetStdHandle, WriteFile, ReadFile)
- File I/O through both Windows API and C FFI
- Supports wide character handling (`wchar`)
- Command-line arguments via `GetCommandLineW()`

#### Linux

- Direct syscall interface for I/O operations
- No C runtime dependency for core operations
- File descriptor-based file I/O
- Entry point: `_start()` → `FRTStartup()`

#### macOS

- Similar to Linux with BSD syscalls
- Console I/O implementation pending full testing
- File operations via POSIX syscalls

---

## Best Practices

### Memory Management

1. **Always free allocated memory**:
   ```flux
   byte* str = malloc(100);
   // ... use str ...
   free(str);
   ```

2. **Check allocation results**:
   ```flux
   void* buffer = malloc(1024);
   if (buffer == 0)
   {
       // Handle allocation failure
       return -1;
   };
   ```

3. **Use appropriate types**:
   ```flux
   size_t size = 1024;  // Platform-appropriate size type
   void* ptr = malloc(size);
   ```

### String Handling

1. **Always null-terminate strings**:  
The compiler does not null terminate your strings.
   ```flux
   print("Hello, World!\0");
   ```

2. **Use appropriate buffer sizes**:
   ```flux
   byte[32] buffer;  // Enough for most integer conversions
   i32str(value, @buffer[0]);
   ```

3. **Free dynamically allocated strings**:
   ```flux
   byte* result = concat(s1, s2);
   print(result);
   free(result);
   ```

### File I/O

1. **Always check file handles**:
   ```flux
   i64 fd = open_read("file.txt\0");
   if (fd == INVALID_FD)
   {
       // Handle error
       return -1;
   };
   ```

2. **Close files when done**:
   ```flux
   i64 fd = open_write("output.txt\0");
   // ... operations ...
   close(fd);
   ```

3. **Use appropriate modes**:
   ```flux
   i64 fd = open_append("log.txt\0");  // Don't truncate log files
   ```

### Error Handling

1. **Check return values**:
   ```flux
   int result = write_file("data.txt\0", buffer, size);
   if (result < 0)
   {
       print("Write failed\0");
       return 1;
   };
   ```

2. **Use try-catch for critical sections**:
   ```flux
   try
   {
       // Risky operation
   }
   catch()
   {
       // Handle error
       return false;
   };
   ```

### Type Safety

1. **Use type aliases for clarity**:
   ```flux
   size_t buffer_size = 1024;
   byte_ptr data = malloc(buffer_size);
   ```

2. **Explicit casts for clarity**:
   ```flux
   i64 big_value = (i64)small_value;
   ```

---

## Version History

**Version 1.0** (February 2026)
- Initial reduced specification implementation
- Cross-platform support (Windows, Linux, macOS)
- Core I/O, math, and string utilities
- FFI integration with C runtime
- Bootstrap-ready implementation

---

## Contributing

The Flux Standard Library is part of the Flux language project. For contributions, bug reports, or questions, please visit the [Flux Discord server](https://discord.gg/RAHjbYuNUc).

---

## License

This documentation describes the Flux Standard Library as part of the Flux programming language project.

---

*This documentation is current as of the Flux reduced specification implementation (v1.0, February 2026). For the most up-to-date information, please refer to the official Flux language repository and Discord community.*