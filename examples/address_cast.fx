#import "standard.fx";

def main() -> int
{
	int a = 5;         // Initialize a

	int* pa = @a;      // Point to a

	int x = (int)pa;   // Take pointer as integer

	int* pb = (@)x;    // Cast integer to new pointer

	if (*pb == 5)      // Dereference new pointer
	{
		print("Success!\0");
	};
	return 0;
};