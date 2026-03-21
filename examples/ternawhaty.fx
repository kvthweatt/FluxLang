#import "standard.fx";

using standard::io::console;

def main() -> int
{
	int a = 50, b = 25, x, y, z;

	x ?= y ?? z ? a : b;

	print(x); print();
	return 0;
};