#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_RUNTIME
#def FLUX_RUNTIME 1;
#endif;

#ifdef __WIN64__
#def __WIN32__ 0;
#else
#ifndef __WIN32__
#def __WIN32__ 1;
#endif;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

// Import raw functions & builtins
#import "strfuncs.fx";
//
// ---------------------------
//
// Import runtime helpers
#import "ffifio.fx";
//
// ---------------------------
//

#ifndef FLUX_STANDARD_SYSTEM
#import "redsys.fx";
#endif;
#ifndef FLUX_STANDARD_IO
#import "redio.fx";
#endif;

extern
{
    def !!GetCommandLineW() -> wchar*;
    def !!CommandLineToArgvW(wchar* x, int* y) -> wchar**; 
    def !!LocalFree(void* x) -> void*;
    // Note, should be able to declare all comma separated
    // names should not have to be identical, they're just prototypes.
    // Also, issue with type-only specified prototypes, failing
};


// >Mains
def !!main() -> int;
def !!main(int* argc, byte** argv) -> int;
// /Mains

  ///                                       ///
 ///DO NOT REDEFINE THIS FUNCTION SIGNATURE///
///                                       ///
def !!FRTStartup() -> int; // GO AWAY, SHOO
  ///                                       ///
 ///DO NOT REDEFINE THIS FUNCTION SIGNATURE///
///                                       ///

def !!exit(int code) -> void;
def !!exit(int code) -> void
{
#ifdef __WINDOWS__
    volatile asm
    {
        movl $0, %ecx
        movq $$0x002C, %rax
        movq $$-1, %r10
        syscall
    } : : "r"(code) : "rax", "rcx", "r10", "r11", "memory";
#endif;
#ifdef __LINUX__
    volatile asm
    {
        movl $0, %edi
        movq $$231, %rax
        syscall
    } : : "r"(code) : "rax", "rdi", "r11", "memory";
#endif;
#ifdef __MACOS__
    volatile asm
    {
        movq $$0x2000001, %rax
        movl $0, %edi
        syscall
    } : : "r"(code) : "rax", "rdi", "memory";
#endif;
    return;
};

def !!abort() -> void;
def !!abort() -> void
{
#ifdef __WINDOWS__
    volatile asm
    {
        movq $$1, %rcx
        movq $$0x002C, %rax
        movq $$-1, %r10
        syscall
    } : : : "rax", "rcx", "r10", "r11", "memory";
#endif;
#ifdef __LINUX__
    volatile asm
    {
        movq $$1, %rdi
        movq $$231, %rax
        syscall
    } : : : "rax", "rdi", "r11", "memory";
#endif;
#ifdef __MACOS__
    volatile asm
    {
        movq $$0x2000001, %rax
        movq $$1, %rdi
        syscall
    } : : : "rax", "rdi", "memory";
#endif;
};

#ifdef __LINUX__
def !!_start() -> int;

def !!_start() -> int
{
    return FRTStartup();
};
#endif; // Linux

#ifdef FLUX_RUNTIME
def !!FRTStartup() -> int
{
    int return_code;
    switch (CURRENT_OS)
    {
        #ifdef __WINDOWS__
        case (1)
        {
            return_code = main();
            ///
            //global i64 WIN_STANDARD_HANDLE = win_get_std_handle();
            
            // Get command line and parse arguments
            wchar* cmdLine = GetCommandLineW();
            int argc = 0;
            wchar** argvW = CommandLineToArgvW(cmdLine, @argc);
            
            // Convert wchar** to byte** (simplified - you may need proper conversion)
            byte** argv = (byte**)argvW;
            
            return_code = main(argc, argv);
            
            // Free the argument vector
            LocalFree(argvW);
            ///
        }
        #endif;
        #ifdef __LINUX__
        case (2)
        {
            i64 argc = 0;
            noopstr* argv = (noopstr*)0;
            
            volatile asm
            {
                movq %rdi, $0  // argc
                movq %rsi, $1  // argv
            } : : "m"(argc), "m"(argv) : "rdi","rsi","memory";
            
            // Try main with args first
            return_code = main();
        }
        #endif;
        #ifdef __MACOS__
        case (3)
        {
            return_code = main();
        }
        #endif;
        default
        {
            #ifdef __LINUX__
            exit(0);
            #endif;
            return return_code;
        };
    };
    if (return_code != 0)
    {
        // Handle error
    };
    #ifdef __LINUX__
    exit(0);  // Should pass return_code
    #endif;
    return return_code;
};
#endif;

#ifndef FLUX_STANDARD_EXCEPTIONS
#import "redexceptions.fx";
#endif;