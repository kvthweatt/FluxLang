import "redstandard.fx";

using standard::io::console;

def main() -> int
{
    noopstr a = "TEST";
    noopstr b = a + "ING";

    win_print(@b,7);
    return 0;
};