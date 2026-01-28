// Reduced Specification Standard Library `types.fx` -> `redtypes.fx`
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#def FLUX_STANDARD_TYPES 1;
#endif;

namespace standard
{
	namespace types
	{
		unsigned data{4} as nybble;
        unsigned data{8} as byte;
        byte[] as noopstr;
        unsigned data{16} as u16;
        unsigned data{32} as u32;
        unsigned data{64} as u64;

        signed data{8}  as i8;
        signed data{16} as i16;
        signed data{32} as i32;
        signed data{64} as i64;
	};
};

using standard::types;