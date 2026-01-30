// Example: Using the File I/O Library
#import "standard.fx", "ffifio.fx";

def main() -> int
{
    noopstr filename = "test.txt\0";
    // ===== EXAMPLE 1: Write to a file =====
    byte[100] message = "Hello from Flux!\nThis is a test file.\n\0";
    int result = write_file(filename, message, 41);  // 41 chars

    if (result == (bool)-1)
    {
        // Error writing file
        return 1;
    };
    
    
    // ===== EXAMPLE 2: Read from a file =====
    byte[1024] buffer;
    int bytes_read = read_file(filename, buffer, 1024);
    
    if (bytes_read == -1)
    {
        // Error reading file
        return 1;
    };
    
    // buffer now contains the file contents
    // You can print it or process it
    
    
    // ===== EXAMPLE 3: Append to a file =====
    byte[50] more_data = "Appending more text!\n\0";
    append_file(filename, more_data, 21);
    
    
    // ===== EXAMPLE 4: Check file size =====
    int size = get_file_size(filename);
    // size now contains the file size in bytes
    
    
    // ===== EXAMPLE 5: Check if file exists =====
    if ((bool)file_exists(filename))
    {
        // File exists!
        print("File exists!\0");
    };

    
    // ===== EXAMPLE 6: Manual file operations =====
    // For more control, use the raw C functions:
    ///
    void* file = fopen("data.bin", "wb");
    if (file != (@)0)
    {
        byte[10] data = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
        fwrite(@data, 1, 10, file);
        fclose(file);
    };
    
    // Read it back
    void* file2 = fopen("data.bin", "rb");
    if (file2 != (@)0)
    {
        byte[10] read_data;
        fread(@read_data, 1, 10, file2);
        fclose(file2);
        
        // read_data now contains {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
    };
    ///
    return 0;
};