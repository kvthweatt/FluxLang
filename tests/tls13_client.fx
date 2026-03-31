// Author: Karac V. Thweatt
// tls13_client.fx - TLS 1.3 Test Client
//
// Connects to tls13_server.fx on 127.0.0.1:8443, completes the TLS 1.3
// handshake, reads the server greeting, sends a reply, then closes.
//
// Run tls13_server.fx first.

#import "standard.fx", "tls.fx";

using standard::io::console,
      standard::net,
      standard::tls;

#def TLS_TEST_PORT 8443;

def main() -> int
{
    TLS13_CTX ctx;
    int sockfd, result, n, i;
    byte[256] buf;
    sockaddr_in server_addr;

    print("=== TLS 1.3 Test Client ===\n\0");

    // Init Winsock
    if (init() != 0)
    {
        print("[client] WSAStartup failed\n\0");
        return 1;
    };

    // Create socket and connect to server
    sockfd = tcp_socket();
    if (sockfd < 0)
    {
        print("[client] socket() failed\n\0");
        cleanup();
        return 1;
    };

    server_addr.sin_family  = (u16)AF_INET;
    server_addr.sin_port    = htons((u16)TLS_TEST_PORT);
    server_addr.sin_addr    = inet_addr("127.0.0.1\0");
    server_addr.sin_zero[0] = '\0';
    server_addr.sin_zero[1] = '\0';
    server_addr.sin_zero[2] = '\0';
    server_addr.sin_zero[3] = '\0';
    server_addr.sin_zero[4] = '\0';
    server_addr.sin_zero[5] = '\0';
    server_addr.sin_zero[6] = '\0';
    server_addr.sin_zero[7] = '\0';

    print("[client] connecting to 127.0.0.1:\0");
    print(TLS_TEST_PORT);
    print("...\n\0");

    if (connect(sockfd, @server_addr, 16) < 0)
    {
        print("[client] connect() failed, WSA error: \0");
        print(get_last_error());
        print("\n\0");
        closesocket(sockfd);
        cleanup();
        return 1;
    };
    print("[client] TCP connected, starting TLS handshake...\n\0");

    // TLS 1.3 handshake (client side)
    noopstr hostname = "localhost\0";
    result = tls13_connect(@ctx, sockfd, hostname, 9);
    if (result == 0)
    {
        print("[client] TLS handshake FAILED\n\0");
        closesocket(sockfd);
        cleanup();
        return 1;
    };
    print("[client] TLS handshake complete\n\0");

    // Receive server greeting
    n = tls13_recv(@ctx, @buf[0], 256);
    if (n > 0)
    {
        print("[client] received \0");
        print(n);
        print(" bytes: \0");
        for (i = 0; i < n; i++) { print(buf[i]); };
    }
    else
    {
        print("[client] recv failed\n\0");
    };

    // Send reply
    noopstr reply = "Hello from TLS 1.3 client!\n\0";

    result = tls13_send(@ctx, reply, 27);
    if (result < 0)
    {
        print("[client] send failed\n\0");
    }
    else
    {
        print("[client] sent reply\n\0");
    };

    // Close TLS session
    tls13_close(@ctx);
    closesocket(sockfd);
    cleanup();

    print("[client] done\n\0");
    return 0;
};
