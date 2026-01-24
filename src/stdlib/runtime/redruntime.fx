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

// Import raw functions & builtins
#import "strlen.fx";
// ---------------------------

#ifndef FLUX_STANDARD_SYSTEM
#import "redsys.fx";
#endif;
#ifndef FLUX_STANDARD_IO
#import "redio.fx";
#endif;

// >Mains
def main() -> int;
def main(int argc, char** argv) -> int;
// /Mains

  ///                                   ///
  //DO NOT REDEFINE THIS FUNCTION SIGNATURE
///                                   ///
def FRTStartup() -> int; // GO AWAY, SHOO
  ///                                   ///
  //DO NOT REDEFINE THIS FUNCTION SIGNATURE
///                                   ///

#ifdef __LINUX__
def _start() -> int;
def exit() -> void;

def _start() -> int
{
    return FRTStartup();
};
def exit() -> void
{
    volatile asm
    {
        movq $$60, %rax          // sys_exit
        movq $$0, %rdi           // exit code 0
        syscall
    } : : : "rax", "rdi";
};
#endif; // Linux

#ifdef FLUX_RUNTIME
def FRTStartup() -> int
{
    int return_code;
    switch (CURRENT_OS)
    {
        #ifdef __WINDOWS__
        case (1)
        {
            //global i64 WIN_STANDARD_HANDLE = win_get_std_handle();
            return_code = main();
        }
        #endif;
        #ifdef __LINUX__
        case (2)
        {
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
            exit();
            #endif;
            return return_code;
        };
    };
    if (return_code != 0)
    {
        // Handle error
    };
    #ifdef __LINUX__
    exit();  // Should pass return_code
    #endif;
    return return_code;
};
#endif;