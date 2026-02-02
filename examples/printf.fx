#import "standard.fx";

def main() -> int
{
	uint size = 1000000; // 1 million
    print("Allocating buffer ...\n\0");
    byte* buffer = malloc(size);
    print("Done.\n\0");

    char c = '*';
    
    print("Performing memset() ...\n\0");
    memset(buffer, c, (size_t)size - 1);
    buffer[size-1] = '\0';
    printf("%s",buffer);
    free(buffer); // Can use (void)buffer; as well.
    
    print("Done.\n\0");

	return 0;
};