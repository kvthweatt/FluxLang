//#import "standard.fx";
#import "redtypes.fx", "redmemory.fx", "red_string_utilities.fx", "redio.fx";
def main() -> int
{
    print("Hello World!\0");

    return 0;
};
def !!FRTStartup() -> int { return main(); };