// Author: Karac V. Thweatt
// ecdsa_test.fx - ECDSA P-256 test suite
//
// Tests:
//   1. Known-answer pubkey derivation (NIST FIPS 186-4 vector)
//   2. Sign then verify roundtrip
//   3. Verify rejects tampered hash
//   4. Verify rejects tampered signature (r corrupted)
//   5. DER encode / decode roundtrip
//   6. bigint_modpow known-answer
//   7. bigint_modinv known-answer + no-inverse detection

#import "standard.fx";
#import "cryptography.fx";

using standard::io::console;
using standard::crypto::hashing::SHA256;
using standard::crypto::ECDSA;

// Forward declarations
def test_pass(noopstr) -> void,
    test_fail(noopstr) -> void,
    print_hex32(byte*) -> void,
    print_hex(byte*, int) -> void,
    bytes_equal(byte*, byte*, int) -> bool,
    sha256_of(byte*, int, byte*) -> void;

// ---- Helpers ----

def print_hex32(byte* buf) -> void
{
    int i;
    byte hi, lo;
    for (i = 0; i < 32; i++)
    {
        hi = ((buf[i] >> 4) & 0x0F);
        lo = (buf[i] & 0x0F);
        if (hi < 10) { print(('0' + hi)); } else { print(('a' + (hi - 10))); };
        if (lo < 10) { print(('0' + lo)); } else { print(('a' + (lo - 10))); };
    };
    return;
};

def print_hex(byte* buf, int len) -> void
{
    int i;
    byte hi, lo;
    for (i = 0; i < len; i++)
    {
        hi = ((buf[i] >> 4) & 0x0F);
        lo = (buf[i] & 0x0F);
        if (hi < 10) { print(('0' + hi)); } else { print(('a' + (hi - 10))); };
        if (lo < 10) { print(('0' + lo)); } else { print(('a' + (lo - 10))); };
    };
    return;
};

def bytes_equal(byte* a, byte* b, int len) -> bool
{
    int i;
    for (i = 0; i < len; i++)
    {
        if (a[i] != b[i]) { return false; };
    };
    return true;
};

def sha256_of(byte* msg, int msg_len, byte* out32) -> void
{
    SHA256_CTX ctx;
    sha256_init(@ctx);
    sha256_update(@ctx, msg, (u64)msg_len);
    sha256_final(@ctx, out32);
    return;
};

def test_pass(noopstr s) -> void
{
    print("[PASS] \0");
    print(s);
    print("\n\0");
    return;
};

def test_fail(noopstr s) -> void
{
    print("[FAIL] \0");
    print(s);
    print("\n\0");
    return;
};

// ---- Shared key material used across multiple tests ----
// Private key: arbitrary valid scalar < n
// Nonce: arbitrary valid scalar < n (fixed for determinism; use RFC 6979 in production)

global byte[32] TEST_PRIVKEY = [
    0x51, 0x9B, 0x42, 0x3D, 0x71, 0x5F, 0x8B, 0x58,
    0x1F, 0x4F, 0xA8, 0xEE, 0x59, 0xF4, 0x77, 0x1A,
    0x5B, 0x44, 0xC8, 0x13, 0x0B, 0x4E, 0x3E, 0xAC,
    0xCA, 0x54, 0xA5, 0x6D, 0xDA, 0x72, 0xB4, 0x64
];

global byte[32] TEST_NONCE = [
    0x94, 0xA1, 0xBB, 0xB1, 0x4B, 0x90, 0x6A, 0x61,
    0xA2, 0x80, 0xF2, 0x45, 0xF9, 0xE9, 0x3C, 0x7F,
    0x3B, 0x4A, 0x62, 0x47, 0x82, 0x4F, 0x5D, 0x33,
    0xB9, 0x67, 0x07, 0x87, 0x64, 0x2A, 0x68, 0xDE
];

// ---- Test 1: NIST P-256 known-answer pubkey derivation ----
//
// NIST FIPS 186-4 test vector:
//   d  = C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721
//   Qx = 60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6
//   Qy = 7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299

global byte[32] NIST_D = [
    0xC9, 0xAF, 0xA9, 0xD8, 0x45, 0xBA, 0x75, 0x16,
    0x6B, 0x5C, 0x21, 0x57, 0x67, 0xB1, 0xD6, 0x93,
    0x4E, 0x50, 0xC3, 0xDB, 0x36, 0xE8, 0x9B, 0x12,
    0x7B, 0x8A, 0x62, 0x2B, 0x12, 0x0F, 0x67, 0x21
];

global byte[32] NIST_QX = [
    0x60, 0xFE, 0xD4, 0xBA, 0x25, 0x5A, 0x9D, 0x31,
    0xC9, 0x61, 0xEB, 0x74, 0xC6, 0x35, 0x6D, 0x68,
    0xC0, 0x49, 0xB8, 0x92, 0x3B, 0x61, 0xFA, 0x6C,
    0xE6, 0x69, 0x62, 0x2E, 0x60, 0xF2, 0x9F, 0xB6
];

global byte[32] NIST_QY = [
    0x79, 0x03, 0xFE, 0x10, 0x08, 0xB8, 0xBC, 0x99,
    0xA4, 0x1A, 0xE9, 0xE9, 0x56, 0x28, 0xBC, 0x64,
    0xF2, 0xF1, 0xB2, 0x0C, 0x2D, 0x7E, 0x9F, 0x51,
    0x77, 0xA3, 0xC2, 0x94, 0xD4, 0x46, 0x22, 0x99
];

def test_pubkey_known_answer() -> void
{
    byte[32] got_qx, got_qy;

    bool ok = ecdsa_p256_pubkey(@got_qx[0], @got_qy[0], @NIST_D[0]);
    if (!ok) { test_fail("pubkey_known_answer: returned false\0"); return; };

    if (!bytes_equal(@got_qx[0], @NIST_QX[0], 32))
    {
        test_fail("pubkey_known_answer: Qx mismatch\0");
        print("  expected: \0"); print_hex32(@NIST_QX[0]); print("\n\0");
        print("  got:      \0"); print_hex32(@got_qx[0]);  print("\n\0");
        return;
    };

    if (!bytes_equal(@got_qy[0], @NIST_QY[0], 32))
    {
        test_fail("pubkey_known_answer: Qy mismatch\0");
        print("  expected: \0"); print_hex32(@NIST_QY[0]); print("\n\0");
        print("  got:      \0"); print_hex32(@got_qy[0]);  print("\n\0");
        return;
    };

    test_pass("pubkey_known_answer\0");
    return;
};

// ---- Test 2: Sign then verify roundtrip ----

def test_sign_verify_roundtrip() -> void
{
    byte[32] hash, sig_r, sig_s, pubx, puby;
    bool ok;

    sha256_of("hello world\0", 11, @hash[0]);

    ok = ecdsa_p256_pubkey(@pubx[0], @puby[0], @TEST_PRIVKEY[0]);
    if (!ok) { test_fail("sign_verify_roundtrip: pubkey failed\0"); return; };

    ok = ecdsa_p256_sign(@sig_r[0], @sig_s[0], @TEST_PRIVKEY[0], @hash[0], @TEST_NONCE[0]);
    if (!ok) { test_fail("sign_verify_roundtrip: sign failed\0"); return; };

    ok = ecdsa_p256_verify(@sig_r[0], @sig_s[0], @pubx[0], @puby[0], @hash[0]);
    if (!ok)
    {
        test_fail("sign_verify_roundtrip: verify rejected valid signature\0");
        print("  r: \0"); print_hex32(@sig_r[0]); print("\n\0");
        print("  s: \0"); print_hex32(@sig_s[0]); print("\n\0");
        return;
    };

    test_pass("sign_verify_roundtrip\0");
    return;
};

// ---- Test 3: Verify rejects tampered hash ----

def test_verify_rejects_bad_hash() -> void
{
    byte[32] hash, bad_hash, sig_r, sig_s, pubx, puby;

    sha256_of("hello world\0",  11, @hash[0]);
    sha256_of("hello WORLD\0",  11, @bad_hash[0]);

    ecdsa_p256_pubkey(@pubx[0], @puby[0], @TEST_PRIVKEY[0]);
    ecdsa_p256_sign(@sig_r[0], @sig_s[0], @TEST_PRIVKEY[0], @hash[0], @TEST_NONCE[0]);

    bool ok = ecdsa_p256_verify(@sig_r[0], @sig_s[0], @pubx[0], @puby[0], @bad_hash[0]);
    if (ok) { test_fail("verify_rejects_bad_hash: accepted tampered hash\0"); return; };

    test_pass("verify_rejects_bad_hash\0");
    return;
};

// ---- Test 4: Verify rejects corrupted r ----

def test_verify_rejects_bad_sig() -> void
{
    byte[32] hash, sig_r, sig_s, pubx, puby;

    sha256_of("hello world\0", 11, @hash[0]);

    ecdsa_p256_pubkey(@pubx[0], @puby[0], @TEST_PRIVKEY[0]);
    ecdsa_p256_sign(@sig_r[0], @sig_s[0], @TEST_PRIVKEY[0], @hash[0], @TEST_NONCE[0]);

    sig_r[15] = sig_r[15] ^^ 0xFF;

    bool ok = ecdsa_p256_verify(@sig_r[0], @sig_s[0], @pubx[0], @puby[0], @hash[0]);
    if (ok) { test_fail("verify_rejects_bad_sig: accepted corrupted r\0"); return; };

    test_pass("verify_rejects_bad_sig\0");
    return;
};

// ---- Test 5: DER encode / decode roundtrip ----

def test_der_roundtrip() -> void
{
    byte[32] hash, sig_r, sig_s, dec_r, dec_s, pubx, puby;
    byte[72] der;
    int der_len;
    bool ok;

    sha256_of("der roundtrip test\0", 18, @hash[0]);

    ecdsa_p256_pubkey(@pubx[0], @puby[0], @TEST_PRIVKEY[0]);
    ecdsa_p256_sign(@sig_r[0], @sig_s[0], @TEST_PRIVKEY[0], @hash[0], @TEST_NONCE[0]);

    ecdsa_p256_encode_der(@der[0], @der_len, @sig_r[0], @sig_s[0]);

    ok = ecdsa_p256_decode_der(@dec_r[0], @dec_s[0], @der[0], der_len);
    if (!ok) { test_fail("der_roundtrip: decode returned false\0"); return; };

    if (!bytes_equal(@dec_r[0], @sig_r[0], 32))
    {
        test_fail("der_roundtrip: r mismatch after decode\0");
        print("  original: \0"); print_hex32(@sig_r[0]); print("\n\0");
        print("  decoded:  \0"); print_hex32(@dec_r[0]); print("\n\0");
        return;
    };

    if (!bytes_equal(@dec_s[0], @sig_s[0], 32))
    {
        test_fail("der_roundtrip: s mismatch after decode\0");
        print("  original: \0"); print_hex32(@sig_s[0]); print("\n\0");
        print("  decoded:  \0"); print_hex32(@dec_s[0]); print("\n\0");
        return;
    };

    print("  DER (\0"); print(der_len); print(" bytes): \0");
    print_hex(@der[0], der_len);
    print("\n\0");

    test_pass("der_roundtrip\0");
    return;
};

// ---- Test 6: bigint_modpow known-answer ----
// 2^10 mod 1000 = 24
// 3^100 mod 97  = 81  (3^96 = 1 by Fermat, so 3^100 = 3^4 = 81)

def test_bigint_modpow() -> void
{
    BigInt base, exp, m, result;
    uint* rd;

    math::bigint::bigint_from_uint(@base, 2);
    math::bigint::bigint_from_uint(@exp,  10);
    math::bigint::bigint_from_uint(@m,    1000);
    math::bigint::bigint_modpow(@result, @base, @exp, @m);

    rd = @result.digits[0];
    if (rd[0] != 24)
    {
        test_fail("bigint_modpow: 2^10 mod 1000 wrong\0");
        print("  expected 24, got \0"); print((uint)rd[0]); print("\n\0");
        return;
    };

    math::bigint::bigint_from_uint(@base, 3);
    math::bigint::bigint_from_uint(@exp,  100);
    math::bigint::bigint_from_uint(@m,    97);
    math::bigint::bigint_modpow(@result, @base, @exp, @m);

    rd = @result.digits[0];
    if (rd[0] != 81)
    {
        test_fail("bigint_modpow: 3^100 mod 97 wrong\0");
        print("  expected 81, got \0"); print((uint)rd[0]); print("\n\0");
        return;
    };

    test_pass("bigint_modpow\0");
    return;
};

// ---- Test 7: bigint_modinv known-answer + no-inverse detection ----
// 3^(-1) mod 7 = 5   (3*5 = 15 = 2*7 + 1)
// 6^(-1) mod 9 -> no inverse (gcd(6,9) = 3)

def test_bigint_modinv() -> void
{
    BigInt a, m, result;
    uint* rd;
    bool ok;

    math::bigint::bigint_from_uint(@a, 3);
    math::bigint::bigint_from_uint(@m, 7);
    ok = math::bigint::bigint_modinv(@result, @a, @m);

    if (!ok) { test_fail("bigint_modinv: 3^-1 mod 7 returned false\0"); return; };

    rd = @result.digits[0];
    if (rd[0] != 5)
    {
        test_fail("bigint_modinv: 3^-1 mod 7 wrong\0");
        print("  expected 5, got \0"); print((uint)rd[0]); print("\n\0");
        return;
    };

    math::bigint::bigint_from_uint(@a, 6);
    math::bigint::bigint_from_uint(@m, 9);
    ok = math::bigint::bigint_modinv(@result, @a, @m);

    if (ok) { test_fail("bigint_modinv: 6^-1 mod 9 should have no inverse\0"); return; };

    test_pass("bigint_modinv\0");
    return;
};

// ---- Diagnostic: test scalar mul with k=1 and k=2 ----
def test_scalar_mul_small() -> void
{
    byte[32] rx, ry;
    uint* gxd, gyd, pgx, pgy;
    uint i;
    BigInt k, bgx, bgy, brx, bry;

    gxd = @bgx.digits[0];
    gyd = @bgy.digits[0];
    pgx = @standard::crypto::ECDSA::P256_GX[0];
    pgy = @standard::crypto::ECDSA::P256_GY[0];
    for (i = 0; i < 8; i++) { gxd[i] = pgx[i]; };
    for (i = 0; i < 8; i++) { gyd[i] = pgy[i]; };
    bgx.length = 8; bgx.negative = false;
    bgy.length = 8; bgy.negative = false;
    math::bigint::bigint_normalize(@bgx);
    math::bigint::bigint_normalize(@bgy);

    math::bigint::bigint_one(@k);
    standard::crypto::ECDSA::ecdsa_p256_point_mul(@brx, @bry, @k, @bgx, @bgy);
    standard::crypto::ECDSA::ecdsa_p256_store_scalar(@rx[0], @brx);
    print("[DBG] k=1 rx: "); print_hex32(@rx[0]); print();

    math::bigint::bigint_from_uint(@k, 2);
    standard::crypto::ECDSA::ecdsa_p256_point_mul(@brx, @bry, @k, @bgx, @bgy);
    standard::crypto::ECDSA::ecdsa_p256_store_scalar(@rx[0], @brx);
    print("[DBG] k=2 rx: "); print_hex32(@rx[0]); print();
    print("[DBG] 2G   x: 7cf27b188d034f7e8a52380304b51ac3c74355b0a6b0c3b8716c895ccbd1b0e");

    return;
};

// ---- Entry point ----

def main() -> int
{
    print("=== ECDSA P-256 Test Suite ===\n\0");

    test_scalar_mul_small();
    test_pubkey_known_answer();
    test_sign_verify_roundtrip();
    test_verify_rejects_bad_hash();
    test_verify_rejects_bad_sig();
    test_der_roundtrip();
    test_bigint_modpow();
    test_bigint_modinv();

    print("=== Done ===\n\0");
    return 0;
};
