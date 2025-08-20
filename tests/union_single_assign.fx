union myU
{
	int a;
	char b;
};

def main() -> int
{
    myU newU;
    newU.a = 10;  // This should work (first and only assignment)
	return 0;
};
