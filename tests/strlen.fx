import "redstandard.fx";


def strlen(byte* str) -> int
{
	int len = 0;
	byte* tmp = @str;
	while (true)
	{
		if ((char)*tmp == 0) { break; };
		tmp = (@tmp)++;
	};
	return len;
};


def main() -> int
{
	noopstr x = "Test!\0";

	int len = strlen(x);

	if (len == 0)
	{
		print("zero",4);
	};

	print("Hello World!\n", 13);
	return 0;
};