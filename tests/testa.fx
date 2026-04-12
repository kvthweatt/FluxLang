#import "standard.fx";

using standard::io::console,
      standard::strings;

def main() -> int
{
    string s("Testing!\0");
    print(s.val()[0:3]);
    return 0;
};