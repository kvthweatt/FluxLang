#import "standard.fx";

def main() -> int
{
	unsigned data{7} as i7;
    unsigned data{21} as i21;
	i7 a = 4;
    i7 b = 8;
    i7 c = 16;
	i21[1] test = [[a, b, c]];
	return 0;
};