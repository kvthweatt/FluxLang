#import <standard.fx>;

using standard::io::console;
!using standard::io::file;

object test
{
    def __init() -> this
    {
        return this;
    };

    def __expr() -> test* { return this; };

    def __exit() -> void 
    {
        (void)this;
        return;
    };
};

def main() -> int
{
    test MyTest();
    return 0;
};