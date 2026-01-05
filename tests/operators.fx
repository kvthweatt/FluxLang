import "redstandard.fx";

using standard::io::console;

def main() -> int
{
	int x = 2;
	x <<= 1;

    noopstr s = "Success!";
    noopstr f = "Fail.";
    if (x == 4)
    {
        win_print(@s,8);
    }
    else
    {
        win_print(@f,5);
    };
	return 0;
};