#import "redstandard.fx";
#import "strlen.fx";

float a = 3.14;
float b = a + a; // Float math is failing

int c = 1;
int d = 2;
d += 1;

def main() -> int
{
    noopstr x = f"{a}\n\0";
	noopstr y = f"{b}\n\0";
    int len1 = strlen(@x);
    int len2 = strlen(@y);
	print(@x,len1);
    print(@y,len2);
	return 0;	
};