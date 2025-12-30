import "redio.fx";

using standard::io;

def main() -> int
{
    noopstr name = "World";
    int num = 42;
    noopstr str = f"Hello {name}! The number is {num}";
    win_print(@str, sizeof(str) / 8);
    return 0;
};
