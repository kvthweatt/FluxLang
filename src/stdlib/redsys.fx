// OS Detection Library
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_SYSTEM
#def FLUX_STANDARD_SYSTEM 1;
#endif;

#ifdef __WINDOWS__
#def CURRENT_OS 1;
#endif;

#ifdef __LINUX__
#def CURRENT_OS 2;
#endif;

#ifdef __MACOS__
#def CURRENT_OS 3;
#endif;

global const int OS_UNKNOWN = 0;
global const int OS_WINDOWS = 1;
global const int OS_LINUX = 2;
global const int OS_MACOS = 3;

namespace standard
{
    namespace system
    {
    };
};

//using standard::system;