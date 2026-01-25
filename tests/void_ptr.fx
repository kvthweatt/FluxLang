#import "standard.fx";

def main() -> int
{
    char x = 5;
    void* px = @x;
    int y = *px;
    if (y == 5)
    {
        print("Success!\0");
    }
    else
    {
        print("Failure.\0");
    };

    (void)x;
    (void)y;
    (void)px;
	return 0;
};