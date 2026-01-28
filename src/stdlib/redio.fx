// Input/Output Operations
//import "redsys.fx";
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#import "redsys.fx";

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
            // GENERIC
            def print(noopstr s, int len) -> void;
            def print(noopstr s) -> void;


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
                return void;
            };

            def reset_from_input() -> void
            {
                char bs = 8;
                win_print(@bs,1);
                win_print(@bs,1);
                return void;
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
                return void;
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
                return void;
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
                return void;
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
                return void;
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
                return void;
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
                    default { return void; }; // Unknown - exit() for now
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
                    default { return void; }; // Unknown - exit() for now
                };
                (void)s;
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
                    default { return void; }; // Unknown - exit() for now
                };
                return;
            };
        };      // CONSOLE //

                // FILE //
        namespace file
        {
#ifdef __WINDOWS__
            // File access modes (dwDesiredAccess)
            #def GENERIC_READ 2147483648;
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
                    // Save the input parameters to specific registers for the Windows x64 calling convention
                    // Windows x64: RCX, RDX, R8, R9, then stack
                    
                    movq $0, %rcx           // lpFileName (path) - already 64-bit
                    movl $1, %edx           // dwDesiredAccess (access) - 32-bit into lower EDX
                    movl $2, %r8d           // dwShareMode (share) - 32-bit into lower R8D
                    xorq %r9, %r9           // lpSecurityAttributes = NULL
                    
                    subq $$56, %rsp         // Shadow space (32) + 3 params (24)
                    
                    movl $3, %eax           // Get disposition into EAX
                    movl %eax, 32(%rsp)     // dwCreationDisposition on stack
                    
                    movl $4, %eax           // Get attributes into EAX
                    movl %eax, 40(%rsp)     // dwFlagsAndAttributes on stack
                    
                    xorq %rax, %rax
                    movq %rax, 48(%rsp)     // hTemplateFile = NULL
                    
                    call CreateFileA
                    
                    addq $$56, %rsp
                    movq %rax, $5           // Store handle result
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
                i64 readfile_result = 0;
                i64* readfile_result_ptr = @readfile_result;
                i64 error_code = 0;
                i64* error_code_ptr = @error_code;
                
                volatile asm
                {
                    movq $0, %r12           // Save handle to callee-saved register
                    movq %r12, %rcx         // hFile
                    movq $1, %rdx           // lpBuffer
                    movl $2, %r8d           // nNumberOfBytesToRead
                    movq $3, %r9            // lpNumberOfBytesRead pointer
                    
                    subq $$40, %rsp
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     // lpOverlapped = NULL
                    
                    call ReadFile
                    
                    addq $$40, %rsp
                    
                    movq $4, %r10           // readfile_result_ptr
                    movq %rax, (%r10)       // Store result
                    
                    // If ReadFile failed, get the error code
                    cmpq $$0, %rax
                    jne skip_error
                    
                    subq $$32, %rsp
                    call GetLastError
                    addq $$32, %rsp
                    
                    movq $5, %r10           // error_code_ptr  
                    movq %rax, (%r10)       // Store error
                    
                skip_error:
                } : : "r"(handle), "r"(buffer), "r"(bytes_to_read), "r"(bytes_read_ptr), "r"(readfile_result_ptr), "r"(error_code_ptr)
                  : "rax","rcx","rdx","r8","r9","r10","r11","r12","memory";
                
                if (readfile_result == 0)
                {
                    print("ReadFile syscall failed.\n\0");
                    // error_code now contains the Windows error code
                    // Common errors: 6 = invalid handle, 87 = invalid parameter
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
                i32* success_ptr = @success;
                
                volatile asm
                {
                    // BOOL WriteFile(
                    //   HANDLE hFile,                    // RCX - handle
                    //   LPCVOID lpBuffer,                // RDX - buffer
                    //   DWORD nNumberOfBytesToWrite,     // R8  - bytes to write
                    //   LPDWORD lpNumberOfBytesWritten,  // R9  - bytes written ptr
                    //   LPOVERLAPPED lpOverlapped        // stack+32 - NULL
                    // )
                    
                    movq $0, %rcx           // hFile (handle)
                    movq $1, %rdx           // lpBuffer (buffer)
                    movl $2, %r8d           // nNumberOfBytesToWrite
                    movq $3, %r9            // lpNumberOfBytesWritten (bytes_written ptr)
                    
                    subq $$40, %rsp         // Shadow space + 1 param
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     // lpOverlapped = NULL
                    
                    call WriteFile
                    
                    addq $$40, %rsp
                    movq $4, %rcx           // success_ptr
                    movl %eax, (%rcx)       // Store success/failure
                } : : "r"(handle), "r"(buffer), "r"(bytes_to_write), "r"(bytes_written_ptr), "r"(success_ptr)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                // Return bytes written if successful, -1 if failed
                if (success == 0)
                {
                    return -1;
                };
                
                return bytes_written;
            };
            
            // CloseHandle - Closes a file handle
            // Returns: 1 on success, 0 on failure
            def win_close(i64 handle) -> i32
            {
                i32 result = 0;
                i32* result_ptr = @result;
                
                volatile asm
                {
                    // BOOL CloseHandle(HANDLE hObject)
                    movq $0, %rcx           // hObject (handle)
                    subq $$32, %rsp         // Shadow space
                    call CloseHandle
                    addq $$32, %rsp
                    movq $1, %rcx           // result_ptr
                    movl %eax, (%rcx)       // Store result
                } : : "r"(handle), "r"(result_ptr)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result;
            };
            
            // HELPER FUNCTIONS - Simplified wrappers
            
            // Open file for reading
            def open_read(byte* path) -> i64
            {
                print("In open_read()...\n\0");
                return win_open(path, (u32)GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL);
            };
            
            // Open file for writing (creates if doesn't exist)
            def open_write(byte* path) -> i64
            {
                return win_open(path, GENERIC_WRITE, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL);
            };
            
            // Open file for reading and writing
            def open_read_write(byte* path) -> i64
            {
                return win_open(path, GENERIC_READ_WRITE, FILE_SHARE_READ, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL);
            };
#endif;

#ifdef __LINUX__
            // File I/O functions for Linux

            // File open flags (o_flags)
            #def O_RDONLY 0x0000;
            #def O_WRONLY 0x0001;
            #def O_RDWR 0x0002;
            #def O_CREAT 0x0040;
            #def O_TRUNC 0x0200;
            #def O_APPEND 0x0400;
            
            // File permission modes (mode)
            #def S_IRUSR 0x0400;
            #def S_IWUSR 0x0200;
            #def S_IXUSR 0x0100;
            #def S_IRGRP 0x0040;
            #def S_IWGRP 0x0020;
            #def S_IXGRP 0x0010;
            #def S_IROTH 0x0004;
            #def S_IWOTH 0x0002;
            #def S_IXOTH 0x0001;
            
            // Common permission combinations
            #def S_IRWXU (S_IRUSR || S_IWUSR || S_IXUSR);
            #def S_IRWXG (S_IRGRP || S_IWGRP || S_IXGRP);
            #def S_IRWXO (S_IROTH || S_IWOTH || S_IXOTH);
            #def DEFAULT_PERM (S_IRUSR || S_IWUSR || S_IRGRP || S_IROTH);
            
            // File descriptor constants
            #def INVALID_FD -1;
            
            // FORWARD DECLARATIONS
            def nix_open(byte* path, i32 flags, i32 mode) -> i64;
            def nix_read(i64 fd, byte* buffer, u64 bytes_to_read) -> i64;
            def nix_write(i64 fd, byte* buffer, u64 bytes_to_write) -> i64;
            def nix_close(i64 fd) -> i32;
            
            // IMPLEMENTATIONS
            
            // open - Opens or creates a file
            // Returns: File descriptor (i64), or -1 on failure
            // Linux syscall: open(const char *pathname, int flags, mode_t mode)
            // syscall number: 2 (open)
            def nix_open(byte* path, i32 flags, i32 mode) -> i64
            {
                i64 result = INVALID_FD;
                
                volatile asm
                {
                    // Linux x64 calling convention for syscalls:
                    // syscall number: rax
                    // arg1: rdi, arg2: rsi, arg3: rdx, arg4: r10, arg5: r8, arg6: r9
                    
                    movq $$2, %rax           // syscall number: open = 2
                    movq $0, %rdi           // pathname (path)
                    movl $1, %esi           // flags (lower 32-bit)
                    movl $2, %edx           // mode (lower 32-bit)
                    syscall                 // invoke syscall
                    
                    movq %rax, $3           // Store result
                } : : "r"(path), "r"(flags), "r"(mode), "m"(result)
                  : "rax","rdi","rsi","rdx","r10","r8","r9","r11","rcx","memory";
                
                return result;
            };
            
            // read - Reads data from a file
            // Returns: Number of bytes actually read, or -1 on error
            // Linux syscall: read(int fd, void *buf, size_t count)
            // syscall number: 0 (read)
            def nix_read(i64 fd, byte* buffer, u64 bytes_to_read) -> i64
            {
                i64 result = 0;
                
                volatile asm
                {
                    movq $$0, %rax           // syscall number: read = 0
                    movq $0, %rdi           // fd
                    movq $1, %rsi           // buf (buffer)
                    movq $2, %rdx           // count (bytes_to_read)
                    syscall                 // invoke syscall
                    
                    movq %rax, $3           // Store result
                } : : "r"(fd), "r"(buffer), "r"(bytes_to_read), "m"(result)
                  : "rax","rdi","rsi","rdx","r10","r8","r9","r11","rcx","memory";
                
                return result;
            };
            
            // write - Writes data to a file
            // Returns: Number of bytes actually written, or -1 on error
            // Linux syscall: write(int fd, const void *buf, size_t count)
            // syscall number: 1 (write)
            def nix_write(i64 fd, byte* buffer, u64 bytes_to_write) -> i64
            {
                i64 result = 0;
                
                volatile asm
                {
                    movq $$1, %rax           // syscall number: write = 1
                    movq $0, %rdi           // fd
                    movq $1, %rsi           // buf (buffer)
                    movq $2, %rdx           // count (bytes_to_write)
                    syscall                 // invoke syscall
                    
                    movq %rax, $3           // Store result
                } : : "r"(fd), "r"(buffer), "r"(bytes_to_write), "m"(result)
                  : "rax","rdi","rsi","rdx","r10","r8","r9","r11","rcx","memory";
                
                return result;
            };
            
            // close - Closes a file descriptor
            // Returns: 0 on success, -1 on failure
            // Linux syscall: close(int fd)
            // syscall number: 3 (close)
            def nix_close(i64 fd) -> i32
            {
                i64 result = 0;
                
                volatile asm
                {
                    movq $$3, %rax           // syscall number: close = 3
                    movq $0, %rdi           // fd
                    syscall                 // invoke syscall
                    
                    movq %rax, $1           // Store result
                } : : "r"(fd), "m"(result)
                  : "rax","rdi","rsi","rdx","r10","r8","r9","r11","rcx","memory";
                
                return (i32)result;
            };
            
            // HELPER FUNCTIONS - Simplified wrappers to match Windows API
            
            // Open file for reading
            def open_read(byte* path) -> i64
            {
                return nix_open(path, O_RDONLY, 0);
            };
            
            // Open file for writing (creates if doesn't exist, truncates if exists)
            def open_write(byte* path) -> i64
            {
                return nix_open(path, O_WRONLY || O_CREAT || O_TRUNC, DEFAULT_PERM);
            };
            
            // Open file for reading and writing
            def open_read_write(byte* path) -> i64
            {
                return nix_open(path, O_RDWR || O_CREAT, DEFAULT_PERM);
            };
            
            // Read from file (wrapper with 32-bit count)
            def read(i64 fd, byte* buffer, u32 bytes_to_read) -> i32
            {
                i64 result = nix_read(fd, buffer, (u64)bytes_to_read);
                return (i32)result;
            };
            
            // Write to file (wrapper with 32-bit count)
            def write(i64 fd, byte* buffer, u32 bytes_to_write) -> i32
            {
                i64 result = nix_write(fd, buffer, (u64)bytes_to_write);
                return (i32)result;
            };
            
            // Close file
            def close(i64 fd) -> i32
            {
                return nix_close(fd);
            };
#endif;
        };
    };
};

using standard::io::console;
using standard::io::file;