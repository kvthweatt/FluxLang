unsigned data{8}[12] i2str_buffer;

def i2str(int num) -> noopstr
{
    
    // Handle special case of 0
    if (num == 0)
    {
        i2str_buffer[0] = 48;  // ASCII '0'
        i2str_buffer[1] = 0;   // null terminator
        return @i2str_buffer;
    };
    
    // Handle negative numbers
    int is_negative = 0;
    if (num < 0)
    {
        is_negative = 1;
        num = -num;  // Make positive
    };
    
    // Convert digits in reverse order
    int pos = 0;
    while (num > 0)
    {
        int digit = num % 10;
        i2str_buffer[pos] = digit + 48;  // Convert to ASCII ('0' = 48)
        pos = pos + 1;
        num = num / 10;
    };
    
    // Add minus sign if negative
    if (is_negative == 1)
    {
        i2str_buffer[pos] = 45;  // ASCII '-'
        pos = pos + 1;
    };
    
    // Null terminate
    i2str_buffer[pos] = 0;
    
    // Reverse the string in place
    int start = 0;
    int end = pos - 1;
    while (start < end)
    {
        unsigned data{8} temp = i2str_buffer[start];
        i2str_buffer[start] = i2str_buffer[end];
        i2str_buffer[end] = temp;
        start = start + 1;
        end = end - 1;
    };
    
    return @i2str_buffer;
};