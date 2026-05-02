#import "standard.fx";

using standard::io::console;

struct Test
{
    int x;
};

def main() -> int
{
    noopstr str = "ABCD";
    
    println(long((@)str));

    Test t from str[0:4];

    println(long(@t.x));
    return 0;
};