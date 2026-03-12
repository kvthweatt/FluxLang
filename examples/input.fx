#import "redstandard.fx";

using standard::io::console;

def main() -> int
{
    int max = 16;
    char[max] buffer;

    print("What's your name? \0");
    int bytes_read = input(buffer, max);
    print("Hello, \0");
    print(@buffer, bytes_read);
    print(".\0");

    return 0;
};