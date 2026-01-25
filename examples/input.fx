#import "redstandard.fx";

using standard::io;

def main() -> int
{
    int MAX = 10;
    char[10] buffer;

    print("What's your name? \0");
    int bytes_read = win_input(buffer, MAX);
    print("Hello, \0");
    print(@buffer, bytes_read);
    print(".\0");

    return 0;
};