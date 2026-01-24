///
Compile time f-string example.

Currently requires {vars} to be declared globally,
in this example {a}

Still working to get f-strings working for runtime.
///

#import "redstandard.fx";

// Compile time constant for f-string
int a = 69;
int b = 420;
int c = 1337;
int d = a + b;
int e = 5 ^ 2;
//int[] squares = [x^2 for (x in 1..10)];

def pow(int l, int r) -> int
{
	int x = l;
	for (int y = 0; y < r - 1; y++)
	{
		x *= l;
	};
	return x;
};

namespace test
{
	int z = 5;
};

def main() -> int
{
	int z = (pow(test::z, 2)) / 25;
	if (z == 1)
	{
		print("z\0");
	};
	int j = 0;
	int k = 1;
	j = k;
	if (j == 1)
	{
		print("j\n\0");
	};
	byte[] x = f"Testing f-string.\n{a} {b} {c} {d} {e}\0";
    int len = strlen(@x);
    print(@x,len);
	return 0;
};