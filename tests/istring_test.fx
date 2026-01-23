#import "redstandard.fx";
#import "strlen.fx";

def main() -> int
{
	byte[] x = i"Test i-string\0"{};
    int len = strlen(@x);
    print(@x,len);
	return 0;
};