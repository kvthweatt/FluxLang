#import "standard.fx";

int a = 0dUUTF;

int x = 5;

def main() -> int
{
    print(a);
    return 0dSUCCESS;  // Not 0 so Windows thinks this program didn't end properly.
};