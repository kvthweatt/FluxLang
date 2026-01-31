// Flux Networking Library
// Provides TCP and UDP networking capabilities using FFI to C socket APIs
// Supports Windows (Winsock2) and Linux (POSIX sockets)

#ifndef FLUX_STANDARD_NETWORK
#def FLUX_STANDARD_NETWORK 1;
#endif;

#ifdef FLUX_STANDARD_NETWORK

// ============ PLATFORM-SPECIFIC FFI DECLARATIONS ============

#ifdef __WINDOWS__
// Windows Winsock2 FFI declarations
extern
{
    // WSAStartup(WORD wVersionRequested, LPWSADATA lpWSAData)
    def !!WSAStartup(u16 version, void* wsa_data) -> i32;
    
    // WSACleanup()
    def !!WSACleanup() -> i32;
    
    // socket(int af, int type, int protocol)
    def !!socket(i32 af, i32 type, i32 protocol) -> i64;
    
    // closesocket(SOCKET s)
    def !!closesocket(i64 s) -> i32;
    
    // bind(SOCKET s, const struct sockaddr *name, int namelen)
    def !!bind(i64 s, void* addr, i32 addrlen) -> i32;
    
    // listen(SOCKET s, int backlog)
    def !!listen(i64 s, i32 backlog) -> i32;
    
    // accept(SOCKET s, struct sockaddr *addr, int *addrlen)
    def !!accept(i64 s, void* addr, i32* addrlen) -> i64;
    
    // connect(SOCKET s, const struct sockaddr *name, int namelen)
    def !!connect(i64 s, void* addr, i32 addrlen) -> i32;
    
    // send(SOCKET s, const char *buf, int len, int flags)
    def !!send(i64 s, byte* buf, i32 len, i32 flags) -> i32;
    
    // recv(SOCKET s, char *buf, int len, int flags)
    def !!recv(i64 s, byte* buf, i32 len, i32 flags) -> i32;
    
    // sendto(SOCKET s, const char *buf, int len, int flags, const struct sockaddr *to, int tolen)
    def !!sendto(i64 s, byte* buf, i32 len, i32 flags, void* to, i32 tolen) -> i32;
    
    // recvfrom(SOCKET s, char *buf, int len, int flags, struct sockaddr *from, int *fromlen)
    def !!recvfrom(i64 s, byte* buf, i32 len, i32 flags, void* xfrom, i32* fromlen) -> i32;
    
    // shutdown(SOCKET s, int how)
    def !!shutdown(i64 s, i32 how) -> i32;
    
    // setsockopt(SOCKET s, int level, int optname, const char *optval, int optlen)
    def !!setsockopt(i64 s, i32 level, i32 optname, void* optval, i32 optlen) -> i32;
    
    // getsockopt(SOCKET s, int level, int optname, char *optval, int *optlen)
    def !!getsockopt(i64 s, i32 level, i32 optname, void* optval, i32* optlen) -> i32;
    
    // inet_addr(const char *cp)
    def !!inet_addr(byte* cp) -> u32;
    
    // inet_ntoa(struct in_addr in)
    def !!inet_ntoa(u32 input) -> byte*;
    
    // htons(u_short hostshort)
    def !!htons(u16 hostshort) -> u16;
    
    // htonl(u_long hostlong)
    def !!htonl(u32 hostlong) -> u32;
    
    // ntohs(u_short netshort)
    def !!ntohs(u16 netshort) -> u16;
    
    // ntohl(u_long netlong)
    def !!ntohl(u32 netlong) -> u32;
    
    // gethostname(char *name, int namelen)
    def !!gethostname(byte* name, i32 namelen) -> i32;
    
    // getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res)
    def !!getaddrinfo(byte* node, byte* service, void* hints, void** res) -> i32;
    
    // freeaddrinfo(struct addrinfo *res)
    def !!freeaddrinfo(void* res) -> void;
    
    // WSAGetLastError()
    def !!WSAGetLastError() -> i32;
};
#endif;

#ifdef __LINUX__
// Linux POSIX socket FFI declarations
extern
{
    // socket(int domain, int type, int protocol)
    def !!socket(i32 domain, i32 type, i32 protocol) -> i32;
    
    // close(int fd)
    def !!close(i32 fd) -> i32;
    
    // bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen)
    def !!bind(i32 sockfd, void* addr, u32 addrlen) -> i32;
    
    // listen(int sockfd, int backlog)
    def !!listen(i32 sockfd, i32 backlog) -> i32;
    
    // accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen)
    def !!accept(i32 sockfd, void* addr, u32* addrlen) -> i32;
    
    // connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen)
    def !!connect(i32 sockfd, void* addr, u32 addrlen) -> i32;
    
    // send(int sockfd, const void *buf, size_t len, int flags)
    def !!send(i32 sockfd, byte* buf, u64 len, i32 flags) -> i64;
    
    // recv(int sockfd, void *buf, size_t len, int flags)
    def !!recv(i32 sockfd, byte* buf, u64 len, i32 flags) -> i64;
    
    // sendto(int sockfd, const void *buf, size_t len, int flags, const struct sockaddr *dest_addr, socklen_t addrlen)
    def !!sendto(i32 sockfd, byte* buf, u64 len, i32 flags, void* dest_addr, u32 addrlen) -> i64;
    
    // recvfrom(int sockfd, void *buf, size_t len, int flags, struct sockaddr *src_addr, socklen_t *addrlen)
    def !!recvfrom(i32 sockfd, byte* buf, u64 len, i32 flags, void* src_addr, u32* addrlen) -> i64;
    
    // shutdown(int sockfd, int how)
    def !!shutdown(i32 sockfd, i32 how) -> i32;
    
    // setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen)
    def !!setsockopt(i32 sockfd, i32 level, i32 optname, void* optval, u32 optlen) -> i32;
    
    // getsockopt(int sockfd, int level, int optname, void *optval, socklen_t *optlen)
    def !!getsockopt(i32 sockfd, i32 level, i32 optname, void* optval, u32* optlen) -> i32;
    
    // inet_addr(const char *cp)
    def !!inet_addr(byte* cp) -> u32;
    
    // inet_ntoa(struct in_addr in)
    def !!inet_ntoa(u32 in) -> byte*;
    
    // htons(uint16_t hostshort)
    def !!htons(u16 hostshort) -> u16;
    
    // htonl(uint32_t hostlong)
    def !!htonl(u32 hostlong) -> u32;
    
    // ntohs(uint16_t netshort)
    def !!ntohs(u16 netshort) -> u16;
    
    // ntohl(uint32_t netlong)
    def !!ntohl(u32 netlong) -> u32;
    
    // gethostname(char *name, size_t len)
    def !!gethostname(byte* name, u64 len) -> i32;
    
    // getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res)
    def !!getaddrinfo(byte* node, byte* service, void* hints, void** res) -> i32;
    
    // freeaddrinfo(struct addrinfo *res)
    def !!freeaddrinfo(void* res) -> void;
};
#endif;

// ============ NAMESPACE DEFINITION ============

namespace standard
{
    namespace net
    {
        // ============ CONSTANTS ============
        
        // Address families
        #def AF_UNSPEC 0;
        #def AF_INET 2;
        #def AF_INET6 10;
        
        // Socket types
        #def SOCK_STREAM 1;
        #def SOCK_DGRAM 2;
        #def SOCK_RAW 3;
        
        // Protocols
        #def IPPROTO_IP 0;
        #def IPPROTO_ICMP 1;
        #def IPPROTO_TCP 6;
        #def IPPROTO_UDP 17;
        
        // Shutdown modes
        #def SHUT_RD 0;
        #def SHUT_WR 1;
        #def SHUT_RDWR 2;
        
        // Socket options levels
        #def SOL_SOCKET 0xFFFF;
        
        // Socket options
        #def SO_REUSEADDR 0x0004;
        #def SO_KEEPALIVE 0x0008;
        #def SO_DONTROUTE 0x0010;
        #def SO_BROADCAST 0x0020;
        #def SO_LINGER 0x0080;
        #def SO_OOBINLINE 0x0100;
        #def SO_SNDBUF 0x1001;
        #def SO_RCVBUF 0x1002;
        #def SO_SNDTIMEO 0x1005;
        #def SO_RCVTIMEO 0x1006;
        #def SO_ERROR 0x1007;
        #def SO_TYPE 0x1008;
        
        // TCP options
        #def TCP_NODELAY 1;
        
        // Error codes
        #def INVALID_SOCKET -1;
        #def SOCKET_ERROR -1;
        
        // WSA Version for Windows
        #def WINSOCK_VERSION 0x0202;  // Version 2.2
        
        // ============ STRUCTURES ============
        
        // IPv4 address structure (struct in_addr)
        struct in_addr
        {
            u32 s_addr;
        };
        
        // Socket address structure for IPv4 (struct sockaddr_in)
        struct sockaddr_in
        {
            u16 sin_family;      // AF_INET
            u16 sin_port;        // Port number (network byte order)
            in_addr sin_addr;    // IPv4 address
            byte[8] sin_zero;    // Padding to match sockaddr size
        };
        
        // Generic socket address structure
        struct sockaddr
        {
            u16 sa_family;
            byte[14] sa_data;
        };
        
        // Linger structure for SO_LINGER option
        struct linger
        {
            u16 l_onoff;   // Linger on/off
            u16 l_linger;  // Linger time in seconds
        };
        
        #ifdef __WINDOWS__
        // WSAData structure for Windows
        struct WSAData
        {
            u16 wVersion;
            u16 wHighVersion;
            byte[257] szDescription;
            byte[129] szSystemStatus;
            u16 iMaxSockets;
            u16 iMaxUdpDg;
            byte* lpVendorInfo;
        };
        #endif;
        
        // ============ GLOBAL STATE ============
        
        bool network_initialized = 0;
        
        // ============ INITIALIZATION & CLEANUP ============
        
        // Initialize networking (Windows-specific, no-op on Linux)
        def init() -> i32
        {
            if (network_initialized)
            {
                return 0;
            };
            
            #ifdef __WINDOWS__
            WSAData wsa_data;
            i32 result = WSAStartup((u16)WINSOCK_VERSION, @wsa_data);
            
            if (result == 0)
            {
                network_initialized = 1;
            };
            
            return result;
            #endif;
            
            #ifdef __LINUX__
            network_initialized = 1;
            return 0;
            #endif;
            
            return -1;
        };
        
        // Cleanup networking (Windows-specific, no-op on Linux)
        def cleanup() -> i32
        {
            if (!network_initialized)
            {
                return 0;
            };
            
            #ifdef __WINDOWS__
            i32 result = WSACleanup();
            network_initialized = 0;
            return result;
            #endif;
            
            #ifdef __LINUX__
            network_initialized = 0;
            return 0;
            #endif;
            
            return -1;
        };
        
        // Get last error code
        def get_last_error() -> i32
        {
            #ifdef __WINDOWS__
            return WSAGetLastError();
            #endif;
            
            #ifdef __LINUX__
            // On Linux, errno is more complex, but we can use a simple approach
            // For now, return -1 as placeholder (would need errno FFI)
            return -1;
            #endif;
            
            return -1;
        };
        
        // ============ SOCKET CREATION & MANAGEMENT ============
        
        // Create a socket
        def create_socket(i32 family, i32 type, i32 protocol) -> i64
        {
            #ifdef __WINDOWS__
            return socket(family, type, protocol);
            #endif;
            
            #ifdef __LINUX__
            return (i64)socket(family, type, protocol);
            #endif;
            
            return INVALID_SOCKET;
        };
        
        // Close a socket
        def close_socket(i64 sock) -> i32
        {
            #ifdef __WINDOWS__
            return closesocket(sock);
            #endif;
            
            #ifdef __LINUX__
            return close((i32)sock);
            #endif;
            
            return SOCKET_ERROR;
        };
        
        // Shutdown a socket
        def shutdown_socket(i64 sock, i32 how) -> i32
        {
            #ifdef __WINDOWS__
            return shutdown(sock, how);
            #endif;
            
            #ifdef __LINUX__
            return shutdown((i32)sock, how);
            #endif;
            
            return SOCKET_ERROR;
        };
        
        // ============ ADDRESS MANIPULATION ============
        
        // Create an IPv4 sockaddr_in structure
        def make_sockaddr_in(u16 port, u32 ip_addr) -> sockaddr_in
        {
            sockaddr_in addr;
            addr.sin_family = (u16)AF_INET;
            addr.sin_port = htons(port);
            addr.sin_addr.s_addr = ip_addr;
            
            // Zero out padding
            for (i32 i = 0; i < 8; i++)
            {
                addr.sin_zero[i] = (byte)0;
            };
            
            return addr;
        };
        
        // Convert string IP address to network byte order integer
        def ip_to_addr(byte* ip_str) -> u32
        {
            return inet_addr(ip_str);
        };
        
        // Convert network byte order integer to string IP address
        def addr_to_ip(u32 addr) -> byte*
        {
            return inet_ntoa(addr);
        };
        
        // Create sockaddr_in for any address (0.0.0.0)
        def make_addr_any(u16 port) -> sockaddr_in
        {
            return make_sockaddr_in(port, htonl((u32)0));
        };
        
        // Create sockaddr_in for localhost (127.0.0.1)
        def make_addr_localhost(u16 port) -> sockaddr_in
        {
            return make_sockaddr_in(port, ip_to_addr("127.0.0.1\0"));
        };
        
        // Create sockaddr_in from IP string and port
        def make_addr(byte* ip_str, u16 port) -> sockaddr_in
        {
            return make_sockaddr_in(port, ip_to_addr(ip_str));
        };
        
        // ============ SOCKET OPTIONS ============
        
        // Set socket option
        def set_socket_option(i64 sock, i32 level, i32 optname, void* optval, i32 optlen) -> i32
        {
            #ifdef __WINDOWS__
            return setsockopt(sock, level, optname, optval, optlen);
            #endif;
            
            #ifdef __LINUX__
            return setsockopt((i32)sock, level, optname, optval, (u32)optlen);
            #endif;
            
            return SOCKET_ERROR;
        };
        
        // Get socket option
        def get_socket_option(i64 sock, i32 level, i32 optname, void* optval, i32* optlen) -> i32
        {
            #ifdef __WINDOWS__
            return getsockopt(sock, level, optname, optval, optlen);
            #endif;
            
            #ifdef __LINUX__
            u32 len = (u32)*optlen;
            i32 result = getsockopt((i32)sock, level, optname, optval, @len);
            *optlen = (i32)len;
            return result;
            #endif;
            
            return SOCKET_ERROR;
        };
        
        // Enable SO_REUSEADDR on socket
        def set_reuse_addr(i64 sock, bool enable) -> i32
        {
            i32 opt = (i32)enable;
            return set_socket_option(sock, SOL_SOCKET, SO_REUSEADDR, @opt, 4);
        };
        
        // Enable TCP_NODELAY (disable Nagle's algorithm)
        def set_tcp_nodelay(i64 sock, bool enable) -> i32
        {
            i32 opt = (i32)enable;
            return set_socket_option(sock, IPPROTO_TCP, TCP_NODELAY, @opt, 4);
        };
        
        // Set socket send buffer size
        def set_send_buffer_size(i64 sock, i32 size) -> i32
        {
            return set_socket_option(sock, SOL_SOCKET, SO_SNDBUF, @size, 4);
        };
        
        // Set socket receive buffer size
        def set_recv_buffer_size(i64 sock, i32 size) -> i32
        {
            return set_socket_option(sock, SOL_SOCKET, SO_RCVBUF, @size, 4);
        };
        
        // ============ TCP OPERATIONS ============
        
        namespace tcp
        {
            // Create a TCP socket
            def create() -> i64
            {
                return create_socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
            };
            
            // Bind socket to address
            def bind(i64 sock, sockaddr_in* addr) -> i32
            {
                #ifdef __WINDOWS__
                return bind(sock, (void*)addr, 16);
                #endif;
                
                #ifdef __LINUX__
                return bind((i32)sock, (void*)addr, (u32)16);
                #endif;
                
                return SOCKET_ERROR;
            };
            
            // Listen for incoming connections
            def listen(i64 sock, i32 backlog) -> i32
            {
                #ifdef __WINDOWS__
                return listen(sock, backlog);
                #endif;
                
                #ifdef __LINUX__
                return listen((i32)sock, backlog);
                #endif;
                
                return SOCKET_ERROR;
            };
            
            // Accept incoming connection
            def accept(i64 sock, sockaddr_in* client_addr) -> i64
            {
                #ifdef __WINDOWS__
                i32 addrlen = 16;
                return accept(sock, (void*)client_addr, @addrlen);
                #endif;
                
                #ifdef __LINUX__
                u32 addrlen = 16;
                return (i64)accept((i32)sock, (void*)client_addr, @addrlen);
                #endif;
                
                return INVALID_SOCKET;
            };
            
            // Connect to server
            def connect(i64 sock, sockaddr_in* server_addr) -> i32
            {
                #ifdef __WINDOWS__
                return connect(sock, (void*)server_addr, 16);
                #endif;
                
                #ifdef __LINUX__
                return connect((i32)sock, (void*)server_addr, (u32)16);
                #endif;
                
                return SOCKET_ERROR;
            };
            
            // Send data
            def send(i64 sock, byte* xdata, i32 len) -> i32
            {
                #ifdef __WINDOWS__
                return send(sock, xdata, len, 0);
                #endif;
                
                #ifdef __LINUX__
                return (i32)send((i32)sock, xdata, (u64)len, 0);
                #endif;
                
                return SOCKET_ERROR;
            };
            
            // Receive data
            def recv(i64 sock, byte* buffer, i32 len) -> i32
            {
                #ifdef __WINDOWS__
                return recv(sock, buffer, len, 0);
                #endif;
                
                #ifdef __LINUX__
                return (i32)recv((i32)sock, buffer, (u64)len, 0);
                #endif;
                
                return SOCKET_ERROR;
            };
            
            // Send all data (keeps sending until all data is sent or error)
            def send_all(i64 sock, byte* xdata, i32 len) -> i32
            {
                i32 total_sent = 0;
                i32 bytes_left = len;
                
                while (total_sent < len)
                {
                    i32 sent = send(sock, xdata + total_sent, bytes_left);
                    
                    if (sent == SOCKET_ERROR)
                    {
                        return SOCKET_ERROR;
                    };
                    
                    total_sent = total_sent + sent;
                    bytes_left = bytes_left - sent;
                };
                
                return total_sent;
            };
            
            // Receive exact number of bytes (keeps receiving until all data is received or error)
            def recv_all(i64 sock, byte* buffer, i32 len) -> i32
            {
                i32 total_received = 0;
                i32 bytes_left = len;
                
                while (total_received < len)
                {
                    i32 received = recv(sock, buffer + total_received, bytes_left);
                    
                    if (received == SOCKET_ERROR || received == 0)
                    {
                        return received;
                    };
                    
                    total_received = total_received + received;
                    bytes_left = bytes_left - received;
                };
                
                return total_received;
            };
            
            // Create and bind server socket
            def create_server(u16 port, i32 backlog) -> i64
            {
                i64 sock = create();
                
                if (sock == INVALID_SOCKET)
                {
                    return INVALID_SOCKET;
                };
                
                // Enable address reuse
                set_reuse_addr(sock, 1);
                
                // Bind to any address on specified port
                sockaddr_in addr = make_addr_any(port);
                
                if (bind(sock, @addr) == SOCKET_ERROR)
                {
                    close_socket(sock);
                    return INVALID_SOCKET;
                };
                
                // Listen for connections
                if (listen(sock, backlog) == SOCKET_ERROR)
                {
                    close_socket(sock);
                    return INVALID_SOCKET;
                };
                
                return sock;
            };
            
            // Connect to server
            def connect_to_server(byte* ip_addr, u16 port) -> i64
            {
                i64 sock = create();
                
                if (sock == INVALID_SOCKET)
                {
                    return INVALID_SOCKET;
                };
                
                sockaddr_in server_addr = make_addr(ip_addr, port);
                
                if (connect(sock, @server_addr) == SOCKET_ERROR)
                {
                    close_socket(sock);
                    return INVALID_SOCKET;
                };
                
                return sock;
            };
        };
        
        // ============ UDP OPERATIONS ============
        
        namespace udp
        {
            // Create a UDP socket
            def create() -> i64
            {
                return create_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
            };
            
            // Bind socket to address
            def bind(i64 sock, sockaddr_in* addr) -> i32
            {
                #ifdef __WINDOWS__
                return bind(sock, (void*)addr, 16);
                #endif;
                
                #ifdef __LINUX__
                return bind((i32)sock, (void*)addr, (u32)16);
                #endif;
                
                return SOCKET_ERROR;
            };
            
            // Send datagram to specific address
            def sendto(i64 sock, byte* xdata, i32 len, sockaddr_in* dest_addr) -> i32
            {
                #ifdef __WINDOWS__
                return sendto(sock, xdata, len, 0, (void*)dest_addr, 16);
                #endif;
                
                #ifdef __LINUX__
                return (i32)sendto((i32)sock, xdata, (u64)len, 0, (void*)dest_addr, (u32)16);
                #endif;
                
                return SOCKET_ERROR;
            };
            
            // Receive datagram and get sender address
            def recvfrom(i64 sock, byte* buffer, i32 len, sockaddr_in* src_addr) -> i32
            {
                #ifdef __WINDOWS__
                i32 addrlen = 16;
                return recvfrom(sock, buffer, len, 0, (void*)src_addr, @addrlen);
                #endif;
                
                #ifdef __LINUX__
                u32 addrlen = 16;
                return (i32)recvfrom((i32)sock, buffer, (u64)len, 0, (void*)src_addr, @addrlen);
                #endif;
                
                return SOCKET_ERROR;
            };
            
            // Create and bind UDP socket
            def create_server(u16 port) -> i64
            {
                i64 sock = create();
                
                if (sock == INVALID_SOCKET)
                {
                    return INVALID_SOCKET;
                };
                
                // Enable address reuse
                set_reuse_addr(sock, 1);
                
                // Bind to any address on specified port
                sockaddr_in addr = make_addr_any(port);
                
                if (bind(sock, @addr) == SOCKET_ERROR)
                {
                    close_socket(sock);
                    return INVALID_SOCKET;
                };
                
                return sock;
            };
            
            // Create UDP client socket
            def create_client() -> i64
            {
                return create();
            };
            
            // Enable broadcast on socket
            def enable_broadcast(i64 sock) -> i32
            {
                i32 opt = 1;
                return set_socket_option(sock, SOL_SOCKET, SO_BROADCAST, @opt, 4);
            };
        };
        
        // ============ UTILITY FUNCTIONS ============
        
        // Get hostname
        def get_hostname(byte* buffer, i32 buffer_len) -> i32
        {
            #ifdef __WINDOWS__
            return gethostname(buffer, buffer_len);
            #endif;
            
            #ifdef __LINUX__
            return gethostname(buffer, (u64)buffer_len);
            #endif;
            
            return SOCKET_ERROR;
        };
        
        // Check if socket is valid
        def is_valid_socket(i64 sock) -> bool
        {
            return sock != INVALID_SOCKET;
        };
    };
};



#endif;
