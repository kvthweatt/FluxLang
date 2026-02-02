#import "standard.fx";

def main() -> int
{
    string s("Hello!\0");

    print(s.val());
    print();

    uint[1] a = [0];
    uint[2] b = [a[0]] + [1u];

    u64 x = (u64)b;
    print(x);
	return 0;
};