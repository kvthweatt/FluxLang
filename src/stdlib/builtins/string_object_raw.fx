#ifndef FLUX_STANDARD_STRINGS
#def FLUX_STANDARD_STRINGS 1;
#endif

#ifdef FLUX_STANDARD_STRINGS

namespace standard
{
    namespace strings
    {
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
                free(this.value);
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

            def set(byte* s) -> bool
            {
                try
                {
                    this.value = s;
                    return true;
                }
                catch()
                {
                    return false;
                };
                return false;
            };
        };
    };
};

using standard::strings;

#endif;