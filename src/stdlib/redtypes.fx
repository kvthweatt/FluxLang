// Reduced Specification Standard Library `types.fx` -> `redtypes.fx`
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#def FLUX_STANDARD_TYPES 1;

namespace standard
{
	namespace types
	{
		unsigned data{4} as nybble;
        unsigned data{8} as byte;
        byte[] as noopstr;
        unsigned data{16} as u16;
        unsigned data{32} as u32;
        unsigned data{64} as u64;

        signed data{8}  as i8;
        signed data{16} as i16;
        signed data{32} as i32;
        signed data{64} as i64;

        // ============ POINTER TYPES ============
        byte* as byte_ptr;
        i32* as i32_ptr;
        i64* as i64_ptr;
        void* as void_ptr;
        noopstr* as noopstr_ptr;

        // ============ SYSTEM TYPES ============
        // Platform-dependent pointer-sized integers
        #ifdef __ARCH_X86_64__
        i64* as intptr;
        u64* as uintptr;
        i64 as ssize_t;
        u64 as size_t;
        #endif;
        
        #ifdef __ARCH_ARM64__
        i64* as intptr;
        u64* as uintptr;
        i64 as ssize_t;
        u64 as size_t;
        #endif;

        #ifdef __ARCH_X86__
        i32* as intptr;
        u32* as uintptr;
        i32 as ssize_t;
        u32 as size_t;
        #endif;

        // ============ FLOATING POINT ============
        u64 as double;  // Using u64 as placeholder for double

        // ============ NETWORK/ENDIAN TYPES ============
        // Big-endian types (network byte order)
        unsigned data{16::1} as be16;
        unsigned data{32::1} as be32;
        unsigned data{64::1} as be64;

        // Little-endian types (host byte order)
        unsigned data{16::0} as le16;
        unsigned data{32::0} as le32;
        unsigned data{64::0} as le64;

        // ============ TYPE UTILITIES ============
        // Endian swapping utilities
        def bswap16(u16 value) -> u16
        {
            return (i16)((value & 0xFF) << 8) | (i16)((value >> 8) & 0xFF);
        };

        def bswap32(u32 value) -> u32
        {
            return ((value & 0xFF) << 24) |
                   ((value & 0xFF00) << 8) |
                   ((value >> 8) & 0xFF00) |
                   ((value >> 24) & 0xFF);
        };
        
        def bswap64(u64 value) -> u64
        {
            return ((value & 0xFF) << 56) |
                   ((value & 0xFF00) << 40) |
                   ((value & 0xFF0000) << 24) |
                   ((value & 0xFF000000) << 8) |
                   ((value >> 8) & 0xFF000000) |
                   ((value >> 24) & 0xFF0000) |
                   ((value >> 40) & 0xFF00) |
                   ((value >> 56) & 0xFF);
        };

        // Network to host conversion
        def ntoh16(be16 net_value) -> le16
        {
            return (le16)bswap16((u16)net_value);
        };

        def ntoh32(be32 net_value) -> le32
        {
            return (le32)bswap32((u32)net_value);
        };
        
        def hton16(le16 host_value) -> be16
        {
            return (be16)bswap16((u16)host_value);
        };
        
        def hton32(le32 host_value) -> be32
        {
            return (be32)bswap32((u32)host_value);
        };

        // ============ BIT MANIPULATION ============
        ///
        def bit_set(u32* value, u32 bit) -> void
        {
            *value |= (1 << bit);
        };
        
        def bit_clear(u32* value, u32 bit) -> void
        {
            *value &= ~(1 << bit);
        };
        
        def bit_toggle(u32* value, u32 bit) -> void
        {
            *value ^= (1 << bit);
        };
        ///
        
        def bit_test(u32 value, u32 bit) -> bool
        {
            return (value & (1 << bit)) != 0;
        };

        // ============ ALIGNMENT UTILITIES ============
        def align_up(u64 value, u64 alignment) -> u64
        {
            return (value + alignment - 1) & (alignment - 1);
        };
        
        def align_down(u64 value, u64 alignment) -> u64
        {
            return value & (alignment - 1);
        };
        
        def is_aligned(u64 value, u64 alignment) -> bool
        {
            return (value & (alignment - 1)) == 0;
        };
	};
};

using standard::types;

#endif;