// MD5 Implementation in Flux
// Based on RFC 1321 specification
#import "standard.fx";

// MD5 context structure
struct MD5_CTX
{
    u32[4] state;       // Hash state (A, B, C, D)
    u64 count;          // Number of bits processed
    byte[64] buffer;    // Input buffer
};

namespace crypto
{
    namespace md5
    {
        // MD5 constants - sine-based values
        const u32[64] K = [
            0xD76AA478, 0xE8C7B756, 0x242070DB, 0xC1BDCEEE,
            0xF57C0FAF, 0x4787C62A, 0xA8304613, 0xFD469501,
            0x698098D8, 0x8B44F7AF, 0xFFFF5BB1, 0x895CD7BE,
            0x6B901122, 0xFD987193, 0xA679438E, 0x49B40821,
            0xF61E2562, 0xC040B340, 0x265E5A51, 0xE9B6C7AA,
            0xD62F105D, 0x02441453, 0xD8A1E681, 0xE7D3FBC8,
            0x21E1CDE6, 0xC33707D6, 0xF4D50D87, 0x455A14ED,
            0xA9E3E905, 0xFCEFA3F8, 0x676F02D9, 0x8D2A4C8A,
            0xFFFA3942, 0x8771F681, 0x6D9D6122, 0xFDE5380C,
            0xA4BEEA44, 0x4BDECFA9, 0xF6BB4B60, 0xBEBFBC70,
            0x289B7EC6, 0xEAA127FA, 0xD4EF3085, 0x04881D05,
            0xD9D4D039, 0xE6DB99E5, 0x1FA27CF8, 0xC4AC5665,
            0xF4292244, 0x432AFF97, 0xAB9423A7, 0xFC93A039,
            0x655B59C3, 0x8F0CCC92, 0xFFEFF47D, 0x85845DD1,
            0x6FA87E4F, 0xFE2CE6E0, 0xA3014314, 0x4E0811A1,
            0xF7537E82, 0xBD3AF235, 0x2AD7D2BB, 0xEB86D391
        ];
        
        // Shift amounts for each round
        const u32[64] S = [
            7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
            5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
            4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
            6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
        ];
        
        // Left rotate
        def rotl(u32 value, u32 n) -> u32
        {
            return (value << n) | (value >> (32 - n));
        };
        
        // MD5 auxiliary functions
        def F(u32 x, u32 y, u32 z) -> u32
        {
            return (x & y) | ((!x) & z);
        };
        
        def G(u32 x, u32 y, u32 z) -> u32
        {
            return (x & z) | (y & (!z));
        };
        
        def H(u32 x, u32 y, u32 z) -> u32
        {
            return x ^^ y ^^ z;
        };
        
        def I(u32 x, u32 y, u32 z) -> u32
        {
            return y ^^ (x | (!z));
        };
        
        // Initialize MD5 context
        def md5_init(MD5_CTX* ctx) -> void
        {
            ctx.state[0] = (i32)0x67452301;
            ctx.state[1] = (i32)0xEFCDAB89;
            ctx.state[2] = (i32)0x98BADCFE;
            ctx.state[3] = (i32)0x10325476;
            ctx.count = 0;
            return;
        };
        
        // Process a single 512-bit block
        def md5_transform(MD5_CTX* ctx, byte* block) -> void
        {
            u32[16] M;
            u32 i;
            u32 A, B, C, D;
            u32 f_val, g;
            
            // Decode block into 16 32-bit words (little-endian)
            for (i = 0; i < 16; i++)
            {
                M[i] = ((u32)(block[i * 4] & 0xFF)) |
                       (((u32)(block[i * 4 + 1] & 0xFF)) << 8) |
                       (((u32)(block[i * 4 + 2] & 0xFF)) << 16) |
                       (((u32)(block[i * 4 + 3] & 0xFF)) << 24);
            };
            
            // Initialize working variables
            A = ctx.state[0];
            B = ctx.state[1];
            C = ctx.state[2];
            D = ctx.state[3];
            
            // Main loop - 64 operations in 4 rounds
            for (i = 0; i < 64; i++)
            {
                if (i < 16)
                {
                    f_val = F(B, C, D);
                    g = i;
                }
                else
                {
                    if (i < 32)
                    {
                        f_val = G(B, C, D);
                        g = (5 * i + 1) % 16;
                    }
                    else
                    {
                        if (i < 48)
                        {
                            f_val = H(B, C, D);
                            g = (3 * i + 5) % 16;
                        }
                        else
                        {
                            f_val = I(B, C, D);
                            g = (7 * i) % 16;
                        };
                    };
                };
                
                f_val = f_val + A + K[i] + M[g];
                A = D;
                D = C;
                C = B;
                B = B + rotl(f_val, S[i]);
            };
            
            // Add this chunk's hash to result so far
            ctx.state[0] += A;
            ctx.state[1] += B;
            ctx.state[2] += C;
            ctx.state[3] += D;
            return;
        };
        
        // Update MD5 with datax
        def md5_update(MD5_CTX* ctx, byte* datax, u64 len) -> void
        {
            u32 buffer_index;
            u32 buffer_space;
            u64 i;
            
            // Compute number of bytes mod 64
            buffer_index = (u32)((ctx.count >> 3) & 0x3F);
            
            // Update bit count
            ctx.count += len * 8;
            
            buffer_space = 64 - buffer_index;
            
            // Transform as many times as possible
            if (len >= buffer_space)
            {
                // Fill buffer
                for (i = 0; i < buffer_space; i++)
                {
                    ctx.buffer[buffer_index + i] = datax[i];
                };
                
                md5_transform(ctx, ctx.buffer);
                
                // Process full blocks
                i = buffer_space;
                while (i + 63 < len)
                {
                    md5_transform(ctx, datax + i);
                    i += 64;
                };
                
                buffer_index = 0;
            }
            else
            {
                i = 0;
            };
            
            // Buffer remaining input
            while (i < len)
            {
                ctx.buffer[buffer_index] = datax[i];
                buffer_index++;
                i++;
            };
            return;
        };
        
        // Finalize MD5 hash
        def md5_final(MD5_CTX* ctx, byte* digest) -> void
        {
            byte[8] bits;
            u32 index, pad_len;
            u32 i;
            
            // Save number of bits
            for (i = 0; i < 8; i++)
            {
                bits[i] = (byte)((ctx.count >> (i * 8)) & 0xFF);
            };
            
            // Pad to 56 bytes mod 64
            index = (u32)((ctx.count >> 3) & 0x3F);
            pad_len = 0;
            if (index < 56)
            {
                pad_len = 56 - index;
            }
            else
            {
                pad_len = 120 - index;
            };
            
            // Create padding
            byte[64] padding;
            padding[0] = (byte)0x80;
            for (i = 1; i < 64; i++)
            {
                padding[i] = '\0';
            };
            
            md5_update(ctx, padding, pad_len);
            md5_update(ctx, bits, 8);
            
            // Store state in digest (little-endian)
            for (i = 0; i < 4; i++)
            {
                digest[i * 4] = (byte)(ctx.state[i] & 0xFF);
                digest[i * 4 + 1] = (byte)((ctx.state[i] >> 8) & 0xFF);
                digest[i * 4 + 2] = (byte)((ctx.state[i] >> 16) & 0xFF);
                digest[i * 4 + 3] = (byte)((ctx.state[i] >> 24) & 0xFF);
            };
            return;
        };
    };
};

using crypto::md5;

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
