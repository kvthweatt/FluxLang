// hotpatch_server.fx
//
// Hotpatch server demo.
//
// Holds the CORRECT implementation of compute() as compiled Flux.
// When a client connects, the server:
//   1. Serializes the fix function's machine code bytes by reading
//      from its own text segment via a function pointer
//   2. Computes HMAC-SHA256(HMAC_KEY, payload) as a 32-byte signature
//   3. Sends a PatchHeader followed by the raw bytes, then the signature
//   4. Waits for the client ACK
//
// The "fix" is just good_compute — the same logic bad_compute was
// supposed to implement but without the null-write bug:
//
//   good_compute(x) = x * 3
//
// The server reads its OWN compiled good_compute bytes out of memory
// and ships them to the client.  The client receives real, already-compiled
// machine code, verifies the HMAC-SHA256 signature, and only then
// executes it directly — no interpretation, no JIT.

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
// The fix — what bad_compute should have been
// ============================================================================

def good_compute(ulong x) -> ulong
{
    return x * 3;
};

// ============================================================================
// Send helpers
// ============================================================================

def send_exact(int sockfd, byte* buf, int n) -> bool
{
    int total, sent;
    while (total < n)
    {
        sent = send(sockfd, (void*)(buf + total), n - total, 0);
        if (sent <= 0)
        {
            return false;
        };
        total = total + sent;
    };
    return true;
};

// ============================================================================
// Measure function body size by scanning for a RET byte (0xC3) or
// RET imm16 (0xC2) from the function entry point.
// This is intentionally simple — production code would use a length
// disassembler.  For a leaf function with no branches this is reliable.
// We cap at 256 bytes for safety.
// ============================================================================

def measure_fn(ulong fn_addr) -> int
{
    byte* p = (byte*)fn_addr;
    int i = 0;
    while (i < 256)
    {
        // 0xC3 = RET, 0xC2 = RET imm16
        if (p[i] == 0xC3 | p[i] == 0xC2)
        {
            return i + 1;
        };
        i = i + 1;
    };
    // Fallback: send 64 bytes
    return 64;
};

// ============================================================================
// Main
// ============================================================================

def main() -> int
{
    print("=== Hotpatch Server ===\n\0");

    // --- Init Winsock ---
    if (init() != 0)
    {
        print("[server] WSAStartup failed\n\0");
        return 1;
    };

    // --- Measure good_compute's compiled body ---
    ulong fix_addr = @good_compute;
    int   fix_size = measure_fn(fix_addr);

    print("[server] good_compute at 0x\0");
    print(fix_addr);
    print(", measured size = \0");
    print(fix_size);
    print(" bytes\n\0");

    // --- Print the bytes we'll be sending (debug) ---
    print("[server] patch bytes: \0");
    byte* fix_bytes = (byte*)fix_addr;
    for (int i = 0; i < fix_size; i++)
    {
        print((int)fix_bytes[i]);
        print(" \0");
    };
    print("\n\0");

    // --- Create server socket ---
    print("\n[server] listening on port \0");
    print(HOTPATCH_PORT);
    print("...\n\0");

    int server_sock = tcp_server_create(HOTPATCH_PORT, 1);
    if (server_sock < 0)
    {
        print("[server] failed to create server socket\n\0");
        cleanup();
        return 1;
    };

    print("[server] waiting for client...\n\0");

    // --- Accept one client ---
    sockaddr_in client_addr;
    int client_sock = tcp_server_accept(server_sock, @client_addr);
    if (client_sock < 0)
    {
        print("[server] accept failed\n\0");
        tcp_close(server_sock);
        cleanup();
        return 1;
    };

    print("[server] client connected\n\0");

    // --- Build and send patch header ---
    PatchHeader header;
    header.magic       = PATCH_MAGIC;
    header.patch_size  = fix_size;
    header.target_rva  = 0;   // client resolves target directly via @bad_compute

    byte* hdr_ptr = (byte*)@header;

    print("[server] sending header (\0");
    print(PATCH_HEADER_SIZE);
    print(" bytes)...\n\0");

    if (!send_exact(client_sock, hdr_ptr, PATCH_HEADER_SIZE))
    {
        print("[server] failed to send header\n\0");
        tcp_close(client_sock);
        tcp_close(server_sock);
        cleanup();
        return 1;
    };

    // --- Send raw machine code payload ---
    print("[server] sending payload (\0");
    print(fix_size);
    print(" bytes)...\n\0");

    if (!send_exact(client_sock, fix_bytes, fix_size))
    {
        print("[server] failed to send payload\n\0");
        tcp_close(client_sock);
        tcp_close(server_sock);
        cleanup();
        return 1;
    };

    print("[server] patch sent\n\0");

    // --- Compute and send HMAC-SHA256 signature ---
    print("[server] computing HMAC-SHA256 signature...\n\0");

    byte[32] sig;
    byte* key_ptr = (byte*)@HMAC_KEY[0];
    hmac_sha256(key_ptr, 32, fix_bytes, fix_size, @sig[0]);

    print("[server] signature: \0");
    for (int si = 0; si < 32; si++)
    {
        byte hi = (sig[si] >> 4) & 0x0F;
        byte lo = sig[si] & 0x0F;
        if (hi < 10) { print('0' + hi); } else { print(('a' + (hi - 10))); };
        if (lo < 10) { print('0' + lo); } else { print(('a' + (lo - 10))); };
    };
    print("\n\0");

    if (!send_exact(client_sock, @sig[0], HMAC_SIG_SIZE))
    {
        print("[server] failed to send signature\n\0");
        tcp_close(client_sock);
        tcp_close(server_sock);
        cleanup();
        return 1;
    };

    print("[server] signature sent\n\0");

    // --- Wait for ACK ---
    print("[server] waiting for ACK...\n\0");

    u32 ack = 0;
    byte* ack_ptr = (byte*)@ack;
    int got = recv(client_sock, ack_ptr, 4, 0);

    if (got == 4 & ack == PATCH_ACK)
    {
        print("[server] ACK received - client patched successfully\n\0");
    };

    if (got != 4 | ack != PATCH_ACK)
    {
        print("[server] no ACK or NACK received\n\0");
    };

    tcp_close(client_sock);
    tcp_close(server_sock);
    cleanup();

    print("\n=== Server Done ===\n\0");
    return 0;
};
