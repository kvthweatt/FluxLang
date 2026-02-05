#ifndef FLUX_STANDARD_IO
#import "redio.fx";
#endif;

#ifndef FLUX_STANDARD_NET
#import "rednet_windows.fx";
#endif;

#ifndef FLUX_STANDARD_SOCKETS
#def FLUX_STANDARD_SOCKETS 1;

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
            sockaddr_in local_addr;
            sockaddr_in remote_addr;

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
                int client_fd = tcp_server_accept(this.fd, client_addr);
                
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
                client.remote_addr = *client_addr;
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
    };
};

using standard::sockets;

#endif;