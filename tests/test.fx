#import "standard.fx";

def main() -> int
{
    float fragmentation = check_fragmentation();

    print(fragmentation, 5);
    return 0;
};