#import "standard.fx";
//#import "network.fx";

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
            int network_initialized = 0;
            if ((bool)network_initialized)
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
            #endif;
            
            #ifdef __LINUX__
            network_initialized = 1;
            return 0;
            #endif;
            
            return result;
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
            #endif;
            
            #ifdef __LINUX__
            network_initialized = 0;
            return 0;
            #endif;
            
            return result;
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
        };


        // Create a socket
        /// Crash
        def create_socket(i32 family, i32 type, i32 protocol) -> i64
        {
            #ifdef __WINDOWS__
            return socket(family, type, protocol);
            #endif;
            
            #ifdef __LINUX__
            return (i64)socket(family, type, protocol);
            #endif;
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
        };
        

        def shutdown_socket(i64 sock, i32 how) -> i32
        {
            #ifdef __WINDOWS__
            return shutdown(sock, how);
            #endif;
            
            #ifdef __LINUX__
            return shutdown((i32)sock, how);
            #endif;
        };
        ///


        // ============ ADDRESS MANIPULATION ============
        

def main() -> int
{///
    standard::net::init();
    
    i64 server = standard::tcp::create_server(8080, 10);
    
    while (1)
    {
        net::sockaddr_in client_addr;
        i64 client = standard::tcp::accept(server, @client_addr);
        
        byte[1024] buffer;
        i32 received = standard::tcp::recv(client, buffer, 1024);
        standard::tcp::send_all(client, buffer, received);
        
        standard::net::close_socket(client);
    };
    
    standard::net::cleanup();///
    return 0;
};