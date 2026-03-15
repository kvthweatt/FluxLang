// atomics_demo.fx
// Demonstrates the redatomics.fx library.
//
// Exercises:
//   - Atomic load / store
//   - Atomic exchange
//   - Compare-and-swap (CAS) retry loop
//   - Fetch-and-modify  (add, sub, and, or, xor)
//   - Increment / decrement
//   - Spinlock (mutual exclusion around a shared counter)
//   - Once flag  (single-initialization guard)
//   - Reference counter
//   - Atomic flag

#import "standard.fx";
#import "atomics.fx";

using standard::io::console;

// ─────────────────────────────────────────────
//  Helpers – print a labelled integer result
// ─────────────────────────────────────────────

def print_result(byte* label, i32 value) -> void
{
    print(label);
    print(value);
    print("\n\0");
};

def print_bool(byte* label, bool value) -> void
{
    print(label);
    if (value)
    {
        print("true\n\0");
    }
    else
    {
        print("false\n\0");
    };
};

def print_sep(byte* title) -> void
{
    print("\n-- \0");
    print(title);
    print(" --\n\0");
};

// ─────────────────────────────────────────────
//  Shared state (globals act as "shared memory")
// ─────────────────────────────────────────────

i32 g_counter  = 0,   // Protected by g_lock in the spinlock demo
    g_lock     = 0,   // Spinlock
    g_once     = 0,   // Once flag
    g_refcount = 0,   // Reference counter
    g_flag     = 0,   // Atomic flag
    g_cas_val  = 100; // Value exercised by the CAS demo

// ─────────────────────────────────────────────
//  Demo sections
// ─────────────────────────────────────────────

def demo_load_store() -> void
{
    print_sep("Atomic Load / Store\0");

    i32 x = 0;
    store32(@x, 42);
    i32 loaded = load32(@x);
    print_result("store32(42) -> load32: \0", loaded);   // 42

    store64((i64*)@x, (i64)0);
    store32(@x, -7);
    print_result("store32(-7) -> load32: \0", load32(@x)); // -7
};

def demo_exchange() -> void
{
    print_sep("Atomic Exchange\0");

    i32 val = 10;
    i32 old = exchange32(@val, 99);
    print_result("exchange32(10->99) old: \0", old);      // 10
    print_result("exchange32(10->99) new: \0", load32(@val)); // 99
};

def demo_cas() -> void
{
    print_sep("Compare-and-Swap\0");

    // Successful CAS: expected matches
    bool ok = cas32(@g_cas_val, 100, 200);
    print_bool("cas32(100->200) success: \0", ok);          // true
    print_result("g_cas_val after:        \0", load32(@g_cas_val)); // 200

    // Failing CAS: expected does not match current value
    bool fail = cas32(@g_cas_val, 100, 999);
    print_bool("cas32(100->999) fail:   \0", fail);          // false
    print_result("g_cas_val unchanged:   \0", load32(@g_cas_val)); // 200

    // CAS retry loop – lock-free increment from 200 to 201
    i32 expected, desired;
    do
    {
        expected = load32(@g_cas_val);
        desired  = expected + 1;
    }
    while (!cas32(@g_cas_val, expected, desired));
    print_result("CAS retry increment:   \0", load32(@g_cas_val)); // 201
};

def demo_fetch_modify() -> void
{
    print_sep("Fetch-and-Modify\0");

    i32 n = 50;

    i32 prev = fetch_add32(@n, 10);
    print_result("fetch_add32(50, 10) old: \0", prev);          // 50
    print_result("fetch_add32(50, 10) new: \0", load32(@n));    // 60

    prev = fetch_sub32(@n, 5);
    print_result("fetch_sub32(60,  5) old: \0", prev);          // 60
    print_result("fetch_sub32(60,  5) new: \0", load32(@n));    // 55

    prev = fetch_or32(@n, 0x0F);
    print_result("fetch_or32 (55, 0x0F) old: \0", prev);        // 55  (0x37)
    print_result("fetch_or32 (55, 0x0F) new: \0", load32(@n)); // 63  (0x3F)

    prev = fetch_and32(@n, 0xF0);
    print_result("fetch_and32(63, 0xF0) old: \0", prev);        // 63  (0x3F)
    print_result("fetch_and32(63, 0xF0) new: \0", load32(@n)); // 48  (0x30)

    prev = fetch_xor32(@n, 0xFF);
    print_result("fetch_xor32(48, 0xFF) old: \0", prev);        // 48  (0x30)
    print_result("fetch_xor32(48, 0xFF) new: \0", load32(@n)); // 207 (0xCF)
};

def demo_inc_dec() -> void
{
    print_sep("Increment / Decrement\0");

    i32 c = 0;
    print_result("inc32 (0->1):  \0", inc32(@c));  // 1
    print_result("inc32 (1->2):  \0", inc32(@c));  // 2
    print_result("inc32 (2->3):  \0", inc32(@c));  // 3
    print_result("dec32 (3->2):  \0", dec32(@c));  // 2
    print_result("dec32 (2->1):  \0", dec32(@c));  // 1
    print_result("dec32 (1->0):  \0", dec32(@c));  // 0
};

def demo_spinlock() -> void
{
    print_sep("Spinlock\0");

    // Simulate N "threads" each adding to g_counter under the lock.
    // (Single-threaded simulation – the point is the correct API usage.)
    int iterations = 10;
    int i = 0;
    while (i < iterations)
    {
        spin_lock(@g_lock);
        g_counter = g_counter + 1;   // Critical section
        spin_unlock(@g_lock);
        i = i + 1;
    };
    print_result("counter after 10 locked increments: \0", g_counter); // 10

    // trylock demo
    bool got = spin_trylock(@g_lock);
    print_bool("spin_trylock (unlocked): \0", got);   // true  – lock was free
    bool again = spin_trylock(@g_lock);
    print_bool("spin_trylock (locked):   \0", again); // false – already held
    spin_unlock(@g_lock);
};

def demo_once() -> void
{
    print_sep("Once Flag\0");

    // First caller wins and performs init.
    if (once_begin(@g_once))
    {
        g_counter = g_counter + 100;   // "Expensive" one-time init
        once_end(@g_once);
        print("once_begin: WON - init performed\n\0");
    }
    else
    {
        print("once_begin: lost - init skipped\n\0");
    };

    // Second call must see the flag as already done.
    if (once_begin(@g_once))
    {
        print("once_begin: WON (second call) - SHOULD NOT HAPPEN\n\0");
        once_end(@g_once);
    }
    else
    {
        print("once_begin: lost (second call) - correct\n\0");
    };
};

def demo_refcount() -> void
{
    print_sep("Reference Counter\0");

    // Simulate acquiring two references to a resource.
    ref_inc(@g_refcount);
    ref_inc(@g_refcount);
    print_result("ref_count after 2 acquires: \0", ref_get(@g_refcount)); // 2

    // First release – resource still lives.
    bool dead = ref_dec_and_test(@g_refcount);
    print_bool("ref_dec_and_test (2->1): \0", dead);                      // false
    print_result("ref_count: \0", ref_get(@g_refcount));                  // 1

    // Second release – count hits zero, caller should free.
    dead = ref_dec_and_test(@g_refcount);
    print_bool("ref_dec_and_test (1->0): \0", dead);                      // true
    print_result("ref_count: \0", ref_get(@g_refcount));                  // 0
};

def demo_atomic_flag() -> void
{
    print_sep("Atomic Flag\0");

    print_bool("flag_test (initially 0): \0", flag_test(@g_flag));     // false

    flag_set(@g_flag);
    print_bool("flag_test after set:      \0", flag_test(@g_flag));    // true

    // test_and_set while already set
    bool was_set = flag_test_and_set(@g_flag);
    print_bool("flag_test_and_set (set):  \0", was_set);               // true

    flag_clear(@g_flag);
    print_bool("flag_test after clear:    \0", flag_test(@g_flag));    // false

    // test_and_set while clear – atomically raises the flag
    was_set = flag_test_and_set(@g_flag);
    print_bool("flag_test_and_set (clear):\0", was_set);               // false
    print_bool("flag_test after t-a-s:    \0", flag_test(@g_flag));    // true
};

def demo_fence() -> void
{
    print_sep("Memory Fences\0");

    // Fences have no visible output – we just verify they compile and run.
    fence();
    load_fence();
    store_fence();
    compiler_barrier();
    print("fence(), load_fence(), store_fence(), compiler_barrier() - OK\n\0");
};

// ─────────────────────────────────────────────
//  Entry point
// ─────────────────────────────────────────────

def main() -> int
{
    print("=== redatomics.fx demo ===\n\0");

    demo_load_store();
    demo_exchange();
    demo_cas();
    demo_fetch_modify();
    demo_inc_dec();
    demo_spinlock();
    demo_once();
    demo_refcount();
    demo_atomic_flag();
    demo_fence();

    print("\n=== all demos complete ===\n\0");
    return 0;
};
