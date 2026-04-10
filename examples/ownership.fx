#import "standard.fx";

def foo(~int z) -> void  // accepts a tied type
{
    return;
};

def bar(~int y) -> ~int  // returns a tied type
{
    return ~y;
};

def main() -> int
{
    ~int x, y, z; // Tied vars
    int  w = 3;   // Non-tied var

    x = bar(~y);  // Compile error, function returns tied type to non-tied type

    z = ~w;

    w = 5; // Compile error, w invalidated previously

    return 0;
};