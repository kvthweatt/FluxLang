#import "standard.fx";

def main() -> int
{
    if (void is void)
    {
        print("void is void\n\0");
    };
//
    unsigned data{1} as i1;
    unsigned data{3} as i3;

    i1 a, b, c = 1, 0, 1;
    i3[1] y = [[a, b, c]];

    if (y != 5)
    {
        print("Packing not working!\n\0");
    }
    else
    {
        print("Packing arrays to integers working!\n\0");
    };
//
	return 0;
};