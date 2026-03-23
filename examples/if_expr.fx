#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int x = 5;
    int y = x if (x == 5) else 2;
    if (y == x)
    {
        print("if expressions working!\n\0");
    };
    return 0;
};