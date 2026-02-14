#import "standard.fx";

def main() -> int
{
	unsigned data{16::1} as be16;
	unsigned data{16::0} as le16;

	be16 x = 0x00AAu;

	le16 y = x;

	print(y);
	return 0;
};