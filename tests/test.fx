import "redstandard.fx";
using standard::io;

def main() -> int
{
    noopstr x = "test";
    noopstr y = "ing!";
    noopstr z = x + y;

    win_print(@z, 8);
    return 0;
};