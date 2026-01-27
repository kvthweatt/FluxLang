#import "standard.fx";

def main() -> int
{
    while (void is false) // !void == true, void == 0, !0 = 1, void == false
    {
        print("[void is not true]\0");
    };
	return 0;
};