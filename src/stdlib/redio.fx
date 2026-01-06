// Input/Output Operations

import "redtypes.fx";

using standard::types;

namespace standard
{
    namespace io
    {
        // Console I/O
        namespace console
        {
    		// INPUT FORWARD DECLARATIONS
            def win_input(byte[] buffer, int max_len) -> int;
            def win_readline(byte[] buffer, int max_len) -> int;

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
    return bytes_read;
};



    		// OUTPUT FORWARD DECLARATIONS
            def win_print(byte* msg, int x) -> void;
            def wpnl() -> void;
            def nix_print(byte* msg, int x) -> void;
            def npnl() -> void;
            def mac_print(byte* msg, int x) -> void;
            def mpnl() -> void;
    		def print(noopstr s) -> void;

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

    		def print(noopstr s) -> void
    		{
    			// GENERIC PRINT
    			//
    			// Designed to use system.fx to determine which OS we're on
    			// and call the appropriate print function.
    			if (def(WINDOWS))
                {
    				int len = sizeof(s) / 8; // Leave as-is, will work once RTTI is functional 
    				win_print(@s, len);      //// and passing type information across function calls & returns
    			};
                if (def(LINUX))
                {
                    int len = sizeof(s) / 8;
                    nix_print(@s, len);
                };
                if (def(MAC))
                {
                    int len = sizeof(s) / 8;
                    mac_print(@s, len);
                };
    			(void)s;
    			return;
    		};
        };
    };
};