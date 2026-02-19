#import "standard.fx";
#import "redallocators.fx";
#import "redtiming.fx";

!using standard::io::file;
using standard::memory::allocators::stdheap;
using standard::time;

def main() -> int
{
    Timer t;

    timer_start(@t);

    for (int x = 0; x < 1000000; x++)
    {
        byte* b = fmalloc(1024); // 1KB
        ffree((u64)@b);
    };

    print(timer_read(@t));
    return 0;
};