#import "standard.fx";

u64 c = 0;

def recurse(int c) -> void
{
    print(c); print();
    recurse(++c);
};

def main() -> int
{
    recurse(c);
    return 0;
};