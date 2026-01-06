import "redstandard.fx";

def main() -> int
{
	int[4] arr = [10, 20, 30, 40];

    int x = 1;
	if (arr[x*2] == 30) // Should print, arrays not working.
	{
		win_print("30",2);
	};
    if (x == 2)
    {
        win_print("X",1);
    };

    return 0;
};