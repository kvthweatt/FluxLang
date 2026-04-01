#import "standard.fx";

using standard::io::console,
      standard::strings;

def foo() -> int
{
    return 5;
};

def main() -> int
{
    byte[4] a = [65, 66, 67, 68];

    println((byte[2])a[1..3]);

    return 0;
};