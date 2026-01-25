// Flux Standard Library
//
// Do not modify.

// Note:
//
//   Uncomment this comptime block when the full specification is implemented.
//
//compt
//{
//    if (!def(FLUX_STANDARD))
//    {
//        global def FLUX_STANDARD;
//        global import "types.fx", "collections.fx", "system.fx", "io.fx";
//    };
//};

// "Final" stage, all standard library items are defined and imported,
// now we make standard a constant namespace so it cannot be altered when imported.
// Doing another namespace standard definition after this will result in a compiler error.

//const namespace standard
//{
//    using standard::types;
//    using standard::io;
//    using standard::collections;
//    using standard::system;
//};

#def FLUX_REDUCED_SPECIFICATION 1;

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifdef FLUX_REDUCED_SPECIFICATION
#import "redstandard.fx";
#endif;