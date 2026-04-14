// Author: Karac V. Thweatt

#ifndef FLUX_STANDARD_IO
#import "io.fx";
#endif;

#ifndef FLUX_STANDARD_NET
#import "net_windows.fx";
#endif;

#ifndef FLUX_STANDARD_SOCKETS
#def FLUX_STANDARD_SOCKETS 1;

// ============ WINSOCK FFI DECLARATIONS ============
extern
{
    // Core socket functions
    def !!
        socket(int, int, int) -> int,
        bind(int, void*, int) -> int,
        listen(int, int) -> int,
        accept(int, void*, int*) -> int,
        connect(int, void*, int) -> int,
        send(int, void*, int, int) -> int,
        recv(int, void*, int, int) -> int,
        sendto(int, void*, int, int, void*, int) -> int,
        recvfrom(int, void*, int, int, void*, int*) -> int,
        closesocket(int) -> int,
        shutdown(int, int) -> int,
    
        // Socket options
        setsockopt(int, int, int, void*, int) -> int,
        getsockopt(int, int, int, void*, int*) -> int,
        
        // Address conversion
        inet_addr(byte*) -> u32,
        inet_ntoa(u32) -> byte*,
        htons(u16) -> u16,
        htonl(u32) -> u32,
        ntohs(u16) -> u16,
        ntohl(u32) -> u32,
        
        // Name resolution
        gethostbyname(byte*) -> void*,
        getaddrinfo(byte*, byte*, void*, void**) -> int,
        freeaddrinfo(void* res) -> void,
        
        // Socket control (Windows uses ioctlsocket instead of fcntl)
        ioctlsocket(int, u32, u32*) -> int,
        select(int, void*, void*, void*, void*) -> int,
        
        // WSA initialization/cleanup
        WSAStartup(u16, void*) -> int,
        WSACleanup() -> int,
        WSAGetLastError() -> int;
};

// ============ STRUCTS ============

// IPv4 socket address structure (same as Linux)
struct sockaddr_in
{
    u16 sin_family,      // Address family (AF_INET)
        sin_port;        // Port number (network byte order)
    u32 sin_addr;        // IPv4 address (network byte order)
    byte[8] sin_zero;    // Padding to match sockaddr size
};

// Generic socket address (for compatibility)
struct sockaddr
{
    u16 sa_family;       // Address family
    byte[14] sa_data;    // Address data
};

enum socket_type
{
    TCP,
    UDP
};

enum socket_error
{
    OK,
    NOT_OPEN,
    BIND_FAILED,
    CONNECT_FAILED,
    LISTEN_FAILED,
    SEND_FAILED,
    RECV_FAILED,
    INVALID_TYPE
};

// WSAData structure (simplified)
struct WSAData
{
    u16 wVersion,
        wHighVersion;
    byte[257] szDescription;
    byte[129] szSystemStatus;
    u16 iMaxSockets,
        iMaxUdpDg;
    u64* lpVendorInfo;
};

namespace standard
{
    namespace sockets
    {
        object socket
        {
            int fd, type, error_state;
            //type:            socket_type enum
            //error_state:     socket_error enum
            bool is_server, connected;
            sockaddr_in local_addr,remote_addr;

            // ===== PROTOTYPES =====
            def is_open() -> bool,
                close() -> bool,
                get_error() -> int,
                
                // TCP Server operations
                bind(u16) -> bool,
                listen(int) -> bool,
                accept() -> socket,
                
                // TCP Client operations  
                connect(byte*, u16) -> bool,
                
                // Send/Receive (works for both TCP and UDP)
                send(byte*, int) -> int,
                recv(byte*, int) -> int,
                send_all(byte*, int) -> int,
                recv_all(byte*, int) -> int,
                
                // UDP specific operations
                sendto(byte*, int, byte*, u16) -> int,
                recvfrom(byte*, int, sockaddr_in*) -> int,
                
                // Socket options
                set_nonblocking(bool) -> bool,
                set_reuseaddr(bool) -> bool,
                set_recv_timeout(int) -> bool,
                set_send_timeout(int) -> bool,
                
                // Information getters
                get_local_port() -> u16,
                get_remote_ip() -> byte*,
                get_remote_port() -> u16,
                is_tcp() -> bool,
                is_udp() -> bool;

            // ===== CONSTRUCTOR & DESTRUCTOR =====
            
            // Create a TCP socket
            def __init(int sock_type) -> this
            {
                this.type = sock_type;
                this.is_server = false;
                this.connected = false;
                this.error_state = socket_error.OK;
                return this;
            };

            def is_open() -> bool
            {
                return this.fd >= 0;
            };

            def close() -> bool
            {
                if (!this.is_open())
                {
                    return false;
                };
                
                if (this.type == socket_type.TCP)
                {
                    tcp_close(this.fd);
                }
                else
                {
                    udp_close(this.fd);
                };
                
                this.fd = -1;
                this.connected = false;
                return true;
            };

            def get_error() -> int
            {
                return this.error_state;
            };

            // ===== TCP SERVER OPERATIONS =====
            
            def bind(u16 port) -> bool
            {
                if (!this.is_open())
                {
                    this.error_state = socket_error.NOT_OPEN;
                    return false;
                };
                
                // Enable address reuse
                set_reuseaddr(this.fd, true);
                
                // Initialize address structure
                if (this.type == socket_type.TCP)
                {
                    init_sockaddr(this.local_addr, INADDR_ANY, port);
                }
                else
                {
                    init_sockaddr(this.local_addr, INADDR_ANY, port);
                };
                
                // Bind socket
                int result = bind(this.fd, this.local_addr, 16);
                if (result < 0)
                {
                    this.error_state = socket_error.BIND_FAILED;
                    return false;
                };
                
                this.is_server = true;
                return true;
            };

            def listen(int backlog) -> bool
            {
                if (!this.is_open() | this.type != socket_type.TCP)
                {
                    this.error_state = socket_error.NOT_OPEN;
                    return false;
                };
                
                if (!this.is_server)
                {
                    this.error_state = socket_error.LISTEN_FAILED;
                    return false;
                };
                
                int result = listen(this.fd, backlog);
                if (result < 0)
                {
                    this.error_state = socket_error.LISTEN_FAILED;
                    return false;
                };
                
                return true;
            };

            def accept() -> socket
            {
                if (!this.is_open() | this.type != socket_type.TCP)
                {
                    socket invalid(socket_type.TCP);
                    invalid.fd = -1;
                    invalid.error_state = socket_error.NOT_OPEN;
                    return invalid;
                };
                
                sockaddr_in client_addr;
                int client_fd = tcp_server_accept(this.fd, @client_addr);
                
                if (client_fd < 0)
                {
                    socket invalid(socket_type.TCP);
                    invalid.fd = -1;
                    invalid.error_state = socket_error.NOT_OPEN;
                    return invalid;
                };
                
                // Create new socket object for client connection
                socket client(socket_type.TCP);
                client.fd = client_fd;
                client.connected = true;
                client.is_server = false;
                client.remote_addr = client_addr;
                client.error_state = socket_error.OK;
                
                return client;
            };

            // ===== TCP CLIENT OPERATIONS =====
            
            def connect(byte* ip_addr, u16 port) -> bool
            {
                if (!this.is_open() | this.type != socket_type.TCP)
                {
                    this.error_state = socket_error.NOT_OPEN;
                    return false;
                };
                
                init_sockaddr_str(this.remote_addr, ip_addr, port);
                
                int result = connect(this.fd, this.remote_addr, 16);
                if (result < 0)
                {
                    this.error_state = socket_error.CONNECT_FAILED;
                    return false;
                };
                
                this.connected = true;
                return true;
            };

            // ===== SEND/RECEIVE OPERATIONS =====
            
            def send(byte* datax, int length) -> int
            {
                if (!this.is_open())
                {
                    this.error_state = socket_error.NOT_OPEN;
                    return -1;
                };
                
                if (this.type == socket_type.TCP & !this.connected)
                {
                    this.error_state = socket_error.SEND_FAILED;
                    return -1;
                };
                
                int result = send(this.fd, datax, length, 0);
                if (result < 0)
                {
                    this.error_state = socket_error.SEND_FAILED;
                };
                
                return result;
            };

            def recv(byte* buffer, int buffer_size) -> int
            {
                if (!this.is_open())
                {
                    this.error_state = socket_error.NOT_OPEN;
                    return -1;
                };
                
                int result = recv(this.fd, buffer, buffer_size, 0);
                if (result < 0)
                {
                    this.error_state = socket_error.RECV_FAILED;
                };
                
                return result;
            };

            def send_all(byte* datax, int length) -> int
            {
                if (!this.is_open() | this.type != socket_type.TCP)
                {
                    this.error_state = socket_error.NOT_OPEN;
                    return -1;
                };
                
                int result = tcp_send_all(this.fd, datax, length);
                if (result < 0)
                {
                    this.error_state = socket_error.SEND_FAILED;
                };
                
                return result;
            };

            def recv_all(byte* buffer, int length) -> int
            {
                if (!this.is_open() | this.type != socket_type.TCP)
                {
                    this.error_state = socket_error.NOT_OPEN;
                    return -1;
                };
                
                int result = tcp_recv_all(this.fd, buffer, length);
                if (result < 0)
                {
                    this.error_state = socket_error.RECV_FAILED;
                };
                
                return result;
            };

            // ===== UDP OPERATIONS =====
            
            def sendto(byte* datax, int length, byte* dest_ip, u16 dest_port) -> int
            {
                if (!this.is_open() | this.type != socket_type.UDP)
                {
                    this.error_state = socket_error.INVALID_TYPE;
                    return -1;
                };
                
                int result = udp_send(this.fd, datax, length, dest_ip, dest_port);
                if (result < 0)
                {
                    this.error_state = socket_error.SEND_FAILED;
                };
                
                return result;
            };

            def recvfrom(byte* buffer, int buffer_size, sockaddr_in* src_addr) -> int
            {
                if (!this.is_open() | this.type != socket_type.UDP)
                {
                    this.error_state = socket_error.INVALID_TYPE;
                    return -1;
                };
                
                int result = udp_recv(this.fd, buffer, buffer_size, src_addr);
                if (result < 0)
                {
                    this.error_state = socket_error.RECV_FAILED;
                };
                
                return result;
            };

            // ===== SOCKET OPTIONS =====
            
            def set_nonblocking(bool enable) -> bool
            {
                if (!this.is_open())
                {
                    return false;
                };
                
                int result;
                if (enable)
                {
                    result = set_nonblocking(this.fd);
                }
                else
                {
                    result = set_blocking(this.fd);
                };
                
                return result == 0;
            };

            def set_reuseaddr(bool enable) -> bool
            {
                if (!this.is_open())
                {
                    return false;
                };
                
                return set_reuseaddr(this.fd, enable) == 0;
            };

            def set_recv_timeout(int milliseconds) -> bool
            {
                if (!this.is_open())
                {
                    return false;
                };
                
                return set_recv_timeout(this.fd, milliseconds) == 0;
            };

            def set_send_timeout(int milliseconds) -> bool
            {
                if (!this.is_open())
                {
                    return false;
                };
                
                return set_send_timeout(this.fd, milliseconds) == 0;
            };

            // ===== INFORMATION GETTERS =====
            
            def get_local_port() -> u16
            {
                return get_port(this.local_addr);
            };

            def get_remote_ip() -> byte*
            {
                return get_ip_string(this.remote_addr);
            };

            def get_remote_port() -> u16
            {
                return get_port(this.remote_addr);
            };

            def is_tcp() -> bool
            {
                return this.type == socket_type.TCP;
            };

            def is_udp() -> bool
            {
                return this.type == socket_type.UDP;
            };

            def __exit() -> void
            {
                this.close();
                return;
            };
        };

        // ============ CONSTANTS ============
        
        // Address families
        global const int AF_UNSPEC = 0,
                         AF_INET = 2,      // IPv4
                         AF_INET6 = 23,    // IPv6 (different on Windows!)
        
        // Socket types
                         SOCK_STREAM = 1,  // TCP
                         SOCK_DGRAM = 2,   // UDP
                         SOCK_RAW = 3,
        
        // Protocol
                         IPPROTO_TCP = 6,
                         IPPROTO_UDP = 17,
        
        // Socket options levels
                         SOL_SOCKET = 0xFFFF,  // Different on Windows!
        
        // Socket options
                         SO_REUSEADDR = 0x0004,
                         SO_KEEPALIVE = 0x0008.
                         SO_BROADCAST = 0x0020,
                         SO_RCVBUF = 0x1002,
                         SO_SNDBUF = 0x1001,
                         SO_RCVTIMEO = 0x1006,
                         SO_SNDTIMEO = 0x1005,
        
        // Shutdown modes
                         SD_RECEIVE = 0x00,    // Shutdown receive (same as SHUT_RD)
                         SD_SEND = 0x01,       // Shutdown send (same as SHUT_WR)
                         SD_BOTH = 0x02,       // Shutdown both (same as SHUT_RDWR)
        // Error codes
                         SOCKET_ERROR = -1,
                         INVALID_SOCKET = -1,
        
        // WSA Error codes (some common ones)
                         WSAEWOULDBLOCK = 10035,
                         WSAECONNRESET = 10054,
                         WSAETIMEDOUT = 10060;
        
        // ioctlsocket commands (replaces fcntl)
        global const u32 FIONBIO = 0x8004667E,  // Set non-blocking mode
                         FIONREAD = 0x4004667F, // Get number of bytes available
        // Special addresses
                         INADDR_ANY = 0x00000000,
                         INADDR_LOOPBACK = 0x7F000001,  // 127.0.0.1
                         INADDR_BROADCAST = 0xFFFFFFFF;
        
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
            addr.sin_family = (u16)AF_INET;
            addr.sin_port = htons(port);
            addr.sin_addr = ip_addr;
            
            // Zero out padding
            int i;
            while (i < 8)
            {
                addr.sin_zero[i] = '\0';
                i = i + 1;
            };
        };
        
        // Initialize sockaddr_in with string IP (dotted decimal)
        def init_sockaddr_str(sockaddr_in* addr, byte* ip_str, u16 port) -> void
        {
            addr.sin_family = (u16)AF_INET;
            addr.sin_port = htons(port);
            addr.sin_addr = htonl(inet_addr(ip_str));
            
            // Zero out padding
            int i;
            while (i < 8)
            {
                addr.sin_zero[i] = (byte)0;
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
            u32 mode;  // 0 = blocking, 1 = non-blocking
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
                standard::io::console::print("Failed at sockfd < 0\n\0");
                return -1;
            };
            
            // Enable address reuse
            set_reuseaddr(sockfd, true);

            // Bind to address
            sockaddr_in addr;

            u16 port_network = htons(8080);

            addr.sin_family = 2;
            addr.sin_port = port_network;
            addr.sin_addr = 0;  // Try without htonl

            init_sockaddr(@addr, INADDR_ANY, port);
            int bind_result = bind(sockfd, @addr, 16);
            if (bind_result < 0)
            {
                standard::io::console::print("Failed to bind socket. Result: \0");
                standard::io::console::print(bind_result);
                standard::io::console::print();
                standard::io::console::print("get_last_error() = \0");
                standard::io::console::print(get_last_error());
                standard::io::console::print();
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

            int connect_result = connect(sockfd, @addr, 16);

            if (connect_result < 0)
            {
                int err = get_last_error();  // Call it RIGHT HERE
                standard::io::console::print("connect failed. WSA Error: \0");
                standard::io::console::print(err);
                standard::io::console::print();
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

using standard::sockets;

#endif;