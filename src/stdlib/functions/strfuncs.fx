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
    
    // Use != 0 instead of > 0 to avoid signed comparison issues
    while (value != (u64)0)
    {
        temp[pos] = (byte)((value % (u64)10) + (u64)48); // Convert digit to ASCII
        value = value / (u64)10;
        pos++;
    };
    
    // Copy reversed string to buffer
    u64 write_pos = (u64)0;
    u64 remaining = pos;  // Track how many digits remain

    while (remaining != (u64)0)
    {
        remaining--;  // Decrement BEFORE using as index
        buffer[write_pos] = temp[remaining];
        write_pos++;
    };
    
    buffer[write_pos] = (byte)0; // null terminator
    return write_pos;
};

def str2i32(byte* str) -> int
{
    int result = 0;
    int sign = 1;
    int i = 0;
    
    // Skip leading whitespace
    while (str[i] == 32 | str[i] == 9 | str[i] == 10 | str[i] == 13)
    {
        i++;
    };
    
    // Check for sign
    if (str[i] == 45)  // '-'
    {
        sign = -1;
        i++;
    }
    elif (str[i] == 43)  // '+'
    {
        i++;
    };
    
    // Convert digits
    while (str[i] != 0)
    {
        byte c = str[i];
        
        // Check if character is a digit (0-9 are ASCII 48-57)
        if (c >= 48 & c <= 57)
        {
            int digit = (int)(c - 48);
            result = result * 10 + digit;
        }
        else
        {
            // Non-digit character, stop parsing
            break;
        };
        
        i++;
    };
    
    return result * sign;
};

// Convert string to unsigned 32-bit integer
// Returns 0 if string is invalid or negative
def str2u32(byte* str) -> uint
{
    uint result = (uint)0;
    int i = 0;
    
    // Skip leading whitespace
    while (str[i] == (byte)32 | str[i] == (byte)9 | str[i] == (byte)10 | str[i] == (byte)13)
    {
        i++;
    };
    
    // Skip '+' if present, return 0 if '-' present
    if (str[i] == (byte)45)  // '-'
    {
        return (uint)0;  // Negative not allowed for unsigned
    }
    elif (str[i] == (byte)43)  // '+'
    {
        i++;
    };
    
    // Convert digits
    while (str[i] != (byte)0)
    {
        byte c = str[i];
        
        // Check if character is a digit
        if (c >= (byte)48 & c <= (byte)57)
        {
            uint digit = (uint)(c - (byte)48);
            result = result * (uint)10 + digit;
        }
        else
        {
            // Non-digit character, stop parsing
            break;
        };
        
        i++;
    };
    
    return result;
};

// Convert string to signed 64-bit integer
// Returns 0 if string is invalid
def str2i64(byte* str) -> i64
{
    i64 result = (i64)0;
    i64 sign = (i64)1;
    int i = 0;
    
    // Skip leading whitespace
    while (str[i] == (byte)32 | str[i] == (byte)9 | str[i] == (byte)10 | str[i] == (byte)13)
    {
        i++;
    };
    
    // Check for sign
    if (str[i] == (byte)45)  // '-'
    {
        sign = (i64)-1;
        i++;
    }
    elif (str[i] == (byte)43)  // '+'
    {
        i++;
    };
    
    // Convert digits
    while (str[i] != (byte)0)
    {
        byte c = str[i];
        
        // Check if character is a digit
        if (c >= (byte)48 & c <= (byte)57)
        {
            i64 digit = (i64)(c - (byte)48);
            result = result * (i64)10 + digit;
        }
        else
        {
            // Non-digit character, stop parsing
            break;
        };
        
        i++;
    };
    
    return result * sign;
};

// Convert string to unsigned 64-bit integer
// Returns 0 if string is invalid or negative
def str2u64(byte* str) -> u64
{
    u64 result = (u64)0;
    int i = 0;
    
    // Skip leading whitespace
    while (str[i] == (byte)32 | str[i] == (byte)9 | str[i] == (byte)10 | str[i] == (byte)13)
    {
        i++;
    };
    
    // Skip '+' if present, return 0 if '-' present
    if (str[i] == (byte)45)  // '-'
    {
        return (u64)0;  // Negative not allowed for unsigned
    }
    elif (str[i] == (byte)43)  // '+'
    {
        i++;
    };
    
    // Convert digits
    while (str[i] != (byte)0)
    {
        byte c = str[i];
        
        // Check if character is a digit
        if (c >= (byte)48 & c <= (byte)57)
        {
            u64 digit = (u64)(c - (byte)48);
            result = result * (u64)10 + digit;
        }
        else
        {
            // Non-digit character, stop parsing
            break;
        };
        
        i++;
    };
    
    return result;
};