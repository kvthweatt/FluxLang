// SHA-256 Implementation in Flux

import "types.fx";

using standard::types;

// Core Constants
const u32[64] K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

const u32[8] H0 = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
];

// Rotate Right
operator (u32 x, int n)[>>>] -> u32 {
    return (x >> n) | (x << (32 - n));
};

contract NonEmptyMessage {
    assert(sizeof(msg) > 0, "Message cannot be empty");
}

contract NonEmptyInput {
    assert(sizeof(input) > 0, "Input cannot be empty");
}

def pad_message(byte[] msg) -> byte[] 
: NonEmptyMessage {
    u64 bit_len = sizeof(msg) * 8;
    byte[] padded = msg + [0x80];

    while ((sizeof(padded) % 64) != 56 {
        padded += [0x00];
    };

    padded += (byte[8])(bit_len >> 56);
    padded += (byte[8])(bit_len >> 48);
    padded += (byte[8])(bit_len >> 40);
    padded += (byte[8])(bit_len >> 32);
    padded += (byte[8])(bit_len >> 24);
    padded += (byte[8])(bit_len >> 16);
    padded += (byte[8])(bit_len >> 8);
    padded += (byte[8])bit_len;
    
    return padded;
};

// Core Transform Function
def process_block(byte[64] block, u32[8] hash) -> u32[8] {
    u32[64] W;
    u32 a, b, c, d, e, f, g, h;

    // Prepare message schedule
    for (int i = 0; i < 16; i++) {
        W[i] = (u32)block[i*4] << 24 |
               (u32)block[i*4+1] << 16 |
               (u32)block[i*4+2] << 8 |
               (u32)block[i*4+3];
    };

    // Extend to 64 words
    for (int i = 16; i < 64; i++) {
        u32 s0 = (W[i-15] >>> 7) ^ (W[i-15] >>> 18) ^ (W[i-15] >> 3);
        u32 s1 = (W[i-2] >>> 17) ^ (W[i-2] >>> 19) ^ (W[i-2] >> 10);
        W[i] = W[i-16] + s0 + W[i-7] + s1;
    };

    // Initialize working variables
    a = hash[0]; b = hash[1]; c = hash[2]; d = hash[3];
    e = hash[4]; f = hash[5]; g = hash[6]; h = hash[7];

    // Compression loop
    for (int i = 0; i < 64; i++) {
        u32 S1 = (e >>> 6) ^ (e >>> 11) ^ (e >>> 25);
        u32 ch = (e & f) ^ ((e) & g);
        u32 temp1 = h + S1 + ch + K[i] + W[i];
        u32 S0 = (a >>> 2) ^ (a >>> 13) ^ (a >>> 22);
        u32 maj = (a & b) ^ (a & c) ^ (b & c);
        u32 temp2 = S0 + maj;

        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    };

    // Update hash values
    return [
        hash[0] + a,
        hash[1] + b,
        hash[2] + c,
        hash[3] + d,
        hash[4] + e,
        hash[5] + f,
        hash[6] + g,
        hash[7] + h
    ];
};

def sha256(byte[] input) -> byte[32] 
: NonEmptyInput {
    u32[8] hash = H0;
    byte[] padded = pad_message(input);

    for (int i = 0; i < sizeof(padded); i += 64) {
        hash = process_block(padded[i:i+64], hash);
    };

    return (byte[32])hash;
};