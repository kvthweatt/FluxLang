#import "standard.fx";
#import "operators.fx";

using standard::io::console,
      standard::operators;

def main() -> int
{
    int a = 10, b = 20;

    a <?> b;

    println(f"{a}");
    
    return 0;
};