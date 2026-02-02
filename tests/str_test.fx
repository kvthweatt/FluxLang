#import "standard.fx";

def main() -> int
{
    // Test with explicit large 64-bit constants
    byte[32] buffer;

    noopstr x = "1234\0";
    noopstr z = "12345678987654321\0";

    i32 y = str2i32(x);

    if (y == 1234)
    {
        print("Success!\n\0");
    }
    else
    {
        print("Fail.\n\0");
    };

    u32 y = str2u32(x);

    if (y == 1234u)
    {
        print("Success!\n\0");
    }
    else
    {
        print("Fail.\n\0");
    };

    i64 y = str2i64(z);

    if (y == 12345678987654321)
    {
        print("Success!\n\0");
    }
    else
    {
        print("Fail.\n\0");
    };

    u64 y = str2i64(z);

    if (y == 12345678987654321u)
    {
        print("Success!\n\0");
    }
    else
    {
        print("Fail.\n\0");
    };
    
    return 0;
};