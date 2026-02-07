#import "standard.fx";

def main() -> int
{
    string s("Testing!\0");

    print(s.val());

    s.__exit();
	return 0;
};