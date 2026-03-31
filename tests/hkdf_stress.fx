// Author: Karac V. Thweatt
// hkdf_stress.fx - Stress test for HKDF-SHA256 (RFC 5869)
//
// Tests:
//   1. RFC 5869 Appendix A test vectors (A.1, A.2, A.3) — correctness
//   2. Null salt path (Extract uses HashLen zero bytes)
//   3. Null info path (Expand skips info bytes)
//   4. Single-byte output (okm_len = 1)
//   5. Exact HashLen output (32 bytes)
//   6. Multi-block output (okm_len = 82, spans 3 T blocks)
//   7. Max-length output (okm_len = 8160 = 255 * 32)
//   8. Zero-length IKM
//   9. Large IKM (1024 bytes of 0xAB)
//  10. Repeated Extract on same inputs yields identical PRK
//  11. Different salts produce different PRKs
//  12. Throughput benchmark: N iterations of full HKDF on 32-byte IKM

#import "standard.fx", "cryptography.fx", "timing.fx", "datautils.fx";

using standard::io::console,
      standard::crypto::KDF::HKDF,
      standard::time;

// ---------------------------------------------------------------------------
// Test result tracking
// ---------------------------------------------------------------------------

global int g_pass, g_fail;

def record(byte* name, int ok) -> void
{
    if (ok)
    {
        print("  [PASS] \0");
        print(name);
        print("\n\0");
        g_pass = g_pass + 1;
    }
    else
    {
        print("  [FAIL] \0");
        print(name);
        print("\n\0");
        g_fail = g_fail + 1;
    };
};

// ---------------------------------------------------------------------------
// RFC 5869 Appendix A test vectors
//
// A.1: SHA-256, basic
//   IKM  = 0x0B * 22
//   salt = 0x000102...0c (13 bytes)
//   info = 0xF0F1...f9   (10 bytes)
//   L    = 42
//   PRK  = 077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5
//   OKM  = 3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf
//          34007208d5b887185865 (42 bytes)
//
// A.2: SHA-256, longer inputs/outputs
//   IKM  = 0x000102...4f (80 bytes)
//   salt = 0x606162...af (80 bytes)
//   info = 0xB0B1B2...ef (80 bytes)
//   L    = 82
//   PRK  = 06a6b88c5853361a06104d9d6980e3a19b7a5d73ba3c0a1a78bf76a4a71d8a67
//   OKM  = b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c
//          59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71
//          cc30c58179ec3e87c14c01d5c1f3434f1d87 (82 bytes)
//
// A.3: SHA-256, zero-length salt and info
//   IKM  = 0x0B * 22
//   salt = not provided (null)
//   info = not provided (null)
//   L    = 42
//   PRK  = 19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04
//   OKM  = 8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d
//          9d201395faa4b61a96c8 (42 bytes)
// ---------------------------------------------------------------------------

def test_rfc_a1() -> void
{
    // IKM: 0x0B repeated 22 times
    byte[22] ikm;
    // salt: 0x00 0x01 ... 0x0C
    byte[13] salt;
    // info: 0xF0 0xF1 ... 0xF9
    byte[10] info;
    byte[42] okm;
    // Expected OKM bytes
    byte[42] expected_okm;
    int i;

    fill_buf(@ikm[0], 22, (byte)0x0B);

    for (i = 0; i < 13; i++)
    {
        salt[i] = (byte)i;
    };

    for (i = 0; i < 10; i++)
    {
        info[i] = (byte)(0xF0 + i);
    };

    // Expected OKM (RFC 5869 A.1)
    expected_okm[0]  = (byte)0x3C; expected_okm[1]  = (byte)0xB2; expected_okm[2]  = (byte)0x5F;
    expected_okm[3]  = (byte)0x25; expected_okm[4]  = (byte)0xFA; expected_okm[5]  = (byte)0xAC;
    expected_okm[6]  = (byte)0xD5; expected_okm[7]  = (byte)0x7A; expected_okm[8]  = (byte)0x90;
    expected_okm[9]  = (byte)0x43; expected_okm[10] = (byte)0x4F; expected_okm[11] = (byte)0x64;
    expected_okm[12] = (byte)0xD0; expected_okm[13] = (byte)0x36; expected_okm[14] = (byte)0x2F;
    expected_okm[15] = (byte)0x2A; expected_okm[16] = (byte)0x2D; expected_okm[17] = (byte)0x2D;
    expected_okm[18] = (byte)0x0A; expected_okm[19] = (byte)0x90; expected_okm[20] = (byte)0xCF;
    expected_okm[21] = (byte)0x1A; expected_okm[22] = (byte)0x5A; expected_okm[23] = (byte)0x4C;
    expected_okm[24] = (byte)0x5D; expected_okm[25] = (byte)0xB0; expected_okm[26] = (byte)0x2D;
    expected_okm[27] = (byte)0x56; expected_okm[28] = (byte)0xEC; expected_okm[29] = (byte)0xC4;
    expected_okm[30] = (byte)0xC5; expected_okm[31] = (byte)0xBF; expected_okm[32] = (byte)0x34;
    expected_okm[33] = (byte)0x00; expected_okm[34] = (byte)0x72; expected_okm[35] = (byte)0x08;
    expected_okm[36] = (byte)0xD5; expected_okm[37] = (byte)0xB8; expected_okm[38] = (byte)0x87;
    expected_okm[39] = (byte)0x18; expected_okm[40] = (byte)0x58; expected_okm[41] = (byte)0x65;

    hkdf(@salt[0], 13, @ikm[0], 22, @info[0], 10, @okm[0], 42);

    print("    OKM: \0");
    print_hex(@okm[0], 42);
    print("\n\0");

    record("RFC 5869 A.1 (basic SHA-256)\0", bytes_eq(@okm[0], @expected_okm[0], 42));
};

def test_rfc_a2() -> void
{
    byte[80] ikm, salt, info;
    byte[82] okm;
    byte[82] expected_okm;
    int i;

    for (i = 0; i < 80; i++)
    {
        ikm[i]  = (byte)i;
        salt[i] = (byte)(0x60 + i);
        info[i] = (byte)(0xB0 + i);
    };

    // Expected OKM (RFC 5869 A.2)
    expected_okm[0]  = (byte)0xB1; expected_okm[1]  = (byte)0x1E; expected_okm[2]  = (byte)0x39;
    expected_okm[3]  = (byte)0x8D; expected_okm[4]  = (byte)0xC8; expected_okm[5]  = (byte)0x03;
    expected_okm[6]  = (byte)0x27; expected_okm[7]  = (byte)0xA1; expected_okm[8]  = (byte)0xC8;
    expected_okm[9]  = (byte)0xE7; expected_okm[10] = (byte)0xF7; expected_okm[11] = (byte)0x8C;
    expected_okm[12] = (byte)0x59; expected_okm[13] = (byte)0x6A; expected_okm[14] = (byte)0x49;
    expected_okm[15] = (byte)0x34; expected_okm[16] = (byte)0x4F; expected_okm[17] = (byte)0x01;
    expected_okm[18] = (byte)0x2E; expected_okm[19] = (byte)0xDA; expected_okm[20] = (byte)0x2D;
    expected_okm[21] = (byte)0x4E; expected_okm[22] = (byte)0xFA; expected_okm[23] = (byte)0xD8;
    expected_okm[24] = (byte)0xA0; expected_okm[25] = (byte)0x50; expected_okm[26] = (byte)0xCC;
    expected_okm[27] = (byte)0x4C; expected_okm[28] = (byte)0x19; expected_okm[29] = (byte)0xAF;
    expected_okm[30] = (byte)0xA9; expected_okm[31] = (byte)0x7C; expected_okm[32] = (byte)0x59;
    expected_okm[33] = (byte)0x04; expected_okm[34] = (byte)0x5A; expected_okm[35] = (byte)0x99;
    expected_okm[36] = (byte)0xCA; expected_okm[37] = (byte)0xC7; expected_okm[38] = (byte)0x82;
    expected_okm[39] = (byte)0x72; expected_okm[40] = (byte)0x71; expected_okm[41] = (byte)0xCB;
    expected_okm[42] = (byte)0x41; expected_okm[43] = (byte)0xC6; expected_okm[44] = (byte)0x5E;
    expected_okm[45] = (byte)0x59; expected_okm[46] = (byte)0x0E; expected_okm[47] = (byte)0x09;
    expected_okm[48] = (byte)0xDA; expected_okm[49] = (byte)0x32; expected_okm[50] = (byte)0x75;
    expected_okm[51] = (byte)0x60; expected_okm[52] = (byte)0x0C; expected_okm[53] = (byte)0x2F;
    expected_okm[54] = (byte)0x09; expected_okm[55] = (byte)0xB8; expected_okm[56] = (byte)0x36;
    expected_okm[57] = (byte)0x77; expected_okm[58] = (byte)0x93; expected_okm[59] = (byte)0xA9;
    expected_okm[60] = (byte)0xAC; expected_okm[61] = (byte)0xA3; expected_okm[62] = (byte)0xDB;
    expected_okm[63] = (byte)0x71; expected_okm[64] = (byte)0xCC; expected_okm[65] = (byte)0x30;
    expected_okm[66] = (byte)0xC5; expected_okm[67] = (byte)0x81; expected_okm[68] = (byte)0x79;
    expected_okm[69] = (byte)0xEC; expected_okm[70] = (byte)0x3E; expected_okm[71] = (byte)0x87;
    expected_okm[72] = (byte)0xC1; expected_okm[73] = (byte)0x4C; expected_okm[74] = (byte)0x01;
    expected_okm[75] = (byte)0xD5; expected_okm[76] = (byte)0xC1; expected_okm[77] = (byte)0xF3;
    expected_okm[78] = (byte)0x43; expected_okm[79] = (byte)0x4F; expected_okm[80] = (byte)0x1D;
    expected_okm[81] = (byte)0x87;

    hkdf(@salt[0], 80, @ikm[0], 80, @info[0], 80, @okm[0], 82);

    print("    OKM: \0");
    print_hex(@okm[0], 82);
    print("\n\0");

    record("RFC 5869 A.2 (long inputs/outputs)\0", bytes_eq(@okm[0], @expected_okm[0], 82));
};

def test_rfc_a3() -> void
{
    byte[22] ikm;
    byte[42] okm;
    byte[42] expected_okm;

    fill_buf(@ikm[0], 22, (byte)0x0B);

    // Expected OKM (RFC 5869 A.3 — null salt, null info)
    expected_okm[0]  = (byte)0x8D; expected_okm[1]  = (byte)0xA4; expected_okm[2]  = (byte)0xE7;
    expected_okm[3]  = (byte)0x75; expected_okm[4]  = (byte)0xA5; expected_okm[5]  = (byte)0x63;
    expected_okm[6]  = (byte)0xC1; expected_okm[7]  = (byte)0x8F; expected_okm[8]  = (byte)0x71;
    expected_okm[9]  = (byte)0x5F; expected_okm[10] = (byte)0x80; expected_okm[11] = (byte)0x2A;
    expected_okm[12] = (byte)0x06; expected_okm[13] = (byte)0x3C; expected_okm[14] = (byte)0x5A;
    expected_okm[15] = (byte)0x31; expected_okm[16] = (byte)0xB8; expected_okm[17] = (byte)0xA1;
    expected_okm[18] = (byte)0x1F; expected_okm[19] = (byte)0x5C; expected_okm[20] = (byte)0x5E;
    expected_okm[21] = (byte)0xE1; expected_okm[22] = (byte)0x87; expected_okm[23] = (byte)0x9E;
    expected_okm[24] = (byte)0xC3; expected_okm[25] = (byte)0x45; expected_okm[26] = (byte)0x4E;
    expected_okm[27] = (byte)0x5F; expected_okm[28] = (byte)0x3C; expected_okm[29] = (byte)0x73;
    expected_okm[30] = (byte)0x8D; expected_okm[31] = (byte)0x2D; expected_okm[32] = (byte)0x9D;
    expected_okm[33] = (byte)0x20; expected_okm[34] = (byte)0x13; expected_okm[35] = (byte)0x95;
    expected_okm[36] = (byte)0xFA; expected_okm[37] = (byte)0xA4; expected_okm[38] = (byte)0xB6;
    expected_okm[39] = (byte)0x1A; expected_okm[40] = (byte)0x96; expected_okm[41] = (byte)0xC8;

    // null salt, null info
    hkdf((byte*)0, 0, @ikm[0], 22, (byte*)0, 0, @okm[0], 42);

    print("    OKM: \0");
    print_hex(@okm[0], 42);
    print("\n\0");

    record("RFC 5869 A.3 (null salt + null info)\0", bytes_eq(@okm[0], @expected_okm[0], 42));
};

// ---------------------------------------------------------------------------
// Edge-case tests
// ---------------------------------------------------------------------------

def test_single_byte_output() -> void
{
    byte[16] ikm, salt;
    byte[1] okm_a, okm_b;

    fill_buf(@ikm[0],  16, (byte)0x42);
    fill_buf(@salt[0], 16, (byte)0x11);

    hkdf(@salt[0], 16, @ikm[0], 16, (byte*)0, 0, @okm_a[0], 1);
    hkdf(@salt[0], 16, @ikm[0], 16, (byte*)0, 0, @okm_b[0], 1);

    // Same inputs must produce identical single byte
    record("single-byte output deterministic\0", (okm_a[0] == okm_b[0]) ? 1 : 0);
};

def test_exact_hashlen() -> void
{
    byte[32] ikm, salt, okm_a, okm_b;

    fill_buf(@ikm[0],  32, (byte)0xDE);
    fill_buf(@salt[0], 32, (byte)0xAD);

    hkdf(@salt[0], 32, @ikm[0], 32, (byte*)0, 0, @okm_a[0], 32);
    hkdf(@salt[0], 32, @ikm[0], 32, (byte*)0, 0, @okm_b[0], 32);

    record("exact HashLen (32 bytes) deterministic\0", bytes_eq(@okm_a[0], @okm_b[0], 32));
};

def test_zero_len_ikm() -> void
{
    byte[16] salt;
    byte[16] okm_a, okm_b;
    byte[1] dummy;

    fill_buf(@salt[0], 16, (byte)0x55);

    // Zero-length IKM — point at dummy to avoid null pointer
    hkdf(@salt[0], 16, @dummy[0], 0, (byte*)0, 0, @okm_a[0], 16);
    hkdf(@salt[0], 16, @dummy[0], 0, (byte*)0, 0, @okm_b[0], 16);

    record("zero-length IKM deterministic\0", bytes_eq(@okm_a[0], @okm_b[0], 16));
};

def test_different_salts_differ() -> void
{
    byte[16] ikm, salt_a, salt_b;
    byte[32] okm_a, okm_b;

    fill_buf(@ikm[0],    16, (byte)0xCC);
    fill_buf(@salt_a[0], 16, (byte)0x01);
    fill_buf(@salt_b[0], 16, (byte)0x02);

    hkdf(@salt_a[0], 16, @ikm[0], 16, (byte*)0, 0, @okm_a[0], 32);
    hkdf(@salt_b[0], 16, @ikm[0], 16, (byte*)0, 0, @okm_b[0], 32);

    record("different salts produce different OKM\0", (bytes_eq(@okm_a[0], @okm_b[0], 32) == 0) ? 1 : 0);
};

def test_different_infos_differ() -> void
{
    byte[32] ikm, salt;
    byte[4] info_a, info_b;
    byte[32] okm_a, okm_b;

    fill_buf(@ikm[0],  32, (byte)0xAA);
    fill_buf(@salt[0], 32, (byte)0xBB);
    info_a[0] = (byte)'t'; info_a[1] = (byte)'l'; info_a[2] = (byte)'s'; info_a[3] = (byte)'1';
    info_b[0] = (byte)'t'; info_b[1] = (byte)'l'; info_b[2] = (byte)'s'; info_b[3] = (byte)'2';

    hkdf(@salt[0], 32, @ikm[0], 32, @info_a[0], 4, @okm_a[0], 32);
    hkdf(@salt[0], 32, @ikm[0], 32, @info_b[0], 4, @okm_b[0], 32);

    record("different info produces different OKM\0", (bytes_eq(@okm_a[0], @okm_b[0], 32) == 0) ? 1 : 0);
};

def test_repeated_extract_deterministic() -> void
{
    byte[32] ikm, salt, prk_a, prk_b;

    fill_buf(@ikm[0],  32, (byte)0x77);
    fill_buf(@salt[0], 32, (byte)0x88);

    hkdf_extract(@salt[0], 32, @ikm[0], 32, @prk_a[0]);
    hkdf_extract(@salt[0], 32, @ikm[0], 32, @prk_b[0]);

    record("Extract is deterministic\0", bytes_eq(@prk_a[0], @prk_b[0], 32));
};

def test_expand_length_guard() -> void
{
    byte[32] prk, okm;
    int ret;

    fill_buf(@prk[0], 32, (byte)0x99);

    // 8161 > 255 * 32, must return 0
    ret = hkdf_expand(@prk[0], (byte*)0, 0, @okm[0], 8161);
    record("Expand rejects okm_len > 8160\0", (ret == 0) ? 1 : 0);

    // 8160 == 255 * 32, must return 1 (we only test return code, not the full buffer)
    // Use a heap-allocated buffer to avoid blowing the stack with 8160 bytes
    byte* big = (byte*)fmalloc(8160);
    ret = hkdf_expand(@prk[0], (byte*)0, 0, big, 8160);
    ffree(big);
    record("Expand accepts okm_len == 8160\0", (ret == 1) ? 1 : 0);
};

// ---------------------------------------------------------------------------
// Throughput benchmark
// ---------------------------------------------------------------------------

#def BENCH_ITERS 10000;

def bench_throughput() -> void
{
    byte[32] ikm, salt, okm;
    byte[13] info;
    i64 t0, t1, elapsed_ns;
    int i;

    fill_buf(@ikm[0],  32, (byte)0x5A);
    fill_buf(@salt[0], 32, (byte)0xA5);
    info[0] = (byte)'b'; info[1] = (byte)'e'; info[2] = (byte)'n';
    info[3] = (byte)'c'; info[4] = (byte)'h'; info[5] = (byte)'m';
    info[6] = (byte)'a'; info[7] = (byte)'r'; info[8] = (byte)'k';
    info[9] = (byte)' '; info[10] = (byte)'t'; info[11] = (byte)'l';
    info[12] = (byte)'s';

    t0 = time_now();

    for (i = 0; i < BENCH_ITERS; i++)
    {
        hkdf(@salt[0], 32, @ikm[0], 32, @info[0], 13, @okm[0], 32);
    };

    t1 = time_now();

    elapsed_ns = t1 - t0;

    print("  Throughput: \0");
    print(BENCH_ITERS);
    print(" x hkdf(32-byte IKM -> 32-byte OKM) in \0");
    print((int)(elapsed_ns / 1000000));
    print(" ms  (\0");
    print((int)(elapsed_ns / BENCH_ITERS));
    print(" ns/call)\n\0");
};

// ---------------------------------------------------------------------------
// TLS 1.3 label-style expansion smoke test
// Mirrors what the handshake will actually call:
//   hkdf_expand_label(secret, "derived", "", 32)
//   hkdf_expand_label(secret, "c hs traffic", transcript_hash, 32)
// These are called with HkdfLabel = length(2) || "tls13 " + label || context
// We test the raw Expand against known-good structures to confirm the output
// changes correctly with label changes.
// ---------------------------------------------------------------------------

def test_tls13_label_style() -> void
{
    // Simulate: two different HkdfLabel info blobs derived from the same PRK.
    // Label A: length=0x00 0x20 | "tls13 derived\0" | context_len=0x00
    // Label B: length=0x00 0x20 | "tls13 c hs traffic\0" | context_len=0x20 | 32 zero bytes
    // We just verify the two produce different output — full label encoding lives
    // in the record layer module.
    byte[32] prk, okm_a, okm_b;
    byte[16] info_a;
    byte[20] info_b;
    int i;

    fill_buf(@prk[0], 32, (byte)0xFE);

    // info_a: short label
    info_a[0]  = (byte)'t'; info_a[1]  = (byte)'l'; info_a[2]  = (byte)'s';
    info_a[3]  = (byte)'1'; info_a[4]  = (byte)'3'; info_a[5]  = (byte)' ';
    info_a[6]  = (byte)'d'; info_a[7]  = (byte)'e'; info_a[8]  = (byte)'r';
    info_a[9]  = (byte)'i'; info_a[10] = (byte)'v'; info_a[11] = (byte)'e';
    info_a[12] = (byte)'d'; info_a[13] = (byte)0x00; info_a[14] = (byte)0x00;
    info_a[15] = (byte)0x00;

    // info_b: longer label
    info_b[0]  = (byte)'t'; info_b[1]  = (byte)'l'; info_b[2]  = (byte)'s';
    info_b[3]  = (byte)'1'; info_b[4]  = (byte)'3'; info_b[5]  = (byte)' ';
    info_b[6]  = (byte)'c'; info_b[7]  = (byte)' '; info_b[8]  = (byte)'h';
    info_b[9]  = (byte)'s'; info_b[10] = (byte)' '; info_b[11] = (byte)'t';
    info_b[12] = (byte)'r'; info_b[13] = (byte)'a'; info_b[14] = (byte)'f';
    info_b[15] = (byte)'f'; info_b[16] = (byte)'i'; info_b[17] = (byte)'c';
    info_b[18] = (byte)0x00; info_b[19] = (byte)0x00;

    hkdf_expand(@prk[0], @info_a[0], 16, @okm_a[0], 32);
    hkdf_expand(@prk[0], @info_b[0], 20, @okm_b[0], 32);

    record("TLS 1.3 label-style: different labels differ\0",
           (bytes_eq(@okm_a[0], @okm_b[0], 32) == 0) ? 1 : 0);

    print("    OKM-derived:    \0"); print_hex(@okm_a[0], 32); print("\n\0");
    print("    OKM-c-hs-traf:  \0"); print_hex(@okm_b[0], 32); print("\n\0");
};

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

def main() -> int
{
    print("=== HKDF-SHA256 Stress Test ===\n\n\0");

    print("-- RFC 5869 Test Vectors --\n\0");
    test_rfc_a1();
    test_rfc_a2();
    test_rfc_a3();

    print("\n-- Edge Cases --\n\0");
    test_single_byte_output();
    test_exact_hashlen();
    test_zero_len_ikm();
    test_different_salts_differ();
    test_different_infos_differ();
    test_repeated_extract_deterministic();
    test_expand_length_guard();

    print("\n-- TLS 1.3 Label Style --\n\0");
    test_tls13_label_style();

    print("\n-- Throughput Benchmark --\n\0");
    bench_throughput();

    print("\n=== Results: \0");
    print(g_pass);
    print(" passed, \0");
    print(g_fail);
    print(" failed ===\n\0");

    return g_fail;
};
