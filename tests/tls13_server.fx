// Author: Karac V. Thweatt
// tls13_server.fx - TLS 1.3 Test Server
//
// Listens on port 8443, accepts one client, completes the TLS 1.3
// handshake, sends a greeting, echoes back whatever the client sends,
// then closes the connection.
//
// Run this before tls13_client.fx.

#import "standard.fx";
#import "net_windows.fx";
#import "tls.fx";

using standard::io::console,
      standard::net,
      standard::tls;

#def TLS_TEST_PORT 8443;

def main() -> int
{
    TLS13_CTX ctx;
    int server_sock, client_sock, result, n, i;
    byte[256] buf;
    sockaddr_in client_addr;

    print("=== TLS 1.3 Test Server ===\n\0");

    // Init Winsock
    if (init() != 0)
    {
        print("[server] WSAStartup failed\n\0");
        return 1;
    };

    // Create and bind server socket
    server_sock = tcp_server_create((u16)TLS_TEST_PORT, 1);
    if (server_sock < 0)
    {
        print("[server] failed to create server socket\n\0");
        cleanup();
        return 1;
    };

    print("[server] listening on port \0");
    print(TLS_TEST_PORT);
    print("...\n\0");

    // Accept one client
    client_sock = tcp_server_accept(server_sock, @client_addr);
    if (client_sock < 0)
    {
        print("[server] accept failed\n\0");
        tcp_close(server_sock);
        cleanup();
        return 1;
    };
    print("[server] client connected, starting TLS handshake...\n\0");

    // TLS 1.3 handshake (server side)
    result = tls13_accept(@ctx, client_sock);
    if (result == 0)
    {
        print("[server] TLS handshake FAILED\n\0");
        tcp_close(client_sock);
        tcp_close(server_sock);
        cleanup();
        return 1;
    };
    print("[server] TLS handshake complete\n\0");

    // Send greeting
    noopstr greeting = "Hello from TLS 1.3 server!\n\0";

    result = tls13_send(@ctx, greeting, 27);
    if (result < 0)
    {
        print("[server] send failed\n\0");
    }
    else
    {
        print("[server] sent greeting\n\0");
    };

    // Receive client message
    n = tls13_recv(@ctx, @buf[0], 256);
    if (n > 0)
    {
        print("[server] received \0");
        print(n);
        print(" bytes: \0");
        for (i = 0; i < n; i++) { print(buf[i]); };
    }
    else
    {
        print("[server] recv failed\n\0");
    };

    // Close TLS session
    tls13_close(@ctx);
    tcp_close(client_sock);
    tcp_close(server_sock);
    cleanup();

    print("[server] done\n\0");
    return 0;
};
