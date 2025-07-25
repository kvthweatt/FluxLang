// System Interaction

import "types.fx";

namespace standard
{
    namespace system
    {
        // Execute shell command
        def shell(string command) -> i32
        {
            i32 result;
            volatile asm
            {
                mov eax, 0x2E   ; sys_execve
                mov ebx, command
                xor ecx, ecx    ; no args
                xor edx, edx    ; no env
                int 0x80
                mov result, eax
            };
            return result;
        };
        
        // Exit program
        def exit(i32 code) -> void
        {
            volatile asm
            {
                mov eax, 1      ; sys_exit
                mov ebx, code
                int 0x80
            };
            return void;
        };
        
        // Get environment variable
        def getenv(string name) -> string
        {
            // Implementation would need to interface with libc
            // After we create libfx, replace interface
            return "";
        };
    };
};