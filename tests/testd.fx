#import "standard.fx";

using standard::io::console;

be32 x = 5;
le32 y = 10;

int X = 0;

def f"{x} {y}"() -> void { println("yay"); };

def $X() -> void { println("yay"); };

def main() -> int
{
    f"{x} {y}"();

    $X();

    return 0;
};