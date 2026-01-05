import "redstandard.fx";
using standard::io;

def main() -> int
{
    const volatile global unsigned int x = 5005;
    const heap int y = 3003;
    stack int z = 2002;
    local int k = 10001;
    x += 1;
    y += 2;
    z += 3;
    k += 4;
    for (x; x < 10000; x++) {};
    return 0;
};