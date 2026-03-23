#import "standard.fx";

using standard::io::console,
      standard::strings;

noopstr m1 = "[recurse \0",
        m2 = "]\0";

bool entered_flag;

def recurse1(int x) <~ int
{
    if (!entered_flag) {entered_flag = true;};
    singinit int y;
	print(m1); print(y); println(m2);
    if (y >= 10) { escape main(); };
    return ++y;
};


def recurse2() <~ void
{
    if (!entered_flag) {entered_flag = true;};
    singinit int z;
    print(m1); print(++z); println(m2);
    if (z >= 10) { escape main(); };
};


def main() -> int
{
    if (!entered_flag)
	{
        recurse2(); // Step into tail function
    }
    else
    {
        return 0;
    };
	return 0;
};