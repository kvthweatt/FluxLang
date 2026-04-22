#import "standard.fx";

using standard::io::console;

contract LessThan(a, b)
{
    assert(a < b, "a must be less than b");
};

contract NonZero(a,b)
{
    assert(a != 0, "a must be nonzero");
    assert(b != 0, "b must be nonzero");
};

def addi(int x, int y) -> int : LessThan(a,b)
{
    return x + y;
};

operator(int x, i32 y)[+] -> int : NonZero(a,b)
{
    return x+y;
};


def main() -> int
{
    //int c = addi(5,2);

    //println(c);

    0 + 4;

    return 0;
};