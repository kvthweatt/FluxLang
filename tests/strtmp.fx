#import "standard.fx";

using standard::io::console;

struct myStru<T>
{
	T a,b;
};

def main() -> int
{
    myStru<int> ms = {10,20};

    println(ms.a);
	return 0;
};