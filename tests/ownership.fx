#import "standard.fx";

def foo(~int z) -> void  // accepts a tied parameter
{
    return;
};

def bar(~int z) -> void
{
    return;
};

def main() -> int
{
    ~int x;
    int  y;  // Non-tied var

    foo(~x); // Untie from main, tie to foo()

    //bar(~x); // Use after untie

    foo(y);  // Compile error, foo expects tied param

	return 0;
};