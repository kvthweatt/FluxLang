import "redio.fx";

using standard::io;

def main() -> int
{
    noopstr str = "This language is great!";
    int len = sizeof(str) / 8;

    noopstr b = "b";

    for (int a = 0; a < len; a++)
    {
        str[a] = b;
        win_print(@str[a],1);
    };
    return 0;
};