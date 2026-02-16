// MD5 Implementation in Flux
// Based on RFC 1321 specification
#import "standard.fx", "redcrypto.fx";

using standard::crypto::hashing::MD5;

def main() -> int
{
    print("==== MD5 TEST ====\n\0");
    
    MD5_CTX ctx;
    byte[16] digest;
    
    // Test 1: Empty string
    md5_init(@ctx);
    byte* msg1 = "\0";
    md5_update(@ctx, msg1, 0);
    md5_final(@ctx, digest);
    
    print("MD5(\"\") = \0");
    u32 i;
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(digest[i]);
    };
    print("\n\0");
    print("Expected:  d41d8cd98f00b204e9800998ecf8427e\n\0");
    
    // Test 2: "a"
    md5_init(@ctx);
    byte* msg2 = "a\0";
    md5_update(@ctx, msg2, 1);
    md5_final(@ctx, digest);
    
    print("\nMD5(\"a\") = \0");
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(digest[i]);
    };
    print("\n\0");
    print("Expected:   0cc175b9c0f1b6a831c399e269772661\n\0");
    
    // Test 3: "abc"
    md5_init(@ctx);
    byte* msg3 = "abc\0";
    md5_update(@ctx, msg3, 3);
    md5_final(@ctx, digest);
    
    print("\nMD5(\"abc\") = \0");
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(digest[i]);
    };
    print("\n\0");
    print("Expected:    900150983cd24fb0d6963f7d28e17f72\n\0");
    
    // Test 4: "message digest"
    md5_init(@ctx);
    byte* msg4 = "message digest\0";
    md5_update(@ctx, msg4, 14);
    md5_final(@ctx, digest);
    
    print("\nMD5(\"message digest\") = \0");
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(digest[i]);
    };
    print("\n\0");
    print("Expected:                f96b697d7cb7938d525a2f31aaf161d0\n\0");
    
    // Test 5: alphabet
    md5_init(@ctx);
    byte* msg5 = "abcdefghijklmnopqrstuvwxyz\0";
    md5_update(@ctx, msg5, 26);
    md5_final(@ctx, digest);
    
    print("\nMD5(\"abcdefghijklmnopqrstuvwxyz\") = \0");
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(digest[i]);
    };
    print("\n\0");
    print("Expected:                          c3fcd3d76192e4007dfb496cca67e13b\n\0");
    
    return 0;
};
