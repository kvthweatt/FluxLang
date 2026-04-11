#import "standard.fx";

using standard::io::console;

int a = 5;

def main() -> int
{
    int* xa = @a,
         ya = @a,
         za = @a;
    int*[] piarr = [xa, ya, za];

    print(f"{piarr[0]} {ya} {za}");
	return 0;
};