#import "standard.fx";

using standard::io::console;

def foo() -> void
{
    println("In foo()!");
};

def callback(long x) -> int
{
    def{}* cb()->void = x;
    cb();
    return 0;
};

def main() -> int
{
    callback(long(@foo));
    return 0;
};