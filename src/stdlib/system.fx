// System Interaction

compt
{
    if (!def(FLUX_STANDARD_TYPES))
    {
        global import "types.fx";
    };
    if (!def (FLUX_STANDARD_COLLECTIONS))
    {
        global import "collections.fx";
    };
};

namespace standard
{
    // Made constant to prevent modification after import
    const namespace system
    {
        // Need to use `system.fx` to determine platform at compile time, and create a macro flag which we will switch over for the proper shell implementation.
        // Execute shell command example
        def shell(string command) -> i32
        {
            i32 result;
            volatile asm
            {
                mov eax, 0x2E   ; sys_execve
                mov ebx, command; 
                xor ecx, ecx    ; no args
                xor edx, edx    ; no env
                int 0x80        ; 
                mov result, eax ; get result
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
            // Would need `fio.fx` implementation to be capable of file input/output
            return "";
        };
    };
};