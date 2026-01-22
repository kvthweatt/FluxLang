#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_RUNTIME
#def FLUX_RUNTIME 1;
#endif

def main() -> int;

#ifdef __LINUX__
def _start() -> int;
def exit() -> void;

def _start() -> int
{
    return main();
};
def exit() -> void
{
    volatile asm
    {
        movq $$60, %rax          // sys_exit
        movq $$0, %rdi           // exit code 0
        syscall
    } : : : "rax", "rdi";
};
#endif; // Linux

#ifdef FLUX_RUNTIME
def FRTStartup() -> void
{
    int return_code;
    switch (CURRENT_OS)
    {
        case (1)
        {
            return_code = main();
        }
        #ifdef __LINUX__
        case (2)
        {
            return_code = _start();
        }
        #endif;
        #ifdef __MACOS__
        case (3)
        {
            return_code = _start();
        }
        #endif;
        default
        {
            #ifdef __LINUX__
            exit();
            #endif;
            return;
        };
    };
    if (return_code != 0)
    {
        // Handle error
    };
    #ifdef __LINUX__
    exit();  // Should pass return_code
    #endif;
    return void;
};
#endif;