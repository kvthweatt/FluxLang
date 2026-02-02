#import "standard.fx";

int x = 0;

int[1][1] test = [1][1];

def foo() -> int
{
    if (x == 0)
    {
        return test[0][0];
    };
    return 0;
};

def main() -> int
{
    if (foo() == 1)
    {
        print("global access working.\0");
    };
	return x;
};