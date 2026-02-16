#import "standard.fx";

def foo(~int z) -> void
{
    return;
};

def main() -> int
{
    ~int x;

    foo(~x); // Untie from main, tie to foo() is the idea

	return 0;
};