unsigned data{8} as byte;
byte[] as noopstr;

noopstr nl = "\n";

// Print function (from previous test)
def print(unsigned data{8}* msg, int len) -> void
{
    volatile asm
    {
        // HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE = -11)
        movq $$-11, %rcx
        subq $$32, %rsp
        call GetStdHandle
        addq $$32, %rsp

        // BOOL ok = WriteFile(h, msg, len, NULL, NULL)
        movq %rax, %rcx         // RCX = handle (from GetStdHandle)
        movq %0, %rdx           // RDX = lpBuffer (msg parameter)
        movl %1, %r8d           // R8D = nNumberOfBytesToWrite (len parameter)
        xorq %r9, %r9           // R9 = lpNumberOfBytesWritten = NULL
        subq $$40, %rsp         // 32 bytes shadow + 8 for 5th arg slot
        movq %r9, 32(%rsp)      // *(rsp+32) = lpOverlapped = NULL
        call WriteFile
        addq $$40, %rsp
    } : : "r"(msg), "r"(len) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
    return void;
};

def pnl() -> void
{
    print(@nl, 1);
};

// Print a single byte as hex
def print_hex_byte(byte b) -> void
{
    byte hex_chars[16] = "0123456789ABCDEF";
    byte output[3];
    
    // High nibble
    output[0] = hex_chars[(b >> 4) & 0x0F];
    // Low nibble  
    output[1] = hex_chars[b & 0x0F];
    // Space separator
    output[2] = 32; // ASCII space
    
    print(@output, 3);
};

// Open a file for reading and return handle
def open_file(noopstr filename) -> int
{
    int handle = 0;
    
    volatile asm
    {
        // HANDLE CreateFileA(filename, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL)
        movq %1, %rcx           // RCX = filename
        movq $$0x80000000, %rdx // RDX = GENERIC_READ
        movq $$1, %r8           // R8 = FILE_SHARE_READ
        xorq %r9, %r9           // R9 = lpSecurityAttributes = NULL
        subq $$56, %rsp         // 32 bytes shadow + 24 for remaining args
        movq $$3, 32(%rsp)      // dwCreationDisposition = OPEN_EXISTING
        movq $$128, 40(%rsp)    // dwFlagsAndAttributes = FILE_ATTRIBUTE_NORMAL
        movq %r9, 48(%rsp)      // hTemplateFile = NULL
        call CreateFileA
        addq $$56, %rsp
        movq %rax, %0           // Store result in handle
    } : "=m"(handle) : "r"(filename) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
    
    return handle;
};

// Read from file handle into buffer
def read_file(int handle, byte* buffer, int bytes_to_read) -> int
{
    int bytes_read = 0;
    
    volatile asm
    {
        // BOOL ReadFile(handle, buffer, bytes_to_read, &bytes_read, NULL)
        movl %1, %ecx           // RCX = handle (extend 32-bit to 64-bit)
        movq %2, %rdx           // RDX = buffer
        movl %3, %r8d           // R8D = bytes_to_read
        leaq %0, %r9            // R9 = &bytes_read
        subq $$40, %rsp         // 32 bytes shadow + 8 for 5th arg
        xorq %rax, %rax
        movq %rax, 32(%rsp)     // lpOverlapped = NULL
        call ReadFile
        addq $$40, %rsp
    } : "=m"(bytes_read) : "r"(handle), "r"(buffer), "r"(bytes_to_read) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
    
    return bytes_read;
};

// Close file handle
def close_file(int handle) -> void
{
    volatile asm
    {
        // BOOL CloseHandle(handle)
        movl %0, %ecx           // RCX = handle
        subq $$32, %rsp
        call CloseHandle
        addq $$32, %rsp
    } : : "r"(handle) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
    return void;
};

def main() -> int
{
    // Create a test file first (we'll read our own source code)
    noopstr filename = "tests/file_test.fx";
    
    print("Opening file: ", 14);
    print(filename, 18);  // Length of "tests/file_test.fx"
    pnl();
    
    int file_handle = open_file(filename);
    
    // Check if file opened successfully (INVALID_HANDLE_VALUE = -1)
    if (file_handle == -1)
    {
        print("Failed to open file!", 20);
        pnl();
        return 1;
    }
    
    print("File opened successfully!", 24);
    pnl();
    
    // Read first 64 bytes of the file
    byte buffer[64];
    int bytes_read = read_file(file_handle, @buffer, 64);
    
    print("Bytes read: ", 12);
    print_hex_byte((byte)(bytes_read & 0xFF));
    pnl();
    
    print("File content (hex): ", 20);
    pnl();
    
    // Print the bytes in hex format
    for (int i = 0; i < bytes_read; i++)
    {
        print_hex_byte(buffer[i]);
        
        // Print newline every 16 bytes for readability
        if ((i + 1) % 16 == 0)
        {
            pnl();
        }
    }
    pnl();
    
    print("File content (ASCII): ", 22);
    pnl();
    
    // Print the bytes as ASCII characters (printable ones)
    for (int i = 0; i < bytes_read; i++)
    {
        if (buffer[i] >= 32 && buffer[i] <= 126)  // Printable ASCII range
        {
            print(@buffer[i], 1);
        }
        else
        {
            print(".", 1);  // Non-printable character
        }
    }
    pnl();
    
    close_file(file_handle);
    print("File closed.", 12);
    pnl();
    
    return 0;
};
