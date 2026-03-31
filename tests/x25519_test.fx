// x25519_test.fx - X25519 ECDH test using RFC 7748 vectors

#import "standard.fx", "cryptography.fx";

using standard::io::console,
      standard::strings,
      standard::crypto::ECDH::X25519;

def print_bytes_hex(byte* buf, int len) -> void
{
    int  i;
    byte b, hi, lo;
    while (i < len)
    {
        b  = buf[i];
        hi = (b >> 4) & (byte)0x0F;
        lo = b & (byte)0x0F;
        if (hi < (byte)10) { print((byte)('0' + hi)); }
        else               { print((byte)('A' + (hi - (byte)10))); };
        if (lo < (byte)10) { print((byte)('0' + lo)); }
        else               { print((byte)('A' + (lo - (byte)10))); };
        i++;
    };
    return;
};

def eq32(byte* a, byte* b) -> bool
{
    int i;
    while (i < 32)
    {
        if (a[i] != b[i]) { return false; };
        i++;
    };
    return true;
};

def main() -> int
{
    byte[32] pub_a, pub_b, shared_a, shared_b;
    byte[32] priv_a, priv_b;
    byte[32] expected_pub_a, expected_pub_b, expected_shared;
    byte[32] scalar_k, scalar_u, iter_result, expected_iter1;
    int      passed, failed, i;

    // RFC 7748 section 6.1 - Alice private scalar
    priv_a[0]  = (byte)0x77; priv_a[1]  = (byte)0x07; priv_a[2]  = (byte)0x6D; priv_a[3]  = (byte)0x0A;
    priv_a[4]  = (byte)0x73; priv_a[5]  = (byte)0x18; priv_a[6]  = (byte)0xA5; priv_a[7]  = (byte)0x7D;
    priv_a[8]  = (byte)0x3C; priv_a[9]  = (byte)0x16; priv_a[10] = (byte)0xC1; priv_a[11] = (byte)0x72;
    priv_a[12] = (byte)0x51; priv_a[13] = (byte)0xB2; priv_a[14] = (byte)0x66; priv_a[15] = (byte)0x45;
    priv_a[16] = (byte)0xDF; priv_a[17] = (byte)0x4C; priv_a[18] = (byte)0x2F; priv_a[19] = (byte)0x87;
    priv_a[20] = (byte)0xEB; priv_a[21] = (byte)0xC0; priv_a[22] = (byte)0x99; priv_a[23] = (byte)0x2A;
    priv_a[24] = (byte)0xB1; priv_a[25] = (byte)0x77; priv_a[26] = (byte)0xFB; priv_a[27] = (byte)0xA5;
    priv_a[28] = (byte)0x1D; priv_a[29] = (byte)0xB9; priv_a[30] = (byte)0x2C; priv_a[31] = (byte)0x2A;

    // RFC 7748 section 6.1 - Bob private scalar
    priv_b[0]  = (byte)0x5D; priv_b[1]  = (byte)0xAB; priv_b[2]  = (byte)0x08; priv_b[3]  = (byte)0x7E;
    priv_b[4]  = (byte)0x62; priv_b[5]  = (byte)0x4A; priv_b[6]  = (byte)0x8A; priv_b[7]  = (byte)0x4B;
    priv_b[8]  = (byte)0x79; priv_b[9]  = (byte)0xE1; priv_b[10] = (byte)0x7F; priv_b[11] = (byte)0x8B;
    priv_b[12] = (byte)0x83; priv_b[13] = (byte)0x80; priv_b[14] = (byte)0x0E; priv_b[15] = (byte)0xE6;
    priv_b[16] = (byte)0x6F; priv_b[17] = (byte)0x3B; priv_b[18] = (byte)0xB1; priv_b[19] = (byte)0x29;
    priv_b[20] = (byte)0x26; priv_b[21] = (byte)0x18; priv_b[22] = (byte)0xB6; priv_b[23] = (byte)0xFD;
    priv_b[24] = (byte)0x1C; priv_b[25] = (byte)0x2F; priv_b[26] = (byte)0x8B; priv_b[27] = (byte)0x27;
    priv_b[28] = (byte)0xFF; priv_b[29] = (byte)0x88; priv_b[30] = (byte)0xE0; priv_b[31] = (byte)0xEB;

    // Expected Alice public key
    expected_pub_a[0]  = (byte)0x85; expected_pub_a[1]  = (byte)0x20; expected_pub_a[2]  = (byte)0xF0; expected_pub_a[3]  = (byte)0x09;
    expected_pub_a[4]  = (byte)0x89; expected_pub_a[5]  = (byte)0x30; expected_pub_a[6]  = (byte)0xA7; expected_pub_a[7]  = (byte)0x54;
    expected_pub_a[8]  = (byte)0x74; expected_pub_a[9]  = (byte)0x8B; expected_pub_a[10] = (byte)0x7D; expected_pub_a[11] = (byte)0xDC;
    expected_pub_a[12] = (byte)0xB4; expected_pub_a[13] = (byte)0x3E; expected_pub_a[14] = (byte)0xF7; expected_pub_a[15] = (byte)0x5A;
    expected_pub_a[16] = (byte)0x0D; expected_pub_a[17] = (byte)0xBF; expected_pub_a[18] = (byte)0x3A; expected_pub_a[19] = (byte)0x0D;
    expected_pub_a[20] = (byte)0x26; expected_pub_a[21] = (byte)0x38; expected_pub_a[22] = (byte)0x1A; expected_pub_a[23] = (byte)0xF4;
    expected_pub_a[24] = (byte)0xEB; expected_pub_a[25] = (byte)0xA4; expected_pub_a[26] = (byte)0xA9; expected_pub_a[27] = (byte)0x8E;
    expected_pub_a[28] = (byte)0xAA; expected_pub_a[29] = (byte)0x9B; expected_pub_a[30] = (byte)0x4E; expected_pub_a[31] = (byte)0x6A;

    // Expected Bob public key
    expected_pub_b[0]  = (byte)0xDE; expected_pub_b[1]  = (byte)0x9E; expected_pub_b[2]  = (byte)0xDB; expected_pub_b[3]  = (byte)0x7D;
    expected_pub_b[4]  = (byte)0x7B; expected_pub_b[5]  = (byte)0x7D; expected_pub_b[6]  = (byte)0xC1; expected_pub_b[7]  = (byte)0xB4;
    expected_pub_b[8]  = (byte)0xD3; expected_pub_b[9]  = (byte)0x5B; expected_pub_b[10] = (byte)0x61; expected_pub_b[11] = (byte)0xC2;
    expected_pub_b[12] = (byte)0xEC; expected_pub_b[13] = (byte)0xE4; expected_pub_b[14] = (byte)0x35; expected_pub_b[15] = (byte)0x37;
    expected_pub_b[16] = (byte)0x3F; expected_pub_b[17] = (byte)0x83; expected_pub_b[18] = (byte)0x43; expected_pub_b[19] = (byte)0xC8;
    expected_pub_b[20] = (byte)0x5B; expected_pub_b[21] = (byte)0x78; expected_pub_b[22] = (byte)0x67; expected_pub_b[23] = (byte)0x4D;
    expected_pub_b[24] = (byte)0xAD; expected_pub_b[25] = (byte)0xFC; expected_pub_b[26] = (byte)0x7E; expected_pub_b[27] = (byte)0x14;
    expected_pub_b[28] = (byte)0x6F; expected_pub_b[29] = (byte)0x88; expected_pub_b[30] = (byte)0x2B; expected_pub_b[31] = (byte)0x4F;

    // Expected shared secret
    expected_shared[0]  = (byte)0x4A; expected_shared[1]  = (byte)0x5D; expected_shared[2]  = (byte)0x9D; expected_shared[3]  = (byte)0x5B;
    expected_shared[4]  = (byte)0xA4; expected_shared[5]  = (byte)0xCE; expected_shared[6]  = (byte)0x2D; expected_shared[7]  = (byte)0xE1;
    expected_shared[8]  = (byte)0x72; expected_shared[9]  = (byte)0x8E; expected_shared[10] = (byte)0x3B; expected_shared[11] = (byte)0xF4;
    expected_shared[12] = (byte)0x80; expected_shared[13] = (byte)0x35; expected_shared[14] = (byte)0x0F; expected_shared[15] = (byte)0x25;
    expected_shared[16] = (byte)0xE0; expected_shared[17] = (byte)0x7E; expected_shared[18] = (byte)0x21; expected_shared[19] = (byte)0xC9;
    expected_shared[20] = (byte)0x47; expected_shared[21] = (byte)0xD1; expected_shared[22] = (byte)0x9E; expected_shared[23] = (byte)0x33;
    expected_shared[24] = (byte)0x76; expected_shared[25] = (byte)0xF0; expected_shared[26] = (byte)0x9B; expected_shared[27] = (byte)0x3C;
    expected_shared[28] = (byte)0x1E; expected_shared[29] = (byte)0x16; expected_shared[30] = (byte)0x17; expected_shared[31] = (byte)0x42;

    // RFC 7748 iterative vector: x25519(9, 9) after 1 iteration
    expected_iter1[0]  = (byte)0x42; expected_iter1[1]  = (byte)0x2C; expected_iter1[2]  = (byte)0x8E; expected_iter1[3]  = (byte)0x7A;
    expected_iter1[4]  = (byte)0x62; expected_iter1[5]  = (byte)0x27; expected_iter1[6]  = (byte)0xD7; expected_iter1[7]  = (byte)0xBC;
    expected_iter1[8]  = (byte)0xA1; expected_iter1[9]  = (byte)0x35; expected_iter1[10] = (byte)0x0B; expected_iter1[11] = (byte)0x3E;
    expected_iter1[12] = (byte)0x2B; expected_iter1[13] = (byte)0xB7; expected_iter1[14] = (byte)0x27; expected_iter1[15] = (byte)0x9F;
    expected_iter1[16] = (byte)0x78; expected_iter1[17] = (byte)0x97; expected_iter1[18] = (byte)0xB8; expected_iter1[19] = (byte)0x7B;
    expected_iter1[20] = (byte)0xB6; expected_iter1[21] = (byte)0x85; expected_iter1[22] = (byte)0x4B; expected_iter1[23] = (byte)0x78;
    expected_iter1[24] = (byte)0x3C; expected_iter1[25] = (byte)0x60; expected_iter1[26] = (byte)0xE8; expected_iter1[27] = (byte)0x03;
    expected_iter1[28] = (byte)0x11; expected_iter1[29] = (byte)0xAE; expected_iter1[30] = (byte)0x30; expected_iter1[31] = (byte)0x79;

    print("==== X25519 ECDH TEST ====\n\0");

    // Test 1: Alice public key
    X25519::x25519_pubkey(@pub_a[0], @priv_a[0]);
    print("Alice pubkey:  \0"); print_bytes_hex(@pub_a[0], 32); print("\n\0");
    if (eq32(@pub_a[0], @expected_pub_a[0]))
    {
        print("[PASS] Alice public key\n\0");
        passed++;
    }
    else
    {
        print("[FAIL] Alice public key\n\0");
        print("  expected: \0"); print_bytes_hex(@expected_pub_a[0], 32); print("\n\0");
        failed++;
    };

    // Test 2: Bob public key
    X25519::x25519_pubkey(@pub_b[0], @priv_b[0]);
    print("Bob   pubkey:  \0"); print_bytes_hex(@pub_b[0], 32); print("\n\0");
    if (eq32(@pub_b[0], @expected_pub_b[0]))
    {
        print("[PASS] Bob public key\n\0");
        passed++;
    }
    else
    {
        print("[FAIL] Bob public key\n\0");
        print("  expected: \0"); print_bytes_hex(@expected_pub_b[0], 32); print("\n\0");
        failed++;
    };

    // Test 3: Alice computes shared secret using Bob's public key
    X25519::x25519(@shared_a[0], @priv_a[0], @pub_b[0]);
    print("Shared (A):    \0"); print_bytes_hex(@shared_a[0], 32); print("\n\0");
    if (eq32(@shared_a[0], @expected_shared[0]))
    {
        print("[PASS] Alice shared secret\n\0");
        passed++;
    }
    else
    {
        print("[FAIL] Alice shared secret\n\0");
        print("  expected: \0"); print_bytes_hex(@expected_shared[0], 32); print("\n\0");
        failed++;
    };

    // Test 4: Bob computes shared secret using Alice's public key
    X25519::x25519(@shared_b[0], @priv_b[0], @pub_a[0]);
    print("Shared (B):    \0"); print_bytes_hex(@shared_b[0], 32); print("\n\0");
    if (eq32(@shared_b[0], @expected_shared[0]))
    {
        print("[PASS] Bob shared secret\n\0");
        passed++;
    }
    else
    {
        print("[FAIL] Bob shared secret\n\0");
        print("  expected: \0"); print_bytes_hex(@expected_shared[0], 32); print("\n\0");
        failed++;
    };

    // Test 5: Both sides agree
    if (eq32(@shared_a[0], @shared_b[0]))
    {
        print("[PASS] Shared secrets match\n\0");
        passed++;
    }
    else
    {
        print("[FAIL] Shared secrets do not match\n\0");
        failed++;
    };

    // Test 6: RFC 7748 iterative vector - x25519(9, 9)
    while (i < 32) { scalar_k[i] = (byte)0; scalar_u[i] = (byte)0; i++; };
    scalar_k[0] = (byte)9;
    scalar_u[0] = (byte)9;
    X25519::x25519(@iter_result[0], @scalar_k[0], @scalar_u[0]);
    print("Iter 1:        \0"); print_bytes_hex(@iter_result[0], 32); print("\n\0");
    if (eq32(@iter_result[0], @expected_iter1[0]))
    {
        print("[PASS] Iterative vector (1 iteration)\n\0");
        passed++;
    }
    else
    {
        print("[FAIL] Iterative vector (1 iteration)\n\0");
        print("  expected: \0"); print_bytes_hex(@expected_iter1[0], 32); print("\n\0");
        failed++;
    };

    print("\n\0");
    print("Passed: \0"); print(passed); print("\n\0");
    print("Failed: \0"); print(failed); print("\n\0");

    return failed;
};
