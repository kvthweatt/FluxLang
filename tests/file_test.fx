#import "redstandard.fx";

#import "strfuncs.fx";

def main() -> i32
{
    byte[20] xbuf; // Up to 64 bit integers
    int len = i32str(500,xbuf);
    if (len == 3)
    {
        print(xbuf);
        print();
        print("i32str() success!\n\0");
    };

    u64 len = u64str((u64)5000000000,xbuf);
    print(xbuf);        //705032704
    print();
    print("i64str() success!\n\0");

    print("Starting...\n\0");
    byte[] path = "test.txt\0";
    
    // Open file for reading
    i64 file_handle = open_read(@path);
    
    // Check if file opened successfully
    if (file_handle == -1 or file_handle == 0xFFFFFFFFFFFFFFFF or file_handle == 0)
    {
        byte[] error_msg = "Error opening file\n\0";
        print(@error_msg);
        return 1;
    };
    
    print("File opened!\n\0");
    
    // Create a buffer to read into
    byte[1024] buffer; // zero out with = void
    byte* bufptr = buffer;
    
    // Read from file
    i32 bytes_read = win_read(file_handle, bufptr, 1024);
    
    if (bytes_read == -1)
    {
        print("Read returned -1\n\0");
    };
    
    if (bytes_read == 0)
    {
        print("Read returned 0 (EOF or empty)\n\0");
    };
    
    print("File contents:\n\0");
    print(@buffer, bytes_read);  // Print exactly what we read
    print("\n\0");
    
    // Close the file
    win_close(file_handle);
    
    print("Finished!\n\0");
    return 0;
};