#import "standard.fx";

#import "redmath2.fx";

def main() -> int
{
    i32 x;
    i32 y;
    i32 z; // multi isn't working now wtf. damn it.
    x = 0;
    y = 100;
    z = clamp(x,500,y);
    if (z == 100)
    {
        print("32-bit clamp() success!\n\0");
    };
    ///y = min(y, x);
    if (y == 6)
    {
        print("8-bit min() success!\n\0");
    };///

	return 0;
};