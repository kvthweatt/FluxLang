import "standard.fx";

def main() -> int
{
	noopstr d = "Done.";

    if (1==1)
    {
        win_print(d, 5);
    };
    for (;;)
    {
        win_print("Done.", 5);
        break;
    };
	do
	{
		win_print(d, 5);
		break;
	};
    do
    {
        win_print(d, 5);
        break;
    } while (true);
    while (true)
    {
        win_print(d, 5);
        break;
    };
	return 0;
};