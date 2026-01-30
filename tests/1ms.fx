#import "standard.fx";

def main() -> int
{
	byte[1000000] buf;

    for (int x = 0; x < 999999; x++)
    {
        if (x == 999998)
        {
            x++;
            byte[x] = (byte)0;
            break;
        };
        byte[x] = "*";
    };

    print(buf);
	return 0;
};