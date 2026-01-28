#import "redstandard.fx";

def main(int argc, byte** argv) -> int
{
    if (argc == 2)
    {
        print("2 arguments detected!\n\0");
    };
    print("Hello World!\n\0");

    return 0;
};