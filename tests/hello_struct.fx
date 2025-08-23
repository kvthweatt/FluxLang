unsigned data{8} as byte;
byte[] as noopstr;

noopstr nl = "\n";

def print(unsigned data{8}* msg, int len) -> void
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


struct myStru
{
    noopstr hw;
    int len;
};

def main() -> int
{
    noopstr str = "Hello World!";
    int len = sizeof(str) / 8;

    myStru s = {hw = @"Hello World!", len = 12};

    //print(@s.hw, s.len);
    
    //for (int x = 0; x < 20; x++)
    //{
    //    print(@str, len);
    //    pnl();
    //};
    return 0;
};
