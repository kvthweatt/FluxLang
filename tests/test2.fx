#import "standard.fx";

using standard::io::console;

def main() -> int
{
	byte x = 55;

	x[0``7] = x[7``0];

	println(int(x));

	return 0;
};