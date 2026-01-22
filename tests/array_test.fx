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

    return 0;
};