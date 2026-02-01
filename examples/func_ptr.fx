#import "standard.fx";

def foo(int x) -> int
{
	print("Inside foo!\n\0");
	return 0;	
};


def main() -> int
{
	def{}* pfoo(int)->int = @foo;
    print("Function pointer created.\n\0");
    print((u32)pfoo);
    print();

    pfoo(0);

	return 0;
};