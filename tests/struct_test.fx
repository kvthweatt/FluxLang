struct myStru1
{
	unsigned data{8} a, b, c, d, e, f, g, h;
};

signed data{16} as i16;

struct myStru2
{
    i16 a, b, c, d;
};

def main() -> int
{
    myStru1 newStru1 = {a = "A", b = "B", c = "C", d = "D", e = "E", f = "F", g = "G", h = "H"};

    myStru2 newStru2 = (myStru2)newStru1;

	return 0;
};