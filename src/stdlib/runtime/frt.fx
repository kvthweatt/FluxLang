// Translated from the Microsoft C runtime into Flux.
// Certain functions totally eliminated such as string methods.
// strcpy() deserved to be removed long ago.
//
// That being said, welcome to Flux.
// Copyright (C) 2026 Karac Thweatt
//
// Search "TODO" for things to do.
//
// frt.fx - Minimal C Runtime Replacement for Flux
// This file replaces CRT dependencies for Windows/Linux/macOS

//import "io.fx";

if(_FLUX_VER > 1)
{
};

if(!def(_INC_FRT))
{
	global def _INC_FRT 1;
};

if(!def(_FRTBLD))
{
	//using standard::io::print;
	//print( "Use of Flux runtime library internal header file.");
};

if(def(_M_MRX000) or def(_M_ALPHA) or def(_M_PPC))
{
	global def UNALIGNED 1;
}
else
{
	global def UNALIGNED 1;
};

if(def(_M_IX86))
{
	def REG1    1;
	def REG2    1;
	def REG3    1;
	def REG4    0;
	def REG5    0;
	def REG6    0;
	def REG7    0;
	def REG8    0;
	def REG9    0;
}
elif (def(_M_MRX000) or def(_M_ALPHA) or def(_M_PPC))
{
	def REG1    1;
	def REG2    1;
	def REG3    1;
	def REG4    1;
	def REG5    1;
	def REG6    1;
	def REG7    1;
	def REG8    1;
	def REG9    1;
}
elif (def(_M_M68K) or def(_M_MPPC))
{

	def REG1    0;
	def REG2    0;
	def REG3    0;
	def REG4    0;
	def REG5    0;
	def REG6    0;
	def REG7    0;
	def REG8    0;
	def REG9    0;
}
else
{
	//using standard::io::print;
	//print("Machine register set not defined");

	def REG1    0;
	def REG2    0;
	def REG3    0;
	def REG4    0;
	def REG5    0;
	def REG6    0;
	def REG7    0;
	def REG8    0;
	def REG9    0;
};

// ============ GLOBAL SYMBOLS ============
namespace __frt
{
    // Floating point usage indicator
    const int _fltused = 0x9875;
    
    // Heap base pointer
    void* __heap_base = void;
    
    // Standard file descriptors
    const int STDIN_FD = 0;
    const int STDOUT_FD = 1;
    const int STDERR_FD = 2;
};

// ============ WINDOWS API DECLARATIONS ============
if(def(WINDOWS))
{
    namespace __winapi
    {
        // Kernel32 functions
        //int{}* GetProcessHeap() -> void*;
        //def* HeapAlloc(void* hHeap, unsigned data{32} dwFlags, size_t dwBytes) -> void*;
        //def* HeapFree(void* hHeap, unsigned data{32} dwFlags, void* lpMem) -> int;
        //def* ExitProcess(unsigned data{32} uExitCode) -> void;
        //def* GetStdHandle(unsigned data{32} nStdHandle) -> void*;
        //def* WriteFile(void* hFile, void* lpBuffer, unsigned data{32} nNumberOfBytesToWrite, unsigned data{32}* lpNumberOfBytesWritten, void* lpOverlapped) -> int;
        //def* ReadFile(void* hFile, void* lpBuffer, unsigned data{32} nNumberOfBytesToRead, unsigned data{32}* lpNumberOfBytesRead, void* lpOverlapped) -> int;
        
        // NTDLL functions (for direct syscalls)
        //def* NtAllocateVirtualMemory(void* ProcessHandle, void** BaseAddress, unsigned data{32} ZeroBits, size_t* RegionSize, unsigned data{32} AllocationType, unsigned data{32} Protect) -> unsigned data{32};
        
        // Constants
        const unsigned data{32} HEAP_ZERO_MEMORY  = 0x00000008;
        const unsigned data{32} STD_INPUT_HANDLE  = -10;
        const unsigned data{32} STD_OUTPUT_HANDLE = -11;
        const unsigned data{32} STD_ERROR_HANDLE  = -12;
    };
};

// ============ STACK PROTECTION ============
def __chkstk() -> void
{
    // Stack checking function - Windows x64
    volatile asm
    {
        // Save registers we'll use
        pushq   %rax
        pushq   %rcx
        
        // Get the allocation size (passed in RCX)
        movq    %rcx, %rax
        
        // Current stack pointer
        leaq    24(%rsp), %rcx    // 24 = 16 (saved RCX,RAX) + 8 (return address)
        
        // Check if allocation > 4KB
        cmpq    $4096, %rax
        jb      .chkstk_small
        
    .chkstk_loop:
        // Probe each 4KB page
        subq    $4096, %rcx
        testq   %rcx, (%rcx)      // Touch the page
        
        subq    $4096, %rax
        cmpq    $4096, %rax
        ja      .chkstk_loop
        
    .chkstk_small:
        // Handle remaining bytes
        subq    %rax, %rcx
        testq   %rcx, (%rcx)      // Touch the final page
        
        // Restore registers
        popq    %rcx
        popq    %rax
        
        ret
    };
    return void;
};

def __alloca_probe() -> void
{
    // Alias for __chkstk
    return __chkstk();
};

// ============ FLOATING POINT INITIALIZATION ============
def __fpmath_init() -> void
{
    // Initialize x87 FPU
    volatile asm
    {
        fwait           // Wait for any pending FP operations
        fninit          // Initialize FPU to default state
        
        // Set x87 control word (default: 0x037F)
        // Precision: 64-bit, Rounding: nearest, Exception mask: all
        pushq   %rax
        movw    $0x037F, %ax
        pushq   %rax
        fldcw   (%rsp)
        popq    %rax
        popq    %rax
        
        // Initialize SSE control/status register (default: 0x1F80)
        // Exception mask: all, Rounding: nearest, FTZ/DAZ: off
        pushq   %rax
        movq    $0x1F80, %rax
        movq    %rax, %xmm0
        ldmxcsr (%rsp)
        popq    %rax
    };
    return void;
};

// ============ HEAP MANAGEMENT ============
namespace __heap
{
    if(def(WINDOWS))
    {
        def heap_init() -> void
        {
            // Get the process heap
            volatile asm
            {
                subq    $40, %rsp
                call    GetProcessHeap
                addq    $40, %rsp
                movq    %rax, __heap_base
            };
            return void;
        };
        // Looking for alloc() ?  Try heap()
        // Looking for free() ?   Try (void)
    }
    else
    {  // Linux/macOS
    
        def heap_init() -> void
        {
            // Linux/macOS uses brk/sbrk or mmap
            // We'll use mmap for simplicity
            return void;
        };
    };
    
    def realloc(void* ptr, size_t new_size) -> void*
    {
        if (ptr == void) { heap void* ptr; return ptr; };
        
        if(def(WINDOWS))
        {
            void* result = void;
            volatile asm
            {
                // Note: Windows HeapReAlloc would be needed
                // For now, implement simple alloc/copy/free
                // In practice, you'd call HeapReAlloc
                pushq   %rbx
                pushq   %rsi
                pushq   %rdi
                
                // Save parameters
                movq    ptr, %rbx
                movq    new_size, %rsi
                
                // Allocate new memory
                movq    __heap_base, %rcx
                movq    $0x00000008, %rdx    // HEAP_ZERO_MEMORY
                movq    %rsi, %r8
                subq    $40, %rsp
                call    HeapAlloc
                addq    $40, %rsp
                movq    %rax, %rdi           // Save new pointer
                
                // TODO: Copy old data (need to know old size)
                // For now, just return new allocation
                
                // Free old memory
                movq    __heap_base, %rcx
                xorq    %rdx, %rdx
                movq    %rbx, %r8
                subq    $40, %rsp
                call    HeapFree
                addq    $40, %rsp
                
                movq    %rdi, result         // Return new pointer
                
                popq    %rdi
                popq    %rsi
                popq    %rbx
            };
            return result;
        }
        else
        {
            // Linux: use mremap or implement alloc/copy/free
            heap heap_new_size = new_size;
            heap void* new_ptr = @heap_new_size;
            (void)ptr;
            return new_ptr;
        };
    };
};

// ============ ENTRY POINTS ============
if(def(WINDOWS))
{
    global def mainCRTStartup() -> void
    {
        // Just a symbol to satisfy Windows.
        // Windows console entry point
        
        // Initialize floating point
        __fpmath_init();
        
        // Initialize heap
        using __heap::heap_init;
        heap_init();
        
        // TODO: Call static constructors (if any)
        // __initterm(__xi_a, __xi_z);
        
        // Get command line
        // TODO: Parse command line to argc/argv
        
        // Call main
        int exit_code = main();
        
        // TODO: Call static destructors (if any)
        // __initterm(__xc_a, __xc_z);
        
        // Exit process
        volatile asm
        {
            movq    exit_code, %rcx
            subq    $40, %rsp
            call    ExitProcess
            addq    $40, %rsp
        };
        
        // Never reached
        return void;
    };

    global def WinMainCRTStartup() -> void
    {
        // Just a symbol to satisfy Windows.
        // Windows GUI entry point (similar but different subsystem)
        return mainFRTStartup();
    };

    global def mainFRTStartup() -> void
    {
        // Initialize floating point
        __fpmath_init();
        
        // Initialize heap
        using __heap::heap_init;
        heap_init();
        
        // Call main
        int exit_code = main();
        
        // Exit process
        volatile asm
        {
            movq    exit_code, %rcx
            subq    $40, %rsp
            call    ExitProcess
            addq    $40, %rsp
        };
        
        // Never reached
        return void;
    };
};

if(def(LINUX))
{
    global def _start() -> void
    {
        // Linux x64 entry point
        
        // Clear frame pointer (mark end of stack frames)
        volatile asm
        {
            xorq    %rbp, %rbp
        };
        
        // Initialize floating point
        __fpmath_init();
        
        // Initialize heap
        using __heap::heap_init;
        heap_init();
        
        // Get argc, argv, envp from stack
        int argc;
        //char** argv; // <-- ADD DOUBLE PTR SUPPORT
        //char** envp;
        
        volatile asm
        {
            movq    (%rsp), %rax        // argc
            movq    %rax, argc
            leaq    8(%rsp), %rax       // argv
            movq    %rax, argv
            leaq    8(%rax, %rax, 8), %rbx  // envp = argv + argc*8 + 8
            movq    %rbx, envp
        };
        
        // Align stack to 16 bytes (System V ABI requirement)
        volatile asm
        {
            andq    $-16, %rsp
        };
        
        // TODO: Call global constructors (if any)
        
        // Call main with arguments
        int exit_code = main(argc, argv, envp);
        
        // TODO: Call global destructors (if any)
        
        // Exit with main's return code
        volatile asm
        {
            movq    exit_code, %rdi     // Exit code
            movq    $60, %rax           // syscall: exit
            syscall
        };
        
        // Never reached
        return void;
    };
};

if(def(MACOS))
{
    global def start() -> void
    {
        // macOS entry point (similar to Linux but different)
        return _start();
    };
};

// ============ MEMORY SET/COPY FUNCTIONS ============
def memset(void* dest, int ch, size_t count) -> void*
{
    void* ret = dest;
    byte* d = (byte*)dest;
    byte c = (byte)ch;
    
    // Simple byte-by-byte memset
    for (size_t i = 0; i < count; i++)
    {
        d[i] = c;
    };
    
    return ret;
};

def memcpy(void* dest, void* src, size_t count) -> void*
{
    void* ret = dest;
    byte* d = (byte*)dest;
    byte* s = (byte*)src;
    
    // Simple byte-by-byte memcpy
    for (size_t i = 0; i < count; i++)
    {
        d[i] = s[i];
    };
    
    return ret;
};

def memmove(void* dest, void* src, size_t count) -> void*
{
    void* ret = dest;
    byte* d = (byte*)dest;
    byte* s = (byte*)src;
    
    if (d < s)
    {
        // Copy forward
        for (size_t i = 0; i < count; i++)
        {
            d[i] = s[i];
        };
    }
    elif (d > s)
    {
        // Copy backward
        for (size_t i = count; i > 0; i--)
        {
            d[i-1] = s[i-1];
        };
    };
    
    return ret;
};

def memcmp(void* ptr1, void* ptr2, size_t count) -> int
{
    byte* p1 = (byte*)ptr1;
    byte* p2 = (byte*)ptr2;
    
    for (size_t i = 0; i < count; i++)
    {
        if (p1[i] != p2[i])
        {
            return (int)p1[i] - (int)p2[i];
        };
    };
    
    return 0;
};

// ============ STRING FUNCTIONS ============
def strlen(char* str) -> size_t
{
    // Check a null-terminated string
    size_t len = 0;
    while (str[len] != 0)
    {
        len++;
    };
    return len;
};

// ============ TERMINATION FUNCTIONS ============
def abort() -> void
{
    if(def(WINDOWS))
    {
        // Terminate process with error code 3
        volatile asm
        {
            movq    $3, %rcx
            subq    $40, %rsp
            call    ExitProcess
            addq    $40, %rsp
        };
    }
    else
    {
        // Linux/macOS: abort signal
        volatile asm
        {
            movq    $6, %rdi    // SIGABRT
            movq    $37, %rax   // syscall: kill (getpid(), SIGABRT)
            syscall
            
            // If kill returns, try exit with error
            movq    $1, %rdi
            movq    $60, %rax
            syscall
        };
    };
    
    // Never reached
    return void;
};

def exit(int status) -> void
{
    if(def(WINDOWS))
    {
        volatile asm
        {
            movq    status, %rcx
            subq    $40, %rsp
            call    ExitProcess
            addq    $40, %rsp
        };
    }
    else
    {
        volatile asm
        {
            movq    status, %rdi
            movq    $60, %rax
            syscall
        };
    };
    
    // Never reached
    return void;
};

// ============ BASIC I/O (Fallback) ============
namespace __frt_io
{
    if(def(WINDOWS))
    {
        def write(int fd, void* buf, size_t count) -> size_t
        {
            if (fd != STDOUT_FD && fd != STDERR_FD) {return 0;};
                
            unsigned data{32} written = 0;
            volatile asm
            {
                // Get standard handle
                movq    $-11, %rcx      // STD_OUTPUT_HANDLE
                subq    $40, %rsp
                call    GetStdHandle
                addq    $40, %rsp
                movq    %rax, %rcx      // hFile
                
                // WriteFile
                movq    buf, %rdx       // lpBuffer
                movq    count, %r8
                andq    $0xFFFFFFFF, %r8  // Ensure 32-bit
                leaq    written, %r9    // lpNumberOfBytesWritten
                subq    $40, %rsp
                movq    $0, 32(%rsp)    // lpOverlapped = NULL
                call    WriteFile
                addq    $40, %rsp
            };
            
            return written;
        };
        
        def read(int fd, void* buf, size_t count) -> size_t
        {
            if (fd != STDIN_FD) {return 0;};
                
            unsigned data{32} read = 0;
            volatile asm
            {
                // Get standard handle
                movq    $-10, %rcx      // STD_INPUT_HANDLE
                subq    $40, %rsp
                call    GetStdHandle
                addq    $40, %rsp
                movq    %rax, %rcx      // hFile
                
                // ReadFile
                movq    buf, %rdx       // lpBuffer
                movq    count, %r8
                andq    $0xFFFFFFFF, %r8  // Ensure 32-bit
                leaq    read, %r9       // lpNumberOfBytesRead
                subq    $40, %rsp
                movq    $0, 32(%rsp)    // lpOverlapped = NULL
                call    ReadFile
                addq    $40, %rsp
            };
            
            return read;
        };
    }
    else
    {
        def write(int fd, void* buf, size_t count) -> size_t
        {
            size_t result;
            volatile asm
            {
                movq    $1, %rax        // syscall: write
                movq    fd, %rdi
                movq    buf, %rsi
                movq    count, %rdx
                syscall
                movq    %rax, result
            };
            return result;
        };
        
        def read(int fd, void* buf, size_t count) -> size_t
        {
            size_t result;
            volatile asm
            {
                movq    $0, %rax        // syscall: read
                movq    fd, %rdi
                movq    buf, %rsi
                movq    count, %rdx
                syscall
                movq    %rax, result
            };
            return result;
        };
    };
};

// ============ COMPILER-SPECIFIC HELPERS ============
def __security_check_cookie(void* cookie) -> void
{
    // Stack cookie check - minimal implementation
    // In a real implementation, this would verify the stack canary
    if (cookie == void)
    {
        abort();
    };
    return void;
};

def __report_gsfailure() -> void
{
    // Buffer security check failed
    abort();
};

// ============ MATH FUNCTIONS (Minimal) ============
namespace __frt_math
{
    def fabs(double x) -> double
    {
        volatile asm
        {
            // Clear sign bit
            pushq   %rax
            movq    x, %rax
            andq    $0x7FFFFFFFFFFFFFFF, %rax
            movq    %rax, x
            popq    %rax
        };
        return x;
    };
    
    def sqrt(double x) -> double
    {
        double result;
        volatile asm
        {
            sqrtsd  x, %xmm0
            movsd   %xmm0, result
        };
        return result;
    };
};

// ============ TLS SUPPORT (Minimal) ============
if(def(WINDOWS))
{
    def __dyn_tls_init(void* instance, unsigned data{32} reason, void* reserved) -> int
    {
        // Minimal TLS callback
        return 1;  // Success
    };
};

// ============ EXPORT/IMPORT DECORATORS ============
// These help with linking
if(def(WINDOWS))
{
    global def DLLEXPORT 1;//__declspec(dllexport);
    global def DLLIMPORT 1;//__declspec(dllimport);
    global def STDCALL 1;//__stdcall;
}
else
{
    global def DLLEXPORT 1;
    global def DLLIMPORT 1;
    global def STDCALL 1;
};

// ============ FORCE SYMBOL REFERENCES ============
// Ensure certain symbols are included in the link
const int __force_link_frt = 1;

// ============ MODULE INITIALIZATION ============
// This function is called automatically when the runtime loads
def __frt_init() -> void
{
    // NEVER DO ANYTHING HERE
    // DO NOT ADD CODE TO THIS FUNCTION
    // WHY ARE YOU STILL HERE
    // GO AWAY
    return void;
};