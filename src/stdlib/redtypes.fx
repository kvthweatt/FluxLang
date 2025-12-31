// Reduced Specification Standard Library `types.fx` -> `redtypes.fx`

namespace standard
{
	namespace types
	{
		unsigned data{4} as nybble;
        unsigned data{8} as byte;
        byte[] as noopstr;
        char nl = "\n";

        signed data{16} as i16;
		signed data{16} as testi16;
        signed data{32} as i32;
        signed data{64} as i64;

        unsigned data{16} as u16;
        unsigned data{32} as u32;
        unsigned data{64} as u64;
	};
};