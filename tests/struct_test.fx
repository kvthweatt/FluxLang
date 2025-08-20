struct myStru1
{
	unsigned data{8} a, b, c, d, e, f, g, h;
};

signed data{16} as i16;
unsigned data{8} as byte;
byte[] as noopstr;

struct myStru2
{
    i16 a, b, c, d;
};

def main() -> int
{
    myStru1 newStru1 = {a = "A", b = "B", c = "C", d = "D", e = "E", f = "F", g = "G", h = "H"};
    myStru2 newStru2 = (myStru2)newStru1;


    noopstr str = "ABCDEFGH";

    myStru2 newStru3 = (myStru2)str;

	return 0;
};