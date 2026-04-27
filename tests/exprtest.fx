#import "standard.fx";

using standard::io::console,
      standard::strings;

def main() -> int
{
    string h = "Hello";
    string w = "World!";
    print(f"{h} {w}");
    return 0;
};