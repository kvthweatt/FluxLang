import "redstandard.fx";

using standard::io::file;

def main() -> int
{
    // 1. Open the file for reading
    FileHandle handle = open_read("myfile.txt");
    
    // 2. Check if the file opened successfully
    if (!is_valid(handle))
    {
        print("Error: Could not open file\n");
        return -1;
    };
    
    // 3. Get the file size to know how much memory to allocate
    signed data{64} file_size = win_get_size(handle);
    
    // 4. Allocate a buffer (byte array) to hold the file contents
    byte[file_size] buffer; // This causes parsing errors. Must fix.
    
    // 5. Read the file into the buffer
    unsigned data{32} bytes_read = 0;
    bool success = win_read(handle, @buffer, (unsigned data{32})file_size, @bytes_read);
    
    // 6. Check if read was successful
    if (!success)
    {
        print("Error: Could not read file\n");
        win_close(handle);
        return -1;
    };
    
    // 7. Close the file handle
    win_close(handle);
    
    // 8. Convert buffer to string (cast byte array to noopstr)
    noopstr file_contents = (noopstr)buffer;
    
    // 9. Use the string
    print(file_contents);
    
    return 0;
};