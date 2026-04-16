#import "standard.fx";

using standard::io::console;

be32 x = 2;
le32 y = 10;

int X = 0;

byte[4] bytes = [0x48, 0x31, 0xC0, 0xC3];  // (x86_64   ) xor rax,rax ; ret

def f"{bytes}"() -> void { println("yay"); };

def $X() -> void { println("yay"); };

def i"{}":{uint(1000 / x);}() -> void { println("yay"); };

def main() -> int
{
    f"{bytes}"();

    $X();

    i"{}":{x * 250;}();

    println(i"{}":{x;});

    println(f"{x}");

    return 0;
};