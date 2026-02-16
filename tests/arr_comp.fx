#import "standard.fx";

def main() -> int
{
    int a = 1, b = 10;
	int[10] x = [y for (int y in a..b)];

    print(x[4]);

	return 0;
};