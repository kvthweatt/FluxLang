// Manual integer to string conversion in Flux
// This approach uses no runtime library - pure arithmetic

unsigned data{8} as byte;
byte[] as noopstr;

def i2str(int num) -> noopstr
{
    // Static buffer for the result (enough for 32-bit int + null terminator)
    static byte[12] buffer;
    
    // Handle special case of 0
    if (num == 0) {
        buffer[0] = '0';
        buffer[1] = '\0';
        return @buffer;
    }
    
    // Handle negative numbers
    int is_negative = 0;
    if (num < 0) {
        is_negative = 1;
        num = -num;  // Make positive
    }
    
    // Convert digits in reverse order
    int pos = 0;
    while (num > 0) {
        int digit = num % 10;
        buffer[pos] = digit + '0';  // Convert to ASCII
        pos++;
        num = num / 10;
    }
    
    // Add minus sign if negative
    if (is_negative) {
        buffer[pos] = '-';
        pos++;
    }
    
    // Null terminate
    buffer[pos] = '\0';
    
    // Reverse the string in place
    int start = 0;
    int end = pos - 1;
    while (start < end) {
        byte temp = buffer[start];
        buffer[start] = buffer[end];
        buffer[end] = temp;
        start++;
        end--;
    }
    
    return @buffer;
}

def main() -> int
{
    noopstr result = i2str(12345);
    int len = sizeof(*result) / 8;  // Calculate length manually
    print(result, len);
    return 0;
}
