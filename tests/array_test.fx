#import "redstandard.fx";
#import "strlen.fx";        // src\stdlib\functions

def main() -> int
{
    byte[] s = "Test\0";

    byte* ps = @s;
    int c = strlen(ps);
    if (c == 4)
    {
        print("\nSuccess.\n", 11);
    };
    #ifdef __WINDOWS__
    print("Windows detected.",17);
    #endif;

    return 0;
};