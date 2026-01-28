#import "standard.fx";

#import "redmath.fx";

#def MAX_32 0xFFFFFFFF;
#def MAX_64 0xFFFFFFFFFFFFFFFF;

def main() -> int
{
    // Set to all 1s
    int max32  = MAX_32;
    i64 max64  = MAX_64;

    u32 maxu32 = MAX_32;
    u64 maxu64 = MAX_64;

    print("Start...\n\0");

    i32 ix32 = popcount(max32);
    if (ix32 == 32)
    {
        print("Signed 32-bit popcount() success!\n\0");
    }
    else
    {
        print("Signed 32-bit popcount() failed.\n\0");
    };

    i64 ix64 = popcount(max64);
    if (ix64 == 64)
    {
        print("Signed 64-bit popcount() success!\n\0");
    }
    else
    {
        print("Signed 64-bit integers handled as 32-bit!\nCritical failure!\n\0");
    };
    
    u32 ux32 = popcount(maxu32);
    if (ux32 == 32)
    {
        print("Unsigned 32-bit popcount() success!\n\0");
    }
    else
    {
        print("Unsigned 32-bit popcount() failed.\n\0");
    };

    u64 ux64 = popcount(maxu64);
    if (ux64 == (u64)64)
    {
        print("Unsigned 64-bit popcount() success!\n\0");
    }
    elif (ux64 == 32)
    {
        print("Unsigned 64-bit integers handled as 32-bit!\nCritical failure!\n\0");
    };

    print("End.\n\0");
	return 0;
};