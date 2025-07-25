// Input/Output Operations

import "types.fx";

namespace standard
{
    namespace io
    {
        global
        {
            // Print to standard output
            def print(string s) -> void
            {
                volatile asm
                {
                    mov eax, 4         ; sys_write
                    mov ebx, 1         ; stdout
                    mov ecx, s         ; string pointer
                    mov edx, sizeof(s) ; length
                    int 0x80           ; syscall
                };
            };
            
            // Print with newline
            def println(string s) -> void
            {
                print(f"{s}\n");
            };
            
            // Read line from standard input
            def readline() -> string
            {
                unsigned data{8}[256] as buffer;
                buffer buf;
                
                volatile asm
                {
                    mov eax, 3      ; sys_read
                    mov ebx, 0      ; stdin
                    mov ecx, buf    ; buffer pointer
                    mov edx, 256    ; max length
                    int 0x80        ; syscall
                };
                
                // Find newline and null-terminate
                for (u32 i = 0; i < 256; i++)
                {
                    if (buffer[i] == '\n')
                    {
                        buffer[i] = 0;
                        break;
                    };
                };
                
                return buffer;
            };
        };
    };
};