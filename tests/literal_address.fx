#import "standard.fx";

def main() -> int
{
	int* x = @25;
    if (*x == 25)
    {
        print("Address of literal integer to pointer working.\0");
    };
	return 0;
};