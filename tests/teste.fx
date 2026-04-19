#import "standard.fx";

using standard::io::console;

def main() -> int
{
    byte*str1=@"Testing address of string.";
    byte*str2=@f"{str1}";
    byte*str3=@i"{}":{str2};
    byte*str4=@[0x41, 0x42, 0x43, 0x44, 0x00];

    char* x = @'x';

    int x = 5;

    int* px @= x;

    println(str3);
    println(str4);
    println(*px);

    return 0;
};