#import "standard.fx";

using standard::io::console,
      standard::strings;

def foo() -> void
{
    println("In foo()!");
};

def main() -> int
{
    long x = @foo;

    jump x;

    print("Test?");

    return 0;
};