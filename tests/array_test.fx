#import "redstandard.fx";

def main() -> int
{
    byte[] s1 = "Testing a random string printed with strlen()!?\n\0";
    byte[] s2 = "Another string sized by strlen()?\n\0";

    byte[7] test = "abcde\n\0";
    test[0] = "x";
    print(@test,6);
    noopstr test2 = "test!\n";
    test2[4] = "?";
    print(@test2,6);

    int c1 = strlen(@s1);
    int c2 = strlen(@s2);
    for (int x = 0; x < c1 - 1; x++)
    {
        s1[x] = (byte)x + (byte)(x<<2);
    };
    print(@s1, c1);
    (void)s1;
    print(@s2, c2);
    (void)s2;
    #ifdef __WINDOWS__
    print("Windows detected.",17);
    #endif;
    #ifdef __LINUX__
    print("Linux detected.\n",16);
    #endif;

    return 0;
};