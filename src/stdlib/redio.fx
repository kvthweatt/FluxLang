// Input/Output Operations
//import "redsys.fx";
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#import "redtypes.fx";
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
#endif;
#ifdef __LINUX__
            def nix_input(byte[] buffer, int max_len) -> int;
#endif;
#ifdef __MACOS__
            def mac_input(byte[] buffer, int max_len) -> int;
#endif;
            def input(byte[] buffer, int max_len) -> int;
            //def input(byte[] msg) -> byte[]; <-- overloading not working correctly.

            // OUTPUT FORWARD DECLARATIONS
#ifdef __WINDOWS__
            def win_print(byte* msg, int x) -> void;
            def wpnl() -> void;
#endif;
#ifdef __LINUX__
            def nix_print(byte* msg, int x) -> void;
            def npnl() -> void;
#endif;
#ifdef __MACOS__
            def mac_print(byte* msg, int x) -> void;
            def mpnl() -> void;
#endif;
            def print(noopstr s, int len) -> void;
#ifdef __WINDOWS__
            def reset_from_input() -> void;

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

            def input(byte[] buffer, int max_len) -> int
            {
                switch (1)
                {
                    case (1)
                    {
                        return win_input(buffer, max_len);
                    }
                    default
                    { return 0; };
                };
                return 0;
            };

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

            def wpnl() -> void
            {
                win_print(@nl,1);
                return void;
            };

            def reset_from_input() -> void
            {
                char bs = 8;
                win_print(@bs,1);
                win_print(@bs,1);
                return void;
            };
#endif; // Windows
#ifdef __LINUX__
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
                    
                    movq $$1, %rax           // syscall number: write = 1
                    movq $$1, %rdi           // fd = STDOUT_FILENO = 1
                    movq $0, %rsi           // buf = msg
                    movq $1, %rdx           // count = count (64-bit)
                    syscall                 // invoke syscall
                } : : "r"(msg), "r"(count) : "rax","rdi","rsi","rdx","rcx","r8","r9","r10","r11","memory";
                return void;
            };
#endif;

#ifdef __MACOS__
            def mac_print(byte* msg, int x) -> void
            {

            };
#endif;

    		def print(noopstr s, int len) -> void
    		{
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
        };

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
            
            // Invalid handle value
            #def INVALID_HANDLE_VALUE -1;
       
            // FORWARD DECLARATIONS
            def win_open(byte* path, u32 access, u32 share, u32 disposition, u32 attributes) -> i64;
            def win_read(i64 handle, byte[] buffer, u32 bytes_to_read) -> i32;
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
                    // HANDLE CreateFileA(
                    //   LPCSTR lpFileName,                // RCX - path
                    //   DWORD dwDesiredAccess,            // RDX - access mode
                    //   DWORD dwShareMode,                // R8  - share mode
                    //   LPSECURITY_ATTRIBUTES lpSA,       // R9  - security (NULL)
                    //   DWORD dwCreationDisposition,      // stack+32 - creation mode
                    //   DWORD dwFlagsAndAttributes,       // stack+40 - attributes
                    //   HANDLE hTemplateFile              // stack+48 - template (NULL)
                    // )
                    
                    movq $0, %rcx           // lpFileName (path)
                    movl $1, %edx           // dwDesiredAccess (access)
                    movl $2, %r8d           // dwShareMode (share)
                    xorq %r9, %r9           // lpSecurityAttributes = NULL
                    
                    subq $$56, %rsp         // Shadow space (32) + 3 params (24)
                    movl $3, %eax           // disposition
                    movl %eax, 32(%rsp)     // dwCreationDisposition
                    movl $4, %eax           // attributes
                    movl %eax, 40(%rsp)     // dwFlagsAndAttributes
                    xorq %rax, %rax
                    movq %rax, 48(%rsp)     // hTemplateFile = NULL
                    
                    call CreateFileA
                    
                    addq $$56, %rsp
                    movq %rax, $5           // Store handle result
                } : : "r"(path), "r"(access), "r"(share), "r"(disposition), "r"(attributes), "r"(@handle)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return handle;
            };
            
            // ReadFile - Reads data from a file
            // Returns: Number of bytes actually read, or -1 on error
            def win_read(i64 handle, byte[] buffer, u32 bytes_to_read) -> i32
            {
                u32 bytes_read = 0;
                u32* bytes_read_ptr = @bytes_read;
                i32 success = 0;
                i32* success_ptr = @success;
                
                volatile asm
                {
                    // BOOL ReadFile(
                    //   HANDLE hFile,                    // RCX - handle
                    //   LPVOID lpBuffer,                 // RDX - buffer
                    //   DWORD nNumberOfBytesToRead,      // R8  - bytes to read
                    //   LPDWORD lpNumberOfBytesRead,     // R9  - bytes read ptr
                    //   LPOVERLAPPED lpOverlapped        // stack+32 - NULL
                    // )
                    
                    movq $0, %rcx           // hFile (handle)
                    movq $1, %rdx           // lpBuffer (buffer)
                    movl $2, %r8d           // nNumberOfBytesToRead
                    movq $3, %r9            // lpNumberOfBytesRead (bytes_read ptr)
                    
                    subq $$40, %rsp         // Shadow space + 1 param
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     // lpOverlapped = NULL
                    
                    call ReadFile
                    
                    addq $$40, %rsp
                    movq $4, %rcx           // success_ptr
                    movl %eax, (%rcx)       // Store success/failure
                } : : "r"(handle), "r"(buffer), "r"(bytes_to_read), "r"(bytes_read_ptr), "r"(success_ptr)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                // Return bytes read if successful, -1 if failed
                if (success == 0)
                {
                    return -1;
                };
                
                return bytes_read;
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
                return win_open(path, GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL);
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
        };
    };
};

using standard::io::console;
//using standard::io::file;