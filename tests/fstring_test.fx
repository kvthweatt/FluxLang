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

def main() -> int
{
	int j = 0;
	int k = 1;
	j = k;
	if (j == 1)
	{
		print("j\n",2);
	};
	byte[] x = f"Testing f-string.\n{a} {b} {c} {d}\0";
    int len = strlen(@x);
    print(@x,len);
	return 0;
};