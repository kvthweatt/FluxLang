// Big Integer Library for Flux - Foundation
// Phase 1: Structure, initialization, and printing
#import "standard.fx";

// BigInt structure - stores large integers as arrays of u32 digits
// Each u32 holds one "digit" in base 2^32
// digits[0] is least significant, digits[length-1] is most significant
struct BigInt
{
    u32[128] digits;    // Can hold up to 4096 bits (128 * 32)
    u32 length;         // Number of u32 digits actually used
    bool negative;      // Sign: false = positive, true = negative
};

namespace math
{
    namespace bigint
    {
        // Initialize a BigInt to zero
        def bigint_zero(BigInt* num) -> void
        {
            u32 i;
            for (i = 0; i < 128; i++)
            {
                num.digits[i] = 0;
            };
            num.length = 1;
            num.negative = false;
            return;
        };
        
        // Initialize a BigInt to one
        def bigint_one(BigInt* num) -> void
        {
            u32 i;
            num.digits[0] = 1;
            for (i = 1; i < 128; i++)
            {
                num.digits[i] = 0;
            };
            num.length = 1;
            num.negative = false;
            return;
        };
        
        // Create a BigInt from a u32 value
        def bigint_from_u32(BigInt* num, u32 value) -> void
        {
            u32 i;
            num.digits[0] = value;
            for (i = 1; i < 128; i++)
            {
                num.digits[i] = 0;
            };
            
            if (value == 0)
            {
                num.length = 1;
            }
            else
            {
                num.length = 1;
            };
            
            num.negative = false;
            return;
        };
        
        // Create a BigInt from a u64 value
        def bigint_from_u64(BigInt* num, u64 value) -> void
        {
            u32 i;
            num.digits[0] = (u32)(value & 0xFFFFFFFF);
            num.digits[1] = (u32)(value >> 32);
            
            for (i = 2; i < 128; i++)
            {
                num.digits[i] = 0;
            };
            
            if (num.digits[1] != 0)
            {
                num.length = 2;
            }
            else
            {
                if (num.digits[0] != 0)
                {
                    num.length = 1;
                }
                else
                {
                    num.length = 1;
                };
            };
            
            num.negative = false;
            return;
        };
        
        // Check if BigInt is zero
        def bigint_is_zero(BigInt* num) -> bool
        {
            if (num.length == 1)
            {
                if (num.digits[0] == 0)
                {
                    return true;
                };
            };
            return false;
        };
        
        // Check if BigInt is one
        def bigint_is_one(BigInt* num) -> bool
        {
            if (num.negative)
            {
                return false;
            };
            
            if (num.length == 1)
            {
                if (num.digits[0] == 1)
                {
                    return true;
                };
            };
            
            return false;
        };
        
        // Print a single hex digit
        def print_hex_digit(u32 digit) -> void
        {
            if (digit < 10)
            {
                print((byte)('0' + digit));
            }
            else
            {
                print((byte)('a' + (digit - 10)));
            };
            return;
        };
        
        // Print BigInt in hexadecimal format (for debugging)
        def bigint_print_hex(BigInt* num) -> void
        {
            if (num.negative)
            {
                print("-\0");
            };
            
            print("0x\0");
            
            // Print from most significant to least significant
            u32 i = num.length;
            while (i > 0)
            {
                i--;
                
                u32 digit = num.digits[i];
                
                // Print all 8 hex digits for this u32
                u32 j;
                for (j = 0; j < 8; j++)
                {
                    u32 nibble = (digit >> (28 - j * 4)) & 0xF;
                    print_hex_digit(nibble);
                };
                
                // Add separator between digits for readability
                if (i > 0)
                {
                    print("_\0");
                };
            };
            
            return;
        };
        
        // Print BigInt in decimal format (simple version - converts to decimal string)
        // Note: This is a simplified version that only works for small numbers
        // We'll implement full decimal conversion later with division
        def bigint_print_decimal_simple(BigInt* num) -> void
        {
            if (num.negative)
            {
                print("-\0");
            };
            
            // For now, only handle numbers that fit in u64
            if (num.length > 2)
            {
                print("[Large number - use hex print]\0");
                return;
            };
            
            u64 value;
            if (num.length == 2)
            {
                value = ((u64)num.digits[1] << 32) | (u64)num.digits[0];
            }
            else
            {
                value = (u64)num.digits[0];
            };
            
            // Print as u64
            print((int)value);
            
            return;
        };
        
        // Copy one BigInt to another
        def bigint_copy(BigInt* dest, BigInt* src) -> void
        {
            u32 i;
            for (i = 0; i < 128; i++)
            {
                dest.digits[i] = src.digits[i];
            };
            dest.length = src.length;
            dest.negative = src.negative;
            return;
        };
    };
};

using math::bigint;

def main() -> int
{
    print("==== BIG INTEGER FOUNDATION TEST ====\n\n\0");
    
    BigInt num;
    
    // Test 1: Zero
    print("Test 1: Zero\n\0");
    bigint_zero(@num);
    print("Decimal: \0");
    bigint_print_decimal_simple(@num);
    print("\nHex: \0");
    bigint_print_hex(@num);
    print("\n\n\0");
    
    // Test 2: One
    print("Test 2: One\n\0");
    bigint_one(@num);
    print("Decimal: \0");
    bigint_print_decimal_simple(@num);
    print("\nHex: \0");
    bigint_print_hex(@num);
    print("\n\n\0");
    
    // Test 3: Small u32 value
    print("Test 3: From u32 (42)\n\0");
    bigint_from_u32(@num, 42);
    print("Decimal: \0");
    bigint_print_decimal_simple(@num);
    print("\nHex: \0");
    bigint_print_hex(@num);
    print("\n\n\0");
    
    // Test 4: Larger u32 value
    print("Test 4: From u32 (0xDEADBEEF)\n\0");
    bigint_from_u32(@num, 0xDEADBEEF);
    print("Decimal: \0");
    bigint_print_decimal_simple(@num);
    print("\nHex: \0");
    bigint_print_hex(@num);
    print("\n\n\0");
    
    // Test 5: u64 value that spans two u32 digits
    print("Test 5: From u64 (0x123456789ABCDEF0)\n\0");
    bigint_from_u64(@num, 0x123456789ABCDEF0);
    print("Decimal: \0");
    bigint_print_decimal_simple(@num);
    print("\nHex: \0");
    bigint_print_hex(@num);
    print("\n\n\0");
    
    // Test 6: Maximum u64 value
    print("Test 6: From u64 (0xFFFFFFFFFFFFFFFF)\n\0");
    bigint_from_u64(@num, 0xFFFFFFFFFFFFFFFF);
    print("Decimal: \0");
    bigint_print_decimal_simple(@num);
    print("\nHex: \0");
    bigint_print_hex(@num);
    print("\n\n\0");
    
    // Test 7: Check is_zero
    print("Test 7: is_zero checks\n\0");
    bigint_zero(@num);
    print("Zero is_zero: \0");
    if (bigint_is_zero(@num))
    {
        print("true\n\0");
    }
    else
    {
        print("false\n\0");
    };
    
    bigint_one(@num);
    print("One is_zero: \0");
    if (bigint_is_zero(@num))
    {
        print("true\n\0");
    }
    else
    {
        print("false\n\0");
    };
    print("\n\0");
    
    // Test 8: Check is_one
    print("Test 8: is_one checks\n\0");
    bigint_one(@num);
    print("One is_one: \0");
    if (bigint_is_one(@num))
    {
        print("true\n\0");
    }
    else
    {
        print("false\n\0");
    };
    
    bigint_zero(@num);
    print("Zero is_one: \0");
    if (bigint_is_one(@num))
    {
        print("true\n\0");
    }
    else
    {
        print("false\n\0");
    };
    print("\n\0");
    
    print("==== ALL FOUNDATION TESTS COMPLETE ====\n\0");
    
    return 0;
};
