import "redio.fx";

using standard::io;

def main() -> int
{
    noopstr x = "Test" + "ing!";
    win_print(@x, sizeof(x)/8);
    return 0;
};