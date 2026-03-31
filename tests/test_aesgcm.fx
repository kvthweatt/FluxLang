// Author: Karac V. Thweatt
// test_aesgcm.fx - AES-128-GCM Test Suite
//
// Test vectors sourced from NIST SP 800-38D Appendix B.
// Each test case checks:
//   1. Encryption output (ciphertext) matches expected
//   2. Authentication tag matches expected
//   3. Decryption recovers the original plaintext
//   4. Tag verification returns 1 on valid data
//   5. Tag verification returns 0 when tag is tampered

#import "standard.fx";
#import "cryptography.fx";

using standard::io::console;
using standard::crypto::encryption::AES;

// Compare two byte buffers, return 1 if equal, 0 if not
def bytes_equal(byte* a, byte* b, int len) -> int
{
    int i, diff;
    for (i = 0; i < len; i++)
    {
        diff = diff | ((int)(a[i] ^^ b[i]));
    };
    return (diff == 0) ? 1 : 0;
};

// Run one encrypt+decrypt test case.
// Returns number of failures (0 = pass).
def run_test(int test_num,
             byte* key,
             byte* iv,
             byte* aad,     int aad_len,
             byte* plain,   int plain_len,
             byte* exp_ct,
             byte* exp_tag) -> int
{
    GCM_CTX ctx;
    byte[256] cipher, recovered;
    byte[16] tag;
    byte[16] bad_tag;
    int ok_ct, ok_tag, ok_pt, ok_tamper, ok_verify, fails, result, i;

    print("--- Test \0");
    print(test_num);
    print(" ---\n\0");

    gcm_init(@ctx, key);

    // Encrypt
    gcm_encrypt(@ctx, iv,
                aad, aad_len,
                plain, plain_len,
                @cipher[0], @tag[0]);

    // Check ciphertext
    ok_ct = (plain_len == 0) ? 1 : bytes_equal(@cipher[0], exp_ct, plain_len);
    print("  ciphertext : \0");
    if (ok_ct != 0) { print("PASS\0"); } else { print("FAIL\0"); };
    print("\n\0");
    if (plain_len > 0)
    {
        print("    got      : \0"); print_hex(@cipher[0], plain_len); print("\n\0");
        print("    expected : \0"); print_hex(exp_ct,     plain_len); print("\n\0");
    };

    // Check tag
    ok_tag = bytes_equal(@tag[0], exp_tag, 16);
    print("  tag        : \0");
    if (ok_tag != 0) { print("PASS\0"); } else { print("FAIL\0"); };
    print("\n\0");
    print("    got      : \0"); print_hex(@tag[0],  16); print("\n\0");
    print("    expected : \0"); print_hex(exp_tag,  16); print("\n\0");

    // Decrypt with correct tag — must recover plaintext and return 1
    ok_verify = gcm_decrypt(@ctx, iv,
                            aad, aad_len,
                            @cipher[0], plain_len,
                            @recovered[0], @tag[0]);
    ok_pt = (plain_len == 0) ? 1 : bytes_equal(@recovered[0], plain, plain_len);
    print("  decrypt ok : \0");
    if ((ok_verify != 0) & (ok_pt != 0)) { print("PASS\0"); } else { print("FAIL\0"); };
    print("\n\0");

    // Tamper: flip one bit in the tag, verify returns 0
    for (i = 0; i < 16; i++) { bad_tag[i] = tag[i]; };
    bad_tag[0] = bad_tag[0] ^^ (byte)0x01;
    result = gcm_decrypt(@ctx, iv,
                         aad, aad_len,
                         @cipher[0], plain_len,
                         @recovered[0], @bad_tag[0]);
    ok_tamper = (result == 0) ? 1 : 0;
    print("  tamper rej : \0");
    if (ok_tamper != 0) { print("PASS\0"); } else { print("FAIL\0"); };
    print("\n\0");

    fails = 0;
    if (ok_ct    == 0) { fails = fails + 1; };
    if (ok_tag   == 0) { fails = fails + 1; };
    if (ok_verify == 0) { fails = fails + 1; };
    if (ok_pt    == 0) { fails = fails + 1; };
    if (ok_tamper == 0) { fails = fails + 1; };

    return fails;
};

def main() -> int
{
    int total_fails, f;

    print("=== AES-128-GCM Test Suite (NIST SP 800-38D) ===\n\n\0");

    // -----------------------------------------------------------------------
    // Test Case 1 (NIST GCM Test Case 1)
    // Key  : 00000000000000000000000000000000
    // IV   : 000000000000000000000000
    // Plain: (empty)
    // AAD  : (empty)
    // CT   : (empty)
    // Tag  : 58E2FCCEFA7E3061367F1D57A4E7455A
    // -----------------------------------------------------------------------
    {
        byte[16] key1 = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ];
        byte[12] iv1 = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ];
        byte[16] exp_tag1 = [
            0x58, 0xE2, 0xFC, 0xCE, 0xFA, 0x7E, 0x30, 0x61,
            0x36, 0x7F, 0x1D, 0x57, 0xA4, 0xE7, 0x45, 0x5A
        ];
        f = run_test(1, @key1[0], @iv1[0],
                     (byte*)0, 0,
                     (byte*)0, 0,
                     (byte*)0, @exp_tag1[0]);
        total_fails = total_fails + f;
    };

    // -----------------------------------------------------------------------
    // Test Case 2 (NIST GCM Test Case 2)
    // Key  : 00000000000000000000000000000000
    // IV   : 000000000000000000000000
    // Plain: 00000000000000000000000000000000
    // AAD  : (empty)
    // CT   : 0388DACE60B6A392F328C2B971B2FE78
    // Tag  : AB6E47D42CEC13BDF53A67B21257BDDF
    // -----------------------------------------------------------------------
    {
        byte[16] key2 = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ];
        byte[12] iv2 = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ];
        byte[16] plain2 = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ];
        byte[16] exp_ct2 = [
            0x03, 0x88, 0xDA, 0xCE, 0x60, 0xB6, 0xA3, 0x92,
            0xF3, 0x28, 0xC2, 0xB9, 0x71, 0xB2, 0xFE, 0x78
        ];
        byte[16] exp_tag2 = [
            0xAB, 0x6E, 0x47, 0xD4, 0x2C, 0xEC, 0x13, 0xBD,
            0xF5, 0x3A, 0x67, 0xB2, 0x12, 0x57, 0xBD, 0xDF
        ];
        f = run_test(2, @key2[0], @iv2[0],
                     (byte*)0, 0,
                     @plain2[0], 16,
                     @exp_ct2[0], @exp_tag2[0]);
        total_fails = total_fails + f;
    };

    // -----------------------------------------------------------------------
    // Test Case 3 (NIST GCM Test Case 3)
    // Key  : FEFFE9928665731C6D6A8F9467308308
    // IV   : CAFEBABEFACEDBADDECAF888
    // Plain: D9313225F88406E5A55909C5AFF5269A
    //        86A7A9531534F7DA2E4C303D8A318A72
    //        1C3C0C95956809532FCF0E2449A6B525
    //        B16AEDF5AA0DE657BA637B391AAFD255
    // AAD  : (empty)
    // CT   : 42831EC2217774244B7221B784D0D49C
    //        E3AA212F2C02A4E035C17E2329ACA12E
    //        21D514B25466931C7D8F6A5AAC84AA05
    //        1BA30B396A0AAC973D58E091473F5985
    // Tag  : 4D5C2AF327CD64A62CF35ABD2BA6FAB4
    // -----------------------------------------------------------------------
    {
        byte[16] key3 = [
            0xFE, 0xFF, 0xE9, 0x92, 0x86, 0x65, 0x73, 0x1C,
            0x6D, 0x6A, 0x8F, 0x94, 0x67, 0x30, 0x83, 0x08
        ];
        byte[12] iv3 = [
            0xCA, 0xFE, 0xBA, 0xBE, 0xFA, 0xCE,
            0xDB, 0xAD, 0xDE, 0xCA, 0xF8, 0x88
        ];
        byte[64] plain3 = [
            0xD9, 0x31, 0x32, 0x25, 0xF8, 0x84, 0x06, 0xE5,
            0xA5, 0x59, 0x09, 0xC5, 0xAF, 0xF5, 0x26, 0x9A,
            0x86, 0xA7, 0xA9, 0x53, 0x15, 0x34, 0xF7, 0xDA,
            0x2E, 0x4C, 0x30, 0x3D, 0x8A, 0x31, 0x8A, 0x72,
            0x1C, 0x3C, 0x0C, 0x95, 0x95, 0x68, 0x09, 0x53,
            0x2F, 0xCF, 0x0E, 0x24, 0x49, 0xA6, 0xB5, 0x25,
            0xB1, 0x6A, 0xED, 0xF5, 0xAA, 0x0D, 0xE6, 0x57,
            0xBA, 0x63, 0x7B, 0x39, 0x1A, 0xAF, 0xD2, 0x55
        ];
        byte[64] exp_ct3 = [
            0x42, 0x83, 0x1E, 0xC2, 0x21, 0x77, 0x74, 0x24,
            0x4B, 0x72, 0x21, 0xB7, 0x84, 0xD0, 0xD4, 0x9C,
            0xE3, 0xAA, 0x21, 0x2F, 0x2C, 0x02, 0xA4, 0xE0,
            0x35, 0xC1, 0x7E, 0x23, 0x29, 0xAC, 0xA1, 0x2E,
            0x21, 0xD5, 0x14, 0xB2, 0x54, 0x66, 0x93, 0x1C,
            0x7D, 0x8F, 0x6A, 0x5A, 0xAC, 0x84, 0xAA, 0x05,
            0x1B, 0xA3, 0x0B, 0x39, 0x6A, 0x0A, 0xAC, 0x97,
            0x3D, 0x58, 0xE0, 0x91, 0x47, 0x3F, 0x59, 0x85
        ];
        byte[16] exp_tag3 = [
            0x4D, 0x5C, 0x2A, 0xF3, 0x27, 0xCD, 0x64, 0xA6,
            0x2C, 0xF3, 0x5A, 0xBD, 0x2B, 0xA6, 0xFA, 0xB4
        ];
        f = run_test(3, @key3[0], @iv3[0],
                     (byte*)0, 0,
                     @plain3[0], 64,
                     @exp_ct3[0], @exp_tag3[0]);
        total_fails = total_fails + f;
    };

    // -----------------------------------------------------------------------
    // Test Case 4 (NIST GCM Test Case 4)
    // Key  : FEFFE9928665731C6D6A8F9467308308
    // IV   : CAFEBABEFACEDBADDECAF888
    // Plain: D9313225F88406E5A55909C5AFF5269A
    //        86A7A9531534F7DA2E4C303D8A318A72
    //        1C3C0C95956809532FCF0E2449A6B525
    //        B16AEDF5AA0DE657BA637B391AAFD255  (same 60 bytes -- last 4 moved to AAD)
    // AAD  : FEEDFACEDEADBEEFFEEDFACEDEADBEEF
    //        ABADDAD2
    // CT   : 42831EC2217774244B7221B784D0D49C
    //        E3AA212F2C02A4E035C17E2329ACA12E
    //        21D514B25466931C7D8F6A5AAC84AA05
    //        1BA30B396A0AAC973D58E091
    // Tag  : 5BC94FBC3221A5DB94FAE95AE7121A47
    // -----------------------------------------------------------------------
    {
        byte[16] key4 = [
            0xFE, 0xFF, 0xE9, 0x92, 0x86, 0x65, 0x73, 0x1C,
            0x6D, 0x6A, 0x8F, 0x94, 0x67, 0x30, 0x83, 0x08
        ];
        byte[12] iv4 = [
            0xCA, 0xFE, 0xBA, 0xBE, 0xFA, 0xCE,
            0xDB, 0xAD, 0xDE, 0xCA, 0xF8, 0x88
        ];
        byte[60] plain4 = [
            0xD9, 0x31, 0x32, 0x25, 0xF8, 0x84, 0x06, 0xE5,
            0xA5, 0x59, 0x09, 0xC5, 0xAF, 0xF5, 0x26, 0x9A,
            0x86, 0xA7, 0xA9, 0x53, 0x15, 0x34, 0xF7, 0xDA,
            0x2E, 0x4C, 0x30, 0x3D, 0x8A, 0x31, 0x8A, 0x72,
            0x1C, 0x3C, 0x0C, 0x95, 0x95, 0x68, 0x09, 0x53,
            0x2F, 0xCF, 0x0E, 0x24, 0x49, 0xA6, 0xB5, 0x25,
            0xB1, 0x6A, 0xED, 0xF5, 0xAA, 0x0D, 0xE6, 0x57,
            0xBA, 0x63, 0x7B, 0x39
        ];
        byte[20] aad4 = [
            0xFE, 0xED, 0xFA, 0xCE, 0xDE, 0xAD, 0xBE, 0xEF,
            0xFE, 0xED, 0xFA, 0xCE, 0xDE, 0xAD, 0xBE, 0xEF,
            0xAB, 0xAD, 0xDA, 0xD2
        ];
        byte[60] exp_ct4 = [
            0x42, 0x83, 0x1E, 0xC2, 0x21, 0x77, 0x74, 0x24,
            0x4B, 0x72, 0x21, 0xB7, 0x84, 0xD0, 0xD4, 0x9C,
            0xE3, 0xAA, 0x21, 0x2F, 0x2C, 0x02, 0xA4, 0xE0,
            0x35, 0xC1, 0x7E, 0x23, 0x29, 0xAC, 0xA1, 0x2E,
            0x21, 0xD5, 0x14, 0xB2, 0x54, 0x66, 0x93, 0x1C,
            0x7D, 0x8F, 0x6A, 0x5A, 0xAC, 0x84, 0xAA, 0x05,
            0x1B, 0xA3, 0x0B, 0x39, 0x6A, 0x0A, 0xAC, 0x97,
            0x3D, 0x58, 0xE0, 0x91
        ];
        byte[16] exp_tag4 = [
            0x5B, 0xC9, 0x4F, 0xBC, 0x32, 0x21, 0xA5, 0xDB,
            0x94, 0xFA, 0xE9, 0x5A, 0xE7, 0x12, 0x1A, 0x47
        ];
        f = run_test(4, @key4[0], @iv4[0],
                     @aad4[0], 20,
                     @plain4[0], 60,
                     @exp_ct4[0], @exp_tag4[0]);
        total_fails = total_fails + f;
    };

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    print("\n=== Results ===\n\0");
    if (total_fails == 0)
    {
        print("All tests PASSED.\n\0");
    }
    else
    {
        print("FAILED: \0");
        print(total_fails);
        print(" assertion(s) failed.\n\0");
    };

    return total_fails;
};
