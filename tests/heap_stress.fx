// Author: Karac V. Thweatt
// heap_stress.fx - Stress test for standard::memory::allocators::stdheap

#import "standard.fx", "allocators.fx", "random.fx", "timing.fx";

using standard::io::console,
      standard::strings,
      standard::time,
      standard::random,
      standard::memory::allocators::stdheap;

global int g_pass, g_fail;

def pass(byte* name) -> void
{
    print("[PASS] \0");
    print(name);
    print("\n\0");
    g_pass = g_pass + 1;
    return;
};

def fail(byte* name) -> void
{
    print("[FAIL] \0");
    print(name);
    print("\n\0");
    g_fail = g_fail + 1;
    return;
};

def check(bool ok, byte* name) -> void
{
    if (ok) { pass(name); }
    else    { fail(name); };
    return;
};

def print_mb(size_t bytes) -> void
{
    byte[32] buf;
    u64str((u64)(bytes / 1048576), @buf[0]);
    print(@buf[0]);
    print(" MB\0");
    return;
};

// Size classes:  0=16  1=32  2=64  3=128  4=256  5=512  6=1024  7=2048  8=4096
// Each class_block_size is the canonical block returned by the bump path.
// >4096 is large: dedicated OS slab.

#def SMALL_SIZES_COUNT  (size_t)9;

// =========================================================================
// Test 1: Null / zero-size edge cases
// =========================================================================
def test_edge_cases() -> void
{
    u64 p;

    print("-- edge cases --\n\0");

    p = fmalloc((size_t)0);
    check(p == (u64)0, "fmalloc(0) returns null\0");

    ffree((u64)0);
    check(true, "ffree(null) does not crash\0");

    p = frealloc((u64)0, (size_t)0);
    check(p == (u64)0, "frealloc(null, 0) returns null\0");

    p = frealloc((u64)0, (size_t)64);
    check(p != (u64)0, "frealloc(null, 64) acts as fmalloc\0");
    ffree(p);

    p = fmalloc((size_t)64);
    check(p != (u64)0, "setup alloc for frealloc(ptr,0)\0");
    u64 r = frealloc(p, (size_t)0);
    check(r == (u64)0, "frealloc(ptr, 0) acts as ffree, returns null\0");

    return;
};

// =========================================================================
// Test 2: Every size class allocates, returns non-null, 16-byte aligned
// =========================================================================
def test_all_size_classes() -> void
{
    // Canonical sizes: one per class boundary plus boundary-minus-one
    size_t[18] sizes;
    u64[18]    ptrs;
    size_t     i;
    byte[64]   buf;

    print("-- all size classes --\n\0");

    sizes[0]  = (size_t)1;      // class 0 (<=16)
    sizes[1]  = (size_t)16;     // class 0 upper boundary
    sizes[2]  = (size_t)17;     // class 1 lower boundary
    sizes[3]  = (size_t)32;     // class 1 upper boundary
    sizes[4]  = (size_t)33;     // class 2 lower boundary
    sizes[5]  = (size_t)64;     // class 2 upper boundary
    sizes[6]  = (size_t)65;     // class 3 lower boundary
    sizes[7]  = (size_t)128;    // class 3 upper boundary
    sizes[8]  = (size_t)129;    // class 4 lower boundary
    sizes[9]  = (size_t)256;    // class 4 upper boundary
    sizes[10] = (size_t)257;    // class 5 lower boundary
    sizes[11] = (size_t)512;    // class 5 upper boundary
    sizes[12] = (size_t)513;    // class 6 lower boundary
    sizes[13] = (size_t)1024;   // class 6 upper boundary
    sizes[14] = (size_t)1025;   // class 7 lower boundary
    sizes[15] = (size_t)2048;   // class 7 upper boundary
    sizes[16] = (size_t)2049;   // class 8 lower boundary
    sizes[17] = (size_t)4096;   // class 8 upper boundary

    while (i < (size_t)18)
    {
        ptrs[i] = fmalloc(sizes[i]);
        check(ptrs[i] != (u64)0,                  "size class alloc non-null\0");
        check((ptrs[i] & (u64)15) == (u64)0,      "size class alloc 16-byte aligned\0");
        i++;
    };

    i = 0;
    while (i < (size_t)18)
    {
        ffree(ptrs[i]);
        i++;
    };
    return;
};

// =========================================================================
// Test 3: Large allocation (>4096) gets its own OS slab, is 16-byte aligned,
//         write/read correctness, and large blocks are properly freed
// =========================================================================
def test_large_alloc() -> void
{
    u64    p;
    byte*  bp;
    size_t i;
    bool   ok;

    print("-- large alloc (>4096) --\n\0");

    // Exact boundary: 4097 bytes
    p = fmalloc((size_t)4097);
    check(p != (u64)0,           "fmalloc(4097) non-null\0");
    check((p & (u64)15) == 0,    "fmalloc(4097) 16-byte aligned\0");
    ffree(p);

    // 1 MB
    p = fmalloc((size_t)1048576);
    check(p != (u64)0,           "fmalloc(1MB) non-null\0");
    check((p & (u64)15) == 0,    "fmalloc(1MB) 16-byte aligned\0");

    bp = (byte*)p;
    ok = true;
    while (i < (size_t)1048576) { bp[i] = (byte)0xCD; i++; };
    i = 0;
    while (i < (size_t)1048576)
    {
        if (bp[i] != (byte)0xCD) { ok = false; break; };
        i++;
    };
    check(ok, "fmalloc(1MB) write/read correct\0");
    ffree(p);

    // 8 MB
    p = fmalloc((size_t)8388608);
    check(p != (u64)0,           "fmalloc(8MB) non-null\0");
    ok = true;
    bp = (byte*)p;
    i  = 0;
    while (i < (size_t)8388608) { bp[i] = (byte)0xAB; i++; };
    i = 0;
    while (i < (size_t)8388608)
    {
        if (bp[i] != (byte)0xAB) { ok = false; break; };
        i++;
    };
    check(ok, "fmalloc(8MB) write/read correct\0");
    ffree(p);

    return;
};

// =========================================================================
// Test 4: Free-list bin reuse - freed small blocks are handed back first
// =========================================================================
def test_bin_reuse() -> void
{
    u64    p1, p2, p3;

    print("-- bin reuse --\n\0");

    // Allocate two class-2 (64-byte) blocks from the bump path.
    p1 = fmalloc((size_t)64);
    p2 = fmalloc((size_t)64);
    check(p1 != (u64)0, "first  alloc(64) non-null\0");
    check(p2 != (u64)0, "second alloc(64) non-null\0");
    check(p1 != p2,     "two allocs differ\0");

    // Free p1; the block enters bin[2].
    ffree(p1);

    // Next alloc of same class must reuse p1 (LIFO free-list).
    p3 = fmalloc((size_t)64);
    check(p3 == p1, "bin reuse returns previously freed block\0");

    ffree(p2);
    ffree(p3);

    // Same exercise for class-3 (128 bytes)
    p1 = fmalloc((size_t)128);
    ffree(p1);
    p2 = fmalloc((size_t)128);
    check(p2 == p1, "bin reuse class-3 (128 bytes)\0");
    ffree(p2);

    // Same exercise for class-0 (16 bytes, upper boundary)
    p1 = fmalloc((size_t)16);
    ffree(p1);
    p2 = fmalloc((size_t)16);
    check(p2 == p1, "bin reuse class-0 (16 bytes)\0");
    ffree(p2);

    return;
};

// =========================================================================
// Test 5: Write/read correctness - fill block with tag, verify after alloc
// =========================================================================
def test_write_read() -> void
{
    PCG32  rng;
    size_t i, j, n, sz;
    bool   ok;
    byte*  p;
    byte   tag;
    u32    rval;
    u64    rval64, ptr;

    print("-- write/read correctness (10000 allocs/frees) --\n\0");
    pcg32_init(@rng);

    n  = (size_t)10000;
    ok = true;
    while (i < n)
    {
        rval   = pcg32_next(@rng);
        rval64 = (u64)rval;
        sz     = (size_t)(rval64 % (u64)4096) + (size_t)1;
        tag    = (byte)(i & 0xFF);
        ptr    = fmalloc(sz);
        if (ptr == (u64)0) { ok = false; break; };
        p = (byte*)ptr;
        j = 0;
        while (j < sz) { p[j] = tag; j++; };
        j = 0;
        while (j < sz)
        {
            if (p[j] != tag) { ok = false; break; };
            j++;
        };
        if (!ok) { break; };
        ffree(ptr);
        i++;
    };
    check(ok, "write/read correct across 10000 random-sized alloc/free cycles\0");
    return;
};

// =========================================================================
// Test 6: Concurrent live allocations - hold N pointers, verify no overlap
// =========================================================================
def test_no_overlap() -> void
{
    // Hold 512 live blocks and stamp each with a unique byte tag.
    // After all are allocated, verify every block still holds its original tag.
    // This catches aliasing bugs (two ptrs pointing to the same memory).

    size_t n, i, j;
    u64[512]  ptrs;
    byte[512] tags;
    bool      ok;
    byte*     bp;
    PCG32     rng;
    u32       rval;
    u64       rval64;
    size_t    sz;

    print("-- no-overlap under 512 live blocks --\n\0");
    pcg32_init(@rng);

    n  = (size_t)512;
    ok = true;

    while (i < n)
    {
        rval      = pcg32_next(@rng);
        rval64    = (u64)rval;
        sz        = (size_t)(rval64 % (u64)256) + (size_t)1;
        ptrs[i]   = fmalloc(sz);
        tags[i]   = (byte)(i & 0xFF);
        if (ptrs[i] == (u64)0) { ok = false; break; };
        bp = (byte*)ptrs[i];
        // Stamp first 16 bytes (or entire block if smaller)
        j = 0;
        while (j < (size_t)16 & j < sz)
        {
            bp[j] = tags[i];
            j++;
        };
        i++;
    };
    check(ok, "all 512 blocks allocated non-null\0");

    // Verify tags
    ok = true;
    i  = 0;
    while (i < n)
    {
        bp = (byte*)ptrs[i];
        if (bp[0] != tags[i]) { ok = false; break; };
        i++;
    };
    check(ok, "no block aliasing: all tag checks pass\0");

    i = 0;
    while (i < n) { ffree(ptrs[i]); i++; };
    return;
};

// =========================================================================
// Test 7: frealloc - same class stays in place (no move)
// =========================================================================
def test_frealloc_same_class() -> void
{
    u64    p1, p2;
    byte*  bp;
    size_t i;
    bool   ok;

    print("-- frealloc same-class in-place --\n\0");

    // class 2: any size 33..64 stays put
    p1 = fmalloc((size_t)33);
    check(p1 != (u64)0, "fmalloc(33) non-null\0");
    bp = (byte*)p1;
    i  = 0;
    while (i < (size_t)33) { bp[i] = (byte)0xAA; i++; };

    p2 = frealloc(p1, (size_t)64);   // still class 2, no move
    check(p2 == p1, "frealloc within class: same pointer returned\0");
    ok = true;
    i  = 0;
    while (i < (size_t)33)
    {
        if (((byte*)p2)[i] != (byte)0xAA) { ok = false; break; };
        i++;
    };
    check(ok, "frealloc within class: data preserved\0");
    ffree(p2);

    // Shrink: class 3 -> class 2, no move because data fits
    p1 = fmalloc((size_t)128);
    check(p1 != (u64)0, "fmalloc(128) non-null for shrink test\0");
    bp = (byte*)p1;
    i  = 0;
    while (i < (size_t)64) { bp[i] = (byte)0xBB; i++; };
    p2 = frealloc(p1, (size_t)60);   // class 2 < class 3: in-place shrink
    check(p2 == p1, "frealloc shrink to smaller class: same pointer\0");
    ok = true;
    i  = 0;
    while (i < (size_t)60)
    {
        if (((byte*)p2)[i] != (byte)0xBB) { ok = false; break; };
        i++;
    };
    check(ok, "frealloc shrink: data preserved\0");
    ffree(p2);

    return;
};

// =========================================================================
// Test 8: frealloc - grow to new class, data is preserved
// =========================================================================
def test_frealloc_grow() -> void
{
    u64    p1, p2;
    byte*  bp;
    size_t i;
    bool   ok;

    print("-- frealloc grow --\n\0");

    // class 1 -> class 3 (32 -> 128)
    p1 = fmalloc((size_t)32);
    check(p1 != (u64)0, "fmalloc(32) non-null\0");
    bp = (byte*)p1;
    i  = 0;
    while (i < (size_t)32) { bp[i] = (byte)(i & 0xFF); i++; };

    p2 = frealloc(p1, (size_t)128);
    check(p2 != (u64)0, "frealloc grow non-null\0");
    ok = true;
    i  = 0;
    while (i < (size_t)32)
    {
        if (((byte*)p2)[i] != (byte)(i & 0xFF)) { ok = false; break; };
        i++;
    };
    check(ok, "frealloc grow: original bytes preserved\0");
    ffree(p2);

    // class 2 -> large (64 -> 8192): cross the small/large boundary
    p1 = fmalloc((size_t)64);
    check(p1 != (u64)0, "fmalloc(64) non-null for cross-boundary grow\0");
    bp = (byte*)p1;
    i  = 0;
    while (i < (size_t)64) { bp[i] = (byte)(0xFF - i); i++; };

    p2 = frealloc(p1, (size_t)8192);
    check(p2 != (u64)0, "frealloc small->large non-null\0");
    check(p2 != p1,     "frealloc small->large moved pointer\0");
    ok = true;
    i  = 0;
    while (i < (size_t)64)
    {
        if (((byte*)p2)[i] != (byte)(0xFF - i)) { ok = false; break; };
        i++;
    };
    check(ok, "frealloc small->large: original bytes preserved\0");
    ffree(p2);

    // large -> small (8192 -> 64): shrink across boundary
    p1 = fmalloc((size_t)8192);
    check(p1 != (u64)0, "fmalloc(8192) non-null for large->small shrink\0");
    bp = (byte*)p1;
    i  = 0;
    while (i < (size_t)64) { bp[i] = (byte)(i * 3); i++; };
    p2 = frealloc(p1, (size_t)64);
    check(p2 != (u64)0, "frealloc large->small non-null\0");
    ok = true;
    i  = 0;
    while (i < (size_t)64)
    {
        if (((byte*)p2)[i] != (byte)(i * 3)) { ok = false; break; };
        i++;
    };
    check(ok, "frealloc large->small: bytes preserved\0");
    ffree(p2);

    return;
};

// =========================================================================
// Test 9: frealloc - large block same-size is identity (no move)
// =========================================================================
def test_frealloc_large_identity() -> void
{
    u64    p1, p2;

    print("-- frealloc large-block identity --\n\0");

    p1 = fmalloc((size_t)65536);
    check(p1 != (u64)0, "fmalloc(64K) non-null\0");
    p2 = frealloc(p1, (size_t)65536);
    check(p2 == p1, "frealloc large same-size returns same pointer\0");
    ffree(p2);
    return;
};

// =========================================================================
// Test 10: frealloc chained growth - repeatedly grow the same allocation
// =========================================================================
def test_frealloc_chain() -> void
{
    u64    ptr;
    byte*  bp;
    size_t i;
    bool   ok;

    print("-- frealloc chained growth --\n\0");

    ptr = fmalloc((size_t)8);
    check(ptr != (u64)0, "initial fmalloc(8) non-null\0");
    ((byte*)ptr)[0] = (byte)0x42;

    ptr = frealloc(ptr, (size_t)32);
    check(ptr != (u64)0, "frealloc -> 32 non-null\0");

    ptr = frealloc(ptr, (size_t)128);
    check(ptr != (u64)0, "frealloc -> 128 non-null\0");

    ptr = frealloc(ptr, (size_t)512);
    check(ptr != (u64)0, "frealloc -> 512 non-null\0");

    ptr = frealloc(ptr, (size_t)4096);
    check(ptr != (u64)0, "frealloc -> 4096 non-null\0");

    ptr = frealloc(ptr, (size_t)65536);
    check(ptr != (u64)0, "frealloc -> 65536 (large) non-null\0");

    // Shrink back through classes
    ptr = frealloc(ptr, (size_t)4096);
    check(ptr != (u64)0, "frealloc large->4096 non-null\0");

    ptr = frealloc(ptr, (size_t)64);
    check(ptr != (u64)0, "frealloc ->64 non-null\0");

    ffree(ptr);
    return;
};

// =========================================================================
// Test 11: coalesce_heap - empty-slab slabs are released to the OS
// =========================================================================
def test_coalesce() -> void
{
    size_t i, n;
    u64[64] ptrs;
    bool    ok;

    print("-- coalesce_heap --\n\0");

    n  = (size_t)64;
    ok = true;

    // Allocate 64 class-1 (32-byte) blocks.  All land in the same slab.
    while (i < n)
    {
        ptrs[i] = fmalloc((size_t)32);
        if (ptrs[i] == (u64)0) { ok = false; break; };
        i++;
    };
    check(ok, "64 blocks allocated for coalesce test\0");

    // Free all of them so the slab used-counter reaches zero.
    i = 0;
    while (i < n) { ffree(ptrs[i]); i++; };

    // coalesce_heap must detect used==0 and release that slab.
    coalesce_heap();
    check(true, "coalesce_heap completed without crash\0");

    // After coalesce, subsequent allocs must still succeed (bins or new slab).
    u64 p = fmalloc((size_t)32);
    check(p != (u64)0, "alloc after coalesce succeeds\0");
    ffree(p);
    return;
};

// =========================================================================
// Test 12: coalesce_heap - no dangling pointers in bins after slab release
// =========================================================================
def test_coalesce_bin_integrity() -> void
{
    size_t i, n;
    u64[32] ptrs;
    bool    ok;
    byte*   bp;
    size_t  j;

    print("-- coalesce bin integrity --\n\0");

    // Allocate and free 32 class-2 (64-byte) blocks.
    n = (size_t)32;
    i = 0;
    ok = true;
    while (i < n)
    {
        ptrs[i] = fmalloc((size_t)64);
        if (ptrs[i] == (u64)0) { ok = false; break; };
        i++;
    };
    check(ok, "32 class-2 blocks allocated\0");

    i = 0;
    while (i < n) { ffree(ptrs[i]); i++; };
    coalesce_heap();

    // Now allocate again - any returned pointer must be writable
    // (i.e. the bin was not left with a dangling entry into a freed slab).
    ok = true;
    i  = 0;
    while (i < n)
    {
        ptrs[i] = fmalloc((size_t)64);
        if (ptrs[i] == (u64)0) { ok = false; break; };
        bp = (byte*)ptrs[i];
        j  = 0;
        while (j < (size_t)64) { bp[j] = (byte)(i & 0xFF); j++; };
        i++;
    };
    check(ok, "post-coalesce allocs all non-null\0");

    // Verify writes
    ok = true;
    i  = 0;
    while (i < n)
    {
        bp = (byte*)ptrs[i];
        if (bp[0] != (byte)(i & 0xFF)) { ok = false; break; };
        i++;
    };
    check(ok, "post-coalesce write/read correct\0");

    i = 0;
    while (i < n) { ffree(ptrs[i]); i++; };
    return;
};

// =========================================================================
// Test 13: check_fragmentation - basic range and monotone behaviour
// =========================================================================
def test_fragmentation() -> void
{
    float  f0, f1, f2;
    u64    p1, p2, p3, p4;

    print("-- check_fragmentation --\n\0");

    // Fresh state: no slabs yet.  Large block guard path should return 0.0
    f0 = check_fragmentation();
    check(f0 >= 0.0 & f0 <= 1.0, "fragmentation in [0,1] before any alloc\0");

    // Alloc a few blocks but keep them live: minimal fragmentation expected.
    p1 = fmalloc((size_t)64);
    p2 = fmalloc((size_t)128);
    p3 = fmalloc((size_t)256);
    p4 = fmalloc((size_t)512);
    f1 = check_fragmentation();
    check(f1 >= 0.0 & f1 <= 1.0, "fragmentation in [0,1] with live blocks\0");

    // Free all: fragmentation should increase (more free bytes vs committed).
    ffree(p1);
    ffree(p2);
    ffree(p3);
    ffree(p4);
    f2 = check_fragmentation();
    check(f2 >= 0.0 & f2 <= 1.0, "fragmentation in [0,1] after freeing all\0");
    check(f2 >= f1,               "fragmentation rises after freeing live blocks\0");

    coalesce_heap();
    return;
};

// =========================================================================
// Test 14: Mixed alloc/free pattern - alternating alloc/free with
//          random sizes, checks table lookup integrity
// =========================================================================
def test_mixed_pattern() -> void
{
    PCG32       rng;
    size_t      i, n, sz;
    u64[256]    live;
    size_t[256] live_sz;
    size_t      live_count;
    u32         rval;
    u64         rval64, ptr;
    bool        ok;
    byte*       bp;
    size_t      j, victim;

    print("-- mixed alloc/free (5000 ops, up to 256 live) --\n\0");
    pcg32_init(@rng);

    n          = (size_t)5000;
    live_count = 0;
    ok         = true;

    while (i < n)
    {
        rval   = pcg32_next(@rng);
        rval64 = (u64)rval;

        // Decide: alloc or free.  If live is full, always free.
        // If live is empty, always alloc.
        // Otherwise 60% alloc / 40% free.
        bool do_alloc;
        if (live_count == (size_t)256)      { do_alloc = false; }
        elif (live_count == (size_t)0)      { do_alloc = true; }
        else                                { do_alloc = (rval64 & 0xFF) < 0x99; };

        switch (do_alloc)
        {
            case (1)
            {
                sz   = (size_t)(rval64 % (u64)4096) + (size_t)1;
                ptr  = fmalloc(sz);
                if (ptr == (u64)0) { ok = false; break; };
                // Stamp with live_count as tag
                bp = (byte*)ptr;
                j  = 0;
                while (j < (size_t)8 & j < sz) { bp[j] = (byte)(live_count & 0xFF); j++; };
                live[live_count]    = ptr;
                live_sz[live_count] = sz;
                live_count++;
            }
            default
            {
                // Pick a random victim from live set and free it.
                victim = (size_t)(rval64 % (u64)live_count);
                ffree(live[victim]);
                // Compact: move last into victim slot.
                live_count--;
                live[victim]    = live[live_count];
                live_sz[victim] = live_sz[live_count];
            };
        };

        if (!ok) { break; };
        i++;
    };
    check(ok, "5000 mixed ops: all allocs non-null\0");

    // Free remaining live blocks
    j = 0;
    while (j < live_count) { ffree(live[j]); j++; };
    return;
};

// =========================================================================
// Test 15: Table hash map stress - force many table grow cycles
//          by holding many live pointers simultaneously
// =========================================================================
def test_table_stress() -> void
{
    size_t  n, i;
    u64     p;
    bool    ok;

    // 4096 live large blocks will each get a table entry and stress rehash.
    // Use large blocks so each is independent and easy to account for.
    n  = (size_t)2048;
    ok = true;

    print("-- table stress: 2048 live large blocks --\n\0");

    // We don't have a heap-backed dynamic array, so we'll reuse a fixed array
    // and free in the same loop to keep the 'used' vector small.
    // Instead: allocate all, track in a local array.
    // Flux stack limit: use a batch of 256 at a time.
    size_t batch, b, total_freed;
    u64[256] ptrs;
    batch       = (size_t)256;
    total_freed = 0;

    while (total_freed < n)
    {
        i = 0;
        while (i < batch)
        {
            p = fmalloc((size_t)8192);
            if (p == (u64)0) { ok = false; break; };
            ptrs[i] = p;
            i++;
        };
        if (!ok) { break; };
        i = 0;
        while (i < batch) { ffree(ptrs[i]); i++; };
        total_freed = total_freed + batch;
    };

    check(ok, "2048 large blocks (8 batches of 256) allocated and freed\0");

    // One final alloc should succeed
    p = fmalloc((size_t)64);
    check(p != (u64)0, "alloc succeeds after table stress\0");
    ffree(p);
    return;
};

// =========================================================================
// Test 16: Double-free guard - ffree on already-freed ptr must not crash
// =========================================================================
def test_double_free_guard() -> void
{
    u64 p;

    print("-- double-free guard --\n\0");

    p = fmalloc((size_t)64);
    check(p != (u64)0, "alloc for double-free test\0");
    ffree(p);
    ffree(p);   // second free: entry has kind=BLOCK_BINNED; ffree sees
                // the entry still exists but the block is already in the bin.
                // The contract is: no crash, no memory corruption.
    check(true, "double-free does not crash\0");

    // Allocate again to confirm the allocator is still functional
    p = fmalloc((size_t)64);
    check(p != (u64)0, "alloc after double-free is functional\0");
    ffree(p);
    return;
};

// =========================================================================
// Test 17: Throughput - 1M x 64-byte fmalloc/ffree pairs
// =========================================================================
def test_throughput_small() -> void
{
    i64      t0, t1, ns, ms, us, mbs, mbs_frac, kb_per_s, us_elapsed;
    size_t   k, n;
    u64      p;
    bool     ok;
    byte[64] buf;

    print("-- throughput: 1M x 64-byte alloc+free pairs --\n\0");
    n  = (size_t)1000000;
    ok = true;
    k  = 0;

    t0 = time_now();
    while (k < n)
    {
        p = fmalloc((size_t)64);
        if (p == (u64)0) { ok = false; break; };
        ffree(p);
        k++;
    };
    t1 = time_now();
    check(ok, "1M alloc+free pairs all succeeded\0");

    ns          = t1 - t0;
    ms          = ns_to_ms(ns);
    us          = ns_to_us(ns) % 1000;
    us_elapsed  = ns / 1000;
    if (us_elapsed <= 0) { us_elapsed = 1; };
    kb_per_s    = ((i64)n * 64 * 1000) / us_elapsed;
    mbs         = kb_per_s / 1024;
    mbs_frac    = (kb_per_s % 1024) * 10 / 1024;

    print("  time:       \0");
    i64str(ms, @buf[0]); print(@buf[0]); print(".\0");
    if (us < 100) { print("0\0"); };
    if (us < 10)  { print("0\0"); };
    i64str(us, @buf[0]); print(@buf[0]); print(" ms\n\0");
    print("  throughput: \0");
    i64str(mbs, @buf[0]); print(@buf[0]); print(".\0");
    i64str(mbs_frac, @buf[0]); print(@buf[0]); print(" MB/s\n\0");
    return;
};

// =========================================================================
// Test 18: Throughput - 1M x mixed-size fmalloc/ffree pairs
// =========================================================================
def test_throughput_mixed() -> void
{
    PCG32    rng;
    i64      t0, t1, ns, ms, us, mbs, mbs_frac, kb_per_s, us_elapsed, total_bytes;
    size_t   k, n, sz;
    u64      p;
    bool     ok;
    byte[64] buf;
    u32      rval;
    u64      rval64;

    print("-- throughput: 1M mixed-size (1-4096 bytes) alloc+free pairs --\n\0");
    n  = (size_t)1000000;
    ok = true;
    k  = 0;
    total_bytes = 0;
    pcg32_init(@rng);

    t0 = time_now();
    while (k < n)
    {
        rval        = pcg32_next(@rng);
        rval64      = (u64)rval;
        sz          = (size_t)(rval64 % (u64)4096) + (size_t)1;
        p           = fmalloc(sz);
        if (p == (u64)0) { ok = false; break; };
        total_bytes = total_bytes + (i64)sz;
        ffree(p);
        k++;
    };
    t1 = time_now();
    check(ok, "1M mixed alloc+free pairs all succeeded\0");

    ns         = t1 - t0;
    ms         = ns_to_ms(ns);
    us         = ns_to_us(ns) % 1000;
    us_elapsed = ns / 1000;
    if (us_elapsed <= 0) { us_elapsed = 1; };
    kb_per_s   = (total_bytes * 1000) / us_elapsed;
    mbs        = kb_per_s / 1024;
    mbs_frac   = (kb_per_s % 1024) * 10 / 1024;

    print("  time:       \0");
    i64str(ms, @buf[0]); print(@buf[0]); print(".\0");
    if (us < 100) { print("0\0"); };
    if (us < 10)  { print("0\0"); };
    i64str(us, @buf[0]); print(@buf[0]); print(" ms\n\0");
    print("  throughput: \0");
    i64str(mbs, @buf[0]); print(@buf[0]); print(".\0");
    i64str(mbs_frac, @buf[0]); print(@buf[0]); print(" MB/s\n\0");
    return;
};

// =========================================================================
// Test 19: Throughput - fast-path sizes (32, 64, 128) after bin is warm
//          Measures the bin-reuse path exclusively.
// =========================================================================
def test_throughput_fastpath() -> void
{
    i64      t0, t1, ns, ms, us, mbs, mbs_frac, kb_per_s, us_elapsed;
    size_t   k, n;
    u64      p;
    bool     ok;
    byte[64] buf;

    print("-- throughput: fast-path bin reuse (1M x 64-byte, warm bin) --\n\0");
    n  = (size_t)1000000;
    ok = true;
    k  = 0;

    // Warm the bin: one alloc to ensure the free-list path is primed.
    p = fmalloc((size_t)64);
    ffree(p);

    t0 = time_now();
    while (k < n)
    {
        p = fmalloc((size_t)64);
        if (p == (u64)0) { ok = false; break; };
        ffree(p);
        k++;
    };
    t1 = time_now();
    check(ok, "1M fast-path bin-reuse cycles all succeeded\0");

    ns         = t1 - t0;
    ms         = ns_to_ms(ns);
    us         = ns_to_us(ns) % 1000;
    us_elapsed = ns / 1000;
    if (us_elapsed <= 0) { us_elapsed = 1; };
    kb_per_s   = ((i64)n * 64 * 1000) / us_elapsed;
    mbs        = kb_per_s / 1024;
    mbs_frac   = (kb_per_s % 1024) * 10 / 1024;

    print("  time:       \0");
    i64str(ms, @buf[0]); print(@buf[0]); print(".\0");
    if (us < 100) { print("0\0"); };
    if (us < 10)  { print("0\0"); };
    i64str(us, @buf[0]); print(@buf[0]); print(" ms\n\0");
    print("  throughput: \0");
    i64str(mbs, @buf[0]); print(@buf[0]); print(".\0");
    i64str(mbs_frac, @buf[0]); print(@buf[0]); print(" MB/s\n\0");
    return;
};

// =========================================================================
// Test 20: frealloc pressure - 1000 cycles of grow/shrink on a live block
// =========================================================================
def test_frealloc_pressure() -> void
{
    PCG32    rng;
    u64      ptr;
    size_t   i, n, sz, prev_sz, copy_sz;
    bool     ok;
    byte*    bp;
    size_t   j;
    u32      rval;
    u64      rval64;

    print("-- frealloc pressure (1000 random grow/shrink cycles) --\n\0");
    pcg32_init(@rng);

    n       = (size_t)1000;
    ptr     = fmalloc((size_t)64);
    prev_sz = (size_t)64;
    ok      = true;

    check(ptr != (u64)0, "initial alloc for frealloc pressure\0");

    // Stamp known pattern
    bp = (byte*)ptr;
    j  = 0;
    while (j < prev_sz) { bp[j] = (byte)0x5A; j++; };

    while (i < n)
    {
        rval   = pcg32_next(@rng);
        rval64 = (u64)rval;
        sz     = (size_t)(rval64 % (u64)8192) + (size_t)1;

        copy_sz = prev_sz;
        if (sz < copy_sz) { copy_sz = sz; };

        u64 new_ptr = frealloc(ptr, sz);
        if (new_ptr == (u64)0) { ok = false; break; };

        // Verify preserved bytes
        bp = (byte*)new_ptr;
        j  = 0;
        while (j < copy_sz)
        {
            if (bp[j] != (byte)0x5A) { ok = false; break; };
            j++;
        };
        if (!ok) { break; };

        // Re-stamp full new block
        j = 0;
        while (j < sz) { bp[j] = (byte)0x5A; j++; };

        ptr     = new_ptr;
        prev_sz = sz;
        i++;
    };
    check(ok, "1000 frealloc grow/shrink cycles: data always preserved\0");
    ffree(ptr);
    return;
};

// =========================================================================
// Test 21: Slab exhaustion then recovery - fill multiple slabs, free all,
//          coalesce, then confirm allocator is fully functional
// =========================================================================
def test_slab_exhaustion_recovery() -> void
{
    // Allocate small blocks to exhaust the first slab (4 MB default),
    // spill into a second slab, then free everything and coalesce.
    size_t   batch, i, total, freed;
    u64[256] ptrs;
    bool     ok;
    u64      p;

    print("-- slab exhaustion and recovery --\n\0");

    batch = (size_t)256;
    total = (size_t)0;
    ok    = true;

    // Fill ~6 MB worth of 16-byte blocks (class 0):
    // 6MB / 16 bytes = 393216 blocks, batched in groups of 256 to stay on stack.
    size_t target = (size_t)393216;
    while (total < target & ok)
    {
        i = 0;
        while (i < batch & total < target)
        {
            ptrs[i] = fmalloc((size_t)16);
            if (ptrs[i] == (u64)0) { ok = false; break; };
            i++;
            total++;
        };
        // Free this batch immediately to keep stack-local ptrs valid.
        size_t freed_batch = i;
        i = 0;
        while (i < freed_batch) { ffree(ptrs[i]); i++; };
    };
    check(ok,        "6MB slab exhaustion: all allocs succeeded\0");

    coalesce_heap();
    check(true,      "coalesce after exhaustion: no crash\0");

    p = fmalloc((size_t)64);
    check(p != (u64)0, "alloc after exhaustion+coalesce succeeds\0");
    ffree(p);
    return;
};

// =========================================================================
// main
// =========================================================================
def main() -> int
{
    byte[32] buf;

    print("=== stdheap stress test ===\n\n\0");

    test_edge_cases();
    test_all_size_classes();
    test_large_alloc();
    test_bin_reuse();
    test_write_read();
    test_no_overlap();
    test_frealloc_same_class();
    test_frealloc_grow();
    test_frealloc_large_identity();
    test_frealloc_chain();
    test_coalesce();
    test_coalesce_bin_integrity();
    test_fragmentation();
    test_mixed_pattern();
    test_table_stress();
    test_double_free_guard();
    test_throughput_small();
    test_throughput_mixed();
    test_throughput_fastpath();
    test_frealloc_pressure();
    test_slab_exhaustion_recovery();

    print("\n\0");
    i32str(g_pass, @buf[0]); print(@buf[0]); print(" passed, \0");
    i32str(g_fail, @buf[0]); print(@buf[0]); print(" failed\n\0");

    return g_fail;
};
