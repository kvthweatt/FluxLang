#import "standard.fx";


operator (int L, int R) [GT] -> bool
{
    return L > R;
};


def main() -> int
{
    print(5 GT 3);
    return 0;
};