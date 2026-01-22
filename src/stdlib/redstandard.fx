// Reduced Specification Standard Library `standarx.fx` -> `redstandard.fx`

// Designed to provide a base implementation of the standard library for the reduced specification
// until the bootstrap process is completed and the full specification is implemented.

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#def FLUX_RUNTIME 1;

#ifndef CURRENT_OS
#ifndef WINDOWS
#def WINDOWS 1;
#endif;
#def CURRENT_OS WINDOWS;
#endif;

import "redio.fx";
#ifdef FLUX_RUNTIME
import "redruntime.fx";
#endif;

namespace standard
{
};