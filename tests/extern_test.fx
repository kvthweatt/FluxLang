#import "standard.fx";

def main() -> int
{
    try
    {
        throw(100);
    }
    catch (int err)
    {
        print("Caught \0");
        print(err);
        print("!\n\0");
    };

    print("Done\n\0");
    return 0;
};