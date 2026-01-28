// ============ COMMON C RUNTIME FUNCTIONS TRANSLATED TO FLUX ============
// Functions that exist in frt.fx have been excluded from this translation.
// All assembly uses AT&T syntax for LLVM integration with proper clobber lists.

// ============ STRING FUNCTIONS ============

def strncpy(char* dest, char* src, size_t n) -> char*
{
    size_t i = 0;
    while (i < n && src[i] != 0)
    {
        dest[i] = src[i];
        i++;
    };
    
    // Pad with zeros if needed
    while (i < n)
    {
        dest[i] = 0;
        i++;
    };
    
    return dest;
};

def strncmp(char* str1, char* str2, size_t n) -> int
{
    for (size_t i = 0; i < n; i++)
    {
        if (str1[i] != str2[i])
        {
            return (int)str1[i] - (int)str2[i];
        };
        if (str1[i] == 0)
        {
            return 0;
        };
    };
    return 0;
};

def strchr(char* str, int ch) -> char*
{
    size_t i = 0;
    while (str[i] != 0)
    {
        if (str[i] == ch)
        {
            return @str[i];
        };
        i++;
    };
    return void;
};

def strrchr(char* str, int ch) -> char*
{
    char* result = void;
    size_t i = 0;
    
    while (str[i] != 0)
    {
        if (str[i] == ch)
        {
            result = @str[i];
        };
        i++;
    };
    
    return result;
};

def strstr(char* haystack, char* needle) -> char*
{
    if (needle[0] == 0)
    {
        return haystack;
    };
    
    size_t i = 0;
    while (haystack[i] != 0)
    {
        size_t j = 0;
        while (needle[j] != 0 && haystack[i + j] == needle[j])
        {
            j++;
        };
        
        if (needle[j] == 0)
        {
            return @haystack[i];
        };
        i++;
    };
    
    return void;
};

// ============ MEMORY FUNCTIONS ============

def memchr(void* ptr, int ch, size_t n) -> void*
{
    byte* p = (byte*)ptr;
    for (size_t i = 0; i < n; i++)
    {
        if (p[i] == ch)
        {
            return @p[i];
        };
    };
    return void;
};

// ============ MATH FUNCTIONS ============

namespace __crt_math
{
    def abs(int x) -> int
    {
        return (x < 0) ? -x : x;
    };
    
    def labs(long x) -> long
    {
        return (x < 0) ? -x : x;
    };
    
    def fabsf(float x) -> float
    {
        float result;
        volatile asm
        {
            "andps   %1, %0"
        }   : "=x"(result)
            : "x"(x), "0" (0x7FFFFFFF)
            : "xmm0";

        return result;
    };
    
    def ceil(double x) -> double
    {
        double result;
        volatile asm
        {
            "roundsd $2, %1, %0"
        }   : "=x"(result)
            : "x"(x)
            : "xmm0";

        return result;
    };
    
    def floor(double x) -> double
    {
        double result;
        volatile asm
        {
            "roundsd $1, %1, %0"
        }   : "=x"(result)
            : "x"(x)
            : "xmm0";

        return result;
    };
    
    def pow(double x, double y) -> double
    {
        double result;
        volatile asm
        {
            "movsd   %1, %%xmm0"
            "movsd   %2, %%xmm1"
            "call    pow"
            "movsd   %%xmm0, %0"
        }   : "=m"(result)
            : "m"(x), "m"(y)
            : "xmm0", "xmm1", "rax", "rcx", "rdx", "r8", "r9", "r10", "r11";

        return result;
    };
    
    def sin(double x) -> double
    {
        double result;
        volatile asm
        {
            "movsd   %1, %%xmm0"
            "call    sin"
            "movsd   %%xmm0, %0"
        }   : "=m"(result)
            : "m"(x)
            : "xmm0", "rax", "rcx", "rdx", "r8", "r9", "r10", "r11";

        return result;
    };
    
    def cos(double x) -> double
    {
        double result;
        volatile asm
        {
            "movsd   %1, %%xmm0"
            "call    cos"
            "movsd   %%xmm0, %0"
        }   : "=m"(result)
            : "m"(x)
            : "xmm0", "rax", "rcx", "rdx", "r8", "r9", "r10", "r11";
        return result;
    };
    
    def tan(double x) -> double
    {
        double result;
        volatile asm
        {
            "movsd   %1, %%xmm0"
            "call    tan"
            "movsd   %%xmm0, %0"
        }   : "=m"(result)
            : "m"(x)
            : "xmm0", "rax", "rcx", "rdx", "r8", "r9", "r10", "r11";

        return result;
    };
    
    def log(double x) -> double
    {
        double result;
        volatile asm
        {
            "movsd   %1, %%xmm0"
            "call    log"
            "movsd   %%xmm0, %0"
        }   : "=m"(result)
            : "m"(x)
            : "xmm0", "rax", "rcx", "rdx", "r8", "r9", "r10", "r11";

        return result;
    };
    
    def log10(double x) -> double
    {
        double result;
        volatile asm
        {
            "movsd   %1, %%xmm0"
            "call    log10"
            "movsd   %%xmm0, %0"
        }   : "=m"(result)
            : "m"(x)
            : "xmm0", "rax", "rcx", "rdx", "r8", "r9", "r10", "r11";

        return result;
    };
    
    def exp(double x) -> double
    {
        double result;
        volatile asm
        {
            "movsd   %1, %%xmm0"
            "call    exp"
            "movsd   %%xmm0, %0"
        }   : "=m"(result)
            : "m"(x)
            : "xmm0", "rax", "rcx", "rdx", "r8", "r9", "r10", "r11";

        return result;
    };
};

// ============ CHARACTER CLASSIFICATION ============

def isalpha(int c) -> int
{
    return ((c >= "a" && c <= "z") || (c >= "A" && c <= "Z")) ? 1 : 0;
};

def isdigit(int c) -> int
{
    return (c >= "0" && c <= "9") ? 1 : 0;
};

def isalnum(int c) -> int
{
    return (isalpha(c) || isdigit(c)) ? 1 : 0;
};

def isspace(int c) -> int
{
    return (c == " " || c == "\t" || c == "\n" || c == "\v" || c == "\f" || c == "\r") ? 1 : 0;
};

def isupper(int c) -> int
{
    return (c >= "A" && c <= "Z") ? 1 : 0;
};

def islower(int c) -> int
{
    return (c >= "a" && c <= "z") ? 1 : 0;
};

def toupper(int c) -> int
{
    if (c >= "a" && c <= "z")
    {
        return c - ("a" - "A");
    };
    return c;
};

def tolower(int c) -> int
{
    if (c >= "A" && c <= "Z")
    {
        return c + ("a" - "A");
    };
    return c;
};

// ============ FORMATTED I/O FUNCTIONS ============

namespace __crt_stdio
{
    def printf(string fmt) -> int
    {
        // Note: This is a simplified implementation
        // A full implementation would need to parse format specifiers
        return __frt_io::write(1, fmt, strlen(fmt));
    };
    
    def sprintf(char* buffer, string fmt) -> int
    {
        // Simplified: just copy the format string
        // Full implementation would require format parsing
        size_t len = strlen(fmt);
        memcpy(buffer, fmt, len);
        buffer[len] = 0;
        return (int)len;
    };
    
    def snprintf(char* buffer, size_t n, string fmt) -> int
    {
        size_t len = strlen(fmt);
        if (len >= n)
        {
            len = n - 1;
        };
        memcpy(buffer, fmt, len);
        buffer[len] = 0;
        return (int)len;
    };
    
    def sscanf(char* str, string fmt) -> int
    {
        // Simplified implementation
        // Full implementation would parse format specifiers
        (void)str;
        (void)fmt;
        return 0;
    };
};


// ============ RANDOM NUMBER GENERATION ============

namespace __crt_rand
{
    unsigned data{32} _rand_state = 1;
    
    def rand() -> int
    {
        // Linear congruential generator
        _rand_state = _rand_state * 1103515245 + 12345;
        return (int)((_rand_state / 65536) % 32768);
    };
    
    def srand(unsigned data{32} seed) -> void
    {
        _rand_state = seed;
        return void;
    };
};

// ============ ATOMIC OPERATIONS ============

def atomic_exchange(volatile int* ptr, int value) -> int
{
    int result;
    volatile asm
    {
        "xchgl   %1, %0"
    }   : "=r"(result), "+m"(*ptr)
        : "0"(value)
        : "memory";

    return result;
};

def atomic_compare_exchange(volatile int* ptr, int expected, int desired) -> bool
{
    char result;
    volatile asm
    {
        "lock"
        "cmpxchgl   %2, %1"
        "sete       %0"
    }   : "=q"(result), "+m"(*ptr), "+a"(expected)
        : "r"(desired)
        : "memory";

    return (bool)result;
};

def atomic_fetch_add(volatile int* ptr, int value) -> int
{
    int result;
    volatile asm
    {
        "lock"
        "xaddl   %0, %1"
    }   : "=r"(result), "+m"(*ptr)
        : "0"(value)
        : "memory";

    return result;
};

// ============ TIME FUNCTIONS ============

namespace __crt_time
{
    struct timeval {
        unsigned data{64} tv_sec;
        unsigned data{64} tv_usec;
    };
    
    def gettimeofday(timeval* tv, void* tz) -> int
    {
        (void)tz;  // timezone parameter is obsolete
        
//#ifdef __WINDOWS__
            // Windows implementation using GetSystemTimeAsFileTime
            unsigned data{64} ft;
            volatile asm
            {
                "subq    $40, %%rsp"
                "leaq    %1, %%rcx"
                "call    GetSystemTimeAsFileTime"
                "addq    $40, %%rsp"
            }   : "=m"(ft)
                : "m"(ft)
                : "rcx", "rax", "r10", "r11", "memory";
            
            // Convert Windows FILETIME to Unix time
            tv.tv_sec = (ft - 116444736000000000) / 10000000;
            tv.tv_usec = ((ft - 116444736000000000) % 10000000) / 10;
//#else
            // Linux/macOS implementation
            volatile asm
            {
                "movq    $96, %%rax"      // syscall: gettimeofday
                "movq    %1, %%rdi"
                "movq    %2, %%rsi"
                "syscall"
                "movl    %%eax, %0"
            }   : "=r"(result)
                : "r"(tv), "r"(tz)
                : "rax", "rdi", "rsi", "rdx", "r10", "r8", "r9", "memory";
//#endif;
        
        return result;
    };
    
    def clock() -> unsigned data{64}
    {
        unsigned data{64} result = 0;
        
//#ifdef __WINDOWS__
            volatile asm
            {
                "subq    $40, %%rsp"
                "call    GetTickCount64"
                "addq    $40, %%rsp"
                "movq    %%rax, %0"
            }   : "=r"(result)
                :
                : "rax", "rcx", "rdx", "r8", "r9", "r10", "r11", "memory";

            result *= 1000;  // Convert to microseconds
//#else
            // Use gettimeofday on Unix-like systems
            timeval tv;
            gettimeofday(@tv, void);
            result = tv.tv_sec * 1000000 + tv.tv_usec;
//#endif;
        
        return result;
    };
};

// ============ ENVIRONMENT FUNCTIONS ============

def getenv(char* name) -> char*
{
    // Simplified implementation - would need to access actual environment
    (void)name;
    return void;
};

def system(char* command) -> int
{
    if (command == void)
    {
        // Check if shell is available
        return 1;
    };
    
    // Note: Full implementation would need to spawn a process
    // This is platform-specific
    return -1;
};

// ============ TERMINAL CONTROL ============

def atexit(void *func) -> int
{
    // Simplified: would need to maintain a list of exit functions
    (void)func;
    return 0;
};

def on_exit(void* func, void* arg) -> int
{
    (void)func;
    (void)arg;
    return 0;
};

// ============ SIGNAL HANDLING (MINIMAL) ============

def signal(int sig, void* handler) -> void*
{
    // Simplified implementation
    (void)sig;
    (void)handler;
    return void;
};

def raise(int sig) -> int
{
    // Send signal to current process
//#ifdef __WINDOWS__
        // Windows doesn"t have POSIX signals
        return -1;
//#else
        int result;
        volatile asm
        {
            "movq    $62, %%rax"       // syscall: kill (getpid(), sig)
            "movq    $0, %%rdi"        // getpid()
            "movq    %1, %%rsi"        // signal number
            "syscall"
            "movl    %%eax, %0"
        }   : "=r"(result)
            : "r"(sig)
            : "rax", "rdi", "rsi", "rdx", "r10", "r8", "r9", "memory";

        return result;
//#endif;
};

// ============ DYNAMIC MEMORY ============

def calloc(size_t num, size_t size) -> void*
{
    size_t total = num * size;
    void* ptr = malloc(total);
    if (ptr != void)
    {
        memset(ptr, 0, total);
    };
    return ptr;
};

def _msize(void* ptr) -> size_t
{
    // Platform-specific heap size query
    // This is a simplified placeholder
    (void)ptr;
    return 0;
};

// ============ FLOATING POINT CONTROL ============

def _controlfp(unsigned data{32} new, unsigned data{32} mask) -> unsigned data{32}
{
    unsigned data{32} result;
    
    volatile asm
    {
        "stmxcsr  %0"
        "movl     %0, %%eax"
        "andl     %2, %%eax"
        "orl      %1, %%eax"
        "movl     %%eax, %0"
        "ldmxcsr  %0"
    }   : "=m"(result)
        : "r"(new & mask), "r"(~mask)
        : "rax", "memory";
    
    return result;
};

// ============ ERROR HANDLING ============

namespace __crt_error
{
    int errno = 0;
    
    def perror(char* s) -> void
    {
        if (s != void && s[0] != 0)
        {
            __frt_io::write(2, s, strlen(s));
            __frt_io::write(2, ": ", 2);
        };
        
        // Would need error string mapping
        __frt_io::write(2, "Unknown error\n", 14);
        return void;
    };
    
    def strerror(int errnum) -> char*
    {
        // Simplified error message table
        switch (errnum)
        {
            case (0)
            {
                return "Success";
            }
            case (1)
            {
                return "Operation not permitted";
            }
            case (2)
            {
                return "No such file or directory";
            }
            default
            {
                return "Unknown error";
            };
        };
    };
};

// ============ ALIGNED ALLOCATION ============

def _aligned_malloc(size_t size, size_t alignment) -> void*
{
    if (alignment < sizeof(void*))
    {
        alignment = sizeof(void*);
    };
    
    // Calculate total size with padding for alignment and pointer storage
    size_t total = size + alignment + sizeof(void*);
    void* original = malloc(total);
    
    if (original == void)
    {
        return void;
    };
    
    // Calculate aligned pointer
    char* aligned = (char*)original + sizeof(void*);
    aligned += alignment - ((size_t)aligned & (alignment - 1));
    
    // Store original pointer before aligned block
    ((void**)aligned)[-1] = original;
    
    return aligned;
};

def _aligned_free(void* ptr) -> void
{
    if (ptr != void)
    {
        void* original = ((void**)ptr)[-1];
        free(original);
    };
    return void;
};

// ============ THREAD-LOCAL STORAGE ============

//#ifdef __WINDOWS__
    def _tls_get_value(unsigned data{32} index) -> void*
    {
        void* result;
        volatile asm
        {
            "movq    %%gs:0x58, %%rax"  // TEB.ThreadLocalStoragePointer
            "movq    (%%rax,%1,8), %%rax"
            "movq    %%rax, %0"
        }   : "=r"(result)
            : "r"(index)
            : "rax", "memory";

        return result;
    };
//#endif;

// ============ COMPILER INTRINSICS ============

def _rotl(unsigned data{32} value, int shift) -> unsigned data{32}
{
    shift &= 31;
    return (value << shift) | (value >> (32 - shift));
};

def _rotr(unsigned data{32} value, int shift) -> unsigned data{32}
{
    shift &= 31;
    return (value >> shift) | (value << (32 - shift));
};

def _byteswap_ushort(unsigned data{16} value) -> unsigned data{16}
{
    unsigned data{16} result;
    volatile asm
    {
        "rorw    $8, %1"
    }   : "=r"(result)
        : "r"(value)
        : "memory";

    return result;
};

def _byteswap_ulong(unsigned data{32} value) -> unsigned data{32}
{
    unsigned data{32} result;
    volatile asm
    {
        "bswap   %1"
    }   : "=r"(result)
        : "r"(value)
        : "memory";

    return result;
};

def _byteswap_uint64(unsigned data{64} value) -> unsigned data{64}
{
    unsigned data{64} result;
    volatile asm
    {
        "bswap   %1"
    }   : "=r"(result)
        : "r"(value)
        : "memory";

    return result;
};

// ============ STACK ALLOCATION CHECK ============

def _alloca(size_t size) -> void*
{
    // Note: This is typically a compiler intrinsic
    // In Flux, use stack allocation or __chkstk()
    __chkstk();
    
    // Stack allocation using assembly
    void* result;
    volatile asm
    {
        "movq    %%rsp, %%rax"
        "subq    %1, %%rsp"
        "movq    %%rsp, %0"
    }   : "=r"(result)
        : "r"(size)
        : "rax", "memory";
    
    return result;
};

// ============ EXIT HANDLERS ============

def _onexit(void (*func)()) -> int
{
    // Similar to atexit()
    (void)func;
    return 0;
};

// ============ FLOATING POINT STATUS ============

def _statusfp() -> unsigned data{32}
{
    unsigned data{32} result;
    volatile asm
    {
        "stmxcsr  %0"
    }   : "=m"(result)
        :
        : "memory";

    return result;
};

// ============ MEMORY BARRIERS ============

def _ReadWriteBarrier() -> void
{
    volatile asm
    {
        "mfence"
    }   :
        :
        : "memory";

    return void;
};

def _ReadBarrier() -> void
{
    volatile asm
    {
        "lfence"
    }   :
        :
        : "memory";

    return void;
};

def _WriteBarrier() -> void
{
    volatile asm
    {
        "sfence"
    }   :
        :
        : "memory";

    return void;
};

// ============ COMPILER-SPECIFIC ============

def _ReturnAddress() -> void*
{
    void* result;
    volatile asm
    {
        "movq    (%%rbp), %%rax"
        "movq    8(%%rax), %%rax"
        "movq    %%rax, %0"
    }   : "=r"(result)
        :
        : "rax", "memory";

    return result;
};

// ============ DEPRECATED/LEGACY FUNCTIONS ============

def stricmp(char* str1, char* str2) -> int
{
    // Case-insensitive compare (deprecated, use strcasecmp)
    size_t i = 0;
    while (true)
    {
        char c1 = tolower(str1[i]);
        char c2 = tolower(str2[i]);
        
        if (c1 != c2)
        {
            return (int)c1 - (int)c2;
        };
        
        if (c1 == 0)
        {
            return 0;
        };
        
        i++;
    };
};

def strnicmp(char* str1, char* str2, size_t n) -> int
{
    // Case-insensitive compare with length limit
    for (size_t i = 0; i < n; i++)
    {
        char c1 = tolower(str1[i]);
        char c2 = tolower(str2[i]);
        
        if (c1 != c2)
        {
            return (int)c1 - (int)c2;
        };
        
        if (c1 == 0)
        {
            return 0;
        };
    };
    return 0;
};

// ============ UTILITY FUNCTIONS ============

def itoa(int value, char* str, int base) -> char*
{
    if (base < 2 || base > 36)
    {
        str[0] = 0;
        return str;
    };
    
    char* ptr = str;
    char* ptr1 = str;
    char tmp_char;
    int tmp_value;
    
    bool is_negative = false;
    if (value < 0 && base == 10)
    {
        is_negative = true;
        value = -value;
    };
    
    do
    {
        tmp_value = value;
        value /= base;
        *ptr++ = "0123456789abcdefghijklmnopqrstuvwxyz"[tmp_value - value * base];
    } while (value);
    
    if (is_negative)
    {
        *ptr++ = "-";
    };
    
    *ptr-- = 0;
    
    // Reverse string
    while (ptr1 < ptr)
    {
        tmp_char = *ptr;
        *ptr-- = *ptr1;
        *ptr1++ = tmp_char;
    };
    
    return str;
};

def atoi(char* str) -> int
{
    int result = 0;
    int sign = 1;
    size_t i = 0;
    
    // Skip whitespace
    while (isspace(str[i]))
    {
        i++;
    };
    
    // Check sign
    if (str[i] == "-")
    {
        sign = -1;
        i++;
    }
    elif (str[i] == "+")
    {
        i++;
    };
    
    // Convert digits
    while (isdigit(str[i]))
    {
        result = result * 10 + (str[i] - "0");
        i++;
    };
    
    return sign * result;
};

// ============ END OF CRT TRANSLATION ============