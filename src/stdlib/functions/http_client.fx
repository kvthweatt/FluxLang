// Simple HTTP Client Example
// Demonstrates using the Flux networking library to make a simple HTTP GET request
// This shows how to build higher-level protocols on top of TCP

#import "standard.fx";
#import "network.fx";
#import "redmemory.fx";
#import "strfuncs.fx";

// Helper function to find string in buffer
def find_str(byte* haystack, i32 haystack_len, byte* needle, i32 needle_len) -> i32
{
    if (needle_len > haystack_len)
    {
        return -1;
    };
    
    for (i32 i = 0; i <= haystack_len - needle_len; i++)
    {
        bool found = 1;
        
        for (i32 j = 0; j < needle_len; j++)
        {
            if (haystack[i + j] != needle[j])
            {
                found = 0;
                break;
            };
        };
        
        if (found)
        {
            return i;
        };
    };
    
    return -1;
};

def main() -> int
{
    // Initialize networking
    if (net::init() != 0)
    {
        print("Failed to initialize networking\n\0");
        return 1;
    };
    
    print("HTTP Client Example\n\0");
    print("===================\n\0");
    
    // Connect to HTTP server (example.com on port 80)
    // Note: For actual HTTP requests, you'd want to resolve DNS first
    // For this example, we'll use a direct IP or localhost
    
    byte* server_ip = "93.184.216.34\0";  // example.com IP
    u16 server_port = 80;
    
    print("Connecting to server...\n\0");
    i64 sock = tcp::connect_to_server(server_ip, server_port);
    
    if (!net::is_valid_socket(sock))
    {
        print("Failed to connect to server\n\0");
        net::cleanup();
        return 1;
    };
    
    print("Connected!\n\0");
    
    // Build HTTP GET request
    byte[512] request;
    
    // HTTP request line
    byte* method = "GET / HTTP/1.1\r\n\0";
    byte* host_header = "Host: example.com\r\n\0";
    byte* user_agent = "User-Agent: Flux-HTTP-Client/1.0\r\n\0";
    byte* connection = "Connection: close\r\n\0";
    byte* end_headers = "\r\n\0";
    
    // Copy request parts into buffer
    i32 pos = 0;
    
    // Copy method
    for (i32 i = 0; method[i] != 0; i++)
    {
        request[pos] = method[i];
        pos = pos + 1;
    };
    
    // Copy Host header
    for (i32 i = 0; host_header[i] != 0; i++)
    {
        request[pos] = host_header[i];
        pos = pos + 1;
    };
    
    // Copy User-Agent
    for (i32 i = 0; user_agent[i] != 0; i++)
    {
        request[pos] = user_agent[i];
        pos = pos + 1;
    };
    
    // Copy Connection
    for (i32 i = 0; connection[i] != 0; i++)
    {
        request[pos] = connection[i];
        pos = pos + 1;
    };
    
    // Copy end of headers
    for (i32 i = 0; end_headers[i] != 0; i++)
    {
        request[pos] = end_headers[i];
        pos = pos + 1;
    };
    
    i32 request_len = pos;
    
    print("Sending HTTP request...\n\0");
    print("Request:\n\0");
    print("--------\n\0");
    print(request, request_len);
    print("--------\n\0");
    
    // Send request
    i32 bytes_sent = tcp::send_all(sock, request, request_len);
    
    if (bytes_sent == SOCKET_ERROR)
    {
        print("Failed to send HTTP request\n\0");
        net::close_socket(sock);
        net::cleanup();
        return 1;
    };
    
    print("Request sent successfully\n\0");
    
    // Receive response
    byte[4096] response;
    i32 total_received = 0;
    
    print("\nReceiving HTTP response...\n\0");
    print("Response:\n\0");
    print("---------\n\0");
    
    // Receive loop
    while (1)
    {
        i32 bytes_received = tcp::recv(sock, response + total_received, 4096 - total_received);
        
        if (bytes_received <= 0)
        {
            // Connection closed or error
            break;
        };
        
        total_received = total_received + bytes_received;
        
        if (total_received >= 4096)
        {
            break;
        };
    };
    
    if (total_received > 0)
    {
        print(response, total_received);
    }
    else
    {
        print("No data received\n\0");
    };
    
    print("\n---------\n\0");
    print("Total bytes received: \0");
    print("\n\0");
    
    // Close connection
    net::shutdown_socket(sock, SHUT_RDWR);
    net::close_socket(sock);
    
    print("Connection closed\n\0");
    
    // Cleanup
    net::cleanup();
    
    return 0;
};
