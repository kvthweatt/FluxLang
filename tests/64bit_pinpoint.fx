#import "standard.fx";
#import "strfuncs.fx";
#import "tests\\64bit_arith.fx";
#import "tests\\64bit_arith2.fx";
#import "tests\\64bit_su_test.fx";
#import "tests\\64bit_direct_test.fx";
#import "tests\\64bit_direct_test2.fx";

def pinpoint_llvm_bug() -> int
{
    byte[32] buf;
    
    // Test exact operations that should use 64-bit LLVM instructions
    u64 a = (u64)4294967295;  // 0xFFFFFFFF
    
    print("Testing operation bit-widths:\n\0");
    
    // These should use i64 operations in LLVM IR:
    u64 div_result = a / (u64)256;      // Should be: udiv i64
    u64 mod_result = a % (u64)257;      // Should be: urem i64  
    u64 and_result = a & (u64)0xFFFF;   // Should be: and i64
    u64 or_result = a | (u64)0x100000000; // Should be: or i64
    u64 add_result = a + (u64)1;        // Should be: add i64
    
    print("0xFFFFFFFF / 256 = \0"); u64str(div_result, buf); print(buf); print(" (expected: 16777215)\n\0");
    print("0xFFFFFFFF % 257 = \0"); u64str(mod_result, buf); print(buf); print(" (expected: 254)\n\0");
    print("0xFFFFFFFF & 0xFFFF = \0"); u64str(and_result, buf); print(buf); print(" (expected: 65535)\n\0");
    print("0xFFFFFFFF | 0x100000000 = \0"); u64str(or_result, buf); print(buf); print(" (expected: 8589934591)\n\0");
    print("0xFFFFFFFF + 1 = \0"); u64str(add_result, buf); print(buf); print(" (expected: 4294967296)\n\0");
    
    // Test if it's value-dependent
    u64 small = (u64)255;
    u64 small_div = small / (u64)2;
    print("\nSmall value test (255/2): \0"); u64str(small_div, buf); print(buf); print(" (expected: 127)\n\0");
    
    return 0;
};

def test_all_ops() -> int
{
    byte[32] buf;
    u64 large = (u64)0xFFFFFFFF;
    
    print("Testing ALL operations on 0xFFFFFFFF:\n\0");
    
    // Multiplication (should overflow in 32-bit)
    u64 mul = large * (u64)2;
    print("0xFFFFFFFF * 2 = \0"); u64str(mul, buf); print(buf); print(" (expected: 8589934590)\n\0");
    
    // Subtraction
    u64 sub = large - (u64)1;
    print("0xFFFFFFFF - 1 = \0"); u64str(sub, buf); print(buf); print(" (expected: 4294967294)\n\0");
    
    // Bitwise XOR
    u64 xx = large xor (u64)0xFFFF0000;
    print("0xFFFFFFFF ^ 0xFFFF0000 = \0"); u64str(xx, buf); print(buf); print(" (expected: 65535)\n\0");
    
    // Right shift (logical vs arithmetic matters for signed!)
    u64 shr = large >> (u64)8;
    print("0xFFFFFFFF >> 8 = \0"); u64str(shr, buf); print(buf); print(" (expected: 16777215)\n\0");
    
    return 0;
};

def isolate_the_bug() -> int
{
    byte[32] buf;
    
    // Test 1: Explicit 64-bit constant division
    // (Should work if literals are correct)
    u64 result1 = (u64)0xFFFFFFFF / (u64)256;
    print("Literal 0xFFFFFFFF / 256 = \0"); 
    u64str(result1, buf); print(buf); print("\n\0");
    
    // Test 2: Variable division (might be different code path)
    u64 var = (u64)0xFFFFFFFF;
    u64 result2 = var / (u64)256;
    print("Variable 0xFFFFFFFF / 256 = \0");
    u64str(result2, buf); print(buf); print("\n\0");
    
    // Test 3: Force 64-bit with cast
    u64 result3 = (u64)((u64)0xFFFFFFFF / (u64)256);
    print("Double-cast 0xFFFFFFFF / 256 = \0");
    u64str(result3, buf); print(buf); print("\n\0");
    
    return 0;
};

def main() -> int
{
    test_64bit_arithmetic();
    check_literal_types();
    test_direct();
    test_individual_operations();
    signed_vs_unsigned();
    pinpoint_llvm_bug();
    test_all_ops();
    isolate_the_bug();
    return 0;
};