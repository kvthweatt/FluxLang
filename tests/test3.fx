#import "standard.fx";

def "??foo@"() -> void
{
    print("I'm working!\n\0");
};

def main() -> int
{
    uint a = 5;
    uint b = 2;
    uint c = a `!| b;
    print(c);
	return 0;
};