#import "standard.fx";

using standard::io::console;

def main() -> int
{
    int x = 10;
    
    {
        println("Print1");
        println("Print2");
    }
    if (x == 5) else
    {
        println("Print3");
        println("Print4");
    };

    return 0;
};