// net.fx - Flux Networking Library - Pure Assembly Implementation
// Copyright (C) 2026 Karac Thweatt
// License: MIT

import "standard.fx";
using standard::io, standard::types;

// ============ SYSTEM CALL NUMBERS ============

compt
{
    if (def(LINUX))
    {
        global def SYS_SOCKET 41;
        global def SYS_BIND 49;
        global def SYS_CONNECT 42;
        global def SYS_LISTEN 50;
        global def SYS_ACCEPT 43;
        global def SYS_SENDTO 44;
        global def SYS_RECVFROM 45;
        global def SYS_CLOSE 3;
        global def SYS_FCNTL 72;
        global def SYS_SETSOCKOPT 54;
        global def SYS_GETSOCKOPT 55;
        
        // Socket domains
        global def AF_INET 2;
        global def AF_INET6 10;
        global def AF_PACKET 17;
        
        // Socket types
        global def SOCK_STREAM 1;
        global def SOCK_DGRAM 2;
        global def SOCK_RAW 3;
        
        // Protocols
        global def IPPROTO_TCP 6;
        global def IPPROTO_UDP 17;
        global def IPPROTO_RAW 255;
        
        // Options
        global def SOL_SOCKET 1;
        global def SO_REUSEADDR 2;
        global def SO_BROADCAST 6;
        global def SO_RCVTIMEO 20;
        global def SO_SNDTIMEO 21;
        
    }
    elif (def(MACOS))
    {
        global def SYS_SOCKET 97;
        global def SYS_BIND 104;
        global def SYS_CONNECT 98;
        global def SYS_LISTEN 106;
        global def SYS_ACCEPT 30;
        global def SYS_SENDTO 133;
        global def SYS_RECVFROM 134;
        global def SYS_CLOSE 6;
        
        global def AF_INET 2;
        global def SOCK_STREAM 1;
        global def SOCK_DGRAM 2;
        global def IPPROTO_TCP 6;
        global def IPPROTO_UDP 17;
        
    }
    elif (def(WINDOWS))
    {
        // Windows would need different assembly (Winsock)
        // For now, we'll focus on Unix-like systems
    };
};

// ============ RAW SOCKET SYSTEM CALLS ============

namespace Syscalls
{
    def socket(int domain, int type, int protocol) -> int
    {
        int result = -1;
        volatile asm
        {
            movq    $SYS_SOCKET, %rax
            movq    domain, %rdi
            movq    type, %rsi
            movq    protocol, %rdx
            syscall
            movq    %rax, result
        };
        return result;
    };
    
    def bind(int sockfd, void* addr, unsigned data{32} addrlen) -> int
    {
        int result = -1;
        volatile asm
        {
            movq    $SYS_BIND, %rax
            movq    sockfd, %rdi
            movq    addr, %rsi
            movq    addrlen, %rdx
            syscall
            movq    %rax, result
        };
        return result;
    };
    
    def connect(int sockfd, void* addr, unsigned data{32} addrlen) -> int
    {
        int result = -1;
        volatile asm
        {
            movq    $SYS_CONNECT, %rax
            movq    sockfd, %rdi
            movq    addr, %rsi
            movq    addrlen, %rdx
            syscall
            movq    %rax, result
        };
        return result;
    };
    
    def listen(int sockfd, int backlog) -> int
    {
        int result = -1;
        volatile asm
        {
            movq    $SYS_LISTEN, %rax
            movq    sockfd, %rdi
            movq    backlog, %rsi
            syscall
            movq    %rax, result
        };
        return result;
    };
    
    def accept(int sockfd, void* addr, unsigned data{32}* addrlen) -> int
    {
        int result = -1;
        volatile asm
        {
            movq    $SYS_ACCEPT, %rax
            movq    sockfd, %rdi
            movq    addr, %rsi
            movq    addrlen, %rdx
            syscall
            movq    %rax, result
        };
        return result;
    };
    
    def send(int sockfd, void* buf, size_t len, int flags) -> size_t
    {
        size_t result = 0;
        volatile asm
        {
            movq    $SYS_SENDTO, %rax
            movq    sockfd, %rdi
            movq    buf, %rsi
            movq    len, %rdx
            movq    flags, %r10
            xorq    %r8, %r8      // dest_addr = NULL
            xorq    %r9, %r9      // addrlen = 0
            syscall
            movq    %rax, result
        };
        return result;
    };
    
    def recv(int sockfd, void* buf, size_t len, int flags) -> size_t
    {
        size_t result = 0;
        volatile asm
        {
            movq    $SYS_RECVFROM, %rax
            movq    sockfd, %rdi
            movq    buf, %rsi
            movq    len, %rdx
            movq    flags, %r10
            xorq    %r8, %r8      // src_addr = NULL
            xorq    %r9, %r9      // addrlen = NULL
            syscall
            movq    %rax, result
        };
        return result;
    };
    
    def close(int fd) -> int
    {
        int result = -1;
        volatile asm {
            movq    $SYS_CLOSE, %rax
            movq    fd, %rdi
            syscall
            movq    %rax, result
        };
        return result;
    };
    
    def setsockopt(int sockfd, int level, int optname, void* optval, unsigned data{32} optlen) -> int
    {
        int result = -1;
        volatile asm
        {
            movq    $SYS_SETSOCKOPT, %rax
            movq    sockfd, %rdi
            movq    level, %rsi
            movq    optname, %rdx
            movq    optval, %r10
            movq    optlen, %r8
            syscall
            movq    %rax, result
        };
        return result;
    };
};

// ============ NETWORK STRUCTS (Bit-exact) ============

// sockaddr_in for IPv4
struct SockAddrIn
{
    unsigned data{16} sin_family;    // AF_INET = 2
    unsigned data{16} sin_port;      // Port in network byte order
    unsigned data{32} sin_addr;      // IPv4 address
    unsigned data{64} sin_zero;      // Padding to 16 bytes
};

// sockaddr_in6 for IPv6  
struct SockAddrIn6
{
    unsigned data{16} sin6_family;   // AF_INET6 = 10
    unsigned data{16} sin6_port;     // Port in network byte order
    unsigned data{32} sin6_flowinfo; // IPv6 flow information
    unsigned data{128} sin6_addr;    // IPv6 address
    unsigned data{32} sin6_scope_id; // Scope ID
};

// Generic sockaddr for casting
struct SockAddr
{
    unsigned data{16} sa_family;     // Address family
    unsigned data{112} sa_data;      // Address data (14 bytes)
};

// ============ SOCKET OBJECT ============

object Socket
{
    private
    {
        int fd = -1;
        int domain;
        int type;
        int protocol;
    };
    
    public
    {
        def __init(int domain, int type, int protocol) -> this
        {
            this.fd = Syscalls::socket(domain, type, protocol);
            if (this.fd < 0)
            {
                throw("Failed to create socket");
            };
            this.domain = domain;
            this.type = type;
            this.protocol = protocol;
            return this;
        };
        
        def __exit() -> void
        {
            if (this.fd >= 0)
            {
                Syscalls::close(this.fd);
            };
            return void;
        };
        
        def bind_ipv4(unsigned data{32} ip, int port) -> void
        {
            SockAddrIn addr;
            addr.sin_family = AF_INET;
            addr.sin_port = htons(port);
            addr.sin_addr = ip;
            addr.sin_zero = 0;
            
            if (Syscalls::bind(this.fd, @addr, sizeof(addr)) < 0)
            {
                throw("Failed to bind socket");
            };
            return void;
        };
        
        def connect_ipv4(unsigned data{32} ip, int port) -> void
        {
            SockAddrIn addr;
            addr.sin_family = AF_INET;
            addr.sin_port = htons(port);
            addr.sin_addr = ip;
            addr.sin_zero = 0;
            
            if (Syscalls::connect(this.fd, @addr, sizeof(addr)) < 0)
            {
                throw("Failed to connect");
            };
            return void;
        };
        
        def listen(int backlog) -> void
        {
            if (Syscalls::listen(this.fd, backlog) < 0)
            {
                throw("Failed to listen");
            };
            return void;
        };
        
        def accept() -> Socket
        {
            SockAddrIn client_addr;
            unsigned data{32} addr_len = sizeof(client_addr);
            
            int client_fd = Syscalls::accept(this.fd, @client_addr, @addr_len);
            if (client_fd < 0)
            {
                throw("Failed to accept connection");
            };
            
            Socket client = Socket();
            client.fd = client_fd;
            client.domain = this.domain;
            client.type = this.type;
            client.protocol = this.protocol;
            
            return client;
        };
        
        def send(byte[] data) -> int
        {
            int sent = Syscalls::send(this.fd, data.ptr, data.len, 0);
            if (sent < 0)
            {
                throw("Failed to send data");
            };
            return sent;
        };
        
        def receive(int max_size) -> byte[]
        {
            byte[] buffer = byte[max_size];
            int received = Syscalls::recv(this.fd, buffer.ptr, max_size, 0);
            
            if (received < 0)
            {
                throw("Failed to receive data");
            };
            
            // Resize to actual received data
            buffer.len = received;
            return buffer;
        };
        
        def set_reuseaddr(bool enable) -> void
        {
            int val = enable ? 1 : 0;
            if (Syscalls::setsockopt(this.fd, SOL_SOCKET, SO_REUSEADDR, @val, sizeof(val)) < 0)
            {
                throw("Failed to set SO_REUSEADDR");
            };
            return void;
        };
        
        def get_fd() -> int
        {
            return this.fd;
        };
    };
};

// ============ BYTE ORDER HELPERS ============

def htons(unsigned data{16} hostshort) -> unsigned data{16}
{
    return (hostshort >> 8) | (hostshort << 8);
};

def htonl(unsigned data{32} hostlong) -> unsigned data{32}
{
    return (hostlong >> 24) |
           ((hostlong >> 8) & 0x0000FF00) |
           ((hostlong << 8) & 0x00FF0000) |
           (hostlong << 24);
};

def ntohs(unsigned data{16} netshort) -> unsigned data{16}
{
    return htons(netshort);
};

def ntohl(unsigned data{32} netlong) -> unsigned data{32}
{
    return htonl(netlong);
};

// ============ RAW PACKET SOCKET ============

object RawSocket
{
    private
    {
        Socket socket;
    };
    
    public
    {
        def __init() -> this
        {
            this.socket = Socket(AF_PACKET, SOCK_RAW, htons(0x0003));  // ETH_P_ALL
            return this;
        };
        
        def __exit() -> void
        {
            return void;
        };
        
        def send_frame(byte[] frame) -> int
        {
            return this.socket.send(frame);
        };
        
        def receive_frame() -> byte[]
        {
            // Ethernet frame max size (1518 bytes) + 4 for VLAN tag
            return this.socket.receive(1522);
        };
        
        def bind_interface(string ifname) -> void
        {
            // TODO: Implement interface binding
            // Would need struct sockaddr_ll and SIOCGIFINDEX ioctl
            return void;
        };
    };
};

// ============ PACKET CONSTRUCTORS ============

namespace Packets
{
    def create_arp_request(unsigned data{48} src_mac, unsigned data{32} src_ip, unsigned data{32} target_ip) -> byte[]
    {
        // ARP packet: 14 bytes Ethernet + 28 bytes ARP
        byte[] packet = byte[42];
        
        // Ethernet header
        EthernetHeader eth;
        eth.dst_mac = 0xFFFFFFFFFFFF;  // Broadcast
        eth.src_mac = src_mac;
        eth.ethertype = 0x0806;  // ARP
        
        packet[0:13] = (byte[])eth;
        
        // ARP payload
        packet[14] = 0x00;  // HTYPE = 1 (Ethernet)
        packet[15] = 0x01;
        packet[16] = 0x08;  // PTYPE = 0x0800 (IPv4)
        packet[17] = 0x00;
        packet[18] = 0x06;  // HLEN = 6
        packet[19] = 0x04;  // PLEN = 4
        packet[20] = 0x00;  // OPER = 1 (Request)
        packet[21] = 0x01;
        
        // Sender MAC
        for (int i = 0; i < 6; i++)
        {
            packet[22 + i] = (src_mac >> (40 - i*8)) & 0xFF;
        };
        
        // Sender IP
        for (int i = 0; i < 4; i++)
        {
            packet[28 + i] = (src_ip >> (24 - i*8)) & 0xFF;
        };
        
        // Target MAC (00:00:00:00:00:00)
        for (int i = 0; i < 6; i++)
        {
            packet[32 + i] = 0;
        };
        
        // Target IP
        for (int i = 0; i < 4; i++)
        {
            packet[38 + i] = (target_ip >> (24 - i*8)) & 0xFF;
        };
        
        return packet;
    };
    
    def create_icmp_echo(unsigned data{32} src_ip, unsigned data{32} dst_ip, unsigned data{16} id, unsigned data{16} seq) -> byte[]
    {
        // Ethernet + IP + ICMP echo request
        byte[] packet = byte[98];  // 14 + 20 + 64
        
        // Ethernet header
        EthernetHeader eth;
        eth.dst_mac = 0xFFFFFFFFFFFF;  // Will be replaced by gateway MAC
        eth.src_mac = 0x001122334455;  // Source MAC
        eth.ethertype = 0x0800;
        
        packet[0:13] = (byte[])eth;
        
        // IP header
        IPv4Header ip;
        ip.version = 4;
        ip.ihl = 5;
        ip.tos = 0;
        ip.total_length = htons(84);  // 20 + 64
        ip.identification = htons(0x1234);
        ip.flags = 0b010;  // Don't fragment
        ip.fragment_offset = 0;
        ip.ttl = 64;
        ip.protocol = 1;  // ICMP
        ip.checksum = 0;
        ip.src_addr = src_ip;
        ip.dst_addr = dst_ip;
        
        // Calculate IP checksum
        byte[] ip_bytes = (byte[])ip;
        unsigned data{32} sum = 0;
        for (int i = 0; i < 20; i += 2)
        {
            sum += ((unsigned data{16})ip_bytes[i] << 8) | ip_bytes[i + 1];
        };
        while (sum >> 16)
        {
            sum = (sum & 0xFFFF) + (sum >> 16);
        };
        ip.checksum = sum;
        
        packet[14:33] = (byte[])ip;
        
        // ICMP echo request (type 8, code 0)
        packet[34] = 8;   // Type
        packet[35] = 0;   // Code
        packet[36] = 0;   // Checksum (to be filled)
        packet[37] = 0;
        packet[38] = id >> 8;     // Identifier
        packet[39] = id & 0xFF;
        packet[40] = seq >> 8;    // Sequence number
        packet[41] = seq & 0xFF;
        
        // Payload (56 bytes of data)
        for (int i = 0; i < 56; i++)
        {
            packet[42 + i] = i;
        };
        
        // Calculate ICMP checksum
        sum = 0;
        for (int i = 34; i < 98; i += 2)
        {
            if (i == 98 - 1)
            {
                sum += ((unsigned data{16})packet[i]) << 8;
            }
            else
            {
                sum += ((unsigned data{16})packet[i] << 8) | packet[i + 1];
            };
        };
        while (sum >> 16)
        {
            sum = (sum & 0xFFFF) + (sum >> 16);
        };
        unsigned data{16} checksum = sum;
        
        packet[36] = checksum >> 8;
        packet[37] = checksum & 0xFF;
        
        return packet;
    };
};

// ============ ETHERNET TYPES ============

struct EthernetHeader
{
    unsigned data{48} dst_mac;
    unsigned data{48} src_mac;
    unsigned data{16} ethertype;
};

struct IPv4Header
{
    unsigned data{4} version;
    unsigned data{4} ihl;
    unsigned data{8} tos;
    unsigned data{16} total_length;
    unsigned data{16} identification;
    unsigned data{3} flags;
    unsigned data{13} fragment_offset;
    unsigned data{8} ttl;
    unsigned data{8} protocol;
    unsigned data{16} checksum;
    unsigned data{32} src_addr;
    unsigned data{32} dst_addr;
};

// ============ EXAMPLE: PING UTILITY ============

object Ping
{
    private
    {
        RawSocket raw_sock;
        unsigned data{32} src_ip;
        unsigned data{32} dst_ip;
        unsigned data{16} identifier;
    };
    
    public
    {
        def __init(unsigned data{32} dst) -> this
        {
            this.raw_sock = RawSocket();
            this.dst_ip = dst;
            this.identifier = 0x1234;
            // TODO: Get source IP from routing table
            this.src_ip = 0xC0A80001;  // 192.168.0.1
            return this;
        };
        
        def __exit() -> void
        {
            return void;
        };
        
        def send_echo(int seq) -> void
        {
            byte[] packet = Packets::create_icmp_echo(this.src_ip, this.dst_ip, this.identifier, seq);
            
            this.raw_sock.send_frame(packet);
            return void;
        };
        
        def wait_reply(int timeout_ms) -> bool
        {
            // TODO: Implement timeout and reply parsing
            byte[] reply = this.raw_sock.receive_frame();
            
            // Parse Ethernet frame
            EthernetHeader eth = (EthernetHeader)reply[0:13];
            if (ntohs(eth.ethertype) != 0x0800)
            {
                return false;
            };
            
            // Parse IP header
            IPv4Header ip = (IPv4Header)reply[14:33];
            if (ip.protocol != 1)
            {   // Not ICMP
                return false;
            };
            
            // Check if it's an ICMP echo reply (type 0)
            if (reply[34] == 0)
            {
                return true;
            };
            
            return false;
        };
    };
};

// ============ SIMPLE TCP SERVER EXAMPLE ============

def tcp_echo_server(int port) -> void
{
    try
    {
        Socket server = Socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        server.set_reuseaddr(true);
        server.bind_ipv4(0, port);  // 0 = INADDR_ANY
        server.listen(10);
        
        print(f"TCP echo server listening on port {port}");
        
        while (true)
        {
            Socket client = server.accept();
            print("Client connected");
            
            byte[] data = client.receive(1024);
            print(f"Received: {data.len} bytes");
            
            client.send(data);
            print(f"Echoed: {data.len} bytes");
            
            // Client will be destroyed when out of scope
        };
    }
    catch (string error)
    {
        print(f"Server error: {error}");
    };
    return void;
};

// ============ SIMPLE UDP CLIENT EXAMPLE ============

def udp_echo_client(string server_ip, int port, string message) -> void
{
    try
    {
        Socket sock = Socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        
        // Convert IP string to binary (simple version)
        unsigned data{32} ip = 0;
        // TODO: Parse IP string properly
        
        sock.connect_ipv4(ip, port);
        
        byte[] data = (byte[])message;
        sock.send(data);
        
        byte[] reply = sock.receive(1024);
        print(f"Reply: {(string)reply}");
    }
    catch (string error)
    {
        print(f"Client error: {error}");
    };
    return void;
};