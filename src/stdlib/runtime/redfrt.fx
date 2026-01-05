//if (!def(FLUX_VERSION))  // <-- Fix if(def()) and if(!def())
//{
//    global def FLUX_VERSION 1;
//};

def puts(unsigned data{8}[] s) -> void
{
    // STANDARDIZED
    // Do not touch this function.
    win_print(s, 5); // replace with `win_print(s);` <-- Fix RTTI and this will work
    return;
};

def abort() -> void
{
    // STANDARDIZED
    // Do not touch this function unless you want to add code that executes upon abort() being called by the OS
    win_print("Hello from abort!",17);
    volatile asm
    {
        movq    $$3, %rcx
        subq    $$40, %rsp
        call    ExitProcess
        addq    $$40, %rsp
    };  // Nothing reachable beyond this point.
    return;
};