#import "standard.fx";

def main() -> int
{
    noopstr f = "src\\stdlib\\redio.fx\0";
    int size = get_file_size(f);
	byte* buffer = malloc(size + 1);

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