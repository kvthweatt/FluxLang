#import "standard.fx";

using standard::io::console;

def main(int argc, byte** argv) -> int
{
    if (argc == 0) { return 0; };
    if (argc >= 1)
    {
        print(argv[0]);
        print("\n\0");
    };

    system("pause\0");
    return 0;
};