#import "standard.fx";

def main() -> int
{
    uint[1] a = [0u];            // 32 bits of zeros
    uint[2] b = [a[0]] + [1u];   // 31 zeros followed by 1

    u64 x = (u64)b;              // 32 zeros + 31 zeros + 1 = 64 bits
    print(x);
    print();
	return 0;
};