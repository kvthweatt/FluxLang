// Networking Library - Windows Sockets API (Winsock2)
// Provides minimal TCP/UDP socket functionality for Windows
// No object usage - structs and functions only

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_NET
#def FLUX_STANDARD_NET 1;

#import "redtypes.fx";
#import "redmemory.fx";

// ============ WINSOCK FFI DECLARATIONS ============
extern
{
    // Core socket functions
    def !!
        socket(int domain, int type, int protocol) -> int,
        bind(int sockfd, void* addr, int addrlen) -> int,
        listen(int sockfd, int backlog) -> int,
        accept(int sockfd, void* addr, int* addrlen) -> int,
        connect(int sockfd, void* addr, int addrlen) -> int,
        send(int sockfd, void* buf, int len, int flags) -> int,
        recv(int sockfd, void* buf, int len, int flags) -> int,
        sendto(int sockfd, void* buf, int len, int flags, void* dest_addr, int addrlen) -> int,
        recvfrom(int sockfd, void* buf, int len, int flags, void* src_addr, int* addrlen) -> int,
        closesocket(int fd) -> int,
        shutdown(int sockfd, int how) -> int,
    
        // Socket options
        setsockopt(int sockfd, int level, int optname, void* optval, int optlen) -> int,
        getsockopt(int sockfd, int level, int optname, void* optval, int* optlen) -> int,
        
        // Address conversion
        inet_addr(byte* cp) -> u32,
        inet_ntoa(u32 addr) -> byte*,
        htons(u16 hostshort) -> u16,
        htonl(u32 hostlong) -> u32,
        ntohs(u16 netshort) -> u16,
        ntohl(u32 netlong) -> u32,
        
        // Name resolution
        gethostbyname(byte* name) -> void*,
        getaddrinfo(byte* node, byte* service, void* hints, void** res) -> int,
        freeaddrinfo(void* res) -> void,
        
        // Socket control (Windows uses ioctlsocket instead of fcntl)
        ioctlsocket(int sockfd, u32 cmd, u32* argp) -> int,
        select(int nfds, void* readfds, void* writefds, void* exceptfds, void* timeout) -> int,
        
        // WSA initialization/cleanup
        WSAStartup(u16 version, void* wsadata) -> int,
        WSACleanup() -> int,
        WSAGetLastError() -> int;
};


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

        // ============ INITIALIZATION ============
        
        // Initialize Winsock (MUST be called before any socket operations on Windows!)
        def init() -> int
        {
            WSAData wsaData;
            return WSAStartup(WINSOCK_VERSION, @wsaData);
        };
        
        // Cleanup Winsock (should be called when done with sockets)
        def cleanup() -> int
        {
            return WSACleanup();
        };
        
        // Get last socket error
        def get_last_error() -> int
        {
            return WSAGetLastError();
        };
        
        // ============ HELPER FUNCTIONS ============
        
        // Create a TCP socket
        def tcp_socket() -> int
        {
            return socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        };
        
        // Create a UDP socket
        def udp_socket() -> int
        {
            return socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        };
        
        // Initialize sockaddr_in structure
        def init_sockaddr(sockaddr_in* addr, u32 ip_addr, u16 port) -> void
        {
            *addr.sin_family = (u16)AF_INET;
            *addr.sin_port = htons(port);
            *addr.sin_addr = htonl(ip_addr);
            
            // Zero out padding
            int i = 0;
            while (i < 8)
            {
                *addr.sin_zero[i] = 0;
                i = i + 1;
            };
        };
        
        // Initialize sockaddr_in with string IP (dotted decimal)
        def init_sockaddr_str(sockaddr_in* addr, byte* ip_str, u16 port) -> void
        {
            *addr.sin_family = (u16)AF_INET;
            *addr.sin_port = htons(port);
            *addr.sin_addr = inet_addr(ip_str);
            
            // Zero out padding
            int i = 0;
            while (i < 8)
            {
                *addr.sin_zero[i] = 0;
                i = i + 1;
            };
        };

        // Set socket to non-blocking mode (Windows version using ioctlsocket)
        def set_nonblocking(int sockfd) -> int
        {
            u32 mode = 1;  // 1 = non-blocking, 0 = blocking
            return ioctlsocket(sockfd, FIONBIO, @mode);
        };
        
        // Set socket to blocking mode
        def set_blocking(int sockfd) -> int
        {
            u32 mode = 0;  // 0 = blocking, 1 = non-blocking
            return ioctlsocket(sockfd, FIONBIO, @mode);
        };
        
        // Enable SO_REUSEADDR option
        def set_reuseaddr(int sockfd, bool enable) -> int
        {
            int optval = enable ? 1 : 0;
            return setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, @optval, 4);
        };
        
        // Set receive timeout (Windows uses milliseconds as DWORD, not timeval)
        def set_recv_timeout(int sockfd, int milliseconds) -> int
        {
            return setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, @milliseconds, 4);
        };
        
        // Set send timeout (Windows uses milliseconds as DWORD, not timeval)
        def set_send_timeout(int sockfd, int milliseconds) -> int
        {
            return setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, @milliseconds, 4);
        };

        // ============ HIGH-LEVEL TCP FUNCTIONS ============
        
        // Create and bind a TCP server socket
        // Returns socket fd on success, -1 on error
        def tcp_server_create(u16 port, int backlog) -> int
        {
            int sockfd = tcp_socket();
            if (sockfd < 0)
            {
                return -1;
            };
            
            // Enable address reuse
            set_reuseaddr(sockfd, true);
            
            // Bind to address
            sockaddr_in addr;
            init_sockaddr(@addr, INADDR_ANY, port);
            
            if (bind(sockfd, @addr, 16) < 0)
            {
                closesocket(sockfd);
                return -1;
            };
            
            // Listen for connections
            if (listen(sockfd, backlog) < 0)
            {
                closesocket(sockfd);
                return -1;
            };
            
            return sockfd;
        };

        // Accept a connection on server socket
        // Returns client socket fd on success, -1 on error
        def tcp_server_accept(int server_sockfd, sockaddr_in* client_addr) -> int
        {
            int addr_len = 16;
            return accept(server_sockfd, client_addr, @addr_len);
        };

        // Connect to a TCP server
        // Returns socket fd on success, -1 on error
        def tcp_client_connect(byte* ip_addr, u16 port) -> int
        {
            int sockfd = tcp_socket();
            if (sockfd < 0)
            {
                return -1;
            };
            
            sockaddr_in addr;
            init_sockaddr_str(@addr, ip_addr, port);
            
            if (connect(sockfd, @addr, 16) < 0)
            {
                closesocket(sockfd);
                return -1;
            };
            
            return sockfd;
        };
        
        // Send data over TCP socket
        // Returns number of bytes sent, -1 on error
        def tcp_send(int sockfd, byte[] xdata, int length) -> int
        {
            return send(sockfd, xdata, length, 0);
        };
        
        // Receive data from TCP socket
        // Returns number of bytes received, -1 on error, 0 on connection close
        def tcp_recv(int sockfd, byte[] buffer, int buffer_size) -> int
        {
            return recv(sockfd, buffer, buffer_size, 0);
        };

        // Send all data (handles partial sends)
        // Returns total bytes sent on success, -1 on error
        def tcp_send_all(int sockfd, byte[] xdata, int length) -> int
        {
            int total_sent = 0;
            int remaining = length;
            
            while (total_sent < length)
            {
                int sent = send(sockfd, xdata + total_sent, remaining, 0);
                if (sent <= 0)
                {
                    return -1;
                };
                
                total_sent = total_sent + sent;
                remaining = remaining - sent;
            };
            
            return total_sent;
        };

        // Receive exact amount of data (handles partial receives)
        // Returns total bytes received on success, -1 on error
        def tcp_recv_all(int sockfd, byte[] buffer, int length) -> int
        {
            int total_recv = 0;
            int remaining = length;
            
            while (total_recv < length)
            {
                int received = recv(sockfd, buffer + total_recv, remaining, 0);
                if (received <= 0)
                {
                    return -1;
                };
                
                total_recv = total_recv + received;
                remaining = remaining - received;
            };
            
            return total_recv;
        };

        // Close TCP connection
        def tcp_close(int sockfd) -> int
        {
            shutdown(sockfd, SD_BOTH);
            return closesocket(sockfd);
        };

        // ============ HIGH-LEVEL UDP FUNCTIONS ============
        
        // Create and bind a UDP socket
        // Returns socket fd on success, -1 on error
        def udp_socket_bind(u16 port) -> int
        {
            int sockfd = udp_socket();
            if (sockfd < 0)
            {
                return -1;
            };
            
            sockaddr_in addr;
            init_sockaddr(@addr, INADDR_ANY, port);
            
            if (bind(sockfd, @addr, 16) < 0)
            {
                closesocket(sockfd);
                return -1;
            };
            
            return sockfd;
        };

        // Send UDP datagram
        // Returns number of bytes sent, -1 on error
        def udp_send(int sockfd, byte[] xdata, int length, byte* dest_ip, u16 dest_port) -> int
        {
            sockaddr_in dest_addr;
            init_sockaddr_str(@dest_addr, dest_ip, dest_port);
            
            return sendto(sockfd, xdata, length, 0, @dest_addr, 16);
        };
        
        // Receive UDP datagram
        // Returns number of bytes received, -1 on error
        def udp_recv(int sockfd, byte[] buffer, int buffer_size, sockaddr_in* src_addr) -> int
        {
            int addr_len = 16;
            return recvfrom(sockfd, buffer, buffer_size, 0, src_addr, @addr_len);
        };
        
        // Close UDP socket
        def udp_close(int sockfd) -> int
        {
            return closesocket(sockfd);
        };

        // ============ UTILITY FUNCTIONS ============
        
        // Convert port from network byte order to host byte order
        def port_ntoh(u16 net_port) -> u16
        {
            return ntohs(net_port);
        };
        
        // Convert port from host byte order to network byte order
        def port_hton(u16 host_port) -> u16
        {
            return htons(host_port);
        };
        
        // Get IP address from sockaddr_in as string
        def get_ip_string(sockaddr_in* addr) -> byte*
        {
            return inet_ntoa(addr.sin_addr);
        };
        
        // Get port from sockaddr_in
        def get_port(sockaddr_in* addr) -> u16
        {
            return ntohs(addr.sin_port);
        };
        
        // Check if socket is valid
        def is_valid_socket(int sockfd) -> bool
        {
            return sockfd != INVALID_SOCKET;
        };
    };
};

using standard::net;

#endif;
