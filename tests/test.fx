//#import "standard.fx";
unsigned data{8} as byte;

byte* as noopstr;

def main() -> int
{
    noopstr[3] s = ["Testing\0","String\0","Arrays\0"];

    return 0;
};


def !!FRTStartup() -> int {return main();};