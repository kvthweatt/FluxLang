// SHA-256 Implementation in Flux
// Based on FIPS 180-4 specification
#import "standard.fx";

// SHA-256 context structure
struct SHA256_CTX
{
    u32[8] state;           // Hash state
    byte[64] buffer;        // Message block buffer
    u64 bitlen;             // Message length in bits
    u32 buflen;             // Current buffer length
};

namespace crypto
{
    namespace sha256
    {
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
            return (value >> n) | (value << (32 - n));
        };
        
        // SHA-256 functions
        def ch(u32 x, u32 y, u32 z) -> u32
        {
            return (x & y) ^^ (!x & z);
        };
        
        def maj(u32 x, u32 y, u32 z) -> u32
        {
            return (x & y) ^^ (x & z) ^^ (y & z);
        };
        
        def sigma0(u32 x) -> u32
        {
            return rotr(x, 2) ^^ rotr(x, 13) ^^ rotr(x, 22);
        };
        
        def sigma1(u32 x) -> u32
        {
            return rotr(x, 6) ^^ rotr(x, 11) ^^ rotr(x, 25);
        };
        
        def gamma0(u32 x) -> u32
        {
            return rotr(x, 7) ^^ rotr(x, 18) ^^ (x >> 3);
        };
        
        def gamma1(u32 x) -> u32
        {
            return rotr(x, 17) ^^ rotr(x, 19) ^^ (x >> 10);
        };
        
        // Initialize SHA-256 context
        def sha256_init(SHA256_CTX* ctx) -> void
        {
            // Initial hash values (first 32 bits of the fractional parts of the square roots of the first 8 primes)
            *ctx.state[0] = 0x6A09E667;
            *ctx.state[1] = 0xBB67AE85;
            *ctx.state[2] = 0x3C6EF372;
            *ctx.state[3] = 0xA54FF53A;
            *ctx.state[4] = 0x510E527F;
            *ctx.state[5] = 0x9B05688C;
            *ctx.state[6] = 0x1F83D9AB;
            *ctx.state[7] = 0x5BE0CD19;
            
            *ctx.bitlen = 0;
            *ctx.buflen = 0;
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
                W[i] = ((u32)datax[i * 4] << 24) |
                       ((u32)datax[i * 4 + 1] << 16) |
                       ((u32)datax[i * 4 + 2] << 8) |
                       ((u32)datax[i * 4 + 3]);
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
        };
        
        // Update SHA-256 with data
        def sha256_update(SHA256_CTX* ctx, byte* datax, u64 len) -> void
        {
            u64 i;
            
            for (i = 0; i < len; i++)
            {
                ctx.buffer[ctx.buflen] = datax[i];
                ctx.buflen++;
                
                if (ctx.buflen == 64)
                {
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
    };
};

using crypto::sha256;

def main()->int
{
    SHA256_CTX ctx;

    sha256_init(@ctx);

    print("==== SHA256 TEST ====\n\0");
    noopstr msg = "Testing SHA256!\0";

    byte[32] hash;
    sha256_update(@ctx, @msg, (u64)strlen(msg));
    sha256_final(@ctx, @hash);

    print(ctx.state[0]);
    print();
    print(ctx.state[1]);
    print();
    print(ctx.state[2]);
    print();
    print(ctx.state[3]);
    print();
    print(ctx.state[4]);
    print();
    print(ctx.state[5]);
    print();
    print(ctx.state[6]);
    print();
    print(ctx.state[7]);

    return 0;
};