import "standard.fx";

// Simple hello world function using inline assembly
def print_hello() -> void {
    // Use a simple syscall approach for Windows
    // This will call WriteConsoleA with a hardcoded string
    volatile asm {
        // Get stdout handle
        mov $-11, %ecx
        call GetStdHandle
        mov %eax, %ebx
        
        // Call WriteConsoleA
        // WriteConsoleA(handle, buffer, length, &written, reserved)
        push $0                    // reserved (NULL)
        push $hello_written        // &bytes_written
        push $14                   // length (14 chars)
        push $hello_msg            // message buffer
        push %ebx                  // stdout handle
        call WriteConsoleA
        add $20, %esp              // clean stack
        
    } : : : "eax", "ebx", "ecx", "esp", "memory";
};

def main() -> int {
    print_hello();
    return 0;
};
