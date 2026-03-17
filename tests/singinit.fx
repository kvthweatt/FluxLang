#import "standard.fx";

using standard::io::console;

def foo() -> void
{
	singinit int x;
    x += 1;
    print(x); print();
};

def call(int y) -> void
{
    if (y == 0) { return; };
    foo();
    call(--y);
};

def main() -> int
{
    call(10);
	return 0;
};