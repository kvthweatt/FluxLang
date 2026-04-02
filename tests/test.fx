#import "standard.fx";

using standard::io::console,
      standard::strings;

def foo() -> int
{
    return 5;
};

def main() -> int
{
    println("Test!");
    jump @main;

    return 0;
};