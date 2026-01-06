import "redstandard.fx";

def main() -> int
{
    char c = "C";
    u64* pb = @c;

    pb = c + 7;

    return 0;
};