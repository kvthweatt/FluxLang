import "standard.fx";

def loop(int c) -> void
{
	if (c > 0)
	{
		win_print("Loop. ", 6);
		loop(--c);
	};
	return void;
};

def main() -> int
{
	int c = 10;
    loop(c);
	return 0;
};