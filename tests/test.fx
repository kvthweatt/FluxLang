import "redstandard.fx";
using standard::io;

def main() -> int
{
    noopstr X = "X";
    const volatile global unsigned int x = 5005;
    const heap int y = 3003;
    register int v = 4004;
    const register int rh = -1;
    stack int z = 2002;
    local int k = 10001;
    x += 1;
    y += 2;
    z += 3;
    k += 4;
    for (x; x < 100;)
    {
        win_print(X,1);
        x++;
    };
    return 0;
};