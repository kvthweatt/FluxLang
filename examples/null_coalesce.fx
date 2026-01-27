#import "standard.fx";

def main() -> int
{
	int x = 0;
	int y = 5;

	int z = y ?? 0;

	if (z is 5)
	{
		print("Success!\0");
	};
	return 0;
};