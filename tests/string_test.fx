#import "standard.fx";

using standard::io::console,
      standard::strings;

def main() -> int
{
    string s("Testing!\0");

    print(s.val());

    s.__exit();
	return 0;
};