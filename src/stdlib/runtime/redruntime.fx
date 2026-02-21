global const void* STDLIB_GVP = (void*)@void;
global const unsigned data{64} U64MAXVAL = 0xFFFFFFFFFFFFFFFFu;

#def NULL STDLIB_GVP;

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

#ifdef __WINDOWS__
global i64 WIN_STDOUT_HANDLE;
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

#import "red_string_utilities.fx";

#ifndef FLUX_STANDARD_SYSTEM
#import "redsys.fx";
#endif;

#ifndef FLUX_STANDARD_IO
#import "redio.fx";
#endif;

// ---------------------------
//
// Import runtime helpers
#import "ffifio.fx";                 // FFI-based File Input/Output (CRT)
//
// ---------------------------
//
// Import raw functions & builtins
#import "string_object_raw.fx";
#import "file_object_raw.fx";
//#import "socket_object_raw.fx";
//

#ifndef FLUX_STANDARD_COLLECTIONS
#import "redcollections.fx";
#endif;

extern
{
#ifdef __WINDOWS__
    def !!
        GetStdHandle(int nStdHandle) -> i64,
        GetCommandLineW() -> wchar*,
        LocalFree(void* x) -> void*;
#endif;
#ifdef __LINUX__
    def !!
        exit(int code) -> void,
        abort() -> void,
        atexit(void*) -> int;
#endif;
#ifdef __MACOS__
    def !!
        exit(int code) -> void,
        abort() -> void,
        atexit(void*) -> int;
#endif;
};



// >Mains
def main() -> int;
def main(int, byte**) -> int;
// /Mains

  ///                                       ///
 ///DO NOT REDEFINE THIS FUNCTION SIGNATURE///
///                                       ///
def !!FRTStartup() -> int; // GO AWAY, SHOO
  ///                                       ///
 ///DO NOT REDEFINE THIS FUNCTION SIGNATURE///
///                                       ///

#ifdef __LINUX__
def !!_start() -> int;

def !!_start() -> int
{
    exit(FRTStartup());
    abort();
    return;
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
            // Initialize stdout handle for win_print
            WIN_STDOUT_HANDLE = GetStdHandle(-11);
            //print("STDOUT: \0"); print(WIN_STDOUT_HANDLE); print();

            // Initialize the Flux standard heap allocator
            // For reference, see runtime/redallocators.fx
            standard::memory::allocators::stdheap::table_init();

            // Parse command line manually from GetCommandLineW
            wchar* cmdLine = GetCommandLineW();

            // Count arguments
            int argc = 0;
            int pos = 0;
            while (cmdLine[pos] != (wchar)0)
            {
                // Skip whitespace
                while (cmdLine[pos] == (wchar)32 | cmdLine[pos] == (wchar)9)
                {
                    pos = pos + 1;
                };
                if (cmdLine[pos] == (wchar)0)
                {
                    break;
                };
                // Skip quoted or unquoted token
                if (cmdLine[pos] == (wchar)34)
                {
                    pos = pos + 1;
                    while (cmdLine[pos] != (wchar)0 & cmdLine[pos] != (wchar)34)
                    {
                        pos = pos + 1;
                    };
                    if (cmdLine[pos] == (wchar)34)
                    {
                        pos = pos + 1;
                    };
                }
                else
                {
                    while (cmdLine[pos] != (wchar)0 & cmdLine[pos] != (wchar)32 & cmdLine[pos] != (wchar)9)
                    {
                        pos = pos + 1;
                    };
                };
                argc = argc + 1;
            };

            // Allocate argv
            byte** argv = (byte**)fmalloc((u64)argc * (u64)8);

            // Fill argv
            int argi = 0;
            pos = 0;
            while (cmdLine[pos] != (wchar)0)
            {
                // Skip whitespace
                while (cmdLine[pos] == (wchar)32 | cmdLine[pos] == (wchar)9)
                {
                    pos = pos + 1;
                };
                if (cmdLine[pos] == (wchar)0)
                {
                    break;
                };

                // Measure token length
                int start = pos;
                int len = 0;
                bool quoted = false;
                if (cmdLine[pos] == (wchar)34)
                {
                    quoted = true;
                    pos = pos + 1;
                    start = pos;
                    while (cmdLine[pos] != (wchar)0 & cmdLine[pos] != (wchar)34)
                    {
                        len = len + 1;
                        pos = pos + 1;
                    };
                    if (cmdLine[pos] == (wchar)34)
                    {
                        pos = pos + 1;
                    };
                }
                else
                {
                    while (cmdLine[pos] != (wchar)0 & cmdLine[pos] != (wchar)32 & cmdLine[pos] != (wchar)9)
                    {
                        len = len + 1;
                        pos = pos + 1;
                    };
                };

                // Copy low byte of each wchar into byte buffer
                byte* arg = (byte*)fmalloc((u64)len + (u64)1);
                int j = 0;
                while (j < len)
                {
                    arg[j] = (byte)cmdLine[start + j];
                    j = j + 1;
                };
                arg[len] = (byte)0;
                argv[argi] = arg;
                argi = argi + 1;
            };

            // Call the appropriate main overload
            if (argc > 1)
            {
                return_code = main__2__int__data_ptr2_ubits8__ret_int(argc, argv);
            }
            else
            {
                return_code = main();
            };

            // Free converted argv
            int k = 0;
            while (k < argc)
            {
                ffree((u64)argv[k]);
                k = k + 1;
            };
            ffree((u64)argv);
        }
        #endif;
        #ifdef __LINUX__
        case (2)
        {
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
            abort();
            #endif;
            return return_code;
        };
    };
    if (return_code != 0)
    {
        // Handle error
        if (return_code == 3221225477)
        {
            print("SEGFAULT\n\0");
        };
    };
    return return_code;
};
#endif;
///
#ifndef FLUX_STANDARD_EXCEPTIONS
#import "redexceptions.fx";
#endif;
///