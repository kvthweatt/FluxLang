#import "standard.fx";

def main() -> int
{
    if (is_whitespace('\n'))
    {
        print("Whitespace found!\n\0");
    };
    if (is_digit('7'))
    {
        print("Digit found!\n\0");
    };

    if (is_hex_digit('C'))
    {
        print("Hex value!\n\0");
    };

    print(hex_to_int('F'));

    int lo = find_char_last("abcdabcd",'d');

	return 0;
};