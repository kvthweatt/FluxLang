// redallocators.fx - Flux Custom Memory Allocators
//
//
// Default Standard Heap Allocator:
    // Segregated free lists by size class for O(1) small alloc/free.
    // Bump pointer fast path carves from slab frontier.
    // Large allocations (>4096) get a dedicated OS slab, released on ffree.
    // Block metadata lives in a separate table slab (open-addressed hash map
    // keyed by user pointer). The table slab is itself an entry in the table.
    // No inline headers — user data blocks are completely pure.
    // No zeroing (Flux zero-inits at language level).
    // No coalescing (fragments are reusable as-is per Flux memory model).
    // Slabs acquired directly from OS: 4MB -> 8MB -> 16MB -> 32MB -> 64MB cap.
    // Zero OS memory consumed until first fmalloc call.
//
//

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_ALLOCATORS
#def FLUX_STANDARD_ALLOCATORS 1;

// ── OS primitives ─────────────────────────────────────────────────────────────

#ifdef __WINDOWS__
extern
{
    def !!
        VirtualAlloc(u64, size_t, u32, u32) -> u64,
        VirtualFree(u64, size_t, u32)       -> bool;
};
#endif;

#ifdef __LINUX__
extern
{
    def !!
        mmap(u64, size_t, int, int, int, i64) -> u64,
        munmap(u64, size_t)                   -> int;
};
#endif;

#ifdef __MACOS__
extern
{
    def !!
        mmap(u64, size_t, int, int, int, i64) -> u64,
        munmap(u64, size_t)                   -> int;
};
#endif;

// ── Size classes ──────────────────────────────────────────────────────
//
//  Index:  0    1    2    3    4    5     6     7     8
//  Bytes: 16   32   64  128  256  512  1024  2048  4096
//  >4096 = large, gets its own dedicated OS slab.

// ── Block kinds ───────────────────────────────────────────────────────
//
//  BLOCK_SMALL (0): size field holds size class index (0-8)
//  BLOCK_LARGE (1): size field holds exact byte count requested
//  BLOCK_TABLE (2): this entry describes a table slab itself

// ── Block table entry ─────────────────────────────────────────────────
//
//  key  : user pointer (null = empty slot)
//  size : size class index for small; byte count for large/table
//  kind : 0=small 1=large 2=table
//  slab : pointer to the OS slab that owns this block (for large/table)

struct BlockEntry
{
    u64    key;
    size_t size;
    u64    kind;
    u64    slab;
};

// ── Slab descriptor ───────────────────────────────────────────────────

struct Slab
{
    u64    base;
    size_t capacity,frontier;
    Slab*  next;
};

// ── Free list node (lives in the free block's own memory) ─────────────

struct FreeNode
{
    FreeNode* next;
};

namespace standard
{
    namespace memory
    {
        namespace allocators
        {
            namespace stdheap
            {
                // ── Globals ───────────────────────────────────────────────────────────

                global Slab*       g_slab_head      = (Slab*)0;
                global size_t      g_next_slab_size = (size_t)4194304;   // 4 MB
                global size_t      g_slab_size_cap  = (size_t)67108864;  // 64 MB

                // Block table: open-addressed hash map, stored in its own OS slab
                global BlockEntry* g_table          = (BlockEntry*)0;
                global size_t      g_table_cap      = (size_t)0;   // entry capacity
                global size_t      g_table_count    = (size_t)0;   // live entries
                global size_t      g_table_slab_cap = (size_t)0;   // byte size of table OS slab

                // Segregated free list bins (indices 0-8)
                global FreeNode* g_bin_0 = (FreeNode*)0;
                global FreeNode* g_bin_1 = (FreeNode*)0;
                global FreeNode* g_bin_2 = (FreeNode*)0;
                global FreeNode* g_bin_3 = (FreeNode*)0;
                global FreeNode* g_bin_4 = (FreeNode*)0;
                global FreeNode* g_bin_5 = (FreeNode*)0;
                global FreeNode* g_bin_6 = (FreeNode*)0;
                global FreeNode* g_bin_7 = (FreeNode*)0;
                global FreeNode* g_bin_8 = (FreeNode*)0;

                // ── OS helpers ────────────────────────────────────────────────────────

                def heap_os_alloc(size_t bytes) -> u64
                {
                    #ifdef __WINDOWS__
                    return VirtualAlloc((u64)0, bytes, (u32)0x3000, (u32)0x04);
                    #endif;
                    #ifdef __LINUX__
                    u64* p = mmap((u64)0, bytes, 3, 0x22, -1, (i64)0);
                    switch ((size_t)p == (size_t)0xFFFFFFFFFFFFFFFF) { case (1) { return (u64)0; } default {}; };
                    return p;
                    #endif;
                    #ifdef __MACOS__
                    u64* p = mmap((u64)0, bytes, 3, 0x1002, -1, (i64)0);
                    switch ((size_t)p == (size_t)0xFFFFFFFFFFFFFFFF) { case (1) { return (u64)0; } default {}; };
                    return p;
                    #endif;
                };

                def heap_os_free(u64 ptr, size_t bytes) -> void
                {
                    #ifdef __WINDOWS__
                    VirtualFree(ptr, (size_t)0, (u32)0x8000);
                    #endif;
                    #ifdef __LINUX__
                    munmap(ptr, bytes);
                    #endif;
                    #ifdef __MACOS__
                    munmap(ptr, bytes);
                    #endif;
                };

                def size_class(size_t size) -> size_t
                {
                    bool b;
                    b = size <= (size_t)16;   switch (b) { case (1) { return (size_t)0; } default {}; };
                    b = size <= (size_t)32;   switch (b) { case (1) { return (size_t)1; } default {}; };
                    b = size <= (size_t)64;   switch (b) { case (1) { return (size_t)2; } default {}; };
                    b = size <= (size_t)128;  switch (b) { case (1) { return (size_t)3; } default {}; };
                    b = size <= (size_t)256;  switch (b) { case (1) { return (size_t)4; } default {}; };
                    b = size <= (size_t)512;  switch (b) { case (1) { return (size_t)5; } default {}; };
                    b = size <= (size_t)1024; switch (b) { case (1) { return (size_t)6; } default {}; };
                    b = size <= (size_t)2048; switch (b) { case (1) { return (size_t)7; } default {}; };
                    b = size <= (size_t)4096; switch (b) { case (1) { return (size_t)8; } default {}; };
                    return (size_t)9;
                };

                def class_block_size(size_t cls) -> size_t
                {
                    switch (cls)
                    {
                        case (0) { return (size_t)16;   }
                        case (1) { return (size_t)32;   }
                        case (2) { return (size_t)64;   }
                        case (3) { return (size_t)128;  }
                        case (4) { return (size_t)256;  }
                        case (5) { return (size_t)512;  }
                        case (6) { return (size_t)1024; }
                        case (7) { return (size_t)2048; }
                        default  { return (size_t)4096; };
                    };
                    return (size_t)0;
                };

                def bin_pop(size_t cls) -> FreeNode*
                {
                    FreeNode* n = (FreeNode*)0;
                    switch (cls)
                    {
                        case (0) { n = g_bin_0; switch (n != (FreeNode*)0) { case (1) { g_bin_0 = n.next; } default {}; }; return n; }
                        case (1) { n = g_bin_1; switch (n != (FreeNode*)0) { case (1) { g_bin_1 = n.next; } default {}; }; return n; }
                        case (2) { n = g_bin_2; switch (n != (FreeNode*)0) { case (1) { g_bin_2 = n.next; } default {}; }; return n; }
                        case (3) { n = g_bin_3; switch (n != (FreeNode*)0) { case (1) { g_bin_3 = n.next; } default {}; }; return n; }
                        case (4) { n = g_bin_4; switch (n != (FreeNode*)0) { case (1) { g_bin_4 = n.next; } default {}; }; return n; }
                        case (5) { n = g_bin_5; switch (n != (FreeNode*)0) { case (1) { g_bin_5 = n.next; } default {}; }; return n; }
                        case (6) { n = g_bin_6; switch (n != (FreeNode*)0) { case (1) { g_bin_6 = n.next; } default {}; }; return n; }
                        case (7) { n = g_bin_7; switch (n != (FreeNode*)0) { case (1) { g_bin_7 = n.next; } default {}; }; return n; }
                        case (8) { n = g_bin_8; switch (n != (FreeNode*)0) { case (1) { g_bin_8 = n.next; } default {}; }; return n; }
                        default  {};
                    };
                    return (FreeNode*)0;
                };

                def bin_push(size_t cls, FreeNode* node) -> void
                {
                    switch (cls)
                    {
                        case (0) { node.next = g_bin_0; g_bin_0 = node; return; }
                        case (1) { node.next = g_bin_1; g_bin_1 = node; return; }
                        case (2) { node.next = g_bin_2; g_bin_2 = node; return; }
                        case (3) { node.next = g_bin_3; g_bin_3 = node; return; }
                        case (4) { node.next = g_bin_4; g_bin_4 = node; return; }
                        case (5) { node.next = g_bin_5; g_bin_5 = node; return; }
                        case (6) { node.next = g_bin_6; g_bin_6 = node; return; }
                        case (7) { node.next = g_bin_7; g_bin_7 = node; return; }
                        case (8) { node.next = g_bin_8; g_bin_8 = node; return; }
                        default  {return;};
                    };
                };

                // ── Block table ───────────────────────────────────────────────────────

                // entry size: 8+8+8+8 = 32 bytes
                def entry_size() -> size_t
                {
                    return (size_t)32;
                };

                // Hash a pointer to a table slot index
                def table_hash(u64 ptr, size_t cap) -> size_t
                {
                    size_t h = (size_t)ptr;
                    h = h `^^ (h >> (size_t)16);
                    h = h * (size_t)0x45D9F3B;
                    h = h `^^ (h >> (size_t)16);
                    return h & (cap - (size_t)1);
                };

                // Insert into a raw table buffer (used by both insert and grow)
                def table_raw_insert(BlockEntry* tbl, size_t cap,
                                     u64 key, size_t size, u64 kind, u64 slab) -> void
                {
                    size_t idx = table_hash(key, cap);
                    while (tbl[idx].key != (u64)0)
                    {
                        idx = (idx + (size_t)1) & (cap - (size_t)1);
                    };
                    tbl[idx].key  = key;
                    tbl[idx].size = size;
                    tbl[idx].kind = kind;
                    tbl[idx].slab = slab;
                };

                // Grow the table slab when load factor exceeds 0.5
                def table_grow() -> bool
                {
                    size_t new_cap  = g_table_cap * (size_t)2;
                    size_t new_bytes = new_cap * entry_size();

                    u64* raw = heap_os_alloc(new_bytes);
                    switch (raw == (u64)0)
                    {
                        case (1) { return false; }
                        default  {};
                    };

                    // Zero the new table (table entries must start null)
                    byte* p = (byte*)raw;
                    size_t i = (size_t)0;
                    while (i < new_bytes)
                    {
                        p[i] = '\0';
                        i++;
                    };

                    BlockEntry* new_tbl = (BlockEntry*)raw;

                    // Rehash all existing entries into the new table
                    size_t j = (size_t)0;
                    while (j < g_table_cap)
                    {
                        switch (g_table[j].key != (u64)0)
                        {
                            case (1)
                            {
                                table_raw_insert(new_tbl, new_cap,
                                                 g_table[j].key,
                                                 g_table[j].size,
                                                 g_table[j].kind,
                                                 g_table[j].slab);
                            }
                            default {};
                        };
                        j++;
                    };

                    // Release old table slab
                    heap_os_free((u64)g_table, g_table_slab_cap);

                    g_table          = new_tbl;
                    g_table_cap      = new_cap;
                    g_table_slab_cap = new_bytes;

                    // Record this table slab as an entry in itself
                    table_raw_insert(g_table,
                                     g_table_cap,
                                     (u64)raw,
                                     new_bytes,
                                     (u64)2,
                                     (u64)raw);
                    g_table_count++;

                    return true;
                };

                // Initialise the table on first use
                def table_init() -> bool
                {
                    size_t initial_cap   = (size_t)1024;
                    size_t initial_bytes = initial_cap * entry_size();

                    u64* raw = heap_os_alloc(initial_bytes);
                    switch (raw == (u64)0)
                    {
                        case (1) { return false; }
                        default  {};
                    };

                    // Zero the table
                    byte* p = (byte*)raw;
                    size_t i = (size_t)0;
                    while (i < initial_bytes)
                    {
                        p[i] = (byte)0;
                        i++;
                    };

                    g_table          = (BlockEntry*)raw;
                    g_table_cap      = initial_cap;
                    g_table_count    = (size_t)0;
                    g_table_slab_cap = initial_bytes;

                    // Record this table slab as an entry in itself
                    table_raw_insert(g_table,
                                     g_table_cap,
                                     (u64)raw,
                                     initial_bytes,
                                     (u64)2,
                                     (u64)raw);
                    g_table_count++;

                    return true;
                };

                def table_insert(u64 key, size_t size, u64 kind, u64 slab) -> bool
                {
                    switch (g_table == (BlockEntry*)0)
                    {
                        case (1)
                        {
                            switch (!table_init()) { case (1) { return false; } default {}; };
                        }
                        default {};
                    };

                    // Grow if load > 50%
                    switch (g_table_count * (size_t)2 >= g_table_cap)
                    {
                        case (1)
                        {
                            switch (!table_grow()) { case (1) { return false; } default {}; };
                        }
                        default {};
                    };

                    table_raw_insert(g_table, g_table_cap, key, size, kind, slab);
                    g_table_count++;
                    return true;
                };

                def table_find(u64 key) -> BlockEntry*
                {
                    switch (g_table == (BlockEntry*)0) { case (1) { return (BlockEntry*)0; } default {}; };

                    size_t idx = table_hash(key, g_table_cap);
                    while (g_table[idx].key != (u64)0)
                    {
                        switch (g_table[idx].key == key)
                        {
                            case (1) { return @g_table[idx]; }
                            default  {};
                        };
                        idx = (idx + (size_t)1) & (g_table_cap - (size_t)1);
                    };
                    return (BlockEntry*)0;
                };

                def table_remove(u64 key) -> void
                {
                    switch (g_table == (BlockEntry*)0) { case (1) { return; } default {}; };

                    size_t idx = table_hash(key, g_table_cap);
                    while (g_table[idx].key != (u64)0)
                    {
                        switch (g_table[idx].key == key)
                        {
                            case (1)
                            {
                                // Tombstone: clear key, leave rest for Robin Hood probe chain
                                g_table[idx].key = (u64)0;
                                g_table_count--;

                                // Rehash the run after the removed slot to maintain probe invariant
                                size_t next = (idx + (size_t)1) & (g_table_cap - (size_t)1);
                                while (g_table[next].key != (u64)0)
                                {
                                    u64  rkey  = g_table[next].key;
                                    size_t rsize = g_table[next].size;
                                    u64    rkind = g_table[next].kind;
                                    u64  rslab = g_table[next].slab;
                                    g_table[next].key = (u64)0;
                                    g_table_count--;
                                    table_raw_insert(g_table, g_table_cap, rkey, rsize, rkind, rslab);
                                    g_table_count++;
                                    next = (next + (size_t)1) & (g_table_cap - (size_t)1);
                                };
                                return;
                            }
                            default {};
                        };
                        idx = (idx + (size_t)1) & (g_table_cap - (size_t)1);
                    };
                };

                // ── Data slab management ──────────────────────────────────────────────

                def slab_header_size() -> size_t
                {
                    return (size_t)32;  // sizeof(Slab)
                };

                def heap_new_slab(size_t min_capacity) -> Slab*
                {
                    size_t sz = g_next_slab_size;
                    switch (min_capacity + slab_header_size() > sz)
                    {
                        case (1) { sz = min_capacity + slab_header_size(); }
                        default  {};
                    };

                    u64* raw = heap_os_alloc(sz);
                    switch (raw == (u64)0) { case (1) { return (Slab*)0; } default {}; };

                    Slab* slab    = (Slab*)raw;
                    slab.base     = (u64)raw;
                    slab.capacity = sz;
                    slab.frontier = slab_header_size();
                    slab.next     = g_slab_head;
                    g_slab_head   = slab;

                    // Advance exponential growth
                    size_t next = g_next_slab_size * (size_t)2;
                    switch (next > g_slab_size_cap)
                    {
                        case (1) { next = g_slab_size_cap; }
                        default  {};
                    };
                    g_next_slab_size = next;

                    return slab;
                };

                def bump_alloc(size_t bytes) -> u64
                {
                    Slab* slab = g_slab_head;
                    switch (slab == (Slab*)0) { case (1) { return (u64)0; } default {}; };
                    switch (slab.frontier + bytes > slab.capacity) { case (1) { return (u64)0; } default {}; };
                    u64 ptr     = (u64)((byte*)slab.base + slab.frontier);
                    slab.frontier = slab.frontier + bytes;
                    return ptr;
                };

                // ── Public API ────────────────────────────────────────────────────────

                def fmalloc(size_t size) -> u64
                {
                    switch (size == (size_t)0) { case (1) { return (u64)0; } default {}; };

                    size_t cls = size_class(size);

                    switch (cls == (size_t)9)
                    {
                        case (1)
                        {
                            // Large: dedicated OS slab, no bump involvement
                            u64 raw = heap_os_alloc(size);
                            switch (raw == (u64)0) { case (1) { return (u64)0; } default {}; };

                            switch (!table_insert(raw, size, (u64)1, raw))
                            {
                                case (1)
                                {
                                    heap_os_free(raw, size);
                                    return (u64)0;
                                }
                                default {};
                            };

                            return raw;
                        }
                        default {};
                    };

                    // Small: try free list bin first
                    FreeNode* node = bin_pop(cls);
                    switch (node != (FreeNode*)0)
                    {
                        case (1)
                        {
                            u64 ptr = (u64)node;
                            // Re-insert into table as live (kind=0)
                            table_insert(ptr, cls, (u64)0, (u64)0);
                            return ptr;
                        }
                        default {};
                    };

                    // Bump allocate from current slab
                    size_t block = class_block_size(cls);
                    u64 ptr = bump_alloc(block);
                    switch (ptr == (u64)0)
                    {
                        case (1)
                        {
                            switch (heap_new_slab(block) == (Slab*)0) { case (1) { return (u64)0; } default {}; };
                            ptr = bump_alloc(block);
                            switch (ptr == (u64)0) { case (1) { return (u64)0; } default {}; };
                        }
                        default {};
                    };

                    switch (!table_insert(ptr, cls, (u64)0, (u64)0))
                    {
                        case (1) { return (u64)0; }
                        default  {};
                    };

                    return ptr;
                };

                def ffree(u64 ptr) -> void
                {
                    switch (ptr == (u64)0) { case (1) { return; } default {}; };

                    BlockEntry* entry = table_find(ptr);
                    switch (entry == (BlockEntry*)0) { case (1) { return; } default {}; };

                    u64    kind = entry.kind;
                    size_t size = entry.size;
                    u64  slab = entry.slab;

                    table_remove(ptr);

                    switch (kind == (u64)1)
                    {
                        case (1)
                        {
                            // Large block: release OS slab directly
                            heap_os_free(slab, size);
                            return;
                        }
                        default {};
                    };

                    // Small block: return to bin
                    bin_push(size, (FreeNode*)ptr);
                };

                def frealloc(u64 ptr, size_t new_size) -> u64
                {
                    switch (ptr == (u64)0) { case (1) { return fmalloc(new_size); } default {}; };
                    switch (new_size == (size_t)0) { case (1) { ffree(ptr); return (u64)0; } default {}; };

                    BlockEntry* entry = table_find(ptr);
                    switch (entry == (BlockEntry*)0) { case (1) { return (u64)0; } default {}; };

                    u64    kind    = entry.kind;
                    size_t old_size = entry.size;

                    switch (kind == (u64)1)
                    {
                        case (1)
                        {
                            // Large block: shrinking or same — update size in table, no move
                            bool fits = old_size >= new_size;
                            switch (fits)
                            {
                                case (1) { entry.size = new_size; return ptr; }
                                default  {};
                            };
                        }
                        default
                        {
                            size_t old_cls = old_size;
                            size_t new_cls = size_class(new_size);

                            // Same class: fits as-is, no move
                            bool same = new_cls == old_cls;
                            switch (same) { case (1) { return ptr; } default {}; };

                            // Shrinking to a smaller class: data fits, no move needed
                            bool shrink = new_cls < old_cls;
                            switch (shrink) { case (1) { entry.size = new_cls; return ptr; } default {}; };

                            // Growing: check if the target bin has a free block before bumping
                            size_t copy_size = class_block_size(old_cls);
                            switch (new_size < copy_size) { case (1) { copy_size = new_size; } default {}; };

                            FreeNode* reuse = bin_pop(new_cls);
                            bool has_reuse = reuse != (FreeNode*)0;
                            switch (has_reuse)
                            {
                                case (1)
                                {
                                    u64 new_ptr = (u64)reuse;
                                    table_insert(new_ptr, new_cls, (u64)0, (u64)0);
                                    byte* src = (byte*)ptr;
                                    byte* dst = (byte*)new_ptr;
                                    size_t i = (size_t)0;
                                    while (i < copy_size) { dst[i] = src[i]; i++; };
                                    table_remove(ptr);
                                    bin_push(old_cls, (FreeNode*)ptr);
                                    return new_ptr;
                                }
                                default {};
                            };

                            // No free block in bin — bump allocate, copy, free old
                            u64 new_ptr = fmalloc(new_size);
                            switch (new_ptr == (u64)0) { case (1) { return (u64)0; } default {}; };
                            byte* src = (byte*)ptr;
                            byte* dst = (byte*)new_ptr;
                            size_t i = (size_t)0;
                            while (i < copy_size) { dst[i] = src[i]; i++; };
                            ffree(ptr);
                            return new_ptr;
                        };
                    };

                    // Large block growing: must move
                    u64 new_ptr = fmalloc(new_size);
                    switch (new_ptr == (u64)0) { case (1) { return (u64)0; } default {}; };
                    byte* src = (byte*)ptr;
                    byte* dst = (byte*)new_ptr;
                    size_t i = (size_t)0;
                    while (i < old_size) { dst[i] = src[i]; i++; };
                    ffree(ptr);
                    return new_ptr;
                };
            };
        };
    };
};

#endif;
