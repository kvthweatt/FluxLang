// Author: Karac V. Thweatt

// Networking Library - Windows Sockets API (Winsock2)
// Provides minimal TCP/UDP socket functionality for Windows
// No object usage - structs and functions only

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_NET
#def FLUX_STANDARD_NET 1;

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;
#ifndef FLUX_STANDARD_MEMORY
#import "memory.fx";
#endif;

#ifndef FLUX_STANDARD_SOCKETS
#import "socket_object_raw.fx";
#endif;

// Time value for timeouts (different on Windows - uses milliseconds as DWORD)
struct timeval
{
    i32 tv_sec,          // Seconds
        tv_usec;         // Microseconds
};

namespace standard
{
    namespace net
    {
    };
};

#endif;
