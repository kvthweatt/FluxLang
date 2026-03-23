// hotpatch_client.fx
//
// Hotpatch client demo.
//
// Ships with a deliberately broken function (bad_compute) that will
// segfault when called.  Connects to the hotpatch server, receives a
// replacement function as raw bytes, verifies its HMAC-SHA256 signature,
// writes the bytes into an executable page, installs a detour over
// bad_compute, then calls it successfully.
//
// Flow:
//   1. Call bad_compute() - crashes intentionally (writes to null)
//      (we skip the first call and just show what WOULD happen)
//   2. Connect to hotpatch server on HOTPATCH_PORT
//   3. Receive PatchHeader  (16 bytes)
//   4. Validate magic
//   5. Receive payload      (patch_size bytes) into RWX page
//   6. Receive signature    (32 bytes) HMAC-SHA256 over payload
//   7. Verify signature — reject and abort if invalid
//   8. Install detour:  bad_compute -> patch page
//   9. Call bad_compute() again - now routed through the fix
//  10. Send ACK to server

#import "standard.fx";
#ifdef __WINDOWS__
#import "net_windows.fx";
#endif;
#ifdef __LINUX__
#import "net_linux.fx";
#endif;
#import "../../examples/hotpatch_protocol2.fx";

using standard::io::console,
      standard::net;

// ============================================================================
// The broken function - intentional null-write segfault
// ============================================================================

def bad_compute(ulong x) -> ulong
{
    // BUG: writes to address 0 - instant segfault
    ulong* null_ptr = (@)0;
    *null_ptr = x; // Write, segfault, OS says no
    return x * 3;
};

// ============================================================================
// Detour helpers  (same primitives as detour.fx)
// ============================================================================

global int PATCH_BYTES = 14;

def write_jmp_indirect(ulong dst) -> void
{
    byte* p = (byte*)dst;
    p[0] = 0xFF;
    p[1] = 0x25;
    p[2] = 0x00;
    p[3] = 0x00;
    p[4] = 0x00;
    p[5] = 0x00;
};

def write_addr64(ulong dst, ulong addr) -> void
{
    byte* p = (byte*)dst;
    p[0] = (addr & 0xFF);
    p[1] = ((addr >> 8)  & 0xFF);
    p[2] = ((addr >> 16) & 0xFF);
    p[3] = ((addr >> 24) & 0xFF);
    p[4] = ((addr >> 32) & 0xFF);
    p[5] = ((addr >> 40) & 0xFF);
    p[6] = ((addr >> 48) & 0xFF);
    p[7] = ((addr >> 56) & 0xFF);
};

// Stamp a 14-byte absolute indirect JMP at target_addr pointing to patch_addr
def install_patch(ulong target_addr, ulong patch_addr) -> void
{
    u32 old_protect;
    VirtualProtect(target_addr, PATCH_BYTES, 0x40, @old_protect);

    write_jmp_indirect(target_addr);
    write_addr64(target_addr + 6, patch_addr);

    FlushInstructionCache(0xFFFFFFFFFFFFFFFF, target_addr, PATCH_BYTES);
};

// ============================================================================
// Receive helpers
// ============================================================================

// Receive exactly `n` bytes from `sockfd` into `buf`.
def recv_exact(int sockfd, byte* buf, int n) -> bool
{
    int total, got;
    while (total < n)
    {
        got = recv(sockfd, (void*)(buf + total), n - total, 0);
        if (got <= 0)
        {
            return false;
        };
        total = total + got;
    };
    return true;
};

// ============================================================================
// Main
// ============================================================================

def main() -> int
{
    print("=== Hotpatch Client ===\n\0");

    // --- Show what bad_compute would do ---
    print("\n[bad_compute is BROKEN - calling it would segfault]\n\0");
    print("  bad_compute writes to address 0x0 - instant crash\n\0");
    print("  Skipping direct call, waiting for hotpatch...\n\0");

    // --- Init Winsock ---
    if (init() != 0)
    {
        print("[client] WSAStartup failed\n\0");
        return 1;
    };

    // --- Connect to hotpatch server ---
    print("\n[client] connecting to 127.0.0.1:\0");
    print(HOTPATCH_PORT);
    print("...\n\0");

    // Build sockaddr_in manually - inet_addr already returns network byte order,
    // so we must NOT call htonl on it.  tcp_client_connect goes through
    // init_sockaddr_str which double-swaps the address, so we bypass it here.
    int sockfd = tcp_socket();
    if (sockfd < 0)
    {
        print("[client] socket() failed\n\0");
        cleanup();
        return 1;
    };

    sockaddr_in server_addr;
    server_addr.sin_family  = (u16)AF_INET;
    server_addr.sin_port    = htons(HOTPATCH_PORT);
    server_addr.sin_addr    = inet_addr("127.0.0.1\0");
    server_addr.sin_zero[0] = 0;
    server_addr.sin_zero[1] = 0;
    server_addr.sin_zero[2] = 0;
    server_addr.sin_zero[3] = 0;
    server_addr.sin_zero[4] = 0;
    server_addr.sin_zero[5] = 0;
    server_addr.sin_zero[6] = 0;
    server_addr.sin_zero[7] = 0;

    int conn_result = connect(sockfd, @server_addr, 16);
    if (conn_result < 0)
    {
        print("[client] connect() failed, WSA error: \0");
        print(get_last_error());
        print("\n\0");
        closesocket(sockfd);
        cleanup();
        return 1;
    };
    print("[client] connected\n\0");

    // --- Receive patch header (16 bytes) ---
    print("[client] receiving patch header...\n\0");

    PatchHeader header;
    byte* hdr_ptr = (byte*)@header;

    if (!recv_exact(sockfd, hdr_ptr, PATCH_HEADER_SIZE))
    {
        print("[client] failed to receive header\n\0");
        closesocket(sockfd);
        cleanup();
        return 1;
    };

    // --- Validate magic ---
    if (header.magic != PATCH_MAGIC)
    {
        print("[client] bad magic - rejecting packet\n\0");
        closesocket(sockfd);
        cleanup();
        return 1;
    };

    print("[client] magic OK, payload size = \0");
    print(header.patch_size);
    print(" bytes\n\0");

    if (header.patch_size > PATCH_MAX_SIZE)
    {
        print("[client] payload too large - rejecting\n\0");
        closesocket(sockfd);
        cleanup();
        return 1;
    };

    // --- Allocate RWX page for incoming code ---
    ulong patch_page = VirtualAlloc(0, 4096, 0x3000, 0x40);

    if (patch_page == 0)
    {
        print("[client] VirtualAlloc failed\n\0");
        closesocket(sockfd);
        cleanup();
        return 1;
    };

    // --- Receive payload bytes directly into executable page ---
    print("[client] receiving patch payload...\n\0");

    byte* payload_ptr = (byte*)patch_page;

    if (!recv_exact(sockfd, payload_ptr, (int)header.patch_size))
    {
        print("[client] failed to receive payload\n\0");
        VirtualFree(patch_page, 0, 0x8000);
        closesocket(sockfd);
        cleanup();
        return 1;
    };

    print("[client] payload received\n\0");

    // --- Receive HMAC-SHA256 signature (32 bytes) ---
    print("[client] receiving signature...\n\0");

    byte[32] recv_sig;
    if (!recv_exact(sockfd, @recv_sig[0], HMAC_SIG_SIZE))
    {
        print("[client] failed to receive signature\n\0");
        VirtualFree(patch_page, 0, 0x8000);
        closesocket(sockfd);
        cleanup();
        return 1;
    };

    // --- Verify signature before executing a single byte ---
    print("[client] verifying HMAC-SHA256 signature...\n\0");

    byte[32] expected_sig;
    byte* key_ptr = (byte*)@HMAC_KEY[0];
    hmac_sha256(key_ptr, 32, payload_ptr, header.patch_size, @expected_sig[0]);

    if (!sig_equal(@recv_sig[0], @expected_sig[0]))
    {
        print("[client] SIGNATURE INVALID - rejecting patch, possible tampering!\n\0");
        VirtualFree(patch_page, 0, 0x8000);
        closesocket(sockfd);
        cleanup();
        return 1;
    };

    print("[client] signature OK - patch is authentic\n\0");

    // --- Flush cache on the newly written page ---
    FlushInstructionCache(0xFFFFFFFFFFFFFFFF, patch_page, header.patch_size);

    // --- Install detour: bad_compute -> patch_page ---
    print("[client] installing patch over bad_compute...\n\0");
    install_patch((ulong)@bad_compute, patch_page);
    print("[client] patch installed\n\0");

    // --- Send ACK ---
    u32 ack = PATCH_ACK;
    send(sockfd, (void*)@ack, 4, 0);

    closesocket(sockfd);

    // --- Now call bad_compute - routed to the fix ---
    print("\n[client] calling bad_compute(7) via hotpatch...\n\0");
    ulong result = bad_compute(7),
          result2 = bad_compute(10);
    print("[client] result = \0");
    print(result);
    print("\n\0");

    print("\n[client] calling bad_compute(10) via hotpatch...\n\0");
    print("[client] result2 = \0");
    print(result2);
    print("\n\0");

    // --- Cleanup ---
    VirtualFree(patch_page, 0, 0x8000);
    cleanup();

    print("\n=== Client Done ===\n\0");
    return 0;
};
