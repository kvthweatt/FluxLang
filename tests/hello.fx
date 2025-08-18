// Windows x64 Hello World using volatile inline asm in AT&T syntax
// No CRT calls; directly calls Kernel32!GetStdHandle and Kernel32!WriteFile

def main() -> int
{
    // "Hello, World!\r\n" is 15 bytes (no NUL required for WriteFile)
    unsigned data{8}[15] msg = "Hello, World!";

    unsigned data{8}* pmsg = @msg;      // pointer to buffer
    int len = sizeof(msg) / 8;          // sizeof returns bits in reduced spec

    // AT&T inline assembly (volatile). Inputs: $0 == pmsg, $1 == len
    volatile asm
    {
        // HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE = -11)
        movq $$-11, %rcx
        subq $$32, %rsp
        call GetStdHandle
        addq $$32, %rsp

        // BOOL ok = WriteFile(h, pmsg, len, NULL, NULL)
        movq %rax, %rcx         // RCX = handle (from GetStdHandle)
        movq $0, %rdx           // RDX = lpBuffer (operand 0 = pmsg)
        movl $1, %r8d           // R8D = nNumberOfBytesToWrite (operand 1 = len, DWORD)
        xorq %r9, %r9           // R9 = lpNumberOfBytesWritten = NULL
        subq $$40, %rsp          // 32 bytes shadow + 8 for 5th arg slot
        movq %r9, 32(%rsp)      // *(rsp+32) = lpOverlapped = NULL
        call WriteFile
        addq $$40, %rsp
    } : : "r"(pmsg), "r"(len) : "rax","rcx","rdx","r8","r9","r10","r11","memory";

    return 0;
};