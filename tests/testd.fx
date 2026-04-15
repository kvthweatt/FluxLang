#import "standard.fx";

using standard::io::console;

be32 x = 5;
le32 y = 10;

def foo(be32 k) -> le32 { return 0; };

def main() -> int
{
    le32 z = foo(y); // Compile error, passing little-endian type to big-endian parameter
    return 0;
};