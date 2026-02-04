// Basic HTTP Client in Flux
// Demonstrates making HTTP GET requests

#import "standard.fx", "rednet_windows.fx";

// Build HTTP GET request
def build_http_request(byte* host, byte* path, byte* buffer) -> int
{
    byte* get_line = "GET \0";
    byte* http_version = " HTTP/1.1\r\n\0";
    byte* host_header = "Host: \0";
    byte* connection_header = "Connection: close\r\n\0";
    byte* end_headers = "\r\n\0";
    
    int pos = 0;
    int i;
    
    // "GET "
    i = 0;
    while (get_line[i] != 0)
    {
        buffer[pos] = get_line[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // path
    i = 0;
    while (path[i] != 0)
    {
        buffer[pos] = path[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // " HTTP/1.1\r\n"
    i = 0;
    while (http_version[i] != 0)
    {
        buffer[pos] = http_version[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // "Host: "
    i = 0;
    while (host_header[i] != 0)
    {
        buffer[pos] = host_header[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // host
    i = 0;
    while (host[i] != 0)
    {
        buffer[pos] = host[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // "\r\n"
    buffer[pos] = '\r';
    pos = pos + 1;
    buffer[pos] = '\n';
    pos = pos + 1;
    
    // "Connection: close\r\n"
    i = 0;
    while (connection_header[i] != 0)
    {
        buffer[pos] = connection_header[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // "\r\n"
    i = 0;
    while (end_headers[i] != 0)
    {
        buffer[pos] = end_headers[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    return pos;
};

// Extract status code from HTTP response
def extract_status_code(byte* response) -> int
{
    // Look for "HTTP/1.x nnn" pattern
    int i = 0;
    
    // Skip to first space after HTTP/1.x
    while (response[i] != 0 & response[i] != ' ')
    {
        i = i + 1;
    };
    
    if (response[i] == ' ')
    {
        i = i + 1;
        
        // Parse the 3-digit status code
        int status = 0;
        int digit_count = 0;
        
        while (response[i] >= '0' & response[i] <= '9' & digit_count < 3)
        {
            status = status * 10 + (response[i] - '0');
            i = i + 1;
            digit_count = digit_count + 1;
        };
        
        return status;
    };
    
    return 0;
};

// Find start of response body
def find_body_start(byte* response, int response_len) -> int
{
    // Look for "\r\n\r\n" separator
    int i = 0;
    while (i < response_len - 3)
    {
        if (response[i] == '\r' & response[i+1] == '\n' & response[i+2] == '\r' & response[i+3] == '\n')
        {
            return i + 4;
        };
        i = i + 1;
    };
    
    return -1;
};

// Make HTTP GET request
def http_get(byte* host, u16 port, byte* path) -> int
{
    print("Connecting to \0");
    int host_len = 0;
    while (host[host_len] != 0) { host_len = host_len + 1; };
    print(host, host_len);
    print(":\0");
    
    byte[16] port_str;
    u32str((u32)port, @port_str[0]);
    int port_len = 0;
    while (port_str[port_len] != 0) { port_len = port_len + 1; };
    print(@port_str[0], port_len);
    print("...\n\0");
    
    // Connect to server
    int sock = tcp_client_connect(host, port);
    if (sock < 0)
    {
        int err = net::get_last_error();
        print("Failed to connect. WSA Error: \0");
        print(err);
        print("\n\0");
        return 1;
    };
    
    print("Connected! Sending request...\n\0");
    
    // Build and send request
    byte[2048] request_buffer;
    int request_len = build_http_request(host, path, @request_buffer[0]);
    
    int sent = tcp_send_all(sock, @request_buffer[0], request_len);
    if (sent < 0)
    {
        print("Failed to send request\n\0");
        tcp_close(sock);
        return 1;
    };
    
    print("Request sent. Waiting for response...\n\n\0");
    
    // Receive response
    byte[8192] response_buffer;
    int total_received = 0;
    int bytes_recv;
    
    while (true)
    {
        bytes_recv = tcp_recv(sock, @response_buffer[total_received], 8192 - total_received);
        
        if (bytes_recv <= 0)
        {
            break;
        };
        
        total_received = total_received + bytes_recv;
        
        if (total_received >= 8192)
        {
            break;
        };
    };
    
    tcp_close(sock);
    
    if (total_received > 0)
    {
        // Null-terminate
        if (total_received < 8192)
        {
            response_buffer[total_received] = (byte)0;
        };
        
        // Extract status code
        int status = extract_status_code(@response_buffer[0]);
        print("Status: \0");
        byte[16] status_str;
        i32str(status, @status_str[0]);
        int status_len = 0;
        while (status_str[status_len] != 0) { status_len = status_len + 1; };
        print(@status_str[0], status_len);
        print("\n\n\0");
        
        // Find and print body
        int body_start = find_body_start(@response_buffer[0], total_received);
        if (body_start >= 0)
        {
            print("Response body:\n\0");
            print("==============\n\0");
            
            int body_len = total_received - body_start;
            if (body_len > 0)
            {
                print(@response_buffer[body_start], body_len);
            };
            print("\n==============\n\0");
        }
        else
        {
            // No body separator found, print entire response
            print("Full response:\n\0");
            print(@response_buffer[0], total_received);
            print("\n\0");
        };
    }
    else
    {
        print("No response received\n\0");
    };
    
    return 0;
};

// Main function
def main() -> int
{
    // Initialize Winsock
    int init_result = net::init();
    if (init_result != 0)
    {
        print("Failed to initialize Winsock\n\0");
        return 1;
    };
    
    print("=== Flux HTTP Client ===\n\n\0");
    
    // Example 1: Request from local server
    print("Example 1: Requesting from local server\n\0");
    print("---------------------------------------\n\0");
    http_get("127.0.0.1\0", (u16)8080, "/\0");
    
    print("\n\n\0");
    
    // Example 2: Another path
    print("Example 2: Requesting /about\n\0");
    print("---------------------------------------\n\0");
    http_get("127.0.0.1\0", (u16)8080, "/about\0");
    
    // Cleanup
    net::cleanup();
    
    return 0;
};
