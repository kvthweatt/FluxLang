def main() -> int
{
    int x = 42;
    
    volatile asm
    {
        movl $0, %eax
    } : : "r"(x) : "eax";
    
    return 0;
};
