#import "standard.fx";

enum my_enum
{
	GOOD_RETURN,
	BAD_RETURN_1
};

def main() -> int
{
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