import "redstandard.fx";


def strlen(byte* ps) -> int
{
    int c = 0;
    while (true)
    {
        ++c;
        if (*ps++ == 0)
        {
            c += 1;
            break;
        };
    };
    return c;
};


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