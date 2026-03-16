// shm_reader.fx
// Opens the named shared memory region created by shm_writer.fx,
// waits for the writer to mark the data as ready, reads and prints
// everything, then signals the writer that it is done.
//
// Run shm_writer.fx first, then run this in a second terminal.
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

def main() -> int
{
    print("=== shm_reader ===\n\0");

    // ── Open the existing region ───────────────────────────
    SharedMem shm;
    int rc = shm_open_existing(@shm, @SHM_NAME[0], (size_t)SHM_SIZE);
    if (rc != SHM_OK)
    {
        print("shm_open_existing failed - is shm_writer running?\n\0");
        return 1;
    };
    print("shared memory opened\n\0");

    byte* base = (byte*)shm_map(@shm, SHM_READ | SHM_WRITE);
    if ((u64)base == (u64)0)
    {
        print("shm_map failed\n\0");
        shm_close(@shm);
        return 1;
    };

    // ── Lay out pointers into the region ───────────────────
    i32*  ready = (i32*)base;
    i32*  done  = (i32*)(base + 4);
    byte* msg   = base + MSG_OFFSET;
    i32*  arr   = (i32*)(base + ARR_OFFSET);

    // ── Wait for the writer to signal ready ────────────────
    print("waiting for writer...\n\0");
    while (load32(ready) == 0)
    {
        #ifdef __ARCH_X86_64__
        volatile asm { pause } : : : "memory";
        #endif;
        #ifdef __ARCH_ARM64__
        volatile asm { yield } : : : "memory";
        #endif;
    };
    load_fence();
    print("writer signalled ready\n\0");

    // ── Read and print the data ────────────────────────────
    print("message : \0");
    print(msg);
    print("\n\0");

    int i = 0;
    while (i < ARR_COUNT)
    {
        print("arr[\0");
        print(i);
        print("] = \0");
        print(arr[i]);
        print("\n\0");
        i = i + 1;
    };

    // ── Signal the writer that we are done ─────────────────
    store32(done, 1);
    print("signalled writer (done = 1)\n\0");

    // ── Cleanup ────────────────────────────────────────────
    shm_unmap(@shm);
    shm_close(@shm);
    print("=== shm_reader done ===\n\0");
    return 0;
};
