// redmemman.fx - Memory Management Library

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

extern
{
    // Memory allocation
    def !!malloc(size_t) -> void*,
          memcpy(void*, void*, size_t) -> void*,
          free(void*) -> void,
          calloc(size_t, size_t) -> void*,
          realloc(void*, size_t) -> void*,
          memcpy(void*, void*, size_t) -> void*,
          memmove(void*, void*, size_t) -> void*,
          memset(void*, int, size_t) -> void*,
          memcmp(void*, void*, size_t) -> int,
          strlen(const char*) -> size_t,
          strcpy(char*, const char*) -> char,
          strncpy(char*, const char*, size_t) -> char,
          strcat(char*, const char*) -> char,
          strncat(char*, const char*, size_t) -> char,
          strcmp(const char*, const char*) -> int,
          strncmp(const char*, const char*, size_t) -> int,
          strchr(const char*, int) -> char,
          strstr(const char*, const char*) -> char*,
          abort() -> void,
          exit(int) -> void,
          atexit(void*) -> int;
};

#ifndef FLUX_STANDARD_MEMORY_MANAGEMENT
#def FLUX_STANDARD_MEMORY_MANAGEMENT 1;
///
namespace standard
{
    namespace memory
    {
        // ===== MEMORY BLOCK HEADER =====
        struct MemoryBlockHeader
        {
            size_t size;
            bool is_free;
            MemoryBlockHeader* next, prev;
        };
        
        // ===== HEAP ALLOCATOR =====
        object HeapAllocator
        {
            MemoryBlockHeader* head;
            size_t total_allocated, total_freed, block_count;
            
            def __init() -> this
            {
                this.head = (MemoryBlockHeader*)0;
                this.total_allocated = (size_t)0;
                this.total_freed = (size_t)0;
                this.block_count = (size_t)0;
                return this;
            };
            
            def __exit() -> void
            {
                this.free_all();
                return;
            };
            
            def allocate(size_t size) -> void*
            {
                if (size == (size_t)0)
                {
                    return (void*)0;
                };
                
                // Try to find a free block of sufficient size
                MemoryBlockHeader* current = this.head;
                while (current != (MemoryBlockHeader*)0)
                {
                    if (current.is_free & current.size >= size)
                    {
                        current.is_free = false;
                        return (void*)(current + (size_t)1);
                    };
                    current = current.next;
                };
                
                // No suitable block found, allocate new one
                size_t total_size = sizeof(MemoryBlockHeader) + size;
                MemoryBlockHeader* block = (MemoryBlockHeader*)malloc(total_size);
                
                if (block == (MemoryBlockHeader*)0)
                {
                    return (void*)0;
                };
                
                block.size = size;
                block.is_free = false;
                block.next = this.head;
                block.prev = (MemoryBlockHeader*)0;
                
                if (this.head != (MemoryBlockHeader*)0)
                {
                    this.head.prev = block;
                };
                
                this.head = block;
                this.total_allocated += size;
                this.block_count++;
                
                return (void*)(block + (size_t)1);
            };
            
            def deallocate(void* ptr) -> bool
            {
                if (ptr == (void*)0)
                {
                    return false;
                };
                
                MemoryBlockHeader* block = ((MemoryBlockHeader*)ptr) - (size_t)1;
                
                if (block.is_free)
                {
                    return false;
                };
                
                block.is_free = true;
                this.total_freed += block.size;
                
                return true;
            };
            
            def reallocate(void* ptr, size_t new_size) -> void*
            {
                if (ptr == (void*)0)
                {
                    return this.allocate(new_size);
                };
                
                if (new_size == (size_t)0)
                {
                    this.deallocate(ptr);
                    return (void*)0;
                };
                
                MemoryBlockHeader* block = ((MemoryBlockHeader*)ptr) - (size_t)1;
                
                if (block.size >= new_size)
                {
                    return ptr;
                };
                
                void* new_ptr = this.allocate(new_size);
                if (new_ptr == (void*)0)
                {
                    return (void*)0;
                };
                
                memcpy(new_ptr, ptr, block.size);
                this.deallocate(ptr);
                
                return new_ptr;
            };
            
            def free_all() -> void
            {
                MemoryBlockHeader* current = this.head;
                
                while (current != (MemoryBlockHeader*)0)
                {
                    MemoryBlockHeader* next = current.next;
                    (void)current;
                    current = next;
                };
                
                this.head = (MemoryBlockHeader*)0;
                this.total_allocated = (size_t)0;
                this.total_freed = (size_t)0;
                this.block_count = (size_t)0;
            };
            
            def get_allocated() -> size_t
            {
                return this.total_allocated;
            };
            
            def get_freed() -> size_t
            {
                return this.total_freed;
            };
            
            def get_in_use() -> size_t
            {
                return this.total_allocated - this.total_freed;
            };
            
            def get_block_count() -> size_t
            {
                return this.block_count;
            };
        };
        
        // ===== MEMORY POOL =====
        struct MemoryPoolBlock
        {
            byte[1024] buffer;
            bool in_use;
        };
        
        object MemoryPool
        {
            MemoryPoolBlock* blocks;
            size_t block_count, block_size, blocks_allocated, blocks_in_use;
            
            def __init(size_t count, size_t size) -> this
            {
                this.block_count = count;
                this.block_size = size;
                this.blocks_allocated = (size_t)0;
                this.blocks_in_use = (size_t)0;
                
                this.blocks = (MemoryPoolBlock*)calloc(count, sizeof(MemoryPoolBlock));
                
                if (this.blocks != (MemoryPoolBlock*)0)
                {
                    for (size_t i = (size_t)0; i < count; i++)
                    {
                        this.blocks[i].in_use = false;
                    };
                    this.blocks_allocated = count;
                };
                
                return this;
            };
            
            def __exit() -> void
            {
                if (this.blocks != (MemoryPoolBlock*)0)
                {
                    (void)this.blocks;
                };
                return;
            };
            
            def acquire() -> void*
            {
                for (size_t i = (size_t)0; i < this.block_count; i++)
                {
                    if (!this.blocks[i].in_use)
                    {
                        this.blocks[i].in_use = true;
                        this.blocks_in_use++;
                        return (void*)@this.blocks[i].buffer[0];
                    };
                };
                
                return (void*)0;
            };
            
            def release(void* ptr) -> bool
            {
                if (ptr == (void*)0)
                {
                    return false;
                };
                
                byte* base = (byte*)@this.blocks[0].buffer[0];
                byte* target = (byte*)ptr;
                
                size_t offset = (size_t)(target - base);
                size_t index = offset / sizeof(MemoryPoolBlock);
                
                if (index >= this.block_count)
                {
                    return false;
                };
                
                if (!this.blocks[index].in_use)
                {
                    return false;
                };
                
                this.blocks[index].in_use = false;
                this.blocks_in_use--;
                
                // Zero out the memory
                memset(@this.blocks[index].buffer[0], 0, (size_t)1024);
                
                return true;
            };
            
            def get_available() -> size_t
            {
                return this.block_count - this.blocks_in_use;
            };
            
            def get_in_use() -> size_t
            {
                return this.blocks_in_use;
            };
            
            def get_total() -> size_t
            {
                return this.block_count;
            };
            
            def is_full() -> bool
            {
                return this.blocks_in_use >= this.block_count;
            };
            
            def is_empty() -> bool
            {
                return this.blocks_in_use == (size_t)0;
            };
        };
        
        // ===== STACK ALLOCATOR =====
        object StackAllocator
        {
            byte* buffer;
            size_t capacity, offset;
            
            def __init(size_t size) -> this
            {
                this.capacity = size;
                this.offset = (size_t)0;
                this.buffer = (byte*)malloc(size);
                return this;
            };
            
            def __exit() -> void
            {
                if (this.buffer != (byte*)0)
                {
                    (void)this.buffer;
                };
                return;
            };
            
            def allocate(size_t size) -> void*
            {
                if (this.offset + size > this.capacity)
                {
                    return (void*)0;
                };
                
                void* ptr = (void*)(this.buffer + this.offset);
                this.offset += size;
                
                return ptr;
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
        
        // ===== ARENA ALLOCATOR =====
        struct ArenaBlock
        {
            byte* buffer;
            size_t size, used;
            ArenaBlock* next;
        };
        
        object ArenaAllocator
        {
            ArenaBlock* head;
            size_t default_block_size, total_allocated;
            
            def __init(size_t block_size) -> this
            {
                this.head = (ArenaBlock*)0;
                this.default_block_size = block_size;
                this.total_allocated = (size_t)0;
                return this;
            };
            
            def __exit() -> void
            {
                this.clear();
                return;
            };
            
            def allocate(size_t size) -> void*
            {
                if (size == (size_t)0)
                {
                    return (void*)0;
                };
                
                // Try to allocate from existing block
                if (this.head != (ArenaBlock*)0)
                {
                    if (this.head.used + size <= this.head.size)
                    {
                        void* ptr = (void*)(this.head.buffer + this.head.used);
                        this.head.used += size;
                        return ptr;
                    };
                };
                
                // Need a new block
                size_t block_size = this.default_block_size;
                if (size > block_size)
                {
                    block_size = size;
                };
                
                ArenaBlock* block = (ArenaBlock*)malloc(sizeof(ArenaBlock));
                if (block == (ArenaBlock*)0)
                {
                    return (void*)0;
                };
                
                block.buffer = (byte*)malloc(block_size);
                if (block.buffer == (byte*)0)
                {
                    (void)block;
                    return (void*)0;
                };
                
                block.size = block_size;
                block.used = size;
                block.next = this.head;
                
                this.head = block;
                this.total_allocated += block_size;
                
                return (void*)block.buffer;
            };
            
            def clear() -> void
            {
                ArenaBlock* current = this.head;
                
                while (current != (ArenaBlock*)0)
                {
                    ArenaBlock* next = current.next;
                    
                    if (current.buffer != (byte*)0)
                    {
                        (void)current.buffer;
                    };
                    
                    (void)current;
                    current = next;
                };
                
                this.head = (ArenaBlock*)0;
                this.total_allocated = (size_t)0;
            };
            
            def get_total_allocated() -> size_t
            {
                return this.total_allocated;
            };
        };
        
        // ===== MEMORY UTILITIES =====
        
        def mem_zero(void* ptr, size_t size) -> void
        {
            memset(ptr, 0, size);
        };
        
        def mem_fill(void* ptr, byte value, size_t size) -> void
        {
            memset(ptr, (int)value, size);
        };
        
        def mem_copy(void* dest, void* src, size_t size) -> void
        {
            memcpy(dest, src, size);
        };
        
        def mem_move(void* dest, void* src, size_t size) -> void
        {
            memmove(dest, src, size);
        };
        
        def mem_compare(void* a, void* b, size_t size) -> int
        {
            return memcmp(a, b, size);
        };
        
        def mem_equals(void* a, void* b, size_t size) -> bool
        {
            return memcmp(a, b, size) == 0;
        };
        
        // ===== ALIGNED ALLOCATION =====
        
        def align_forward(size_t addr, size_t alignment) -> size_t
        {
            size_t modulo = addr & (alignment - (size_t)1);
            if (modulo != (size_t)0)
            {
                addr += alignment - modulo;
            };
            return addr;
        };
        
        def is_aligned(size_t addr, size_t alignment) -> bool
        {
            return (addr & (alignment - (size_t)1)) == (size_t)0;
        };
        
        def malloc_aligned(size_t size, size_t alignment) -> void*
        {
            size_t total_size = size + alignment + sizeof(void*);
            void* raw = malloc(total_size);
            
            if (raw == (void*)0)
            {
                return (void*)0;
            };
            
            size_t raw_addr = (size_t)raw;
            size_t aligned_addr = align_forward(raw_addr + sizeof(void*), alignment);
            
            void** header = (void**)(aligned_addr - sizeof(void*));
            *header = raw;
            
            return (void*)aligned_addr;
        };
        
        def free_aligned(void* ptr) -> void
        {
            if (ptr == (void*)0)
            {
                return;
            };
            
            void** header = (void**)((size_t)ptr - sizeof(void*));
            void* raw = *header;
            (void)raw;
        };

        // ===== REFERENCE COUNTING =====
        
        struct RefCountHeader
        {
            size_t ref_count, size;
        };
        
        def ref_alloc(size_t size) -> void*
        {
            size_t total = sizeof(RefCountHeader) + size;
            RefCountHeader* header = (RefCountHeader*)malloc(total);
            
            if (header == (RefCountHeader*)0)
            {
                return (void*)0;
            };
            
            header.ref_count = (size_t)1;
            header.size = size;
            
            return (void*)(header + (size_t)1);
        };
        
        def ref_retain(void* ptr) -> void*
        {
            if (ptr == (void*)0)
            {
                return (void*)0;
            };
            
            RefCountHeader* header = ((RefCountHeader*)ptr) - (size_t)1;
            header.ref_count++;
            
            return ptr;
        };
        
        def ref_release(void* ptr) -> void
        {
            if (ptr == (void*)0)
            {
                return;
            };
            
            RefCountHeader* header = ((RefCountHeader*)ptr) - (size_t)1;
            
            if (header.ref_count > (size_t)0)
            {
                header.ref_count--;
            };
            
            if (header.ref_count == (size_t)0)
            {
                (void)header;
            };
        };
        
        def ref_count(void* ptr) -> size_t
        {
            if (ptr == (void*)0)
            {
                return (size_t)0;
            };
            
            RefCountHeader* header = ((RefCountHeader*)ptr) - (size_t)1;
            return header.ref_count;
        };
        
        // ===== MEMORY TRACKING =====
        
        struct MemoryStats
        {
            size_t allocations, deallocations, bytes_allocated, bytes_freed, peak_usage, current_usage;
        };
        
        //global MemoryStats g_mem_stats = {(size_t)0, (size_t)0, (size_t)0, (size_t)0, (size_t)0, (size_t)0};
        
        def tracked_malloc(size_t size) -> void*
        {
            void* ptr = malloc(size);
            
            if (ptr != (void*)0)
            {
                g_mem_stats.allocations++;
                g_mem_stats.bytes_allocated += size;
                g_mem_stats.current_usage += size;
                
                if (g_mem_stats.current_usage > g_mem_stats.peak_usage)
                {
                    g_mem_stats.peak_usage = g_mem_stats.current_usage;
                };
            };
            
            return ptr;
        };
        
        def tracked_free(void* ptr, size_t size) -> void
        {
            if (ptr != (void*)0)
            {
                (void)ptr;
                
                g_mem_stats.deallocations++;
                g_mem_stats.bytes_freed += size;
                g_mem_stats.current_usage -= size;
            };
        };
        
        def get_memory_stats() -> MemoryStats
        {
            return g_mem_stats;
        };
        
        def reset_memory_stats() -> void
        {
            g_mem_stats.allocations = (size_t)0;
            g_mem_stats.deallocations = (size_t)0;
            g_mem_stats.bytes_allocated = (size_t)0;
            g_mem_stats.bytes_freed = (size_t)0;
            g_mem_stats.peak_usage = (size_t)0;
            g_mem_stats.current_usage = (size_t)0;
        };
        
        // ===== BYTE MANIPULATION =====
        
        def swap_bytes(byte* a, byte* b) -> void
        {
            byte temp = *a;
            *a = *b;
            *b = temp;
        };
        
        def reverse_bytes(byte* buffer, size_t size) -> void
        {
            size_t i = (size_t)0;
            size_t j = size - (size_t)1;
            
            while (i < j)
            {
                swap_bytes(buffer + i, buffer + j);
                i++;
                j--;
            };
        };
        
        def copy_bytes(byte* dest, byte* src, size_t count) -> void
        {
            for (size_t i = (size_t)0; i < count; i++)
            {
                dest[i] = src[i];
            };
        };
        
        def zero_bytes(byte* buffer, size_t count) -> void
        {
            for (size_t i = (size_t)0; i < count; i++)
            {
                buffer[i] = (byte)0;
            };
        };
    };
};
///
using standard::memory;

#endif;
