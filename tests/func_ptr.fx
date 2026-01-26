#import "standard.fx";

def foo() -> void
{
    print("Hello World!\0");
	return void;
};

def main() -> int
{
    void{}* x() = @foo;
    x();
	return 0;
};