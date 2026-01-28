#import "standard.fx";

def foo(byte x) -> byte
{
	return x;
};


def main() -> int
{
	byte a = (byte)0x0F;

	byte b = foo(a);

	if (b == (byte)0x0F)
	{
		print("Success!\n\0");
	}
	else
	{
		print("Failure!\n\0");
		return 1;
	};
	return 0;
};