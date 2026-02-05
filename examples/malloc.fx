#import "standard.fx";

def main() -> int
{
    ///
    To programmers learning to program, it is important you understand
    stack limits. To get around stack limits you can either increase
    the stack size, or use the heap.

    You should use malloc to allocate the space for a file.
    ///
    noopstr f = "src\\stdlib\\redio.fx\0";
    int size = get_file_size(f);
	byte* buffer = malloc((u64)size + 1);

    int bytes_read = read_file(f, buffer, size);

    if (bytes_read > 0)
    {
        print("Success!\n\n\0");
    };

    print(buffer);
    print();

	free(buffer);
	return 0;
};