#import "standard.fx";

using standard::io::console;

struct test
{
    int a,b;
};

def main() -> int
{
    byte* str1 = @"Testing address of string.",
          str2 = @f"{str1}",
          str3 = @i"{}":{str2},
          str4 = @[0x41, 0x42, 0x43, 0x44, 0x00];

    char* x = @'x';

    int x = 5;

    int* px @= x;

    test* s = @{10,20};

    println(str3);
    println(str4);
    println(*px);

    println(s.b);

    return 0;
};