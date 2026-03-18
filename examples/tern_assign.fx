#import "standard.fx";

using standard::io::console;

def main() -> int
{
	int x = 10,
        y;

	x ?= 50;
    y ?= x;

	if (x == y) { print("Success!\n\0"); };

	return 0;
};