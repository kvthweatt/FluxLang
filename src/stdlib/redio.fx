// Input/Output Operations

import "redtypes.fx";

using standard::types;

namespace standard
{
    namespace io
    {
		// INPUT

		
		// OUTPUT
        def win_print(byte[] msg, int x) -> void;
        def wpnl() -> void;
        def nix_print(byte* msg, int x) -> void;
        def npnl() -> void;
        def mac_print(byte* msg, int x) -> void;
        def mpnl() -> void;
		def print(noopstr s) -> void;

        def win_print(byte[] msg, int x) -> void
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
			if (def(WINDOWS)) {
				int len = sizeof(*s) / 8;
				win_print(@s, len);
			};
			(void)s; // Linker complains but this is supposed to be here.
			return;
		};
    };
};