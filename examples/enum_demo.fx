#import "standard.fx";

enum my_enum
{
	GOOD_RETURN,
	BAD_RETURN_1
};

union reg { int x; };

union tag_union
{
    int x;
    char y;
} my_enum;

def main() -> int
{
    reg myU;

    myU.x = 5;
    if (myU.x == 5)
    {
        print("Unions working!\n\0");
    };

    tag_union myT;

    myT._ = my_enum.GOOD_RETURN; // ._ to access the union tag.

    switch (myT._)
    {
        case (0)
        {
            print("Tagged unions working!\n\0");
        }
        default {};
    };

    int x = 5;
    int y = 0;

    x ^^= y;
    y ^^= x;
    x ^^= y;

    switch (x)
    {
        case (0)
        {
            print("Swapped x and y!\n\0");
            return my_enum.GOOD_RETURN;
        }
        case (5)
        {
            print("Failed to swap x and y!\n\0");
            return my_enum.BAD_RETURN_1;
        }
        default {};
    };

	return my_enum.GOOD_RETURN;
};