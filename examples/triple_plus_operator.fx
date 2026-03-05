#import "standard.fx";


operator (int L, int R) [+++] -> int
{
    return (++L + ++R);
};


def main() -> int
{
    print(5 +++ 3);
    return 0;
};