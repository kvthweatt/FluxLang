// OS Detection Library
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_SYSTEM
#def FLUX_STANDARD_SYSTEM 1;
#endif;

///
global const int OS_UNKNOWN = 0;
global const int OS_WINDOWS = 1;
global const int OS_LINUX = 2;
global const int OS_MACOS = 3;
///
#ifdef __WINDOWS__
#def CURRENT_OS 1;
extern
{
    def !!
        Sleep(u32) -> void,
        system(byte*) -> int,
        LoadLibraryA(byte*) -> void*,
        GetProcAddress(void*, byte*) -> void*,
        GetSystemInfo(void*) -> void;
};
#endif;

#ifdef __LINUX__
#def CURRENT_OS 2;
#endif;

#ifdef __MACOS__
#def CURRENT_OS 3;
#endif;

namespace standard
{
    namespace system
    {
        namespace Windows
        {
        };
    };
};