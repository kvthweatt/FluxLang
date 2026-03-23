// redthreading.fx - Threading Library
// Provides platform-level thread creation, synchronization primitives,
// and thread-local utilities built on top of redatomics.fx.
//
// Supported platforms: Windows, Linux, macOS (ARM64/x86-64)
//
// Features:
//   - Thread creation and joining (pthreads / Win32)
//   - Mutex  (blocking mutual exclusion)
//   - R/W Lock (multiple readers, exclusive writer)
//   - Condition variable (wait / signal / broadcast)
//   - Semaphore (counting and binary)
//   - Barrier  (rendezvous point for N threads)
//   - Thread-local storage key (pthreads / Win32 TLS)
//   - Thread ID and yield helpers

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_ATOMICS
#import "atomics.fx";
#endif;

#ifndef FLUX_STANDARD_THREADING
#def FLUX_STANDARD_THREADING 1;

// ============================================================
//  Platform FFI
// ============================================================

#ifdef __WINDOWS__

// Win32 thread/sync API surface used by this library.
extern
{
    def !!
        // Threads
        CreateThread(void*, size_t, void*, void*, u32, u32*) -> void*,
        WaitForSingleObject(void*, u32) -> u32,
        CloseHandle(void*) -> int,
        GetCurrentThreadId() -> u32,
        SwitchToThread() -> int,
        Sleep(u32) -> void,
        ExitThread(u32) -> void,

        // Critical section (kernel-backed mutex)
        InitializeCriticalSection(void*) -> void,
        DeleteCriticalSection(void*) -> void,
        EnterCriticalSection(void*) -> void,
        LeaveCriticalSection(void*) -> void,
        TryEnterCriticalSection(void*) -> int,

        // Slim Reader/Writer Lock
        InitializeSRWLock(void*) -> void,
        AcquireSRWLockExclusive(void*) -> void,
        ReleaseSRWLockExclusive(void*) -> void,
        AcquireSRWLockShared(void*) -> void,
        ReleaseSRWLockShared(void*) -> void,
        TryAcquireSRWLockExclusive(void*) -> int,
        TryAcquireSRWLockShared(void*) -> int,

        // Condition variable
        InitializeConditionVariable(void*) -> void,
        SleepConditionVariableCS(void*, void*, u32) -> int,
        WakeConditionVariable(void*) -> void,
        WakeAllConditionVariable(void*) -> void,

        // Semaphore
        CreateSemaphoreA(void*, i32, i32, void*) -> void*,
        ReleaseSemaphore(void*, i32, i32*) -> int,

        // Thread-local storage
        TlsAlloc() -> u32,
        TlsFree(u32) -> int,
        TlsGetValue(u32) -> void*,
        TlsSetValue(u32, void*) -> int;
};

// INFINITE timeout constant for WaitForSingleObject
global const u32 WIN32_INFINITE = 0xFFFFFFFF;

#endif; // __WINDOWS__

#ifdef __LINUX__

// POSIX pthreads and semaphore API surface.
extern
{
    def !!
        // Threads
        pthread_create(void*, void*, void*, void*) -> int,
        pthread_join(void*, void**) -> int,
        pthread_self() -> u64,
        pthread_yield() -> int,
        pthread_exit(void*) -> void,
        sched_yield() -> int,

        // Mutex
        pthread_mutex_init(void*, void*) -> int,
        pthread_mutex_destroy(void*) -> int,
        pthread_mutex_lock(void*) -> int,
        pthread_mutex_unlock(void*) -> int,
        pthread_mutex_trylock(void*) -> int,

        // R/W lock
        pthread_rwlock_init(void*, void*) -> int,
        pthread_rwlock_destroy(void*) -> int,
        pthread_rwlock_rdlock(void*) -> int,
        pthread_rwlock_wrlock(void*) -> int,
        pthread_rwlock_unlock(void*) -> int,
        pthread_rwlock_tryrdlock(void*) -> int,
        pthread_rwlock_trywrlock(void*) -> int,

        // Condition variable
        pthread_cond_init(void*, void*) -> int,
        pthread_cond_destroy(void*) -> int,
        pthread_cond_wait(void*, void*) -> int,
        pthread_cond_timedwait(void*, void*, void*) -> int,
        pthread_cond_signal(void*) -> int,
        pthread_cond_broadcast(void*) -> int,

        // POSIX semaphore
        sem_init(void*, int, u32) -> int,
        sem_destroy(void*) -> int,
        sem_wait(void*) -> int,
        sem_post(void*) -> int,
        sem_trywait(void*) -> int,
        sem_getvalue(void*, int*) -> int,

        // Thread-local storage keys
        pthread_key_create(void*, void*) -> int,
        pthread_key_delete(u64) -> int,
        pthread_getspecific(u64) -> void*,
        pthread_setspecific(u64, void*) -> int,

        // Sleep
        nanosleep(void*, void*) -> int;
};

#endif; // __LINUX__

#ifdef __MACOS__

// macOS uses pthreads - identical extern block to Linux.
extern
{
    def !!
        pthread_create(void*, void*, void*, void*) -> int,
        pthread_join(void*, void**) -> int,
        pthread_self() -> u64,
        pthread_yield_np() -> void,
        pthread_exit(void*) -> void,
        sched_yield() -> int,

        pthread_mutex_init(void*, void*) -> int,
        pthread_mutex_destroy(void*) -> int,
        pthread_mutex_lock(void*) -> int,
        pthread_mutex_unlock(void*) -> int,
        pthread_mutex_trylock(void*) -> int,

        pthread_rwlock_init(void*, void*) -> int,
        pthread_rwlock_destroy(void*) -> int,
        pthread_rwlock_rdlock(void*) -> int,
        pthread_rwlock_wrlock(void*) -> int,
        pthread_rwlock_unlock(void*) -> int,
        pthread_rwlock_tryrdlock(void*) -> int,
        pthread_rwlock_trywrlock(void*) -> int,

        pthread_cond_init(void*, void*) -> int,
        pthread_cond_destroy(void*) -> int,
        pthread_cond_wait(void*, void*) -> int,
        pthread_cond_timedwait(void*, void*, void*) -> int,
        pthread_cond_signal(void*) -> int,
        pthread_cond_broadcast(void*) -> int,

        sem_init(void*, int, u32) -> int,
        sem_destroy(void*) -> int,
        sem_wait(void*) -> int,
        sem_post(void*) -> int,
        sem_trywait(void*) -> int,
        sem_getvalue(void*, int*) -> int,

        pthread_key_create(void*, void*) -> int,
        pthread_key_delete(u64) -> int,
        pthread_getspecific(u64) -> void*,
        pthread_setspecific(u64, void*) -> int,

        // Sleep
        nanosleep(void*, void*) -> int;
};

#endif; // __MACOS__

// ============================================================
//  Opaque storage sizes
//
//  We store OS objects in fixed-size byte arrays so this file
//  has no C header dependency.  Sizes are conservative upper
//  bounds that hold on both 32- and 64-bit builds.
//
//  Windows CRITICAL_SECTION : 40 bytes (x64)
//  Windows SRWLOCK          :  8 bytes
//  Windows CONDITION_VARIABLE:  8 bytes
//  pthreads mutex           : 48 bytes (Linux glibc x64)
//  pthreads rwlock          : 56 bytes (Linux glibc x64)
//  pthreads cond            : 48 bytes (Linux glibc x64)
//  POSIX sem_t              : 32 bytes (Linux)
//  pthread_t                :  8 bytes (pointer-sized)
//  pthread_key_t            :  8 bytes
// ============================================================

const int THREAD_OPAQUE_BYTES   = 8,   // Handle / pthread_t
          MUTEX_OPAQUE_BYTES    = 64,  // Covers all platforms
          RWLOCK_OPAQUE_BYTES   = 64,
          COND_OPAQUE_BYTES     = 64,
          SEM_OPAQUE_BYTES      = 32,
          TLS_KEY_OPAQUE_BYTES  = 8,
// ============================================================
//  Thread result / exit status constants
// ============================================================
          THREAD_OK      =  0,
          THREAD_ERROR   = -1,
          THREAD_TIMEOUT = -2;

// ============================================================
//  Structs
// ============================================================

// A joinable thread handle.
struct Thread
{
    byte[8]  handle;    // void* on Windows; pthread_t on POSIX
    i32      alive;     // 1 while thread is running, 0 after join/detach
};

// Blocking mutual-exclusion lock.
struct Mutex
{
    byte[64] storage;   // CRITICAL_SECTION or pthread_mutex_t
};

// Reader/writer lock.
struct RWLock
{
    byte[64] storage;   // SRWLOCK or pthread_rwlock_t
};

// Condition variable (always paired with a Mutex).
struct CondVar
{
    byte[64] storage;   // CONDITION_VARIABLE or pthread_cond_t
};

// Counting semaphore.
struct Semaphore
{
    // On Windows we store the HANDLE (a pointer) in the first 8 bytes.
    // On POSIX  we store the inline sem_t (up to 32 bytes).
    byte[32] storage;
};

// Barrier: blocks N threads until all have arrived.
struct Barrier
{
    i32 total,      // How many threads must arrive
        arrived,    // Atomic counter of arrivals
        phase,      // Atomic phase flip, prevents reuse races
        _pad;       // Alignment
};

// Thread-local storage key.
struct TLSKey
{
    byte[8] key;    // DWORD on Windows (4 bytes, padded); pthread_key_t on POSIX
};


// ============================================================
//  Namespace
// ============================================================

namespace standard
{
    namespace threading
    {
        // ====================================================
        //  Internal helpers
        // ====================================================

        // Interpret the first sizeof(void*) bytes of an opaque array
        // as a void pointer.  Used to recover Win32 HANDLEs.
        // Cast through u64 to avoid the compiler emitting an extra
        // pointer dereference when reading/writing through void**.
        def _ptr_from_bytes(byte* storage) -> void*
        {
            u64* ip = (u64*)storage;
            return (void*)*ip;
        };

        def _store_ptr(byte* storage, void* ptr) -> void
        {
            u64* ip = (u64*)storage;
            *ip = (u64)ptr;
        };

        // ====================================================
        //  Thread
        // ====================================================

        // Spawn a new thread.
        //   fn   - function pointer with signature: def fn(void*) -> void*
        //   arg  - opaque argument forwarded to fn
        //   out  - Thread struct to fill
        // Returns THREAD_OK on success, THREAD_ERROR on failure.
        def thread_create(void* fn, void* arg, Thread* out) -> int
        {
            store32(@out.alive, 1);

            #ifdef __WINDOWS__
            void* h = CreateThread(
                (void*)0,       // default security
                0,              // default stack size
                (void*)fn,      // thread function
                arg,            // argument
                0,              // run immediately
                (u32*)0         // don't need thread ID
            );
            if ((u64)h == (u64)0)
            {
                store32(@out.alive, 0);
                return THREAD_ERROR;
            };
            _store_ptr(@out.handle[0], h);
            return THREAD_OK;
            #endif;

            #ifdef __LINUX__
            void* tid_storage = (void*)@out.handle[0];
            int rc = pthread_create(tid_storage, (void*)0, (void*)fn, arg);
            if (rc != 0)
            {
                store32(@out.alive, 0);
                return THREAD_ERROR;
            };
            return THREAD_OK;
            #endif;

            #ifdef __MACOS__
            void* tid_storage = (void*)@out.handle[0];
            int rc = pthread_create(tid_storage, (void*)0, (void*)fn, arg);
            if (rc != 0)
            {
                store32(@out.alive, 0);
                return THREAD_ERROR;
            };
            return THREAD_OK;
            #endif;
        };

        // Block the calling thread until the target thread finishes.
        // Returns THREAD_OK or THREAD_ERROR.
        def thread_join(Thread* t) -> int
        {
            if (load32(@t.alive) == 0)
            {
                return THREAD_OK;
            };

            #ifdef __WINDOWS__
            void* h = _ptr_from_bytes(@t.handle[0]);
            u32 rc = WaitForSingleObject(h, WIN32_INFINITE);
            CloseHandle(h);
            store32(@t.alive, 0);
            return rc == (u32)0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __LINUX__
            void* tid_storage = (void*)@t.handle[0];
            void** no_retval = (void**)0;
            int rc = pthread_join(_ptr_from_bytes(tid_storage), no_retval);
            store32(@t.alive, 0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __MACOS__
            void* tid_storage = (void*)@t.handle[0];
            void** no_retval = (void**)0;
            int rc = pthread_join(_ptr_from_bytes(tid_storage), no_retval);
            store32(@t.alive, 0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;
        };

        // Returns the platform thread ID of the calling thread.
        def thread_id() -> u64
        {
            #ifdef __WINDOWS__
            return (u64)GetCurrentThreadId();
            #endif;

            #ifdef __LINUX__
            return (u64)pthread_self();
            #endif;

            #ifdef __MACOS__
            return (u64)pthread_self();
            #endif;
        };

        // Yield the remainder of this thread's time-slice.
        def thread_yield() -> void
        {
            #ifdef __WINDOWS__
            SwitchToThread();
            #endif;

            #ifdef __LINUX__
            sched_yield();
            #endif;

            #ifdef __MACOS__
            sched_yield();
            #endif;
        };

        // Sleep for approximately ms milliseconds.
        def thread_sleep_ms(u32 ms) -> void
        {
            #ifdef __WINDOWS__
            Sleep(ms);
            #endif;

            #ifdef __LINUX__
            // Build a timespec in a local byte buffer and call nanosleep.
            // timespec layout: tv_sec (i64) at offset 0, tv_nsec (i64) at offset 8.
            i64 tv_sec  = (i64)(ms / 1000),
                tv_nsec = (i64)((ms % 1000) * 1000000);
            byte[16] ts;
            i64* sec_ptr  = (i64*)@ts[0];
            i64* nsec_ptr = (i64*)@ts[8];
            *sec_ptr  = tv_sec;
            *nsec_ptr = tv_nsec;
            nanosleep((void*)@ts[0], (void*)0);
            #endif; // __LINUX__

            #ifdef __MACOS__
            // Build a timespec in a local byte buffer and call nanosleep.
            // timespec layout: tv_sec (i64) at offset 0, tv_nsec (i64) at offset 8.
            i64 tv_sec  = (i64)(ms / 1000),
                tv_nsec = (i64)((ms % 1000) * 1000000);
            byte[16] ts;
            i64* sec_ptr  = (i64*)@ts[0];
            i64* nsec_ptr = (i64*)@ts[8];
            *sec_ptr  = tv_sec;
            *nsec_ptr = tv_nsec;
            nanosleep((void*)@ts[0], (void*)0);
            #endif; // __MACOS__
        };

        // ====================================================
        //  Mutex
        // ====================================================

        // Initialize a Mutex.  Must be called before any other mutex operation.
        def mutex_init(Mutex* m) -> int
        {
            #ifdef __WINDOWS__
            InitializeCriticalSection((void*)@m.storage[0]);
            return THREAD_OK;
            #endif;

            #ifdef __LINUX__
            int rc = pthread_mutex_init((void*)@m.storage[0], (void*)0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = pthread_mutex_init((void*)@m.storage[0], (void*)0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;
        };

        // Destroy a Mutex.
        def mutex_destroy(Mutex* m) -> void
        {
            #ifdef __WINDOWS__
            DeleteCriticalSection((void*)@m.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_mutex_destroy((void*)@m.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_mutex_destroy((void*)@m.storage[0]);
            #endif;
        };

        // Block until the mutex is acquired.
        def mutex_lock(Mutex* m) -> void
        {
            #ifdef __WINDOWS__
            EnterCriticalSection((void*)@m.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_mutex_lock((void*)@m.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_mutex_lock((void*)@m.storage[0]);
            #endif;
        };

        // Release a previously acquired mutex.
        def mutex_unlock(Mutex* m) -> void
        {
            #ifdef __WINDOWS__
            LeaveCriticalSection((void*)@m.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_mutex_unlock((void*)@m.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_mutex_unlock((void*)@m.storage[0]);
            #endif;
        };

        // Try to acquire without blocking.  Returns true on success.
        def mutex_trylock(Mutex* m) -> bool
        {
            #ifdef __WINDOWS__
            return TryEnterCriticalSection((void*)@m.storage[0]) != 0;
            #endif;

            #ifdef __LINUX__
            return pthread_mutex_trylock((void*)@m.storage[0]) == 0;
            #endif;

            #ifdef __MACOS__
            return pthread_mutex_trylock((void*)@m.storage[0]) == 0;
            #endif;
        };

        // ====================================================
        //  Reader/Writer Lock
        // ====================================================

        def rwlock_init(RWLock* rw) -> int
        {
            #ifdef __WINDOWS__
            InitializeSRWLock((void*)@rw.storage[0]);
            return THREAD_OK;
            #endif;

            #ifdef __LINUX__
            int rc = pthread_rwlock_init((void*)@rw.storage[0], (void*)0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = pthread_rwlock_init((void*)@rw.storage[0], (void*)0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;
        };

        def rwlock_destroy(RWLock* rw) -> void
        {
            #ifdef __WINDOWS__
            // SRWLock has no destroy call on Windows.
            #endif;

            #ifdef __LINUX__
            pthread_rwlock_destroy((void*)@rw.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_rwlock_destroy((void*)@rw.storage[0]);
            #endif;
        };

        // Acquire a shared (read) lock.
        def rwlock_read_lock(RWLock* rw) -> void
        {
            #ifdef __WINDOWS__
            AcquireSRWLockShared((void*)@rw.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_rwlock_rdlock((void*)@rw.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_rwlock_rdlock((void*)@rw.storage[0]);
            #endif;
        };

        // Release a shared (read) lock.
        def rwlock_read_unlock(RWLock* rw) -> void
        {
            #ifdef __WINDOWS__
            ReleaseSRWLockShared((void*)@rw.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_rwlock_unlock((void*)@rw.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_rwlock_unlock((void*)@rw.storage[0]);
            #endif;
        };

        // Acquire an exclusive (write) lock.
        def rwlock_write_lock(RWLock* rw) -> void
        {
            #ifdef __WINDOWS__
            AcquireSRWLockExclusive((void*)@rw.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_rwlock_wrlock((void*)@rw.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_rwlock_wrlock((void*)@rw.storage[0]);
            #endif;
        };

        // Release an exclusive (write) lock.
        def rwlock_write_unlock(RWLock* rw) -> void
        {
            #ifdef __WINDOWS__
            ReleaseSRWLockExclusive((void*)@rw.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_rwlock_unlock((void*)@rw.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_rwlock_unlock((void*)@rw.storage[0]);
            #endif;
        };

        // Try to acquire a shared lock without blocking.
        def rwlock_try_read_lock(RWLock* rw) -> bool
        {
            #ifdef __WINDOWS__
            return TryAcquireSRWLockShared((void*)@rw.storage[0]) != 0;
            #endif;

            #ifdef __LINUX__
            return pthread_rwlock_tryrdlock((void*)@rw.storage[0]) == 0;
            #endif;

            #ifdef __MACOS__
            return pthread_rwlock_tryrdlock((void*)@rw.storage[0]) == 0;
            #endif;
        };

        // Try to acquire an exclusive lock without blocking.
        def rwlock_try_write_lock(RWLock* rw) -> bool
        {
            #ifdef __WINDOWS__
            return TryAcquireSRWLockExclusive((void*)@rw.storage[0]) != 0;
            #endif;

            #ifdef __LINUX__
            return pthread_rwlock_trywrlock((void*)@rw.storage[0]) == 0;
            #endif;

            #ifdef __MACOS__
            return pthread_rwlock_trywrlock((void*)@rw.storage[0]) == 0;
            #endif;
        };

        // ====================================================
        //  Condition Variable
        // ====================================================

        def condvar_init(CondVar* cv) -> int
        {
            #ifdef __WINDOWS__
            InitializeConditionVariable((void*)@cv.storage[0]);
            return THREAD_OK;
            #endif;

            #ifdef __LINUX__
            int rc = pthread_cond_init((void*)@cv.storage[0], (void*)0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = pthread_cond_init((void*)@cv.storage[0], (void*)0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;
        };

        def condvar_destroy(CondVar* cv) -> void
        {
            #ifdef __WINDOWS__
            // Windows CONDITION_VARIABLE has no destroy call.
            #endif;

            #ifdef __LINUX__
            pthread_cond_destroy((void*)@cv.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_cond_destroy((void*)@cv.storage[0]);
            #endif;
        };

        // Atomically release the mutex and wait for a signal.
        // The mutex must be held by the calling thread on entry.
        // On return the mutex is held again.
        def condvar_wait(CondVar* cv, Mutex* m) -> void
        {
            #ifdef __WINDOWS__
            SleepConditionVariableCS(
                (void*)@cv.storage[0],
                (void*)@m.storage[0],
                WIN32_INFINITE
            );
            #endif;

            #ifdef __LINUX__
            pthread_cond_wait(
                (void*)@cv.storage[0],
                (void*)@m.storage[0]
            );
            #endif;

            #ifdef __MACOS__
            pthread_cond_wait(
                (void*)@cv.storage[0],
                (void*)@m.storage[0]
            );
            #endif;
        };

        // Wait with a millisecond timeout.
        // Returns THREAD_OK on signal, THREAD_TIMEOUT on expiry.
        def condvar_wait_ms(CondVar* cv, Mutex* m, u32 ms) -> int
        {
            #ifdef __WINDOWS__
            int ok = SleepConditionVariableCS(
                (void*)@cv.storage[0],
                (void*)@m.storage[0],
                ms
            );
            return ok != 0 ? THREAD_OK : THREAD_TIMEOUT;
            #endif;

            // POSIX timed wait uses an absolute timespec.
            // We build one from a relative ms delta via inline asm.
            #ifdef __LINUX__
            // clock_gettime(CLOCK_REALTIME=0, &ts) then add ms.
            i64 ts_sec, ts_nsec;
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                lea  rdi, [rsp - 16]
                xor  edi, edi
                mov  rsi, rdi
                mov  rax, 228
                syscall
                lea  rdi, [rsp - 16]
                mov  $0, [rdi]
                mov  $1, [rdi + 8]
            } : "=r"(ts_sec), "=r"(ts_nsec) : : "rax", "rdi", "rsi", "rcx", "r11", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                sub  sp, sp, #16
                mov  x0, #0
                mov  x1, sp
                mov  x8, #113
                svc  #0
                ldr  $0, [sp]
                ldr  $1, [sp, #8]
                add  sp, sp, #16
            } : "=r"(ts_sec), "=r"(ts_nsec) : : "x0", "x1", "x8", "memory";
            #endif;
            ts_nsec = ts_nsec + ((i64)(ms % (u32)1000) * (i64)1000000);
            ts_sec  = ts_sec  +  (i64)(ms / (u32)1000);
            if (ts_nsec >= (i64)1000000000)
            {
                ts_sec++;
                ts_nsec = ts_nsec - (i64)1000000000;
            };
            // Build timespec on the stack and call pthread_cond_timedwait.
            // We pass a pointer to a local [sec, nsec] pair.
            i64[2] ts = [ts_sec, ts_nsec];
            int rc = pthread_cond_timedwait(
                (void*)@cv.storage[0],
                (void*)@m.storage[0],
                (void*)@ts[0]
            );
            return rc == 0 ? THREAD_OK : THREAD_TIMEOUT;
            #endif;

            #ifdef __MACOS__
            i64 ts_sec, ts_nsec;
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                xor  edi, edi
                lea  rsi, [rsp - 16]
                mov  rax, 0x20000A9
                syscall
                lea  rdi, [rsp - 16]
                mov  $0, [rdi]
                mov  $1, [rdi + 8]
            } : "=r"(ts_sec), "=r"(ts_nsec) : : "rax", "rdi", "rsi", "rcx", "r11", "memory";
            #endif;
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                sub  sp, sp, #16
                mov  x0, #0
                mov  x1, sp
                mov  x16, #0x20000A9
                svc  #0x80
                ldr  $0, [sp]
                ldr  $1, [sp, #8]
                add  sp, sp, #16
            } : "=r"(ts_sec), "=r"(ts_nsec) : : "x0", "x1", "x16", "memory";
            #endif;
            ts_nsec = ts_nsec + ((i64)(ms % (u32)1000) * (i64)1000000);
            ts_sec  = ts_sec  +  (i64)(ms / (u32)1000);
            if (ts_nsec >= (i64)1000000000)
            {
                ts_sec++;
                ts_nsec = ts_nsec - (i64)1000000000;
            };
            i64[2] ts = [ts_sec, ts_nsec];
            int rc = pthread_cond_timedwait(
                (void*)@cv.storage[0],
                (void*)@m.storage[0],
                (void*)@ts[0]
            );
            return rc == 0 ? THREAD_OK : THREAD_TIMEOUT;
            #endif;
        };

        // Wake one waiting thread.
        def condvar_signal(CondVar* cv) -> void
        {
            #ifdef __WINDOWS__
            WakeConditionVariable((void*)@cv.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_cond_signal((void*)@cv.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_cond_signal((void*)@cv.storage[0]);
            #endif;
        };

        // Wake all waiting threads.
        def condvar_broadcast(CondVar* cv) -> void
        {
            #ifdef __WINDOWS__
            WakeAllConditionVariable((void*)@cv.storage[0]);
            #endif;

            #ifdef __LINUX__
            pthread_cond_broadcast((void*)@cv.storage[0]);
            #endif;

            #ifdef __MACOS__
            pthread_cond_broadcast((void*)@cv.storage[0]);
            #endif;
        };

        // ====================================================
        //  Semaphore
        // ====================================================

        // Initialize a counting semaphore with an initial value.
        def semaphore_init(Semaphore* s, i32 initial_value) -> int
        {
            #ifdef __WINDOWS__
            void* h = CreateSemaphoreA(
                (void*)0,       // default security
                initial_value,  // initial count
                0x7FFFFFFF,     // max count (INT_MAX)
                (void*)0        // unnamed
            );
            if ((u64)h == (u64)0)
            {
                return THREAD_ERROR;
            };
            _store_ptr(@s.storage[0], h);
            return THREAD_OK;
            #endif;

            #ifdef __LINUX__
            int rc = sem_init((void*)@s.storage[0], 0, (u32)initial_value);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = sem_init((void*)@s.storage[0], 0, (u32)initial_value);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;
        };

        // Destroy a semaphore.
        def semaphore_destroy(Semaphore* s) -> void
        {
            #ifdef __WINDOWS__
            void* h = _ptr_from_bytes(@s.storage[0]);
            CloseHandle(h);
            #endif;

            #ifdef __LINUX__
            sem_destroy((void*)@s.storage[0]);
            #endif;

            #ifdef __MACOS__
            sem_destroy((void*)@s.storage[0]);
            #endif;
        };

        // Decrement (wait / P-operation).  Blocks if count == 0.
        def semaphore_wait(Semaphore* s) -> void
        {
            #ifdef __WINDOWS__
            void* h = _ptr_from_bytes(@s.storage[0]);
            WaitForSingleObject(h, WIN32_INFINITE);
            #endif;

            #ifdef __LINUX__
            sem_wait((void*)@s.storage[0]);
            #endif;

            #ifdef __MACOS__
            sem_wait((void*)@s.storage[0]);
            #endif;
        };

        // Non-blocking decrement.  Returns true if decremented.
        def semaphore_trywait(Semaphore* s) -> bool
        {
            #ifdef __WINDOWS__
            void* h = _ptr_from_bytes(@s.storage[0]);
            return WaitForSingleObject(h, 0) == (u32)0;
            #endif;

            #ifdef __LINUX__
            return sem_trywait((void*)@s.storage[0]) == 0;
            #endif;

            #ifdef __MACOS__
            return sem_trywait((void*)@s.storage[0]) == 0;
            #endif;
        };

        // Increment (signal / V-operation).
        def semaphore_post(Semaphore* s) -> void
        {
            #ifdef __WINDOWS__
            void* h = _ptr_from_bytes(@s.storage[0]);
            ReleaseSemaphore(h, 1, (i32*)0);
            #endif;

            #ifdef __LINUX__
            sem_post((void*)@s.storage[0]);
            #endif;

            #ifdef __MACOS__
            sem_post((void*)@s.storage[0]);
            #endif;
        };

        // Read the current count without blocking.
        def semaphore_value(Semaphore* s) -> int
        {
            #ifdef __WINDOWS__
            // Win32 has no direct "peek" call; return -1 to signal unsupported.
            return -1;
            #endif;

            #ifdef __LINUX__
            int val = 0;
            sem_getvalue((void*)@s.storage[0], @val);
            return val;
            #endif;

            #ifdef __MACOS__
            int val = 0;
            sem_getvalue((void*)@s.storage[0], @val);
            return val;
            #endif;
        };

        // ====================================================
        //  Barrier
        // ====================================================

        // Initialize a barrier for `n` threads.
        def barrier_init(Barrier* b, i32 n) -> void
        {
            store32(@b.total,   n);
            store32(@b.arrived, 0);
            store32(@b.phase,   0);
        };

        // Each thread calls this.  The last arrival unblocks all.
        // Spins until the barrier releases - suitable for short waits.
        // Returns true only for the thread that was the last to arrive.
        def barrier_wait(Barrier* b) -> bool
        {
            i32 current_phase = load32(@b.phase),
                arrived = inc32(@b.arrived);

            if (arrived == load32(@b.total))
            {
                // This thread is last; reset and flip phase to release others.
                store32(@b.arrived, 0);
                fence();
                inc32(@b.phase);    // Phase flip wakes all spinners.
                return true;
            };

            // Spin until the phase flips (barrier released).
            while (load32(@b.phase) == current_phase)
            {
                #ifdef __ARCH_X86_64__
                volatile asm { pause } : : : "memory";
                #endif;
                #ifdef __ARCH_ARM64__
                volatile asm { yield } : : : "memory";
                #endif;
            };

            return false;
        };

        // ====================================================
        //  Thread-Local Storage Key
        // ====================================================

        // Allocate a TLS slot.  Returns THREAD_OK or THREAD_ERROR.
        def tls_key_create(TLSKey* k) -> int
        {
            #ifdef __WINDOWS__
            u32* kp = (u32*)@k.key[0];
            *kp = TlsAlloc();
            return (*kp != 0xFFFFFFFF) ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __LINUX__
            int rc = pthread_key_create((void*)@k.key[0], (void*)0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = pthread_key_create((void*)@k.key[0], (void*)0);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;
        };

        // Free a TLS slot.
        def tls_key_destroy(TLSKey* k) -> void
        {
            #ifdef __WINDOWS__
            u32* kp = (u32*)@k.key[0];
            TlsFree(*kp);
            #endif;

            #ifdef __LINUX__
            u64* kp = (u64*)@k.key[0];
            pthread_key_delete(*kp);
            #endif;

            #ifdef __MACOS__
            u64* kp = (u64*)@k.key[0];
            pthread_key_delete(*kp);
            #endif;
        };

        // Set the value for the calling thread.
        def tls_set(TLSKey* k, void* value) -> int
        {
            #ifdef __WINDOWS__
            u32* kp = (u32*)@k.key[0];
            return TlsSetValue(*kp, value) != 0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __LINUX__
            u64* kp = (u64*)@k.key[0];
            int rc = pthread_setspecific(*kp, value);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;

            #ifdef __MACOS__
            u64* kp = (u64*)@k.key[0];
            int rc = pthread_setspecific(*kp, value);
            return rc == 0 ? THREAD_OK : THREAD_ERROR;
            #endif;
        };

        // Get the value for the calling thread.
        def tls_get(TLSKey* k) -> void*
        {
            #ifdef __WINDOWS__
            u32* kp = (u32*)@k.key[0];
            return TlsGetValue(*kp);
            #endif;

            #ifdef __LINUX__
            u64* kp = (u64*)@k.key[0];
            return pthread_getspecific(*kp);
            #endif;

            #ifdef __MACOS__
            u64* kp = (u64*)@k.key[0];
            return pthread_getspecific(*kp);
            #endif;
        };

        // ====================================================
        //  Spinlock (atomic, no OS involvement)
        //  Re-exported here so callers need only one import.
        // ====================================================

        // Acquire a spinlock stored as an i32 (0 = free, 1 = held).
        def spinlock_lock(i32* lock) -> void
        {
            spin_lock(lock);
        };

        def spinlock_unlock(i32* lock) -> void
        {
            spin_unlock(lock);
        };

        def spinlock_trylock(i32* lock) -> bool
        {
            return spin_trylock(lock);
        };
    };
};

#endif; // FLUX_STANDARD_THREADING
