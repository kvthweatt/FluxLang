import "standard.fx";
using standard::io, standard::types;

// Constants
const uint32[64] K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

// Initial hash values
const uint32[8] H0 = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
];

// Utility functions
def rotr(uint32 x, uint32 n) -> uint32 {
    return (x >> n) | (x << (32 - n));
}

def ch(uint32 x, uint32 y, uint32 z) -> uint32 {
    return (x & y) ^ (~x & z);
}

def maj(uint32 x, uint32 y, uint32 z) -> uint32 {
    return (x & y) ^ (x & z) ^ (y & z);
}

def Σ0(uint32 x) -> uint32 {
    return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
}

def Σ1(uint32 x) -> uint32 {
    return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
}

def σ0(uint32 x) -> uint32 {
    return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
}

def σ1(uint32 x) -> uint32 {
    return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
}

// Main SHA-256 function
def sha256(uint8[] message) -> uint8[32] {
    // Pre-processing
    uint64 original_bit_len = message.size * 8;
    uint64 new_bit_len = original_bit_len + 1 + 64;
    uint64 blocks_needed = (new_bit_len + 511) / 512;
    uint64 padded_len = blocks_needed * 64;
    
    uint8[padded_len] padded;
    for (uint64 i = 0; i < message.size; i++) {
        padded[i] = message[i];
    }
    
    // Append '1' bit
    padded[message.size] = 0x80;
    
    // Append length in bits (big-endian)
    for (uint32 i = 0; i < 8; i++) {
        padded[padded_len - 8 + i] = (original_bit_len >> (56 - i*8)) & 0xff;
    }
    
    // Process each 512-bit block
    uint32[8] hash = H0;
    
    for (uint64 chunk = 0; chunk < padded_len; chunk += 64) {
        uint32[64] w;
        
        // Copy chunk into first 16 words
        for (uint32 i = 0; i < 16; i++) {
            w[i] = (padded[chunk + i*4] << 24) |
                   (padded[chunk + i*4 + 1] << 16) |
                   (padded[chunk + i*4 + 2] << 8) |
                   padded[chunk + i*4 + 3];
        }
        
        // Extend to 64 words
        for (uint32 i = 16; i < 64; i++) {
            w[i] = σ1(w[i-2]) + w[i-7] + σ0(w[i-15]) + w[i-16];
        }
        
        // Initialize working variables
        uint32 a = hash[0];
        uint32 b = hash[1];
        uint32 c = hash[2];
        uint32 d = hash[3];
        uint32 e = hash[4];
        uint32 f = hash[5];
        uint32 g = hash[6];
        uint32 h = hash[7];
        
        // Compression function
        for (uint32 i = 0; i < 64; i++) {
            uint32 temp1 = h + Σ1(e) + ch(e, f, g) + K[i] + w[i];
            uint32 temp2 = Σ0(a) + maj(a, b, c);
            
            h = g;
            g = f;
            f = e;
            e = d + temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 + temp2;
        }
        
        // Update hash values
        hash[0] += a;
        hash[1] += b;
        hash[2] += c;
        hash[3] += d;
        hash[4] += e;
        hash[5] += f;
        hash[6] += g;
        hash[7] += h;
    }
    
    // Produce final hash
    uint8[32] digest;
    for (uint32 i = 0; i < 8; i++) {
        digest[i*4] = (hash[i] >> 24) & 0xff;
        digest[i*4 + 1] = (hash[i] >> 16) & 0xff;
        digest[i*4 + 2] = (hash[i] >> 8) & 0xff;
        digest[i*4 + 3] = hash[i] & 0xff;
    }
    
    return digest;
}

// Helper function to print hash as hex
def print_hash(uint8[32] hash) {
    for (uint32 i = 0; i < 32; i++) {
        print(f"{hash[i]:02x}");
    }
    print("\n");
}

// Example usage
def main() -> int {
    string test = "hello world";
    uint8[test.size] message;
    
    // Convert string to byte array
    for (uint32 i = 0; i < test.size; i++) {
        message[i] = test[i];
    }
    
    uint8[32] hash = sha256(message);
    print("SHA-256 hash of \"hello world\": ");
    print_hash(hash);
    
    return 0;
}