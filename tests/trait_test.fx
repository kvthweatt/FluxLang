#import "standard.fx";

trait TestTrait
{
	def foo() -> void;
};

TestTrait object MyObj
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
};

def main() -> int
{
	return 0;
};