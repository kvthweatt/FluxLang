#ifndef FLUX_STANDARD_STRINGS
#def FLUX_STANDARD_STRINGS 1;
#endif

#ifdef FLUX_STANDARD_STRINGS

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

#endif;