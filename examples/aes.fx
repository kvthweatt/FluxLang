// AES-128 Implementation in Flux
// Based on FIPS 197 specification
#import "standard.fx", "redcrypto.fx";

using standard::io::console;
using standard::strings;
using standard::crypto::encryption::AES;

def main() -> int
{
    print("==== AES-128 TEST ====\n\0");
    
    // Test key (128 bits = 16 bytes)
    byte[16] key = [
        0x2B, 0x7E, 0x15, 0x16,
        0x28, 0xAE, 0xD2, 0xA6,
        0xAB, 0xF7, 0x15, 0x88,
        0x09, 0xCF, 0x4F, 0x3C
    ];
    
    // Test plaintext (128 bits = 16 bytes)
    byte[16] plaintext = [
        0x32, 0x43, 0xF6, 0xA8,
        0x88, 0x5A, 0x30, 0x8D,
        0x31, 0x31, 0x98, 0xA2,
        0xE0, 0x37, 0x07, 0x34
    ];
    
    // Expected ciphertext for FIPS 197 test vector
    // Should be: 3925841d02dc09fbdc118597196a0b32
    
    byte[16] ciphertext;
    byte[16] decrypted;
    AES_CTX ctx;
    
    print("Key:       \0");
    u32 i;
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(key[i]);
    };
    print("\n\0");
    
    print("Plaintext: \0");
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(plaintext[i]);
    };
    print("\n\0");
    
    // Initialize and expand key
    aes_key_expansion(@ctx, key);
    
    // Encrypt
    aes_encrypt_block(@ctx, plaintext, ciphertext);
    
    print("Encrypted: \0");
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(ciphertext[i]);
    };
    print("\n\0");
    
    // Decrypt
    aes_decrypt_block(@ctx, ciphertext, decrypted);
    
    print("Decrypted: \0");
    for (i = 0; i < 16; i++)
    {
        print_hex_byte(decrypted[i]);
    };
    print("\n\0");
    
    // Verify
    bool success = true;
    for (i = 0; i < 16; i++)
    {
        if (decrypted[i] != plaintext[i])
        {
            success = false;
        };
    };
    
    if (success)
    {
        print("\nDecryption successful - plaintext recovered!\n\0");
    }
    else
    {
        print("\nDecryption failed\n\0");
    };
    
    return 0;
};
