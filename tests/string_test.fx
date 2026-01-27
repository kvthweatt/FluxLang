#import "standard.fx";

def strcat_raw(byte[] x, byte[] y) -> byte*
{
    int xlen = strlen(x);
    int ylen = strlen(y);
    int len = xlen + ylen;
    //byte[xlen] a = x;
    //byte[ylen] b = y;
    ///
    for (int k; k < len; k++)
    {
        if (k > xlen) // Consumed x
        {
            c[k-xlen] = b[k-xlen];
        }
        else // Consuming x
        {
            c[k] = a[k]; // lol ak
        };
    };
    ///
    return y;
};

def main() -> int
{
	noopstr x = "Test\0";
	noopstr y = "ing!\0";
    noopstr z;
    print(strcat_raw(x,y));

	noopstr z = x + y + " strings!\0";

    //noopstr z = strcat(x,y);

	print(z);
	return 0;
};