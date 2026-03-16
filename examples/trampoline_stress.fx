// trampoline_stress.fx
//
// Stress test for the Flux bytecode trampoline mechanism.
//
// Tests exercised:
//
//   1. Rapid retargeting      - patch the same stub thousands of times in a
//                               tight loop, verifying the return value each
//                               call so a stale patch is immediately caught.
//
//   2. Multi-stub independence - allocate N separate stubs simultaneously and
//                               confirm each fires its own target without
//                               cross-contamination.
//
//   3. Round-robin churn       - cycle through all targets in order across a
//                               large number of iterations; validates that
//                               repeated patch → call → verify is stable.
//
//   4. Accumulator chain       - feed the output of one trampoline call as
//                               the input of the next, building a running
//                               value that would diverge immediately if any
//                               dispatch misfired.
//
//   5. Re-entrant stub reuse   - free a stub page and reallocate it, write a
//                               fresh template, and confirm the new stub works
//                               correctly after the old one is gone.

#import "standard.fx";

using standard::io::console;

// ============================================================================
// Win32 memory primitives
// ============================================================================

extern
{
    def !!
        VirtualAlloc(ulong, size_t, u32, u32)  -> ulong,
        VirtualFree(ulong, size_t, u32)        -> bool,
        VirtualProtect(ulong, size_t, u32, u32*) -> bool;
};

// ============================================================================
// Target functions
// ============================================================================

def op_double(ulong x)  -> ulong { return x * (ulong)2;       };
def op_add100(ulong x)  -> ulong { return x + (ulong)100;     };
def op_square(ulong x)  -> ulong { return x * x;              };
def op_sub7(ulong x)    -> ulong { return x - (ulong)7;       };
def op_xor(ulong x)     -> ulong { return x xor (ulong)0xDEAD;  };
def op_identity(ulong x)-> ulong { return x;                  };

// ============================================================================
// Stub helpers  (identical to trampoline.fx)
// ============================================================================

def alloc_stub_page() -> ulong
{
    ulong page = VirtualAlloc((ulong)0, (size_t)4096, (u32)0x3000, (u32)0x40);
    return page;
};

def write_stub(ulong page) -> void
{
    byte* p = (byte*)page;
    p[0]  = (byte)0x48;
    p[1]  = (byte)0xB8;
    p[2]  = (byte)0x00;
    p[3]  = (byte)0x00;
    p[4]  = (byte)0x00;
    p[5]  = (byte)0x00;
    p[6]  = (byte)0x00;
    p[7]  = (byte)0x00;
    p[8]  = (byte)0x00;
    p[9]  = (byte)0x00;
    p[10] = (byte)0xFF;
    p[11] = (byte)0xE0;
};

def patch_target(ulong page, ulong target_addr) -> void
{
    byte* p = (byte*)page;
    p[2] = (byte)(target_addr & (ulong)0xFF);
    p[3] = (byte)((target_addr >> (ulong)8)  & (ulong)0xFF);
    p[4] = (byte)((target_addr >> (ulong)16) & (ulong)0xFF);
    p[5] = (byte)((target_addr >> (ulong)24) & (ulong)0xFF);
    p[6] = (byte)((target_addr >> (ulong)32) & (ulong)0xFF);
    p[7] = (byte)((target_addr >> (ulong)40) & (ulong)0xFF);
    p[8] = (byte)((target_addr >> (ulong)48) & (ulong)0xFF);
    p[9] = (byte)((target_addr >> (ulong)56) & (ulong)0xFF);
};

// ============================================================================
// Simple pass/fail reporter
// ============================================================================

def pass(ulong got, ulong expected) -> bool
{
    if (got == expected)
    {
        print("    PASS (got \0");
        print(got);
        print(")\n\0");
        return true;
    };

    print("    FAIL  got=\0");
    print(got);
    print("  expected=\0");
    print(expected);
    print("\n\0");
    return false;
};

// ============================================================================
// TEST 1 - Rapid retargeting
//
// Patch and call 10 000 times, alternating between op_double and op_add100.
// Input is always 3:
//   op_double(3)  == 6
//   op_add100(3)  == 103
// Any stale-patch failure shows up immediately as a wrong return value.
// ============================================================================

def test_rapid_retarget() -> bool
{
    print("\n[TEST 1] Rapid retargeting (10 000 iterations)\n\0");

    ulong page = alloc_stub_page();
    write_stub(page);
    def{}* fn(ulong) -> ulong = (byte*)page;

    bool ok = true;
    int  failures = 0;

    for (int i = 0; i < 10000; i++)
    {
        ulong result = (ulong)0;

        if (i % 2 == 0)
        {
            patch_target(page, (ulong)@op_double);
            result = fn((ulong)3);
            if (result != (ulong)6)
            {
                failures = failures + 1;
                ok = false;
            };
        };

        if (i % 2 != 0)
        {
            patch_target(page, (ulong)@op_add100);
            result = fn((ulong)3);
            if (result != (ulong)103)
            {
                failures = failures + 1;
                ok = false;
            };
        };
    };

    VirtualFree(page, (size_t)0, (u32)0x8000);

    if (ok)
    {
        print("    PASS - 0 failures in 10 000 calls\n\0");
        return true;
    };

    print("    FAIL - \0");
    print(failures);
    print(" mismatches\n\0");
    return false;
};

// ============================================================================
// TEST 2 - Multi-stub independence
//
// Allocate 6 stubs simultaneously, one per target.
// Call them all, then shuffle targets across stubs and call again.
// No stub should ever dispatch to another stub's target.
// ============================================================================

def test_multi_stub() -> bool
{
    print("\n[TEST 2] Multi-stub independence (6 concurrent stubs)\n\0");

    ulong p0 = alloc_stub_page();
    ulong p1 = alloc_stub_page();
    ulong p2 = alloc_stub_page();
    ulong p3 = alloc_stub_page();
    ulong p4 = alloc_stub_page();
    ulong p5 = alloc_stub_page();

    write_stub(p0);
    write_stub(p1);
    write_stub(p2);
    write_stub(p3);
    write_stub(p4);
    write_stub(p5);

    patch_target(p0, (ulong)@op_double);
    patch_target(p1, (ulong)@op_add100);
    patch_target(p2, (ulong)@op_square);
    patch_target(p3, (ulong)@op_sub7);
    patch_target(p4, (ulong)@op_xor);
    patch_target(p5, (ulong)@op_identity);

    def{}* f0(ulong) -> ulong = (byte*)p0;
    def{}* f1(ulong) -> ulong = (byte*)p1;
    def{}* f2(ulong) -> ulong = (byte*)p2;
    def{}* f3(ulong) -> ulong = (byte*)p3;
    def{}* f4(ulong) -> ulong = (byte*)p4;
    def{}* f5(ulong) -> ulong = (byte*)p5;

    bool ok = true;
    ulong x = (ulong)10;

    // --- Round A: initial assignment ---
    print("  Round A (initial patch):\n\0");

    print("    f0(op_double,  10) -> \0");
    ok = pass(f0(x), (ulong)20)    & ok;

    print("    f1(op_add100,  10) -> \0");
    ok = pass(f1(x), (ulong)110)   & ok;

    print("    f2(op_square,  10) -> \0");
    ok = pass(f2(x), (ulong)100)   & ok;

    print("    f3(op_sub7,    10) -> \0");
    ok = pass(f3(x), (ulong)3)     & ok;

    print("    f4(op_xor,     10) -> \0");
    ok = pass(f4(x), (ulong)10 xor (ulong)0xDEAD) & ok;

    print("    f5(op_identity,10) -> \0");
    ok = pass(f5(x), (ulong)10)    & ok;

    // --- Round B: cross-patch (rotate targets one slot) ---
    print("  Round B (rotated patch):\n\0");

    patch_target(p0, (ulong)@op_add100);
    patch_target(p1, (ulong)@op_square);
    patch_target(p2, (ulong)@op_sub7);
    patch_target(p3, (ulong)@op_xor);
    patch_target(p4, (ulong)@op_identity);
    patch_target(p5, (ulong)@op_double);

    print("    f0(op_add100,  10) -> \0");
    ok = pass(f0(x), (ulong)110)   & ok;

    print("    f1(op_square,  10) -> \0");
    ok = pass(f1(x), (ulong)100)   & ok;

    print("    f2(op_sub7,    10) -> \0");
    ok = pass(f2(x), (ulong)3)     & ok;

    print("    f3(op_xor,     10) -> \0");
    ok = pass(f3(x), (ulong)10 xor (ulong)0xDEAD) & ok;

    print("    f4(op_identity,10) -> \0");
    ok = pass(f4(x), (ulong)10)    & ok;

    print("    f5(op_double,  10) -> \0");
    ok = pass(f5(x), (ulong)20)    & ok;

    VirtualFree(p0, (size_t)0, (u32)0x8000);
    VirtualFree(p1, (size_t)0, (u32)0x8000);
    VirtualFree(p2, (size_t)0, (u32)0x8000);
    VirtualFree(p3, (size_t)0, (u32)0x8000);
    VirtualFree(p4, (size_t)0, (u32)0x8000);
    VirtualFree(p5, (size_t)0, (u32)0x8000);

    return ok;
};

// ============================================================================
// TEST 3 - Round-robin churn
//
// Cycle targets A→B→C→D→E→F→A... for 6 000 calls (1 000 full rotations).
// Each call uses input 5 and checks the known result.
// ============================================================================

def test_round_robin() -> bool
{
    print("\n[TEST 3] Round-robin churn (6 000 calls, 1 000 rotations)\n\0");

    ulong page = alloc_stub_page();
    write_stub(page);
    def{}* fn(ulong) -> ulong = (byte*)page;

    bool ok       = true;
    int  failures = 0;
    ulong x       = (ulong)5;

    for (int i = 0; i < 1000; i++)
    {
        ulong r = (ulong)0;

        // Slot 0 - op_double
        patch_target(page, (ulong)@op_double);
        r = fn(x);
        if (r != (ulong)10) { failures = failures + 1; ok = false; };

        // Slot 1 - op_add100
        patch_target(page, (ulong)@op_add100);
        r = fn(x);
        if (r != (ulong)105) { failures = failures + 1; ok = false; };

        // Slot 2 - op_square
        patch_target(page, (ulong)@op_square);
        r = fn(x);
        if (r != (ulong)25) { failures = failures + 1; ok = false; };

        // Slot 3 - op_sub7
        patch_target(page, (ulong)@op_sub7);
        r = fn(x);
        if (r != (ulong)( (ulong)5 - (ulong)7 )) { failures = failures + 1; ok = false; };

        // Slot 4 - op_xor
        patch_target(page, (ulong)@op_xor);
        r = fn(x);
        if (r != ((ulong)5 xor (ulong)0xDEAD)) { failures = failures + 1; ok = false; };

        // Slot 5 - op_identity
        patch_target(page, (ulong)@op_identity);
        r = fn(x);
        if (r != (ulong)5) { failures = failures + 1; ok = false; };
    };

    VirtualFree(page, (size_t)0, (u32)0x8000);

    if (ok)
    {
        print("    PASS - 0 failures in 6 000 calls\n\0");
        return true;
    };

    print("    FAIL - \0");
    print(failures);
    print(" mismatches\n\0");
    return false;
};

// ============================================================================
// TEST 4 - Accumulator chain
//
// Start with seed = 1.
// Each step: patch to the next target, call with current accumulator.
// After N steps the accumulator must equal the manually computed value.
//
//   step 0: op_double(1)     = 2
//   step 1: op_add100(2)     = 102
//   step 2: op_square(102)   = 10404
//   step 3: op_sub7(10404)   = 10397
//   step 4: op_identity(10397) = 10397
//   step 5: op_double(10397)  = 20794
//   ... repeat pattern
// ============================================================================

def test_accumulator() -> bool
{
    print("\n[TEST 4] Accumulator chain\n\0");

    ulong page = alloc_stub_page();
    write_stub(page);
    def{}* fn(ulong) -> ulong = (byte*)page;

    // Manually compute the first 5-step chain so we have a known expected value.
    ulong acc      = (ulong)1;
    ulong expected = (ulong)1;

    // step 0
    expected = expected * (ulong)2;
    // step 1
    expected = expected + (ulong)100;
    // step 2
    expected = expected * expected;
    // step 3
    expected = expected - (ulong)7;
    // step 4
    expected = expected;    // identity

    print("  Manually computed 5-step expected: \0");
    print(expected);
    print("\n\0");

    // Now run via trampoline
    patch_target(page, (ulong)@op_double);
    acc = fn(acc);

    patch_target(page, (ulong)@op_add100);
    acc = fn(acc);

    patch_target(page, (ulong)@op_square);
    acc = fn(acc);

    patch_target(page, (ulong)@op_sub7);
    acc = fn(acc);

    patch_target(page, (ulong)@op_identity);
    acc = fn(acc);

    print("  Trampoline chain result:           \0");
    print(acc);
    print("\n  ");

    bool ok = pass(acc, expected);

    VirtualFree(page, (size_t)0, (u32)0x8000);
    return ok;
};

// ============================================================================
// TEST 5 - Re-entrant stub reuse (free → reallocate → rewrite → call)
//
// Allocate, use, free, then allocate again and write a fresh stub.
// Proves the mechanism is not relying on any residual executable state
// from the previous allocation.
// ============================================================================

def test_reuse() -> bool
{
    print("\n[TEST 5] Re-entrant stub reuse\n\0");

    bool ok = true;

    // --- First lifetime ---
    ulong page = alloc_stub_page();
    write_stub(page);
    def{}* fn(ulong) -> ulong = (byte*)page;

    patch_target(page, (ulong)@op_double);
    ulong r1 = fn((ulong)9);
    print("  First lifetime  op_double(9) -> \0");
    ok = pass(r1, (ulong)18) & ok;

    VirtualFree(page, (size_t)0, (u32)0x8000);

    // --- Second lifetime (fresh allocation) ---
    ulong page2 = alloc_stub_page();
    write_stub(page2);
    def{}* fn2(ulong) -> ulong = (byte*)page2;

    patch_target(page2, (ulong)@op_square);
    ulong r2 = fn2((ulong)9);
    print("  Second lifetime op_square(9) -> \0");
    ok = pass(r2, (ulong)81) & ok;

    patch_target(page2, (ulong)@op_add100);
    ulong r3 = fn2((ulong)9);
    print("  Repatch         op_add100(9) -> \0");
    ok = pass(r3, (ulong)109) & ok;

    VirtualFree(page2, (size_t)0, (u32)0x8000);

    return ok;
};

// ============================================================================
// Main
// ============================================================================

def main() -> int
{
    print("=== Flux Trampoline Stress Test ===\n\0");

    bool t1 = test_rapid_retarget();
    bool t2 = test_multi_stub();
    bool t3 = test_round_robin();
    bool t4 = test_accumulator();
    bool t5 = test_reuse();

    print("\n========================================\n\0");
    print("Results:\n\0");

    print("  Test 1 (rapid retarget)    : \0");
    if (t1) { print("PASS\n\0"); };
    if (!t1) { print("FAIL\n\0"); };

    print("  Test 2 (multi-stub)        : \0");
    if (t2) { print("PASS\n\0"); };
    if (!t2) { print("FAIL\n\0"); };

    print("  Test 3 (round-robin churn) : \0");
    if (t3) { print("PASS\n\0"); };
    if (!t3) { print("FAIL\n\0"); };

    print("  Test 4 (accumulator chain) : \0");
    if (t4) { print("PASS\n\0"); };
    if (!t4) { print("FAIL\n\0"); };

    print("  Test 5 (stub reuse)        : \0");
    if (t5) { print("PASS\n\0"); };
    if (!t5) { print("FAIL\n\0"); };

    bool all = t1 & t2 & t3 & t4 & t5;
    print("========================================\n\0");
    if (all)  { print("ALL TESTS PASSED\n\0"); };
    if (!all) { print("ONE OR MORE TESTS FAILED\n\0"); };

    return 0;
};
