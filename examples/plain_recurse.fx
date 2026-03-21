#import "standard.fx";

using standard::io::console;

def recurse(int x) -> int
{
	return recurse(++x);
};


def main() -> int
{
	recurse();
	return 0;
};