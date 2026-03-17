// SHA-256 Implementation in Flux
// Based on FIPS 180-4 specification
#import "standard.fx", "redcrypto.fx";

using standard::io::console;
using standard::strings;
using standard::crypto::hashing::SHA256;

def main() -> int
{
    SHA256_CTX ctx;

    sha256_init(@ctx);

    print("==== SHA256 TEST ====\n\0");
    byte* msg = "Testing SHA256!\0";
    
    // Calculate length manually or use strlen
    int msg_len = strlen(msg);
    
    print("Message: \0");
    print(msg);
    print("\n\0");
    print("Length: \0");
    print(msg_len);
    print("\n\0");

    byte[32] hash;
    sha256_update(@ctx, msg, (u64)msg_len);
    sha256_final(@ctx, @hash);

    print("Hash: \0");
    
    // Print hash in hex
    int i = 0;
    while (i < 32)
    {
        byte b = hash[i];
        // Print high nibble
        byte high = (b >> 4) & 0x0F;
        if (high < 10)
        {
            print((byte)('0' + high));
        }
        else
        {
            print((byte)('a' + (high - 10)));
        };
        
        // Print low nibble
        byte low = b & 0x0F;
        if (low < 10)
        {
            print((byte)('0' + low));
        }
        else
        {
            print((byte)('a' + (low - 10)));
        };
        
        i++;
    };
    print("\n\0");

    return 0;
};
