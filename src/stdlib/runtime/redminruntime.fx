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

#ifndef FLUX_STANDARD_SYSTEM
#import "redsys.fx";
#endif;

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

extern def !!exit(int code) -> void;

extern def !!abort() -> void;

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