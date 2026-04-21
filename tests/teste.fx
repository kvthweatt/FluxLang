#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int x = 5;
    int* px = @x;

    println("px is valid") if (px);

    return 0;
};