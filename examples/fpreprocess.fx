#import "standard.fx";

using standard::io::console,
      standard::io::file,
      standard::strings;

def main(int argc, byte** argv) -> int
{
    noopstr f = "examples\\malloc.fx\0";
    u64 size = get_file_size(f);
	byte* buffer = (byte*)fmalloc((u64)size + 1);

    int bytes_read = read_file(f, buffer, size);

    string filedata = buffer;

    byte** lines = filedata.lines;

    for (line in lines)
    {
        println(line);
    };

	return 0;
};