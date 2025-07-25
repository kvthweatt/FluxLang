// Flux Standard Library
//
// Do not modify.

// Note:
//
//   Uncomment this comptime block when the full specification is implemented.
//
//compt
//{
//    if (!def(FLUX_STANDARD))
//    {
//        global def FLUX_STANDARD;
//        global import "types.fx", "collections.fx", "system.fx", "io.fx";
//    };
//};

namespace standard
{
    namespace io {
        // Basic I/O functions (placeholders for now)
        def print(string message) -> void;
        def println(string message) -> void;
        def input(string prompt) -> string;
    }
    
    namespace types {
        // Type aliases for convenience  
        using uint8_t = uint8;
        using uint16_t = uint16;
        using uint32_t = uint32;
        using uint64_t = uint64;
        using int8_t = int8;
        using int16_t = int16;
        using int32_t = int32;
        using int64_t = int64;
        
        using size_t = uint64;
    }
    
    namespace math {
        // Basic math functions (placeholders)
        def abs(int x) -> int;
        def min(int a, int b) -> int;
        def max(int a, int b) -> int;
    }
};