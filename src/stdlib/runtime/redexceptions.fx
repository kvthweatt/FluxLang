// Flux Exception Handling Runtime

#ifndef FLUX_STANDARD_EXCEPTIONS
#def FLUX_STANDARD_EXCEPTIONS 1


def setjmp(char* env) -> int
{
    i64* buf = (i64*)env;
    
    volatile asm
    {
        // Save rbp
        movq %rbp, ($0)
        
        // Save return address
        movq (%rsp), %rax
        movq %rax, 8($0)
        
        // Save rsp
        movq %rsp, 16($0)
        
        // Save rbx
        movq %rbx, 24($0)
        
        // Save r12
        movq %r12, 32($0)
        
        // Return 0
        xorl %eax, %eax
    } : : "r"(buf) : "rax", "memory";
    
    return 0;
};

def __intrinsic_setjmp(char* env) -> int
{
    return setjmp(env);
};

def longjmp(char* env, int val) -> void
{
    i64* buf = (i64*)env;
    
    volatile asm
    {
        // Restore r12
        movq 32($0), %r12
        
        // Restore rbx
        movq 24($0), %rbx
        
        // Restore rsp
        movq 16($0), %rsp
        
        // Restore rbp
        movq ($0), %rbp
        
        // Set return value
        movl $1, %eax
        
        // Jump to return address
        movq 8($0), %rcx
        jmp *%rcx
    } : : "r"(buf), "r"(val) : "rax", "rbx", "rcx", "r12", "rsp", "rbp", "memory";

    return;
};


#endif; // FLUX_STANDARD_EXCEPTIONS