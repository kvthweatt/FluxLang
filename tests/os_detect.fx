import "redio.fx";

using standard::io;

def main() -> int
{
    int result;

    volatile asm 
    {
        // Try Windows detection first - GetVersion API call
        subq $$32, %rsp           // Shadow space for Windows calling convention
        call GetVersion          // Windows API call
        addq $$32, %rsp
        
        // If GetVersion succeeded, we're on Windows
        testl %eax, %eax
        jz try_linux
        
        movl $1, %ebx            // OS_WINDOWS
        jmp detection_done
        
    try_linux:
        // Try Linux - sys_uname syscall (syscall 63)
        movl $$63, %eax           // sys_uname (using 32-bit register)
        movl $$0, %edi            // NULL buffer (using 32-bit register)
        syscall
        
        // Linux syscall returns 0 on success
        cmpl $0, %eax
        jne try_macos
        
        movl $2, %ebx            // OS_LINUX
        jmp detection_done
        
    try_macos:
        // Try macOS - getpid syscall (different number than Linux)
        movl $$20, %eax           // macOS getpid syscall number (using 32-bit register)
        syscall
        
        // getpid returns positive PID on success
        cmpl $$0, %eax
        jle unknown_os
        
        movl $3, %ebx            // OS_MACOS
        jmp detection_done
        
    unknown_os:
        movl $0, %ebx            // OS_UNKNOWN
        
    detection_done:
        movl %ebx, %0            // Store result to memory operand 0
    } : "=m"(result) : : "eax", "ebx", "ecx", "edx", "edi", "esi", "r8d", "r9d", "r10d", "r11d", "memory";

    if (result == 1)
    {
        noopstr x = "HI!";
        win_print(@x,3);
    };
	return 0;
};