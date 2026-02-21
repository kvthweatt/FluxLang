#import "standard.fx", "redallocators.fx";

using standard::memory::allocators::stdheap;

// ============================================================================
// Helpers
// ============================================================================

def print_pass(byte* msg) -> void
{
    print("[PASS] \0");
    print(msg);
    print("\n\0");
    return;
};

def print_fail(byte* msg) -> void
{
    print("[FAIL] \0");
    print(msg);
    print("\n\0");
    return;
};

// ============================================================================
// TEST 1: basic alloc/free of each small size class
// ============================================================================

def test_size_classes() -> void
{
    print("--- test_size_classes ---\n\0");

    // Sizes that land in classes 0-8: 16, 32, 64, 128, 256, 512, 1024, 2048, 4096
    u64 p0  = fmalloc((u64)16);
    u64 p1  = fmalloc((u64)32);
    u64 p2  = fmalloc((u64)64);
    u64 p3  = fmalloc((u64)128);
    u64 p4  = fmalloc((u64)256);
    u64 p5  = fmalloc((u64)512);
    u64 p6  = fmalloc((u64)1024);
    u64 p7  = fmalloc((u64)2048);
    u64 p8  = fmalloc((u64)4096);

    bool ok = p0 != (u64)0 & p1 != (u64)0 & p2 != (u64)0 &
              p3 != (u64)0 & p4 != (u64)0 & p5 != (u64)0 &
              p6 != (u64)0 & p7 != (u64)0 & p8 != (u64)0;

    if (ok) { print_pass("alloc one block per size class\0"); }
    else    { print_fail("alloc one block per size class\0"); };

    ffree(p0);
    ffree(p1);
    ffree(p2);
    ffree(p3);
    ffree(p4);
    ffree(p5);
    ffree(p6);
    ffree(p7);
    ffree(p8);

    print_pass("free one block per size class\0");
    return;
};

// ============================================================================
// TEST 2: many small allocs then free all (same pattern as graph_demo)
// ============================================================================

def test_many_small() -> void
{
    print("--- test_many_small ---\n\0");

    u64 p0 = fmalloc((u64)256);
    print("alloc p0 done\n\0");
    u64 p1 = fmalloc((u64)256);
    print("alloc p1 done\n\0");
    u64 p2 = fmalloc((u64)256);
    print("alloc p2 done\n\0");
    u64 p3 = fmalloc((u64)256);
    print("alloc p3 done\n\0");
    u64 p4 = fmalloc((u64)256);
    print("alloc p4 done\n\0");
    u64 p5 = fmalloc((u64)256);
    print("alloc p5 done\n\0");
    u64 p6 = fmalloc((u64)256);
    print("alloc p6 done\n\0");
    u64 p7 = fmalloc((u64)256);
    print("alloc p7 done\n\0");

    print("writing p0...\n\0");
    byte* b = (byte*)p0;
    int j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };
    print("writing p1...\n\0");
    b = (byte*)p1;
    j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };
    print("writing p2...\n\0");
    b = (byte*)p2;
    j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };
    print("writing p3...\n\0");
    b = (byte*)p3;
    j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };
    print("writing p4...\n\0");
    b = (byte*)p4;
    j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };
    print("writing p5...\n\0");
    b = (byte*)p5;
    j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };
    print("writing p6...\n\0");
    b = (byte*)p6;
    j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };
    print("writing p7...\n\0");
    b = (byte*)p7;
    j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };

    print("freeing p0...\n\0");
    ffree(p0);
    print("freeing p1...\n\0");
    ffree(p1);
    print("freeing p2...\n\0");
    ffree(p2);
    print("freeing p3...\n\0");
    ffree(p3);
    print("freeing p4...\n\0");
    ffree(p4);
    print("freeing p5...\n\0");
    ffree(p5);
    print("freeing p6...\n\0");
    ffree(p6);
    print("freeing p7...\n\0");
    ffree(p7);

    print_pass("alloc 8x256 bytes, dirty, free all\0");
    return;
};

// ============================================================================
// TEST 3: alloc, free, realloc from bin - verify pointer comes from bin
// ============================================================================

def test_bin_reuse() -> void
{
    print("--- test_bin_reuse ---\n\0");

    u64 p1 = fmalloc((u64)64);
    ffree(p1);

    // Should get the same block back from the free bin
    u64 p2 = fmalloc((u64)64);

    if (p2 == p1) { print_pass("bin reuse returns same pointer\0"); }
    else          { print_fail("bin reuse returned different pointer\0"); };

    ffree(p2);
    return;
};

// ============================================================================
// TEST 4: large block (>4096) alloc/free
// ============================================================================

def test_large() -> void
{
    print("--- test_large ---\n\0");

    u64 p = fmalloc((u64)8192);

    if (p != (u64)0) { print_pass("large alloc succeeded\0"); }
    else             { print_fail("large alloc returned null\0"); };

    // Write to it
    byte* b = (byte*)p;
    int i = 0;
    while (i < 8192)
    {
        b[i] = (byte)i;
        i = i + 1;
    };

    ffree(p);
    print_pass("large free succeeded\0");
    return;
};

// ============================================================================
// TEST 5: mixed small sizes, same as graph_demo allocation pattern exactly
// ============================================================================

def test_graph_demo_pattern() -> void
{
    print("--- test_graph_demo_pattern ---\n\0");

    // Mirrors graph_demo exactly:
    //   4x fmalloc(256)  -> class 4
    //   2x fmalloc(48)   -> class 2
    //   2x fmalloc(40)   -> class 2
    u64 xs1 = fmalloc((u64)256);
    u64 ys1 = fmalloc((u64)256);
    u64 xs2 = fmalloc((u64)256);
    u64 ys2 = fmalloc((u64)256);
    u64 xs3 = fmalloc((u64)48);
    u64 ys3 = fmalloc((u64)48);
    u64 xs4 = fmalloc((u64)40);
    u64 ys4 = fmalloc((u64)40);

    bool ok = xs1 != (u64)0 & ys1 != (u64)0 & xs2 != (u64)0 & ys2 != (u64)0 &
              xs3 != (u64)0 & ys3 != (u64)0 & xs4 != (u64)0 & ys4 != (u64)0;

    if (ok) { print_pass("graph_demo pattern: all allocs non-null\0"); }
    else    { print_fail("graph_demo pattern: a null was returned\0"); };

    // Write floats into every block, dirtying the slab header overlap region too
    float* f;

    f = (float*)xs1;
    int i = 0;
    while (i < 64) { f[i] = 1.23; i = i + 1; };

    f = (float*)ys1;
    i = 0;
    while (i < 64) { f[i] = 4.56; i = i + 1; };

    f = (float*)xs2;
    i = 0;
    while (i < 64) { f[i] = 7.89; i = i + 1; };

    f = (float*)ys2;
    i = 0;
    while (i < 64) { f[i] = 0.12; i = i + 1; };

    // Now free all, same order as graph_demo
    print("freeing xs1...\n\0");
    ffree(xs1);
    print("freeing ys1...\n\0");
    ffree(ys1);
    print("freeing xs2...\n\0");
    ffree(xs2);
    print("freeing ys2...\n\0");
    ffree(ys2);
    print("freeing xs3...\n\0");
    ffree(xs3);
    print("freeing ys3...\n\0");
    ffree(ys3);
    print("freeing xs4...\n\0");
    ffree(xs4);
    print("freeing ys4...\n\0");
    ffree(ys4);

    print_pass("graph_demo pattern: all frees completed\0");
    return;
};

// ============================================================================
// TEST 6: double-free safety (should not crash, just silently skip)
// ============================================================================

def test_double_free() -> void
{
    print("--- test_double_free ---\n\0");

    u64 p = fmalloc((u64)64);
    ffree(p);
    ffree(p);  // second free: table_find returns null, should return early

    print_pass("double free did not crash\0");
    return;
};

// ============================================================================
// TEST 7: null free (no-op)
// ============================================================================

def test_null_free() -> void
{
    print("--- test_null_free ---\n\0");
    ffree((u64)0);
    print_pass("null free did not crash\0");
    return;
};

// ============================================================================
// TEST 8: many alloc/free cycles to stress the bin and table
// ============================================================================

def test_stress() -> void
{
    print("--- test_stress ---\n\0");

    const int ROUNDS = 32;
    u64[16] ptrs;
    const int NPTRS = 16;

    int r = 0;
    while (r < ROUNDS)
    {
        int i = 0;
        while (i < NPTRS)
        {
            ptrs[i] = fmalloc((u64)256);
            i = i + 1;
        };

        // Dirty first 8 bytes of each (writes into bin's next pointer region)
        i = 0;
        while (i < NPTRS)
        {
            byte* b = (byte*)ptrs[i];
            b[0] = (byte)r;
            b[1] = (byte)i;
            i = i + 1;
        };

        i = 0;
        while (i < NPTRS)
        {
            ffree(ptrs[i]);
            i = i + 1;
        };

        r = r + 1;
    };

    print_pass("stress: 32 rounds of 16 alloc/dirty/free\0");
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    print("=== heap allocator tests ===\n\0");

    test_size_classes();
    test_many_small();
    test_bin_reuse();
    test_large();
    test_graph_demo_pattern();
    test_double_free();
    test_null_free();
    test_stress();

    print("=== done ===\n\0");
    return 0;
};
