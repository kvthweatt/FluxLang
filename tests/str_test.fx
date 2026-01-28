#import "standard.fx";

#import "strfuncs.fx";

def main() -> int
{
    // Test with explicit large 64-bit constants
    byte[32] buffer;
    
    print("Testing u64str:\n\0");
    
    // 4,294,967,295 = 2^32 - 1 (max 32-bit unsigned)
    u64 val1 = (u64)4294967295;
    u64 len1 = u64str(val1, buffer);
    print("2^32 - 1 = \0"); print(buffer); print(" (expected: 4294967295)\n\0");
    
    // 5,000,000,000 = should work with proper 64-bit
    u64 val2 = (u64)5000000000;
    u64 len2 = u64str(val2, buffer);
    print("5e9 = \0"); print(buffer); print(" (expected: 5000000000)\n\0");
    
    // 10,000,000,000 = even larger
    u64 val3 = (u64)10000000000;
    u64 len3 = u64str(val3, buffer);
    print("10e9 = \0"); print(buffer); print(" (expected: 10000000000)\n\0");
    
    // Direct hex test
    u64 hex_val = (u64)0xFFFFFFFFFFFFFFFF;
    u64 hex_len = u64str(hex_val, buffer);
    print("max u64 = \0"); print(buffer); print(" (expected: 18446744073709551615)\n\0");
    
    // Test operations
    u64 a = (u64)3000000000;
    u64 b = (u64)2000000000;
    u64 sum = a + b;
    u64 sum_len = u64str(sum, buffer);
    print("3000000000 + 2000000000 = \0"); print(buffer); print(" (expected: 5000000000)\n\0");
    
    // Check if we're getting correct values
    print("\nDirect value checks:\n\0");
    if (val2 == (u64)5000000000) {
        print("val2 == 5000000000 is TRUE\n\0");
    } else {
        print("val2 == 5000000000 is FALSE\n\0");
    };
    
    return 0;
};