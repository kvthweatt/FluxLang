import "redstandard.fx";

using standard::io;

struct TEST
{
    noopstr a;
    noopstr b;
};

def main() -> int
{
    TEST test = {a="test",b="ing!"};
    //noopstr x = "test";
    win_print(@test.a, 4); // Parser not supporting this, no codegen happened.
    return 0;
};