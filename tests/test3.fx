#import "standard.fx";

def "??foo@"() -> void
{
    print("I'm working!\n\0");
};

def main() -> int
{
    "??foo@"();
    int x;
    x += 1;
	return 0;
};