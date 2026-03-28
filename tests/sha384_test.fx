// Author: Karac V. Thweatt
// sha384_test.fx

#import "standard.fx", "cryptography.fx", "datautils.fx";

using standard::io::console,
      standard::crypto::hashing::SHA384;

def main() -> int
{
    // SHA-384("abc") = CB00753F45A35E8BB5A03D699AC65007272C32AB0EDED1631A8B605A43FF5BED8086072BA1E7CC2358BAECA134C825A7
    byte[3] msg;
    byte[48] hash, exp;
    SHA384_CTX ctx;
    int i;
    byte hi, lo;

    msg[0] = (byte)'a'; msg[1] = (byte)'b'; msg[2] = (byte)'c';

    exp[0]=(byte)0xCB; exp[1]=(byte)0x00; exp[2]=(byte)0x75; exp[3]=(byte)0x3F;
    exp[4]=(byte)0x45; exp[5]=(byte)0xA3; exp[6]=(byte)0x5E; exp[7]=(byte)0x8B;
    exp[8]=(byte)0xB5; exp[9]=(byte)0xA0; exp[10]=(byte)0x3D; exp[11]=(byte)0x69;
    exp[12]=(byte)0x9A; exp[13]=(byte)0xC6; exp[14]=(byte)0x50; exp[15]=(byte)0x07;
    exp[16]=(byte)0x27; exp[17]=(byte)0x2C; exp[18]=(byte)0x32; exp[19]=(byte)0xAB;
    exp[20]=(byte)0x0E; exp[21]=(byte)0xDE; exp[22]=(byte)0xD1; exp[23]=(byte)0x63;
    exp[24]=(byte)0x1A; exp[25]=(byte)0x8B; exp[26]=(byte)0x60; exp[27]=(byte)0x5A;
    exp[28]=(byte)0x43; exp[29]=(byte)0xFF; exp[30]=(byte)0x5B; exp[31]=(byte)0xED;
    exp[32]=(byte)0x80; exp[33]=(byte)0x86; exp[34]=(byte)0x07; exp[35]=(byte)0x2B;
    exp[36]=(byte)0xA1; exp[37]=(byte)0xE7; exp[38]=(byte)0xCC; exp[39]=(byte)0x23;
    exp[40]=(byte)0x58; exp[41]=(byte)0xBA; exp[42]=(byte)0xEC; exp[43]=(byte)0xA1;
    exp[44]=(byte)0x34; exp[45]=(byte)0xC8; exp[46]=(byte)0x25; exp[47]=(byte)0xA7;

    sha384_init(@ctx);
    sha384_update(@ctx, @msg[0], (u64)3);
    sha384_final(@ctx, @hash[0]);

    print("GOT: \0");
    for (i = 0; i < 48; i++)
    {
        hi = (hash[i] >> 4) & (byte)0x0F;
        lo = hash[i] & (byte)0x0F;
        if (hi < (byte)10) { print('0' + hi); } else { print('A' + (hi - (byte)10)); };
        if (lo < (byte)10) { print('0' + lo); } else { print('A' + (lo - (byte)10)); };
    };
    print("\n\0");

    int ok = 1;
    for (i = 0; i < 48; i++) { if (hash[i] != exp[i]) { ok = 0; }; };
    print(ok ? "[PASS]\n\0" : "[FAIL]\n\0");
    return ok ? 0 : 1;
};
