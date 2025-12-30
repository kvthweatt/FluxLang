import "redstandard.fx";

using standard::io;

struct X
{
    noopstr a, b;
};

def main() -> int
{
	X x = {a = "TEST", b = "ING!"};
    win_print(@x.a, 10);
    return 0;
};