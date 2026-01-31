#import "standard.fx";

def main() -> int
{
    string s("Hello!\0");

    print(s.val());
	return 0;
};