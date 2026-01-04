import "redstandard.fx";

using standard::io;

def main() -> int
{
	noopstr x = win_input();
	win_print(@x, 1);
	return 0;
};