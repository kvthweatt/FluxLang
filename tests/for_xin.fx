#import "standard.fx";

def main() -> int
{
    int a = 1, b = 10;
	int[10] y = [z for (int z in a..b)];

	for (x in y)
	{
		print(x);
		print();
	};

	return 0;
};