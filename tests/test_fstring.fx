import "redio.fx";

using standard::io;

def main() -> int
{
    noopstr name = "World";
    int num = 42;
    win_print(f"Hello {name}! The number is {num}.", 25);
    return 0;
};
