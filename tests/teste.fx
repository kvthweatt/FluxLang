#import "standard.fx";

using standard::io::console;

object to1
{
    def __init() -> this
    {
        return this;
    };

    def __exit() -> void
    {
    };

    private
    {
        int x = 5;

        def bar() -> void
        {
            println("in bar!");
            return;
        };
    };

    public
    {
        int y = 10;

        def foo() -> void
        {
            println("in foo!");
            this.bar();
        };
    };
};

def main() -> int
{
    to1 newObj();

    newObj.foo();

    println(newObj.y);

    newObj.__exit();

	return 0;
};