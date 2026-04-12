#import "standard.fx";

using standard::io::console;

int a, b, c = 5, 10, 20;

def main() -> int
{
    int* pa = @a,
         pb = @b,
         pc = @c;

    println(a);

    int*[] piarr = [pa, pb, pc];

    print
    (
    i"{} {} {}"
    :{
        (piarr[0] + 4);
        piarr[1];
        piarr[2];
    }
    );

	return 0;
};