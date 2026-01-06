import "redstandard.fx";

using standard::io;

def main() -> int
{
    int MAX = 256;
    char[256] buffer;
    
    int bytes_read = win_input(buffer, MAX);
    //wpnl();
    win_print(@buffer,bytes_read);

    return 0;
};