import "redstandard.fx";

signed data{8} as sbyte;

def main() -> int
{
    byte b =           0b00100001;
    sbyte sb =         0b11111111;
    b <<= 1;         //0b01000010
    b ^^= 0b10111101;//0b00000000
    if (b == 255) { win_print("255",3); };
    // Works on first if, subsequent if causes failure.
    if (sb == -256) { win_print("-256", 4); };
    return 0;
};