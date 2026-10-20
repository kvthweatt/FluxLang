// Effect system comprehensive test.
// Tests: transitive propagation, Pure enforcement, conflict detection,
//        attenuation, exclusions, user-defined effects, all builtin families.

#import <standard.fx>;

using standard::io::console;

// ---------------------------------------------------------------------------
// Effect declarations
// ---------------------------------------------------------------------------

// Standard composed effects
effect ShadowStack { *Hook & !@Unsafe & !Alloc };
effect SafeDetour  { *Hook.Detour & ^Alloc };
effect RealTime    { !Alloc & !IO & !Throw };
effect NetworkIO   { *IO.Socket & [Mem.Write | Mem.Read] };
effect HookContext { *Hook & !@Unsafe & !IO };

// Conflict test effects -- exactly-one and mutual implication
effect ReadOnly    { *Mem.Read <-> !Mem.Write };
effect ExclusiveIO { IO.Console ^| IO.File };

// ---------------------------------------------------------------------------
// Leaf stubs -- direct effect sources
// ---------------------------------------------------------------------------

// IO
leaf_console(byte* msg) -> void # effect {*IO.Console};
leaf_console(byte* msg) -> void {};

leaf_file(byte* path) -> void # effect {*IO.File};
leaf_file(byte* path) -> void {};

leaf_socket(byte* xd) -> void # effect {*IO.Socket};
leaf_socket(byte* xd) -> void {};

// Alloc
leaf_heap() -> void* # effect {*Alloc.Heap};
leaf_heap() -> void* {};

leaf_virtual(uint size) -> void* # effect {*Alloc.Virtual};
leaf_virtual(uint size) -> void* {};

// Unsafe
leaf_ptr(void* p) -> byte # effect {*Unsafe.Ptr};
leaf_ptr(void* p) -> byte { -> 0; };

leaf_asm() -> long # effect {*Unsafe.ASM};
leaf_asm() -> long { -> 0; };

leaf_ffi(void* fn) -> void # effect {*Unsafe.FFI};
leaf_ffi(void* fn) -> void {};

// Mem
leaf_read_proc(void* addr) -> byte # effect {*Mem.Read.Process};
leaf_read_proc(void* addr) -> byte { -> 0; };

leaf_write_exec(void* addr, byte val) -> void # effect {*Mem.Write.Exec};
leaf_write_exec(void* addr, byte val) -> void {};

leaf_write_kernel(void* addr, byte val) -> void # effect {*Mem.Write.Kernel};
leaf_write_kernel(void* addr, byte val) -> void {};

// Hook
leaf_detour(void* target, void* hook) -> void # effect {*Hook.Detour};
leaf_detour(void* target, void* hook) -> void {};

leaf_iat(byte* mod, byte* fn, void* hook) -> void # effect {*Hook.IAT};
leaf_iat(byte* mod, byte* fn, void* hook) -> void {};

// Sync
leaf_lock() -> void # effect {*Sync.Lock};
leaf_lock() -> void {};

leaf_atomic(void* p, int val) -> void # effect {*Sync.Atomic};
leaf_atomic(void* p, int val) -> void {};

// Crypto
leaf_hash(byte* xd, uint len) -> void # effect {*Crypto.Hash};
leaf_hash(byte* xd, uint len) -> void {};

leaf_random(byte* buf, uint len) -> void # effect {*Crypto.Random};
leaf_random(byte* buf, uint len) -> void {};

// Process
leaf_spawn(byte* path) -> uint # effect {*Process.Spawn};
leaf_spawn(byte* path) -> uint { -> 0; };

leaf_inject(uint pid, byte* dll) -> void # effect {*Process.Inject};
leaf_inject(uint pid, byte* dll) -> void {};

// Privilege
leaf_elevate() -> void # effect {*Privilege.Elevate};
leaf_elevate() -> void {};

leaf_priv_check(uint p) -> bool # effect {*Privilege.Check};
leaf_priv_check(uint p) -> bool { -> false; };

// Time
leaf_sleep(uint ms) -> void # effect {*Time.Sleep};
leaf_sleep(uint ms) -> void {};

// Anchors
leaf_pure(int a, int b) -> int # effect {Pure};
leaf_pure(int a, int b) -> int { -> a + b; };

leaf_throw(int x) -> int # effect {*Throw};
leaf_throw(int x) -> int { -> x; };

// ---------------------------------------------------------------------------
// Intermediate functions (transitive propagation test targets)
// No annotations -- effects propagate upward through them.
// ---------------------------------------------------------------------------

// mid_io calls leaf_console. No annotation.
// Any caller that excludes IO should catch this transitively.
mid_io() -> void;
mid_io() -> void
{
    leaf_console("mid\0");
};

// mid_alloc calls leaf_heap. No annotation.
mid_alloc() -> void*;
mid_alloc() -> void*
{
    -> leaf_heap();
};

// mid_chain calls mid_io which calls leaf_console -- two hops deep.
mid_chain() -> void;
mid_chain() -> void
{
    mid_io();
};

// mid_deep_alloc calls mid_alloc which calls leaf_heap -- two hops.
mid_deep_alloc() -> void;
mid_deep_alloc() -> void
{
    void* p = mid_alloc();
    (void)p;
};

// mid_multi introduces both IO and Alloc through separate chains.
mid_multi() -> void;
mid_multi() -> void
{
    mid_io();
    mid_deep_alloc();
};

// mid_unsafe calls leaf_asm transitively.
mid_unsafe() -> void;
mid_unsafe() -> void
{
    leaf_asm();
};

// ---------------------------------------------------------------------------
// Attenuation stubs
// ---------------------------------------------------------------------------

// Fully attenuates IO -- callers see no IO effect.
attenuated_io(byte* msg) -> void # attenuate {IO};
attenuated_io(byte* msg) -> void
{
    leaf_console(msg);
};

// Fully attenuates Alloc.
attenuated_alloc(uint size) -> void* # attenuate {Alloc};
attenuated_alloc(uint size) -> void* {};

// Attenuates IO but not Alloc -- both escape without attenuation.
partial_attenuate(byte* msg) -> void # effect {*Alloc.Heap} # attenuate {IO};
partial_attenuate(byte* msg) -> void
{
    leaf_console(msg);
    void* p = leaf_heap();
    (void)p;
};

// Attenuates only IO.Socket -- IO.File still escapes.
socket_attenuate(byte* msg) -> void # effect {*IO.File} # attenuate {IO.Socket};
socket_attenuate(byte* msg) -> void
{
    leaf_socket(msg);
    leaf_file(msg);
};

// Attenuates a transitively introduced effect -- mid_io's IO is contained.
attenuated_transitive(byte* msg) -> void # attenuate {IO};
attenuated_transitive(byte* msg) -> void
{
    mid_io();
};

// ---------------------------------------------------------------------------
// TRANSITIVE PROPAGATION TESTS
// ---------------------------------------------------------------------------

// SHOULD FAIL (1 violation): excludes IO, calls mid_io which introduces
// IO.Console transitively through leaf_console.
trans_direct_fail() -> void # effect {!IO};
trans_direct_fail() -> void
{
    mid_io();
};

// SHOULD FAIL (1 violation): excludes IO, calls mid_chain which is two hops
// from leaf_console.
trans_two_hop_fail() -> void # effect {!IO};
trans_two_hop_fail() -> void
{
    mid_chain();
};

// SHOULD FAIL (2 violations): excludes both IO and Alloc, calls mid_multi
// which introduces both transitively.
trans_multi_fail() -> void # effect {!IO & !Alloc};
trans_multi_fail() -> void
{
    mid_multi();
};

// SHOULD PASS: calls attenuated_transitive which contains mid_io's IO.
trans_attenuated_pass() -> void # effect {!IO};
trans_attenuated_pass() -> void
{
    attenuated_transitive("ok\0");
};

// SHOULD PASS: calls attenuated_io which attenuates all IO.
trans_fully_attenuated_pass() -> void # effect {!IO};
trans_fully_attenuated_pass() -> void
{
    attenuated_io("ok\0");
};

// SHOULD FAIL (1 violation): partial_attenuate attenuates IO but introduces
// Alloc.Heap -- caller excludes Alloc.
trans_partial_attenuate_fail() -> void # effect {!Alloc};
trans_partial_attenuate_fail() -> void
{
    partial_attenuate("bad\0");
};

// SHOULD FAIL (1 violation): socket_attenuate attenuates IO.Socket but
// IO.File escapes -- caller excludes IO.
trans_socket_fail() -> void # effect {!IO};
trans_socket_fail() -> void
{
    socket_attenuate("bad\0");
};

// ---------------------------------------------------------------------------
// PURE ENFORCEMENT TESTS
// ---------------------------------------------------------------------------

// SHOULD PASS: only calls leaf_pure which is Pure.
pure_pass() -> int # effect {Pure};
pure_pass() -> int
{
    -> leaf_pure(1, 2);
};

// SHOULD PASS: chains two Pure calls.
pure_chain_pass() -> int # effect {Pure};
pure_chain_pass() -> int
{
    int a = leaf_pure(1, 2);
    int b = leaf_pure(a, 3);
    -> b;
};

// SHOULD FAIL: declares Pure but calls leaf_console -- IO violation.
pure_io_fail() -> void # effect {Pure};
pure_io_fail() -> void
{
    leaf_console("bad\0");
};

// SHOULD FAIL: declares Pure but calls mid_alloc -- Alloc violation
// introduced transitively through mid_alloc -> leaf_heap.
pure_transitive_alloc_fail() -> int # effect {Pure};
pure_transitive_alloc_fail() -> int
{
    void* p = mid_alloc();
    (void)p;
    -> 0;
};

// SHOULD FAIL: declares Pure but calls leaf_throw -- Throw violation.
pure_throw_fail() -> int # effect {Pure};
pure_throw_fail() -> int
{
    -> leaf_throw(1);
};

// SHOULD FAIL: declares Pure but calls mid_chain -- IO violation two hops deep.
pure_deep_fail() -> void # effect {Pure};
pure_deep_fail() -> void
{
    mid_chain();
};

// ---------------------------------------------------------------------------
// CONFLICT DETECTION TESTS
// ---------------------------------------------------------------------------

// ExclusiveIO declares IO.Console ^ IO.File (exactly one allowed).

// SHOULD FAIL: introduces both IO.Console and IO.File -- violates ^ constraint.
conflict_xor_fail() -> void # effect {ExclusiveIO};
conflict_xor_fail() -> void
{
    leaf_console("a\0");
    leaf_file("b\0");
};

// SHOULD PASS: introduces only IO.Console.
conflict_xor_pass() -> void # effect {ExclusiveIO};
conflict_xor_pass() -> void
{
    leaf_console("a\0");
};

// ReadOnly declares Mem.Read <-> !Mem.Write (mutual: read implies no write).

// SHOULD FAIL: introduces Mem.Read.Process and Mem.Write.Exec --
// violates <-> constraint.
conflict_mutual_fail() -> void # effect {ReadOnly};
conflict_mutual_fail() -> void
{
    leaf_read_proc((@)void);
    leaf_write_exec((@)void, 0);
};

// SHOULD PASS: introduces only Mem.Read.
conflict_mutual_pass() -> void # effect {ReadOnly};
conflict_mutual_pass() -> void
{
    leaf_read_proc((@)void);
};

// ---------------------------------------------------------------------------
// DIRECT EXCLUSION TESTS (baseline)
// ---------------------------------------------------------------------------

// SHOULD FAIL: !Alloc, calls leaf_heap directly.
excl_alloc_fail() -> void # effect {!Alloc};
excl_alloc_fail() -> void
{
    leaf_heap();
};

// SHOULD FAIL: !IO, calls leaf_console directly.
excl_io_fail() -> void # effect {!IO};
excl_io_fail() -> void
{
    leaf_console("bad\0");
};

// SHOULD PASS: !IO, calls attenuated_io.
excl_io_attenuated_pass() -> void # effect {!IO};
excl_io_attenuated_pass() -> void
{
    attenuated_io("ok\0");
};

// SHOULD PASS: !Alloc, calls attenuated_alloc.
excl_alloc_attenuated_pass() -> void # effect {!Alloc};
excl_alloc_attenuated_pass() -> void
{
    attenuated_alloc(64);
};

// SHOULD FAIL: !IO, calls socket_attenuate -- IO.File escapes.
excl_partial_fail() -> void # effect {!IO};
excl_partial_fail() -> void
{
    socket_attenuate("bad\0");
};

// ---------------------------------------------------------------------------
// USER-DEFINED EFFECT TESTS
// ---------------------------------------------------------------------------

// SHOULD PASS: ShadowStack excludes Alloc, hook_wrap only calls leaf_detour.
shadow_stack_pass() -> void # effect {ShadowStack};
shadow_stack_pass() -> void
{
    leaf_detour((@)void, (@)void);
};

// SHOULD FAIL: ShadowStack excludes Alloc, but we call leaf_heap.
shadow_stack_alloc_fail() -> void # effect {ShadowStack};
shadow_stack_alloc_fail() -> void
{
    leaf_detour((@)void, (@)void);
    leaf_heap();
};

// SHOULD PASS: RealTime excludes Alloc, IO, Throw -- only calls leaf_pure.
rt_pass() -> void # effect {RealTime};
rt_pass() -> void
{
    leaf_pure(1, 2);
};

// SHOULD FAIL: RealTime excludes IO -- calls mid_io transitively.
rt_io_fail() -> void # effect {RealTime};
rt_io_fail() -> void
{
    mid_io();
};

// SHOULD FAIL: RealTime excludes Alloc -- calls leaf_heap.
rt_alloc_fail() -> void # effect {RealTime};
rt_alloc_fail() -> void
{
    leaf_heap();
};

// ---------------------------------------------------------------------------
// MAIN -- unrestricted, exercises all families
// ---------------------------------------------------------------------------

main() -> int
{
    leaf_console("Effect comprehensive test\0");

    void* p = leaf_heap();
    (void)p;

    leaf_lock();
    leaf_hash("x\0", 1);
    leaf_random("buf\0", 4);
    leaf_elevate();
    leaf_priv_check(0);
    leaf_sleep(1);
    leaf_detour((@)void, (@)void);
    leaf_inject(0, "dll\0");
    leaf_spawn("path\0");
    leaf_asm();
    leaf_ffi((@)void);

    int r = leaf_pure(2, 3);
    (void)r;

    -> 0;
};