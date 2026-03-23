// Author: Karac V. Thweatt

// redallocators.fx - Flux Custom Memory Allocators
//
//
// Default Standard Heap Allocator:
    // Segregated free lists by size class for O(1) small alloc/free.
    // Bump pointer fast path carves from slab frontier.
    // Large allocations (>4096) get a dedicated OS slab, released on ffree.
    // Block metadata lives in a separate table slab (open-addressed hash map
    // keyed by user pointer). The table slab is itself an entry in the table.
    // No inline headers user data blocks are completely pure.
    // No zeroing (Flux zero-inits at language level).
    // No coalescing (fragments are reusable as-is per Flux memory model).
    // Slabs acquired directly from OS: 4MB -> 8MB -> 16MB -> 32MB -> 64MB cap.
    // Zero OS memory consumed until first fmalloc call.
//
//

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_ALLOCATORS
#def FLUX_STANDARD_ALLOCATORS 1;

// OS primitives 

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

// Size classes
//
//  Index:  0    1    2    3    4    5     6     7     8
//  Bytes: 16   32   64  128  256  512  1024  2048  4096
//  >4096 = large, gets its own dedicated OS slab.

// Block kinds
//
//  BLOCK_SMALL (0): size field holds size class index (0-8)
//  BLOCK_LARGE (1): size field holds exact byte count requested
//  BLOCK_TABLE (2): this entry describes a table slab itself

// Block table entry
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

// Slab descriptor

struct Slab
{
    u64    base;
    size_t capacity,frontier,used;
    Slab*  next;
};

// Free list node (lives in the free block's own memory)

struct FreeNode
{
    FreeNode* next;
};

// Ring allocator result (returned by stdring::allocate)
//
//  ptr     : pointer to the allocated region (never null unless size > capacity)
//  wrapped : true if the write pointer wrapped around and overwrote old data

struct RingAllocResult
{
    u64*  ptr;
    bool  wrapped;
};

#def NP_FREENODE (FreeNode*)0; // Null free node pointer
#def NP_SLAB     (Slab*)0;     // Null slab pointer

namespace standard
{
    namespace memory
    {
        namespace allocators
        {
            namespace stdheap
            {
                // Globals
                Slab*       g_slab_head      = NP_SLAB;
                size_t      g_next_slab_size = (size_t)4194304;   // 4 MB
                size_t      g_slab_size_cap  = (size_t)67108864;  // 64 MB
                size_t      g_large_used     = (size_t)0;         // live large-block count

                // Block table: open-addressed hash map, stored in its own OS slab
                BlockEntry* g_table          = (BlockEntry*)0;
                size_t      g_table_cap      = (size_t)0;   // entry capacity
                size_t      g_table_count    = (size_t)0;   // live entries
                size_t      g_table_slab_cap = (size_t)0;   // byte size of table OS slab

                // Segregated free list bins (indices 0-8)
                FreeNode* g_bin_0 = NP_FREENODE,
                          g_bin_1 = NP_FREENODE,
                          g_bin_2 = NP_FREENODE,
                          g_bin_3 = NP_FREENODE,
                          g_bin_4 = NP_FREENODE,
                          g_bin_5 = NP_FREENODE,
                          g_bin_6 = NP_FREENODE,
                          g_bin_7 = NP_FREENODE,
                          g_bin_8 = NP_FREENODE;

                // OS helpers

                def heap_os_alloc(size_t bytes) -> u64
                {
                    #ifdef __WINDOWS__
                    return VirtualAlloc((u64)0, bytes, (u32)0x3000, (u32)0x04);
                    #endif;
                    #ifdef __LINUX__
                    u64* p = mmap((u64)0, bytes, 3, 0x22, -1, (i64)0);
                    switch ((size_t)p == (size_t)U64MAXVAL) { case (1) { return (u64)0; } default {}; };
                    return (u64)p;
                    #endif;
                    #ifdef __MACOS__
                    u64* p = mmap((u64)0, bytes, 3, 0x1002, -1, (i64)0);
                    switch ((size_t)p == (size_t)U64MAXVAL) { case (1) { return (u64)0; } default {}; };
                    return (u64)p;
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
                        case (8) { return (size_t)4096; }
                        default  { return (size_t)4096; };
                    };
                    return (size_t)0;
                };

                def bin_pop(size_t cls) -> FreeNode*
                {
                    FreeNode* n = NP_FREENODE;
                    switch (cls)
                    {
                        case (0) { n = g_bin_0; switch (n != NP_FREENODE) { case (1) { g_bin_0 = n.next; } default {}; }; return n; }
                        case (1) { n = g_bin_1; switch (n != NP_FREENODE) { case (1) { g_bin_1 = n.next; } default {}; }; return n; }
                        case (2) { n = g_bin_2; switch (n != NP_FREENODE) { case (1) { g_bin_2 = n.next; } default {}; }; return n; }
                        case (3) { n = g_bin_3; switch (n != NP_FREENODE) { case (1) { g_bin_3 = n.next; } default {}; }; return n; }
                        case (4) { n = g_bin_4; switch (n != NP_FREENODE) { case (1) { g_bin_4 = n.next; } default {}; }; return n; }
                        case (5) { n = g_bin_5; switch (n != NP_FREENODE) { case (1) { g_bin_5 = n.next; } default {}; }; return n; }
                        case (6) { n = g_bin_6; switch (n != NP_FREENODE) { case (1) { g_bin_6 = n.next; } default {}; }; return n; }
                        case (7) { n = g_bin_7; switch (n != NP_FREENODE) { case (1) { g_bin_7 = n.next; } default {}; }; return n; }
                        case (8) { n = g_bin_8; switch (n != NP_FREENODE) { case (1) { g_bin_8 = n.next; } default {}; }; return n; }
                        default  {};
                    };
                    return NP_FREENODE;
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

                // Block table

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

                    u64 raw = heap_os_alloc(new_bytes);
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

                    g_table_count = (size_t)0;

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
                                g_table_count++;
                            }
                            default {};
                        };
                        j++;
                    };

                    // Remove the stale BLOCK_TABLE entry for the old slab that was
                    // rehashed into new_tbl, then release the old slab.
                    u64 old_tbl_addr = (u64)g_table;
                    size_t rm_idx = table_hash(old_tbl_addr, new_cap);
                    bool rm_found = false;
                    while (new_tbl[rm_idx].key != (u64)0)
                    {
                        switch (new_tbl[rm_idx].key == old_tbl_addr)
                        {
                            case (1)
                            {
                                new_tbl[rm_idx].key = (u64)0;
                                g_table_count--;
                                // Backward-shift deletion to close the gap
                                size_t rm_hole = rm_idx;
                                size_t rm_next = (rm_idx + (size_t)1) & (new_cap - (size_t)1);
                                while (new_tbl[rm_next].key != (u64)0)
                                {
                                    size_t rm_natural = table_hash(new_tbl[rm_next].key, new_cap);
                                    bool rm_shift;
                                    switch (rm_hole < rm_next)
                                    {
                                        case (1)
                                        {
                                            bool rm_in_range;
                                            switch (rm_natural > rm_hole)
                                            {
                                                case (1)
                                                {
                                                    switch (rm_natural <= rm_next)
                                                    {
                                                        case (1) { rm_in_range = true; }
                                                        default  { rm_in_range = false; };
                                                    };
                                                }
                                                default { rm_in_range = false; };
                                            };
                                            switch (rm_in_range)
                                            {
                                                case (1) { rm_shift = false; }
                                                default  { rm_shift = true; };
                                            };
                                        }
                                        default
                                        {
                                            bool rm_in_range;
                                            switch (rm_natural > rm_hole)
                                            {
                                                case (1) { rm_in_range = true; }
                                                default
                                                {
                                                    switch (rm_natural <= rm_next)
                                                    {
                                                        case (1) { rm_in_range = true; }
                                                        default  { rm_in_range = false; };
                                                    };
                                                };
                                            };
                                            switch (rm_in_range)
                                            {
                                                case (1) { rm_shift = false; }
                                                default  { rm_shift = true; };
                                            };
                                        };
                                    };
                                    switch (rm_shift)
                                    {
                                        case (1)
                                        {
                                            new_tbl[rm_hole].key  = new_tbl[rm_next].key;
                                            new_tbl[rm_hole].size = new_tbl[rm_next].size;
                                            new_tbl[rm_hole].kind = new_tbl[rm_next].kind;
                                            new_tbl[rm_hole].slab = new_tbl[rm_next].slab;
                                            new_tbl[rm_next].key  = (u64)0;
                                            rm_hole = rm_next;
                                        }
                                        default {};
                                    };
                                    rm_next = (rm_next + (size_t)1) & (new_cap - (size_t)1);
                                };
                                rm_found = true;
                            }
                            default {};
                        };
                        switch (rm_found) { case (1) { break; } default {}; };
                        rm_idx = (rm_idx + (size_t)1) & (new_cap - (size_t)1);
                    };

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

                    u64 raw = heap_os_alloc(initial_bytes);
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

                                // Backward-shift deletion: slide each following entry one slot
                                // back if its natural home is at or before the vacant slot,
                                // stopping when we reach an empty slot or wrap all the way around.
                                size_t hole = idx;
                                size_t next = (idx + (size_t)1) & (g_table_cap - (size_t)1);
                                while (g_table[next].key != (u64)0)
                                {
                                    size_t natural = table_hash(g_table[next].key, g_table_cap);
                                    // Determine whether this entry belongs at or before the hole.
                                    // We need to account for wrap-around: entry should shift back
                                    // if the hole is between its natural slot and its current slot.
                                    // Shift this entry back to fill the hole if its natural
                                    // home is NOT strictly between hole (exclusive) and next
                                    // (inclusive) in the forward/non-wrapping direction.
                                    // In other words: do NOT shift only when hole < natural <= next.
                                    // When the probe run wraps (next < hole), the non-shift region
                                    // is hole < natural (and natural did not wrap past 0) -- i.e.
                                    // natural > hole && natural <= next is impossible when next < hole
                                    // so instead: no-shift when natural > hole && next >= natural is
                                    // replaced by: no-shift when !(natural <= hole || natural > next).
                                    bool should_shift;
                                    switch (hole < next)
                                    {
                                        case (1)
                                        {
                                            // Normal (non-wrapping) run: shift unless hole < natural <= next
                                            bool in_range;
                                            switch (natural > hole)
                                            {
                                                case (1)
                                                {
                                                    switch (natural <= next)
                                                    {
                                                        case (1) { in_range = true; }
                                                        default  { in_range = false; };
                                                    };
                                                }
                                                default { in_range = false; };
                                            };
                                            switch (in_range)
                                            {
                                                case (1) { should_shift = false; }
                                                default  { should_shift = true; };
                                            };
                                        }
                                        default
                                        {
                                            // Wrapping run (next < hole): shift unless natural is in
                                            // (hole, cap) union [0, next] -- i.e. natural > hole OR natural <= next
                                            bool in_range;
                                            switch (natural > hole)
                                            {
                                                case (1) { in_range = true; }
                                                default
                                                {
                                                    switch (natural <= next)
                                                    {
                                                        case (1) { in_range = true; }
                                                        default  { in_range = false; };
                                                    };
                                                };
                                            };
                                            switch (in_range)
                                            {
                                                case (1) { should_shift = false; }
                                                default  { should_shift = true; };
                                            };
                                        };
                                    };
                                    switch (should_shift)
                                    {
                                        case (1)
                                        {
                                            g_table[hole].key  = g_table[next].key;
                                            g_table[hole].size = g_table[next].size;
                                            g_table[hole].kind = g_table[next].kind;
                                            g_table[hole].slab = g_table[next].slab;
                                            g_table[next].key  = (u64)0;
                                            hole = next;
                                        }
                                        default {};
                                    };
                                    next = (next + (size_t)1) & (g_table_cap - (size_t)1);
                                };
                                return;
                            }
                            default {};
                        };
                        idx = (idx + (size_t)1) & (g_table_cap - (size_t)1);
                    };
                };

                // Data slab management
                def slab_header_size() -> size_t
                {
                    return (size_t)40;  // sizeof(Slab)
                };

                def heap_new_slab(size_t min_capacity) -> Slab*
                {
                    size_t sz = g_next_slab_size;
                    switch (min_capacity + slab_header_size() > sz)
                    {
                        case (1) { sz = min_capacity + slab_header_size(); }
                        default  {};
                    };

                    u64 raw = heap_os_alloc(sz);
                    switch (raw == (u64)0) { case (1) { return (Slab*)0; } default {}; };

                    Slab* slab    = (Slab*)raw;
                    slab.base     = (u64)raw;
                    slab.capacity = sz;
                    slab.frontier = slab_header_size();
                    slab.used     = (size_t)0;
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

                // Public API

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

                            // slab field stores OS allocation size so ffree can release correctly
                            switch (!table_insert(raw, size, (u64)1, size))
                            {
                                case (1)
                                {
                                    heap_os_free(raw, size);
                                    return (u64)0;
                                }
                                default {};
                            };

                            g_large_used++;
                            return raw;
                        }
                        default {};
                    };

                    // Small: try free list bin first
                    FreeNode* node = bin_pop(cls);
                    switch (node != NP_FREENODE)
                    {
                        case (1)
                        {
                            u64 ptr = (u64)node;
                            // Find which slab owns this block, increment its counter,
                            // then store the slab pointer in the table entry
                            Slab* owner = (Slab*)0;
                            Slab* s = g_slab_head;
                            while (s != (Slab*)0)
                            {
                                switch (ptr >= s.base & ptr < s.base + (u64)s.capacity)
                                {
                                    case (1) { s.used++; owner = s; s = (Slab*)0; }
                                    default  { s = s.next; };
                                };
                            };
                            // Re-insert into table as live (kind=0), storing owning slab
                            table_insert(ptr, cls, (u64)0, (u64)owner);
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

                    switch (!table_insert(ptr, cls, (u64)0, (u64)g_slab_head))
                    {
                        case (1) { return (u64)0; }
                        default  {};
                    };

                    g_slab_head.used++;
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
                            // Large block: release immediately, decrement large counter
                            g_large_used--;
                            heap_os_free(ptr, (size_t)slab);
                            return;
                        }
                        default {};
                    };

                    // Small block: decrement owning slab counter, return to bin
                    Slab* owner = (Slab*)slab;
                    switch (owner != (Slab*)0)
                    {
                        case (1) { switch (owner.used > (size_t)0) { case (1) { owner.used--; } default {}; }; }
                        default  {};
                    };
                    bin_push(size, (FreeNode*)ptr);
                };

                def ffree(byte* ptr) -> void
                {
                    ffree((u64)ptr);
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
                            // Large block: same size, no move needed
                            bool same = old_size == new_size;
                            switch (same)
                            {
                                case (1) { return ptr; }
                                default  {};
                            };
                            // Shrinking or growing: fall through to move path below.
                            // Shrinking releases excess OS memory; growing gets more.
                        }
                        default
                        {
                            size_t old_cls = old_size;
                            size_t new_cls = size_class(new_size);

                            // Same class: fits as-is, no move
                            bool same = new_cls == old_cls;
                            switch (same) { case (1) { return ptr; } default {}; };

                            // Shrinking to a smaller class: data fits in current block, no move needed
                            bool shrink = new_cls < old_cls;
                            switch (shrink) { case (1) { return ptr; } default {}; };

                            // Growing: check if the target bin has a free block before bumping
                            size_t copy_size = class_block_size(old_cls);
                            switch (new_size < copy_size) { case (1) { copy_size = new_size; } default {}; };

                            FreeNode* reuse = bin_pop(new_cls);
                            bool has_reuse = reuse != NP_FREENODE;
                            switch (has_reuse)
                            {
                                case (1)
                                {
                                    u64 new_ptr = (u64)reuse;
                                    // Find and increment owning slab for new_ptr
                                    Slab* new_owner = (Slab*)0;
                                    Slab* ws = g_slab_head;
                                    while (ws != (Slab*)0)
                                    {
                                        switch (new_ptr >= ws.base & new_ptr < ws.base + (u64)ws.capacity)
                                        {
                                            case (1) { ws.used++; new_owner = ws; ws = (Slab*)0; }
                                            default  { ws = ws.next; };
                                        };
                                    };
                                    table_insert(new_ptr, new_cls, (u64)0, (u64)new_owner);
                                    byte* src = (byte*)ptr;
                                    byte* dst = (byte*)new_ptr;
                                    size_t i = (size_t)0;
                                    while (i < copy_size) { dst[i] = src[i]; i++; };
                                    // Decrement old ptr's slab used counter before removing
                                    Slab* old_owner = (Slab*)entry.slab;
                                    switch (old_owner != (Slab*)0)
                                    {
                                        case (1) { switch (old_owner.used > (size_t)0) { case (1) { old_owner.used--; } default {}; }; }
                                        default  {};
                                    };
                                    table_remove(ptr);
                                    bin_push(old_cls, (FreeNode*)ptr);
                                    return new_ptr;
                                }
                                default {};
                            };

                            // No free block in bin Ã¢â‚¬â€ bump allocate, copy, free old
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

                    // Large block growing or shrinking to small: must move
                    u64 new_ptr = fmalloc(new_size);
                    switch (new_ptr == (u64)0) { case (1) { return (u64)0; } default {}; };
                    byte* src = (byte*)ptr;
                    byte* dst = (byte*)new_ptr;
                    size_t copy_size = old_size;
                    switch (new_size < old_size) { case (1) { copy_size = new_size; } default {}; };
                    size_t i = (size_t)0;
                    while (i < copy_size) { dst[i] = src[i]; i++; };
                    ffree(ptr);
                    return new_ptr;
                };

                // Walk all small-block slabs and release any whose used counter
                // has reached zero back to the OS.  Free-list nodes belonging to
                // released slabs are removed from their bins before the slab is
                // freed so dangling pointers are never left in the bins.
                def coalesce_heap() -> void
                {
                    Slab* slab = g_slab_head;
                    Slab* prev = (Slab*)0;

                    while (slab != (Slab*)0)
                    {
                        Slab* next = slab.next;

                        switch (slab.used == (size_t)0)
                        {
                            case (1)
                            {
                                // Purge every free-list node that lives inside this slab
                                // from all nine bins.
                                size_t bin_idx = (size_t)0;
                                while (bin_idx <= (size_t)8)
                                {
                                    FreeNode* node = bin_pop(bin_idx);
                                    FreeNode* keep_head = NP_FREENODE;
                                    FreeNode* keep_tail = NP_FREENODE;

                                    while (node != NP_FREENODE)
                                    {
                                        u64 addr = (u64)node;
                                        FreeNode* node_next = node.next;

                                        switch (addr >= slab.base & addr < slab.base + (u64)slab.capacity)
                                        {
                                            // Node is inside the slab being released: discard it.
                                            case (1) {}
                                            default
                                            {
                                                // Node belongs to a different slab: keep it.
                                                node.next = NP_FREENODE;
                                                switch (keep_tail == NP_FREENODE)
                                                {
                                                    case (1)
                                                    {
                                                        keep_head = node;
                                                        keep_tail = node;
                                                    }
                                                    default
                                                    {
                                                        keep_tail.next = node;
                                                        keep_tail      = node;
                                                    };
                                                };
                                            };
                                        };

                                        node = node_next;
                                    };

                                    // Re-push survivors back into the bin in order.
                                    FreeNode* reinsert = keep_head;
                                    while (reinsert != NP_FREENODE)
                                    {
                                        FreeNode* reinsert_next = reinsert.next;
                                        bin_push(bin_idx, reinsert);
                                        reinsert = reinsert_next;
                                    };

                                    bin_idx++;
                                };

                                // Unlink the slab from the chain.
                                switch (prev == (Slab*)0)
                                {
                                    case (1) { g_slab_head = next; }
                                    default  { prev.next   = next; };
                                };

                                heap_os_free(slab.base, slab.capacity);
                            }
                            default
                            {
                                prev = slab;
                            };
                        };

                        slab = next;
                    };
                };

                // Returns a fragmentation estimate in the range [0.0, 1.0].
                // The value is the ratio of free (binned) small-block bytes plus
                // live large-block count to total tracked capacity.
                // 0.0 means no fragmentation, 1.0 means entirely fragmented.
                def check_fragmentation() -> float
                {
                    // Sum usable capacity and live bytes across all small slabs.
                    size_t total_capacity = (size_t)0;
                    size_t total_used     = (size_t)0;

                    Slab* slab = g_slab_head;
                    while (slab != (Slab*)0)
                    {
                        // Usable capacity excludes the slab header.
                        size_t usable = slab.capacity - slab_header_size();
                        total_capacity += usable;
                        // used counts live small blocks; free bytes = usable - used*avg_block
                        // We track used as a block count not byte count, so we use
                        // frontier as a proxy for committed bytes instead.
                        total_used += slab.used;
                        slab = slab.next;
                    };

                    switch (total_capacity == (size_t)0)
                    {
                        case (1)
                        {
                            // No slabs yet; include large blocks if any.
                            switch (g_large_used > (size_t)0)
                            {
                                case (1) { return 1.0; }
                                default  { return 0.0; };
                            };
                        }
                        default {};
                    };

                    // free_blocks = frontier bytes committed minus live blocks.
                    // Fragmentation rises as free blocks accumulate relative to
                    // total committed space.  Large blocks are live so they do
                    // not contribute free bytes but are added to used.
                    size_t committed = (size_t)0;
                    slab = g_slab_head;
                    while (slab != (Slab*)0)
                    {
                        committed += slab.frontier - slab_header_size();
                        slab = slab.next;
                    };

                    size_t all_used = total_used + g_large_used;

                    switch (committed == (size_t)0)
                    {
                        case (1) { return 0.0; }
                        default  {};
                    };

                    // free_bytes = committed space that has been bumped but is
                    // currently sitting in a bin waiting to be reused.
                    // We approximate: each used block occupies at least 16 bytes
                    // (smallest class), free = committed - used*16 clamped to 0.
                    size_t used_bytes = all_used * (size_t)16;
                    switch (used_bytes > committed)
                    {
                        case (1) { used_bytes = committed; }
                        default  {};
                    };
                    size_t free_bytes = committed - used_bytes;

                    float frag = (float)free_bytes / (float)committed;
                    return frag;
                };

            };

            namespace stdstack
            {
                // ===== STACK ALLOCATOR =====
                object StackAllocator
                {
                    byte* buffer;
                    size_t capacity, offset;
                    
                    def __init(size_t size) -> this
                    {
                        this.capacity = size;
                        this.offset = (size_t)0;
                        this.buffer = (byte*)stdheap::fmalloc(size);
                        return this;
                    };
                    
                    def __exit() -> void
                    {
                        switch (this.buffer != 0)
                        {
                            case (true)
                            {
                                stdheap::ffree((u64)this.buffer);
                            }
                            default {};
                        };
                    };
                    
                    def allocate(size_t size) -> void_ptr
                    {
                        bool b = (this.offset + size) > this.capacity;
                        switch (b)
                        {
                            case (true)
                            {
                                return STDLIB_GVP;
                            }
                            default
                            {
                                u64* ptr = (void_ptr)(this.buffer + this.offset);
                                this.offset += size;
                                return ptr;
                            };
                        };
                        return STDLIB_GVP;
                    };
                    
                    def reset() -> void
                    {
                        this.offset = (size_t)0;
                    };
                    
                    def get_used() -> size_t
                    {
                        return this.offset;
                    };
                    
                    def get_available() -> size_t
                    {
                        return this.capacity - this.offset;
                    };
                    
                    def get_capacity() -> size_t
                    {
                        return this.capacity;
                    };
                };
            };

            namespace stdpool
            {
                // ===== POOL ALLOCATOR =====
                //
                // Fixed-size block pool backed by a single stdheap allocation.
                // All blocks are the same size (block_size), carved at init.
                // A free list threaded through the blocks themselves gives O(1)
                // alloc and free.
                // allocate() returns null when all blocks are in use.
                // Individual blocks are returned via deallocate(void_ptr ptr).
                // __exit() releases the backing buffer back to stdheap.

                object PoolAllocator
                {
                    byte*     buffer;
                    size_t    block_size, block_count;
                    FreeNode* free_head;

                    def __init(size_t bsize, size_t bcount) -> this
                    {
                        // Enforce a minimum block size large enough to hold a
                        // FreeNode pointer so the free list can live in-place.
                        size_t actual_bsize = bsize;
                        switch (actual_bsize < (size_t)8)
                        {
                            case (1) { actual_bsize = (size_t)8; }
                            default  {};
                        };

                        this.block_size  = actual_bsize;
                        this.block_count = bcount;
                        this.buffer      = (byte*)stdheap::fmalloc(actual_bsize * bcount);
                        this.free_head   = NP_FREENODE;

                        // Build the free list by threading every block together.
                        switch (this.buffer != (byte*)0)
                        {
                            case (1)
                            {
                                size_t i = bcount;
                                while (i > (size_t)0)
                                {
                                    i--;
                                    FreeNode* node = (FreeNode*)(this.buffer + i * actual_bsize);
                                    node.next      = this.free_head;
                                    this.free_head = node;
                                };
                            }
                            default {};
                        };

                        return this;
                    };

                    def __exit() -> void
                    {
                        switch (this.buffer != (byte*)0)
                        {
                            case (1)
                            {
                                stdheap::ffree((u64)@this.buffer);
                            }
                            default {};
                        };
                    };

                    // Returns a pointer to a free block, or null if the pool is
                    // exhausted.
                    def allocate() -> void_ptr
                    {
                        switch (this.free_head == NP_FREENODE)
                        {
                            case (1) { return (void_ptr)0; }
                            default  {};
                        };

                        FreeNode* node = this.free_head;
                        this.free_head = node.next;
                        return (void_ptr)node;
                    };

                    // Return a previously allocated block back to the pool.
                    // Passing a pointer not belonging to this pool is undefined
                    // behaviour.
                    def deallocate(void_ptr ptr) -> void
                    {
                        switch (ptr == (void_ptr)0)
                        {
                            case (1) { return; }
                            default  {};
                        };

                        FreeNode* node = (FreeNode*)ptr;
                        node.next      = this.free_head;
                        this.free_head = node;
                    };

                    def get_block_size() -> size_t
                    {
                        return this.block_size;
                    };

                    def get_block_count() -> size_t
                    {
                        return this.block_count;
                    };

                    // Returns the number of blocks currently available.
                    def get_free_count() -> size_t
                    {
                        size_t    count = (size_t)0;
                        FreeNode* node  = this.free_head;
                        while (node != NP_FREENODE)
                        {
                            count++;
                            node = node.next;
                        };
                        return count;
                    };
                };
            };

            namespace stdring
            {
                // ===== RING (CIRCULAR) ALLOCATOR =====
                //
                // Fixed-capacity FIFO bump allocator backed by a single stdheap
                // allocation.  The write pointer advances on each allocate() call
                // and wraps back to the start when it would exceed the capacity,
                // overwriting the oldest data.
                //
                // allocate() returns a RingAllocResult* (backed by a small
                // per-call descriptor stored in the ring buffer itself ahead of
                // the user data):
                //   ptr     - pointer to the usable region
                //   wrapped - true if the write pointer wrapped this call
                //
                // If size > capacity (request can never fit) both ptr and
                // wrapped carry null/false and the descriptor pointer itself is
                // null.
                //
                // __exit() releases the backing buffer back to stdheap.

                object RingAllocator
                {
                    byte*            buffer;
                    size_t           capacity, write_pos;
                    RingAllocResult* rallocresult;

                    def __init(size_t size) -> this
                    {
                        this.capacity     = size;
                        this.write_pos    = (size_t)0;
                        this.buffer       = (byte*)stdheap::fmalloc(size);
                        this.rallocresult = (RingAllocResult*)stdheap::fmalloc((size_t)16);
                        return this;
                    };

                    def __exit() -> void
                    {
                        switch (this.buffer != (byte*)0)
                        {
                            case (1)
                            {
                                stdheap::ffree((u64)@this.buffer);
                            }
                            default {};
                        };
                        switch (this.rallocresult != (RingAllocResult*)0)
                        {
                            case (1)
                            {
                                stdheap::ffree((u64)@this.rallocresult);
                            }
                            default {};
                        };
                    };

                    // Allocate `size` bytes from the ring.
                    // Returns a pointer to the persistent rallocresult member
                    // describing the outcome.  The result is valid until the
                    // next call to allocate().
                    // Returns null if size > capacity (can never fit).
                    def allocate(size_t size) -> RingAllocResult*
                    {
                        // Request can never fit in the buffer at all.
                        switch (size > this.capacity)
                        {
                            case (1) { return (RingAllocResult*)0; }
                            default  {};
                        };

                        bool wrapped = false;

                        // Check if we need to wrap.
                        switch (this.write_pos + size > this.capacity)
                        {
                            case (1)
                            {
                                this.write_pos = (size_t)0;
                                wrapped        = true;
                            }
                            default {};
                        };

                        // The user region is carved directly from the buffer.
                        u64* user_ptr   = (void_ptr)(this.buffer + this.write_pos);
                        this.write_pos  += size;

                        this.rallocresult.ptr     = user_ptr;
                        this.rallocresult.wrapped = wrapped;

                        return this.rallocresult;
                    };

                    def get_capacity() -> size_t
                    {
                        return this.capacity;
                    };

                    def get_write_pos() -> size_t
                    {
                        return this.write_pos;
                    };

                    def reset() -> void
                    {
                        this.write_pos = (size_t)0;
                    };
                };
            };
        };
    };
};

#endif;