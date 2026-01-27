#import "standard.fx";

int a = 0dUUTF;

def main() -> int
{
    noopstr x = f"{a}\0";
    print(x);
    return 0dSUCCESS;  // Not 0 so Windows thinks this program didn't end properly.
};