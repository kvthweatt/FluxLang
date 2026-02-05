#import "standard.fx";
#import "socket_object_raw.fx";

def main() -> int
{
    // Initialize Winsock (required on Windows)
    init();
    
    print("=== Flux Echo Server ===\0\0");
    print("Starting server on port 8080...\0\0");
    
    // Create TCP server socket
    socket server(socket_type.TCP);
    server.fd = tcp_socket();
    
    if (!server.is_open())
    {
        print("ERROR: Failed to create socket\0\0");
        cleanup();
        return 1;
    };
    
    print("Socket created successfully\0\0");
    
    // Bind to port 8080
    if (!server.bind((i16)8080))
    {
        print("ERROR: Failed to bind to port 8080\0\0");
        server.close();
        cleanup();
        return 1;
    };

    print("Bound to port 8080\0\0");
    
    // Listen for incoming connections (backlog of 5)
    if (!server.listen(5))
    {
        print("ERROR: Failed to listen on socket\0\0");
        server.close();
        cleanup();
        return 1;
    };
    
    print("Listening for connections...\0\0");
    print("Press Ctrl+C to stop the server\0\0");
    print("\0\0");
    
    // Accept and handle clients in a loop
    while (true)
    {
        print("Waiting for client connection...\0\0");
        
        // Accept a client connection
        socket client = server.accept();
        
        if (!client.is_open())
        {
            print("ERROR: Failed to accept client connection\0\0");
            continue;
        };
        
        print("Client connected!\0\0");
        
        // Buffer for receiving data
        byte[1024] buffer;
        
        // Receive and echo data
        while (true)
        {
            // Clear buffer
            int i = 0;
            while (i < 1024)
            {
                buffer[i] = (byte*)'\0';
                i++;
            };
            
            // Receive data from client
            int bytes_received = client.recv(buffer[0], 1024);
            
            if (bytes_received <= 0)
            {
                print("Client disconnected\0\0");
                break;
            };
            
            // Print received message
            print("Received: \0");
            print(buffer[0]);
            print("\0\0");
            
            // Echo the data back to client
            int bytes_sent = client.send_all(buffer[0], bytes_received);
            
            if (bytes_sent < 0)
            {
                print("ERROR: Failed to send data to client\0\0");
                break;
            };
            
            print("Echoed message back to client\0\0");
        };
        
        // Close client connection
        client.close();
        print("Client connection closed\0\0");
        print("\0\0");
    };
    
    // Cleanup (this code is unreachable in the infinite loop)
    server.close();
    cleanup();
    
    return 0;
};
