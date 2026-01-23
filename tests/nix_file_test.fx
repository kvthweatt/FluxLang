#import "redstandard.fx";

def main() -> i32
{
    print("Linux file read test\n", 21);
    byte[] path = "test.txt\0";
    
    // Open file for reading
    i64 file_handle = open_read(@path);
    
    // Check if file opened successfully
    if (file_handle == (i64)-1)
    {
        byte[] error_msg = "Cannot open test.txt\n";
        print(@error_msg, 21);
        //return 1;
    };
    
    // Create a buffer to read into
    byte[1024] buffer = void;
    
    // Read from file
    i64 bytes_read = read(file_handle, @buffer, 1024);
    
    if (bytes_read == -1)
    {
        byte[] read_error = "Read error\n";
        print(@read_error, 11);
        close(file_handle);
        return 1;
    };
    
    print("Read", 4);
    
    // Print bytes read count
    byte[20] count_str = void;
    i64 pos = 19;
    count_str[pos] = (byte)0;
    i64 temp = bytes_read;
    
    if (temp == (i64)0)
    {
        count_str[--pos] = '0';
    }
    else
    {
        while (temp > (i64)0 && pos > (i64)0)
        {
            //count_str[--pos] = (temp % (i64)10) + '0';
            temp = temp / (i64)10;
        };
    };
    
    print(@count_str[pos], 20 - (i32)pos);
    print(" bytes:\n", 8);
    
    // Print what was read
    if (bytes_read > (i64)0)
    {
        print(@buffer, (i32)bytes_read);
    };
    
    print("\n", 1);
    
    // Close the file
    close(file_handle);
    
    return 0;
};