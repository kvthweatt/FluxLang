// Example: Using the File I/O Library
#import "standard.fx", "ffifio.fx";

def main() -> int
{
    int bsize = 8192;
    byte[8192] fbuf; // 8KB, stack allocated. For bigger arrays use malloc()
    noopstr f = "src\\stdlib\\builtins\\string_object_raw.fx\0";

    int bytes_read = read_file(f, fbuf, bsize);
    if (bytes_read > 0)
    {
        print("Successfully read Flux source file.\n\n\0");
    };

    print(fbuf);
    print();

    return 0;
};