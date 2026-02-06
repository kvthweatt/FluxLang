#import "standard.fx";


// ============ STRUCTS ============

// IPv4 socket address structure (same as Linux)
struct sockaddr_in
{
    u16 sin_family;      // Address family (AF_INET)
    u16 sin_port;        // Port number (network byte order)
    u32 sin_addr;        // IPv4 address (network byte order)
    byte[8] sin_zero;    // Padding to match sockaddr size
};

// Generic socket address (for compatibility)
struct sockaddr
{
    u16 sa_family;       // Address family
    byte[14] sa_data;    // Address data
};

// Time value for timeouts (different on Windows - uses milliseconds as DWORD)
struct timeval
{
    i32 tv_sec;          // Seconds
    i32 tv_usec;         // Microseconds
};

// WSAData structure (simplified)
struct WSAData
{
    u16 wVersion;
    u16 wHighVersion;
    byte[257] szDescription;
    byte[129] szSystemStatus;
    u16 iMaxSockets;
    u16 iMaxUdpDg;
    u64* lpVendorInfo;
};


namespace standard
{
    namespace net
    {
        // ============ CONSTANTS ============
        
        // Address families
        global const int AF_UNSPEC = 0;
        global const int AF_INET = 2;      // IPv4
        global const int AF_INET6 = 23;    // IPv6 (different on Windows!)
        
        // Socket types
        global const int SOCK_STREAM = 1;  // TCP
        global const int SOCK_DGRAM = 2;   // UDP
        global const int SOCK_RAW = 3;
        
        // Protocol
        global const int IPPROTO_TCP = 6;
        global const int IPPROTO_UDP = 17;
        
        // Socket options levels
        global const int SOL_SOCKET = 0xFFFF;  // Different on Windows!
        
        // Socket options
        global const int SO_REUSEADDR = 0x0004;
        global const int SO_KEEPALIVE = 0x0008;
        global const int SO_BROADCAST = 0x0020;
        global const int SO_RCVBUF = 0x1002;
        global const int SO_SNDBUF = 0x1001;
        global const int SO_RCVTIMEO = 0x1006;
        global const int SO_SNDTIMEO = 0x1005;
        
        // Shutdown modes
        global const int SD_RECEIVE = 0x00;    // Shutdown receive (same as SHUT_RD)
        global const int SD_SEND = 0x01;       // Shutdown send (same as SHUT_WR)
        global const int SD_BOTH = 0x02;       // Shutdown both (same as SHUT_RDWR)
        
        // ioctlsocket commands (replaces fcntl)
        global const u32 FIONBIO = 0x8004667E;  // Set non-blocking mode
        global const u32 FIONREAD = 0x4004667F; // Get number of bytes available
        
        // Error codes
        global const int SOCKET_ERROR = -1;
        global const int INVALID_SOCKET = -1;
        
        // WSA Error codes (some common ones)
        global const int WSAEWOULDBLOCK = 10035;
        global const int WSAECONNRESET = 10054;
        global const int WSAETIMEDOUT = 10060;
        
        // Special addresses
        global const u32 INADDR_ANY = 0x00000000;
        global const u32 INADDR_LOOPBACK = 0x7F000001;  // 127.0.0.1
        global const u32 INADDR_BROADCAST = 0xFFFFFFFF;
        
        // WSA version
        global const u16 WINSOCK_VERSION = 0x0202;  // Version 2.2 (stored as 0x0202)
    };
};
using standard::net;


        def init_sockaddr(sockaddr_in* addr, u32 ip_addr, u16 port) -> void
        {
            addr.sin_family = (u16)AF_INET;
            addr.sin_port = htons(port);
            addr.sin_addr = ip_addr;
            
            // Zero out padding
            int i = 0;
            while (i < 8)
            {
                addr.sin_zero[i] = 0;
                i = i + 1;
            };
        };



def main() -> int
{

    i32 x = 1;

    if (x == 1) { return 0; };

    print(x);
    return 0;
};