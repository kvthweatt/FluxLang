#import "standard.fx";

// Custom operator +++
operator (int L, int R) [+++] -> int
{
    return ++L + ++R;
};

// Overload a built in operator
operator (int L, i16* R) [+] -> int
{
    i32 t = [R[0], R[1]];
    return L + t;
};


def main() -> int
{
    int    x = 12;
    i16[2] y = [0,55];
    int    z = x + y;
    print(z); print(); // 67
    print(5 +++ 3);    // 10
    return 0;
};