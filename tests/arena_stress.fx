// Author: Karac V. Thweatt
// arena_stress.fx - Stress test for standard::memory::allocators::stdarena

#import "standard.fx", "allocators.fx", "random.fx", "timing.fx";

using standard::io::console,
      standard::strings,
      standard::time,
      standard::random,
      standard::memory::allocators::stdarena,
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

// =========================================================================
// Test 1: Basic alloc and alignment
// =========================================================================
def test_basic_alloc() -> void
{
    Arena  a;
    void*  p1, p2, p3;
    size_t u1, u2;

    print("-- basic alloc & alignment --\n\0");
    arena_init(@a);

    p1 = alloc(@a, (size_t)1);
    check((u64)p1 != 0,                "alloc(1) non-null\0");
    check(((u64)p1 & (u64)7) == 0,     "alloc(1) 8-byte aligned\0");

    p2 = alloc(@a, (size_t)1);
    check((u64)p2 != 0,                "alloc(1) second non-null\0");
    check(((u64)p2 & (u64)7) == 0,     "alloc(1) second 8-byte aligned\0");
    check((u64)p2 > (u64)p1,           "sequential allocs advance\0");
    check((u64)p2 - (u64)p1 == (u64)8, "1-byte alloc padded to 8\0");

    p3 = alloc(@a, (size_t)64);
    check((u64)p3 != 0,                "alloc(64) non-null\0");
    check(((u64)p3 & (u64)7) == 0,     "alloc(64) 8-byte aligned\0");

    u1 = arena_used(@a);
    check(u1 == (size_t)80,            "used = 8+8+64 = 80\0");

    arena_destroy(@a);
    u2 = arena_used(@a);
    check(u2 == (size_t)0,             "used = 0 after destroy\0");
    check((u64)a.head == 0,            "head = null after destroy\0");
    return;
};

// =========================================================================
// Test 2: alloc_zero produces zeroed memory
// =========================================================================
def test_alloc_zero() -> void
{
    Arena  a;
    byte*  p;
    size_t i;
    bool   all_zero;

    print("-- alloc_zero --\n\0");
    arena_init(@a);

    p = (byte*)alloc_zero(@a, (size_t)256);
    check((u64)p != 0, "alloc_zero(256) non-null\0");

    all_zero = true;
    while (i < (size_t)256)
    {
        if (p[i] != (byte)0) { all_zero = false; break; };
        i++;
    };
    check(all_zero, "alloc_zero(256) all bytes zero\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 3: alloc_str copies string correctly
// =========================================================================
def test_alloc_str() -> void
{
    Arena a;
    byte* s1, s2, s3;

    print("-- alloc_str --\n\0");
    arena_init(@a);

    s1 = alloc_str(@a, "hello\0");
    check((u64)s1 != 0,              "alloc_str non-null\0");
    check(strcmp(s1, "hello\0") == 0, "alloc_str value correct\0");

    s2 = alloc_str(@a, "world\0");
    check(strcmp(s2, "world\0") == 0, "alloc_str second value\0");
    check((u64)s2 > (u64)s1,         "alloc_str advances pointer\0");

    s3 = alloc_str(@a, "\0");
    check((u64)s3 != 0,              "alloc_str empty non-null\0");
    check(s3[0] == (byte)0,          "alloc_str empty null terminator\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 4: alloc_copy copies bytes correctly
// =========================================================================
def test_alloc_copy() -> void
{
    Arena    a;
    byte[16] src;
    byte*    dst;
    size_t   i;
    bool     match;

    print("-- alloc_copy --\n\0");
    arena_init(@a);

    while (i < (size_t)16) { src[i] = (byte)(i + 1); i++; };

    dst = (byte*)alloc_copy(@a, (void*)@src[0], (size_t)16);
    check((u64)dst != 0, "alloc_copy non-null\0");

    match = true;
    i = 0;
    while (i < (size_t)16)
    {
        if (dst[i] != src[i]) { match = false; break; };
        i++;
    };
    check(match, "alloc_copy bytes match\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 5: Chunk overflow - force multiple chunks
// =========================================================================
def test_chunk_overflow() -> void
{
    Arena       a;
    size_t      i, chunks_after;
    void*       p;
    ArenaChunk* c;

    print("-- chunk overflow --\n\0");
    arena_init_sized(@a, (size_t)288);

    while (i < (size_t)8)
    {
        p = alloc(@a, (size_t)32);
        check((u64)p != 0, "alloc in chunk 1 non-null\0");
        i++;
    };
    p = alloc(@a, (size_t)32);
    check((u64)p != 0,            "alloc after overflow non-null\0");
    check(((u64)p & (u64)7) == 0, "alloc after overflow aligned\0");

    c = a.head;
    chunks_after = 0;
    while ((u64)c != 0) { chunks_after++; c = c.next; };
    check(chunks_after >= (size_t)2, "at least 2 chunks after overflow\0");

    arena_destroy(@a);
    check((u64)a.head == 0, "head null after destroy\0");
    return;
};

// =========================================================================
// Test 6: mark / rewind
// =========================================================================
def test_mark_rewind() -> void
{
    Arena       a;
    ArenaMark   m;
    void*       p;
    ArenaChunk* c;
    size_t      chunks_at_mark, chunks_after_rewind;

    print("-- mark / rewind --\n\0");
    arena_init_sized(@a, (size_t)160);

    p = alloc(@a, (size_t)64);
    check((u64)p != 0, "baseline alloc non-null\0");

    m = arena_mark(@a);

    p = alloc(@a, (size_t)64);
    p = alloc(@a, (size_t)64);
    p = alloc(@a, (size_t)64);
    check((u64)p != 0, "alloc after mark non-null\0");

    c = a.head;
    chunks_at_mark = 0;
    while ((u64)c != 0) { chunks_at_mark++; c = c.next; };

    arena_rewind(@a, @m);

    c = a.head;
    chunks_after_rewind = 0;
    while ((u64)c != 0) { chunks_after_rewind++; c = c.next; };

    check(chunks_after_rewind <= chunks_at_mark, "rewind freed excess chunks\0");
    check((u64)a.head == (u64)m.chunk,           "head restored to mark chunk\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 7: reset keeps memory, reuses it
// =========================================================================
def test_reset() -> void
{
    Arena       a;
    void*       p1, p2;
    size_t      committed_before, committed_after;
    ArenaChunk* head_before;

    print("-- reset --\n\0");
    arena_init(@a);

    p1               = alloc(@a, (size_t)512);
    head_before      = a.head;
    committed_before = arena_committed(@a);

    arena_reset(@a);
    check(arena_used(@a) == (size_t)0,         "used = 0 after reset\0");
    check((u64)a.head == (u64)head_before,     "head unchanged after reset\0");
    committed_after = arena_committed(@a);
    check(committed_after == committed_before, "committed unchanged after reset\0");

    p2 = alloc(@a, (size_t)512);
    check((u64)p2 != 0,       "alloc after reset non-null\0");
    check((u64)p2 == (u64)p1, "alloc after reset reuses same address\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 8: Write/read correctness under many random-sized allocs
// =========================================================================
def test_write_read() -> void
{
    Arena  a;
    PCG32  rng;
    size_t i, j, n, sz;
    bool   ok;
    byte*  p;
    byte   tag;
    u32    rval;
    u64    rval64;

    print("-- write/read correctness (10000 allocs) --\n\0");
    arena_init(@a);
    pcg32_init(@rng);

    n  = (size_t)10000;
    ok = true;
    while (i < n)
    {
        rval   = pcg32_next(@rng);
        rval64 = (u64)rval;
        sz     = (size_t)(rval64 % (u64)256) + (size_t)1;
        tag    = (byte)(i & 0xFF);
        p      = (byte*)alloc(@a, sz);
        if ((u64)p == 0) { ok = false; break; };
        j = 0;
        while (j < sz) { p[j] = tag; j++; };
        j = 0;
        while (j < sz)
        {
            if (p[j] != tag) { ok = false; break; };
            j++;
        };
        if (!ok) { break; };
        i++;
    };
    check(ok, "write/read correct across 10000 random-sized allocs\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 9: Oversized single alloc (forces dedicated large chunk)
// =========================================================================
def test_large_alloc() -> void
{
    Arena  a;
    byte*  p;
    size_t i;
    bool   ok;

    print("-- large single alloc (8 MB) --\n\0");
    arena_init(@a);

    p = (byte*)alloc(@a, (size_t)8388608);
    check((u64)p != 0,            "alloc(8MB) non-null\0");
    check(((u64)p & (u64)7) == 0, "alloc(8MB) aligned\0");

    ok = true;
    while (i < (size_t)8388608) { p[i] = (byte)0xAB; i++; };
    i = 0;
    while (i < (size_t)8388608)
    {
        if (p[i] != (byte)0xAB) { ok = false; break; };
        i++;
    };
    check(ok, "alloc(8MB) write/read correct\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 10: Throughput - 1 million small allocs
// =========================================================================
def test_throughput() -> void
{
    Arena    a;
    i64      t0, t1, ns, ms, us, mbs, mbs_frac, kb_per_s, bytes_total, us_elapsed;
    size_t   i, n;
    void*    p;
    bool     ok;
    byte[64] buf;

    print("-- throughput: 1M x 64-byte allocs --\n\0");
    n = (size_t)1000000;
    arena_init(@a);

    t0 = time_now();
    ok = true;
    while (i < n)
    {
        p = alloc(@a, (size_t)64);
        if ((u64)p == 0) { ok = false; break; };
        i++;
    };
    t1 = time_now();
    check(ok, "1M allocs all succeeded\0");

    ns          = t1 - t0;
    ms          = ns_to_ms(ns);
    us          = ns_to_us(ns) % 1000;
    bytes_total = (i64)n * (i64)64;
    us_elapsed  = ns / 1000;
    if (us_elapsed <= 0) { us_elapsed = 1; };
    kb_per_s    = (bytes_total * 1000) / us_elapsed;
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
    print("  committed:  \0"); print_mb(arena_committed(@a)); print("\n\0");
    print("  used:       \0"); print_mb(arena_used(@a));      print("\n\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 11: Throughput - 1 million mixed-size allocs
// =========================================================================
def test_throughput_mixed() -> void
{
    Arena    a;
    PCG32    rng;
    i64      t0, t1, ns, ms, us, mbs, mbs_frac, kb_per_s, us_elapsed, total_bytes;
    size_t   i, n, sz;
    void*    p;
    bool     ok;
    byte[64] buf;
    u32      rval;
    u64      rval64;

    print("-- throughput: 1M mixed-size allocs (1-512 bytes) --\n\0");
    n = (size_t)1000000;
    arena_init(@a);
    pcg32_init(@rng);

    t0          = time_now();
    ok          = true;
    total_bytes = 0;
    while (i < n)
    {
        rval        = pcg32_next(@rng);
        rval64      = (u64)rval;
        sz          = (size_t)(rval64 % (u64)512) + (size_t)1;
        p           = alloc(@a, sz);
        if ((u64)p == 0) { ok = false; break; };
        total_bytes = total_bytes + (i64)sz;
        i++;
    };
    t1 = time_now();
    check(ok, "1M mixed allocs all succeeded\0");

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
    print("  committed:  \0"); print_mb(arena_committed(@a)); print("\n\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 12: mark/rewind cycle correctness under pressure
// =========================================================================
def test_mark_rewind_pressure() -> void
{
    Arena     a;
    ArenaMark m;
    PCG32     rng;
    size_t    i, j, n, sz;
    void*     p, tmp;
    bool      ok;
    u32       rval;
    u64       rval64;

    print("-- mark/rewind pressure (1000 cycles) --\n\0");
    arena_init(@a);
    pcg32_init(@rng);

    p = alloc(@a, (size_t)1048576);
    check((u64)p != 0, "baseline 1MB alloc\0");

    n  = (size_t)1000;
    ok = true;
    while (i < n)
    {
        m = arena_mark(@a);
        j = 0;
        while (j < (size_t)100)
        {
            rval   = pcg32_next(@rng);
            rval64 = (u64)rval;
            sz     = (size_t)(rval64 % (u64)4096) + (size_t)1;
            tmp    = alloc(@a, sz);
            if ((u64)tmp == 0) { ok = false; break; };
            j++;
        };
        arena_rewind(@a, @m);
        if ((u64)a.head != (u64)m.chunk) { ok = false; break; };
        i++;
    };
    check(ok, "1000 mark/rewind cycles correct\0");

    arena_destroy(@a);
    return;
};

// =========================================================================
// Test 13: arena_committed tracks chunk bytes
// =========================================================================
def test_committed() -> void
{
    Arena  a;
    size_t c0, c1, c2;

    print("-- arena_committed --\n\0");
    arena_init(@a);

    c0 = arena_committed(@a);
    check(c0 == (size_t)0, "committed = 0 before first alloc\0");

    alloc(@a, (size_t)1);
    c1 = arena_committed(@a);
    check(c1 > (size_t)0, "committed > 0 after first alloc\0");

    alloc(@a, c1 + (size_t)1);
    c2 = arena_committed(@a);
    check(c2 > c1, "committed grows with new chunk\0");

    arena_reset(@a);
    check(arena_committed(@a) == c2, "committed unchanged by reset\0");

    arena_destroy(@a);
    check(arena_committed(@a) == (size_t)0, "committed = 0 after destroy\0");
    return;
};

// =========================================================================
// main
// =========================================================================
def main() -> int
{
    byte[32] buf;

    print("=== stdarena stress test ===\n\n\0");

    test_basic_alloc();
    test_alloc_zero();
    test_alloc_str();
    test_alloc_copy();
    test_chunk_overflow();
    test_mark_rewind();
    test_reset();
    test_write_read();
    test_large_alloc();
    test_throughput();
    test_throughput_mixed();
    test_mark_rewind_pressure();
    test_committed();

    print("\n\0");
    i32str(g_pass, @buf[0]); print(@buf[0]); print(" passed, \0");
    i32str(g_fail, @buf[0]); print(@buf[0]); print(" failed\n\0");

    return g_fail;
};
