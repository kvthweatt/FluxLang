#import "standard.fx";

using standard::io::console;

def main() -> int
{
label a1:
	int x = 5;
label a2:
	print(x); print();
    goto a1;
	return 0;
};