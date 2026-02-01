#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_MEMORY
#def FLUX_STANDARD_MEMORY 1;

extern
{
    def !!malloc(int size) -> void*;
    def !!free(void* ptr) -> void;
};

namespace standard
{
	namespace memory
	{
		// ============ MEMORY UTILITIES ============

		// Memory copy (simple byte-by-byte implementation)
		def memcpy(void* dest, void* src, size_t n) -> void*
		{
		    byte* d = (byte*)dest;
		    byte* s = (byte*)src;
		    
		    for (size_t i = 0; i < n; i++)
		    {
		        d[i] = s[i];
		    };
		    
		    return dest;
		};

		// Memory move (handles overlapping regions)
		def memmove(void* dest, void* src, size_t n) -> void*
		{
		    byte* d = (byte*)dest;
		    byte* s = (byte*)src;
		    
		    if (d < s)
		    {
		        for (size_t i = 0; i < n; i++)
		        {
		            d[i] = s[i];
		        };
		    }
		    else
		    {
		        for (size_t i = n; i > 0; i--)
		        {
		            d[i-1] = s[i-1];
		        };
		    };
		    
		    return dest;
		};

		// Memory set
		def memset(void* ptr, byte value, size_t n) -> void*
		{
		    byte* p = (byte*)ptr;
		    
		    for (size_t i = 0; i < n; i++)
		    {
		        p[i] = value;
		    };
		    
		    return ptr;
		};

		def memcmp(void* ptr1, void* ptr2, size_t n) -> i32
		{
		    byte* p1 = (byte*)ptr1;
		    byte* p2 = (byte*)ptr2;
		    
		    for (size_t i = 0; i < n; i++)
		    {
		        if (p1[i] != p2[i])
		        {
		            return (i32)p1[i] - (i32)p2[i];
		        };
		    };
		    
		    return 0;
		};

		// Zero memory
		def bzero(void* ptr, size_t n) -> void
		{
		    return (void)memset(ptr, (i8)0, n);
		};
	};
};

using standard::memory;

#endif;