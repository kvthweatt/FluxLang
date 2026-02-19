#import "standard.fx";

def foo(int z) -> int
{
	return z;
};

def main() -> int
{
	local int y = 5;
	foo(y); // Illegal, compile error
	return 0;
};