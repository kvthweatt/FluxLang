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

            // INPUT DEFINITIONS

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

        // File I/O
        namespace file
        {
        };
    };
};