// Author: Karac V. Thweatt

// ================================================================
// stdtheap - Thread-Safe Heap Allocator
//
// Design: per-thread arenas, zero contention on the fast path.
//
//   - Each thread gets its own Arena: independent bins, slab list,
//     and block table.  Small alloc/free never touches a lock.
//   - Thread registration uses a global spinlock only once per
//     thread (on first tfmalloc call from that thread).
//   - Large allocations (>4096) acquire g_large_lock only for the
//     VirtualAlloc/mmap call, then release immediately.  The block
//     table entry lives in the calling thread's arena so tffree
//     needs no lock either.
//   - Up to MAX_TARENA (128) threads supported.  Slots are
//     identified by OS thread ID (u64); 0 = empty.
//   - Call tffree_arena() before thread exit to return the slot.
// ================================================================

#ifndef FLUX_STANDARD_ALLOCATORS
#stop "Must import redallocators.fx to use threaded allocators.";
#endif;

struct Arena
{
    u64        tid;

    // Slab list
    Slab*      slab_head;
    size_t     next_slab_size;
    size_t     large_used;

    // Block table
    BlockEntry* table;
    size_t      table_cap;
    size_t      table_count;
    size_t      table_slab_cap;

    // Segregated free list bins (9 size classes: 16..4096)
    FreeNode*  bin_0, bin_1, bin_2, bin_3, bin_4,
               bin_5, bin_6, bin_7, bin_8;
};

namespace standard
{
    namespace memory
    {
        namespace allocators
        {
            namespace stdtheap
            {
                global const size_t MAX_TARENA = (size_t)128;

                // Per-thread allocator state

                Arena[128]  g_arenas;
                i32         g_arenas_lock  = 0;
                i32         g_large_lock   = 0;
                size_t      g_slab_size_cap = (size_t)67108864;

                // ── OS thread ID ──────────────────────────────────────────

                def current_tid() -> u64
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

                // ── Arena lookup / registration ───────────────────────────

                def get_arena() -> Arena*
                {
                    u64 tid = current_tid();

                    // Fast unlocked scan
                    size_t i = (size_t)0;
                    while (i < MAX_TARENA)
                    {
                        switch (g_arenas[i].tid == tid)
                        {
                            case (1) { return @g_arenas[i]; }
                            default  {};
                        };
                        i++;
                    };

                    // Register under lock
                    spin_lock(@g_arenas_lock);

                    // Re-scan inside lock
                    i = (size_t)0;
                    while (i < MAX_TARENA)
                    {
                        switch (g_arenas[i].tid == tid)
                        {
                            case (1)
                            {
                                spin_unlock(@g_arenas_lock);
                                return @g_arenas[i];
                            }
                            default {};
                        };
                        i++;
                    };

                    // Claim a free slot
                    i = (size_t)0;
                    Arena* slot = (Arena*)0;
                    while (i < MAX_TARENA)
                    {
                        switch (g_arenas[i].tid == (u64)0)
                        {
                            case (1)
                            {
                                slot = @g_arenas[i];
                                i    = MAX_TARENA;
                            }
                            default {};
                        };
                        i++;
                    };

                    switch (slot != (Arena*)0)
                    {
                        case (1)
                        {
                            slot.tid            = tid;
                            slot.slab_head      = (Slab*)0;
                            slot.next_slab_size = (size_t)4194304;
                            slot.large_used     = (size_t)0;
                            slot.table          = (BlockEntry*)0;
                            slot.table_cap      = (size_t)0;
                            slot.table_count    = (size_t)0;
                            slot.table_slab_cap = (size_t)0;
                            slot.bin_0          = NP_FREENODE;
                            slot.bin_1          = NP_FREENODE;
                            slot.bin_2          = NP_FREENODE;
                            slot.bin_3          = NP_FREENODE;
                            slot.bin_4          = NP_FREENODE;
                            slot.bin_5          = NP_FREENODE;
                            slot.bin_6          = NP_FREENODE;
                            slot.bin_7          = NP_FREENODE;
                            slot.bin_8          = NP_FREENODE;
                        }
                        default {};
                    };

                    spin_unlock(@g_arenas_lock);
                    return slot;
                };

                // ── Per-arena bin helpers ─────────────────────────────────

                def arena_bin_pop(Arena* a, size_t cls) -> FreeNode*
                {
                    FreeNode* n = NP_FREENODE;
                    switch (cls)
                    {
                        case (0) { n = a.bin_0; switch (n != NP_FREENODE) { case (1) { a.bin_0 = n.next; } default {}; }; return n; }
                        case (1) { n = a.bin_1; switch (n != NP_FREENODE) { case (1) { a.bin_1 = n.next; } default {}; }; return n; }
                        case (2) { n = a.bin_2; switch (n != NP_FREENODE) { case (1) { a.bin_2 = n.next; } default {}; }; return n; }
                        case (3) { n = a.bin_3; switch (n != NP_FREENODE) { case (1) { a.bin_3 = n.next; } default {}; }; return n; }
                        case (4) { n = a.bin_4; switch (n != NP_FREENODE) { case (1) { a.bin_4 = n.next; } default {}; }; return n; }
                        case (5) { n = a.bin_5; switch (n != NP_FREENODE) { case (1) { a.bin_5 = n.next; } default {}; }; return n; }
                        case (6) { n = a.bin_6; switch (n != NP_FREENODE) { case (1) { a.bin_6 = n.next; } default {}; }; return n; }
                        case (7) { n = a.bin_7; switch (n != NP_FREENODE) { case (1) { a.bin_7 = n.next; } default {}; }; return n; }
                        case (8) { n = a.bin_8; switch (n != NP_FREENODE) { case (1) { a.bin_8 = n.next; } default {}; }; return n; }
                        default  {};
                    };
                    return NP_FREENODE;
                };

                def arena_bin_push(Arena* a, size_t cls, FreeNode* node) -> void
                {
                    switch (cls)
                    {
                        case (0) { node.next = a.bin_0; a.bin_0 = node; return; }
                        case (1) { node.next = a.bin_1; a.bin_1 = node; return; }
                        case (2) { node.next = a.bin_2; a.bin_2 = node; return; }
                        case (3) { node.next = a.bin_3; a.bin_3 = node; return; }
                        case (4) { node.next = a.bin_4; a.bin_4 = node; return; }
                        case (5) { node.next = a.bin_5; a.bin_5 = node; return; }
                        case (6) { node.next = a.bin_6; a.bin_6 = node; return; }
                        case (7) { node.next = a.bin_7; a.bin_7 = node; return; }
                        case (8) { node.next = a.bin_8; a.bin_8 = node; return; }
                        default  { return; };
                    };
                };

                // ── Per-arena block table ─────────────────────────────────

                def arena_table_init(Arena* a) -> bool
                {
                    size_t initial_cap   = (size_t)1024;
                    size_t initial_bytes = initial_cap * (size_t)32;

                    u64 raw = stdheap::heap_os_alloc(initial_bytes);
                    switch (raw == (u64)0) { case (1) { return false; } default {}; };

                    byte* p = (byte*)raw;
                    size_t i = (size_t)0;
                    while (i < initial_bytes) { p[i] = (byte)0; i++; };

                    a.table          = (BlockEntry*)raw;
                    a.table_cap      = initial_cap;
                    a.table_count    = (size_t)0;
                    a.table_slab_cap = initial_bytes;

                    stdheap::table_raw_insert(a.table, a.table_cap,
                                              raw, initial_bytes, (u64)2, raw);
                    a.table_count++;
                    return true;
                };

                def arena_table_grow(Arena* a) -> bool
                {
                    size_t new_cap   = a.table_cap * (size_t)2;
                    size_t new_bytes = new_cap * (size_t)32;

                    u64 raw = stdheap::heap_os_alloc(new_bytes);
                    switch (raw == (u64)0) { case (1) { return false; } default {}; };

                    byte* p = (byte*)raw;
                    size_t i = (size_t)0;
                    while (i < new_bytes) { p[i] = (byte)0; i++; };

                    BlockEntry* new_tbl = (BlockEntry*)raw;
                    a.table_count = (size_t)0;

                    size_t j = (size_t)0;
                    while (j < a.table_cap)
                    {
                        switch (a.table[j].key != (u64)0)
                        {
                            case (1)
                            {
                                stdheap::table_raw_insert(new_tbl, new_cap,
                                                          a.table[j].key,
                                                          a.table[j].size,
                                                          a.table[j].kind,
                                                          a.table[j].slab);
                                a.table_count++;
                            }
                            default {};
                        };
                        j++;
                    };

                    // Remove old table slab entry from new_tbl, release old slab
                    u64    old_addr = (u64)a.table;
                    size_t rm_idx   = stdheap::table_hash(old_addr, new_cap);
                    while (new_tbl[rm_idx].key != (u64)0)
                    {
                        switch (new_tbl[rm_idx].key == old_addr)
                        {
                            case (1)
                            {
                                new_tbl[rm_idx].key = (u64)0;
                                a.table_count--;
                                size_t hole = rm_idx;
                                size_t next = (rm_idx + (size_t)1) & (new_cap - (size_t)1);
                                while (new_tbl[next].key != (u64)0)
                                {
                                    size_t nat = stdheap::table_hash(new_tbl[next].key, new_cap);
                                    bool shift;
                                    switch (hole < next)
                                    {
                                        case (1) { shift = (nat <= hole) | (nat > next); }
                                        default  { shift = !((nat > hole) | (nat <= next)); };
                                    };
                                    switch (shift)
                                    {
                                        case (1)
                                        {
                                            new_tbl[hole].key  = new_tbl[next].key;
                                            new_tbl[hole].size = new_tbl[next].size;
                                            new_tbl[hole].kind = new_tbl[next].kind;
                                            new_tbl[hole].slab = new_tbl[next].slab;
                                            new_tbl[next].key  = (u64)0;
                                            hole = next;
                                        }
                                        default {};
                                    };
                                    next = (next + (size_t)1) & (new_cap - (size_t)1);
                                };
                                rm_idx = new_cap;
                            }
                            default {};
                        };
                        rm_idx = (rm_idx + (size_t)1) & (new_cap - (size_t)1);
                    };

                    stdheap::heap_os_free((u64)a.table, a.table_slab_cap);

                    a.table          = new_tbl;
                    a.table_cap      = new_cap;
                    a.table_slab_cap = new_bytes;

                    stdheap::table_raw_insert(a.table, a.table_cap,
                                              raw, new_bytes, (u64)2, raw);
                    a.table_count++;
                    return true;
                };

                def arena_table_insert(Arena* a, u64 key, size_t size, u64 kind, u64 slab) -> bool
                {
                    switch (a.table == (BlockEntry*)0)
                    {
                        case (1) { switch (!arena_table_init(a)) { case (1) { return false; } default {}; }; }
                        default  {};
                    };
                    switch (a.table_count * (size_t)2 >= a.table_cap)
                    {
                        case (1) { switch (!arena_table_grow(a)) { case (1) { return false; } default {}; }; }
                        default  {};
                    };
                    stdheap::table_raw_insert(a.table, a.table_cap, key, size, kind, slab);
                    a.table_count++;
                    return true;
                };

                def arena_table_find(Arena* a, u64 key) -> BlockEntry*
                {
                    switch (a.table == (BlockEntry*)0) { case (1) { return (BlockEntry*)0; } default {}; };

                    size_t idx = stdheap::table_hash(key, a.table_cap);
                    while (a.table[idx].key != (u64)0)
                    {
                        switch (a.table[idx].key == key)
                        {
                            case (1) { return @a.table[idx]; }
                            default  {};
                        };
                        idx = (idx + (size_t)1) & (a.table_cap - (size_t)1);
                    };
                    return (BlockEntry*)0;
                };

                def arena_table_remove(Arena* a, u64 key) -> void
                {
                    switch (a.table == (BlockEntry*)0) { case (1) { return; } default {}; };

                    size_t idx = stdheap::table_hash(key, a.table_cap);
                    while (a.table[idx].key != (u64)0)
                    {
                        switch (a.table[idx].key == key)
                        {
                            case (1)
                            {
                                a.table[idx].key = (u64)0;
                                a.table_count--;
                                size_t hole = idx;
                                size_t next = (idx + (size_t)1) & (a.table_cap - (size_t)1);
                                while (a.table[next].key != (u64)0)
                                {
                                    size_t nat = stdheap::table_hash(a.table[next].key, a.table_cap);
                                    bool shift;
                                    switch (hole < next)
                                    {
                                        case (1) { shift = (nat <= hole) | (nat > next); }
                                        default  { shift = !((nat > hole) | (nat <= next)); };
                                    };
                                    switch (shift)
                                    {
                                        case (1)
                                        {
                                            a.table[hole].key  = a.table[next].key;
                                            a.table[hole].size = a.table[next].size;
                                            a.table[hole].kind = a.table[next].kind;
                                            a.table[hole].slab = a.table[next].slab;
                                            a.table[next].key  = (u64)0;
                                            hole = next;
                                        }
                                        default {};
                                    };
                                    next = (next + (size_t)1) & (a.table_cap - (size_t)1);
                                };
                                return;
                            }
                            default {};
                        };
                        idx = (idx + (size_t)1) & (a.table_cap - (size_t)1);
                    };
                };

                // ── Per-arena slab management ─────────────────────────────

                def arena_new_slab(Arena* a, size_t min_capacity) -> Slab*
                {
                    size_t sz = a.next_slab_size;
                    switch (min_capacity + (size_t)40 > sz)
                    {
                        case (1) { sz = min_capacity + (size_t)40; }
                        default  {};
                    };

                    u64 raw = stdheap::heap_os_alloc(sz);
                    switch (raw == (u64)0) { case (1) { return (Slab*)0; } default {}; };

                    Slab* slab    = (Slab*)raw;
                    slab.base     = raw;
                    slab.capacity = sz;
                    slab.frontier = (size_t)40;
                    slab.used     = (size_t)0;
                    slab.next     = a.slab_head;
                    a.slab_head   = slab;

                    size_t next_sz = a.next_slab_size * (size_t)2;
                    switch (next_sz > g_slab_size_cap)
                    {
                        case (1) { next_sz = g_slab_size_cap; }
                        default  {};
                    };
                    a.next_slab_size = next_sz;

                    return slab;
                };

                def arena_bump_alloc(Arena* a, size_t bytes) -> u64
                {
                    Slab* slab = a.slab_head;
                    switch (slab == (Slab*)0) { case (1) { return (u64)0; } default {}; };
                    switch (slab.frontier + bytes > slab.capacity) { case (1) { return (u64)0; } default {}; };
                    u64 ptr      = (u64)((byte*)slab.base + slab.frontier);
                    slab.frontier = slab.frontier + bytes;
                    return ptr;
                };

                // ── Public API ────────────────────────────────────────────

                // Thread-safe malloc. Small allocs are lock-free (per-thread arena).
                // Large allocs hold g_large_lock only for the OS call.
                def tfmalloc(size_t size) -> u64
                {
                    switch (size == (size_t)0) { case (1) { return (u64)0; } default {}; };

                    Arena* a = get_arena();
                    switch (a == (Arena*)0) { case (1) { return (u64)0; } default {}; };

                    size_t cls = stdheap::size_class(size);

                    // Large block
                    switch (cls == (size_t)9)
                    {
                        case (1)
                        {
                            spin_lock(@g_large_lock);
                            u64 raw = stdheap::heap_os_alloc(size);
                            spin_unlock(@g_large_lock);

                            switch (raw == (u64)0) { case (1) { return (u64)0; } default {}; };

                            switch (!arena_table_insert(a, raw, size, (u64)1, size))
                            {
                                case (1)
                                {
                                    spin_lock(@g_large_lock);
                                    stdheap::heap_os_free(raw, size);
                                    spin_unlock(@g_large_lock);
                                    return (u64)0;
                                }
                                default {};
                            };

                            a.large_used++;
                            return raw;
                        }
                        default {};
                    };

                    // Small: try free list bin first (no lock)
                    FreeNode* node = arena_bin_pop(a, cls);
                    switch (node != NP_FREENODE)
                    {
                        case (1)
                        {
                            u64 ptr = (u64)node;
                            Slab* owner = (Slab*)0;
                            Slab* s = a.slab_head;
                            while (s != (Slab*)0)
                            {
                                switch (ptr >= s.base & ptr < s.base + (u64)s.capacity)
                                {
                                    case (1) { s.used++; owner = s; s = (Slab*)0; }
                                    default  { s = s.next; };
                                };
                            };
                            arena_table_insert(a, ptr, cls, (u64)0, (u64)owner);
                            return ptr;
                        }
                        default {};
                    };

                    // Bump allocate from current slab
                    size_t block = stdheap::class_block_size(cls);
                    u64 ptr = arena_bump_alloc(a, block);
                    switch (ptr == (u64)0)
                    {
                        case (1)
                        {
                            switch (arena_new_slab(a, block) == (Slab*)0) { case (1) { return (u64)0; } default {}; };
                            ptr = arena_bump_alloc(a, block);
                            switch (ptr == (u64)0) { case (1) { return (u64)0; } default {}; };
                        }
                        default {};
                    };

                    switch (!arena_table_insert(a, ptr, cls, (u64)0, (u64)a.slab_head))
                    {
                        case (1) { return (u64)0; }
                        default  {};
                    };

                    a.slab_head.used++;
                    return ptr;
                };

                // Thread-safe free. Small frees are lock-free (per-thread arena).
                // Large frees hold g_large_lock only for the OS release.
                def tffree(u64 ptr) -> void
                {
                    switch (ptr == (u64)0) { case (1) { return; } default {}; };

                    Arena* a = get_arena();
                    switch (a == (Arena*)0) { case (1) { return; } default {}; };

                    BlockEntry* entry = arena_table_find(a, ptr);
                    switch (entry == (BlockEntry*)0) { case (1) { return; } default {}; };

                    u64    kind = entry.kind;
                    size_t size = entry.size;
                    u64    slab = entry.slab;

                    arena_table_remove(a, ptr);

                    switch (kind == (u64)1)
                    {
                        case (1)
                        {
                            // Large block: release to OS under lock
                            a.large_used--;
                            spin_lock(@g_large_lock);
                            stdheap::heap_os_free(ptr, (size_t)slab);
                            spin_unlock(@g_large_lock);
                            return;
                        }
                        default {};
                    };

                    // Small block: return to arena bin, no lock
                    Slab* owner = (Slab*)slab;
                    switch (owner != (Slab*)0)
                    {
                        case (1) { switch (owner.used > (size_t)0) { case (1) { owner.used--; } default {}; }; }
                        default  {};
                    };
                    arena_bin_push(a, size, (FreeNode*)ptr);
                };

                // Thread-safe realloc.
                def tfrealloc(u64 ptr, size_t new_size) -> u64
                {
                    switch (ptr == (u64)0)         { case (1) { return tfmalloc(new_size); } default {}; };
                    switch (new_size == (size_t)0) { case (1) { tffree(ptr); return (u64)0; } default {}; };

                    Arena* a = get_arena();
                    switch (a == (Arena*)0) { case (1) { return (u64)0; } default {}; };

                    BlockEntry* entry = arena_table_find(a, ptr);
                    switch (entry == (BlockEntry*)0) { case (1) { return (u64)0; } default {}; };

                    u64    kind     = entry.kind;
                    size_t old_size = entry.size;

                    // Large same size: no-op
                    switch (kind == (u64)1)
                    {
                        case (1) { switch (old_size == new_size) { case (1) { return ptr; } default {}; }; }
                        default
                        {
                            // Small: same or shrinking class fits as-is
                            size_t new_cls = stdheap::size_class(new_size);
                            switch (new_cls <= old_size) { case (1) { return ptr; } default {}; };
                        };
                    };

                    // Must move: alloc new, copy, free old
                    u64 new_ptr = tfmalloc(new_size);
                    switch (new_ptr == (u64)0) { case (1) { return (u64)0; } default {}; };

                    size_t copy_size = old_size;
                    switch (new_size < old_size) { case (1) { copy_size = new_size; } default {}; };

                    byte* src = (byte*)ptr;
                    byte* dst = (byte*)new_ptr;
                    size_t i  = (size_t)0;
                    while (i < copy_size) { dst[i] = src[i]; i++; };

                    tffree(ptr);
                    return new_ptr;
                };

                // Release the calling thread's arena slot back to the pool.
                // Call this before thread exit. Live blocks are leaked (same
                // as not calling free before exit - OS reclaims on process end).
                def tffree_arena() -> void
                {
                    u64 tid = current_tid();

                    spin_lock(@g_arenas_lock);

                    size_t i = (size_t)0;
                    while (i < MAX_TARENA)
                    {
                        switch (g_arenas[i].tid == tid)
                        {
                            case (1)
                            {
                                // Release all small slabs back to OS
                                Slab* s = g_arenas[i].slab_head;
                                while (s != (Slab*)0)
                                {
                                    Slab* next = s.next;
                                    stdheap::heap_os_free(s.base, s.capacity);
                                    s = next;
                                };

                                // Release table slab
                                switch (g_arenas[i].table != (BlockEntry*)0)
                                {
                                    case (1)
                                    {
                                        stdheap::heap_os_free((u64)g_arenas[i].table,
                                                              g_arenas[i].table_slab_cap);
                                    }
                                    default {};
                                };

                                // Zero the slot so it can be reused by a future thread
                                g_arenas[i].tid            = (u64)0;
                                g_arenas[i].slab_head      = (Slab*)0;
                                g_arenas[i].table          = (BlockEntry*)0;
                                g_arenas[i].table_cap      = (size_t)0;
                                g_arenas[i].table_count    = (size_t)0;
                                g_arenas[i].table_slab_cap = (size_t)0;
                                g_arenas[i].large_used     = (size_t)0;
                                g_arenas[i].bin_0          = NP_FREENODE;
                                g_arenas[i].bin_1          = NP_FREENODE;
                                g_arenas[i].bin_2          = NP_FREENODE;
                                g_arenas[i].bin_3          = NP_FREENODE;
                                g_arenas[i].bin_4          = NP_FREENODE;
                                g_arenas[i].bin_5          = NP_FREENODE;
                                g_arenas[i].bin_6          = NP_FREENODE;
                                g_arenas[i].bin_7          = NP_FREENODE;
                                g_arenas[i].bin_8          = NP_FREENODE;

                                i = MAX_TARENA;
                            }
                            default {};
                        };
                        i++;
                    };

                    spin_unlock(@g_arenas_lock);
                };
            };
        };
    };
};

#endif;
