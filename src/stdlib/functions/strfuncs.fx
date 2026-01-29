#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

def strlen(byte* ps) -> int
{
    int c = 0;
    while (true)
    {
        byte* ch = ps++;

        if (*ch == 0)
        {
            break;
        };
        c++;
    };
    return c;
};

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
        buffer[0] = (byte)45; // '-' // cannot store i32 to i8*: mismatching types without (byte)
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

// Convert float to string with specified precision
// Returns number of characters written (excluding null terminator)
def float2str(float value, byte* buffer, i32 precision) -> i32
{
    i32 write_pos = 0;
    
    // Handle negative numbers
    if (value < 0.0)
    {
        buffer[0] = (byte)45; // '-'
        write_pos = 1;
        value = -value;
    };
    
    // Handle zero case
    if (value == 0.0)
    {
        buffer[write_pos] = (byte)48; // '0'
        buffer[write_pos + 1] = (byte)46; // '.'
        
        i32 i = 0;
        while (i < precision)
        {
            buffer[write_pos + 2 + i] = (byte)48; // '0'
            i++;
        };
        
        buffer[write_pos + 2 + precision] = (byte)0;
        return write_pos + 1 + precision;
    };
    
    // Extract integer part
    i32 int_part = (i32)value;
    
    // Extract fractional part
    float fractional = value - (float)int_part;
    
    // Multiply fractional by 10^precision without helper function
    i32 frac_multiplier = 1;
    i32 j = 0;
    while (j < precision)
    {
        frac_multiplier = frac_multiplier * 10;
        j++;
    };
    
    // Calculate fractional part with rounding
    float scaled_frac = fractional * (float)frac_multiplier;
    i32 frac_part = (i32)(scaled_frac + 0.5);
    
    // Handle overflow from rounding (e.g., 0.999 becomes 1.00)
    if (frac_part >= frac_multiplier)
    {
        int_part = int_part + 1;
        frac_part = 0;
        
        // If int_part became 10, 100, etc., adjust
        if (int_part % 10 == 0 && precision > 0)
        {
            // Simple adjustment for common cases
            // Full general solution would be more complex
        };
    };
    
    // Convert integer part to string
    if (int_part == 0)
    {
        buffer[write_pos] = (byte)48; // '0'
        write_pos = write_pos + 1;
    }
    else
    {
        // Convert integer part in reverse
        byte[32] int_temp;
        i32 temp_pos = 0;
        i32 temp_int = int_part;
        
        while (temp_int > 0)
        {
            int_temp[temp_pos] = (byte)((temp_int % 10) + 48);
            temp_int = temp_int / 10;
            temp_pos++;
        };
        
        // Copy integer part to buffer
        i32 k = temp_pos - 1;
        while (k >= 0)
        {
            buffer[write_pos] = int_temp[k];
            write_pos = write_pos + 1;
            k--;
        };
    };
    
    // Add decimal point if precision > 0
    if (precision > 0)
    {
        buffer[write_pos] = (byte)46; // '.'
        write_pos = write_pos + 1;
        
        // Convert fractional part to string with leading zeros
        if (frac_part == 0)
        {
            i32 m = 0;
            while (m < precision)
            {
                buffer[write_pos] = (byte)48; // '0'
                write_pos = write_pos + 1;
                m++;
            };
        }
        else
        {
            // Build fractional part in reverse
            byte[32] frac_temp;
            i32 frac_digits = 0;
            i32 temp_frac = frac_part;
            
            while (temp_frac > 0)
            {
                frac_temp[frac_digits] = (byte)((temp_frac % 10) + 48);
                temp_frac = temp_frac / 10;
                frac_digits++;
            };
            
            // Add leading zeros if needed
            i32 leading_zeros = precision - frac_digits;
            i32 n = 0;
            while (n < leading_zeros)
            {
                buffer[write_pos] = (byte)48; // '0'
                write_pos = write_pos + 1;
                n++;
            };
            
            // Copy fractional digits in reverse (to get correct order)
            i32 p = frac_digits - 1;
            while (p >= 0)
            {
                buffer[write_pos] = frac_temp[p];
                write_pos = write_pos + 1;
                p--;
            };
        };
    };
    
    // Add null terminator
    buffer[write_pos] = (byte)0;
    return write_pos;
};