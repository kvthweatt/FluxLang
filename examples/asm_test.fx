asm {
"mov $1, %rax\n"     // syscall number for write
"mov $1, %rdi\n"     // file descriptor (stdout)
"lea message(%rip), %rsi\n"  // message address
"mov $13, %rdx\n"    // message length
"syscall\n"
"ret"
};

def main() -> int
{
    return 0;
};