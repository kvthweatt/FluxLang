#import "redtypes.fx";
#import "strfuncs.fx";
#import "redio.fx";
//#import "string_utils.fx";

    
    def is_whitespace(char c) -> bool
    {
        return c == ' ' | c == '\t' | c == '\n' | c == '\r';
    };
    
    def is_digit(char c) -> bool
    {
        return c >= '0' & c <= '9';
    };
    
    def is_alpha(char c) -> bool
    {
        return (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z');
    };
    
    def is_alnum(char c) -> bool
    {
        return is_alpha(c) | is_digit(c);
    };
    
    def is_hex_digit(char c) -> bool
    {
        return is_digit(c) | (c >= 'a' & c <= 'f') | (c >= 'A' & c <= 'F');
    };
    
    def is_identifier_start(char c) -> bool
    {
        return is_alpha(c) | c == '_';
    };
    
    def is_identifier_char(char c) -> bool
    {
        return is_alnum(c) | c == '_';
    };
    
    def is_newline(char c) -> bool
    {
        return c == '\n' | c == '\r';
    };

    def to_lower(char c) -> char
    {
        if (c >= 'A' & c <= 'Z')
        {
            return c + 32u;
        };
        return c;
    };

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
	return 0;
};