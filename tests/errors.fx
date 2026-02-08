#import "standard.fx";


def foo() -> void {};

def main() -> int
{
	foo("TESTING");
	foo(3.3);
	foo(0);
	return 0;
};