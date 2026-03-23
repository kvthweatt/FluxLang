#import "standard.fx", "redallocators.fx";

using standard::memory::allocators::stdstack,
      standard::io::console;

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
// TEST 1: basic alloc from a fresh stack, verify pointer is non-null
// ============================================================================

def test_basic_alloc() -> void
{
    print("--- test_basic_alloc ---\n\0");

    StackAllocator sa((size_t)4096);

    void_ptr p0 = sa.allocate((size_t)16);
    void_ptr p1 = sa.allocate((size_t)32);
    void_ptr p2 = sa.allocate((size_t)64);
    void_ptr p3 = sa.allocate((size_t)128);

    bool ok = p0 != 0 & p1 != 0 &
              p2 != 0 & p3 != 0;

    if (ok) { print_pass("basic alloc: all pointers non-null\0"); }
    else    { print_fail("basic alloc: null pointer returned\0"); };

    sa.__exit();
    return;
};

// ============================================================================
// TEST 2: pointers are sequential (bump allocator advances linearly)
// ============================================================================

def test_sequential_ptrs() -> void
{
    print("--- test_sequential_ptrs ---\n\0");

    StackAllocator sa((size_t)4096);

    void_ptr p0 = sa.allocate((size_t)64);
    void_ptr p1 = sa.allocate((size_t)64);
    void_ptr p2 = sa.allocate((size_t)64);

    // Each allocation must be exactly 64 bytes ahead of the last
    u64 a0 = (u64)p0;
    u64 a1 = (u64)p1;
    u64 a2 = (u64)p2;

    bool ok = (a1 - a0) == (u64)64 & (a2 - a1) == (u64)64;

    if (ok) { print_pass("sequential: pointers advance by alloc size\0"); }
    else    { print_fail("sequential: unexpected pointer gap\0"); };

    sa.__exit();
    return;
};

// ============================================================================
// TEST 3: get_used / get_available / get_capacity reflect alloc state
// ============================================================================

def test_bookkeeping() -> void
{
    print("--- test_bookkeeping ---\n\0");

    StackAllocator sa((size_t)1024);

    bool ok = sa.get_used() == (size_t)0 &
              sa.get_available() == (size_t)1024 &
              sa.get_capacity() == (size_t)1024;

    if (ok) { print_pass("bookkeeping: fresh state correct\0"); }
    else    { print_fail("bookkeeping: fresh state wrong\0"); };

    sa.allocate((size_t)256);

    ok = sa.get_used() == (size_t)256 &
         sa.get_available() == (size_t)768 &
         sa.get_capacity() == (size_t)1024;

    if (ok) { print_pass("bookkeeping: after 256-byte alloc correct\0"); }
    else    { print_fail("bookkeeping: after 256-byte alloc wrong\0"); };

    sa.allocate((size_t)512);

    ok = sa.get_used() == (size_t)768 &
         sa.get_available() == (size_t)256 &
         sa.get_capacity() == (size_t)1024;

    if (ok) { print_pass("bookkeeping: after 512-byte alloc correct\0"); }
    else    { print_fail("bookkeeping: after 512-byte alloc wrong\0"); };

    sa.__exit();
    return;
};

// ============================================================================
// TEST 4: exhaustion returns null
// ============================================================================

def test_exhaustion() -> void
{
    print("--- test_exhaustion ---\n\0");

    StackAllocator sa((size_t)128);

    void_ptr p0 = sa.allocate((size_t)64);
    void_ptr p1 = sa.allocate((size_t)64);
    // Buffer is now full
    void_ptr p2 = sa.allocate((size_t)1);

    bool ok = p0 != 0 & p1 != 0 & p2 == 0;

    if (ok) { print_pass("exhaustion: overflow returns null\0"); }
    else    { print_fail("exhaustion: overflow did not return null\0"); };

    sa.__exit();
    return;
};

// ============================================================================
// TEST 5: reset reclaims the entire buffer
// ============================================================================

def test_reset() -> void
{
    print("--- test_reset ---\n\0");

    StackAllocator sa((size_t)256);

    void_ptr p0 = sa.allocate((size_t)256);

    // Exhausted — next alloc must fail
    void_ptr should_null = sa.allocate((size_t)1);

    if (should_null != 0)
    {
        print_fail("reset: expected null before reset\0");
        sa.__exit();
        return;
    };

    sa.reset();

    bool ok_state = sa.get_used() == (size_t)0 &
                    sa.get_available() == (size_t)256;

    if (ok_state) { print_pass("reset: offset returns to zero\0"); }
    else          { print_fail("reset: offset not zero after reset\0"); };

    // Should be able to allocate from the start again
    void_ptr p1 = sa.allocate((size_t)256);

    bool ok_ptr = p1 != 0 & (u64)p1 == (u64)p0;

    if (ok_ptr) { print_pass("reset: realloc returns same base pointer\0"); }
    else        { print_fail("reset: realloc returned unexpected pointer\0"); };

    sa.__exit();
    return;
};

// ============================================================================
// TEST 6: write and read back data through the stack allocator
// ============================================================================

def test_write_read() -> void
{
    print("--- test_write_read ---\n\0");

    StackAllocator sa((size_t)2048);

    void_ptr p = sa.allocate((size_t)256);

    if (p == 0)
    {
        print_fail("write_read: alloc returned null\0");
        sa.__exit();
        return;
    };

    byte* b = (byte*)p;
    int j = 0;
    while (j < 256) { b[j] = (byte)j; j = j + 1; };

    bool ok = true;
    j = 0;
    while (j < 256)
    {
        if (b[j] != (byte)j) { ok = false; };
        j = j + 1;
    };

    if (ok) { print_pass("write_read: data round-trips correctly\0"); }
    else    { print_fail("write_read: data mismatch\0"); };

    sa.__exit();
    return;
};

// ============================================================================
// TEST 7: multiple regions do not overlap
// ============================================================================

def test_no_overlap() -> void
{
    print("--- test_no_overlap ---\n\0");

    StackAllocator sa((size_t)8192);

    void_ptr p0 = sa.allocate((size_t)256);
    void_ptr p1 = sa.allocate((size_t)256);
    void_ptr p2 = sa.allocate((size_t)256);
    void_ptr p3 = sa.allocate((size_t)256);

    byte* b0 = (byte*)p0;
    byte* b1 = (byte*)p1;
    byte* b2 = (byte*)p2;
    byte* b3 = (byte*)p3;

    // Write distinct sentinel bytes into each region
    int j = 0;
    while (j < 256) { b0[j] = (byte)0xAA; j = j + 1; };
    j = 0;
    while (j < 256) { b1[j] = (byte)0xBB; j = j + 1; };
    j = 0;
    while (j < 256) { b2[j] = (byte)0xCC; j = j + 1; };
    j = 0;
    while (j < 256) { b3[j] = (byte)0xDD; j = j + 1; };

    // Verify none of the writes bled into neighbouring regions
    bool ok = true;
    j = 0;
    while (j < 256) { if (b0[j] != (byte)0xAA) { ok = false; }; j = j + 1; };
    j = 0;
    while (j < 256) { if (b1[j] != (byte)0xBB) { ok = false; }; j = j + 1; };
    j = 0;
    while (j < 256) { if (b2[j] != (byte)0xCC) { ok = false; }; j = j + 1; };
    j = 0;
    while (j < 256) { if (b3[j] != (byte)0xDD) { ok = false; }; j = j + 1; };

    if (ok) { print_pass("no_overlap: regions are disjoint\0"); }
    else    { print_fail("no_overlap: region data corrupted\0"); };

    sa.__exit();
    return;
};

// ============================================================================
// TEST 8: reset and refill stress (many cycles)
// ============================================================================

def test_reset_stress() -> void
{
    print("--- test_reset_stress ---\n\0");

    const int ROUNDS = 32;
    const int NALLOCS = 8;

    StackAllocator sa((size_t)4096);

    bool ok = true;
    int r = 0;
    while (r < ROUNDS)
    {
        sa.reset();

        int i = 0;
        while (i < NALLOCS)
        {
            void_ptr p = sa.allocate((size_t)256);
            if (p == 0) { ok = false; };

            // Dirty both ends of each region
            byte* b = (byte*)p;
            b[0]   = (byte)r;
            b[255] = (byte)i;

            i = i + 1;
        };

        r = r + 1;
    };

    if (ok) { print_pass("reset_stress: 32 rounds of 8 allocs all non-null\0"); }
    else    { print_fail("reset_stress: null pointer in stress loop\0"); };

    sa.__exit();
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    print("=== stack allocator tests ===\n\0");

    test_basic_alloc();
    test_sequential_ptrs();
    test_bookkeeping();
    test_exhaustion();
    test_reset();
    test_write_read();
    test_no_overlap();
    test_reset_stress();

    print("=== done ===\n\0");
    return 0;
};
