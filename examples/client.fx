// TCP Echo Client
// Connects to server at 127.0.0.1:8080 and sends messages

#import "standard.fx";
#import "socket_object_raw.fx";

using standard::io::console,
      standard::io::sockets,
      standard::strings;

def main() -> int
{
    // Initialize Winsock
    int init_result = init();
    if (init_result != 0)
    {
        print("Failed to initialize Winsock\n\0");
        return 1;
    };
    
    print("=== TCP Echo Client ===\n\0");
    print("Connecting to server at 127.0.0.1:8080...\n\0");
    
    // Create TCP socket
    socket client_socket(socket_type.TCP);
    client_socket.fd = tcp_socket();
    
    if (!client_socket.is_open())
    {
        print("Failed to create socket\n\0");
        cleanup();
        return 1;
    };
    
    // Connect to server
    if (!client_socket.connect("127.0.0.1\0", (i16)8080))
    {
        print("Failed to connect to server\n\0");
        client_socket.close();
        cleanup();
        return 1;
    };
    
    print("Connected to server!\n\0");
    
    // Buffer for sending and receiving data
    byte[1024] send_buffer;
    byte[1024] recv_buffer;
    
    // Send some test messages
    int message_count = 3;
    int i;
    
    while (i < message_count)
    {
        // Create message
        print("\n--- Message \0");
        print(i + 1);
        print(" ---\n\0");
        
        // Simple test message
        byte[3]* messages;
        messages[0] = "Hello, Server!\0";
        messages[1] = "This is message 2\0";
        messages[2] = "Final message from client\0";
        
        byte* msg = messages[i];
        
        // Calculate message length
        int msg_len = 0;
        while (msg[msg_len] != 0)
        {
            send_buffer[msg_len] = msg[msg_len];
            msg_len = msg_len + 1;
        };
        
        print("Sending: \0");
        print(msg);
        print("\n\0");
        
        // Send message
        int bytes_sent = client_socket.send_all(send_buffer, msg_len);
        
        if (bytes_sent < 0)
        {
            print("Failed to send message\n\0");
            break;
        };
        
        print("Sent \0");
        print(bytes_sent);
        print(" bytes\n\0");
        
        // Receive echo response
        int bytes_received = client_socket.recv(recv_buffer, 1024);
        
        if (bytes_received <= 0)
        {
            print("Server disconnected or error occurred\n\0");
            break;
        };
        
        // Null-terminate the received data
        recv_buffer[bytes_received] = '\0';
        
        print("Received echo (\0");
        print(bytes_received);
        print(" bytes): \0");
        print(recv_buffer);
        print("\n\0");
        
        i = i + 1;
    };
    
    // Clean up
    client_socket.close();
    cleanup();
    
    print("\nClient finished\n\0");
    return 0;
};
