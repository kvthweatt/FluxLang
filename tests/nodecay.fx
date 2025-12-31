import "redstandard.fx";

using standard::io;

def foo(noopstr x) -> noopstr
{
	return x;
};

def main() -> int
{
	noopstr a = "A";
	noopstr b = foo(a);
	win_print(@b, 1);
};