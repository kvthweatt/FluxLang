#import "redstandard.fx";
#import "strlen.fx";        // src\stdlib\functions

def main() -> int
{
    byte[] s1 = "Testing a random string!?\n\0";
    byte[] s2 = "Another string?\n\0";

    int c1 = strlen(@s1);
    int c2 = strlen(@s2);
    print(@s1, c1);
    (void)s1;
    print(@s2, c2);
    (void)s2;
    #ifdef __WINDOWS__
    print("Windows detected.",17);
    #endif;
    #ifdef __LINUX__
    print("Linux detected.",15);
    #endif;

    return 0;
};