#import "standard.fx";

using standard::io::console;

struct myStru
{
	int x,y;
};

def main() -> int
{
	myStru b;
	print((int)b.x); print();
	print((int)b.y); print();
	return 0;
};