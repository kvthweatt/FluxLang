import "redio.fx";

using standard::io;

def main() -> int
{
    noopstr m = "Test!";
    int len = sizeof(m) / 8;
    win_print(@m,len);
	return 0;
};