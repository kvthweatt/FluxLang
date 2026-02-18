#import "standard.fx";

object test
{
    def __init() -> this
    {
        return this;
    };

    def __exit() -> void { (void)this; };

    def pv() -> void { print("TEST\n\0"); };
};

def main() -> int
{
    test t();

    t.__exit();

    t.pv();
    return 0;
};