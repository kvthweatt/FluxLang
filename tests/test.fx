#import "standard.fx";

#import "string_object_raw.fx";


namespace test
{
	def foo(int,int)->int,
        foo()->void;

    def foo(int x, int y) -> int {return x * y;};
    def foo()->void {};
};


def main() -> int
{
    string s("\0");
    foo();
    test::foo(1,2);
	return 0;
};