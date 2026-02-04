// Basic HTTP Server in Flux - Debug Version
// Demonstrates TCP server handling simple HTTP GET requests

#import "standard.fx", "rednet_windows.fx";

// HTTP response helper
def build_http_response(byte* content, int content_len, byte* buffer) -> int
{
    // Build HTTP/1.1 200 OK response
    byte* header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \0";
    byte* header_end = "\r\n\r\n\0";
    
    // Copy header
    int pos = 0;
    int i = 0;
    while (header[i] != 0)
    {
        buffer[pos] = header[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // Add content length
    byte[32] len_str;
    i32str(content_len, @len_str[0]);
    i = 0;
    while (len_str[i] != 0)
    {
        buffer[pos] = len_str[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // Add header end
    i = 0;
    while (header_end[i] != 0)
    {
        buffer[pos] = header_end[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    // Add content
    i = 0;
    while (i < content_len)
    {
        buffer[pos] = content[i];
        pos = pos + 1;
        i = i + 1;
    };
    
    return pos;
};

// Parse HTTP request path
def parse_request_path(byte* request, byte* path_buffer, int max_len) -> int
{
    // Find "GET " or "POST "
    int start = 0;
    bool found = false;
    
    // Look for "GET "
    int i = 0;
    while (request[i] != 0 & i < 500)
    {
        if (request[i] == 'G' & request[i+1] == 'E' & request[i+2] == 'T' & request[i+3] == ' ')
        {
            start = i + 4;
            found = true;
            break;
        };
        i = i + 1;
    };
    
    if (!found)
    {
        return 0;
    };
    
    // Extract path until space or ?
    int path_len = 0;
    i = start;
    while (request[i] != 0 & request[i] != ' ' & request[i] != '?' & path_len < max_len - 1)
    {
        path_buffer[path_len] = request[i];
        path_len = path_len + 1;
        i = i + 1;
    };
    path_buffer[path_len] = '\0';
    
    return path_len;
};

// Handle client connection
def handle_client(int client_sock) -> void
{
    byte[4096] request_buffer;
    byte[8192] response_buffer;
    byte[256] path_buffer;
    
    // Receive request
    int bytes_recv = tcp_recv(client_sock, @request_buffer[0], 4096);
    
    if (bytes_recv > 0)
    {
        // Null-terminate for safety
        if (bytes_recv < 4096)
        {
            request_buffer[bytes_recv] = (byte)0;
        };
        
        // Parse request path
        int path_len = parse_request_path(@request_buffer[0], @path_buffer[0], 256);
        
        // Print request info
        print("Request: \0");
        if (path_len > 0)
        {
            print(@path_buffer[0], path_len);
        };
        print("\n\0");
        
        // Generate response based on path
        byte* content;
        int content_len;
        
        // Check if root path
        bool is_root = (path_len == 1 & path_buffer[0] == '/');
        
        if (is_root)
        {
            content = "
<html>
    <body>
        <h1>Flux HTTP Server</h1><p>Welcome to the Flux web server!</p><p>Try: <a href='/about'>/about</a> or <a href='/time'>/time</a></p></body></html>\0";
            content_len = 0;
            while (content[content_len] != 0) { content_len = content_len + 1; };
        }
        elif (path_buffer[0] == '/' & path_buffer[1] == 'a' & path_buffer[2] == 'b' & path_buffer[3] == 'o' & path_buffer[4] == 'u' & path_buffer[5] == 't')
        {
            content = "
<html>
    <body>
        <h1>About</h1>
        <p>This is a simple HTTP server written in Flux.</p>
        <p>Flux is a systems programming language.</p>
        <p><a href='/'>Go to the root of the site.</a></p>
    </body>
</html>\0";
            content_len = 0;
            while (content[content_len] != 0) { content_len = content_len + 1; };
        }
        elif (path_buffer[0] == '/' & path_buffer[1] == 't' & path_buffer[2] == 'i' & path_buffer[3] == 'm' & path_buffer[4] == 'e')
        {
            content = "
<html>
    <body>
        <h1>Time</h1>
        <p>This is a simple HTTP server written in Flux.</p>
        <p>Time to look at the clock.</p>
        <p><a href='/'>Go to the root of the site.</a></p>
    </body>
</html>\0";
            content_len = 0;
            while (content[content_len] != 0) { content_len = content_len + 1; };
        }
        else
        {
            content = "
<html>
    <body>
        <h1>404 Not Found</h1>
        <p>The requested page was not found.</p>
    </body>
</html>\0";
            content_len = 0;
            while (content[content_len] != 0) { content_len = content_len + 1; };
        };
        
        // Build and send response
        int response_len = build_http_response(content, content_len, @response_buffer[0]);
        tcp_send_all(client_sock, @response_buffer[0], response_len);
    };
    
    // Close connection
    tcp_close(client_sock);
};

// Main server function
def main() -> int
{
    // Initialize Winsock
    int init_result = net::init();
    if (init_result != 0)
    {
        print("Failed to initialize Winsock\n\0");
        return 1;
    };
    
    print("Starting HTTP server on port 8080...\n\0");
    
    // Create server socket
    int server_sock = tcp_server_create((u16)8080, 10);
    if (server_sock < 0)
    {
        print("Failed to create server socket\nserver_sock = \0");
        print(server_sock);
        print();
        net::cleanup();
        return 1;
    };
    
    print("Server listening on localhost:8080\n\0");
    print("Press Ctrl+C to stop\n\n\0");
    
    // Accept loop
    sockaddr_in client_addr;
    while (true)
    {
        int client_sock = tcp_server_accept(server_sock, @client_addr);
        
        if (client_sock >= 0)
        {
            // Get client info
            byte* client_ip = net::get_ip_string(@client_addr);
            u16 client_port = net::get_port(@client_addr);
            
            print("Connection from: \0");
            int ip_len = 0;
            while (client_ip[ip_len] != 0) { ip_len = ip_len + 1; };
            print(client_ip, ip_len);
            print("\n\0");
            
            // Handle the request
            handle_client(client_sock);
        };
    };
    
    // Cleanup (never reached in this simple server)
    tcp_close(server_sock);
    net::cleanup();
    
    return 0;
};