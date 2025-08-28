import "redio.fx";

using standard::io;

def MY_MACRO "Hello World!";
def LEN 12;

def main() -> int
{
    noopstr str = MY_MACRO;

    if (def(LEN))
    {
        win_print(@str, LEN);
    };
    return 0;
};