import "redio.fx";

using standard::io;

def ret(byte[] x) -> byte[]
{
    return x;
}; // Should return array type because [], so type information should be included.

def main() -> int
{
    noopstr s = "Test"; // noopstr is type byte[]

    noopstr x = ret(s);

    win_print(@x, sizeof(x)/8);
    return 0;
};