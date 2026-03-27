// rle_test.fx - Tests for standard::rle

#import "standard.fx";
#import "random.fx";
#import "rle.fx";

using standard::io::console,
      standard::strings,
      standard::random,
      standard::rle;

def check(noopstr name, bool result) -> void
{
    if (result)
    {
        print("PASS: \0");
        println(name);
    }
    else
    {
        print("FAIL: \0");
        println(name);
    };
    return;
};

def main(int argc, byte** argv) -> int
{
    byte* enc, dec, bin_enc, bin_dec, capped_enc, null_enc, null_dec;
    int enc_size, dec_size;
    byte[6] bin_input;
    byte[260] long_run;
    int i;
    PCG32* rng;
    int buf_size, rt_enc_size, rt_dec_size, mismatch, j;
    byte* rt_buf, rt_enc, rt_dec;
    int run_buf_size, run_pos, run_len, run_val_i;
    byte run_val;
    byte* run_buf, run_enc, run_dec;
    int run_enc_size, run_dec_size, run_mismatch, k;

    // =====================================================================
    // encode_str / decode_str tests
    // =====================================================================

    enc = encode_str("AAABBC\0");
    check("encode_str basic\0", strcmp(enc, "3A2B1C\0") == 0);
    ffree(enc);

    enc = encode_str("ABC\0");
    check("encode_str no runs\0", strcmp(enc, "1A1B1C\0") == 0);
    ffree(enc);

    enc = encode_str("FFFFF\0");
    check("encode_str all same\0", strcmp(enc, "5F\0") == 0);
    ffree(enc);

    enc = encode_str("X\0");
    check("encode_str single char\0", strcmp(enc, "1X\0") == 0);
    ffree(enc);

    enc = encode_str("AABBBCCCC\0");
    dec = decode_str(enc);
    check("encode_str/decode_str round-trip\0", strcmp(dec, "AABBBCCCC\0") == 0);
    ffree(enc);
    ffree(dec);

    dec = decode_str("3A2B1C\0");
    check("decode_str basic\0", strcmp(dec, "AAABBC\0") == 0);
    ffree(dec);

    dec = decode_str("10A\0");
    check("decode_str multi-digit count\0", strcmp(dec, "AAAAAAAAAA\0") == 0);
    ffree(dec);

    // =====================================================================
    // Binary encode / decode tests
    // =====================================================================

    bin_input[0] = (byte)0xAA;
    bin_input[1] = (byte)0xAA;
    bin_input[2] = (byte)0xAA;
    bin_input[3] = (byte)0xBB;
    bin_input[4] = (byte)0xCC;
    bin_input[5] = (byte)0xCC;

    bin_enc = encode(bin_input, 6, @enc_size);
    check("encode binary size\0",     enc_size == 6);
    check("encode binary count[0]\0", (int)bin_enc[0] == 3);
    check("encode binary value[0]\0", bin_enc[1] == (byte)0xAA);
    check("encode binary count[1]\0", (int)bin_enc[2] == 1);
    check("encode binary value[1]\0", bin_enc[3] == (byte)0xBB);
    check("encode binary count[2]\0", (int)bin_enc[4] == 2);
    check("encode binary value[2]\0", bin_enc[5] == (byte)0xCC);

    bin_dec = decode(bin_enc, enc_size, @dec_size);
    check("decode binary size\0",    dec_size == 6);
    check("decode binary byte[0]\0", bin_dec[0] == (byte)0xAA);
    check("decode binary byte[1]\0", bin_dec[1] == (byte)0xAA);
    check("decode binary byte[2]\0", bin_dec[2] == (byte)0xAA);
    check("decode binary byte[3]\0", bin_dec[3] == (byte)0xBB);
    check("decode binary byte[4]\0", bin_dec[4] == (byte)0xCC);
    check("decode binary byte[5]\0", bin_dec[5] == (byte)0xCC);

    ffree(bin_enc);
    ffree(bin_dec);

    // Run cap at 255
    for (i = 0; i < 260; i = i + 1)
    {
        long_run[i] = (byte)0x41;
    };

    capped_enc = encode(long_run, 260, @enc_size);
    check("encode run cap size\0",     enc_size == 4);
    check("encode run cap count[0]\0", ((int)capped_enc[0] & 0xFF) == 255);
    check("encode run cap count[1]\0", ((int)capped_enc[2] & 0xFF) == 5);
    ffree(capped_enc);

    // Empty string guards
    null_enc = encode_str("\0");
    check("encode_str empty string\0", null_enc != 0 & null_enc[0] == (byte)0);
    ffree(null_enc);

    null_dec = decode_str("\0");
    check("decode_str empty string\0", null_dec != 0 & null_dec[0] == (byte)0);
    ffree(null_dec);

    // =====================================================================
    // Round-trip fuzz: random high-entropy data (few natural runs)
    // =====================================================================

    rng = (PCG32*)fmalloc((u64)sizeof(PCG32) / 8);
    pcg32_init(rng);
    buf_size = 1024;
    rt_buf = (byte*)fmalloc((u64)buf_size);
    random_bytes(rng, rt_buf, (u64)buf_size);

    rt_enc = encode(rt_buf, buf_size, @rt_enc_size);
    rt_dec = decode(rt_enc, rt_enc_size, @rt_dec_size);

    check("round-trip size match (random)\0", rt_dec_size == buf_size);

    mismatch = 0;
    for (j = 0; j < buf_size; j = j + 1)
    {
        if (rt_dec[j] != rt_buf[j])
        {
            mismatch = 1;
        };
    };
    check("round-trip byte match (random)\0", mismatch == 0);

    ffree(rt_buf);
    ffree(rt_enc);
    ffree(rt_dec);

    // =====================================================================
    // Round-trip fuzz: random run-length data (many natural runs)
    // =====================================================================

    run_buf_size = 1024;
    run_buf = (byte*)fmalloc((u64)run_buf_size);

    // Fill with a simple repeating pattern of runs instead of random
    for (k = 0; k < run_buf_size; k = k + 1)
    {
        run_buf[k] = (byte)(k / 16); // 16-byte runs of each value
    };

    run_enc = encode(run_buf, run_buf_size, @run_enc_size);
    run_dec = decode(run_enc, run_enc_size, @run_dec_size);

    check("round-trip size match (run data)\0", run_dec_size == run_buf_size);

    run_mismatch = 0;
    for (k = 0; k < run_buf_size; k = k + 1)
    {
        if (run_dec[k] != run_buf[k])
        {
            run_mismatch = 1;
        };
    };
    check("round-trip byte match (run data)\0", run_mismatch == 0);

    ffree(long(run_buf));
    ffree(long(run_enc));
    ffree(long(run_dec));

    ffree(long(rng));
    return 0;
};
