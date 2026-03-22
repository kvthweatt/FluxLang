#import "standard.fx";

namespace test1
{
	namespace test2
	{
		def foo() -> void {};
	};
};


deprecate test1::test2;

def main() -> int
{
	test1::test2::foo();

	return 0;
};

