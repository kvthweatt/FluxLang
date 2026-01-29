// debug_file_test.fx
#import "standard.fx";

def main() -> i32
{
    print("Debug: Starting file test...\n\0");
    
    // Test different paths
    byte[] path1 = "test.txt\0";
    byte[] path2 = "\\test.txt\0";
    byte[] path3 = "C:\\test.txt\0";
    
    print("Debug: Testing path1: \0");
    print(@path1);
    print();
    
    // First check if we can even call the function
    i64 handle = open_read(@path1);
    
    print("Debug: open_read returned: \0");
    byte[20] buf;
    i64str(handle, buf);
    print(buf);
    print();
    
    // Try creating a file first
    print("Debug: Trying to create a file first...\0");
    
    i64 create_handle = open_write(@path1);
    
    print("Debug: open_write returned: \0");
    i64str(create_handle, buf);
    print(buf);
    print();
    
    if (create_handle != -1)
    {
        print("Debug: Successfully created file!\n");
        
        // Write something
        byte[] test_data = "Test data\n\0";
        i32 written = win_write(create_handle, test_data, strlen(test_data));
        
        print("Debug: win_write returned: \0");
        i32str(written, buf);
        print(buf);
        print();
        
        // Close it
        i32 closed = win_close(create_handle);
        print("Debug: win_close returned: \0");
        i32str(closed, buf);
        print(buf);
        print();
        
        // Now try to read it
        print("Debug: Now trying to read the file we just created...\n\0");
        handle = open_read(@path1);
        
        print("Debug: open_read (after create) returned: \0");
        i64str(handle, buf);
        print(buf);
        print();
        
        if (handle != -1)
        {
            byte[100] read_buf;
            i32 read_bytes = win_read(handle, read_buf, 100);
            
            print("Debug: win_read returned: \0");
            i32str(read_bytes, buf);
            print(buf);
            print("\n");
            
            if (read_bytes > 0)
            {
                print("Debug: Read content: \0");
                read_buf[read_bytes] = (byte)0;
                print(read_buf);
            };
            
            win_close(handle);
        };
    }
    else
    {
        print("Debug: Could not create file. Testing with absolute path...\n\0");
        
        // Try C:\test.txt
        create_handle = open_write(@path3);
        
        print("Debug: open_write (C:\\test.txt) returned: \0");
        i64str(create_handle, buf);
        print(buf);
        print();
    };
    
    print("Debug: Test complete.\n\0");
    return 0;
};