// loop_counter.fx
// Prints numbers 0..999,999 (inclusive) using WriteFile in inline x64 assembly (AT&T syntax)
// Handle to STD_OUTPUT_HANDLE is fetched once; WriteFile assembly is inside the loop

// NOTE: This example follows the same conventions used in tests/hello.fx
//       Buffer size is 32 bytes which is more than enough for the largest decimal
//       representation ("1000000" -> 7 digits) plus CRLF.

def main() -> int
{
    // Obtain console handle once
    unsigned data{64} stdout_handle;

    volatile asm
    {
        movq $$-11, %rcx          // STD_OUTPUT_HANDLE = -11
        subq $$32, %rsp           // shadow space for Win64 ABI
        call GetStdHandle         // RAX = handle
        addq $$32, %rsp
    } : "=a"(stdout_handle) : : "rcx","r10","r11","memory";

    // Reserve buffer outside the loop (32 bytes is plenty)
    unsigned data{8}[32] buf;

    for (int i = 0; i < 1000000; i++)
    {
        // Convert i to ASCII (decimal) in reverse inside buf[0..29]
        int n = i;
        int idx = 29;                         // current write position (digits go backwards)

        // Append CRLF at the end of the buffer positions 30 & 31
        buf[30] = (unsigned data{8})13;       // '\r'
        buf[31] = (unsigned data{8})10;       // '\n'

        do
        {
            int digit = n % 10;
            buf[idx] = (unsigned data{8})(digit + 48); // '0' == 48
            idx -= 1;
            n = n / 10;
        } while (n > 0);

        unsigned data{8}* pmsg = @buf[idx + 1];        // pointer to first digit
        int len = (29 - idx) + 2;                      // digits + CRLF (2 bytes)

        // Inline assembly to write buffer to stdout
        volatile asm
        {
            movq $2, %rcx          // RCX = handle (operand 2)
            movq $0, %rdx          // RDX = lpBuffer (operand 0)
            movl $1, %r8d          // R8D = nNumberOfBytesToWrite (operand 1)
            xorq %r9, %r9          // R9  = lpNumberOfBytesWritten = NULL
            subq $$40, %rsp        // shadow + 5th arg slot
            movq %r9, 32(%rsp)     // lpOverlapped NULL on stack
            call WriteFile
            addq $$40, %rsp
        } : : "r"(pmsg), "r"(len), "r"(stdout_handle) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
    };

    return 0;
};

