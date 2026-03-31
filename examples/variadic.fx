#import "standard.fx";

using standard::io::console;

def variadic(int x, ...) -> void
{
	print(double(x)); print();
	print(...[0]); print();
	print(...[1]); print();
	print(...[2]); print();
};



def main() -> int
{
	variadic(1,2,3,4);

	return 0;
};