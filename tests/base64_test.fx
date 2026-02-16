// Base64 Encoding/Decoding for Flux
// RFC 4648 compliant
#import "standard.fx";

namespace encoding
{
    namespace base64
    {
        // Base64 alphabet (standard encoding)
        const byte[64] BASE64_CHARS = [
            'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
            'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
            'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
            'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
            'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
            'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
            'w', 'x', 'y', 'z', '0', '1', '2', '3',
            '4', '5', '6', '7', '8', '9', '+', '/'
        ];
        
        const byte BASE64_PAD = '=';
        
        // Decode table: maps ASCII character to 6-bit value
        // Invalid chars map to 255
        const byte[256] BASE64_DECODE = [
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 62,  255, 255, 255, 63,
            52,  53,  54,  55,  56,  57,  58,  59,  60,  61,  255, 255, 255, 255, 255, 255,
            255, 0,   1,   2,   3,   4,   5,   6,   7,   8,   9,   10,  11,  12,  13,  14,
            15,  16,  17,  18,  19,  20,  21,  22,  23,  24,  25,  255, 255, 255, 255, 255,
            255, 26,  27,  28,  29,  30,  31,  32,  33,  34,  35,  36,  37,  38,  39,  40,
            41,  42,  43,  44,  45,  46,  47,  48,  49,  50,  51,  255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
        ];
        
        // Calculate the encoded length for a given input length
        def base64_encoded_length(u64 input_len) -> u64
        {
            // Each 3 bytes becomes 4 characters
            // Output is padded to multiple of 4
            return ((input_len + 2) / 3) * 4;
        };
        
        // Calculate the maximum decoded length for a given encoded length
        def base64_decoded_max_length(u64 encoded_len) -> u64
        {
            // Each 4 characters decodes to at most 3 bytes
            return (encoded_len / 4) * 3;
        };
        
        // Encode binary data to Base64
        // Returns the number of bytes written to output
        def base64_encode(byte* input, u64 input_len, byte* output) -> u64
        {
            u64 i = 0;
            u64 j = 0;
            
            // Process 3 bytes at a time
            while (i + 2 < input_len)
            {
                // Read 3 bytes (24 bits)
                u32 b1 = (u32)(input[i] & 0xFF);
                u32 b2 = (u32)(input[i + 1] & 0xFF);
                u32 b3 = (u32)(input[i + 2] & 0xFF);
                
                u32 triple = (b1 << 16) | (b2 << 8) | b3;
                
                // Split into 4 6-bit groups
                output[j] = BASE64_CHARS[(triple >> 18) & 0x3F];
                output[j + 1] = BASE64_CHARS[(triple >> 12) & 0x3F];
                output[j + 2] = BASE64_CHARS[(triple >> 6) & 0x3F];
                output[j + 3] = BASE64_CHARS[triple & 0x3F];
                
                i += 3;
                j += 4;
            };
            
            // Handle remaining bytes (1 or 2)
            if (i < input_len)
            {
                u32 b1 = (u32)(input[i] & 0xFF);
                u32 b2 = 0;
                u32 b3 = 0;
                
                if (i + 1 < input_len)
                {
                    b2 = (u32)(input[i + 1] & 0xFF);
                };
                
                u32 triple = (b1 << 16) | (b2 << 8) | b3;
                
                output[j] = BASE64_CHARS[(triple >> 18) & 0x3F];
                output[j + 1] = BASE64_CHARS[(triple >> 12) & 0x3F];
                
                if (i + 1 < input_len)
                {
                    // 2 bytes remaining
                    output[j + 2] = BASE64_CHARS[(triple >> 6) & 0x3F];
                    output[j + 3] = BASE64_PAD;
                }
                else
                {
                    // 1 byte remaining
                    output[j + 2] = BASE64_PAD;
                    output[j + 3] = BASE64_PAD;
                };
                
                j += 4;
            };
            
            // Null terminate
            output[j] = '\0';
            
            return j;
        };
        
        // Decode Base64 to binary data
        // Returns the number of bytes written to output, or 0 on error
        def base64_decode(byte* input, u64 input_len, byte* output) -> u64
        {
            u64 i = 0;
            u64 j = 0;
            
            // Skip whitespace and find actual length
            u64 actual_len = 0;
            u64 k;
            for (k = 0; k < input_len; k++)
            {
                byte c = input[k];
                if (c != ' ')
                {
                    if (c != '\t')
                    {
                        if (c != '\n')
                        {
                            if (c != '\r')
                            {
                                actual_len++;
                            };
                        };
                    };
                };
            };
            
            // Input must be multiple of 4
            if ((actual_len % 4) != 0)
            {
                return 0;
            };
            
            // Process 4 characters at a time
            while (i < input_len)
            {
                // Skip whitespace
                while (i < input_len)
                {
                    byte c = input[i];
                    if (c == ' ')
                    {
                        i++;
                    }
                    else
                    {
                        if (c == '\t')
                        {
                            i++;
                        }
                        else
                        {
                            if (c == '\n')
                            {
                                i++;
                            }
                            else
                            {
                                if (c == '\r')
                                {
                                    i++;
                                }
                                else
                                {
                                    break;
                                };
                            };
                        };
                    };
                };
                
                if (i >= input_len)
                {
                    break;
                };
                
                // Read 4 characters
                byte c1 = input[i];
                byte c2 = '\0';
                byte c3 = '\0';
                byte c4 = '\0';
                
                if (i + 1 < input_len)
                {
                    c2 = input[i + 1];
                };
                if (i + 2 < input_len)
                {
                    c3 = input[i + 2];
                };
                if (i + 3 < input_len)
                {
                    c4 = input[i + 3];
                };
                
                // Decode characters
                byte v1 = BASE64_DECODE[(c1 & 0xFF)];
                byte v2 = BASE64_DECODE[(c2 & 0xFF)];
                byte v3 = BASE64_DECODE[(c3 & 0xFF)];
                byte v4 = BASE64_DECODE[(c4 & 0xFF)];
                
                // Check for invalid characters
                if (v1 == 255)
                {
                    if (c1 != BASE64_PAD)
                    {
                        return 0;
                    };
                };
                if (v2 == 255)
                {
                    if (c2 != BASE64_PAD)
                    {
                        return 0;
                    };
                };
                
                // Combine into 24-bit value
                u32 triple = ((u32)(v1 & 0x3F) << 18) |
                             ((u32)(v2 & 0x3F) << 12) |
                             ((u32)(v3 & 0x3F) << 6) |
                             (u32)(v4 & 0x3F);
                
                // Extract bytes
                output[j] = (byte)((triple >> 16) & 0xFF);
                
                if (c3 != BASE64_PAD)
                {
                    output[j + 1] = (byte)((triple >> 8) & 0xFF);
                    
                    if (c4 != BASE64_PAD)
                    {
                        output[j + 2] = (byte)(triple & 0xFF);
                        j += 3;
                    }
                    else
                    {
                        j += 2;
                    };
                }
                else
                {
                    j += 1;
                };
                
                i += 4;
            };
            
            return j;
        };
    };
};

using encoding::base64;

def print_bytes_as_hex(byte* datax, u64 len) -> void
{
    u64 i;
    for (i = 0; i < len; i++)
    {
        byte b = datax[i];
        byte high = (b >> 4) & 0x0F;
        byte low = b & 0x0F;
        
        if (high < 10)
        {
            print((byte)('0' + high));
        }
        else
        {
            print((byte)('a' + (high - 10)));
        };
        
        if (low < 10)
        {
            print((byte)('0' + low));
        }
        else
        {
            print((byte)('a' + (low - 10)));
        };
        
        if ((i + 1) % 16 == 0)
        {
            print("\n\0");
        }
        else
        {
            print(" \0");
        };
    };
    if (len % 16 != 0)
    {
        print("\n\0");
    };
    return;
};

def main() -> int
{
    print("==== BASE64 ENCODING/DECODING TEST ====\n\n\0");
    
    byte[1024] encoded;
    byte[1024] decoded;
    u64 encoded_len;
    u64 decoded_len;
    
    // Test 1: Empty string
    print("Test 1: Empty string\n\0");
    byte* test1 = "\0";
    encoded_len = base64_encode(test1, 0, encoded);
    print("Input: \"\"\n\0");
    print("Encoded: \0");
    print(encoded);
    print("\n\0");
    print("Expected: \"\"\n\n\0");
    
    // Test 2: Single character
    print("Test 2: Single character\n\0");
    byte* test2 = "A\0";
    encoded_len = base64_encode(test2, 1, encoded);
    print("Input: \"A\"\n\0");
    print("Encoded: \0");
    print(encoded);
    print("\n\0");
    print("Expected: \"QQ==\"\n\n\0");
    
    // Test 3: Two characters
    print("Test 3: Two characters\n\0");
    byte* test3 = "AB\0";
    encoded_len = base64_encode(test3, 2, encoded);
    print("Input: \"AB\"\n\0");
    print("Encoded: \0");
    print(encoded);
    print("\n\0");
    print("Expected: \"QUI=\"\n\n\0");
    
    // Test 4: Three characters (no padding)
    print("Test 4: Three characters\n\0");
    byte* test4 = "ABC\0";
    encoded_len = base64_encode(test4, 3, encoded);
    print("Input: \"ABC\"\n\0");
    print("Encoded: \0");
    print(encoded);
    print("\n\0");
    print("Expected: \"QUJD\"\n\n\0");
    
    // Test 5: Standard test string
    print("Test 5: \"Hello, World!\"\n\0");
    byte* test5 = "Hello, World!\0";
    encoded_len = base64_encode(test5, 13, encoded);
    print("Input: \"Hello, World!\"\n\0");
    print("Encoded: \0");
    print(encoded);
    print("\n\0");
    print("Expected: \"SGVsbG8sIFdvcmxkIQ==\"\n\n\0");
    
    // Test 6: Binary data (all byte values)
    print("Test 6: Binary data [0x00, 0x01, 0x02]\n\0");
    byte[3] test6;
    test6[0] = (byte)0x00;
    test6[1] = (byte)0x01;
    test6[2] = (byte)0x02;
    encoded_len = base64_encode(test6, 3, encoded);
    print("Input (hex): 00 01 02\n\0");
    print("Encoded: \0");
    print(encoded);
    print("\n\0");
    print("Expected: \"AAEC\"\n\n\0");
    
    // Test 7: Round-trip encoding/decoding
    print("Test 7: Round-trip test\n\0");
    byte* test7 = "The quick brown fox jumps over the lazy dog\0";
    print("Original: \0");
    print(test7);
    print("\n\0");
    
    encoded_len = base64_encode(test7, 44, encoded);
    print("Encoded: \0");
    print(encoded);
    print("\n\0");
    
    decoded_len = base64_decode(encoded, encoded_len, decoded);
    decoded[decoded_len] = '\0';
    print("Decoded: \0");
    print(decoded);
    print("\n\0");
    
    print("Decoded length: \0");
    print((int)decoded_len);
    print(" bytes\n\0");
    print("Match: \0");
    
    bool match = true;
    u64 i;
    for (i = 0; i < 44; i++)
    {
        if (test7[i] != decoded[i])
        {
            match = false;
        };
    };
    
    if (match)
    {
        print("YES\n\n\0");
    }
    else
    {
        print("NO\n\n\0");
    };
    
    // Test 8: Decode standard test vectors
    print("Test 8: Decode test\n\0");
    byte* encoded_test = "SGVsbG8sIFdvcmxkIQ==\0";
    decoded_len = base64_decode(encoded_test, 20, decoded);
    decoded[decoded_len] = '\0';
    print("Encoded: \0");
    print(encoded_test);
    print("\n\0");
    print("Decoded: \0");
    print(decoded);
    print("\n\0");
    print("Expected: \"Hello, World!\"\n\n\0");
    
    print("==== ALL BASE64 TESTS COMPLETE ====\n\0");
    
    return 0;
};
