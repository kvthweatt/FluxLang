#import "standard.fx";

using standard::io::console;

def main() -> int
{
    unsigned data{5} as i5;
    double z = 3.0;
	long y = long(z);

	print(y); print();
    print(z);

	return 0;
};