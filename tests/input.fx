import "redstandard.fx";

using standard::io;

def main() -> int
{
    int MAX = 256;
    char[256] buffer;
    
    u32 bytes_read = win_input(buffer, MAX);

    return 0;
};