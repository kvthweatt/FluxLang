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
    byte[24] buf1;
    byte[24] buf2;

    byte* bfp1 = @buf1;
    byte* bfp2 = @buf2;

    noopstr x = "TESTING OOP STRINGS!!!\n\0";
    byte* px = @x;

    string str(px);
    print(str.val());
    print(str.len());
    print();

    noopstr x = strcpy(bfp2, x);
    print(buf2);
    print();

    print("Hello World!\n\0");
    return 0;
};