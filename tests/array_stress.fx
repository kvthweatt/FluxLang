// array_stress.fx - Dynamic Array Stress Test
//
// Tests:
//   1. Basic push/get/len on int elements
//   2. pop returns correct value and shrinks len
//   3. set overwrites in place
//   4. insert shifts elements correctly
//   5. remove shifts elements correctly
//   6. clear resets len without freeing
//   7. contains byte-for-byte scan
//   8. Large insertion forcing multiple resizes
//   9. Interleaved push/remove/insert
//  10. Multi-type: 8-byte (u64) elements

#import "standard.fx", "redcollections.fx";

using standard::io::console,
      standard::collections;

// -------------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------------

int g_pass = 0;
int g_fail = 0;

def pass(noopstr name) -> void
{
    print("  [PASS] \0");
    print(name);
    print();
    g_pass = g_pass + 1;
};

def fail(noopstr name) -> void
{
    print("  [FAIL] \0");
    print(name);
    print();
    g_fail = g_fail + 1;
};

def check(bool cond, noopstr name) -> void
{
    if (cond)
    {
        pass(name);
    }
    else
    {
        fail(name);
    };
};

// -------------------------------------------------------------------------
// Section 1 - Basic push / get / len
// -------------------------------------------------------------------------

def test_basic() -> void
{
    print("--- Array basic push/get/len ---\0");
    print();

    Array arr((size_t)4); // int-sized elements
    defer arr.__exit();

    check(arr.len() == (size_t)0, "initial len == 0\0");

    int a = 10;
    int b = 20;
    int c = 30;

    arr.push((void*)@a);
    arr.push((void*)@b);
    arr.push((void*)@c);

    check(arr.len() == (size_t)3, "len == 3 after 3 pushes\0");

    int* pa = (int*)arr.get((size_t)0);
    int* pb = (int*)arr.get((size_t)1);
    int* pc = (int*)arr.get((size_t)2);

    check(*pa == 10, "get(0) == 10\0");
    check(*pb == 20, "get(1) == 20\0");
    check(*pc == 30, "get(2) == 30\0");

    check(arr.get((size_t)3) == STDLIB_GVP, "get(3) out of range returns null\0");
};

// -------------------------------------------------------------------------
// Section 2 - pop
// -------------------------------------------------------------------------

def test_pop() -> void
{
    print("--- Array pop ---\0");
    print();

    Array arr((size_t)4);
    defer arr.__exit();

    int a = 1;
    int b = 2;
    int c = 3;
    arr.push((void*)@a);
    arr.push((void*)@b);
    arr.push((void*)@c);

    int out = 0;
    check(arr.pop((void*)@out),    "pop returns true on non-empty\0");
    check(out == 3,                "pop gives last element (3)\0");
    check(arr.len() == (size_t)2,  "len == 2 after pop\0");

    arr.pop((void*)@out);
    check(out == 2,                "second pop gives 2\0");
    arr.pop((void*)@out);
    check(out == 1,                "third pop gives 1\0");
    check(arr.len() == (size_t)0,  "len == 0 after all pops\0");

    check(!arr.pop((void*)@out),   "pop on empty returns false\0");
};

// -------------------------------------------------------------------------
// Section 3 - set
// -------------------------------------------------------------------------

def test_set() -> void
{
    print("--- Array set ---\0");
    print();

    Array arr((size_t)4);
    defer arr.__exit();

    int a = 100;
    int b = 200;
    int c = 300;
    arr.push((void*)@a);
    arr.push((void*)@b);
    arr.push((void*)@c);

    int v = 999;
    check(arr.set((size_t)1, (void*)@v),  "set(1) returns true\0");
    int* p = (int*)arr.get((size_t)1);
    check(*p == 999,                       "get(1) == 999 after set\0");

    // Neighbours unchanged
    int* p0 = (int*)arr.get((size_t)0);
    int* p2 = (int*)arr.get((size_t)2);
    check(*p0 == 100, "get(0) still 100\0");
    check(*p2 == 300, "get(2) still 300\0");

    // Out-of-range set
    int q = 77;
    check(!arr.set((size_t)5, (void*)@q), "set(5) out of range returns false\0");
};

// -------------------------------------------------------------------------
// Section 4 - insert
// -------------------------------------------------------------------------

def test_insert() -> void
{
    print("--- Array insert ---\0");
    print();

    Array arr((size_t)4);
    defer arr.__exit();

    int a = 1;
    int b = 3;
    arr.push((void*)@a);
    arr.push((void*)@b);
    // arr = [1, 3]

    int mid = 2;
    check(arr.insert((size_t)1, (void*)@mid), "insert(1) returns true\0");
    // arr = [1, 2, 3]

    check(arr.len() == (size_t)3, "len == 3 after insert\0");

    int* p0 = (int*)arr.get((size_t)0);
    int* p1 = (int*)arr.get((size_t)1);
    int* p2 = (int*)arr.get((size_t)2);
    check(*p0 == 1, "get(0) == 1\0");
    check(*p1 == 2, "get(1) == 2 (inserted)\0");
    check(*p2 == 3, "get(2) == 3 (shifted)\0");

    // Insert at front
    int front = 0;
    arr.insert((size_t)0, (void*)@front);
    // arr = [0, 1, 2, 3]
    int* pf = (int*)arr.get((size_t)0);
    check(*pf == 0, "insert at 0 gives 0 at front\0");
    check(arr.len() == (size_t)4, "len == 4 after front insert\0");

    // Insert at end (== len)
    int tail = 4;
    arr.insert((size_t)4, (void*)@tail);
    // arr = [0, 1, 2, 3, 4]
    int* pt = (int*)arr.get((size_t)4);
    check(*pt == 4, "insert at len appends correctly\0");
    check(arr.len() == (size_t)5, "len == 5 after tail insert\0");

    // Out-of-range
    int bad = 99;
    check(!arr.insert((size_t)99, (void*)@bad), "insert beyond len returns false\0");
};

// -------------------------------------------------------------------------
// Section 5 - remove
// -------------------------------------------------------------------------

def test_remove() -> void
{
    print("--- Array remove ---\0");
    print();

    Array arr((size_t)4);
    defer arr.__exit();

    int a = 10;
    int b = 20;
    int c = 30;
    int d = 40;
    arr.push((void*)@a);
    arr.push((void*)@b);
    arr.push((void*)@c);
    arr.push((void*)@d);
    // arr = [10, 20, 30, 40]

    check(arr.remove((size_t)1), "remove(1) returns true\0");
    // arr = [10, 30, 40]
    check(arr.len() == (size_t)3, "len == 3 after remove\0");

    int* p0 = (int*)arr.get((size_t)0);
    int* p1 = (int*)arr.get((size_t)1);
    int* p2 = (int*)arr.get((size_t)2);
    check(*p0 == 10, "get(0) == 10 after remove\0");
    check(*p1 == 30, "get(1) == 30 (shifted left)\0");
    check(*p2 == 40, "get(2) == 40 (shifted left)\0");

    // Remove last element
    check(arr.remove((size_t)2), "remove(2) last returns true\0");
    check(arr.len() == (size_t)2, "len == 2 after removing last\0");

    // Out-of-range
    check(!arr.remove((size_t)5), "remove(5) out of range returns false\0");
};

// -------------------------------------------------------------------------
// Section 6 - clear
// -------------------------------------------------------------------------

def test_clear() -> void
{
    print("--- Array clear ---\0");
    print();

    Array arr((size_t)4);
    defer arr.__exit();

    int a = 1;
    int b = 2;
    arr.push((void*)@a);
    arr.push((void*)@b);

    arr.clear();
    check(arr.len() == (size_t)0, "len == 0 after clear\0");

    // Buffer is still alive; re-push should work
    int c = 99;
    arr.push((void*)@c);
    check(arr.len() == (size_t)1, "len == 1 after push post-clear\0");
    int* p = (int*)arr.get((size_t)0);
    check(*p == 99, "get(0) == 99 after re-push\0");
};

// -------------------------------------------------------------------------
// Section 7 - contains
// -------------------------------------------------------------------------

def test_contains() -> void
{
    print("--- Array contains ---\0");
    print();

    Array arr((size_t)4);
    defer arr.__exit();

    int a = 5;
    int b = 10;
    int c = 15;
    arr.push((void*)@a);
    arr.push((void*)@b);
    arr.push((void*)@c);

    int x = 10;
    int y = 99;
    check(arr.contains((void*)@x),  "contains 10 -> true\0");
    check(!arr.contains((void*)@y), "contains 99 -> false\0");

    int z = 5;
    check(arr.contains((void*)@z),  "contains 5 (first) -> true\0");

    int w = 15;
    check(arr.contains((void*)@w),  "contains 15 (last) -> true\0");
};

// -------------------------------------------------------------------------
// Section 8 - Resize stress: push 1000 ints, verify all
// -------------------------------------------------------------------------

def test_resize() -> void
{
    print("--- Array resize stress (1000 ints) ---\0");
    print();

    Array arr((size_t)4);
    defer arr.__exit();

    int n = 1000;
    int i = 0;
    while (i < n)
    {
        arr.push((void*)@i);
        i = i + 1;
    };

    check(arr.len() == (size_t)1000, "len == 1000 after bulk push\0");

    bool all_ok = true;
    i = 0;
    while (i < n)
    {
        int* p = (int*)arr.get((size_t)i);
        if (*p != i)
        {
            all_ok = false;
        };
        i = i + 1;
    };
    check(all_ok, "all 1000 elements correct after resize\0");
};

// -------------------------------------------------------------------------
// Section 9 - Interleaved push / remove / insert
// Push 20, remove odds, insert sentinel at front, verify.
// -------------------------------------------------------------------------

def test_interleaved() -> void
{
    print("--- Array interleaved push/remove/insert ---\0");
    print();

    Array arr((size_t)4);
    defer arr.__exit();

    // Push 0..19
    int n = 20;
    int i = 0;
    while (i < n)
    {
        arr.push((void*)@i);
        i = i + 1;
    };

    // Remove odd-indexed positions. After each removal the array shrinks,
    // so we walk a write cursor over positions that held odd values.
    // Simpler: remove from back to front to avoid index drift.
    i = n - 1;
    while (i >= 0)
    {
        int val = i;
        if (val % 2 != 0)
        {
            // find and remove - we know position = i still because we go right to left
            arr.remove((size_t)i);
        };
        i = i - 1;
    };
    // arr should now be [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
    check(arr.len() == (size_t)10, "len == 10 after removing odds\0");

    bool evens_ok = true;
    i = 0;
    while (i < 10)
    {
        int* p = (int*)arr.get((size_t)i);
        int expected = i * 2;
        if (*p != expected)
        {
            evens_ok = false;
        };
        i = i + 1;
    };
    check(evens_ok, "remaining elements are 0,2,4,...,18\0");

    // Insert sentinel -1 at front
    int sentinel = -1;
    arr.insert((size_t)0, (void*)@sentinel);
    check(arr.len() == (size_t)11, "len == 11 after front insert\0");
    int* pfront = (int*)arr.get((size_t)0);
    check(*pfront == -1, "front sentinel == -1\0");

    // First even is still at index 1
    int* p1 = (int*)arr.get((size_t)1);
    check(*p1 == 0, "index 1 still holds 0 after front insert\0");
};

// -------------------------------------------------------------------------
// Section 10 - 8-byte (u64) elements
// -------------------------------------------------------------------------

def test_u64_elements() -> void
{
    print("--- Array u64 elements ---\0");
    print();

    Array arr((size_t)8); // 8-byte elements
    defer arr.__exit();

    u64 a = 1000000000u;
    u64 b = 2000000000u;
    u64 c = 9999999999u;

    arr.push((void*)@a);
    arr.push((void*)@b);
    arr.push((void*)@c);

    check(arr.len() == (size_t)3, "u64 arr len == 3\0");

    u64* pa = (u64*)arr.get((size_t)0);
    u64* pb = (u64*)arr.get((size_t)1);
    u64* pc = (u64*)arr.get((size_t)2);

    check(*pa == 1000000000u, "u64 get(0) correct\0");
    check(*pb == 2000000000u, "u64 get(1) correct\0");
    check(*pc == 9999999999u, "u64 get(2) correct\0");

    // Pop
    u64 out = 0u;
    arr.pop((void*)@out);
    check(out == 9999999999u, "u64 pop gives last value\0");
    check(arr.len() == (size_t)2, "u64 len == 2 after pop\0");

    // contains
    u64 look = 2000000000u;
    u64 miss = 12345u;
    check(arr.contains((void*)@look),  "u64 contains 2000000000 -> true\0");
    check(!arr.contains((void*)@miss), "u64 contains 12345 -> false\0");
};

// -------------------------------------------------------------------------
// main
// -------------------------------------------------------------------------

def main() -> int
{
    print("==============================\0");
    print();
    print("  Array Stress Test\0");
    print();
    print("==============================\0");
    print();

    test_basic();
    test_pop();
    test_set();
    test_insert();
    test_remove();
    test_clear();
    test_contains();
    test_resize();
    test_interleaved();
    test_u64_elements();

    print("==============================\0");
    print();
    print("Results: \0");
    print(g_pass);
    print(" passed, \0");
    print(g_fail);
    print(" failed\0");
    print();
    print("==============================\0");
    print();

    if (g_fail != 0)
    {
        return 1;
    };
    return 0;
};
