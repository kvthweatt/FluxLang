import "standard.fx";

using standard::io;

def main() -> int
{
	noopstr a = "A";
	noopstr b = "B";
	//a ^^= b;
	//b ^^= a;
	//a ^^= b;
	a = xor(b);
	b = xor(a);
	a = xor(b);
	
	win_print(@a, 1);
	return 0;
};