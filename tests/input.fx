import "redstandard.fx";

using standard::io;

def main() -> int
{
    int MAX = 10;
    char[10] buffer;
    
    noopstr p = ".";
    noopstr h = "Hello, ";
    win_print("What's your name? ", 18);
    int bytes_read = win_input(buffer, MAX);
    win_print(@h,7);
    win_print(@buffer,bytes_read);
    win_print(@p,1);

    return 0;
};