// Author: Karac V. Thweatt

// Flux Exception Handling Runtime

#ifndef FLUX_STANDARD_EXCEPTIONS
#def FLUX_STANDARD_EXCEPTIONS 1;

namespace standard
{
    namespace exceptions
    {
        enum STDLIB_Exceptions
        {
            MSG_ACTIVE,
            NUM_ACTIVE
        };

        union STDLIB_Exception
        {
            byte* msg;
            u16   code;
        } STDLIB_Exceptions;
    };
};

#endif; // FLUX_STANDARD_EXCEPTIONS