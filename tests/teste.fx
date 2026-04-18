#import "standard.fx";

using standard::io::console;

enum testEnum
{
    A,
    B,
    C,
    D,
    E
};

def main() -> int
{
    testEnum e;

    e = testEnum.B;

    println(e);

    return 0;
};