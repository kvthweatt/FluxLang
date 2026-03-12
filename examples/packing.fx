#import "standard.fx";

using standard::io::console;

def main() -> int
{
    uint[1] a = [0xABCDu];          // 32 bits of zeros
    uint[2] b = [a[0], 0xEFABu];    // 31 zeros followed by 1

    u64 x = (u64)b;              // 32 zeros + 31 zeros + 1 = 64 bits
    print(x);
    print();

    uint a = 0x00003CF0u,
         b = 0xFAF00000u;

    u64 x = (u64)[a,b];

    print((u64)x);
    print();

    unsigned data{1} as bit;

    bit[32] bits1 = (bit[32])a,
            bits2 = (bit[32])b;

    if (bits1 == bits2) { print("FAULT\0"); return 1; };

    for (k in bits1)
    {
        print((uint)k);
    };
    print();
    for (k in bits2)
    {
        print((uint)k);
    };
    print();

    byte[8] z = (byte[8])x;
    print("Hello world!\n\0");

    for (b in z)
    {
        print(b + '\0');
    };
    print();
    for (b in z)
    {
        print("Char 1 as integer: \0");
        print((uint)b);
        print();
    };
	return 0;
};