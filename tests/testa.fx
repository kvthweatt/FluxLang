#import "standard.fx";

using standard::io::console;

struct xx { int a, b; };

def main() -> int
{
    data{4} as u4;
    xx yy = {5,10};
    u4 a = yy[59``63]; // 10 because 0b1010

    print((int)a);

    return 0;
};