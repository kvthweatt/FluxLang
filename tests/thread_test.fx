// threading_demo.fx
// Demonstrates the redthreading.fx library.
//
// Exercises (single-process, sequential simulation where real
// multi-threading would be needed - the point is correct API usage):
//   - Thread creation and joining
//   - Mutex (mutual exclusion)
//   - Reader/Writer lock
//   - Condition variable (signal and broadcast)
//   - Semaphore (counting)
//   - Barrier (rendezvous)
//   - Thread-local storage
//   - Spinlock (re-exported from atomics)
//   - thread_id / thread_yield / thread_sleep_ms

#import "standard.fx", "threading.fx";

using standard::io::console;
using standard::threading;

// ─────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────

def print_result(byte* label, int value) -> void
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
//  Shared globals for cross-thread demos
// ─────────────────────────────────────────────

i32 g_counter      = 0;   // Protected by g_mutex in mutex demo
i32 g_ready        = 0;   // Condvar signal flag
i32 g_barrier_hits = 0;   // Counts barrier arrivals
i32 g_spin_counter = 0;   // Protected by g_spinlock
i32 g_spinlock     = 0;   // Raw spinlock word

Mutex   g_mutex;
RWLock  g_rwlock;
CondVar g_condvar;
Barrier g_barrier;

// ─────────────────────────────────────────────
//  Thread entry points
// ─────────────────────────────────────────────

// Increments g_counter under g_mutex ten times.
def thread_mutex_worker(void* arg) -> void*
{
    int i = 0;
    while (i < 10)
    {
        mutex_lock(@g_mutex);
        g_counter = g_counter + 1;
        mutex_unlock(@g_mutex);
        i = i + 1;
    };
    return (void*)0;
};

// Reads g_counter under a shared read lock and stores it via arg pointer.
def thread_rwlock_reader(void* arg) -> void*
{
    rwlock_read_lock(@g_rwlock);
    i32* out = (i32*)arg;
    *out = g_counter;
    rwlock_read_unlock(@g_rwlock);
    return (void*)0;
};

// Increments g_counter under an exclusive write lock.
def thread_rwlock_writer(void* arg) -> void*
{
    rwlock_write_lock(@g_rwlock);
    i32* delta_ptr = (i32*)arg;
    g_counter = g_counter + (int)*delta_ptr;
    rwlock_write_unlock(@g_rwlock);
    return (void*)0;
};

// Waits on g_condvar until g_ready is set, then increments g_counter.
def thread_condvar_waiter(void* arg) -> void*
{
    mutex_lock(@g_mutex);
    while (load32(@g_ready) == 0)
    {
        condvar_wait(@g_condvar, @g_mutex);
    };
    g_counter = g_counter + 1;
    mutex_unlock(@g_mutex);
    return (void*)0;
};

// Arrives at g_barrier and increments g_barrier_hits if it was the last.
def thread_barrier_worker(void* arg) -> void*
{
    bool last = barrier_wait(@g_barrier);
    if (last)
    {
        fetch_add32(@g_barrier_hits, 1);
    };
    return (void*)0;
};

// ─────────────────────────────────────────────
//  Demo sections
// ─────────────────────────────────────────────

def demo_thread_basics() -> void
{
    print_sep("Thread Create / Join\0");

    Thread t;
    g_counter = 0;
    mutex_init(@g_mutex);

    int rc = thread_create(@thread_mutex_worker, (void*)0, @t);
    print_bool("thread_create ok: \0", rc == THREAD_OK);

    rc = thread_join(@t);
    print_bool("thread_join  ok: \0", rc == THREAD_OK);

    // Worker added 10 to g_counter
    print_result("g_counter after worker (expect 10): \0", g_counter);

    print_result("thread_id (main): \0", (int)thread_id());
    print("thread_yield() called - OK\n\0");
    thread_yield();

    print("thread_sleep_ms(1) called - OK\n\0");
    thread_sleep_ms((u32)1);

    mutex_destroy(@g_mutex);
};

def demo_mutex() -> void
{
    print_sep("Mutex\0");

    mutex_init(@g_mutex);
    g_counter = 0;

    // Spawn two workers, each adding 10.
    Thread t1, t2;
    thread_create(@thread_mutex_worker, (void*)0, @t1);
    thread_create(@thread_mutex_worker, (void*)0, @t2);
    thread_join(@t1);
    thread_join(@t2);

    print_result("g_counter after 2 workers (expect 20): \0", g_counter);

    // trylock demo
    bool got = mutex_trylock(@g_mutex);
    print_bool("mutex_trylock (unlocked): \0", got);   // true
    // Note: on Windows, CRITICAL_SECTION is a recursive mutex.
    // TryEnterCriticalSection always succeeds for the owning thread,
    // so we unlock twice to match the two successful acquires.
    bool again = mutex_trylock(@g_mutex);
    print_bool("mutex_trylock (locked):   \0", again); // true on Windows (recursive), false on POSIX
    mutex_unlock(@g_mutex);
    mutex_unlock(@g_mutex);

    mutex_destroy(@g_mutex);
};

def demo_rwlock() -> void
{
    print_sep("Reader/Writer Lock\0");

    rwlock_init(@g_rwlock);
    g_counter = 42;

    // Two readers run concurrently, reading the same g_counter.
    i32 read1 = 0, read2 = 0;
    Thread r1, r2;
    thread_create(@thread_rwlock_reader, (void*)@read1, @r1);
    thread_create(@thread_rwlock_reader, (void*)@read2, @r2);
    thread_join(@r1);
    thread_join(@r2);

    print_result("reader 1 saw (expect 42): \0", (int)read1);
    print_result("reader 2 saw (expect 42): \0", (int)read2);

    // One writer adds 8 under exclusive lock.
    Thread w;
    i32 delta = 8;
    thread_create(@thread_rwlock_writer, (void*)@delta, @w);
    thread_join(@w);

    print_result("g_counter after writer (expect 50): \0", g_counter);

    // trylock variants
    bool rd = rwlock_try_read_lock(@g_rwlock);
    print_bool("try_read_lock (unlocked):  \0", rd);  // true
    rwlock_read_unlock(@g_rwlock);

    bool wr = rwlock_try_write_lock(@g_rwlock);
    print_bool("try_write_lock (unlocked): \0", wr);  // true
    rwlock_write_unlock(@g_rwlock);

    rwlock_destroy(@g_rwlock);
};

def demo_condvar() -> void
{
    print_sep("Condition Variable\0");

    mutex_init(@g_mutex);
    condvar_init(@g_condvar);
    g_counter = 0;
    store32(@g_ready, 0);

    // Spawn a waiter thread that will block until we signal it.
    Thread waiter;
    thread_create(@thread_condvar_waiter, (void*)0, @waiter);

    // Give the waiter a moment to reach condvar_wait.
    thread_sleep_ms((u32)5);

    // Signal: set g_ready and wake the waiter.
    mutex_lock(@g_mutex);
    store32(@g_ready, 1);
    condvar_signal(@g_condvar);
    mutex_unlock(@g_mutex);

    thread_join(@waiter);
    print_result("g_counter after condvar signal (expect 1): \0", g_counter);

    // Broadcast demo: two waiters, one broadcast.
    g_counter = 0;
    store32(@g_ready, 0);

    Thread w1, w2;
    thread_create(@thread_condvar_waiter, (void*)0, @w1);
    thread_create(@thread_condvar_waiter, (void*)0, @w2);

    thread_sleep_ms((u32)5);

    mutex_lock(@g_mutex);
    store32(@g_ready, 1);
    condvar_broadcast(@g_condvar);
    mutex_unlock(@g_mutex);

    thread_join(@w1);
    thread_join(@w2);
    print_result("g_counter after condvar broadcast (expect 2): \0", g_counter);

    // Timed wait that expires immediately (timeout = 1 ms).
    mutex_lock(@g_mutex);
    CondVar cv_temp;
    condvar_init(@cv_temp);
    int trc = condvar_wait_ms(@cv_temp, @g_mutex, (u32)1);
    mutex_unlock(@g_mutex);
    print_bool("condvar_wait_ms timeout: \0", trc == THREAD_TIMEOUT);

    condvar_destroy(@cv_temp);
    condvar_destroy(@g_condvar);
    mutex_destroy(@g_mutex);
};

def demo_semaphore() -> void
{
    print_sep("Semaphore\0");

    Semaphore sem;
    semaphore_init(@sem, 2);   // Two permits available initially.

    // Consume both permits.
    semaphore_wait(@sem);
    semaphore_wait(@sem);

    // Non-blocking attempt should fail (count == 0).
    bool got = semaphore_trywait(@sem);
    print_bool("trywait on empty semaphore (expect false): \0", !got);

    // Release one permit.
    semaphore_post(@sem);

    // Now trywait should succeed.
    got = semaphore_trywait(@sem);
    print_bool("trywait after post (expect true): \0", got);

    semaphore_destroy(@sem);
};

def demo_barrier() -> void
{
    print_sep("Barrier\0");

    int n = 4;
    barrier_init(@g_barrier, n);
    store32(@g_barrier_hits, 0);

    // Spawn n-1 workers; main acts as the n-th participant.
    Thread[3] workers;
    int i = 0;
    while (i < (n - 1))
    {
        thread_create(@thread_barrier_worker, (void*)0, @workers[i]);
        i = i + 1;
    };

    // Main arrives at barrier - it will be the last if workers arrived first.
    bool last = barrier_wait(@g_barrier);
    if (last)
    {
        fetch_add32(@g_barrier_hits, 1);
    };

    i = 0;
    while (i < (n - 1))
    {
        thread_join(@workers[i]);
        i = i + 1;
    };

    // Exactly one thread should have been the last arrival.
    print_result("barrier last-arrival count (expect 1): \0", (int)load32(@g_barrier_hits));
};

def demo_tls() -> void
{
    print_sep("Thread-Local Storage\0");

    TLSKey key;
    int rc = tls_key_create(@key);
    print_bool("tls_key_create ok: \0", rc == THREAD_OK);

    // Store and retrieve a value in the main thread's slot.
    i32 sentinel = 0xDEAD;
    tls_set(@key, (void*)@sentinel);
    void* got = tls_get(@key);
    i32 retrieved = *(i32*)got;

    print_bool("tls round-trip ok (expect 0xDEAD == 57005): \0",
               retrieved == (i32)0xDEAD);
    print_result("tls value: \0", (int)retrieved);

    tls_key_destroy(@key);
};

def demo_spinlock() -> void
{
    print_sep("Spinlock (re-exported)\0");

    g_spin_counter = 0;
    g_spinlock     = 0;

    // Simulate 10 "threads" each incrementing under the spinlock.
    int i = 0;
    while (i < 10)
    {
        spinlock_lock(@g_spinlock);
        g_spin_counter = g_spin_counter + 1;
        spinlock_unlock(@g_spinlock);
        i = i + 1;
    };

    print_result("spin_counter after 10 increments (expect 10): \0", g_spin_counter);

    bool got = spinlock_trylock(@g_spinlock);
    print_bool("spinlock_trylock (unlocked): \0", got);   // true
    bool again = spinlock_trylock(@g_spinlock);
    print_bool("spinlock_trylock (locked):   \0", again); // false
    spinlock_unlock(@g_spinlock);
};

// ─────────────────────────────────────────────
//  Entry point
// ─────────────────────────────────────────────

def main() -> int
{
    print("=== threading.fx demo ===\n\0");

    demo_thread_basics();
    demo_mutex();
    demo_rwlock();
    demo_condvar();
    demo_semaphore();
    demo_barrier();
    demo_tls();
    demo_spinlock();

    print("\n=== all threading demos complete ===\n\0");
    return 0;
};