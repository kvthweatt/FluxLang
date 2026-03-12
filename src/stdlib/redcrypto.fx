// redcrypto.fx - Cryptography Library

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_CRYPTO
#def FLUX_STANDARD_CRYPTO;

namespace standard
{
    namespace crypto
    {
        namespace hashing
        {
            namespace SHA256
            {
                struct SHA256_CTX
                {
                    u32[8] state;           // Hash state
                    byte[64] buffer;        // Message block buffer
                    u64 bitlen;             // Message length in bits
                    u32 buflen;             // Current buffer length
                };

                // SHA-256 constants (first 32 bits of the fractional parts of the cube roots of the first 64 primes)
                const u32[64] K = [
                    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
                    0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
                    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
                    0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
                    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
                    0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
                    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
                    0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
                    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
                    0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
                    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
                    0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
                    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
                    0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
                    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
                    0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
                ];
                
                // Right rotate
def rotr(u32 value, u32 n) -> u32
{
    return (value >> n) `| (value << (32 - n));
};
                
                // SHA-256 functions
def ch(u32 x, u32 y, u32 z) -> u32
{
    return (x `& y) `^^ (`!x `& z);
};

def maj(u32 x, u32 y, u32 z) -> u32
{
    return (x `& y) `^^ (x `& z) `^^ (y `& z);
};

def sigma0(u32 x) -> u32
{
    return rotr(x, 2) `^^ rotr(x, 13) `^^ rotr(x, 22);
};

def sigma1(u32 x) -> u32
{
    return rotr(x, 6) `^^ rotr(x, 11) `^^ rotr(x, 25);
};

def gamma0(u32 x) -> u32
{
    return rotr(x, 7) `^^ rotr(x, 18) `^^ (x >> 3);
};

def gamma1(u32 x) -> u32
{
    return rotr(x, 17) `^^ rotr(x, 19) `^^ (x >> 10);
};
                
                // Initialize SHA-256 context
                def sha256_init(SHA256_CTX* ctx) -> void
                {
                    // Initial hash values (first 32 bits of the fractional parts of the square roots of the first 8 primes)
                    ctx.state[0] = 0x6A09E667u;
                    ctx.state[1] = 0xBB67AE85u;
                    ctx.state[2] = 0x3C6EF372u;
                    ctx.state[3] = 0xA54FF53Au;
                    ctx.state[4] = 0x510E527Fu;
                    ctx.state[5] = 0x9B05688Cu;
                    ctx.state[6] = 0x1F83D9ABu;
                    ctx.state[7] = 0x5BE0CD19u;
                    
                    ctx.bitlen = (u64)0;
                    ctx.buflen = 0;
                    
                    print("SHA256 initialized\n\0");
                };
                
                // Process a single 512-bit block
                def sha256_transform(SHA256_CTX* ctx, byte* datax) -> void
                {
                    u32[64] W;
                    u32 a, b, c, d, e, f, g, h, t1, t2;
                    u32 i;
                    
                    // Prepare message schedule
                    for (i = 0; i < 16; i++)
                    {
                        W[i] = (((u32)datax[i * 4] & 0xFF) << 24) |
                               (((u32)datax[i * 4 + 1] & 0xFF) << 16) |
                               (((u32)datax[i * 4 + 2] & 0xFF) << 8) |
                               ((u32)datax[i * 4 + 3] & 0xFF);
                    };
                    
                    for (i = 16; i < 64; i++)
                    {
                        W[i] = gamma1(W[i - 2]) + W[i - 7] + gamma0(W[i - 15]) + W[i - 16];
                    };
                    
                    // Initialize working variables
                    a = ctx.state[0];
                    b = ctx.state[1];
                    c = ctx.state[2];
                    d = ctx.state[3];
                    e = ctx.state[4];
                    f = ctx.state[5];
                    g = ctx.state[6];
                    h = ctx.state[7];
                    
                    // Main loop
                    for (i = 0; i < 64; i++)
                    {
                        t1 = h + sigma1(e) + ch(e, f, g) + K[i] + W[i];
                        t2 = sigma0(a) + maj(a, b, c);
                        h = g;
                        g = f;
                        f = e;
                        e = d + t1;
                        d = c;
                        c = b;
                        b = a;
                        a = t1 + t2;
                    };
                    
                    // Update hash state
                    ctx.state[0] += a;
                    ctx.state[1] += b;
                    ctx.state[2] += c;
                    ctx.state[3] += d;
                    ctx.state[4] += e;
                    ctx.state[5] += f;
                    ctx.state[6] += g;
                    ctx.state[7] += h;
                    
                    ///
                    print("After transform, state[0] = \0");
                    print((int)ctx.state[0]);
                    print("\n\0");
                    ///
                };
                
                // Update SHA-256 with data
                def sha256_update(SHA256_CTX* ctx, byte* datax, u64 len) -> void
                {
                    u64 i;
                    
                    for (i = 0; i < len; i++)
                    {
                        ctx.buffer[ctx.buflen] = datax[i];
                        ctx.buflen = ctx.buflen + 1;
                        
                        if (ctx.buflen == 64)
                        {
                            //print("Transforming block\n\0");
                            sha256_transform(ctx, ctx.buffer);
                            ctx.bitlen += 512;
                            ctx.buflen = 0;
                        };
                    };
                };

                def sha256_final(SHA256_CTX* ctx, byte* hash) -> void
                {
                    u32 i = ctx.buflen;

                    // Pad with 0x80
                    ctx.buffer[i] = (byte)0x80;
                    i++;
                    
                    // Pad with zeros, leaving room for length
                    if (ctx.buflen < 56)
                    {
                        while (i < 56)
                        {
                            ctx.buffer[i] = '\0';
                            i++;
                        };
                    }
                    else
                    {
                        while (i < 64)
                        {
                            ctx.buffer[i] = '\0';
                            i++;
                        };
                        sha256_transform(ctx, ctx.buffer);
                        for (i = 0; i < 56; i++)
                        {
                            ctx.buffer[i] = '\0';
                        };
                    };
                    
                    // Append length in bits as 64-bit big-endian
                    ctx.bitlen += ctx.buflen * 8;

                    ctx.buffer[63] = (byte)(ctx.bitlen);
                    ctx.buffer[62] = (byte)(ctx.bitlen >> 8);
                    ctx.buffer[61] = (byte)(ctx.bitlen >> 16);
                    ctx.buffer[60] = (byte)(ctx.bitlen >> 24);
                    ctx.buffer[59] = (byte)(ctx.bitlen >> 32);
                    ctx.buffer[58] = (byte)(ctx.bitlen >> 40);
                    ctx.buffer[57] = (byte)(ctx.bitlen >> 48);
                    ctx.buffer[56] = (byte)(ctx.bitlen >> 56);
                    
                    sha256_transform(ctx, ctx.buffer);
                    
                    // Convert state to byte array (big-endian)
                    for (i = 0; i < 4; i++)
                    {
                        hash[i] = (byte)((ctx.state[0] >> (24 - i * 8)) & 0xFF);
                        hash[i + 4] = (byte)((ctx.state[1] >> (24 - i * 8)) & 0xFF);
                        hash[i + 8] = (byte)((ctx.state[2] >> (24 - i * 8)) & 0xFF);
                        hash[i + 12] = (byte)((ctx.state[3] >> (24 - i * 8)) & 0xFF);
                        hash[i + 16] = (byte)((ctx.state[4] >> (24 - i * 8)) & 0xFF);
                        hash[i + 20] = (byte)((ctx.state[5] >> (24 - i * 8)) & 0xFF);
                        hash[i + 24] = (byte)((ctx.state[6] >> (24 - i * 8)) & 0xFF);
                        hash[i + 28] = (byte)((ctx.state[7] >> (24 - i * 8)) & 0xFF);
                    };
                };
            }; // SHA256

            namespace MD5
            {
                struct MD5_CTX
                {
                    u32[4] state;       // Hash state (A, B, C, D)
                    u64 count;          // Number of bits processed
                    byte[64] buffer;    // Input buffer
                };

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

        namespace encryption
        {
            namespace AES
            {
                // AES context structure
                struct AES_CTX
                {
                    u32[44] round_keys;     // Expanded key schedule (11 rounds * 4 words)
                    u32 nr;                 // Number of rounds (10 for AES-128)
                };
                
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
    };
};

#endif;