#import "standard.fx";

using standard::io::console;

be32 x = 5;
le32 y = 10;

int X = 0;

byte[4] bytes = [0xAA, 0xBB, 0xCC, 0xDD];

int x = 5;

def f"{bytes}"() -> void { println("yay"); };

def $X() -> void { println("yay"); };

def main() -> int
{
    f"{bytes}"();

    $X();

    return 0;
};