import "redstandard.fx";

using standard::io::console;

def main() -> int
{
	noopstr d = "Done.";
    for (;;)
    {
        win_print(d, 5);
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