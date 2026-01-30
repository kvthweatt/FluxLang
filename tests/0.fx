#import "standard.fx"

def main() -> int
{
	int x = 5;
	int y = ~x;
	print(y);
	print();
    print("Testing *(@)*(void*)void;\n\0");
	*(@)*(void*)void;
	return 0;
};
