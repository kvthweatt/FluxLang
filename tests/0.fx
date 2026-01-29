#import "standard.fx";

def main() -> int
{
    print("Testing *(unsigned data{1}*)0 = 0;\0");
	*(unsigned data{1}*)0 = 0;
	return 0;
};