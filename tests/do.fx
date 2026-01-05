import "redstandard.fx";

using standard::io::console;

def main() -> int
{
	noopstr d = "Done.";
	do
	{
		win_print(@d, 5);
		//break;
	};
	return 0;
};