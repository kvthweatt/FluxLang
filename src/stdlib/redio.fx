// Input/Output Operations
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#import "redsys.fx";


#ifndef FLUX_STANDARD_IO
#def FLUX_STANDARD_IO

#ifndef FLUX_STANDARD_TYPES
//#import "redtypes.fx";
#endif;

namespace standard
{
    namespace io
    {
        // Console I/O
        namespace console
        {
    		// INPUT FORWARD DECLARATIONS
#ifdef __WINDOWS__
            def win_input(byte[] buffer, int max_len) -> int;
#endif; // Windows
#ifdef __LINUX__
            def nix_input(byte[] buffer, int max_len) -> int;
#endif; // Linux
#ifdef __MACOS__
            def mac_input(byte[] buffer, int max_len) -> int;
#endif; // Mac
            // GENERIC
            def input(byte[] buffer, int max_len) -> int;
            

            // OUTPUT FORWARD DECLARATIONS
#ifdef __WINDOWS__
            def win_print(byte* msg, int x) -> void;
#endif;
#ifdef __LINUX__
            def nix_print(byte* msg, int x) -> void;
#endif;
#ifdef __MACOS__
            def mac_print(byte* msg, int x) -> void;
#endif;

// INPUT DEFINITIONS BEGIN
#ifdef __WINDOWS__
            def reset_from_input() -> void;

#ifdef __ARCH_X86_64__
            // INPUT DEFINITIONS
            def win_input(byte[] buf, int max_len) -> int
            {
                i32 bytes_read = 0;
                i32* bytes_read_ptr = @bytes_read;
                i32 original_mode = 0;
                i32* mode_ptr = @original_mode;
                
                volatile asm
                {
                    // Get stdin handle
                    movq $$-10, %rcx
                    subq $$32, %rsp
                    call GetStdHandle
                    addq $$32, %rsp
                    movq %rax, %r12
                    
                    // Get current console mode
                    movq %rax, %rcx
                    movq $3, %rdx
                    subq $$32, %rsp
                    call GetConsoleMode
                    addq $$32, %rsp
                    
                    // Enable ENABLE_PROCESSED_INPUT (for Ctrl+C) and keep ENABLE_LINE_INPUT
                    // 0x001F = ENABLE_PROCESSED_INPUT | ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | 
                    //          ENABLE_WINDOW_INPUT | ENABLE_MOUSE_INPUT
                    movq %r12, %rcx
                    movq $$0x001F, %rdx
                    subq $$32, %rsp
                    call SetConsoleMode
                    addq $$32, %rsp
                    
                    // Read input (will wait for Enter)
                    movq %r12, %rcx
                    movq $0, %rdx           // buf
                    movl $1, %r8d           // max_len
                    movq $2, %r9            // bytes_read_ptr
                    subq $$40, %rsp
                    movq $$0, 32(%rsp)
                    call ReadFile
                    addq $$40, %rsp
                    
                    // Restore original mode
                    movq %r12, %rcx
                    movl ($3), %edx
                    subq $$32, %rsp
                    call SetConsoleMode
                    addq $$32, %rsp
                    
                    // Return bytes_read
                    movl ($2), %eax
                } : : "r"(buf), "r"(max_len), "r"(bytes_read_ptr), "r"(mode_ptr)
                  : "rax","rcx","rdx","r8","r9","r10","r11","r12","memory";
                reset_from_input();
                return bytes_read - 2;
            };
#endif; // ARCH 86 64
#ifdef __ARCH_ARM64__
#endif // ARCH ARM
#endif; // WINDOWS

            def input(byte[] buffer, int max_len) -> int
            {
                switch (CURRENT_OS)
                {
#ifdef __WINDOWS__
                    case (1)
                    {
                        return win_input(buffer, max_len);
                    }
#endif;
#ifdef __LINUX__
                    case (2)
                    {
                        return nix_input(buffer, max_len);
                    }
#endif;
#ifdef __MACOS__
                    case (3)
                    {
                        return mac_input(buffer, max_len);
                    }
#endif;
                    default
                    { return 0; };
                };
                return 0;
            };
// INPUT DEFINITIONS END

// OUTPUT FUNCTIONS BEGIN
#ifdef __WINDOWS__
#ifdef __ARCH_X86_64__
            // OUTPUT DEFINITIONS
            def win_print(byte* msg, int x) -> void
            {
                volatile asm
                {
                    // HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE = -11)
                    movq $$-11, %rcx
                    subq $$32, %rsp
                    call GetStdHandle
                    addq $$32, %rsp

                    // BOOL ok = WriteFile(h, msg, x, NULL, NULL)
                    movq %rax, %rcx         // RCX = handle (from GetStdHandle)
                    movq $0, %rdx           // RDX = lpBuffer (operand 0 = msg)
                    movl $1, %r8d           // R8D = nNumberOfBytesToWrite (operand 1 = x, DWORD)
                    xorq %r9, %r9           // R9 = lpNumberOfBytesWritten = NULL
                    subq $$40, %rsp         // 32 bytes shadow + 8 for 5th arg slot
                    movq %r9, 32(%rsp)      // *(rsp+32) = lpOverlapped = NULL
                    call WriteFile
                    addq $$40, %rsp
                } : : "r"(msg), "r"(x) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return;
            };

            def reset_from_input() -> void
            {
                char bs = 8;
                win_print(@bs,1);
                win_print(@bs,1);
                return;
            };
#endif; // ARCH 86 64
#ifdef __ARCH_ARM64__
            def win_print(byte* msg, int x) -> void
            {
                volatile asm
                {
                    // Windows ARM64 calling convention:
                    // x0: Return value, also first parameter
                    // x1-x7: Parameters 2-8
                    // x8: Indirect result location / syscall number
                    // x9-x15: Temporary registers
                    // x16-x17: Intra-procedure-call scratch registers
                    // x18: Platform register (avoid)
                    // x19-x28: Callee-saved
                    // x29: Frame pointer
                    // x30: Link register
                    //chcp 65001
                    //utf8_test
                    
                    // GetStdHandle(STD_OUTPUT_HANDLE = -11)
                    mov x0, #-11             // STD_OUTPUT_HANDLE
                    bl GetStdHandle          // Call GetStdHandle
                    
                    mov x19, x0              // Save handle in callee-saved register
                    mov x0, x19              // hFile = handle
                    ldr x1, [sp]             // Get msg from stack (first parameter after x0)
                    ldr w2, [sp, #8]         // Get x from stack (32-bit)
                    mov x3, #0               // lpNumberOfBytesWritten = NULL
                    mov x4, #0               // lpOverlapped = NULL
                    
                    bl WriteFile             // Call WriteFile
                } : : "r"(msg), "r"(x) : "x0", "x1", "x2", "x3", "x4", "x5","x6","x7",
                                         "x8", "x9", "x10","x11","x12","x13",
                                         "x14","x15","x16","x17","x19","memory";
                return;
            };
#endif; // ARCH ARM
#endif; // WINDOWS

#ifdef __LINUX__
#ifdef __ARCH_X86_64__
            def nix_print(byte* msg, int x) -> void
            {
                // Convert count to 64-bit for syscall
                i64 count = x;
                
                volatile asm
                {
                    // Linux syscall: write(int fd, const void *buf, size_t count)
                    // syscall number: 1 (write)
                    // fd: 1 (STDOUT_FILENO)
                    // buf: msg
                    // count: count (64-bit)
                    
                    movq $$1, %rax
                    movq $$1, %rdi
                    movq $0, %rsi
                    movq $1, %rdx
                    syscall
                } : : "r"(msg), "r"(count) : "rax","rdi","rsi","rdx","rcx","r11","memory";
                return;
            };
#endif; // ARCH 86 64
#ifdef __ARCH_ARM64__
            def nix_print(byte* msg, int x) -> void
            {
                // Convert count to 64-bit for syscall
                i64 count = x;
                
                volatile asm
                {
                    // Linux ARM64 syscall convention:
                    // x8: syscall number
                    // x0-x5: parameters
                    // Return value in x0
                    
                    // Linux syscall: write(int fd, const void *buf, size_t count)
                    // syscall number: 64 (write)
                    // fd: 1 (STDOUT_FILENO)
                    // buf: msg
                    // count: count (64-bit)
                    
                    mov x8, #64
                    mov x0, #1
                    ldr x1, [sp]
                    ldr x2, [sp, #8]
                    svc #0
                } : : "r"(msg), "r"(count) : "x0","x1","x2","x3","x4","x5",
                                              "x6","x7","x8","x9","x10","x11",
                                              "x12","x13","x14","x15","x16",
                                              "x17","memory";
                return;
            };
#endif; // ARCH ARM
#endif; // LINUX

#ifdef __MACOS__
#ifdef __ARCH_X86_64__
            def mac_print(byte* msg, int x) -> void
            {
                // Convert count to 64-bit for syscall
                i64 count = x;
                
                volatile asm
                {
                    // macOS x86_64 (Darwin) syscall convention:
                    // - Syscall number in rax
                    // - Parameters: rdi, rsi, rdx, r10, r8, r9 (similar to Linux)
                    // - Use syscall instruction (same as Linux)
                    // - Syscall numbers are different from Linux
                    
                    // macOS syscall: write(int fd, const void *buf, size_t count)
                    // syscall number: 0x2000004 (write)
                    // Note: macOS adds 0x2000000 to BSD syscall numbers
                    // BSD write syscall is 4, so macOS = 0x2000004
                    // fd: 1 (STDOUT_FILENO)
                    // buf: msg
                    // count: count (64-bit)
                    
                    movq $$0x2000004, %rax
                    movq $$1, %rdi
                    movq $0, %rsi
                    movq $1, %rdx
                    syscall
                } : : "r"(msg), "r"(count) : "rax","rdi","rsi","rdx","r10","r8","r9","rcx","r11","memory";
                return;
            };
#endif; // ARCH 86 64
#ifdef __ARCH_ARM64__
            def mac_print(byte* msg, int x) -> void
            {
                volatile asm
                {
                    movz x16, #0x4
                    movk x16, #0x2000, lsl #16
                    mov x0, #1
                    ldr x1, [sp]
                    ldr x2, [sp, #8]
                    svc #0x80
                } : : "r"(msg), "r"(x) : "x0","x1","x2","x16","memory";
                return;
            };
#endif; // ARCH ARM
#endif; // MACOS

            // GENERIC
    		def print(noopstr s, int len) -> void
    		{
    			// Designed to use sys.fx to determine which OS we're on
    			// and call the appropriate print function.
                switch (CURRENT_OS)
                {
#ifdef __WINDOWS__
                    case (1) // Windows
                    {
                        win_print(@s, len);
                    }
#endif;
#ifdef __LINUX__
                    case (2) // Linux
                    {
                        nix_print(@s, len);
                    }
#endif;
#ifdef __MACOS__
                    case (3) // Darwin (Mac)
                    {
                        mac_print(@s, len);
                    }
#endif;
                    default { return; }; // Unknown - exit() for now
                };
    			(void)s;
    			return;
    		};

            def print(noopstr s) -> void
            {
                int len = strlen(@s);
                // GENERIC PRINT
                //
                // Designed to use sys.fx to determine which OS we're on
                // and call the appropriate print function.
                switch (CURRENT_OS)
                {
#ifdef __WINDOWS__
                    case (1) // Windows
                    {
                        win_print(@s, len);
                    }
#endif;
#ifdef __LINUX__
                    case (2) // Linux
                    {
                        nix_print(@s, len);
                    }
#endif;
#ifdef __MACOS__
                    case (3) // Darwin (Mac)
                    {
                        mac_print(@s, len);
                    }
#endif;
                    default { return; }; // Unknown - exit() for now
                };
                (void)s;
                return;
            };

            // GENERIC
            def print(noopstr, int) -> void,
                print(noopstr) -> void,
                print(byte) -> void, // print single character
                print(bool) -> void,
                printchar(noopstr x) -> void,
                print(byte x) -> void,
                print(i8 x) -> void,
                print(i16 x) -> void,
                print(int x) -> void,
                print(i32 x) -> void,
                print(i64 x) -> void,
                print(u16 x) -> void,

                print(u32 x) -> void,
                print(u64 x) -> void,
                print(float x) -> void,
                print(float x, int y) -> void;

            def print(bool b) -> void
            {
                if (b) { print("True\0"); } else { print("False\0"); };
            };

            def print(byte s) -> void
            {
                byte[2] x = [s, 0];
                print(x);
                return;
            };

            def print(i32 x) -> void
            {
                byte[21] buf;
                i32str(x,buf);
                print(buf);
                return;
            };

            def print(u32 x) -> void
            {
                byte[21] buf;
                u32str(x,buf);
                print(buf);
                return;
            };

            def print(i64 x) -> void
            {
                byte[21] buf;
                i64str(x,buf);
                print(buf);
                return;
            };///
            def print(u64 x) -> void
            {
                byte[21] buf;
                u64str(x,buf);
                print(buf);
                return;
            };///
            def print(float x) -> void
            {
                byte[256] buffer;
                float2str(x, @buffer, 5);
                print(buffer);
                return;
            };
            def print(float x, int y) -> void
            {
                byte[256] buffer;
                float2str(x, @buffer, y);
                print(buffer);
                return;
            };

            def print() -> void
            {
                // No params = newline printed
                // GENERIC PRINT
                //
                // Designed to use sys.fx to determine which OS we're on
                // and call the appropriate print function.
                switch (CURRENT_OS)
                {
#ifdef __WINDOWS__
                    case (1) // Windows
                    {
                        win_print("\n", 1);
                    }
#endif;
#ifdef __LINUX__
                    case (2) // Linux
                    {
                        nix_print("\n", 1);
                    }
#endif;
#ifdef __MACOS__
                    case (3) // Darwin (Mac)
                    {
                        mac_print("\n", 1);
                    }
#endif;
                    default { return; }; // Unknown - exit() for now
                };
                return;
            };
        };      // CONSOLE //

                // FILE //
        namespace file
        {
#ifdef __WINDOWS__
            // File access modes (dwDesiredAccess)
            #def GENERIC_READ 0x80000000;
            #def GENERIC_WRITE 0x40000000;
            #def GENERIC_READ_WRITE 0xC0000000;
            
            // File share modes (dwShareMode)
            #def FILE_SHARE_READ 0x00000001;
            #def FILE_SHARE_WRITE 0x00000002;
            #def FILE_SHARE_DELETE 0x00000004;
            
            // File creation disposition (dwCreationDisposition)
            #def CREATE_NEW 1;
            #def CREATE_ALWAYS 2;
            #def OPEN_EXISTING 3;
            #def OPEN_ALWAYS 4;
            #def TRUNCATE_EXISTING 5;
            
            // File attributes (dwFlagsAndAttributes)
            #def FILE_ATTRIBUTE_NORMAL 0x80;
            #def FILE_ATTRIBUTE_ARCHIVE 0x20;
            
            // Invalid handle value
            #def INVALID_HANDLE_VALUE -1;
       
            // FORWARD DECLARATIONS
            def win_open(byte* path, u32 access, u32 share, u32 disposition, u32 attributes) -> i64;
            def win_read(i64 handle, byte* buffer, u32 bytes_to_read) -> i32;
            def win_write(i64 handle, byte* buffer, u32 bytes_to_write) -> i32;
            def win_close(i64 handle) -> i32;
            
            // IMPLEMENTATIONS
            
            // CreateFileA - Opens or creates a file
            // Returns: File handle (i64), or INVALID_HANDLE_VALUE on failure
            def win_open(byte* path, u32 access, u32 share, u32 disposition, u32 attributes) -> i64
            {
                i64 handle = INVALID_HANDLE_VALUE;

                volatile asm
                {
                    // Save path to RCX (first parameter)
                    movq $0, %rcx           // lpFileName (path)
                    
                    // Save access to RDX (second parameter)
                    movl $1, %edx           // dwDesiredAccess (access) - 32-bit
                    
                    // Save share to R8 (third parameter)
                    movl $2, %r8d           // dwShareMode (share) - 32-bit
                    
                    // Set R9 to NULL for lpSecurityAttributes (fourth parameter)
                    xorq %r9, %r9           // lpSecurityAttributes = NULL
                    
                    // Allocate stack space: 32 bytes shadow + 24 bytes for 3 parameters
                    subq $$56, %rsp
                    
                    // Save disposition to stack (fifth parameter)
                    movl $3, %eax           // Get disposition
                    movl %eax, 32(%rsp)     // dwCreationDisposition
                    
                    // Save attributes to stack (sixth parameter)
                    movl $4, %eax           // Get attributes
                    movl %eax, 40(%rsp)     // dwFlagsAndAttributes
                    
                    // Set hTemplateFile to NULL (seventh parameter)
                    xorq %rax, %rax
                    movq %rax, 48(%rsp)     // hTemplateFile = NULL
                    
                    // Call CreateFileA
                    call CreateFileA
                    
                    // Store result
                    movq %rax, $5           // Store in 'handle' variable
                    
                    // Clean up stack
                    addq $$56, %rsp
                } : : "r"(path), "r"(access), "r"(share), "r"(disposition), "r"(attributes), "m"(handle)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return handle;
            };
            
            // ReadFile - Reads data from a file
            // Returns: Number of bytes actually read, or -1 on error
            def win_read(i64 handle, byte* buffer, u32 bytes_to_read) -> i32
            {
                u32 bytes_read = 0;
                u32* bytes_read_ptr = @bytes_read;
                i32 success = 0;
                
                volatile asm
                {
                    // Save handle to RCX (first parameter)
                    movq $0, %rcx           // hFile (handle)
                    
                    // Save buffer to RDX (second parameter)
                    movq $1, %rdx           // lpBuffer (buffer)
                    
                    // Save bytes_to_read to R8 (third parameter)
                    movl $2, %r8d           // nNumberOfBytesToRead
                    
                    // Save bytes_read_ptr to R9 (fourth parameter)
                    movq $3, %r9            // lpNumberOfBytesRead
                    
                    // Allocate stack space: 32 bytes shadow + 8 bytes for 5th parameter
                    subq $$40, %rsp
                    
                    // Set lpOverlapped to NULL (fifth parameter)
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     // lpOverlapped = NULL
                    
                    // Call ReadFile
                    call ReadFile
                    
                    // Store success flag
                    movl %eax, $4           // Store in 'success' variable
                    
                    // Clean up stack
                    addq $$40, %rsp
                } : : "r"(handle), "r"(buffer), "r"(bytes_to_read), "r"(bytes_read_ptr), "m"(success)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                if (success == 0)
                {
                    return -1;
                };
                
                return (i32)bytes_read;
            };
            
            // WriteFile - Writes data to a file
            // Returns: Number of bytes actually written, or -1 on error
            def win_write(i64 handle, byte* buffer, u32 bytes_to_write) -> i32
            {
                u32 bytes_written = 0;
                u32* bytes_written_ptr = @bytes_written;
                i32 success = 0;
                
                volatile asm
                {
                    // Save handle to RCX (first parameter)
                    movq $0, %rcx           // hFile (handle)
                    
                    // Save buffer to RDX (second parameter)
                    movq $1, %rdx           // lpBuffer (buffer)
                    
                    // Save bytes_to_write to R8 (third parameter)
                    movl $2, %r8d           // nNumberOfBytesToWrite
                    
                    // Save bytes_written_ptr to R9 (fourth parameter)
                    movq $3, %r9            // lpNumberOfBytesWritten
                    
                    // Allocate stack space: 32 bytes shadow + 8 bytes for 5th parameter
                    subq $$40, %rsp
                    
                    // Set lpOverlapped to NULL (fifth parameter)
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     // lpOverlapped = NULL
                    
                    // Call WriteFile
                    call WriteFile
                    
                    // Store success flag
                    movl %eax, $4           // Store in 'success' variable
                    
                    // Clean up stack
                    addq $$40, %rsp
                } : : "r"(handle), "r"(buffer), "r"(bytes_to_write), "r"(bytes_written_ptr), "m"(success)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                if (success == 0)
                {
                    return -1;
                };
                
                return (i32)bytes_written;
            };
            
            // CloseHandle - Closes a file handle
            // Returns: 1 on success, 0 on failure
            def win_close(i64 handle) -> i32
            {
                i32 result = 0;
                
                volatile asm
                {
                    // Save handle to RCX (first parameter)
                    movq $0, %rcx           // hObject (handle)
                    
                    // Allocate shadow space
                    subq $$32, %rsp
                    
                    // Call CloseHandle
                    call CloseHandle
                    
                    // Store result
                    movl %eax, $1           // Store in 'result' variable
                    
                    // Clean up stack
                    addq $$32, %rsp
                } : : "r"(handle), "m"(result)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result;
            };
            
            // HELPER FUNCTIONS - Simplified wrappers
            //
            // Open file for reading
            def open_read(byte* path) -> i64
            {
                return win_open(path, (i32)GENERIC_READ, (i32)FILE_SHARE_READ, (i32)OPEN_EXISTING, (i32)FILE_ATTRIBUTE_NORMAL);
            };
            //
            // Open file for writing (creates if doesn't exist, truncates if exists)
            def open_write(byte* path) -> i64
            {
                return win_open(path, (i32)GENERIC_WRITE, (i32)0, (i32)CREATE_ALWAYS, (i32)FILE_ATTRIBUTE_NORMAL);
            };
            //
            // Open file for appending (creates if doesn't exist)
            def open_append(byte* path) -> i64
            {
                return win_open(path, (i32)GENERIC_WRITE, (i32)FILE_SHARE_READ, (i32)OPEN_ALWAYS, (i32)FILE_ATTRIBUTE_NORMAL);
            };
            //
            // Open file for reading and writing
            def open_read_write(byte* path) -> i64
            {
                return win_open(path, (i32)GENERIC_READ_WRITE, (i32)FILE_SHARE_READ, (i32)OPEN_ALWAYS, (i32)FILE_ATTRIBUTE_NORMAL);
            };
            //
#endif; // Windows

#ifdef __LINUX__
            // File I/O functions for Linux
            // Linux syscall numbers
            /// Refactor syscall numbers to standard::system::linux ///
            #def SYS_OPEN 2;
            #def SYS_READ 0;
            #def SYS_WRITE 1;
            #def SYS_CLOSE 3;
            #def SYS_EXIT 60;
            
            // File open flags
            #def O_RDONLY 0x0000;
            #def O_WRONLY 0x0001;
            #def O_RDWR   0x0002;
            #def O_CREAT  0x0040;
            #def O_TRUNC  0x0200;
            #def O_APPEND 0x0400;
            
            // File permission modes
            #def S_IRUSR 0x0400;  // user read
            #def S_IWUSR 0x0200;  // user write
            #def S_IXUSR 0x0100;  // user execute
            #def DEFAULT_PERM (S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
            
            #def S_IRGRP 0x0040;  // group read
            #def S_IWGRP 0x0020;  // group write
            #def S_IXGRP 0x0010;  // group execute
            
            #def S_IROTH 0x0004;  // others read
            #def S_IWOTH 0x0002;  // others write
            #def S_IXOTH 0x0001;  // others execute
            
            #def INVALID_FD -1;
            
            // Open a file
            def open(byte* path, i32 flags, i32 mode) -> i64
            {
                i64 result = INVALID_FD;
                
                volatile asm
                {
                    // Linux syscall: open(const char *pathname, int flags, mode_t mode)
                    // syscall number: 2 (open)
                    // Parameters: rdi = pathname, rsi = flags, rdx = mode
                    
                    movq $$2, %rax           // syscall: open
                    movq $0, %rdi           // pathname (path)
                    movl $1, %esi           // flags (lower 32-bit)
                    movl $2, %edx           // mode (lower 32-bit)
                    syscall                 // invoke syscall
                    
                    movq %rax, $3           // Store result
                } : : "r"(path), "r"(flags), "r"(mode), "m"(result)
                  : "rax","rdi","rsi","rdx","rcx","r11","memory";
                
                return result;
            };
            
            // Read from a file
            def read(i64 fd, byte* buffer, u64 count) -> i64
            {
                i64 result = 0;
                
                volatile asm
                {
                    // Linux syscall: read(int fd, void *buf, size_t count)
                    // syscall number: 0 (read)
                    // Parameters: rdi = fd, rsi = buf, rdx = count
                    
                    movq $$0, %rax           // syscall: read
                    movq $0, %rdi           // fd
                    movq $1, %rsi           // buf (buffer)
                    movq $2, %rdx           // count
                    syscall                 // invoke syscall
                    
                    movq %rax, $3           // Store result
                } : : "r"(fd), "r"(buffer), "r"(count), "m"(result)
                  : "rax","rdi","rsi","rdx","rcx","r11","memory";
                
                return result;
            };
            
            // Write to a file
            def write(i64 fd, byte* buffer, u64 count) -> i64
            {
                i64 result = 0;
                
                volatile asm
                {
                    // Linux syscall: write(int fd, const void *buf, size_t count)
                    // syscall number: 1 (write)
                    // Parameters: rdi = fd, rsi = buf, rdx = count
                    
                    movq $$1, %rax           // syscall: write
                    movq $0, %rdi           // fd
                    movq $1, %rsi           // buf (buffer)
                    movq $2, %rdx           // count
                    syscall                 // invoke syscall
                    
                    movq %rax, $3           // Store result
                } : : "r"(fd), "r"(buffer), "r"(count), "m"(result)
                  : "rax","rdi","rsi","rdx","rcx","r11","memory";
                
                return result;
            };
            
            // Close a file
            def close(i64 fd) -> i32
            {
                i64 result = 0;
                
                volatile asm
                {
                    // Linux syscall: close(int fd)
                    // syscall number: 3 (close)
                    // Parameters: rdi = fd
                    
                    movq $$3, %rax           // syscall: close
                    movq $0, %rdi           // fd
                    syscall                 // invoke syscall
                    
                    movq %rax, $1           // Store result
                } : : "r"(fd), "m"(result)
                  : "rax","rdi","rsi","rdx","rcx","r11","memory";
                
                return (i32)result;
            };
            
            // Helper functions
            def open_read(byte* path) -> i64
            {
                return open(path, O_RDONLY, 0);
            };
            
            def open_write(byte* path) -> i64
            {
                return open(path, O_WRONLY | O_CREAT | O_TRUNC, DEFAULT_PERM);
            };
            
            def open_append(byte* path) -> i64
            {
                return open(path, O_WRONLY | O_CREAT | O_APPEND, DEFAULT_PERM);
            };
            
            def open_read_write(byte* path) -> i64
            {
                return open(path, O_RDWR | O_CREAT, DEFAULT_PERM);
            };
            
            // Read with 32-bit count (wrapper)
            def read32(i64 fd, byte* buffer, u32 count) -> i32
            {
                i64 result = read(fd, buffer, (u64)count);
                return (i32)result;
            };
            
            // Write with 32-bit count (wrapper)
            def write32(i64 fd, byte* buffer, u32 count) -> i32
            {
                i64 result = write(fd, buffer, (u64)count);
                return (i32)result;
            };
#endif;
        };
    };
};

using standard::io::console;
using standard::io::file;

#endif;