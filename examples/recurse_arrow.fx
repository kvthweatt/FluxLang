#import "standard.fx";

using standard::io::console;

noopstr m1 = "[recurse \0",
        m2 = "]\0";

def recurse1(int x) <~ int
{
    singinit int y;
	print(m1); print(y); println(m2);
    return ++y;
};


def recurse2() <~ void
{
    singinit int z;
    print(m1); print(++z); println(m2);
};


def main() -> int
{
	recurse2(); // Step into tail function
	return 0;
};