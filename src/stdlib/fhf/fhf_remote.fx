// fhf_remote.fx
//
// Flux Hotpatch Framework (FHF) — Remote Patching Layer
//
// Extends the runtime to send patch bundles over TCP so a patch server
// can push signed bundles to remote clients (or to other local processes
// via loopback).
//
// Wire protocol (extends hotpatch_protocol.fx concepts to full bundles):
//
//   [4 bytes]  FHF_REMOTE_MAGIC  (0x46485250  "FHRP")
//   [4 bytes]  bundle_size       (u32, little-endian)
//   [N bytes]  bundle data       (a complete FHF bundle as produced by
//                                 fhf_bundle_builder)
//
// The receiver calls fhf_apply_bundle() on the received data; all
// signature verification is handled by the bundle layer.
//
// Server API:
//   fhf_remote_serve(mgr, port, bundle_data, bundle_size) -> int
//     — listen on port, accept one client, send bundle, wait for ACK
//
// Client API:
//   fhf_remote_receive(mgr, host, port) -> int
//     — connect, receive bundle, verify + apply, send ACK

#ifndef FHF_REMOTE
#def FHF_REMOTE 1;

#ifndef FHF_RUNTIME
#import "fhf\\fhf_runtime.fx";
#endif;

#ifndef FLUX_STANDARD_NET
#import "rednet_windows.fx";
#endif;

using standard::net;

// ============================================================================
//  Constants
// ============================================================================

const u32 FHF_REMOTE_MAGIC = 0x46485250;   // "FHRP"
const u32 FHF_REMOTE_ACK   = 0x00000001;
const u32 FHF_REMOTE_NACK  = 0x000000FF;

// Maximum bundle size accepted over the wire (1 MiB)
const int FHF_REMOTE_MAX_BUNDLE = 1048576;

// ============================================================================
//  I/O helpers
// ============================================================================

def _fhf_send_exact(int sock, byte* buf, int n) -> bool
{
    int sent = 0;
    while (sent < n)
    {
        int s = send(sock, (void*)(buf + sent), n - sent, 0);
        if (s <= 0) { return false; };
        sent = sent + s;
    };
    return true;
};

def _fhf_recv_exact(int sock, byte* buf, int n) -> bool
{
    int got = 0;
    while (got < n)
    {
        int r = recv(sock, (void*)(buf + got), n - got, 0);
        if (r <= 0) { return false; };
        got = got + r;
    };
    return true;
};

def _fhf_write_u32_le(byte* p, u32 v) -> void
{
    p[0] = (byte)(v        & (u32)0xFF);
    p[1] = (byte)((v >> 8)  & (u32)0xFF);
    p[2] = (byte)((v >> 16) & (u32)0xFF);
    p[3] = (byte)((v >> 24) & (u32)0xFF);
};

// ============================================================================
//  Server — push a bundle to one connecting client
// ============================================================================

// Listen on `port`, accept one client, send the bundle, wait for ACK.
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_remote_serve(FHFManager* mgr,
                     u16         port,
                     byte*       bundle_data,
                     int         bundle_size) -> int
{
    if (mgr == (FHFManager*)0 | bundle_data == (byte*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };

    if (init() != 0) { return FHF_ERR_NETWORK; };

    int server_sock = tcp_server_create(port, 1);
    if (server_sock < 0)
    {
        cleanup();
        return FHF_ERR_NETWORK;
    };

    sockaddr_in client_addr;
    int client_sock = tcp_server_accept(server_sock, @client_addr);
    if (client_sock < 0)
    {
        tcp_close(server_sock);
        cleanup();
        return FHF_ERR_NETWORK;
    };

    // Send wire header: magic (4) + bundle_size (4)
    byte[8] wire_hdr;
    _fhf_write_u32_le(@wire_hdr[0], FHF_REMOTE_MAGIC);
    _fhf_write_u32_le(@wire_hdr[4], (u32)bundle_size);

    if (!_fhf_send_exact(client_sock, @wire_hdr[0], 8))
    {
        tcp_close(client_sock);
        tcp_close(server_sock);
        cleanup();
        return FHF_ERR_NETWORK;
    };

    // Send bundle
    if (!_fhf_send_exact(client_sock, bundle_data, bundle_size))
    {
        tcp_close(client_sock);
        tcp_close(server_sock);
        cleanup();
        return FHF_ERR_NETWORK;
    };

    // Wait for ACK (4 bytes)
    byte[4] ack_buf;
    if (!_fhf_recv_exact(client_sock, @ack_buf[0], 4))
    {
        tcp_close(client_sock);
        tcp_close(server_sock);
        cleanup();
        return FHF_ERR_NETWORK;
    };

    u32 ack = _fhf_read_u32(@ack_buf[0]);

    tcp_close(client_sock);
    tcp_close(server_sock);
    cleanup();

    if (ack != FHF_REMOTE_ACK) { return FHF_ERR_NETWORK; };
    return FHF_OK;
};

// ============================================================================
//  Client — receive, verify, and apply a remote bundle
// ============================================================================

// Connect to host:port, receive a bundle, verify + apply it, send ACK.
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_remote_receive(FHFManager* mgr, byte* host, u16 port) -> int
{
    if (mgr == (FHFManager*)0 | host == (byte*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };

    if (init() != 0) { return FHF_ERR_NETWORK; };

    int sockfd = tcp_socket();
    if (sockfd < 0)
    {
        cleanup();
        return FHF_ERR_NETWORK;
    };

    sockaddr_in srv;
    srv.sin_family  = (u16)AF_INET;
    srv.sin_port    = htons(port);
    srv.sin_addr    = inet_addr(host);
    srv.sin_zero[0] = (byte)0;
    srv.sin_zero[1] = (byte)0;
    srv.sin_zero[2] = (byte)0;
    srv.sin_zero[3] = (byte)0;
    srv.sin_zero[4] = (byte)0;
    srv.sin_zero[5] = (byte)0;
    srv.sin_zero[6] = (byte)0;
    srv.sin_zero[7] = (byte)0;

    if (connect(sockfd, @srv, 16) < 0)
    {
        closesocket(sockfd);
        cleanup();
        return FHF_ERR_NETWORK;
    };

    // Receive wire header
    byte[8] wire_hdr;
    if (!_fhf_recv_exact(sockfd, @wire_hdr[0], 8))
    {
        closesocket(sockfd);
        cleanup();
        return FHF_ERR_NETWORK;
    };

    u32 magic       = _fhf_read_u32(@wire_hdr[0]);
    u32 bundle_size = _fhf_read_u32(@wire_hdr[4]);

    if (magic != FHF_REMOTE_MAGIC)
    {
        closesocket(sockfd);
        cleanup();
        return FHF_ERR_BAD_MAGIC;
    };

    if ((int)bundle_size > FHF_REMOTE_MAX_BUNDLE | (int)bundle_size <= 0)
    {
        closesocket(sockfd);
        cleanup();
        return FHF_ERR_PAYLOAD_TOO_LARGE;
    };

    // Allocate receive buffer
    byte* bundle_buf = (byte*)malloc((size_t)bundle_size);
    if (bundle_buf == (byte*)0)
    {
        closesocket(sockfd);
        cleanup();
        return FHF_ERR_ALLOC;
    };

    if (!_fhf_recv_exact(sockfd, bundle_buf, (int)bundle_size))
    {
        free((void*)bundle_buf);
        closesocket(sockfd);
        cleanup();
        return FHF_ERR_NETWORK;
    };

    // Apply bundle (includes signature verification)
    int apply_rc = fhf_apply_bundle(mgr, bundle_buf, (int)bundle_size);
    free((void*)bundle_buf);

    // Send ACK or NACK
    byte[4] ack_buf;
    if (apply_rc == FHF_OK)
    {
        _fhf_write_u32_le(@ack_buf[0], FHF_REMOTE_ACK);
    }
    else
    {
        _fhf_write_u32_le(@ack_buf[0], FHF_REMOTE_NACK);
    };

    _fhf_send_exact(sockfd, @ack_buf[0], 4);

    closesocket(sockfd);
    cleanup();

    return apply_rc;
};

#endif; // FHF_REMOTE
