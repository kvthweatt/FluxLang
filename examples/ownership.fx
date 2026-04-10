#import "standard.fx";

def foo(~int z) -> void  // accepts a tied type
{
    return;
};

def bar(~int y) -> ~int  // returns a tied type
{
    return ~y;
};

def main() -> int
{
    ~int x, y; // Tied vars
    int  z;    // Non-tied var

    foo(~x);   // Untie from main, tie to foo()

    //bar(~x); // Use after untie

    //foo(y);  // Compile error, foo expects tied param

    z = bar(~y);

	return 0;
};