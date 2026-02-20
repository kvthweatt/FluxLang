// redthread.fx - Windows Threading Library
// Provides threads, mutexes, semaphores, condition variables, and
// thread-local storage using the Windows API.
// Windows only.

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_THREAD
#def FLUX_STANDARD_THREAD 1;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifdef __WINDOWS__

// ============ WIN32 FFI DECLARATIONS ============
extern
{
    def !!
        // Thread management
        CreateThread(void*, u64, void*, void*, u32, u32*) -> void*,
        ExitThread(u32) -> void,
        TerminateThread(void*, u32) -> bool,
        GetCurrentThread() -> void*,
        GetCurrentThreadId() -> u32,
        SuspendThread(void*) -> u32,
        ResumeThread(void*) -> u32,
        SetThreadPriority(void*, int) -> bool,
        GetThreadPriority(void*) -> int,
        GetExitCodeThread(void*, u32*) -> bool,

        // Wait & synchronization
        WaitForSingleObject(void*, u32) -> u32,
        WaitForMultipleObjects(u32, void**, bool, u32) -> u32,

        // Handle management
        CloseHandle(void*) -> bool,
        DuplicateHandle(void*, void*, void*, void**, u32, bool, u32) -> bool,

        // Critical section (non-recursive mutex, kernel-free fast path)
        InitializeCriticalSection(void*) -> void,
        InitializeCriticalSectionAndSpinCount(void*, u32) -> bool,
        DeleteCriticalSection(void*) -> void,
        EnterCriticalSection(void*) -> void,
        TryEnterCriticalSection(void*) -> bool,
        LeaveCriticalSection(void*) -> void,

        // Mutex (cross-process, recursive)
        CreateMutexA(void*, bool, byte*) -> void*,
        OpenMutexA(u32, bool, byte*) -> void*,
        ReleaseMutex(void*) -> bool,

        // Semaphore
        CreateSemaphoreA(void*, i32, i32, byte*) -> void*,
        OpenSemaphoreA(u32, bool, byte*) -> void*,
        ReleaseSemaphore(void*, i32, i32*) -> bool,

        // Event
        CreateEventA(void*, bool, bool, byte*) -> void*,
        OpenEventA(u32, bool, byte*) -> void*,
        SetEvent(void*) -> bool,
        ResetEvent(void*) -> bool,
        PulseEvent(void*) -> bool,

        // Condition variable (Vista+)
        InitializeConditionVariable(void*) -> void,
        SleepConditionVariableCS(void*, void*, u32) -> bool,
        WakeConditionVariable(void*) -> void,
        WakeAllConditionVariable(void*) -> void,

        // Thread-local storage
        TlsAlloc() -> u32,
        TlsFree(u32) -> bool,
        TlsGetValue(u32) -> void*,
        TlsSetValue(u32, void*) -> bool,

        // Interlocked (atomic) operations
        InterlockedIncrement(i32*) -> i32,
        InterlockedDecrement(i32*) -> i32,
        InterlockedAdd(i32*, i32) -> i32,
        InterlockedExchange(i32*, i32) -> i32,
        InterlockedCompareExchange(i32*, i32, i32) -> i32,
        InterlockedIncrement64(i64*) -> i64,
        InterlockedDecrement64(i64*) -> i64,
        InterlockedAdd64(i64*, i64) -> i64,
        InterlockedExchange64(i64*, i64) -> i64,
        InterlockedCompareExchange64(i64*, i64, i64) -> i64,

        // Utility
        Sleep(u32) -> void,
        SwitchToThread() -> bool,
        GetProcessHeap() -> void*,
        GetLastError() -> u32;
};

// ============ STRUCTS ============

// CRITICAL_SECTION is an opaque 40-byte structure on 64-bit Windows.
// We store it as a raw byte block; never inspect the fields directly.
struct CRITICAL_SECTION
{
    byte[40] _opaque;
};

// CONDITION_VARIABLE is an opaque pointer-sized structure (8 bytes on x64).
struct CONDITION_VARIABLE
{
    u64* _ptr;
};

// ============ CONSTANTS ============

namespace standard
{
    namespace thread
    {
        // WaitForSingleObject / WaitForMultipleObjects return values
        global const u32 WAIT_OBJECT_0   = 0x00000000u;
        global const u32 WAIT_ABANDONED  = 0x00000080u;
        global const u32 WAIT_TIMEOUT    = 0x00000102u;
        global const u32 WAIT_FAILED     = 0xFFFFFFFFu;

        // Infinite timeout sentinel
        global const u32 INFINITE        = 0xFFFFFFFFu;

        // Thread priority levels
        global const int PRIORITY_IDLE          = -15;
        global const int PRIORITY_LOWEST        = -2;
        global const int PRIORITY_BELOW_NORMAL  = -1;
        global const int PRIORITY_NORMAL        =  0;
        global const int PRIORITY_ABOVE_NORMAL  =  1;
        global const int PRIORITY_HIGHEST       =  2;
        global const int PRIORITY_TIME_CRITICAL =  15;

        // CreateThread flags
        global const u32 THREAD_CREATE_RUNNING   = 0x00000000u;
        global const u32 THREAD_CREATE_SUSPENDED = 0x00000004u;

        // TLS sentinel for invalid slot
        global const u32 TLS_OUT_OF_INDEXES = 0xFFFFFFFFu;

        // ============ THREAD ============

        object Thread
        {
            void* handle;
            u32   id;
            bool  running;

            // Create and immediately start a thread.
            // proc  : pointer to the thread function  (u32 fn(void*))
            // param : argument passed to proc
            def __init(void* proc, void* param) -> this
            {
                this.id      = (u32)0;
                this.running = false;
                this.handle  = CreateThread(
                    (void*)0,       // default security
                    (u64)0,         // default stack size
                    proc,
                    param,
                    THREAD_CREATE_RUNNING,
                    @this.id
                );
                if (this.handle != (void*)0)
                {
                    this.running = true;
                };
                return this;
            };

            // Create a thread, optionally suspended.
            def __init(void* proc, void* param, bool suspended) -> this
            {
                this.id      = (u32)0;
                this.running = false;
                u32 flags = suspended ? THREAD_CREATE_SUSPENDED : THREAD_CREATE_RUNNING;
                this.handle = CreateThread(
                    (void*)0,
                    (u64)0,
                    proc,
                    param,
                    flags,
                    @this.id
                );
                if (this.handle != (void*)0)
                {
                    this.running = !suspended;
                };
                return this;
            };

            def __exit() -> void
            {
                if (this.handle != (void*)0)
                {
                    CloseHandle(this.handle);
                    this.handle = (void*)0;
                };
                return;
            };

            // Block until the thread finishes (or timeout elapses).
            // Pass INFINITE to wait forever. Returns true if thread finished.
            def join(u32 timeout_ms) -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                u32 result = WaitForSingleObject(this.handle, timeout_ms);
                if (result == WAIT_OBJECT_0)
                {
                    this.running = false;
                    return true;
                };
                return false;
            };

            // Block until the thread finishes with no timeout.
            def join() -> bool
            {
                return this.join(INFINITE);
            };

            // Resume a suspended thread. Returns previous suspend count, -1 on error.
            def resume() -> u32
            {
                if (this.handle == (void*)0)
                {
                    return (u32)-1;
                };
                u32 prev = ResumeThread(this.handle);
                if (prev == (u32)1)
                {
                    this.running = true;
                };
                return prev;
            };

            // Suspend the thread. Returns previous suspend count, -1 on error.
            def suspend() -> u32
            {
                if (this.handle == (void*)0)
                {
                    return (u32)-1;
                };
                u32 prev = SuspendThread(this.handle);
                if (prev == (u32)0)
                {
                    this.running = false;
                };
                return prev;
            };

            // Forcibly terminate the thread. Use with caution.
            def terminate(u32 exit_code) -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                bool ok = TerminateThread(this.handle, exit_code);
                if (ok)
                {
                    this.running = false;
                };
                return ok;
            };

            // Set thread scheduling priority. Use PRIORITY_* constants.
            def set_priority(int priority) -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                return SetThreadPriority(this.handle, priority);
            };

            def get_priority() -> int
            {
                if (this.handle == (void*)0)
                {
                    return PRIORITY_NORMAL;
                };
                return GetThreadPriority(this.handle);
            };

            // Retrieve the thread exit code.
            // Only meaningful after the thread has finished.
            def exit_code() -> u32
            {
                u32 code = (u32)0;
                if (this.handle != (void*)0)
                {
                    GetExitCodeThread(this.handle, @code);
                };
                return code;
            };

            def is_running() -> bool
            {
                return this.running;
            };

            def get_id() -> u32
            {
                return this.id;
            };
        };

        // ============ MUTEX ============
        // Kernel-backed, cross-process capable, recursive mutex.
        // For intra-process locking prefer CriticalSection (lower overhead).

        object Mutex
        {
            void* handle;

            // Create an unnamed, initially-unlocked mutex.
            def __init() -> this
            {
                this.handle = CreateMutexA((void*)0, false, (byte*)0);
                return this;
            };

            // Create a named mutex. Pass null byte* for unnamed.
            def __init(byte* name) -> this
            {
                this.handle = CreateMutexA((void*)0, false, name);
                return this;
            };

            def __exit() -> void
            {
                if (this.handle != (void*)0)
                {
                    CloseHandle(this.handle);
                    this.handle = (void*)0;
                };
                return;
            };

            // Acquire the mutex. Blocks until available or timeout expires.
            // Returns true if lock was acquired.
            def lock(u32 timeout_ms) -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                u32 result = WaitForSingleObject(this.handle, timeout_ms);
                return result == WAIT_OBJECT_0 | result == WAIT_ABANDONED;
            };

            def lock() -> bool
            {
                return this.lock(INFINITE);
            };

            // Release the mutex.
            def unlock() -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                return ReleaseMutex(this.handle);
            };

            def is_valid() -> bool
            {
                return this.handle != (void*)0;
            };
        };

        // ============ CRITICAL SECTION ============
        // Lightweight intra-process mutex with kernel-free fast path.
        // Non-recursive by API contract but Windows allows re-entry by the same thread.

        object CriticalSection
        {
            CRITICAL_SECTION cs;
            bool initialized;

            def __init() -> this
            {
                this.initialized = false;
                InitializeCriticalSection(@this.cs);
                this.initialized = true;
                return this;
            };

            // Initialize with a spin count for extra performance on multi-core.
            def __init(u32 spin_count) -> this
            {
                this.initialized = false;
                InitializeCriticalSectionAndSpinCount(@this.cs, spin_count);
                this.initialized = true;
                return this;
            };

            def __exit() -> void
            {
                if (this.initialized)
                {
                    DeleteCriticalSection(@this.cs);
                    this.initialized = false;
                };
                return;
            };

            // Block until the critical section can be entered.
            def lock() -> void
            {
                if (this.initialized)
                {
                    EnterCriticalSection(@this.cs);
                };
                return;
            };

            // Try to enter without blocking.
            // Returns true if the critical section was successfully entered.
            def try_lock() -> bool
            {
                if (!this.initialized)
                {
                    return false;
                };
                return TryEnterCriticalSection(@this.cs);
            };

            def unlock() -> void
            {
                if (this.initialized)
                {
                    LeaveCriticalSection(@this.cs);
                };
                return;
            };

            def is_valid() -> bool
            {
                return this.initialized;
            };
        };

        // ============ SEMAPHORE ============

        object Semaphore
        {
            void* handle;

            // initial_count : starting signal count
            // max_count     : upper bound on count
            def __init(i32 initial_count, i32 max_count) -> this
            {
                this.handle = CreateSemaphoreA((void*)0, initial_count, max_count, (byte*)0);
                return this;
            };

            def __init(i32 initial_count, i32 max_count, byte* name) -> this
            {
                this.handle = CreateSemaphoreA((void*)0, initial_count, max_count, name);
                return this;
            };

            def __exit() -> void
            {
                if (this.handle != (void*)0)
                {
                    CloseHandle(this.handle);
                    this.handle = (void*)0;
                };
                return;
            };

            // Decrement (wait). Blocks until count > 0 or timeout expires.
            def wait(u32 timeout_ms) -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                return WaitForSingleObject(this.handle, timeout_ms) == WAIT_OBJECT_0;
            };

            def wait() -> bool
            {
                return this.wait(INFINITE);
            };

            // Increment (signal) by release_count. Previous count written to prev_count.
            def signal(i32 release_count, i32* prev_count) -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                return ReleaseSemaphore(this.handle, release_count, prev_count);
            };

            // Signal by 1.
            def signal() -> bool
            {
                i32 dummy = 0;
                return this.signal((i32)1, @dummy);
            };

            def is_valid() -> bool
            {
                return this.handle != (void*)0;
            };
        };

        // ============ EVENT ============

        object Event
        {
            void* handle;

            // manual_reset : if true the event stays signalled until ResetEvent is called
            // initial_state: initial signal state
            def __init(bool manual_reset, bool initial_state) -> this
            {
                this.handle = CreateEventA((void*)0, manual_reset, initial_state, (byte*)0);
                return this;
            };

            def __init(bool manual_reset, bool initial_state, byte* name) -> this
            {
                this.handle = CreateEventA((void*)0, manual_reset, initial_state, name);
                return this;
            };

            def __exit() -> void
            {
                if (this.handle != (void*)0)
                {
                    CloseHandle(this.handle);
                    this.handle = (void*)0;
                };
                return;
            };

            // Wait for the event to become signalled.
            def wait(u32 timeout_ms) -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                return WaitForSingleObject(this.handle, timeout_ms) == WAIT_OBJECT_0;
            };

            def wait() -> bool
            {
                return this.wait(INFINITE);
            };

            // Signal the event (wake waiters).
            def set() -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                return SetEvent(this.handle);
            };

            // Clear the signal (for manual-reset events).
            def reset() -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                return ResetEvent(this.handle);
            };

            // Signal briefly then immediately reset (pulse).
            def pulse() -> bool
            {
                if (this.handle == (void*)0)
                {
                    return false;
                };
                return PulseEvent(this.handle);
            };

            def is_valid() -> bool
            {
                return this.handle != (void*)0;
            };
        };

        // ============ CONDITION VARIABLE ============
        // Must be used together with a CriticalSection.

        object ConditionVariable
        {
            CONDITION_VARIABLE cv;

            def __init() -> this
            {
                InitializeConditionVariable(@this.cv);
                return this;
            };

            // Atomically release the critical section and block until signalled
            // (or timeout_ms elapses). The critical section must be held on entry
            // and will be re-acquired before returning.
            // Returns true if woken by a signal, false on timeout.
            def wait(CriticalSection* cs, u32 timeout_ms) -> bool
            {
                return SleepConditionVariableCS(@this.cv, @cs.cs, timeout_ms);
            };

            def wait(CriticalSection* cs) -> bool
            {
                return this.wait(cs, INFINITE);
            };

            // Wake one waiting thread.
            def notify_one() -> void
            {
                WakeConditionVariable(@this.cv);
                return;
            };

            // Wake all waiting threads.
            def notify_all() -> void
            {
                WakeAllConditionVariable(@this.cv);
                return;
            };
        };

        // ============ THREAD-LOCAL STORAGE ============

        object ThreadLocal
        {
            u32 slot;

            // Allocate a TLS slot.
            def __init() -> this
            {
                this.slot = TlsAlloc();
                return this;
            };

            def __exit() -> void
            {
                if (this.slot != TLS_OUT_OF_INDEXES)
                {
                    TlsFree(this.slot);
                    this.slot = TLS_OUT_OF_INDEXES;
                };
                return;
            };

            // Store a per-thread value.
            def set(void* value) -> bool
            {
                if (this.slot == TLS_OUT_OF_INDEXES)
                {
                    return false;
                };
                return TlsSetValue(this.slot, value);
            };

            // Retrieve the value stored by the calling thread.
            def get() -> void*
            {
                if (this.slot == TLS_OUT_OF_INDEXES)
                {
                    return (void*)0;
                };
                return TlsGetValue(this.slot);
            };

            def is_valid() -> bool
            {
                return this.slot != TLS_OUT_OF_INDEXES;
            };
        };

        // ============ ATOMIC OPERATIONS ============
        // Thin wrappers around Windows Interlocked intrinsics.

        namespace atomic
        {
            def increment(i32* value) -> i32
            {
                return InterlockedIncrement(value);
            };

            def decrement(i32* value) -> i32
            {
                return InterlockedDecrement(value);
            };

            def add(i32* value, i32 addend) -> i32
            {
                return InterlockedAdd(value, addend);
            };

            // Swap value with replacement, return old value.
            def exchange(i32* target, i32 replacement) -> i32
            {
                return InterlockedExchange(target, replacement);
            };

            // If *target == comparand, set *target = replacement.
            // Returns the original value of *target.
            def compare_exchange(i32* target, i32 replacement, i32 comparand) -> i32
            {
                return InterlockedCompareExchange(target, replacement, comparand);
            };

            def increment64(i64* value) -> i64
            {
                return InterlockedIncrement64(value);
            };

            def decrement64(i64* value) -> i64
            {
                return InterlockedDecrement64(value);
            };

            def add64(i64* value, i64 addend) -> i64
            {
                return InterlockedAdd64(value, addend);
            };

            def exchange64(i64* target, i64 replacement) -> i64
            {
                return InterlockedExchange64(target, replacement);
            };

            def compare_exchange64(i64* target, i64 replacement, i64 comparand) -> i64
            {
                return InterlockedCompareExchange64(target, replacement, comparand);
            };
        };

        // ============ UTILITY FUNCTIONS ============

        // Sleep the calling thread for the given number of milliseconds.
        def sleep(u32 milliseconds) -> void
        {
            Sleep(milliseconds);
            return;
        };

        // Yield the remainder of the calling thread's time slice.
        def yield() -> bool
        {
            return SwitchToThread();
        };

        // Return the calling thread's Win32 ID.
        def current_id() -> u32
        {
            return GetCurrentThreadId();
        };

        // Return a pseudo-handle to the calling thread (no CloseHandle needed).
        def current_handle() -> void*
        {
            return GetCurrentThread();
        };

        // Wait for up to 64 handles at once.
        // Returns the index of the signalled handle, or WAIT_TIMEOUT / WAIT_FAILED.
        def wait_any(void** handles, u32 count, u32 timeout_ms) -> u32
        {
            u32 result = WaitForMultipleObjects(count, handles, false, timeout_ms);
            return result;
        };

        // Wait until ALL handles are signalled.
        def wait_all(void** handles, u32 count, u32 timeout_ms) -> bool
        {
            u32 result = WaitForMultipleObjects(count, handles, true, timeout_ms);
            return result == WAIT_OBJECT_0;
        };
    };
};

using standard::thread;
using standard::thread::atomic;

#endif; // __WINDOWS__
#endif; // FLUX_STANDARD_THREAD
