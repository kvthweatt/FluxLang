#import "standard.fx";
#import "testpack.fx";

using standard::io::console;

def main() -> int
{
    byte* p = "x";
	if (p)
	{
		print("x");
	};

	return 0;
};