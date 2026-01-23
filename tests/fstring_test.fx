///
Compile time f-string example.

Currently requires {vars} to be declared globally,
in this example {a}

Still working to get f-strings working for runtime.
///

#import "redstandard.fx";
#import "strlen.fx";

// Compile time constant for f-string
int a = 420691337;

def main() -> int
{
	byte[] x = f"Testing f-string. {a}\0";
    int len = strlen(@x);
    print(@x,len);
	return 0;
};