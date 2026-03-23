// Author: Karac V. Thweatt

// redatomics.fx - Atomic Operations Library
// Provides lock-free atomic primitives for safe multi-threaded access.
// Uses inline assembly for x86/x64 and ARM64 hardware atomics.
//
// Memory ordering constants mirror the C11/C++11 model:
//   RELAXED  - No ordering guarantees (fastest)
//   ACQUIRE  - Loads are ordered before subsequent reads/writes
//   RELEASE  - Stores are ordered after prior reads/writes
//   ACQ_REL  - Both acquire and release (for read-modify-write)
//   SEQ_CST  - Full sequential consistency (strongest, default)

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_ATOMICS
#def FLUX_STANDARD_ATOMICS 1;

// ============================================================
//  Memory Ordering Constants
// ============================================================
global const int ATOMIC_RELAXED = 0,
                 ATOMIC_ACQUIRE = 2,
                 ATOMIC_RELEASE = 3,
                 ATOMIC_ACQ_REL = 4,
                 ATOMIC_SEQ_CST = 5;

namespace standard
{
    namespace atomic
    {
        // ============================================================
        //  Memory Fence / Barrier
        // ============================================================

        // Full sequential memory fence.
        def fence() -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                mfence
            } : : : "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                dmb ish
            } : : : "memory";
            #endif;
        };

        // Compiler-only barrier - no hardware fence instruction.
        def compiler_barrier() -> void
        {
            volatile asm
            {
            } : : : "memory";
        };

        // Load fence.
        def load_fence() -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                lfence
            } : : : "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                dmb ishld
            } : : : "memory";
            #endif;
        };

        // Store fence.
        def store_fence() -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                sfence
            } : : : "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                dmb ishst
            } : : : "memory";
            #endif;
        };

        // ============================================================
        //  Atomic Load
        //
        //  Internal helpers take an explicit out pointer parameter so
        //  the compiler emits it as a real asm constraint argument.
        // ============================================================

        def _load32(i32* ptr, i32* out) -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rsi
                movq $1, %rdi
                movl (%rsi), %eax
                movl %eax, (%rdi)
            } : : "r"(ptr), "r"(out) : "eax", "rsi", "rdi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                ldar w0, [$0]
                str  w0, [$1]
            } : : "r"(ptr), "r"(out) : "w0", "memory";
            #endif;
        };

        def _load64(i64* ptr, i64* out) -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rsi
                movq $1, %rdi
                movq (%rsi), %rax
                movq %rax, (%rdi)
            } : : "r"(ptr), "r"(out) : "rax", "rsi", "rdi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                ldar x0, [$0]
                str  x0, [$1]
            } : : "r"(ptr), "r"(out) : "x0", "memory";
            #endif;
        };

        // Atomically load a 32-bit value from ptr.
        def load32(i32* ptr) -> i32
        {
            i32 result;
            _load32(ptr, @result);
            return result;
        };

        // Atomically load a 64-bit value from ptr.
        def load64(i64* ptr) -> i64
        {
            i64 result;
            _load64(ptr, @result);
            return result;
        };

        // ============================================================
        //  Atomic Store
        // ============================================================

        // Atomically store value into *ptr.
        def store32(i32* ptr, i32 value) -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rsi
                movl $1, %eax
                xchgl %eax, (%rsi)
            } : : "r"(ptr), "r"(value) : "eax", "rsi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                stlr w1, [$0]
            } : : "r"(ptr), "r"(value) : "memory";
            #endif;
        };

        def store64(i64* ptr, i64 value) -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rsi
                movq $1, %rax
                xchgq %rax, (%rsi)
            } : : "r"(ptr), "r"(value) : "rax", "rsi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                stlr x1, [$0]
            } : : "r"(ptr), "r"(value) : "memory";
            #endif;
        };

        // ============================================================
        //  Atomic Exchange (swap)
        // ============================================================

        def _exchange32(i32* ptr, i32 value, i32* out) -> void
        {
            #ifdef __ARCH_X86_64__
            // XCHG with memory has an implicit LOCK prefix.
            volatile asm
            {
                movq $0, %rsi
                movq $2, %rdi
                movl $1, %eax
                xchgl %eax, (%rsi)
                movl %eax, (%rdi)
            } : : "r"(ptr), "r"(value), "r"(out) : "eax", "rsi", "rdi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
            .retry_xchg32:
                ldaxr w0, [$0]
                stlxr w3, w1, [$0]
                cbnz  w3, .retry_xchg32
                str   w0, [$2]
            } : : "r"(ptr), "r"(value), "r"(out) : "w0", "w3", "memory";
            #endif;
        };

        def _exchange64(i64* ptr, i64 value, i64* out) -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rsi
                movq $2, %rdi
                movq $1, %rax
                xchgq %rax, (%rsi)
                movq %rax, (%rdi)
            } : : "r"(ptr), "r"(value), "r"(out) : "rax", "rsi", "rdi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
            .retry_xchg64:
                ldaxr x0, [$0]
                stlxr w3, x1, [$0]
                cbnz  w3, .retry_xchg64
                str   x0, [$2]
            } : : "r"(ptr), "r"(value), "r"(out) : "x0", "w3", "memory";
            #endif;
        };

        // Atomically replace *ptr with value; returns the old value.
        def exchange32(i32* ptr, i32 value) -> i32
        {
            i32 old;
            _exchange32(ptr, value, @old);
            return old;
        };

        def exchange64(i64* ptr, i64 value) -> i64
        {
            i64 old;
            _exchange64(ptr, value, @old);
            return old;
        };

        // ============================================================
        //  Compare-and-Swap (CAS)
        // ============================================================

        def _cas32(i32* ptr, i32 expected, i32 desired, bool* out) -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rsi
                movq $3, %rdi
                movl $1, %eax
                movl $2, %ecx
                lock cmpxchgl %ecx, (%rsi)
                sete %al
                movb %al, (%rdi)
            } : : "r"(ptr), "r"(expected), "r"(desired), "r"(out) : "eax", "ecx", "rsi", "rdi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                mov   w0, #0
            .retry_cas32:
                ldaxr w4, [$0]
                cmp   w4, w1
                bne   .cas32_fail
                stlxr w4, w2, [$0]
                cbnz  w4, .retry_cas32
                mov   w0, #1
                b     .cas32_done
            .cas32_fail:
                clrex
            .cas32_done:
                strb  w0, [$3]
            } : : "r"(ptr), "r"(expected), "r"(desired), "r"(out) : "w0", "w4", "memory";
            #endif;
        };

        def _cas64(i64* ptr, i64 expected, i64 desired, bool* out) -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rsi
                movq $3, %rdi
                movq $1, %rax
                movq $2, %rcx
                lock cmpxchgq %rcx, (%rsi)
                sete %al
                movb %al, (%rdi)
            } : : "r"(ptr), "r"(expected), "r"(desired), "r"(out) : "rax", "rcx", "rsi", "rdi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                mov   w0, #0
            .retry_cas64:
                ldaxr x4, [$0]
                cmp   x4, x1
                bne   .cas64_fail
                stlxr w4, x2, [$0]
                cbnz  w4, .retry_cas64
                mov   w0, #1
                b     .cas64_done
            .cas64_fail:
                clrex
            .cas64_done:
                strb  w0, [$3]
            } : : "r"(ptr), "r"(expected), "r"(desired), "r"(out) : "x0", "x4", "memory";
            #endif;
        };

        // Atomically: if (*ptr == expected) { *ptr = desired; return true; }
        //             else { return false; }
        def cas32(i32* ptr, i32 expected, i32 desired) -> bool
        {
            bool success;
            _cas32(ptr, expected, desired, @success);
            return success;
        };

        def cas64(i64* ptr, i64 expected, i64 desired) -> bool
        {
            bool success;
            _cas64(ptr, expected, desired, @success);
            return success;
        };

        // ============================================================
        //  Atomic Fetch-and-Modify (read-modify-write)
        // ============================================================

        def _fetch_add32(i32* ptr, i32 delta, i32* out) -> void
        {
            #ifdef __ARCH_X86_64__
            // LOCK XADD: exchanges src and dst then adds. src gets old dst value.
            volatile asm
            {
                movq $0, %rsi
                movq $2, %rdi
                movl $1, %eax
                lock xaddl %eax, (%rsi)
                movl %eax, (%rdi)
            } : : "r"(ptr), "r"(delta), "r"(out) : "eax", "rsi", "rdi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
            .retry_fadd32:
                ldaxr w0, [$0]
                add   w3, w0, w1
                stlxr w4, w3, [$0]
                cbnz  w4, .retry_fadd32
                str   w0, [$2]
            } : : "r"(ptr), "r"(delta), "r"(out) : "w0", "w3", "w4", "memory";
            #endif;
        };

        def _fetch_add64(i64* ptr, i64 delta, i64* out) -> void
        {
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                movq $0, %rsi
                movq $2, %rdi
                movq $1, %rax
                lock xaddq %rax, (%rsi)
                movq %rax, (%rdi)
            } : : "r"(ptr), "r"(delta), "r"(out) : "rax", "rsi", "rdi", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
            .retry_fadd64:
                ldaxr x0, [$0]
                add   x3, x0, x1
                stlxr w4, x3, [$0]
                cbnz  w4, .retry_fadd64
                str   x0, [$2]
            } : : "r"(ptr), "r"(delta), "r"(out) : "x0", "x3", "w4", "memory";
            #endif;
        };

        // Atomically add delta to *ptr; returns the old value.
        def fetch_add32(i32* ptr, i32 delta) -> i32
        {
            i32 old;
            _fetch_add32(ptr, delta, @old);
            return old;
        };

        def fetch_add64(i64* ptr, i64 delta) -> i64
        {
            i64 old;
            _fetch_add64(ptr, delta, @old);
            return old;
        };

        // Atomically subtract delta from *ptr; returns the old value.
        def fetch_sub32(i32* ptr, i32 delta) -> i32
        {
            return fetch_add32(ptr, -delta);
        };

        def fetch_sub64(i64* ptr, i64 delta) -> i64
        {
            return fetch_add64(ptr, -delta);
        };

        // Atomically bitwise-AND *ptr with mask; returns the old value.
        def fetch_and32(i32* ptr, i32 mask) -> i32
        {
            i32 old, desired;
            do
            {
                old     = load32(ptr);
                desired = old `& mask;
            }
            while (!cas32(ptr, old, desired));
            return old;
        };

        def fetch_and64(i64* ptr, i64 mask) -> i64
        {
            i64 old, desired;
            do
            {
                old     = load64(ptr);
                desired = old `& mask;
            }
            while (!cas64(ptr, old, desired));
            return old;
        };

        // Atomically bitwise-OR *ptr with mask; returns the old value.
        def fetch_or32(i32* ptr, i32 mask) -> i32
        {
            i32 old;
            i32 desired;
            do
            {
                old     = load32(ptr);
                desired = old `| mask;
            }
            while (!cas32(ptr, old, desired));
            return old;
        };

        def fetch_or64(i64* ptr, i64 mask) -> i64
        {
            i64 old, desired;
            do
            {
                old     = load64(ptr);
                desired = old `| mask;
            }
            while (!cas64(ptr, old, desired));
            return old;
        };

        // Atomically bitwise-XOR *ptr with mask; returns the old value.
        def fetch_xor32(i32* ptr, i32 mask) -> i32
        {
            i32 old, desired;
            do
            {
                old     = load32(ptr);
                desired = old `^^ mask;
            }
            while (!cas32(ptr, old, desired));
            return old;
        };

        def fetch_xor64(i64* ptr, i64 mask) -> i64
        {
            i64 old, desired;
            do
            {
                old     = load64(ptr);
                desired = old `^^ mask;
            }
            while (!cas64(ptr, old, desired));
            return old;
        };

        // ============================================================
        //  Atomic Increment / Decrement
        // ============================================================

        // Atomically increment *ptr by 1; returns the NEW value.
        def inc32(i32* ptr) -> i32
        {
            return fetch_add32(ptr, 1) + 1;
        };

        def inc64(i64* ptr) -> i64
        {
            return fetch_add64(ptr, 1) + (i64)1;
        };

        // Atomically decrement *ptr by 1; returns the NEW value.
        def dec32(i32* ptr) -> i32
        {
            return fetch_sub32(ptr, 1) - 1;
        };

        def dec64(i64* ptr) -> i64
        {
            return fetch_sub64(ptr, 1) - (i64)1;
        };

        // ============================================================
        //  Spinlock
        //
        //  Usage:
        //      i32 lock = 0;
        //      standard::atomic::spin_lock(@lock);
        //      // ... critical section ...
        //      standard::atomic::spin_unlock(@lock);
        // ============================================================

        // Spin until we successfully exchange 0 -> 1 (acquire the lock).
        def spin_lock(i32* lock) -> void
        {
            while (exchange32(lock, 1) != 0)
            {
                #ifdef __ARCH_X86_64__
                volatile asm
                {
                    pause
                } : : : "memory";
                #endif;
                #ifdef __ARCH_ARM64__
                volatile asm
                {
                    yield
                } : : : "memory";
                #endif;
            };
            load_fence();
        };

        // Release the lock.
        def spin_unlock(i32* lock) -> void
        {
            store_fence();
            store32(lock, 0);
        };

        // Try to acquire without spinning; returns true on success.
        def spin_trylock(i32* lock) -> bool
        {
            return exchange32(lock, 1) == 0;
        };

        // ============================================================
        //  Once Flag
        //
        //  Usage:
        //      i32 flag = 0;
        //      if (standard::atomic::once_begin(@flag))
        //      {
        //          // ... initialization ...
        //          standard::atomic::once_end(@flag);
        //      };
        // ============================================================

        // Returns true if this thread wins the right to initialize.
        // Flag transitions: 0 (uninitialized) -> 1 (in progress) -> 2 (done)
        def once_begin(i32* flag) -> bool
        {
            if (load32(flag) == 2)
            {
                load_fence();
                return false;
            };
            return cas32(flag, 0, 1);
        };

        // Called by the winning thread after initialization is complete.
        def once_end(i32* flag) -> void
        {
            store_fence();
            store32(flag, 2);
        };

        // ============================================================
        //  Atomic Reference Counter
        //
        //  ref_dec_and_test returns true when count reaches zero,
        //  signaling the caller should free the resource.
        // ============================================================

        def ref_inc(i32* counter) -> void
        {
            fetch_add32(counter, 1);
        };

        def ref_dec_and_test(i32* counter) -> bool
        {
            return fetch_sub32(counter, 1) == 1;
        };

        def ref_get(i32* counter) -> i32
        {
            return load32(counter);
        };

        // ============================================================
        //  Atomic Flag
        //
        //  Usage:
        //      i32 flag = 0;
        //      standard::atomic::flag_set(@flag);
        //      if (standard::atomic::flag_test(@flag)) { ... };
        //      standard::atomic::flag_clear(@flag);
        // ============================================================

        def flag_set(i32* flag) -> void
        {
            store32(flag, 1);
        };

        def flag_clear(i32* flag) -> void
        {
            store32(flag, 0);
        };

        def flag_test(i32* flag) -> bool
        {
            return load32(flag) != 0;
        };

        // Test-and-set: atomically sets the flag; returns the OLD value.
        def flag_test_and_set(i32* flag) -> bool
        {
            return exchange32(flag, 1) != 0;
        };
    };
};

using standard::atomic;

#endif;
