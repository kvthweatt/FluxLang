#ifndef FLUX_STANDARD
#import "standard.fx";
#endif;

def i32str(i32 value, byte* buffer) -> i32
{
    if (value == 0)
    {
        buffer[0] = (byte)48; // '0'
        buffer[1] = (byte)0;  // null terminator
        return 1;
    };
    
    i32 is_negative = 0;
    if (value < 0)
    {
        is_negative = 1;
        value = -value;
    };
    
    // Convert to string in reverse
    i32 pos = 0;
    byte[32] temp;
    
    while (value > 0)
    {
        temp[pos] = (byte)((value % 10) + 48); // Convert digit to ASCII
        value = value / 10;
        pos++;
    };
    
    // Add negative sign if needed
    i32 write_pos = 0;
    if (is_negative == 1)
    {
        buffer[0] = (byte)45; // '-'
        write_pos = 1;
    };
    
    // Copy reversed string to buffer
    i32 i = pos - 1;
    while (i >= 0)
    {
        buffer[write_pos] = temp[i];
        write_pos++;
        i--;
    };
    
    buffer[write_pos] = (byte)0; // null terminator
    return write_pos;
};

def i64str(i64 value, byte* buffer) -> i64
{
    if (value == (i64)0)
    {
        buffer[0] = (byte)48; // '0'
        buffer[1] = (byte)0;  // null terminator
        return 1;
    };
    
    i64 is_negative = (i64)0;
    if (value < (i64)0)
    {
        is_negative = (i64)1;
        value = -value;
    };
    
    // Convert to string in reverse
    i64 pos = (i64)0;
    byte[32] temp;
    
    while (value > (i64)0)
    {
        temp[pos] = (byte)((value % (i64)10) + (i64)48); // Convert digit to ASCII
        value = value / (i64)10;
        pos++;
    };
    
    // Add negative sign if needed
    i64 write_pos = 0;
    if (is_negative == (i64)1)
    {
        buffer[0] = (byte)45; // '-'
        write_pos = (i64)1;
    };
    
    // Copy reversed string to buffer
    i64 i = pos - (i64)1;
    while (i >= (i64)0)
    {
        buffer[write_pos] = temp[i];
        write_pos++;
        i--;
    };
    
    buffer[write_pos] = (byte)0; // null terminator
    return write_pos;
};

def u32str(u32 value, byte* buffer) -> u32
{
    if (value == (u32)0)
    {
        buffer[0] = (byte)48; // '0'
        buffer[1] = (byte)0;  // null terminator
        return (u32)1;
    };
    
    // Convert to string in reverse
    u32 pos = (u32)0;
    byte[32] temp;
    
    while (value > (u32)0)
    {
        temp[pos] = (byte)((value % (u32)10) + (u32)48); // Convert digit to ASCII
        value = value / (u32)10;
        pos++;
    };
    
    // Copy reversed string to buffer
    u32 write_pos = (u32)0;
    u32 i = pos - (u32)1;
    while (i >= (u32)0)
    {
        buffer[write_pos] = temp[i];
        write_pos++;
        i--;
    };
    
    buffer[write_pos] = (byte)0; // null terminator
    return write_pos;
};

def u64str(u64 value, byte* buffer) -> u64
{
    if (value == (u64)0)
    {
        buffer[0] = (byte)48; // '0'
        buffer[1] = (byte)0;  // null terminator
        return (u64)1;
    };
    
    // Convert to string in reverse
    u64 pos = (u64)0;
    byte[32] temp;
    
    while (value > (u64)0)
    {
        temp[pos] = (byte)((value % (u64)10) + (u64)48); // Convert digit to ASCII
        value = value / (u64)10;
        pos++;
    };
    
    // Copy reversed string to buffer
    u64 write_pos = (u64)0;
    u64 remaining = pos;  // Track how many digits remain

    while (remaining > (u64)0)
    {
        remaining--;  // Decrement BEFORE using as index
        buffer[write_pos] = temp[remaining];
        write_pos++;
    };
    
    buffer[write_pos] = (byte)0; // null terminator
    return write_pos;
};

///
#ifndef FLUX_STANDARD_RUNTIME
def main() -> int
{
    byte[20] xbuf;
    int len = i32str(500, xbuf);

    if (len == 3)
    {
        print(xbuf);
        print("\n\0");
        print("Success!\n\0");
    };
    return 0;
};
#endif;
///