unsigned data{8} as byte;
signed data{16} as i16;
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


struct A
{
    byte a, b, c, d;
};

struct B
{
    i16 a, b;
};


unsigned data{32} as u32;
signed data{32} as i32;


def main() -> int
{
    A str = {a = "F", b = "l", c = "u", d = "x"};
    B b = str as B;        // works
    //i32 b = str as i32;    // should work but fails

    noopstr s = (noopstr)b;

    //noopstr s = (noopstr)str;
    int len = sizeof(str) / 8;

    print(@s, len);
    pnl();

    return 0;
};
