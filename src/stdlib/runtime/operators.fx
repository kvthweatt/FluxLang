// Author: Karac V. Thweatt

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_OPERATORS
#def FLUX_STANDARD_OPERATORS 1;


namespace standard
{
    namespace operators
    {
        ///
        Name: Swap

        Takes two integer pointers, swaps the values at each address.
        ///
        operator (int* a, int* b)[<>] -> void
        {
            *a `^^= *b;
            *b `^^= *a;
            *a `^^= *b;
        };

        operator (int a, int b)[<>] -> void
        {
            a ^^= b;
            b ^^= a;
            a ^^= b;
        };

        operator (int* a, int* b)[<?>] -> void
        {
            if (b is void) { return; };
            *a `^^= *b;
            *b `^^= *a;
            *a `^^= *b;
        };

        operator (int a, int b)[<?>] -> void
        {
            if (b is void) { return; };
            a ^^= b;
            b ^^= a;
            a ^^= b;
        };
    };
};

#endif;