#import "standard.fx";

unsigned data{7} as i7;
unsigned data{21} as i21;
unsigned data{1} as bit;
signed data{3} as i3;
i7 a = 4;
i7 b = 8;
i7 c = 16;
i21 test = [a, b, c];

bit a2, b2, c2 = 1, 0, 1;
i3 test2 = [a2, b2, c2];

def main() -> int
{
    print((u32)test2);
    print();

    print((i32)test);
    print();

    if (test == 0b10000010000010000)
    {
        print("Binary check success!\n\0");
    };
    if (test == 0o202020)
    {
        print("Octal check success!\n\0");
    };
    if (test == 66576)
    {
        print("Decimal check success!\n\0");
    };
    if (test == 0x10410)
    {
        print("Hexadecimal check success!\n\0");
    };
    if (test == 0d210G)
    {
        print("[2;32mDuotrigesimal check passed![0m\n\0");
    };
	return 0;
};