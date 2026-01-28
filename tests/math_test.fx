#import "standard.fx";

#import "redmath.fx";

def main() -> int
{
    i32 r = reverse_bits(1);
    i32 p = popcount(67);
    i32 l = log(100.0);
    i32 f = factorial(5);
    i32 k = sqrt(64);
    i32 x;
    i32 y;
    i32 z;
    x = 0;
    y = 100;
    z = max(x,y);
    if (r == 0b10000000000000000000000000000000)
    {
        print("32-bit reverse_bits() success!\n\0");
    };
    if (p == 3)
    {
        print("32-bit popcount() success!\n\0");
    };
    if (l == 3)
    {
        print("32-bit log() success!\n\0");
    };
    if (f == 120)
    {
        print("32-bit factorial() success!\n\0");
    };
    if (k == 8)
    {
        print("32-bit sqrt() success!\n\0");
    };
    if (z == 100)
    {
        print("32-bit max() success!\n\0");
    };

	return 0;
};