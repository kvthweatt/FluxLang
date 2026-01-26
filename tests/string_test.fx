#import "standard.fx";

def main() -> int
{
	noopstr x = "Test";
	noopstr y = "ing";
	noopstr z = x + y + " strings!\0";

	print(z);
	return 0;
};