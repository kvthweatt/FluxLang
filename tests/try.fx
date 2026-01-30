#import "standard.fx";

def main() -> int
{
    int x = 1000;
    try
    {
        print("Throwing...\0");
        throw(x);
    }
    catch (int s)
    {
        print("\nCaught \0");
        print(s);
        print("!\n\0");
    };
    
    return 0;
};