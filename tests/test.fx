#import "standard.fx";

using standard::io::console,
      standard::strings;

def foo() -> int
{
    return 5;
};

def main() -> int
{
    int x = 5,
        y = 2;

    string a("Test!");

    noopstr z = "STRING???";

    noopstr s = f"{x} is a double.";

    noopstr o = i"Test {} {} istring {}": {x + foo(); y; z;};

    println(o);

    return 0;
};