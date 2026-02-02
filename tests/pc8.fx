#import "standard.fx";

#import "redmath.fx";

#def MAX_8 (byte)0xFFu;

def main() -> int
{

    //print("Start...\n\0");

    int count = popcount(MAX_8);

    if (count == 8)
    {
        print("Success!\n\0");
    }
    else
    {
        print("Failed.\n\0");
    };

    print("End.\n\0");
	return 0;
};