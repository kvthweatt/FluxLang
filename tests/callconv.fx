#import <standard.fx>;

using standard::io::console;

fastcall foo() -> void
{
    print("TESTING!\0");
	return;
};

def main() -> int
{
    foo();
	return 0;
};