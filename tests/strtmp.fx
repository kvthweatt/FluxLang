#import "standard.fx";

using standard::io::console;

struct myStru<T>
{
	T a, b;
};

def foo<T, U>(T a, U b) -> U
{
    return a.a * b;
};

def bar(myStru<int> a, int b) -> int
{
    return foo(a, 3);
};

macro macNZ(x)
{
    x != 0
};

contract ctNonZero(a,b)
{
    assert(macNZ(a), "a must be nonzero");
    assert(macNZ(b), "b must be nonzero");
};

contract ctGreaterThanZero
{
    assert(x > 0, "a must be greater than zero");
    assert(y > 0, "b must be greater than zero");
};

operator<T, K>(T t, K k)[+] -> int : ctNonZero(a,b)
{
    return t + k;
} : ctGreaterThanZero;

def main() -> int
{
    myStru<int> ms = {10,20};

    int x = foo(ms, 3);

    i32 y = bar(ms, 3);

    println(x + y);

	return 0;
};