#import "redtypes.fx";

namespace test
{
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

        def free_all() -> void;
        
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

        def free_all() -> void
        {
        };
    };
};

def main() -> int
{
	return 0;
};

def !!FRTStartup()->int {return main();};