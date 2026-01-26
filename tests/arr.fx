#import "standard.fx";

int[5] arr1 = ["AAAA","BBBB","CCCC","DDDD","EEEE"];

def main() -> int
{
    int[5] arr2 = ["AAAA","BBBB","CCCC","DDDD","EEEE"];
    if (arr1[0] == 0x41414141)
    {
        print("AAAA\0");
    };
    if (arr2[1] == 0x42424242)
    {
        print("BBBB\0");
    };
	return 0;
};