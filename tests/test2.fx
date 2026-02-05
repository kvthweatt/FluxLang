#import "standard.fx";

def main() -> int
{
    string s("Testing string.\0");

    s.printval();
    return 0;
};