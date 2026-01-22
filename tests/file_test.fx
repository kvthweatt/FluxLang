import "redstandard.fx";

def main() -> i32
{
    // File path
    byte[] path = "test.txt";
    
    // Open file for reading
    i64 file_handle = open_read(@path);
    
    // Check if file opened successfully
    if (file_handle == -1)
    {
        // File not found or error
        byte[] error_msg = "Error opening file test.txt\n";
        win_print(@error_msg, 30);
        return 1;
    };

    return 0;
};