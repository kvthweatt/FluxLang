#import "standard.fx";

#import "strfuncs.fx";

def main() -> int
{
    // Test with explicit large 64-bit constants
    byte[32] buffer;

    noopstr x = "1234";

    i32 y = str2i32(x);

    if (y == 1234)
    {
        print("Success!\n\0");
    }
    else
    {
        print("Fail.\n\0");
    };
    
    return 0;
};