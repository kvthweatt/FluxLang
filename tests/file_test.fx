#import "redstandard.fx";

def main() -> i32
{
    print("Starting...\n", 12);
    byte[] path = "test.txt\0";
    
    // Open file for reading
    i64 file_handle = open_read(@path);
    
    // Check if file opened successfully
    if (file_handle == -1)
    {
        byte[] error_msg = "Error opening file\n";
        print(@error_msg, 19);
        return 1;
    };
    
    print("File opened!\n", 13);
    
    // Create a buffer to read into
    byte[1024] buffer = void; // zero out with = void
    
    // Read from file
    i32 bytes_read = win_read(file_handle, @buffer, 1024);
    
    if (bytes_read == -1)
    {
        byte[] read_error = "Read returned -1\n\0";
        print(@read_error, 17);
    };
    
    if (bytes_read == 0)
    {
        byte[] empty = "Read returned 0 (EOF or empty)\n\0";
        print(@empty, 31);
    };
    
    print("File contents:\n\0", 15);
    print(@buffer, bytes_read);  // Print exactly what we read
    print("\n\0", 1);
    
    // Close the file
    win_close(file_handle);
    
    print("Finished!\n\0", 10);
    return 0;
};