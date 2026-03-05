#import "standard.fx";


def main() -> int
{
	string s = "Testing!\n\0";

	s.printval();

	system("pause\0");
	return 0;
};