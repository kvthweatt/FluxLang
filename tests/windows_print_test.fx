import "standard.fx";

def print(data{8}[] message) -> void {
    int stdout_handle;
    int bytes_written;
    int message_length = 14; // Hard-coded for "Hello, World!\n"
    
    // Get stdout handle using GetStdHandle
    asm {
        mov $-11, %ecx           // STD_OUTPUT_HANDLE constant
        call GetStdHandle        // Call Windows API
        mov %eax, %0             // Store handle
    } : "=m" (stdout_handle) : : "eax", "ecx";
    
    // Call WriteConsoleA to write the message
    asm {
        push $0                  // Reserved parameter (NULL)
        lea %3, %%eax            // Address of bytes_written
        push %%eax               // lpNumberOfCharsWritten
        push %2                  // nNumberOfCharsToWrite
        push %1                  // lpBuffer (message)
        push %0                  // hConsoleOutput (stdout_handle)
        call WriteConsoleA       // Call Windows API
        add $20, %%esp           // Clean up stack (5 parameters * 4 bytes)
    } : : "m" (stdout_handle), "m" (message), "m" (message_length), "m" (bytes_written) : "eax", "esp";
};

def main() -> int {
    data{8}[] hello_msg = "Hello, World!\n";
    print(hello_msg);
    return 0;
};
