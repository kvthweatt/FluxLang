// Reduced Specification Standard Library `standarx.fx` -> `redstandard.fx`

// Designed to provide a base implementation of the standard library for the reduced specification
// until the bootstrap process is completed and the full specification is implemented.

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_RUNTIME
// Disable with 0 to not include the Flux runtime.
#def FLUX_RUNTIME 1;
#import "redruntime.fx";
#endif;

///
namespace standard
{
};
///