import "standard.fx";

// Print function using Windows WriteConsoleA system call
def print(data{8}[] message) -> void {
    // Get handle to stdout
    int stdout_handle;
    asm {
        mov $-11, %ecx          // STD_OUTPUT_HANDLE = -11
        call GetStdHandle
        mov %eax, %0
    } : "=m" (stdout_handle) : : "eax", "ecx";
    
    // Calculate string length
    int length = 0;
    int i = 0;
    while (message[i] != 0) {
        length = length + 1;
        i = i + 1;
    };
    
    // Call WriteConsoleA
    int bytes_written;
    asm {
        push $0                 // lpReserved (NULL)
        lea %4, %%eax           // &bytes_written
        push %%eax              // lpNumberOfCharsWritten
        push %2                 // nNumberOfCharsToWrite (length)
        push %1                 // lpBuffer (message)
        push %3                 // hConsoleOutput (stdout_handle)
        call WriteConsoleA
        add $20, %%esp          // Clean up stack (5 * 4 bytes)
    } : "=m" (bytes_written) : "m" (message), "m" (length), "m" (stdout_handle), "m" (bytes_written) : "eax", "esp";
};

def main() -> int {
    data{8}[] hello_msg = "Hello, World!\n";
    data{8}[] test_msg = "Extended inline assembly is working!\n";
    
    print(hello_msg);
    print(test_msg);
    return 0;
};
