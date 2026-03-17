#import "standard.fx";

using standard::io::console;

def foo() -> void
{
	singinit int x;
    x += 1;
    print(x); print();
};

def main() -> int
{
    foo();
    foo();
    foo();
	return 0;
};