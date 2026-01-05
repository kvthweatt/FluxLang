import "redstandard.fx";

using standard::io;

def main() -> int
{
	noopstr x = "Hello World!";
	int len = sizeof(x) / 8;
	win_print(x, len);
	return 0;
};