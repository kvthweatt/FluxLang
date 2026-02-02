#import "minstandard.fx";

struct Token
{
    i32 type;
    byte[1024] value;
    i32 line;
    i32 column;
};

i64 MAX_TOKENS = (u64)((500^2) * 10); // 500 thousand
Token[MAX_TOKENS] tokens;

def main() -> int
{
    tokens[0].value = (byte)65;
    return 0;
};