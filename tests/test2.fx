#import "standard.fx";

using standard::io::console;

def main() -> int
{
	int x = 5;

	int* px = @x;

	print(*px);
	return 0;
};