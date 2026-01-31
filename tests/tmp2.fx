#import "standard.fx";

def main() -> int
{
	i8 a, b, c, d = 1, 2, 3, 4;

    i8* pa, pb, pc, pd = @a, @b, @c, @d;

    int[1] x = [[pa, pb, pc, pd]];

    int y = x[0];

    print(y);

	return 0;
};