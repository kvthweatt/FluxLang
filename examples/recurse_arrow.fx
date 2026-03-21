#import "standard.fx";

using standard::io::console;

noopstr m1 = "[recurse \0",
        m2 = "]\0";

def recurse(int x) <~ int
{
    singinit int y;
	print(m1); print(y); print(m2);
    return ++y;
};


def main() -> int
{
	recurse(0); // Step into tail function
	return 0;
};