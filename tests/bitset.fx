#import <standard.fx>;

using standard::io::console;

def main() -> int
{
	byte b;

	b[`7] = 1;

	println("Success!") if (b == 1);

    int i = 420691337;

    data{13} as d13;

    d13 d = 0b1010101010101;

    for (`x in i)  // "for bit x in i"
    {
        print((int)x);  // x is a data{1} type
    };

    print();

    for (`x in d)
    {
    	print((int)x);
    };

	-> b[`0];
};