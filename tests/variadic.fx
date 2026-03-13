#import "standard.fx";

using standard::io::console;

def variadic(...) -> void
{
	print(...[0]); print();
	print(...[1]); print();
	print(...[2]); print();
	print(...[3]); print();
};



def main() -> int
{
	variadic(1,2,3,4);

	return 0;
};