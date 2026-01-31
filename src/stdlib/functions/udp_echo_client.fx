// UDP Echo Client Example
// Demonstrates using the Flux networking library to create a simple UDP client
// that sends datagrams to a server and receives responses

#import "standard.fx";
#import "network.fx";

def main() -> int
{
    // Initialize networking
    if (net::init() != 0)
    {
        print("Failed to initialize networking\n\0");
        return 1;
    };
    
    print("Network initialized successfully\n\0");
    
    // Create UDP client socket
    print("Creating UDP client socket...\n\0");
    i64 sock = udp::create_client();
    
    if (!net::is_valid_socket(sock))
    {
        print("Failed to create UDP client socket\n\0");
        net::cleanup();
        return 1;
    };
    
    print("UDP client socket created\n\0");
    
    // Prepare server address
    byte* server_ip = "127.0.0.1\0";
    u16 server_port = 8080;
    net::sockaddr_in server_addr = net::make_addr(server_ip, server_port);
    
    // Send a datagram
    byte* message = "Hello from Flux UDP client!\n\0";
    i32 message_len = 28;
    
    print("Sending datagram to 127.0.0.1:8080...\n\0");
    i32 bytes_sent = udp::sendto(sock, message, message_len, @server_addr);
    
    if (bytes_sent == SOCKET_ERROR)
    {
        print("Failed to send datagram\n\0");
        net::close_socket(sock);
        net::cleanup();
        return 1;
    };
    
    print("Datagram sent successfully\n\0");
    
    // Receive echo response
    byte[1024] buffer;
    net::sockaddr_in from_addr;
    
    print("Waiting for server response...\n\0");
    i32 bytes_received = udp::recvfrom(sock, buffer, 1024, @from_addr);
    
    if (bytes_received <= 0)
    {
        print("Failed to receive response\n\0");
        net::close_socket(sock);
        net::cleanup();
        return 1;
    };
    
    print("Received echo from server:\n\0");
    print(buffer, bytes_received);
    
    // Close socket
    net::close_socket(sock);
    
    print("\nSocket closed\n\0");
    
    // Cleanup networking
    net::cleanup();
    
    return 0;
};
