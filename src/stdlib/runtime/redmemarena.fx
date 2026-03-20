// redmemarena.fx - Flux Memory Arena Allocator
//
//
// Arena Allocator - Based on the Standard Heap Allocator
    // Bump pointer allocation from OS-acquired slabs.
    // Individual frees are no-ops (arena owns all memory).
    // arena_reset() rewinds all slabs to empty without releasing OS memory.
    // arena_destroy() releases every slab back to the OS.
    // New slabs are chained when the current one is exhausted.
    // Slab size doubles each time, capped at 64 MB, matching the heap policy.
    // Alignment is always rounded up to the next 16-byte boundary.
    // Zero OS memory consumed until first arena_alloc call.
//
//

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_ALLOCATORS
#import "redallocators.fx";
#endif;

#ifndef FLUX_STANDARD_ARENA
#def FLUX_STANDARD_ARENA 1;

// -- Arena slab descriptor --------------------------------------------------
//
//  base     : raw OS pointer to the slab memory
//  capacity : total usable bytes in this slab
//  frontier : next free byte offset from base
//  next     : older slab in the chain (null = oldest)

struct ArenaSlab
{
    u64        base;
    size_t     capacity;
    size_t     frontier;
    ArenaSlab* next;
};

namespace standard
{
    namespace memory
    {
        namespace allocators
        {
            namespace arena
            {
                // -- Globals ------------------------------------------------

                global const ArenaSlab* NULLARENASLAB   = (ArenaSlab*)0;
                global ArenaSlab* g_arena_head          = NULLARENASLAB;
                global size_t     g_arena_next_slab_sz  = 4194304,  // 4 MB
                       size_t     g_arena_slab_sz_cap   = 67108864; // 64 MB

                // -- Internal helpers ---------------------------------------

                // Round size up to next 16-byte aligned value.
                def arena_align16(size_t size) -> size_t
                {
                    size_t mask = 15;
                    return (size + mask) & ~mask;
                };

                // Acquire a new OS slab large enough for `needed` bytes,
                // append it to the head of the chain, and return it.
                def arena_new_slab(size_t needed) -> ArenaSlab*
                {
                    // Determine slab byte count: at least needed, at least next growth size.
                    size_t slab_bytes = g_arena_next_slab_sz;
                    switch (needed > slab_bytes)
                    {
                        case (1) { slab_bytes = needed; }
                        default  {};
                    };

                    // Grow the next-slab-size for future slabs, capped at 64 MB.
                    size_t doubled = g_arena_next_slab_sz * (size_t)2;
                    switch (doubled <= g_arena_slab_sz_cap)
                    {
                        case (1) { g_arena_next_slab_sz = doubled; }
                        default  {};
                    };

                    // Allocate memory for the descriptor + data in one OS call.
                    size_t total = sizeof(ArenaSlab) + slab_bytes;
                    u64 raw = standard::memory::allocators::stdheap::heap_os_alloc(total);
                    switch (raw is void)
                    {
                        case (1) { return NULLARENASLAB; }
                        default  {};
                    };

                    // Descriptor lives at the very start of the OS allocation.
                    ArenaSlab* slab = (ArenaSlab*)raw;
                    slab.base     = raw + sizeof(ArenaSlab);
                    slab.capacity = slab_bytes;
                    slab.frontier = 0;
                    slab.next     = g_arena_head;
                    g_arena_head  = slab;

                    return slab;
                };

                // -- Public API ---------------------------------------------

                // Allocate `size` bytes from the arena.
                // Returns a non-null pointer on success, null on OOM.
                // Allocation size is rounded up to 16-byte alignment.
                def arena_alloc(size_t size) -> u64
                {
                    switch (size == 0)
                    {
                        case (1) { return 0; }
                        default  {};
                    };

                    size_t aligned = arena_align16(size);

                    // Try to satisfy from the current head slab.
                    switch (g_arena_head != NULLARENASLAB)
                    {
                        case (1)
                        {
                            ArenaSlab* slab = g_arena_head;
                            switch (slab.frontier + aligned <= slab.capacity)
                            {
                                case (1)
                                {
                                    u64 ptr = slab.base + (u64)slab.frontier;
                                    slab.frontier += aligned;
                                    return ptr;
                                }
                                default {};
                            };
                        }
                        default {};
                    };

                    // Current slab exhausted (or no slab yet); get a new one.
                    ArenaSlab* slab = arena_new_slab(aligned);
                    switch (slab == NULLARENASLAB)
                    {
                        case (1) { return 0; }
                        default  {};
                    };

                    u64 ptr = slab.base + (u64)slab.frontier;
                    slab.frontier += aligned;
                    return ptr;
                };

                // Free is a no-op for arena allocations.
                // Memory is reclaimed in bulk by arena_reset or arena_destroy.
                def arena_free(u64 ptr) -> void
                {
                    return;
                };

                // Reset the arena: rewind all slab frontiers to zero.
                // OS memory is retained for immediate reuse on the next cycle.
                def arena_reset() -> void
                {
                    ArenaSlab* slab = g_arena_head;
                    while (slab != NULLARENASLAB)
                    {
                        slab.frontier = 0;
                        slab = slab.next;
                    };
                    // Also reset the growth counter so the next alloc starts fresh.
                    g_arena_next_slab_sz = 4194304;
                };

                // Destroy the arena: release every slab back to the OS.
                // After this call the arena is in its initial empty state.
                def arena_destroy() -> void
                {
                    ArenaSlab* slab = g_arena_head;
                    while (slab != NULLARENASLAB)
                    {
                        ArenaSlab* next = slab.next;
                        size_t total    = sizeof(ArenaSlab) + slab.capacity;
                        standard::memory::allocators::stdheap::heap_os_free((u64)slab, total);
                        slab = next;
                    };
                    g_arena_head         = NULLARENASLAB;
                    g_arena_next_slab_sz = 4194304;
                };
            };
        };
    };
};

#endif;
