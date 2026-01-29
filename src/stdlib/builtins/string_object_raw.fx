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