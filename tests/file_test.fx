// Example: Using the File I/O Library
#import "standard.fx", "ffifio.fx";

def main() -> int
{
    noopstr filename = "test.txt\0";
    // ===== EXAMPLE 1: Write to a file =====
    byte[100] message = "Hello from Flux!\nThis is a test file.\n\0";
    print(message);
    int result = write_file(filename, message, strlen(message));  // 41 chars

    if (result == -1)
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
    int bytes_written = append_file(filename, more_data, strlen(more_data));
    print(more_data);
    print("Bytes written: \0");
    print(bytes_written);
    print();
    
    // ===== EXAMPLE 4: Check file size =====
    int size = get_file_size(filename);
    print("File size: \0");
    print(size);
    print(" bytes.\n\0");
    // size now contains the file size in bytes
    
    
    // ===== EXAMPLE 5: Check if file exists =====
    if (file_exists(filename))
    {
        // File exists!
        print("File exists!\0");
    };
    return 0;
};