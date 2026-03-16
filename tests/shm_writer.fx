// shm_writer.fx
// Creates a named shared memory region, writes a message and a counter
// array into it, then waits for the reader to signal it is done.
//
// Run this first, then run shm_reader.fx in a second terminal.
//
// Shared memory layout (all offsets in bytes):
//   [0..3]   i32  ready  - writer sets to 1 when data is ready
//   [4..7]   i32  done   - reader sets to 1 when it has consumed the data
//   [8..71]  byte[64]    - null-terminated message string
//   [72..]   i32[8]      - array of integers

#import "standard.fx";
#import "atomics.fx";
#import "sharedmemory.fx";

using standard::io::console;
using standard::atomic;
using standard::sharedmemory;

const byte[] SHM_NAME  = "flux_shm_demo\0";
const int    SHM_SIZE  = 4096,
             MSG_OFFSET = 8,
             ARR_OFFSET = 72,
             ARR_COUNT  = 8;

def write_str(byte* dst, byte* src) -> void
{
    int i = 0;
    while (src[i] != '\0')
    {
        dst[i] = src[i];
        i = i + 1;
    };
    dst[i] = '\0';
};

def main() -> int
{
    print("=== shm_writer ===\n\0");

    // ── Create and map the region ──────────────────────────
    SharedMem shm;
    int rc = shm_create(@shm, @SHM_NAME[0], (size_t)SHM_SIZE);
    if (rc != SHM_OK)
    {
        print("shm_create failed\n\0");
        return 1;
    };
    print("shared memory created\n\0");

    byte* base = (byte*)shm_map(@shm, SHM_READ | SHM_WRITE);
    if ((u64)base == (u64)0)
    {
        print("shm_map failed\n\0");
        shm_destroy(@shm, @SHM_NAME[0]);
        return 1;
    };

    // ── Lay out pointers into the region ───────────────────
    i32*  ready = (i32*)base;
    i32*  done  = (i32*)(base + 4);
    byte* msg   = base + MSG_OFFSET;
    i32*  arr   = (i32*)(base + ARR_OFFSET);

    // Clear the handshake flags.
    store32(ready, 0);
    store32(done,  0);

    // ── Write the message ──────────────────────────────────
    write_str(msg, "Hello from shm_writer!\0");

    // ── Write the integer array ────────────────────────────
    int i = 0;
    while (i < ARR_COUNT)
    {
        arr[i] = (i + 1) * 10;   // 10, 20, 30, ... 80
        i = i + 1;
    };

    print("data written to shared memory\n\0");
    print("message : \0");
    print(msg);
    print("\n\0");

    i = 0;
    while (i < ARR_COUNT)
    {
        print("arr[\0");
        print(i);
        print("] = \0");
        print(arr[i]);
        print("\n\0");
        i = i + 1;
    };

    // ── Signal the reader ──────────────────────────────────
    fence();
    store32(ready, 1);
    print("signalled reader (ready = 1)\n\0");

    // ── Wait for the reader to finish ─────────────────────
    print("waiting for reader...\n\0");
    while (load32(done) == 0)
    {
        #ifdef __ARCH_X86_64__
        volatile asm { pause } : : : "memory";
        #endif;
        #ifdef __ARCH_ARM64__
        volatile asm { yield } : : : "memory";
        #endif;
    };
    print("reader signalled done\n\0");

    // ── Cleanup ────────────────────────────────────────────
    shm_flush(@shm);
    shm_destroy(@shm, @SHM_NAME[0]);
    print("shared memory destroyed\n\0");
    print("=== shm_writer done ===\n\0");
    return 0;
};
