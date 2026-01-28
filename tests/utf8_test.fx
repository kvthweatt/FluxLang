#import "standard.fx";
#import "strfuncs.fx";

def encode_utf8_char(u32 codepoint, byte* buffer, u32 pos) -> u32
{
    if (codepoint <= (u32)0x7F)
    {
        buffer[pos] = (byte)codepoint;
        return (u32)1;
    }
    elif (codepoint <= (u32)0x7FF)
    {
        buffer[pos] = (byte)((u32)0xC0 | (codepoint >> (u32)6));
        buffer[pos + (u32)1] = (byte)((u32)0x80 | (codepoint & (u32)0x3F));
        return (u32)2;
    }
    elif (codepoint <= (u32)0xFFFF)
    {
        buffer[pos] = (byte)((u32)0xE0 | (codepoint >> (u32)12));
        buffer[pos + (u32)1] = (byte)((u32)0x80 | ((codepoint >> (u32)6) & (u32)0x3F));
        buffer[pos + (u32)2] = (byte)((u32)0x80 | (codepoint & (u32)0x3F));
        return (u32)3;
    }
    elif (codepoint <= (u32)0x10FFFF)
    {
        buffer[pos] = (byte)((u32)0xF0 | (codepoint >> (u32)18));
        buffer[pos + (u32)1] = (byte)((u32)0x80 | ((codepoint >> (u32)12) & (u32)0x3F));
        buffer[pos + (u32)2] = (byte)((u32)0x80 | ((codepoint >> (u32)6) & (u32)0x3F));
        buffer[pos + (u32)3] = (byte)((u32)0x80 | (codepoint & (u32)0x3F));
        return (u32)4;
    }
    else
    {
        buffer[pos] = (byte)63;
        return (u32)1;
    };

    return 0;
};

def append_utf8_char(byte* buffer, u32 codepoint) -> u32
{
    u32 len = (u32)0;
    while (buffer[len] != (byte)0)
    {
        len = len + (u32)1;
    };
    
    u32 bytes_written = encode_utf8_char(codepoint, buffer, len);
    buffer[len + bytes_written] = (byte)0;
    return bytes_written;
};

def create_utf8_string() -> int
{
    byte[128] utf8_buf;
    utf8_buf[0] = (byte)0;
    
    // Build a UTF-8 string with symbols
    // First add ASCII part
    byte* ascii_part = (byte*)"Test: ";
    u32 i = (u32)0;
    while (ascii_part[i] != (byte)0)
    {
        utf8_buf[i] = ascii_part[i];
        i = i + (u32)1;
    };
    utf8_buf[i] = (byte)0;
    
    // Add checkmark symbol (U+2713)
    append_utf8_char(utf8_buf, (u32)0x2713);
    
    // Add ASCII text
    byte* more_text = (byte*)" Pass\n";
    u32 j = (u32)0;
    while (more_text[j] != (byte)0)
    {
        append_utf8_char(utf8_buf, (u32)more_text[j]);
        j = j + (u32)1;
    };
    
    print(utf8_buf);
    return 0;
};

// Helper to print byte as hex
def print_hex_byte(byte b) -> void
{
    byte[3] hex_buf;
    u32 high = (u32)((b >> 4) & 0xF);
    u32 low = (u32)(b & 0xF);
    
    // Convert to hex characters
    hex_buf[0] = high < 10 ? (byte)(high + 48) : (byte)(high + 55);
    hex_buf[1] = low < 10 ? (byte)(low + 48) : (byte)(low + 55);
    hex_buf[2] = (byte)0;
    
    print(@hex_buf);
    return void;
};

def main() -> int
{
    byte[32] buffer;
    buffer[0] = (byte)0;
    
    // Test 1: ASCII character 'A' (should be 1 byte)
    u32 bytes1 = encode_utf8_char((u32)65, buffer, (u32)0);
    print("ASCII 'A' (65): ");
    print_hex_byte(buffer[0]);
    print(" (");
    u32str(bytes1, buffer);
    print(buffer);
    print(" bytes)\n");
    
    // Test 2: Euro symbol € (U+20AC = 3 bytes: E2 82 AC)
    buffer[0] = (byte)0;
    buffer[1] = (byte)0;
    buffer[2] = (byte)0;
    u32 bytes2 = encode_utf8_char((u32)0x20AC, buffer, (u32)0);
    print("Euro: ");
    print_hex_byte(buffer[0]);
    print(" ");
    print_hex_byte(buffer[1]);
    print(" ");
    print_hex_byte(buffer[2]);
    print(" (");
    u32str(bytes2, buffer);
    print(buffer);
    print(" bytes)\n");
    
    // Test 3: Checkmark ✓ (U+2713 = 3 bytes: E2 9C 93)
    buffer[0] = (byte)0;
    buffer[1] = (byte)0;
    buffer[2] = (byte)0;
    u32 bytes3 = encode_utf8_char((u32)0x2713, buffer, (u32)0);
    print("Checkmark: ");
    print_hex_byte(buffer[0]);
    print(" ");
    print_hex_byte(buffer[1]);
    print(" ");
    print_hex_byte(buffer[2]);
    print(" (");
    u32str(bytes3, buffer);
    print(buffer);
    print(" bytes)\n");
    
    return 0;
};