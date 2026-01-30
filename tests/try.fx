#import "standard.fx";

def main() -> int
{
    try
    {
        print("Attemptnig segfault...\n\0");
        throw(4);
    }
    catch (i64 err)
    {
        print(err);
        print();
    };
    
    return 0;
};