// TCP Echo Client Example
// Demonstrates using the Flux networking library to create a simple TCP client
// that connects to a server and sends/receives messages

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
    
    // Connect to server
    byte* server_ip = "127.0.0.1\0";
    u16 server_port = 8080;
    
    print("Connecting to server at 127.0.0.1:8080...\n\0");
    i64 sock = tcp::connect_to_server(server_ip, server_port);
    
    if (!net::is_valid_socket(sock))
    {
        print("Failed to connect to server\n\0");
        net::cleanup();
        return 1;
    };
    
    print("Connected to server!\n\0");
    
    // Send a message
    byte* message = "Hello from Flux TCP client!\n\0";
    i32 message_len = 28;
    
    print("Sending message to server...\n\0");
    i32 bytes_sent = tcp::send_all(sock, message, message_len);
    
    if (bytes_sent == SOCKET_ERROR)
    {
        print("Failed to send message\n\0");
        net::close_socket(sock);
        net::cleanup();
        return 1;
    };
    
    print("Message sent successfully\n\0");
    
    // Receive echo response
    byte[1024] buffer;
    print("Waiting for server response...\n\0");
    
    i32 bytes_received = tcp::recv(sock, buffer, 1024);
    
    if (bytes_received <= 0)
    {
        print("Failed to receive response or connection closed\n\0");
        net::close_socket(sock);
        net::cleanup();
        return 1;
    };
    
    print("Received echo from server:\n\0");
    print(buffer, bytes_received);
    
    // Close connection
    net::shutdown_socket(sock, SHUT_RDWR);
    net::close_socket(sock);
    
    print("\nConnection closed\n\0");
    
    // Cleanup networking
    net::cleanup();
    
    return 0;
};
