#import "standard.fx";

def bar(~int y) -> ~int  // returns a tied type
{
    return ~y;
};

def main() -> int
{
    ~int x, y, z; // Tied vars
    int  w = 5;       // Non-tied var

    x = bar(~y);  // Copmile error, function returns tied type to non-tied type

    z = ~w;   // Illegal but currently valid line

    int w = 10;

    return 0;
};