#import "standard.fx";

using standard::io::console;

contract NonZero
{
    assert(x > 0, "x must be positive");
};

contract rValGT5
{
    assert(x > 10, "r must be greater than 10");
};

def foo(int x) -> int : NonZero
{
    return x / 2;
} : rValGT5;

def main() -> int
{
    int y = foo(18);

    return 0;
};