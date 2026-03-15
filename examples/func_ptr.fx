#import "standard.fx";

using standard::io::console;

def foo(int x) -> int
{
	print("Inside foo!\n\0");
	return 0;	
};


def main() -> int
{
	def{}* pfoo(int)->int = @foo;
    print("Function pointer created.\n\0");
    print((ulong)pfoo);
    print();

    pfoo(0);

	return 0;
};