#import "standard.fx";
//#import "redallocators.fx";

#ifdef __WINDOWS__
extern
{
    def !!
        VirtualAlloc(u64, size_t, u32, u32) -> u64,
        VirtualFree(u64, size_t, u32)       -> bool;
};
#endif;

struct BlockEntry
{
    u64  key;
    size_t size;
    u64    kind;
    u64  slab;
};

// ── Slab descriptor ───────────────────────────────────────────────────

struct Slab
{
    u64  base;
    size_t capacity,frontier;
    Slab*  next;
};

// ── Free list node (lives in the free block's own memory) ─────────────

struct FreeNode
{
    FreeNode* next;
};


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

            def heap_os_alloc(size_t bytes) -> u64
            {
                #ifdef __WINDOWS__
                return VirtualAlloc((u64)0, bytes, (u32)0x3000, (u32)0x04);
                #endif;
                #ifdef __LINUX__
                u64* p = mmap((u64)0, bytes, 3, 0x22, -1, (i64)0);
                if ((size_t)p == (size_t)0xFFFFFFFFFFFFFFFF) { return (u64)0; };
                return p;
                #endif;
                #ifdef __MACOS__
                u64* p = mmap((u64)0, bytes, 3, 0x1002, -1, (i64)0);
                if ((size_t)p == (size_t)0xFFFFFFFFFFFFFFFF) { return (u64)0; };
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
                    case (0)
                    {
                        n = g_bin_0;
                        bool b = n != (FreeNode*)0;
                        switch (b)
                        {
                            case (1)
                            {
                                g_bin_0 = n.next;
                            }
                            default {};
                        };
                        return n;
                    }

                    default  {};
                };
                return (FreeNode*)0;
            };

def main() -> int
{
	return 0;
};