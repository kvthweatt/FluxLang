#ifdef __DOS__
// WE'RE IN DOS MODE!
#ifdef __MSDOS__
// SPECIFICALLY MS-DOS

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

def strlen(byte* s) -> int
{
    int len;
    len = 0;
    byte* ps;
    ps = s;
    
    while (*ps != 0)
    {
        len = len + 1;
        ps = ps + 1;
    };
    
    return len;
};

def print(byte* c) -> void
{
    u16 len = strlen(c);

    volatile asm
    {
        pushw %ds
        pushw %dx
        movb %ah, 0x09
        movw %dx, %cx
        int $$0x21
        popw %dx
        popw %ds
    } : : "r"(c) : "ax","cx","dx","ds","memory","cc";
    
    return void;
};

#endif;
#endif;