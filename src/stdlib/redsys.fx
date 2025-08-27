// OS Detection Library

import "redtypes.fx";

using standard::types;

const int CURRENT_OS;

namespace standard
{
    namespace system
    {
        // OS Constants
        const int OS_UNKNOWN = 0;
        const int OS_WINDOWS = 1;
        const int OS_LINUX = 2;
        const int OS_MACOS = 3;

        // OS Detection function using inline assembly
        def get_os() -> int
        {
            volatile int result = OS_UNKNOWN;
            
            volatile asm 
            {
                // Try Windows detection first - GetVersion API call
                subq $32, %rsp           // Shadow space for Windows calling convention
                call GetVersion          // Windows API call
                addq $32, %rsp
                
                // If GetVersion succeeded, we're on Windows
                testl %eax, %eax
                jz try_linux
                
                movl $1, %eax            // OS_WINDOWS
                jmp detection_done
                
            try_linux:
                // Try Linux - sys_uname syscall (syscall 63)
                movq $63, %rax           // sys_uname
                movq $0, %rdi            // NULL buffer (we don't need the data)
                syscall
                
                // Linux syscall returns 0 on success
                cmpq $0, %rax
                jne try_macos
                
                movl $2, %eax            // OS_LINUX
                jmp detection_done
                
            try_macos:
                // Try macOS - getpid syscall (different number than Linux)
                movq $20, %rax           // macOS getpid syscall number
                syscall
                
                // getpid returns positive PID on success
                cmpq $0, %rax
                jle unknown_os
                
                movl $3, %eax            // OS_MACOS
                jmp detection_done
                
            unknown_os:
                movl $0, %eax            // OS_UNKNOWN
                
            detection_done:
                nop
                
            } : "=a"(result) : : "rcx", "rdx", "rdi", "rsi", "r8", "r9", "r10", "r11", "memory";
            
            return result;
        };
    };
};

CURRENT_OS = get_os();