import "redstandard.fx";

using standard::io::console;

import "redfrt.fx";

def func(int x) -> int
{
	return ++x;
};

def main() -> int
{
	int x = 0;
	int y = func(x);
	if (y == 1)
	{
        noopstr nz = "Nonzero";
		win_print(nz,7);
	};
	return 0;
};