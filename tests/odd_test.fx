#import "standard.fx";

unsigned data{7} as i7;
unsigned data{21} as i21;
i7 a = 4;
i7 b = 8;
i7 c = 16;
i21[1] test1 = [[a, b, c]];
i21 test2 = test1[0];

def main() -> int
{
    noopstr x = f"{test2}\n\0";
    print(x);
    if (test1[0] == 0b000010000010000010000)
    {
        print("Binary check success!\n\0");
    };
    if (test1[0] == 0o202020)
    {
        print("Octal check success!\n\0");
    };
    if (test1[0] == 66576)
    {
        print("Decimal check success!\n\0");
    };
    if (test1[0] == 0x10410)
    {
        print("Hexadecimal check success!\n\0");
    };
    if (test1[0] == 0d210G)
    {
        print("[2;32mDuotrigesimal check passed![0m\n\0");
    };
	return 0;
};