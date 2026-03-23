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
    print("Address of function pointer: 0x\0"); print_hex((ulong)@pfoo);
    print();

    long addr = @foo;
    print("0x\0"); print_hex(addr); print();

    pfoo(0);

	return 0;
};