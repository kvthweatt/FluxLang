#import "standard.fx";

using standard::io::console,
      standard::strings;


def main() -> int
{
    noopstr x = "Testing!";

    data{4} as u4;

    u4 a = x[8``11];

    print((int)a);

    return 0;
};