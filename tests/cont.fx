#import "standard.fx";

using standard::io::console;

struct Test
{
    int x;
};

def main() -> int
{
    noopstr str = "ABCD";
    byte[4] bytes = [0x65, 0x66, 0x67, 0x68];
    

    Test t from str[0:4];
    Test v from bytes;

    println(long((@)str));
    println(long(@t.x));

    println(long((@)bytes));
    println(long(@v.x));

    return 0;
};