#import "standard.fx";

using standard::io::console;

def main() -> int
{
    byte* test = "int x = 5;";

    ~$test;

    println(x);
    
    return 0;
};