#import "standard.fx";

using standard::io::console,
      standard::string;

def main() -> int
{
    string s("Testing!\0");
    print(s.val()[s.length:0]);
    return 0;
};