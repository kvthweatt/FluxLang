#import "standard.fx";

trait Trait1
{
	def foo() -> void;
};

trait Trait2
{
    def bar() -> void;
};

Trait1 Trait2 object MyObj
{
    def __init() -> this
    {
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    def foo() -> void {};
    def bar() -> void {};
};

def main() -> int
{
	return 0;
};