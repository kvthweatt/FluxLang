// Author: Karac V. Thweatt

// rednet_linux.fx - Flux Linux Networking Library
// Linux socket API: TCP, UDP, Unix domain sockets, epoll, SCM_RIGHTS fd passing.
// Socket externs come from redlinux.fx.

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_NET_LINUX
#def FLUX_STANDARD_NET_LINUX 1;

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "memory.fx";
#endif;

#ifndef __LINUX_INTERFACE__
#import "linux.fx";
#endif;

// ============================================================================
// ADDITIONAL EXTERNS NOT IN REDLINUX
// ============================================================================

#ifdef __LINUX__
extern
{
    def !!
        htons(u16)      -> u16,
        htonl(u32)      -> u32,
        ntohs(u16)      -> u16,
        ntohl(u32)      -> u32,
        inet_addr(byte*) -> u32,
        inet_ntoa(u32)  -> byte*,
        getaddrinfo(byte*, byte*, void*, void**) -> int,
        freeaddrinfo(void*)                      -> void,
        getnameinfo(void*, u32, byte*, u32, byte*, u32, int) -> int,
        gethostname(byte*, size_t)               -> int,
        select(int, void*, void*, void*, void*)  -> int;
};
#endif;

// ============================================================================
// STRUCTURES
// ============================================================================

// addrinfo for getaddrinfo
struct addrinfo
{
    int    ai_flags,
           ai_family,
           ai_socktype,
           ai_protocol;
    u32    ai_addrlen;
    byte*  ai_canonname;
    void*  ai_addr,
           ai_next;
};

// fd_set for select() - 1024 fds, 128 bytes
struct fd_set_t
{
    byte[128] fds_bits;
};

// ============================================================================
// NAMESPACE
// ============================================================================

namespace standard
{
    namespace net
    {
        // ====================================================================
        // CONSTANTS
        // ====================================================================

        // Address families
        global const int AF_UNSPEC  = 0,
                         AF_UNIX    = 1,
                         AF_INET    = 2,
                         AF_INET6   = 10,

        // Socket types
                         SOCK_STREAM    = 1,
                         SOCK_DGRAM     = 2,
                         SOCK_RAW       = 3,
                         SOCK_NONBLOCK  = 0x800,
                         SOCK_CLOEXEC   = 0x80000,

        // Protocols
                         IPPROTO_TCP = 6,
                         IPPROTO_UDP = 17,

        // Socket options
                         SO_REUSEADDR = 2,
                         SO_KEEPALIVE = 9,
                         SO_BROADCAST = 6,
                         SO_RCVBUF    = 8,
                         SO_SNDBUF    = 7,
                         SO_RCVTIMEO  = 20,
                         SO_SNDTIMEO  = 21,
                         SO_ERROR     = 4,
                         SO_TYPE      = 3,

        // SOL_SOCKET level
                         SOL_SOCKET = 1,

        // Shutdown modes
                         SHUT_RD   = 0,
                         SHUT_WR   = 1,
                         SHUT_RDWR = 2,

        // fcntl flags for non-blocking
                         O_NONBLOCK = 0x800,

        // CMsghdr levels/types for SCM_RIGHTS
                         SCM_RIGHTS = 1,
        // Error sentinel
                         INVALID_SOCKET = -1,
                         SOCKET_ERROR   = -1;

        // Special addresses
        global const u32 INADDR_ANY       = 0x00000000,
                         INADDR_LOOPBACK  = 0x7F000001,
                         INADDR_BROADCAST = 0xFFFFFFFF;

        // ====================================================================
        // HELPERS
        // ====================================================================

        def is_valid_socket(int fd) -> bool
        {
            return fd >= 0;
        };

        // Set socket non-blocking via fcntl
        def set_nonblocking(int fd) -> int
        {
            int flags = fcntl(fd, 3, 0);   // F_GETFL
            if (flags < 0)
            {
                return -1;
            };
            return fcntl(fd, 4, flags | O_NONBLOCK);   // F_SETFL
        };

        // Set socket blocking
        def set_blocking(int fd) -> int
        {
            int flags = fcntl(fd, 3, 0);   // F_GETFL
            if (flags < 0)
            {
                return -1;
            };
            return fcntl(fd, 4, flags & `!O_NONBLOCK);  // F_SETFL
        };

        // Enable SO_REUSEADDR
        def set_reuseaddr(int fd, bool enable) -> int
        {
            int val = 0;
            if (enable) { val = 1; };
            return setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (void*)@val, (u32)4);
        };

        // Set receive timeout (timeval)
        def set_recv_timeout(int fd, int seconds, int microseconds) -> int
        {
            standard::system::linux::timeval tv;
            tv.tv_sec  = seconds;
            tv.tv_usec = microseconds;
            return setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, (void*)@tv, (u32)sizeof(standard::system::linux::timeval));
        };

        // Set send timeout
        def set_send_timeout(int fd, int seconds, int microseconds) -> int
        {
            standard::system::linux::timeval tv;
            tv.tv_sec  = seconds;
            tv.tv_usec = microseconds;
            return setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, (void*)@tv, (u32)sizeof(standard::system::linux::timeval));
        };

        // Convert port to/from network byte order
        def port_hton(u16 p) -> u16 { return htons(p); };
        def port_ntoh(u16 p) -> u16 { return ntohs(p); };

        // ====================================================================
        // TCP
        // ====================================================================

        def tcp_socket() -> int
        {
            return socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        };

        // Initialize IPv4 sockaddr_in
        def init_sockaddr(standard::system::linux::sockaddr_in* addr, u32 ip, u16 port) -> void
        {
            addr.family = AF_INET;
            addr.port   = htons(port);
            addr.addr   = ip;
            int i;
            while (i < 8)
            {
                addr.pad[i] = 0;
                i++;
            };
            return;
        };

        // Create and bind a TCP server socket
        def tcp_server_create(u16 port, int backlog) -> int
        {
            int fd = tcp_socket();
            if (fd < 0) { return -1; };

            set_reuseaddr(fd, true);

            standard::system::linux::sockaddr_in addr;
            init_sockaddr(@addr, INADDR_ANY, port);

            if (bind(fd, (void*)@addr, (u32)sizeof(standard::system::linux::sockaddr_in)) < 0)
            {
                close(fd);
                return -1;
            };

            if (listen(fd, backlog) < 0)
            {
                close(fd);
                return -1;
            };

            return fd;
        };

        // Accept a connection
        def tcp_server_accept(int server_fd, standard::system::linux::sockaddr_in* client_addr) -> int
        {
            u32 addr_len = (u32)sizeof(standard::system::linux::sockaddr_in);
            return accept(server_fd, (void*)client_addr, @addr_len);
        };

        // Connect to a TCP server by IP string
        def tcp_client_connect(byte* ip_str, u16 port) -> int
        {
            int fd = tcp_socket();
            if (fd < 0) { return -1; };

            standard::system::linux::sockaddr_in addr;
            init_sockaddr(@addr, inet_addr(ip_str), port);

            if (connect(fd, (void*)@addr, (u32)sizeof(standard::system::linux::sockaddr_in)) < 0)
            {
                close(fd);
                return -1;
            };

            return fd;
        };

        def tcp_send(int fd, byte* buf, int len) -> int
        {
            return (int)send(fd, (void*)buf, (size_t)len, 0);
        };

        def tcp_recv(int fd, byte* buf, int len) -> int
        {
            return (int)recv(fd, (void*)buf, (size_t)len, 0);
        };

        def tcp_send_all(int fd, byte* buf, int len) -> int
        {
            int sent = 0;
            while (sent < len)
            {
                int n = (int)send(fd, (void*)(buf + sent), (size_t)(len - sent), 0);
                if (n <= 0) { return -1; };
                sent = sent + n;
            };
            return sent;
        };

        def tcp_recv_all(int fd, byte* buf, int len) -> int
        {
            int got = 0;
            while (got < len)
            {
                int n = (int)recv(fd, (void*)(buf + got), (size_t)(len - got), 0);
                if (n <= 0) { return -1; };
                got = got + n;
            };
            return got;
        };

        def tcp_close(int fd) -> int
        {
            shutdown(fd, SHUT_RDWR);
            return close(fd);
        };

        // ====================================================================
        // UDP
        // ====================================================================

        def udp_socket() -> int
        {
            return socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        };

        def udp_socket_bind(u16 port) -> int
        {
            int fd = udp_socket();
            if (fd < 0) { return -1; };

            standard::system::linux::sockaddr_in addr;
            init_sockaddr(@addr, INADDR_ANY, port);

            if (bind(fd, (void*)@addr, (u32)sizeof(standard::system::linux::sockaddr_in)) < 0)
            {
                close(fd);
                return -1;
            };

            return fd;
        };

        def udp_send(int fd, byte* buf, int len, byte* dest_ip, u16 dest_port) -> int
        {
            standard::system::linux::sockaddr_in addr;
            init_sockaddr(@addr, inet_addr(dest_ip), dest_port);
            return (int)sendmsg(fd, (void*)@addr, 0);
        };

        def udp_recv(int fd, byte* buf, int buf_size, standard::system::linux::sockaddr_in* src_addr) -> int
        {
            u32 addr_len = (u32)sizeof(standard::system::linux::sockaddr_in);
            return (int)recvmsg(fd, (void*)src_addr, 0);
        };

        def udp_close(int fd) -> int
        {
            return close(fd);
        };

        // ====================================================================
        // UNIX DOMAIN SOCKETS
        // ====================================================================

        // Connect to a Unix domain socket by path
        def unix_connect(byte* path) -> int
        {
            standard::system::linux::sockaddr_un addr;
            memset((void*)@addr, 0, (size_t)sizeof(standard::system::linux::sockaddr_un));
            addr.family = (u16)AF_UNIX;

            int path_len = standard::strings::strlen(path);
            memcpy((void*)@addr.path, (void*)path, (size_t)path_len);

            int fd = socket(AF_UNIX, SOCK_STREAM, 0);
            if (fd < 0) { return -1; };

            if (connect(fd, (void*)@addr, (u32)(2 + path_len + 1)) < 0)
            {
                close(fd);
                return -1;
            };

            return fd;
        };

        // Create and bind a Unix domain socket server
        def unix_server_create(byte* path, int backlog) -> int
        {
            unlink(path);   // Remove stale socket file

            standard::system::linux::sockaddr_un addr;
            memset((void*)@addr, 0, (size_t)sizeof(standard::system::linux::sockaddr_un));
            addr.family = (u16)AF_UNIX;

            int path_len = standard::strings::strlen(path);
            memcpy((void*)@addr.path, (void*)path, (size_t)path_len);

            int fd = socket(AF_UNIX, SOCK_STREAM, 0);
            if (fd < 0) { return -1; };

            if (bind(fd, (void*)@addr, (u32)sizeof(standard::system::linux::sockaddr_un)) < 0)
            {
                close(fd);
                return -1;
            };

            if (listen(fd, backlog) < 0)
            {
                close(fd);
                return -1;
            };

            return fd;
        };

        // ====================================================================
        // SCM_RIGHTS - pass file descriptors over Unix sockets
        // ====================================================================

        // Send a file descriptor over a Unix socket
        def send_fd(int sock, int fd_to_send) -> bool
        {
            return standard::system::linux::send_fd(sock, fd_to_send);
        };

        // ====================================================================
        // EPOLL
        // ====================================================================

        def epoll_create() -> int
        {
            return epoll_create1(0);
        };

        def epoll_add(int epfd, int fd, u32 events) -> int
        {
            standard::system::linux::epoll_event ev;
            ev.events   = events;
            ev.evt_data = (u64)fd;
            return epoll_ctl(epfd, (int)standard::system::linux::EpollOp.EPOLL_CTL_ADD, fd, (void*)@ev);
        };

        def epoll_del(int epfd, int fd) -> int
        {
            standard::system::linux::epoll_event ev;
            ev.events   = (u32)0;
            ev.evt_data = (u64)0;
            return epoll_ctl(epfd, (int)standard::system::linux::EpollOp.EPOLL_CTL_DEL, fd, (void*)@ev);
        };

        // Wait for events, returns number of ready fds
        def epoll_wait_events(int epfd, standard::system::linux::epoll_event* events, int max_events, int timeout_ms) -> int
        {
            return epoll_wait(epfd, (void*)events, max_events, timeout_ms);
        };

        // ====================================================================
        // UTILITY
        // ====================================================================

        def get_ip_string(standard::system::linux::sockaddr_in* addr) -> byte*
        {
            return inet_ntoa(addr.addr);
        };

        def get_port(standard::system::linux::sockaddr_in* addr) -> u16
        {
            return ntohs(addr.port);
        };
    };
};

using standard::net;

#endif;
