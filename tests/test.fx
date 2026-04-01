#import "standard.fx";

using standard::io::console,
      standard::strings;

def foo() -> int
{
    return 5;
};

def main() -> int
{
    int a = 1;
    assert(a != 1, "TEST!\0");

    return 0;
};