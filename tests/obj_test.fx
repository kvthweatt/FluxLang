import "redio.fx";

using standard::io;

object string
{
    noopstr base;

    def __init(noopstr str) -> this
    {
        this.base = str;
        return this;
    };

    def __exit() -> void
    {
        return void;
    };

    def __expr() -> noopstr
    {
        return this.base;
    };
};

def main() -> int
{
    string str("Hello World!");
    int len = sizeof(str) / 8;

    win_print(str, len);
    return 0;
};