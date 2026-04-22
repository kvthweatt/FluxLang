#import "standard.fx";

using standard::io::console;

macro testMac(a,b,c)
{
    (a + b) ^ c
};

def main() -> int
{
    int x,y,z = 1,2,3;

    println(f"testMac(x,y,z) = {testMac(x,y,z)}");

    print(testMac(x,y,z) + 1);

    return 0;
};