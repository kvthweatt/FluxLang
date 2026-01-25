#import "standard.fx";


def memcpy(byte* src, byte* dst) -> void
{
    *dst = *src;
    return void;
};


def main() -> int
{
    byte x = "A";
    byte y = "0";

    byte* px = @x;
    byte* py = @y;

    memcpy(px,py);

    print(@y, 1);
    return 0;
};