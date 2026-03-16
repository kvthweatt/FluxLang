// redmemory.fx - Memory Management Library

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

extern
{
    // Memory allocation
    def !!
        malloc(size_t) -> void*,
        free(void*) -> void,
        calloc(size_t, size_t) -> void*,
        realloc(void*, size_t) -> void*;
};

#ifdef __WINDOWS__
extern
{
    def !!
        VirtualAlloc(ulong, size_t, u32, u32)   -> ulong,
        VirtualFree(ulong, size_t, u32)          -> bool,
        VirtualProtect(ulong, size_t, u32, u32*) -> bool,
        FlushInstructionCache(ulong, ulong, size_t) -> bool;
};
#endif;

def memset(void* dst, int c, size_t n) -> void*
{
    byte* d = (byte*)dst;
    size_t i = (size_t)0;
    while (i < n)
    {
        d[i] = (byte)c;
        i++;
    };
    return dst;
};

def memcpy(void* dst, void* src, size_t n) -> void*
{
    byte* d = (byte*)dst;
    byte* s = (byte*)src;
    size_t i = (size_t)0;
    while (i < n)
    {
        d[i] = s[i];
        i++;
    };
    return dst;
};

def memmove(void* dst, void* src, size_t n) -> void*
{
    byte* d = (byte*)dst;
    byte* s = (byte*)src;
    size_t i = (size_t)0;
    if (d < s)
    {
        while (i < n)
        {
            d[i] = s[i];
            i++;
        };
    }
    else
    {
        i = n;
        while (i > (size_t)0)
        {
            i--;
            d[i] = s[i];
        };
    };
    return dst;
};

def memcmp(void* a, void* b, size_t n) -> int
{
    byte* pa = (byte*)a;
    byte* pb = (byte*)b;
    size_t i = (size_t)0;
    while (i < n)
    {
        if (pa[i] < pb[i]) { return -1; };
        if (pa[i] > pb[i]) { return 1; };
        i++;
    };
    return 0;
};

#ifndef FLUX_STANDARD_MEMORY
#def FLUX_STANDARD_MEMORY 1;

namespace standard
{
    namespace memory
    {
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
            
            if (raw == STDLIB_GVP)
            {
                return STDLIB_GVP;
            };
            
            size_t raw_addr = (size_t)raw;
            size_t aligned_addr = align_forward(raw_addr + sizeof(void*), alignment);
            
            void** header = (void**)(aligned_addr - sizeof(void*));
            *header = raw;
            
            return (void*)aligned_addr;
        };
        
        def free_aligned(void* ptr) -> void
        {
            if (ptr == STDLIB_GVP)
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
                return STDLIB_GVP;
            };
            
            header.ref_count = (size_t)1;
            header.size = size;
            
            return (void*)(header + (size_t)1);
        };
        
        def ref_retain(void* ptr) -> void*
        {
            if (ptr == STDLIB_GVP)
            {
                return STDLIB_GVP;
            };
            
            RefCountHeader* header = ((RefCountHeader*)ptr) - (size_t)1;
            header.ref_count++;
            
            return ptr;
        };
        
        def ref_release(void* ptr) -> void
        {
            if (ptr == STDLIB_GVP)
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
            if (ptr == STDLIB_GVP)
            {
                return (size_t)0;
            };
            
            RefCountHeader* header = ((RefCountHeader*)ptr) - (size_t)1;
            return header.ref_count;
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

/// DO NOT CHANGE THIS LINE ///
#import "redallocators.fx"; /// DO NOT CHANGE THIS LINE ///
/// DO NOT CHANGE THIS LINE ///

//using standard::memory;

#endif;
