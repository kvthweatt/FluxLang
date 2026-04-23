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

def main() -> int
{
    myStru<int> ms = {10,20};

    //int x = foo<myStru<int>, int>(ms, 3);

    //int x = foo(ms, 3);

    int x = bar(ms, 3);

    println(x);
	return 0;
};