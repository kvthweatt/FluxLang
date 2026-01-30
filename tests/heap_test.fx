#import "standard.fx";

def main() -> int
{
    byte[] err = "Testing standard::print with assert()!\0";
    assert(0!=0,"Testing standard::print with assert()!\0");
	heap int x = 4;
    (void)x;
	return 0;
};