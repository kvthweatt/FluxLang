#import "standard.fx";

using standard::io::console;

object testobj
{
	def __init() -> this
    {
        return this;
    };

    def __exit() -> void {};

    def foo() -> this
    {
        println("Test1!\0");
        return this;
    };

    def bar() -> this
    {
        println("Test2!\0");
        return this;
    };
};

def main() -> int
{
    testobj test();

    test.foo().bar();
	return 0;
};