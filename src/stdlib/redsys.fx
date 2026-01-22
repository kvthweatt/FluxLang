// OS Detection Library
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#import "redtypes.fx";

global const int OS_UNKNOWN = 0;
global const int OS_WINDOWS = 1;
global const int OS_LINUX = 2;
global const int OS_MACOS = 3;

namespace standard
{
    namespace system
    {
        // OS Detection function using inline assembly
        def get_os() -> int
        {
            i32 result = 0;
            
            volatile asm
            {
                // Try Linux first
                movq $$1, %rax      // sys_write syscall number
                movq $$-1, %rdi     // invalid fd
                movq $$0, %rsi      // null buffer
                movq $$0, %rdx      // zero length
                syscall
                
                // Linux returns -EBADF (-9), others crash or return different
                cmpq $$-9, %rax
                jne not_linux
                
                movl $$2, %ebx   // return 2
                jmp done
                
            not_windows:
                // Try Linux - check if /proc filesystem signature exists
                // This is hard in pure asm, so check for Linux syscall convention
                movq $$1, %rax      // sys_write syscall number
                movq $$-1, %rdi     // invalid fd
                movq $$0, %rsi      // null buffer
                movq $$0, %rdx      // zero length
                syscall
                
                // Linux returns -EBADF (-9), others crash or return different
                cmpq $$-9, %rax
                jne not_linux
                
                movl $$2, %ebx   // return 2
                jmp done
                
            not_linux:
                movq %gs:0x30, %rax
                testq %rax, %rax
                jz not_windows
                
                // If we got here, likely Windows
                movl $$1, %ebx   // return 1
                jmp done
                
            done:
                movl %ebx, %eax
                movl %eax, $0    // return 0
            } : "=r"(result) : : "rax", "rbx", "rcx", "rdx", "rdi", "rsi", "memory";
            
            return result;
        };
    };
};

using standard::system;