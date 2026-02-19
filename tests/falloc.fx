#import "standard.fx";
#import "redallocators.fx";

def main() -> int
{
	byte* buffer = fmalloc(1024*1024*1024);

	system("pause\0");
	ffree((u64)@buffer);
	return 0;
};