#import "standard.fx";


def main() -> int
{
	int x = 5;

	int* px = @x;

	print(*px);
	return 0;
};