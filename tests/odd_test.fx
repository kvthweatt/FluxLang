#import "standard.fx";

unsigned data{7} as i7;
unsigned data{21} as i21;
i7 a = 4;
i7 b = 8;
i7 c = 16;
i21 test = [a, b, c];

def main() -> int
{
    print((i32)test);
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