#import "redstandard.fx";
#import "strlen.fx";

def main() -> int
{
	byte[] x = f"Testing f-string.\0";
    int len = strlen(@x);
    print(@x,len);
	return 0;
};