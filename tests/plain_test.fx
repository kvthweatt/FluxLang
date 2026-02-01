#import "standard.fx";

struct mystru
{
    int a, b, c = 10, 20, 30;
};

def main() -> int
{
	int x, y = 1, 2;

	if (x == 0)
	{
		print("0\n\0");
	}
	else if (y == 2)
	{
		print("2\n\0");
	};
	return 0;
};