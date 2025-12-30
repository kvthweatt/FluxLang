import "redio.fx";

using standard::io;

struct test
{
    noopstr x = "test";
    noopstr y = "ing!";
};

def main() -> int
{
    test a;
    win_print(@a.x, 4);
    return 0;
};