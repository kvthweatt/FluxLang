#import "standard.fx";

struct MemoryBlock
{
    byte[1024] bytes;
    bool in_use;
};

def main() -> int
{
    MemoryBlock newblock;

    struct* pm = @newblock; // struct pointers not working

    newblock = 0; // wtf
    return 0;
};