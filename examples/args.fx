#import "standard.fx";

using standard::io::console;

def main(int argc, byte** argv) -> int
{
    print(argv[1]);
    print("\n\0");
    print(argv[2]);
    print("\n\0");


    system("pause\0");
    return 0;
};