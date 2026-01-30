#import "standard.fx";

def main() -> int
{
	int x = 5;
	noopstr s = f"Testing fstring with {x}!\n\0";

	print(s);
	return 0;
};