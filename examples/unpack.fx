#import "standard.fx";

using standard::io::console;

def main() -> int
{
	nybble[] arr = [0x01,0x02,0x03,0x04];

	nybble a,b,c,d from arr; // Unpack

	print((int)c); print();
	byte[4] arr = [0x01, 0x02, 0x03, 0x04];
	print((u32)arr);
    
	return 0;
};