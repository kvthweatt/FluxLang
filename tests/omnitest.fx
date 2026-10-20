///
- omnitest.fx
- Designed to test every Flux syntax construct and language feature
///

#import <standard.fx>;

using standard::io::console;

data{1:1:0} as lebit;
data{1:1} as bebit;

///
comptime CA
{
	bool a = true;
    foo(lebit a) -> lebit -> a;

	goto CB;
};

comptime CB
{
	if (a) compiler.io.console.println("Cross-comptime block variable check and goto pass.");
    a = false;

    bebit b;
    foo(b);  // Failed test of param checking at comptime, works outside.

    goto CC;
};

comptime CC
{
    data{21:21} as b21i;
    data{7:7}   as b7i;

    b21i b21i_x = 0b111011100010001110111;

    b7i b7i_x = b21i_x[0``6];

    for (`x in b7i_x)
    {

    };
};
///

foo(lebit a) -> lebit -> a;

def main() -> int
{
    data{21:21} as b21i;
    data{7:7}   as b7i;

    bebit b;

    // Test for mismatching endianness for passed parameter
    foo(b);  // passes base compiler, fails to error using bootstrap

    b21i b21i_mx = 0b111011100010001110111;

    for (x in b21i_mx) // currently x is type b21i
    {
    };

    // Here, x should be a 1 bit type.
    // This is to perform width-based iteration of a target
    // Currently `for (type iden in iden)` is not supported
    // That is to say, specifying the iterative width is not valid
    // Here the iterative width is 1 bit, and should loop 21 times.
    ///
    for (data{1} x in b21i_mx)
    {
    };
    ///

    // New syntax, bitwise iteration of a value.
    // (`x in y) means x is a data{1} type, and this is specifically
    // bitwise-iteration of b21i_mx
    for (`x in b21i_mx)
    {
    };

	return 0;
};