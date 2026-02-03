#import "standard.fx";

def main() -> int
{
	//*(char*)0 = 0;

    int x = 5;
    int y = 0;

    int* px = @x;
    int* py = @y;

    int pxk = px;   // Take x address as integer

    py = (@)pxk;  // cast back to address

    print(*py);
    print();
    print(y);

	return 0;
};