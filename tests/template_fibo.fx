#import "redstandard.fx";
#import "redformat.fx";
#import "redmath.fx";

def fibonacci<T>(T n) -> T
{
    if (n <= (T)1)
    {
        return n;
    };
    
    T a = (T)0;
    T b = (T)1;
    T i = (T)2;
    
    while (i <= n)
    {
        T temp = a + b;
        a = b;
        b = temp;
        i = i + (T)1;
    };
    
    return b;
};

def main() -> int
{
    println_colored("Fibonacci Calculator", standard::format::colors::YELLOW);
    hline_heavy(30);
    u64 x;
    
    for (u64 i = 0; i <= 100; i++)
    {
        print_cyan("fib(\0");
        print(i);
        print_cyan(") = \0");
        x = fibonacci<u64>(i); // Not working with custom identifiers
        print(x);
        print("\n\0");
    };
    
    return 0;
};