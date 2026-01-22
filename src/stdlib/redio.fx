// Input/Output Operations
//import "redsys.fx";
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

import "redtypes.fx";

namespace standard
{
    namespace io
    {
        // Console I/O
        namespace console
        {
    		// INPUT FORWARD DECLARATIONS
            def win_input(byte[] buffer, int max_len) -> int;
            def nix_input(byte[] buffer, int max_len) -> int;
            def mac_input(byte[] buffer, int max_len) -> int;
            def input(byte[] buffer, int max_len) -> int;
            //def input(byte[] msg) -> byte[]; <-- overloading not working correctly.

            // OUTPUT FORWARD DECLARATIONS
            def win_print(byte* msg, int x) -> void;
            def wpnl() -> void;
            def nix_print(byte* msg, int x) -> void;
            def npnl() -> void;
            def mac_print(byte* msg, int x) -> void;
            def mpnl() -> void;
            def print(noopstr s, int len) -> void;
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
                switch (CURRENT_OS)
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

            def mac_print(byte* msg, int x) -> void
            {

            };

    		def print(noopstr s, int len) -> void
    		{
    			// GENERIC PRINT
    			//
    			// Designed to use sys.fx to determine which OS we're on
    			// and call the appropriate print function.
                switch (CURRENT_OS)
                {
                    case (1) // Windows
                    {
                        win_print(@s, len);
                    }
                    case (2) // Linux
                    {
                        nix_print(@s, len);
                    }
                    case (3) // Darwin (Mac)
                    {
                        mac_print(@s, len);
                    }
                    default { return void; }; // Unknown - exit() for now
                };
    			(void)s;
    			return;
    		};
        };
    };
};

using standard::io::console;