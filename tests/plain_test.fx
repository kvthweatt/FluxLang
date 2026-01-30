#import "standard.fx";

def main() -> int
{
	byte[1024] prbuf;

    int c = 0;
    for (int x = 0; x <= 1022; x++)
    {
        if (x == 1022)
        {
            prbuf[++x] = (byte)0;
            c = ++x;
            break;
        };
        prbuf[x] = "*";
    };

    memset(@prbuf, (byte)0, (i64)1024);

    print(c);
    print();

    print(prbuf);
	return 0;
};