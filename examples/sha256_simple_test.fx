// Simplified SHA256 test - basic functionality only

// Some SHA256 constants (first 8)
const uint32[8] K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
];

// Initial hash values
const uint32[8] H0 = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
];

def main() -> int
{
    // Test basic operations with hex constants
    uint32 a = K[0];  // 0x428a2f98
    uint32 b = H0[0]; // 0x6a09e667
    uint32 sum = a + b;
    
    return 0;  // Success
};