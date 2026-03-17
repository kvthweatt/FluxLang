// fhf_cli.fx
//
// Flux Hotpatch Framework (FHF) — CLI Tooling
//
// Implements the `fluxpatch` command-line interface:
//
//   fluxpatch apply   <bundle.fhfb> [--key <hex32>]
//     Apply a bundle file to the current process (self-patch demo).
//
//   fluxpatch rollback <index>
//     Roll back a specific patch by record index.
//
//   fluxpatch rollback-all
//     Roll back all applied patches.
//
//   fluxpatch inspect
//     Print the current state of all patch records.
//
//   fluxpatch serve <bundle.fhfb> [--port <n>] [--key <hex32>]
//     Start a patch server that pushes the bundle to one connecting client.
//
//   fluxpatch receive [--host <ip>] [--port <n>] [--key <hex32>]
//     Connect to a patch server, receive and apply the bundle.
//
//   fluxpatch help
//     Print usage.
//
// The CLI maintains a single process-global FHFManager instance.

#ifndef FLUX_STANDARD
#import "standard.fx";
#endif;

#ifndef FHF_CLI
#def FHF_CLI 1;

#ifndef FHF_RUNTIME
#import "fhf\\fhf_runtime.fx";
#endif;
#ifndef FHF_REMOTE
#import "fhf\\fhf_remote.fx";
#endif;
#ifndef FHF_BUNDLE
#import "fhf\\fhf_bundle.fx";
#endif;


using standard::io::console;

// ============================================================================
//  Process-global manager
// ============================================================================

global FHFManager g_fhf_mgr;
global int        g_fhf_ready = 0;

// ============================================================================
//  String helpers (minimal, no stdlib dependency)
// ============================================================================

def _cli_str_eq(byte* a, byte* b) -> bool
{
    int i = 0;
    while (a[i] != (byte)0 & b[i] != (byte)0)
    {
        if (a[i] != b[i]) { return false; };
        i++;
    };
    return a[i] == b[i];
};

def _cli_str_len(byte* s) -> int
{
    int i = 0;
    while (s[i] != (byte)0) { i++; };
    return i;
};

// Parse a hex nibble.  Returns -1 on invalid input.
def _cli_hex_nibble(byte c) -> int
{
    if (c >= (byte)'0' & c <= (byte)'9') { return (int)(c - (byte)'0'); };
    if (c >= (byte)'a' & c <= (byte)'f') { return (int)(c - (byte)'a') + 10; };
    if (c >= (byte)'A' & c <= (byte)'F') { return (int)(c - (byte)'A') + 10; };
    return -1;
};

// Decode a 64-character hex string into a 32-byte key buffer.
// Returns true on success.
def _cli_parse_hex_key(byte* hex, byte* out32) -> bool
{
    int i;
    for (i = 0; i < 32; i++)
    {
        int hi = _cli_hex_nibble(hex[i * 2]);
        int lo = _cli_hex_nibble(hex[i * 2 + 1]);
        if (hi < 0 | lo < 0) { return false; };
        out32[i] = (byte)((hi << 4) | lo);
    };
    return true;
};

// Parse a decimal integer string.  Returns -1 on failure.
def _cli_parse_int(byte* s) -> int
{
    int v = 0;
    int i = 0;
    while (s[i] >= (byte)'0' & s[i] <= (byte)'9')
    {
        v = v * 10 + (int)(s[i] - (byte)'0');
        i++;
    };
    if (i == 0) { return -1; };
    return v;
};

// ============================================================================
//  File I/O (Windows)
// ============================================================================

#ifdef __WINDOWS__
extern
{
    def !!
        CreateFileA(byte*, u32, u32, void*, u32, u32, void*) -> ulong,
        ReadFile(ulong, void*, u32, u32*, void*)              -> int,
        GetFileSize(ulong, u32*)                              -> u32,
        CloseHandle(ulong)                                    -> int;
};

const u32 GENERIC_READ_ACCESS  = 0x80000000;

// Read an entire file into a heap buffer.  Caller must free().
// Returns NULL on failure.  Writes size into *out_size.
def _cli_read_file(byte* path, int* out_size) -> byte*
{
    ulong fh = CreateFileA(path, GENERIC_READ_ACCESS, (u32)0, (void*)0,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, (void*)0);

    if (fh == (ulong)0xFFFFFFFFFFFFFFFF)
    {
        return (byte*)0;
    };

    u32 hi = (u32)0;
    u32 lo = GetFileSize(fh, @hi);
    int size = (int)lo; // bundles fit in 32-bit on reasonable machines

    byte* buf = (byte*)malloc((size_t)(size + 1));
    if (buf == (byte*)0)
    {
        CloseHandle(fh);
        return (byte*)0;
    };

    u32 bytes_read = (u32)0;
    ReadFile(fh, (void*)buf, (u32)size, @bytes_read, (void*)0);
    CloseHandle(fh);

    *out_size = (int)bytes_read;
    return buf;
};
#endif;

// ============================================================================
//  Command implementations
// ============================================================================

def _cli_ensure_ready(byte* key_hex) -> int
{
    if (g_fhf_ready != 0) { return FHF_OK; };

    byte[32] key;
    int i;
    for (i = 0; i < 32; i++) { key[i] = (byte)0; };

    if (key_hex != (byte*)0)
    {
        if (!_cli_parse_hex_key(key_hex, @key[0]))
        {
            print("[fluxpatch] ERROR: invalid key hex string\n\0");
            return FHF_ERR_INVALID_ARG;
        };
    };

    int rc = fhf_init(@g_fhf_mgr, (key_hex != (byte*)0) ? @key[0] : (byte*)0);
    if (rc != FHF_OK)
    {
        print("[fluxpatch] ERROR: fhf_init failed: \0");
        print(rc);
        print("\n\0");
        return rc;
    };

    g_fhf_ready = 1;
    return FHF_OK;
};

// fluxpatch apply <bundle_path> [--key <hex>]
def cmd_apply(byte* bundle_path, byte* key_hex) -> int
{
    int rc = _cli_ensure_ready(key_hex);
    if (rc != FHF_OK) { return rc; };

    print("[fluxpatch apply] loading bundle: \0");
    print(bundle_path);
    print("\n\0");

    #ifdef __WINDOWS__
    int bundle_size = 0;
    byte* bundle = _cli_read_file(bundle_path, @bundle_size);
    if (bundle == (byte*)0)
    {
        print("[fluxpatch apply] ERROR: could not read file\n\0");
        return FHF_ERR_IO;
    };

    print("[fluxpatch apply] bundle size: \0");
    print(bundle_size);
    print(" bytes\n\0");

    rc = fhf_apply_bundle(@g_fhf_mgr, bundle, bundle_size);
    free((void*)bundle);

    if (rc == FHF_OK)
    {
        print("[fluxpatch apply] SUCCESS\n\0");
    }
    else
    {
        print("[fluxpatch apply] FAILED: error code \0");
        print(rc);
        print("\n\0");
    };

    return rc;
    #endif;
    #ifndef __WINDOWS__
    print("[fluxpatch apply] ERROR: file I/O not implemented on this platform\n\0");
    return FHF_ERR_IO;
    #endif;
};

// fluxpatch rollback <index>
def cmd_rollback(byte* idx_str) -> int
{
    if (g_fhf_ready == 0)
    {
        print("[fluxpatch rollback] ERROR: no active manager\n\0");
        return FHF_ERR_INVALID_ARG;
    };

    int idx = _cli_parse_int(idx_str);
    if (idx < 0)
    {
        print("[fluxpatch rollback] ERROR: invalid index\n\0");
        return FHF_ERR_INVALID_ARG;
    };

    int rc = fhf_rollback(@g_fhf_mgr, idx);
    if (rc == FHF_OK)
    {
        print("[fluxpatch rollback] patch \0");
        print(idx);
        print(" rolled back\n\0");
    }
    else
    {
        print("[fluxpatch rollback] FAILED: error code \0");
        print(rc);
        print("\n\0");
    };
    return rc;
};

// fluxpatch rollback-all
def cmd_rollback_all() -> int
{
    if (g_fhf_ready == 0)
    {
        print("[fluxpatch rollback-all] ERROR: no active manager\n\0");
        return FHF_ERR_INVALID_ARG;
    };
    fhf_rollback_all(@g_fhf_mgr);
    print("[fluxpatch rollback-all] all patches rolled back\n\0");
    return FHF_OK;
};

// fluxpatch inspect
def cmd_inspect() -> int
{
    if (g_fhf_ready == 0)
    {
        print("[fluxpatch inspect] no active manager\n\0");
        return FHF_OK;
    };
    fhf_inspect(@g_fhf_mgr);
    return FHF_OK;
};

// fluxpatch serve <bundle_path> [--port <n>] [--key <hex>]
def cmd_serve(byte* bundle_path, int port, byte* key_hex) -> int
{
    int rc = _cli_ensure_ready(key_hex);
    if (rc != FHF_OK) { return rc; };

    print("[fluxpatch serve] loading bundle: \0");
    print(bundle_path);
    print("\n\0");

    #ifdef __WINDOWS__
    int bundle_size = 0;
    byte* bundle = _cli_read_file(bundle_path, @bundle_size);
    if (bundle == (byte*)0)
    {
        print("[fluxpatch serve] ERROR: could not read bundle file\n\0");
        return FHF_ERR_IO;
    };

    print("[fluxpatch serve] listening on port \0");
    print(port);
    print("...\n\0");

    rc = fhf_remote_serve(@g_fhf_mgr, (u16)port, bundle, bundle_size);
    free((void*)bundle);

    if (rc == FHF_OK)
    {
        print("[fluxpatch serve] bundle delivered and ACKed\n\0");
    }
    else
    {
        print("[fluxpatch serve] FAILED: error code \0");
        print(rc);
        print("\n\0");
    };
    return rc;
    #endif;
    #ifndef __WINDOWS__
    print("[fluxpatch serve] ERROR: not implemented on this platform\n\0");
    return FHF_ERR_IO;
    #endif;
};

// fluxpatch receive [--host <ip>] [--port <n>] [--key <hex>]
def cmd_receive(byte* host, int port, byte* key_hex) -> int
{
    int rc = _cli_ensure_ready(key_hex);
    if (rc != FHF_OK) { return rc; };

    print("[fluxpatch receive] connecting to \0");
    print(host);
    print(":\0");
    print(port);
    print("...\n\0");

    rc = fhf_remote_receive(@g_fhf_mgr, host, (u16)port);
    if (rc == FHF_OK)
    {
        print("[fluxpatch receive] bundle applied successfully\n\0");
    }
    else
    {
        print("[fluxpatch receive] FAILED: error code \0");
        print(rc);
        print("\n\0");
    };
    return rc;
};

// ============================================================================
//  Usage
// ============================================================================

def cmd_help() -> void
{
    print("Flux Hotpatch Framework CLI\n\0");
    print("Usage:\n\0");
    print("  fluxpatch apply   <bundle.fhfb> [--key <hex64>]\n\0");
    print("  fluxpatch rollback <index>\n\0");
    print("  fluxpatch rollback-all\n\0");
    print("  fluxpatch inspect\n\0");
    print("  fluxpatch serve   <bundle.fhfb> [--port <n>] [--key <hex64>]\n\0");
    print("  fluxpatch receive [--host <ip>] [--port <n>] [--key <hex64>]\n\0");
    print("  fluxpatch help\n\0");
};

// ============================================================================
//  Entry point
// ============================================================================

def main(int argc, byte** argv) -> int
{

    if (argc < 1)
    {
        cmd_help();
        return 0;
    };

    byte* cmd = argv[1];

    // --- apply ---
    if (_cli_str_eq(cmd, "apply\0"))
    {
        if (argc < 3)
        {
            print("ERROR: apply requires a bundle path\n\0");
            return 1;
        };
        byte* bundle_path = argv[2];
        byte* key_hex     = (byte*)0;
        int i;
        for (i = 3; i < argc - 1; i++)
        {
            if (_cli_str_eq(argv[i], "--key\0")) { key_hex = argv[i + 1]; };
        };
        return cmd_apply(bundle_path, key_hex) == FHF_OK ? 0 : 1;
    };

    // --- rollback ---
    if (_cli_str_eq(cmd, "rollback\0"))
    {
        if (argc < 3)
        {
            print("ERROR: rollback requires an index\n\0");
            return 1;
        };
        return cmd_rollback(argv[2]) == FHF_OK ? 0 : 1;
    };

    // --- rollback-all ---
    if (_cli_str_eq(cmd, "rollback-all\0"))
    {
        return cmd_rollback_all() == FHF_OK ? 0 : 1;
    };

    // --- inspect ---
    if (_cli_str_eq(cmd, "inspect\0"))
    {
        return cmd_inspect() == FHF_OK ? 0 : 1;
    };

    // --- serve ---
    if (_cli_str_eq(cmd, "serve\0"))
    {
        if (argc < 3)
        {
            print("ERROR: serve requires a bundle path\n\0");
            return 1;
        };
        byte* bundle_path = argv[2];
        int   port        = 9901;
        byte* key_hex     = (byte*)0;
        int i;
        for (i = 3; i < argc - 1; i++)
        {
            if (_cli_str_eq(argv[i], "--port\0"))
            {
                int p = _cli_parse_int(argv[i + 1]);
                if (p > 0) { port = p; };
            };
            if (_cli_str_eq(argv[i], "--key\0")) { key_hex = argv[i + 1]; };
        };
        return cmd_serve(bundle_path, port, key_hex) == FHF_OK ? 0 : 1;
    };

    // --- receive ---
    if (_cli_str_eq(cmd, "receive\0"))
    {
        byte* host    = "127.0.0.1\0";
        int   port    = 9901;
        byte* key_hex = (byte*)0;
        int i;
        for (i = 2; i < argc - 1; i++)
        {
            if (_cli_str_eq(argv[i], "--host\0")) { host    = argv[i + 1]; };
            if (_cli_str_eq(argv[i], "--port\0"))
            {
                int p = _cli_parse_int(argv[i + 1]);
                if (p > 0) { port = p; };
            };
            if (_cli_str_eq(argv[i], "--key\0"))  { key_hex = argv[i + 1]; };
        };
        return cmd_receive(host, port, key_hex) == FHF_OK ? 0 : 1;
    };

    // --- help / unknown ---
    cmd_help();
    return 0;
};

#endif; // FHF_CLI
