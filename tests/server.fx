// TCP Echo Server
// Listens on port 8080 and echoes back any messages received
#import "standard.fx";

using standard::strings;

def main() -> int
{
    // Initialize Winsock
    int init_result = init();
    if (init_result != 0)
    {
        print("Failed to initialize Winsock\n\0");
        return 1;
    };
    
    print("=== TCP Echo Server ===\n\0");
    print("Starting server on port 8080...\n\0");
    
    // Create TCP socket
    socket server_socket(socket_type.TCP);
    server_socket.fd = tcp_socket();
    
    if (!server_socket.is_open())
    {
        print("Failed to create socket\n\0");
        cleanup();
        return 1;
    };
    
    // Bind to port 8080
    if (!server_socket.bind((i16)8080))
    {
        print("Failed to bind to port 8080\n\0");
        server_socket.close();
        cleanup();
        return 1;
    };
    
    // Listen for connections
    if (!server_socket.listen(5))
    {
        print("Failed to listen on socket\n\0");
        server_socket.close();
        cleanup();
        return 1;
    };
    
    print("Server listening on port 8080\n\0");
    print("Waiting for connections...\n\0");
    
    // Accept client connection
    socket client_socket = server_socket.accept();
    
    if (!client_socket.is_open())
    {
        print("Failed to accept client connection\n\0");
        server_socket.close();
        cleanup();
        return 1;
    };
    
    print("Client connected from \0");
    print(client_socket.get_remote_ip());
    print(":\0");
    print((int)client_socket.get_remote_port());
    print("\n\0");
    
    // Buffer for receiving data
    byte[1024] buffer;
    
    // Echo loop
    while (true)
    {
        // Receive data from client
        int bytes_received = client_socket.recv(buffer, 1024);
        
        if (bytes_received <= 0)
        {
            print("Client disconnected\n\0");
            break;
        };
        
        // Null-terminate the received data
        buffer[bytes_received] = '\0';
        
        print("Received (\0");
        print(bytes_received);
        print(" bytes): \0");
        print(buffer);
        print("\n\0");
        
        // Echo the data back to client
        int bytes_sent = client_socket.send_all(buffer, bytes_received);
        
        if (bytes_sent < 0)
        {
            print("Failed to send data to client\n\0");
            break;
        };
        
        print("Echoed back \0");
        print(bytes_sent);
        print(" bytes\n\0");
    };
    
    // Clean up
    client_socket.close();
    server_socket.close();
    cleanup();
    
    print("Server shut down\n\0");
    return 0;
};
