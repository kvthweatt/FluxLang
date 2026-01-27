#import "standard.fx";

def foo(int x) -> int
{
	return x - 1;
};

def bar() -> int
{
	return 1;
};

def main() -> int
{
	if ((foo()<-bar()) == 0)
	{
		print("Success!\0");
	};
	return 0;
};