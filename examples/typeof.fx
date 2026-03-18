#import "standard.fx";

using standard::io::console;

struct mystr
{
};

def main() -> int
{
	if (typeof(mystr) == struct)
	{
		print("Got struct!\0");
	};
	return 0;
};