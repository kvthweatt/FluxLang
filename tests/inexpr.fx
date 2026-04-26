#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int[4] y = [10, 20, 30, 40];

    int[2] x = [20, 30];

    if (x in y)
    {
    	print(f"Found x in y!");
    };
    return 0;
};