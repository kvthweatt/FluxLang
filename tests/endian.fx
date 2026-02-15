#import "standard.fx";


unsigned data{16::1} as be16;
unsigned data{16::0} as le16;

unsigned data{32::1} as u32be;
unsigned data{32::0} as u32le;


def main() -> int
{
	be32 x = 0xAA00AA00u;
	le32 y = x;

	print(endianof(y));
	print();
	print(y);
	return 0;
};