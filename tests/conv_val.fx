#import "standard.fx";

using standard::io::console;

def main() -> int
{
    double z = 3.000000000d;
	u64 y = (u64)z;

	print(y); print();
    print(z);

	return 0;
};