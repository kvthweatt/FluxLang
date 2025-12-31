import "redstandard.fx";

using standard::io;

struct x
{
	noopstr a = "TEST";
	noopstr b = "ING!";
};

def main() -> int
{
	win_print(x.a, 8);
    return 0;
};