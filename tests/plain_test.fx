#import "standard.fx", "strfuncs.fx";

def main() -> int
{
	byte[64] buf;

	int x = float2str(3.14159,buf,5);

	print(buf);

	return 0;
};