// Reduced Specification Standard Library `dostypes.fx`
// DOS LIBRARY
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_DOS_TYPES
#def FLUX_STANDARD_DOS_TYPES 1;
#endif;

namespace standard
{
	namespace types
	{
		unsigned data{4} as nybble;
        unsigned data{8} as byte;
        byte[] as noopstr;
        unsigned data{16} as u16;

        signed data{8}  as i8;
        signed data{16} as i16;
	};
};

using standard::types;