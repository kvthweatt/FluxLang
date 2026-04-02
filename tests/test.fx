#import "standard.fx";

using standard::io::console,
      standard::strings;


def main() -> int
{
    noopstr x = "Testing!";

    data{3} as u3;
           //0110  //011
    u3 a = x[8``11][0``2];

    print((int)a);

    return 0;
};