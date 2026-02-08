#import "redtypes.fx";

def foo() -> void**
{
	byte* buffer;
	return buffer;
};

def main() -> int
{
    byte[] x;

    x = foo();
	return 0;
};

def !!FRTStartup() -> int {return main();};