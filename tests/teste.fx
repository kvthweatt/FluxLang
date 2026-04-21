#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int x = 5;
    int* px = (int*)0;

    println("Test") if (px);

    return 0;
};