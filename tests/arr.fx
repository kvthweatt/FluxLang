#import "standard.fx";

int[5] arr1 = ["AAAA","BBBB","CCCC","DDDD","EEEE"];
int[5] arr3 = arr1;

def main() -> int
{
    int[5] arr2 = arr1;
    if (arr1[0] == 0x41414141)
    {
        print("AAAA\0");
    };
    if (arr2[1] == 0x42424242)
    {
        print("BBBB\0");
    };
    if (arr3[2] == 0x43434343)
    {
        print("CCCC\0");
    };
	return 0;
};