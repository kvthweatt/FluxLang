#import "standard.fx";

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
    };
};

def main() -> int
{
    return 0;
};