int x = 10;

def foo(int a) -> int
{
	(void)x;
    return a;
};

def main() -> int {
    int b = foo(x);
	//b += x;
    return x;
};