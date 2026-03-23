#import "standard.fx";

using standard::io::console;

def main() -> int
{
    uint x = 10;
    uint y = 0;

    uint* px = @x;
    uint* py = @y;

	print(*px); print();
	return 0;
};