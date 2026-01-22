#import "redstandard.fx";
#import "strlen.fx";        // src\stdlib\functions

def main() -> int
{
    byte[] s = "Testing a random string!?\n\0";

    byte* ps = @s;
    int c = strlen(ps);
    print(@s, c);
    #ifdef __WINDOWS__
    win_print("Windows detected.",17);
    #endif;
    #ifdef __LINUX__
    nix_print("Linux detected.",15);
    #endif;

    return 0;
};