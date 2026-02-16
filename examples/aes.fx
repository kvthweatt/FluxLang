// AES-128 Implementation in Flux
// Based on FIPS 197 specification
#import "standard.fx";

// AES context structure
struct AES_CTX
{
    u32[44] round_keys;     // Expanded key schedule (11 rounds * 4 words)
    u32 nr;                 // Number of rounds (10 for AES-128)
};

namespace crypto
{
    namespace aes
    {
        // AES S-Box (Substitution box)
        const byte[256] SBOX = [
            0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
            0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
            0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
            0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
            0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
            0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
            0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
            0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
            0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
            0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
            0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
            0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
            0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
            0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
            0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
            0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16
        ];
        
        // Inverse S-Box (for decryption)
        const byte[256] INV_SBOX = [
            0x52, 0x09, 0x6A, 0xD5, 0x30, 0x36, 0xA5, 0x38, 0xBF, 0x40, 0xA3, 0x9E, 0x81, 0xF3, 0xD7, 0xFB,
            0x7C, 0xE3, 0x39, 0x82, 0x9B, 0x2F, 0xFF, 0x87, 0x34, 0x8E, 0x43, 0x44, 0xC4, 0xDE, 0xE9, 0xCB,
            0x54, 0x7B, 0x94, 0x32, 0xA6, 0xC2, 0x23, 0x3D, 0xEE, 0x4C, 0x95, 0x0B, 0x42, 0xFA, 0xC3, 0x4E,
            0x08, 0x2E, 0xA1, 0x66, 0x28, 0xD9, 0x24, 0xB2, 0x76, 0x5B, 0xA2, 0x49, 0x6D, 0x8B, 0xD1, 0x25,
            0x72, 0xF8, 0xF6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xD4, 0xA4, 0x5C, 0xCC, 0x5D, 0x65, 0xB6, 0x92,
            0x6C, 0x70, 0x48, 0x50, 0xFD, 0xED, 0xB9, 0xDA, 0x5E, 0x15, 0x46, 0x57, 0xA7, 0x8D, 0x9D, 0x84,
            0x90, 0xD8, 0xAB, 0x00, 0x8C, 0xBC, 0xD3, 0x0A, 0xF7, 0xE4, 0x58, 0x05, 0xB8, 0xB3, 0x45, 0x06,
            0xD0, 0x2C, 0x1E, 0x8F, 0xCA, 0x3F, 0x0F, 0x02, 0xC1, 0xAF, 0xBD, 0x03, 0x01, 0x13, 0x8A, 0x6B,
            0x3A, 0x91, 0x11, 0x41, 0x4F, 0x67, 0xDC, 0xEA, 0x97, 0xF2, 0xCF, 0xCE, 0xF0, 0xB4, 0xE6, 0x73,
            0x96, 0xAC, 0x74, 0x22, 0xE7, 0xAD, 0x35, 0x85, 0xE2, 0xF9, 0x37, 0xE8, 0x1C, 0x75, 0xDF, 0x6E,
            0x47, 0xF1, 0x1A, 0x71, 0x1D, 0x29, 0xC5, 0x89, 0x6F, 0xB7, 0x62, 0x0E, 0xAA, 0x18, 0xBE, 0x1B,
            0xFC, 0x56, 0x3E, 0x4B, 0xC6, 0xD2, 0x79, 0x20, 0x9A, 0xDB, 0xC0, 0xFE, 0x78, 0xCD, 0x5A, 0xF4,
            0x1F, 0xDD, 0xA8, 0x33, 0x88, 0x07, 0xC7, 0x31, 0xB1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xEC, 0x5F,
            0x60, 0x51, 0x7F, 0xA9, 0x19, 0xB5, 0x4A, 0x0D, 0x2D, 0xE5, 0x7A, 0x9F, 0x93, 0xC9, 0x9C, 0xEF,
            0xA0, 0xE0, 0x3B, 0x4D, 0xAE, 0x2A, 0xF5, 0xB0, 0xC8, 0xEB, 0xBB, 0x3C, 0x83, 0x53, 0x99, 0x61,
            0x17, 0x2B, 0x04, 0x7E, 0xBA, 0x77, 0xD6, 0x26, 0xE1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0C, 0x7D
        ];
        
        // Round constants for key expansion
        const u32[10] RCON = [
            0x01000000, 0x02000000, 0x04000000, 0x08000000,
            0x10000000, 0x20000000, 0x40000000, 0x80000000,
            0x1B000000, 0x36000000
        ];
        
        // Galois Field multiplication by 2
        def gmul2(byte b) -> byte
        {
            if ((b & 0x80) != 0)
            {
                return (byte)((b << 1) ^^ 0x1B);
            }
            else
            {
                return (byte)(b << 1);
            };
            return '\0';
        };
        
        // Galois Field multiplication by 3
        def gmul3(byte b) -> byte
        {
            return gmul2(b) ^^ b;
        };
        
        // SubBytes transformation
        def sub_bytes(byte* state) -> void
        {
            u32 i;
            for (i = 0; i < 16; i++)
            {
                state[i] = (byte)(SBOX[(state[i] & 0xFF)] & 0xFF);
            };
            return;
        };
        
        // Inverse SubBytes transformation
        def inv_sub_bytes(byte* state) -> void
        {
            u32 i;
            for (i = 0; i < 16; i++)
            {
                state[i] = (byte)(INV_SBOX[(state[i] & 0xFF)] & 0xFF);
            };
            return;
        };
        
        // ShiftRows transformation
        def shift_rows(byte* state) -> void
        {
            byte temp;
            
            // Row 1: shift left by 1
            temp = state[1];
            state[1] = state[5];
            state[5] = state[9];
            state[9] = state[13];
            state[13] = temp;
            
            // Row 2: shift left by 2
            temp = state[2];
            state[2] = state[10];
            state[10] = temp;
            temp = state[6];
            state[6] = state[14];
            state[14] = temp;
            
            // Row 3: shift left by 3
            temp = state[15];
            state[15] = state[11];
            state[11] = state[7];
            state[7] = state[3];
            state[3] = temp;
            return;
        };
        
        // Inverse ShiftRows transformation
        def inv_shift_rows(byte* state) -> void
        {
            byte temp;
            
            // Row 1: shift right by 1
            temp = state[13];
            state[13] = state[9];
            state[9] = state[5];
            state[5] = state[1];
            state[1] = temp;
            
            // Row 2: shift right by 2
            temp = state[2];
            state[2] = state[10];
            state[10] = temp;
            temp = state[6];
            state[6] = state[14];
            state[14] = temp;
            
            // Row 3: shift right by 3
            temp = state[3];
            state[3] = state[7];
            state[7] = state[11];
            state[11] = state[15];
            state[15] = temp;
            return;
        };
        
        // MixColumns transformation
        def mix_columns(byte* state) -> void
        {
            byte[4] temp;
            u32 col;
            
            // Mix each column
            for (col = 0; col < 4; col++)
            {
                u32 base = col * 4;
                temp[0] = state[base + 0];
                temp[1] = state[base + 1];
                temp[2] = state[base + 2];
                temp[3] = state[base + 3];
                
                state[base + 0] = gmul2(temp[0]) ^^ gmul3(temp[1]) ^^ temp[2] ^^ temp[3];
                state[base + 1] = temp[0] ^^ gmul2(temp[1]) ^^ gmul3(temp[2]) ^^ temp[3];
                state[base + 2] = temp[0] ^^ temp[1] ^^ gmul2(temp[2]) ^^ gmul3(temp[3]);
                state[base + 3] = gmul3(temp[0]) ^^ temp[1] ^^ temp[2] ^^ gmul2(temp[3]);
            };
            return;
        };
        
        // Inverse MixColumns transformation
        def inv_mix_columns(byte* state) -> void
        {
            byte[4] temp;
            u32 col;
            
            // Mix each column
            for (col = 0; col < 4; col++)
            {
                u32 base = col * 4;
                temp[0] = state[base + 0];
                temp[1] = state[base + 1];
                temp[2] = state[base + 2];
                temp[3] = state[base + 3];
                
                // Multiply by inverse matrix in GF(2^8)
                // 0x0E, 0x0B, 0x0D, 0x09
                state[base + 0] = (byte)(
                    gmul2(gmul2(gmul2(temp[0]))) ^^ gmul2(gmul2(temp[0])) ^^ gmul2(temp[0]) ^^  // 0x0E
                    gmul2(gmul2(gmul2(temp[1]))) ^^ gmul2(temp[1]) ^^ temp[1] ^^                // 0x0B
                    gmul2(gmul2(gmul2(temp[2]))) ^^ gmul2(gmul2(temp[2])) ^^ temp[2] ^^         // 0x0D
                    gmul2(gmul2(gmul2(temp[3]))) ^^ temp[3]                                      // 0x09
                );
                
                state[base + 1] = (byte)(
                    gmul2(gmul2(gmul2(temp[0]))) ^^ temp[0] ^^
                    gmul2(gmul2(gmul2(temp[1]))) ^^ gmul2(gmul2(temp[1])) ^^ gmul2(temp[1]) ^^
                    gmul2(gmul2(gmul2(temp[2]))) ^^ gmul2(temp[2]) ^^ temp[2] ^^
                    gmul2(gmul2(gmul2(temp[3]))) ^^ gmul2(gmul2(temp[3])) ^^ temp[3]
                );
                
                state[base + 2] = (byte)(
                    gmul2(gmul2(gmul2(temp[0]))) ^^ gmul2(gmul2(temp[0])) ^^ temp[0] ^^
                    gmul2(gmul2(gmul2(temp[1]))) ^^ temp[1] ^^
                    gmul2(gmul2(gmul2(temp[2]))) ^^ gmul2(gmul2(temp[2])) ^^ gmul2(temp[2]) ^^
                    gmul2(gmul2(gmul2(temp[3]))) ^^ gmul2(temp[3]) ^^ temp[3]
                );
                
                state[base + 3] = (byte)(
                    gmul2(gmul2(gmul2(temp[0]))) ^^ gmul2(temp[0]) ^^ temp[0] ^^
                    gmul2(gmul2(gmul2(temp[1]))) ^^ gmul2(gmul2(temp[1])) ^^ temp[1] ^^
                    gmul2(gmul2(gmul2(temp[2]))) ^^ temp[2] ^^
                    gmul2(gmul2(gmul2(temp[3]))) ^^ gmul2(gmul2(temp[3])) ^^ gmul2(temp[3])
                );
            };
            return;
        };
        
        // AddRoundKey transformation
        def add_round_key(byte* state, u32* round_key) -> void
        {
            u32 col;
            // Each round_key word corresponds to a column
            for (col = 0; col < 4; col++)
            {
                u32 base = col * 4;
                state[base + 0] = state[base + 0] ^^ (byte)((round_key[col] >> 24) & 0xFF);
                state[base + 1] = state[base + 1] ^^ (byte)((round_key[col] >> 16) & 0xFF);
                state[base + 2] = state[base + 2] ^^ (byte)((round_key[col] >> 8) & 0xFF);
                state[base + 3] = state[base + 3] ^^ (byte)(round_key[col] & 0xFF);
            };
            return;
        };
        
        // SubWord - apply S-box to each byte of a word
        def sub_word(u32 word) -> u32
        {
            return (((u32)(SBOX[((word >> 24) & 0xFF)] & 0xFF)) << 24) |
                   (((u32)(SBOX[((word >> 16) & 0xFF)] & 0xFF)) << 16) |
                   (((u32)(SBOX[((word >> 8) & 0xFF)] & 0xFF)) << 8) |
                   ((u32)(SBOX[(word & 0xFF)] & 0xFF));
        };
        
        // RotWord - rotate word left by 8 bits
        def rot_word(u32 word) -> u32
        {
            return ((word << 8) | (word >> 24));
        };
        
        // Key expansion for AES-128
        def aes_key_expansion(AES_CTX* ctx, byte* key) -> void
        {
            u32 i;
            u32 temp;
            
            // First 4 words are the key itself
            for (i = 0; i < 4; i++)
            {
                ctx.round_keys[i] = (((u32)key[i * 4] & 0xFF) << 24) |
                                    (((u32)key[i * 4 + 1] & 0xFF) << 16) |
                                    (((u32)key[i * 4 + 2] & 0xFF) << 8) |
                                    ((u32)key[i * 4 + 3] & 0xFF);
            };
            
            // Generate remaining round keys
            for (i = 4; i < 44; i++)
            {
                temp = ctx.round_keys[i - 1];
                
                if ((i % 4) == 0)
                {
                    temp = sub_word(rot_word(temp)) ^^ RCON[i / 4 - 1];
                };
                
                ctx.round_keys[i] = ctx.round_keys[i - 4] ^^ temp;
            };
            
            ctx.nr = 10;
            return;
        };
        
        // AES-128 encryption
        def aes_encrypt_block(AES_CTX* ctx, byte* plaintext, byte* ciphertext) -> void
        {
            byte[16] state;
            u32 i;
            u32 round;
            
            // Copy plaintext to state
            for (i = 0; i < 16; i++)
            {
                state[i] = plaintext[i];
            };
            
            // Initial round key addition
            add_round_key(state, @ctx.round_keys[0]);
            
            // Main rounds
            for (round = 1; round < ctx.nr; round++)
            {
                sub_bytes(state);
                shift_rows(state);
                mix_columns(state);
                add_round_key(state, @ctx.round_keys[round * 4]);
            };
            
            // Final round (no MixColumns)
            sub_bytes(state);
            shift_rows(state);
            add_round_key(state, @ctx.round_keys[ctx.nr * 4]);
            
            // Copy state to ciphertext
            for (i = 0; i < 16; i++)
            {
                ciphertext[i] = state[i];
            };
            return;
        };
        
        // AES-128 decryption
        def aes_decrypt_block(AES_CTX* ctx, byte* ciphertext, byte* plaintext) -> void
        {
            byte[16] state;
            u32 i;
            u32 round;
            
            // Copy ciphertext to state
            for (i = 0; i < 16; i++)
            {
                state[i] = ciphertext[i];
            };
            
            // Initial round key addition
            add_round_key(state, @ctx.round_keys[ctx.nr * 4]);
            
            // Main rounds in reverse
            for (round = ctx.nr - 1; round > 0; round--)
            {
                inv_shift_rows(state);
                inv_sub_bytes(state);
                add_round_key(state, @ctx.round_keys[round * 4]);
                inv_mix_columns(state);
            };
            
            // Final round (no InvMixColumns)
            inv_shift_rows(state);
            inv_sub_bytes(state);
            add_round_key(state, @ctx.round_keys[0]);
            
            // Copy state to plaintext
            for (i = 0; i < 16; i++)
            {
                plaintext[i] = state[i];
            };
            return;
        };
    };
};

using crypto::aes;

def print_hex_byte(byte b) -> void
{
    byte high = (b >> 4) & 0x0F;
    if (high < 10)
    {
        print((byte)('0' + high));
    }
    else
    {
        print((byte)('a' + (high - 10)));
    };
    
    byte low = b & 0x0F;
    if (low < 10)
    {
        print((byte)('0' + low));
    }
    else
    {
        print((byte)('a' + (low - 10)));
    };
    return;
};

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
