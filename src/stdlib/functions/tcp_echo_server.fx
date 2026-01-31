// TCP Echo Server Example
// Demonstrates using the Flux networking library to create a simple TCP server
// that echoes back any data it receives from clients

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
    
    // Create server on port 8080 with backlog of 10
    u16 port = 8080;
    i32 backlog = 10;
    
    print("Creating TCP server on port 8080...\n\0");
    i64 server_socket = tcp::create_server(port, backlog);
    
    if (!net::is_valid_socket(server_socket))
    {
        print("Failed to create server socket\n\0");
        net::cleanup();
        return 1;
    };
    
    print("Server listening on port 8080\n\0");
    print("Waiting for connections...\n\0");
    
    // Accept loop
    while (1)
    {
        // Accept client connection
        net::sockaddr_in client_addr;
        i64 client_socket = tcp::accept(server_socket, @client_addr);
        
        if (!net::is_valid_socket(client_socket))
        {
            print("Failed to accept client\n\0");
            continue;
        };
        
        // Get client IP address
        u32 client_ip = client_addr.sin_addr.s_addr;
        u16 client_port = net::ntohs(client_addr.sin_port);
        
        print("Client connected from port: \0");
        
        // Echo loop for this client
        byte[1024] buffer;
        i32 running = 1;
        
        while (running)
        {
            // Receive data
            i32 bytes_received = tcp::recv(client_socket, buffer, 1024);
            
            if (bytes_received <= 0)
            {
                // Client disconnected or error
                print("Client disconnected\n\0");
                running = 0;
                break;
            };
            
            // Echo data back
            i32 bytes_sent = tcp::send_all(client_socket, buffer, bytes_received);
            
            if (bytes_sent == SOCKET_ERROR)
            {
                print("Failed to send data\n\0");
                running = 0;
                break;
            };
        };
        
        // Close client socket
        net::close_socket(client_socket);
        print("Client socket closed\n\0");
    };
    
    // Cleanup (unreachable in infinite loop, but good practice)
    net::close_socket(server_socket);
    net::cleanup();
    
    return 0;
};
