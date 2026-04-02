#import "standard.fx";

using standard::io::console,
      standard::strings;

struct xx { int a, b; };


def main() -> int
{
    noopstr x = "Testing!";

    data{3} as u3;
           //0110  //011
    u3 a = x[8``11][0``2];

    xx yy = {5,10};
    u3 b = yy[29``31]; // 5 because 0b101

    print((int)b);

    return 0;
};