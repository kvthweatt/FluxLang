// smartptr_stress.fx — Stress test for the smartptr object
//
// Tests:
//   1. Basic init / valid / get / count
//   2. retain increments ref count correctly
//   3. release decrements and frees at zero
//   4. valid() returns false after full release
//   5. detach() transfers ownership without freeing
//   6. swap() exchanges raw + ref_count between two instances
//   7. Chain retain/release back to zero
//   8. Multi-step retain chain (retain N times, release N times)
//   9. Double-release safety (count never underflows below zero)
//  10. detach on already-null pointer returns STDLIB_GVP

#import "standard.fx";

using standard::io::console;

// ============================================================================
// Helpers
// ============================================================================

int g_pass, g_fail;

def check(bool cond, byte* labelx) -> void
{
    if (cond)
    {
        print("  [PASS] \0");
        print(labelx);
        print();
        g_pass = g_pass + 1;
    }
    else
    {
        print("  [FAIL] \0");
        print(labelx);
        print();
        g_fail = g_fail + 1;
    };
    return;
};

// ============================================================================
// main
// ============================================================================

def main() -> int
{
    print("=== smartptr stress test ===\0");
    print();

    // -------------------------------------------------------------------------
    // Test 1 — Basic init
    // -------------------------------------------------------------------------
    print("-- Test 1: Basic init --\0");
    print();

    int* p1 = (int*)fmalloc((u64)8);
    p1[0] = 42;

    smartptr sp1 = smartptr.__init<int>(p1);

    check(sp1.valid(),                  "valid() is true after init\0");
    check(sp1.count() == (size_t)1,     "count() == 1 after init\0");
    check(sp1.get()   == (void*)p1,     "get() returns original pointer\0");
    print();

    // -------------------------------------------------------------------------
    // Test 2 — retain increments count
    // -------------------------------------------------------------------------
    print("-- Test 2: retain --\0");
    print();

    sp1.retain();
    check(sp1.count() == (size_t)2, "count() == 2 after one retain\0");

    sp1.retain();
    check(sp1.count() == (size_t)3, "count() == 3 after two retains\0");
    print();

    // -------------------------------------------------------------------------
    // Test 3 — release decrements count
    // -------------------------------------------------------------------------
    print("-- Test 3: release decrements\0");
    print();

    sp1.release();
    check(sp1.count() == (size_t)2, "count() == 2 after one release\0");

    sp1.release();
    check(sp1.count() == (size_t)1, "count() == 1 after second release\0");

    // pointer must still be live (ref_count > 0)
    check(sp1.valid(), "valid() still true while count > 0\0");
    print();

    // -------------------------------------------------------------------------
    // Test 4 — final release frees and invalidates
    // -------------------------------------------------------------------------
    print("-- Test 4: final release frees\0");
    print();

    sp1.release();
    check(sp1.count() == (size_t)0, "count() == 0 after final release\0");
    check(!sp1.valid(),              "valid() is false after final release\0");
    check(sp1.get() == STDLIB_GVP,  "get() returns STDLIB_GVP after free\0");
    print();

    // -------------------------------------------------------------------------
    // Test 5 — double-release safety (must not underflow)
    // -------------------------------------------------------------------------
    print("-- Test 5: double-release safety --\0");
    print();

    // sp1 already at 0 — calling release again must not wrap around
    sp1.release();
    check(sp1.count() == (size_t)0, "count() stays 0 on extra release\0");
    check(!sp1.valid(),              "valid() still false after extra release\0");
    print();

    // -------------------------------------------------------------------------
    // Test 6 — detach transfers ownership
    // -------------------------------------------------------------------------
    print("-- Test 6: detach --\0");
    print();

    int* p2 = (int*)fmalloc((u64)8);
    p2[0] = 99;

    smartptr sp2;
    sp2.__init<int>(p2);

    void* raw2 = sp2.detach();

    check(raw2        == (void*)p2, "detach() returns original pointer\0");
    check(!sp2.valid(),              "valid() false after detach\0");
    check(sp2.count() == (size_t)0, "count() == 0 after detach\0");

    // We now own raw2 — free it manually to avoid leak
    free(raw2);
    print();

    // -------------------------------------------------------------------------
    // Test 7 — detach on null/already-detached pointer
    // -------------------------------------------------------------------------
    print("-- Test 7: detach on null pointer --\0");
    print();

    smartptr sp3;
    sp3.__init<int>((int*)STDLIB_GVP);

    void* raw3 = sp3.detach();
    check(raw3 == STDLIB_GVP, "detach on null returns STDLIB_GVP\0");
    print();

    // -------------------------------------------------------------------------
    // Test 8 — swap exchanges contents
    // -------------------------------------------------------------------------
    print("-- Test 8: swap --\0");
    print();

    int* pA = (int*)fmalloc((u64)8);
    int* pB = (int*)fmalloc((u64)8);
    pA[0] = 11;
    pB[0] = 22;

    smartptr spA;
    smartptr spB;
    spA.__init<int>(pA);
    spB.__init<int>(pB);

    // Give spA extra retains so counts differ
    spA.retain();
    spA.retain();   // spA.count == 3, spB.count == 1

    spA.swap(@spB);

    check(spA.get()   == (void*)pB,  "after swap: spA.get() == pB\0");
    check(spB.get()   == (void*)pA,  "after swap: spB.get() == pA\0");
    check(spA.count() == (size_t)1,  "after swap: spA.count() == 1\0");
    check(spB.count() == (size_t)3,  "after swap: spB.count() == 3\0");

    // Clean up: drain spB (count 3), spA (count 1)
    spB.release();
    spB.release();
    spB.release();  // frees pA
    spA.release();  // frees pB
    print();

    // -------------------------------------------------------------------------
    // Test 9 — multi-step retain chain
    // -------------------------------------------------------------------------
    print("-- Test 9: multi-step retain/release chain --\0");
    print();

    int* p4 = (int*)fmalloc((u64)8);
    p4[0] = 7;

    smartptr sp4;
    sp4.__init<int>(p4);

    int i = 0;
    while (i < 10)
    {
        sp4.retain();
        i = i + 1;
    };
    check(sp4.count() == (size_t)11, "count() == 11 after 10 retains\0");

    i = 0;
    while (i < 10)
    {
        sp4.release();
        i = i + 1;
    };
    check(sp4.count() == (size_t)1,  "count() == 1 after 10 releases\0");
    check(sp4.valid(),                "valid() true — not yet freed\0");

    sp4.release();  // final release
    check(!sp4.valid(),               "valid() false after final release\0");
    print();

    // -------------------------------------------------------------------------
    // Test 10 — __exit destructor path (manual call)
    // -------------------------------------------------------------------------
    print("-- Test 10: __exit destructor --\0");
    print();

    int* p5 = (int*)fmalloc((u64)8);
    p5[0] = 55;

    smartptr sp5;
    sp5.__init<int>(p5);
    sp5.retain();  // count == 2

    sp5.__exit();  // should release once; count falls to 1, pointer still live
    // After __exit calls release(), count should be 1 and pointer still valid
    // NOTE: __exit calls release() which decrements by 1.
    check(sp5.count() == (size_t)1, "__exit decrements count by 1\0");
    check(sp5.valid(),               "valid() true — count still 1 after __exit\0");

    sp5.release();  // drain the last reference manually
    check(!sp5.valid(), "valid() false after draining remaining reference\0");
    print();

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    print("============================\0");
    print("PASSED: \0"); print(g_pass); print();
    print("FAILED: \0"); print(g_fail); print();
    print("============================\0");
    print();

    if (g_fail == 0)
    {
        print("All tests passed.\0");
        print();
        return 0;
    }
    else
    {
        print("Some tests FAILED.\0");
        print();
        return 1;
    };
};
