#import "standard.fx";


object string
{
    noopstr value;

    def __init(byte* x) -> this
    {
        this.value = x;
        return this;
    };

    def __exit() -> void
    {
        return;
    };

    def val() -> byte*
    {
        return this.value;
    };

    def len() -> int
    {
        return strlen(this.value);
    };
};


def main() -> int
{
    byte[21] buf;

    noopstr x = "TESTING OOP STRINGS!!!\n\0";
    byte* px = @x;

    string str(px);
    print(str.val());
    print(str.len());
    print();

    print("Hello World!\n\0");
    return 0;
};