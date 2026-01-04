import "redtypes.fx";
using standard::types;

struct X
{
	int a;
};

def main() -> int
{
	X x = {a = 65};
	byte test = (byte)x.a;
	return 0;
};