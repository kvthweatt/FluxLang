unsigned data{8} as byte;
byte[] as noopstr;
noopstr nl = "\n";

def print(byte* msg, int len) -> void
{
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

def peek(byte* x) -> byte
{
    return *x;
};

def main() -> int
{
    noopstr s = "TEST";
    noopstr q = "ING";

    s += q;

    s = s + s;

    noopstr x = s[0..3];
    print(@x,4);
    pnl();

    int len = sizeof(s) / 8;
    //noopstr x = s + q;              // Fails: %".10" = add [4 x i8]* %"s", %"q"
    //noopstr x = s[0..3] + q[0..3];  // Fails: {i32,i32}* ???

    print(@s,14);
    pnl();

    //for (byte x = 0; x <= len; x++)
    //{
    //    byte b = peek(@s[x]);
    //    //byte* pb = @b;
    //    print(@b,1);
    //};
    //pnl();

    return 0;
};