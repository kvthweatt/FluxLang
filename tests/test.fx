#import "standard.fx";

using standard::io::console,
      standard::strings;

def main() -> int
{
    for (int x; x < 10; x++)
    {
        print((int)x); print();
    };
    return 0;
};