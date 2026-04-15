#import "standard.fx";

using standard::io::console;

be32 x = 5;
le32 y = 10;

def f"{x} {y}"() -> void { println("yay"); };

def main() -> int
{
    f"{x} {y}"();

    return 0;
};