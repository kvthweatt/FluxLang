#import "standard.fx";

#import "strfuncs.fx";

def check_literal_types() -> int
{
    // Different ways to specify literals
    u64 dec_large = (u64)5000000000u;
    u64 hex_large = (u64)0x12A05F200u;         // 5000000000 in hex
    u64 hex_max   = (u64)0xFFFFFFFFFFFFFFFFu;
    u64 just_over = (u64)4294967296u;          // 2^32
    
    byte[32] buffer;
    
    print("Checking literal storage:\n\0");
    
    print("dec_large = \0"); u64str(dec_large, buffer); print(buffer); print("\n\0");
    print("hex_large = \0"); u64str(hex_large, buffer); print(buffer); print("\n\0");
    print("hex_max   = \0"); u64str(hex_max, buffer); print(buffer); print("\n\0");
    print("just_over = \0"); u64str(just_over, buffer); print(buffer); print("\n\0");
    
    // Check if constants are different
    if (dec_large == hex_large) {
        print("dec_large == hex_large (should be true)\n\0");
    } else {
        print("dec_large != hex_large (BUG!)\n\0");
    };
    
    return 0;
};
///
def main() -> int
{
    return check_literal_types();
};
///