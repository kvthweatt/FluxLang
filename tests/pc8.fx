#import "redmath.fx";

#def MAX_8 (byte)0xFFu;

def main() -> int
{

    int count = popcount(MAX_8);

    if (count == 8)
    {
        return 0;
    }
    else
    {
        return 1;
    };

	return 0;
};

def !!FRTStartup() -> int { return main(); };