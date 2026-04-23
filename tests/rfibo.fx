#import "standard.fx";

using standard::io::console;

def fib_helper(int n, int a, int b) <~ int
{
    if (n == 0) { escape a; };
    escape fib_helper(n - 1, b, a + b);
};

def fib(int n) -> int
{
    return fib_helper(n, 0, 1);
};

def main() -> int
{
    for (int i = 0; i <= 10; i++)
    {
        println(f"fib({i}) = {fib(i)}\0");
    };
    return 0;
};