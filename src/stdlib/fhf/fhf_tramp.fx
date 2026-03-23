// Author: Karac V. Thweatt

// fhf_tramp.fx
//
// Flux Hotpatch Framework (FHF) — Trampoline Manager
//
// Manages a single RWX page divided into FHF_TRAMP_POOL_MAX 14-byte slots.
// Each slot holds one absolute indirect JMP:
//
//   FF 25 00 00 00 00    JMP QWORD PTR [RIP+0]
//   <8 bytes of target address>
//
// The pool is protected by a spinlock so allocation is safe from multiple
// threads.  Slots are recycled when a patch is rolled back.
//
// API:
//   fhf_tramp_pool_init(pool)        -> int
//   fhf_tramp_pool_destroy(pool)     -> void
//   fhf_tramp_alloc(pool, target)    -> int   (slot index, or negative err)
//   fhf_tramp_free(pool, idx)        -> void
//   fhf_tramp_write(pool, idx, dest) -> void  (write destination into slot)
//   fhf_tramp_addr(pool, idx)        -> ulong (code address of slot)

#ifndef FHF_TRAMP
#def FHF_TRAMP 1;

#ifndef FHF_TYPES
#import "fhf\\fhf_types.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

#ifndef FLUX_STANDARD_ATOMICS
#import "atomics.fx";
#endif;

using standard::atomic;

// ============================================================================
//  Pool initialization / teardown
// ============================================================================

// Allocate the RWX pool page and zero all slots.
// Returns FHF_OK or FHF_ERR_ALLOC.
def fhf_tramp_pool_init(FHFTrampolinePool* pool) -> int
{
    if (pool == (FHFTrampolinePool*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };

    #ifdef __WINDOWS__
    // MEM_COMMIT|MEM_RESERVE = 0x3000, PAGE_EXECUTE_READWRITE = 0x40
    ulong page = VirtualAlloc((ulong)0, (size_t)4096, (u32)0x3000, (u32)0x40);
    if (page == (ulong)0)
    {
        return FHF_ERR_ALLOC;
    };
    pool.page_addr = page;
    #endif;

    store32(@pool.lock,       0);
    store32(@pool.used_count, 0);

    // Compute addresses of each 14-byte trampoline slot within the page
    int i;
    for (i = 0; i < FHF_TRAMP_POOL_MAX; i++)
    {
        pool.slots[i].magic       = (u32)0;
        store32(@pool.slots[i].in_use, 0);
        pool.slots[i].code_addr   = pool.page_addr + (ulong)(i * FHF_TRAMP_SIZE);
        pool.slots[i].target_addr = (ulong)0;
    };

    return FHF_OK;
};

// Free the RWX pool page and mark pool as empty.
def fhf_tramp_pool_destroy(FHFTrampolinePool* pool) -> void
{
    if (pool == (FHFTrampolinePool*)0) { return; };

    #ifdef __WINDOWS__
    if (pool.page_addr != (ulong)0)
    {
        VirtualFree(pool.page_addr, (size_t)0, (u32)0x8000); // MEM_RELEASE
        pool.page_addr = (ulong)0;
    };
    #endif;

    store32(@pool.used_count, 0);
};

// ============================================================================
//  Slot allocation / deallocation
// ============================================================================

// Atomically claim a free slot and associate it with target_addr.
// Returns the slot index (>=0) on success, FHF_ERR_TRAMP_POOL_FULL otherwise.
def fhf_tramp_alloc(FHFTrampolinePool* pool, ulong target_addr) -> int
{
    spin_lock(@pool.lock);

    int found = -1;
    int i;
    for (i = 0; i < FHF_TRAMP_POOL_MAX; i++)
    {
        if (load32(@pool.slots[i].in_use) == 0)
        {
            store32(@pool.slots[i].in_use, 1);
            pool.slots[i].magic       = FHF_TRAMP_MAGIC;
            pool.slots[i].target_addr = target_addr;
            inc32(@pool.used_count);
            found = i;
            i = FHF_TRAMP_POOL_MAX; // break
        };
    };

    spin_unlock(@pool.lock);

    if (found < 0)
    {
        return FHF_ERR_TRAMP_POOL_FULL;
    };
    return found;
};

// Release slot idx back to the pool.
def fhf_tramp_free(FHFTrampolinePool* pool, int idx) -> void
{
    if (pool == (FHFTrampolinePool*)0) { return; };
    if (idx < 0 | idx >= FHF_TRAMP_POOL_MAX) { return; };

    spin_lock(@pool.lock);
    store32(@pool.slots[idx].in_use, 0);
    pool.slots[idx].magic       = (u32)0;
    pool.slots[idx].target_addr = (ulong)0;
    dec32(@pool.used_count);
    spin_unlock(@pool.lock);
};

// ============================================================================
//  Trampoline code writing
// ============================================================================

// Write a 14-byte absolute indirect JMP into slot idx's code location,
// targeting dest_addr.
//
//   Encoding:
//     Bytes 0-1  : FF 25          (JMP QWORD PTR [RIP+0])
//     Bytes 2-5  : 00 00 00 00    (32-bit displacement = 0)
//     Bytes 6-13 : <dest_addr>    (little-endian 64-bit target)
def fhf_tramp_write(FHFTrampolinePool* pool, int idx, ulong dest_addr) -> void
{
    if (pool == (FHFTrampolinePool*)0) { return; };
    if (idx < 0 | idx >= FHF_TRAMP_POOL_MAX) { return; };

    ulong code = pool.slots[idx].code_addr;
    byte* p = (byte*)code;

    p[0] = (byte)0xFF;
    p[1] = (byte)0x25;
    p[2] = (byte)0x00;
    p[3] = (byte)0x00;
    p[4] = (byte)0x00;
    p[5] = (byte)0x00;
    p[6]  = (byte)(dest_addr        & (ulong)0xFF);
    p[7]  = (byte)((dest_addr >> 8)  & (ulong)0xFF);
    p[8]  = (byte)((dest_addr >> 16) & (ulong)0xFF);
    p[9]  = (byte)((dest_addr >> 24) & (ulong)0xFF);
    p[10] = (byte)((dest_addr >> 32) & (ulong)0xFF);
    p[11] = (byte)((dest_addr >> 40) & (ulong)0xFF);
    p[12] = (byte)((dest_addr >> 48) & (ulong)0xFF);
    p[13] = (byte)((dest_addr >> 56) & (ulong)0xFF);

    #ifdef __WINDOWS__
    FlushInstructionCache((ulong)0xFFFFFFFFFFFFFFFF, code, (size_t)14);
    #endif;
};

// Return the virtual address of slot idx's executable code.
def fhf_tramp_addr(FHFTrampolinePool* pool, int idx) -> ulong
{
    if (pool == (FHFTrampolinePool*)0) { return (ulong)0; };
    if (idx < 0 | idx >= FHF_TRAMP_POOL_MAX) { return (ulong)0; };
    return pool.slots[idx].code_addr;
};

#endif; // FHF_TRAMP
