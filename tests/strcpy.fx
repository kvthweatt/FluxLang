import "redstandard.fx";

// Need to add `extern` for FFI
def strcpy(char* dst, const char* src) -> char*;

def main() -> int
{
    char a = "A";
    char b;
    char* pa = @a;
    char* pb = @b;

    strcpy(pb,pa);

    win_print(@b,1);
	return 0;
};