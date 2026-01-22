#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_RUNTIME
#def FLUX_RUNTIME 1;
#endif;

def _start() -> int;
def main() -> int;
def exit() -> void;

def _start() -> int
{
    return main();
};

def FRTStartup() -> void
{
    //CURRENT_OS = get_os();
    int return_code;
    switch (CURRENT_OS)
    {
        case (1)
        {
            return_code = main();
        }
        case (2)
        {
            return_code = _start();
        }
        case (3)
        {
            return_code = _start();
        }
        default { exit(); };
    };
    if (return_code != 0)
    {
        // Handle error
    };
    exit();  // Should pass return_code
    return void;
};

def exit() -> void
{
    switch (CURRENT_OS)
    {
        case (1)
        {
            return void;
        }
        case (2)
        {
            volatile asm
            {
                movq $$60, %rax          // sys_exit
                movq $$0, %rdi           // exit code 0
                syscall
            } : : : "rax", "rdi";
        }
        case (3)
        {
            volatile asm
            {
                movq $$60, %rax          // sys_exit
                movq $$0, %rdi           // exit code 0
                syscall
            } : : : "rax", "rdi";
        }
        default { return void; };
    };
    
    return void;
};