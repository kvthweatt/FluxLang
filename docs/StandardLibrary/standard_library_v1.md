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
6. [Collections Library](#collections-library)
   - [redcollections.fx](#redcollectionsfx)
7. [Vectors Library](#vectors-library)
   - [redvectors.fx](#redvectorsfx)
8. [Import Guidelines](#import-guidelines)
9. [Platform Support](#platform-support)

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
  â”œâ”€â”€ standard.fx              # Main entry point
  â”œâ”€â”€ redstandard.fx           # Reduced specification standard library
  â”œâ”€â”€ redtypes.fx              # Type definitions and utilities
  â”œâ”€â”€ redio.fx                 # Input/output operations
  â”œâ”€â”€ redmath.fx               # Mathematical functions
  â”œâ”€â”€ runtime/
  â”‚   â”œâ”€â”€ ffifio.fx            # FFI-based file I/O (C runtime)
  â”‚   â”œâ”€â”€ redmemory.fx         # Memory management (FFI)
  â”‚   â””â”€â”€ redruntime.fx        # Runtime initialization
  â”œâ”€â”€ functions/
  â”‚   â””â”€â”€ red_string_utilities.fx  # String manipulation functions
  â””â”€â”€ builtins/
      â””â”€â”€ string_object_raw.fx     # String object implementation
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
def abs(T x) -> T  // T {i8, i16, i32, i64, float}
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
def factorial(T n) -> T  // T  {i8, i16, i32, i64}
```

Computes `n!` iteratively.

**Note**: Results overflow quickly; use appropriate type sizes.

##### Greatest Common Divisor (GCD)

```flux
def gcd(T a, T b) -> T  // T  {i8, i16, i32, i64}
```

Computes GCD using Euclidean algorithm.

##### Least Common Multiple (LCM)

```flux
def lcm(T a, T b) -> T  // T  {i8, i16, i32, i64}
```

Computes LCM using the formula: `lcm(a,b) = |a*b| / gcd(a,b)`.

##### Power Function

```flux
def pow(T base, T exp) -> T  // T  {i8, i16, i32, i64, float}
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
def lerp(T a, T b, float t) -> T  // T  {i8, i16, i32, i64, float}
```

Linearly interpolates between `a` and `b` by factor `t` (where `t`  [0, 1]).

**Example**:
```flux
float mid = lerp(0.0, 100.0, 0.5);  // Returns 50.0
```

##### Sign Function

```flux
def sign(T x) -> T  // T  {i8, i16, i32, i64, float}
```

Returns:
- `1` if `x > 0`
- `-1` if `x < 0`
- `0` if `x == 0`

##### Population Count (Hamming Weight)

```flux
def popcount(T x) -> T  // T  {i8, i16, i32, i64, byte, u16, u32, u64}
```

Counts the number of set bits (1s) in the binary representation.

**Example**:
```flux
i32 count = popcount(0b11010110);  // Returns 5
```

##### Bit Reversal

```flux
def reverse_bits(T x) -> T  // T  {byte, i8, i16, i32, i64}
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

## Collections Library

### redcollections.fx

**Purpose**: Comprehensive data structure implementations for Flux

**Location**: `stdlib/redcollections.fx`

**Namespace**: `standard::collections`

**Dependencies**:
- `redtypes.fx` - Type definitions
- `redmemory.fx` - Memory management (malloc, free, realloc)

**Description**:  
The collections library provides essential data structures for efficient data management in Flux applications. All collections are generic (using `void*` payloads) and manage their own memory allocation.

#### Dynamic Array (Array)

**Purpose**: Resizable array with O(1) amortized push/pop operations

**Definition**:
```flux
object Array
{
    void** items;
    size_t size;
    size_t capacity;
};
```

**Constructors**:
```flux
Array()                      // Default capacity: 16
Array(size_t initial_capacity)  // Custom capacity
```

**Core Methods**:

| Method | Returns | Description |
|--------|---------|-------------|
| `get_size()` | `size_t` | Get current number of elements |
| `get_capacity()` | `size_t` | Get current allocated capacity |
| `is_empty()` | `bool` | Check if array is empty |
| `push(void* item)` | `bool` | Add item to end (auto-resize) |
| `pop()` | `void*` | Remove and return last item |
| `get(size_t index)` | `void*` | Get item at index |
| `set(size_t index, void* item)` | `bool` | Set item at index |
| `clear()` | `void` | Remove all items (keeps capacity) |
| `remove_at(size_t index)` | `bool` | Remove item at index (shift left) |
| `insert_at(size_t index, void* item)` | `bool` | Insert item at index (shift right) |

**Example**:
```flux
#import "redcollections.fx";

Array myArray(32);  // Start with capacity 32
myArray.push((void*)42);
myArray.push((void*)100);

void* value = myArray.get(0);  // Returns (void*)42
size_t count = myArray.get_size();  // Returns 2

myArray.pop();  // Remove last element
```

**Notes**:
- Automatically doubles capacity when full
- Returns `false` on allocation failure
- Does NOT manage payload memory - caller must free payloads

---

#### Doubly Linked List (LinkedList)

**Purpose**: Dynamic list with O(1) insertion/deletion at both ends

**Definition**:
```flux
struct LinkedListNode
{
    void* payload;
    LinkedListNode* next;
    LinkedListNode* prev;
};

object LinkedList
{
    LinkedListNode* head;
    LinkedListNode* tail;
    size_t size;
};
```

**Constructor**:
```flux
LinkedList()  // Creates empty list
```

**Core Methods**:

| Method | Returns | Description |
|--------|---------|-------------|
| `get_size()` | `size_t` | Get number of nodes |
| `is_empty()` | `bool` | Check if list is empty |
| `push_front(void* item)` | `bool` | Add item to front |
| `push_back(void* item)` | `bool` | Add item to back |
| `pop_front()` | `void*` | Remove and return first item |
| `pop_back()` | `void*` | Remove and return last item |
| `peek_front()` | `void*` | Get first item without removing |
| `peek_back()` | `void*` | Get last item without removing |
| `get(size_t index)` | `void*` | Get item at index (O(n)) |
| `remove_at(size_t index)` | `bool` | Remove item at index |
| `clear()` | `void` | Remove all nodes |

**Example**:
```flux
LinkedList list;

list.push_back((void*)1);
list.push_front((void*)2);
list.push_back((void*)3);

void* first = list.pop_front();  // Returns (void*)2
void* last = list.peek_back();   // Returns (void*)3 (doesn't remove)
```

---

#### Stack

**Purpose**: LIFO (Last-In-First-Out) data structure

**Definition**:
```flux
object Stack
{
    LinkedList list;
};
```

**Constructor**:
```flux
Stack()  // Creates empty stack
```

**Methods**:

| Method | Returns | Description |
|--------|---------|-------------|
| `get_size()` | `size_t` | Get number of items |
| `is_empty()` | `bool` | Check if stack is empty |
| `push(void* item)` | `bool` | Push item onto stack |
| `pop()` | `void*` | Pop and return top item |
| `peek()` | `void*` | Get top item without removing |
| `clear()` | `void` | Remove all items |

**Example**:
```flux
Stack stack;

stack.push((void*)10);
stack.push((void*)20);
stack.push((void*)30);

void* top = stack.peek();  // Returns (void*)30
void* val = stack.pop();   // Returns (void*)30
```

---

#### Queue

**Purpose**: FIFO (First-In-First-Out) data structure

**Definition**:
```flux
object Queue
{
    LinkedList list;
};
```

**Constructor**:
```flux
Queue()  // Creates empty queue
```

**Methods**:

| Method | Returns | Description |
|--------|---------|-------------|
| `get_size()` | `size_t` | Get number of items |
| `is_empty()` | `bool` | Check if queue is empty |
| `enqueue(void* item)` | `bool` | Add item to back of queue |
| `dequeue()` | `void*` | Remove and return front item |
| `peek()` | `void*` | Get front item without removing |
| `clear()` | `void` | Remove all items |

**Example**:
```flux
Queue queue;

queue.enqueue((void*)1);
queue.enqueue((void*)2);
queue.enqueue((void*)3);

void* first = queue.dequeue();  // Returns (void*)1
void* next = queue.peek();      // Returns (void*)2
```

---

#### Hash Map (HashMap)

**Purpose**: Key-value store with O(1) average lookup/insert

**Definition**:
```flux
struct HashMapEntry
{
    i64 key;
    void* value;
    HashMapEntry* next;
};

object HashMap
{
    HashMapEntry** buckets;
    size_t bucket_count;
    size_t size;
};
```

**Constructor**:
```flux
HashMap()                // Default: 16 buckets
HashMap(size_t buckets)  // Custom bucket count
```

**Core Methods**:

| Method | Returns | Description |
|--------|---------|-------------|
| `get_size()` | `size_t` | Get number of key-value pairs |
| `is_empty()` | `bool` | Check if map is empty |
| `hash(i64 key)` | `size_t` | Hash function for keys |
| `put(i64 key, void* value)` | `bool` | Insert or update key-value pair |
| `get(i64 key)` | `void*` | Get value by key (NULL if not found) |
| `contains(i64 key)` | `bool` | Check if key exists |
| `remove(i64 key)` | `bool` | Remove key-value pair |
| `clear()` | `void` | Remove all entries |

**Example**:
```flux
HashMap map(32);  // 32 buckets

map.put(100, (void*)0x1000);
map.put(200, (void*)0x2000);

if (map.contains(100))
{
    void* value = map.get(100);  // Returns (void*)0x1000
};

map.remove(200);
```

**Notes**:
- Uses chaining for collision resolution
- Fixed bucket count (no auto-rehashing)
- Hash function: `key % bucket_count`

---

#### Binary Search Tree (BinarySearchTree)

**Purpose**: Sorted tree structure with O(log n) average operations

**Definition**:
```flux
struct BinaryTreeNode
{
    void* payload;
    i64 key;
    BinaryTreeNode* left;
    BinaryTreeNode* right;
    BinaryTreeNode* parent;
};

object BinarySearchTree
{
    BinaryTreeNode* root;
    size_t size;
};
```

**Constructor**:
```flux
BinarySearchTree()  // Creates empty tree
```

**Core Methods**:

| Method | Returns | Description |
|--------|---------|-------------|
| `get_size()` | `size_t` | Get number of nodes |
| `is_empty()` | `bool` | Check if tree is empty |
| `insert(i64 key, void* item)` | `bool` | Insert node (updates if key exists) |
| `find(i64 key)` | `void*` | Find payload by key |
| `contains(i64 key)` | `bool` | Check if key exists |
| `remove(i64 key)` | `bool` | Remove node by key |
| `clear()` | `void` | Remove all nodes |

**Example**:
```flux
BinarySearchTree bst;

bst.insert(50, (void*)0x50);
bst.insert(30, (void*)0x30);
bst.insert(70, (void*)0x70);
bst.insert(20, (void*)0x20);
bst.insert(40, (void*)0x40);

void* val = bst.find(30);  // Returns (void*)0x30

bst.remove(30);
bool exists = bst.contains(30);  // false
```

**Notes**:
- Maintains sorted order by key
- No self-balancing (can degrade to O(n) with sorted input)
- Handles three deletion cases: no children, one child, two children

---

### Collections Best Practices

1. **Memory Management**:
   ```flux
   Array arr;
   void* data = malloc(100);
   arr.push(data);
   // Later, remember to free payloads before clearing
   free(arr.get(0));
   arr.clear();
   ```

2. **Type Safety with Casting**:
   ```flux
   struct MyData { i32 value; };
   
   MyData* data = (MyData*)malloc(sizeof(MyData));
   data.value = 42;
   
   arr.push((void*)data);
   
   MyData* retrieved = (MyData*)arr.get(0);
   i32 val = retrieved.value;  // 42
   ```

3. **Check Return Values**:
   ```flux
   if (!arr.push(item))
   {
       print("Allocation failed!\0");
       return -1;
   };
   ```

4. **Iterator Pattern** (for LinkedList):
   ```flux
   LinkedListNode* node = list.head;
   while (node != (LinkedListNode*)0)
   {
       // Process node.payload
       node = node.next;
   };
   ```

---

## Vectors Library

### redvectors.fx

**Purpose**: 3D and 4D vector mathematics for graphics, physics, and spatial calculations

**Location**: `stdlib/redvectors.fx`

**Namespace**: `standard::vectors`

**Dependencies**:
- `redtypes.fx` - Type definitions
- `redmath.fx` - Math functions (sin, cos, sqrt, etc.)

**Description**:  
The vectors library provides comprehensive 3D and 4D vector operations commonly used in graphics programming, game development, physics simulations, and geometric calculations.

#### Vector Structures

**Vec3** - 3D Vector:
```flux
struct Vec3
{
    float x, y, z;
};
```

**Vec4** - 4D Vector:
```flux
struct Vec4
{
    float x, y, z, w;
};
```

---

#### Vec3 Constructors

```flux
def vec3(float x, float y, float z) -> Vec3
def vec3_zero() -> Vec3           // (0, 0, 0)
def vec3_one() -> Vec3            // (1, 1, 1)
def vec3_up() -> Vec3             // (0, 1, 0)
def vec3_down() -> Vec3           // (0, -1, 0)
def vec3_left() -> Vec3           // (-1, 0, 0)
def vec3_right() -> Vec3          // (1, 0, 0)
def vec3_forward() -> Vec3        // (0, 0, 1)
def vec3_back() -> Vec3           // (0, 0, -1)
```

**Example**:
```flux
Vec3 position = vec3(10.0, 20.0, 30.0);
Vec3 up = vec3_up();
Vec3 origin = vec3_zero();
```

---

#### Vec4 Constructors

```flux
def vec4(float x, float y, float z, float w) -> Vec4
def vec4_zero() -> Vec4                  // (0, 0, 0, 0)
def vec4_one() -> Vec4                   // (1, 1, 1, 1)
def vec4_from_vec3(Vec3 v, float w) -> Vec4  // Extend Vec3 to Vec4
```

**Example**:
```flux
Vec4 quaternion = vec4(0.0, 0.0, 0.0, 1.0);
Vec3 pos = vec3(1.0, 2.0, 3.0);
Vec4 homogeneous = vec4_from_vec3(pos, 1.0);
```

---

#### Arithmetic Operations

**Vec3 Operations**:
```flux
def vec3_add(Vec3 a, Vec3 b) -> Vec3           // Component-wise addition
def vec3_sub(Vec3 a, Vec3 b) -> Vec3           // Component-wise subtraction
def vec3_mul(Vec3 v, float scalar) -> Vec3     // Scalar multiplication
def vec3_div(Vec3 v, float scalar) -> Vec3     // Scalar division
def vec3_negate(Vec3 v) -> Vec3                // Negate all components
def vec3_scale(Vec3 a, Vec3 b) -> Vec3         // Component-wise multiplication
```

**Vec4 Operations**:
```flux
def vec4_add(Vec4 a, Vec4 b) -> Vec4
def vec4_sub(Vec4 a, Vec4 b) -> Vec4
def vec4_mul(Vec4 v, float scalar) -> Vec4
def vec4_div(Vec4 v, float scalar) -> Vec4
def vec4_negate(Vec4 v) -> Vec4
def vec4_scale(Vec4 a, Vec4 b) -> Vec4
```

**Example**:
```flux
Vec3 a = vec3(1.0, 2.0, 3.0);
Vec3 b = vec3(4.0, 5.0, 6.0);

Vec3 sum = vec3_add(a, b);        // (5, 7, 9)
Vec3 scaled = vec3_mul(a, 2.0);   // (2, 4, 6)
Vec3 product = vec3_scale(a, b);  // (4, 10, 18)
```

---

#### Dot and Cross Products

**Dot Product**:
```flux
def vec3_dot(Vec3 a, Vec3 b) -> float
def vec4_dot(Vec4 a, Vec4 b) -> float
```

Returns scalar result: `a.x*b.x + a.y*b.y + a.z*b.z [+ a.w*b.w]`

**Cross Product** (Vec3 only):
```flux
def vec3_cross(Vec3 a, Vec3 b) -> Vec3
```

Returns perpendicular vector following right-hand rule.

**Example**:
```flux
Vec3 a = vec3(1.0, 0.0, 0.0);
Vec3 b = vec3(0.0, 1.0, 0.0);

float dot = vec3_dot(a, b);     // 0.0 (perpendicular)
Vec3 cross = vec3_cross(a, b);  // (0, 0, 1) - points along Z-axis
```

---

#### Length and Normalization

**Vec3**:
```flux
def vec3_length_squared(Vec3 v) -> float    // Faster, no sqrt
def vec3_length(Vec3 v) -> float            // Magnitude
def vec3_normalize(Vec3 v) -> Vec3          // Unit vector
def vec3_distance(Vec3 a, Vec3 b) -> float
def vec3_distance_squared(Vec3 a, Vec3 b) -> float
```

**Vec4**:
```flux
def vec4_length_squared(Vec4 v) -> float
def vec4_length(Vec4 v) -> float
def vec4_normalize(Vec4 v) -> Vec4
def vec4_distance(Vec4 a, Vec4 b) -> float
def vec4_distance_squared(Vec4 a, Vec4 b) -> float
```

**Example**:
```flux
Vec3 v = vec3(3.0, 4.0, 0.0);
float len = vec3_length(v);           // 5.0
Vec3 normalized = vec3_normalize(v);  // (0.6, 0.8, 0.0)

Vec3 p1 = vec3(0.0, 0.0, 0.0);
Vec3 p2 = vec3(3.0, 4.0, 0.0);
float dist = vec3_distance(p1, p2);   // 5.0
```

---

#### Interpolation

**Linear Interpolation (Lerp)**:
```flux
def vec3_lerp(Vec3 a, Vec3 b, float t) -> Vec3
def vec4_lerp(Vec4 a, Vec4 b, float t) -> Vec4
```

**Spherical Linear Interpolation (Slerp)**:
```flux
def vec3_slerp(Vec3 a, Vec3 b, float t) -> Vec3
def vec4_slerp(Vec4 a, Vec4 b, float t) -> Vec4
```

**Example**:
```flux
Vec3 start = vec3(0.0, 0.0, 0.0);
Vec3 end = vec3(10.0, 10.0, 10.0);

Vec3 halfway = vec3_lerp(start, end, 0.5);  // (5, 5, 5)

// For normalized vectors, slerp maintains constant speed
Vec3 dir1 = vec3_normalize(vec3(1.0, 0.0, 0.0));
Vec3 dir2 = vec3_normalize(vec3(0.0, 1.0, 0.0));
Vec3 interpolated = vec3_slerp(dir1, dir2, 0.5);
```

---

#### Projection and Reflection

**Vec3**:
```flux
def vec3_project(Vec3 v, Vec3 onto) -> Vec3    // Project v onto 'onto'
def vec3_reject(Vec3 v, Vec3 from) -> Vec3     // Perpendicular component
def vec3_reflect(Vec3 v, Vec3 normal) -> Vec3  // Reflect across normal
```

**Vec4**:
```flux
def vec4_project(Vec4 v, Vec4 onto) -> Vec4
def vec4_reject(Vec4 v, Vec4 from) -> Vec4
def vec4_reflect(Vec4 v, Vec4 normal) -> Vec4
```

**Example**:
```flux
Vec3 velocity = vec3(5.0, -5.0, 0.0);
Vec3 normal = vec3(0.0, 1.0, 0.0);

// Reflect velocity off horizontal surface
Vec3 reflected = vec3_reflect(velocity, normal);  // (5, 5, 0)

// Project velocity onto ground plane
Vec3 ground_vel = vec3_reject(velocity, normal);  // (5, 0, 0)
```

---

#### Angle Calculations

```flux
def vec3_angle(Vec3 a, Vec3 b) -> float  // Angle in radians
def vec4_angle(Vec4 a, Vec4 b) -> float
```

Returns angle between vectors in range [0, π].

**Example**:
```flux
Vec3 a = vec3(1.0, 0.0, 0.0);
Vec3 b = vec3(0.0, 1.0, 0.0);

float angle = vec3_angle(a, b);  // π/2 (90 degrees)
```

---

#### Min/Max/Clamp

**Vec3**:
```flux
def vec3_min(Vec3 a, Vec3 b) -> Vec3
def vec3_max(Vec3 a, Vec3 b) -> Vec3
def vec3_clamp(Vec3 v, Vec3 min_v, Vec3 max_v) -> Vec3
```

**Vec4**:
```flux
def vec4_min(Vec4 a, Vec4 b) -> Vec4
def vec4_max(Vec4 a, Vec4 b) -> Vec4
def vec4_clamp(Vec4 v, Vec4 min_v, Vec4 max_v) -> Vec4
```

**Example**:
```flux
Vec3 a = vec3(1.0, 5.0, 3.0);
Vec3 b = vec3(2.0, 4.0, 6.0);

Vec3 minimum = vec3_min(a, b);  // (1, 4, 3)
Vec3 maximum = vec3_max(a, b);  // (2, 5, 6)

Vec3 bounds_min = vec3_zero();
Vec3 bounds_max = vec3_one();
Vec3 clamped = vec3_clamp(a, bounds_min, bounds_max);  // (1, 1, 1)
```

---

#### Component Access

**Vec3 Getters/Setters**:
```flux
def vec3_get_x(Vec3 v) -> float
def vec3_get_y(Vec3 v) -> float
def vec3_get_z(Vec3 v) -> float

def vec3_set_x(Vec3* v, float x) -> void
def vec3_set_y(Vec3* v, float y) -> void
def vec3_set_z(Vec3* v, float z) -> void
```

**Vec4 Getters/Setters**:
```flux
def vec4_get_x(Vec4 v) -> float
def vec4_get_y(Vec4 v) -> float
def vec4_get_z(Vec4 v) -> float
def vec4_get_w(Vec4 v) -> float

def vec4_set_x(Vec4* v, float x) -> void
def vec4_set_y(Vec4* v, float y) -> void
def vec4_set_z(Vec4* v, float z) -> void
def vec4_set_w(Vec4* v, float w) -> void
```

---

#### Rotation (Vec3)

```flux
def vec3_rotate_x(Vec3 v, float angle) -> Vec3  // Rotate around X-axis
def vec3_rotate_y(Vec3 v, float angle) -> Vec3  // Rotate around Y-axis
def vec3_rotate_z(Vec3 v, float angle) -> Vec3  // Rotate around Z-axis
```

Angles in radians. Uses rotation matrices.

**Example**:
```flux
Vec3 v = vec3(1.0, 0.0, 0.0);

// Rotate 90 degrees (π/2 radians) around Z-axis
float angle = 1.57079632679;  // π/2
Vec3 rotated = vec3_rotate_z(v, angle);  // Approximately (0, 1, 0)
```

---

#### Advanced Operations

**Barycentric Coordinates**:
```flux
def vec3_barycentric(Vec3 a, Vec3 b, Vec3 c, float u, float v) -> Vec3
```

Compute point in triangle using barycentric coordinates.

**Triple Product**:
```flux
def vec3_triple_product(Vec3 a, Vec3 b, Vec3 c) -> float
```

Returns `a · (b × c)` - volume of parallelepiped.

**Absolute Value**:
```flux
def vec3_abs(Vec3 v) -> Vec3
def vec4_abs(Vec4 v) -> Vec4
```

**Example**:
```flux
Vec3 a = vec3(0.0, 0.0, 0.0);
Vec3 b = vec3(1.0, 0.0, 0.0);
Vec3 c = vec3(0.0, 1.0, 0.0);

// Get point at center of triangle
Vec3 center = vec3_barycentric(a, b, c, 0.33, 0.33);

// Calculate volume
float volume = vec3_triple_product(a, b, c);
```

---

### Vectors Best Practices

1. **Normalize Before Dot Product for Angles**:
   ```flux
   Vec3 a_norm = vec3_normalize(a);
   Vec3 b_norm = vec3_normalize(b);
   float dot = vec3_dot(a_norm, b_norm);  // Result in range [-1, 1]
   ```

2. **Use Squared Distance for Comparisons**:
   ```flux
   // Faster - avoids sqrt
   float dist_sq = vec3_distance_squared(p1, p2);
   if (dist_sq < threshold * threshold)
   {
       // Points are close
   };
   ```

3. **Check for Zero Vectors**:
   ```flux
   Vec3 v = get_direction();
   float len_sq = vec3_length_squared(v);
   if (len_sq > 0.000001)  // Not zero
   {
       v = vec3_normalize(v);
   };
   ```

4. **Physics Example** - Bounce:
   ```flux
   Vec3 velocity = vec3(10.0, -5.0, 0.0);
   Vec3 normal = vec3(0.0, 1.0, 0.0);
   
   // Bounce with 80% energy retention
   Vec3 reflected = vec3_reflect(velocity, normal);
   Vec3 new_velocity = vec3_mul(reflected, 0.8);
   ```

5. **Graphics Example** - Camera:
   ```flux
   Vec3 camera_pos = vec3(0.0, 5.0, -10.0);
   Vec3 target_pos = vec3(0.0, 0.0, 0.0);
   
   Vec3 forward = vec3_normalize(vec3_sub(target_pos, camera_pos));
   Vec3 world_up = vec3_up();
   Vec3 right = vec3_normalize(vec3_cross(forward, world_up));
   Vec3 up = vec3_cross(right, forward);
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

// Collections
#import "redcollections.fx";

// Vectors
#import "redvectors.fx";
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

// Collections
#import "redcollections.fx";
using standard::collections;
Array myArray;

// Vectors
#import "redvectors.fx";
using standard::vectors;
Vec3 position = vec3(1.0, 2.0, 3.0);
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
- Entry point: `_start()` â†’ `FRTStartup()`

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
- Collections library (Array, LinkedList, Stack, Queue, HashMap, BinarySearchTree)
- Vectors library (3D/4D vector mathematics)

---

## Contributing

The Flux Standard Library is part of the Flux language project. For contributions, bug reports, or questions, please visit the [Flux Discord server](https://discord.gg/RAHjbYuNUc).

---

## License

This documentation describes the Flux Standard Library as part of the Flux programming language project.

---

*This documentation is current as of the Flux reduced specification implementation (v1.0, February 2026). For the most up-to-date information, please refer to the official Flux language repository and Discord community.*