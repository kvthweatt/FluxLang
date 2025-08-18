import "standard.fx";

// Test extended inline assembly with output operands
def test_extended_output() -> int {
    int result;
    asm {
        mov %1, %0
    } : "=r" (result) : "r" (42);
    
    return result;
};

// Test extended inline assembly with input operands
def test_extended_input() -> void {
    int value = 100;
    asm {
        mov %0, %%eax
    } : : "r" (value);
};

// Test extended inline assembly with output, input, and clobber list
def test_extended_full() -> int {
    int input = 10;
    int result;
    
    asm {
        mov %1, %0
        add $5, %0
    } : "=r" (result) : "r" (input) : "memory";
    
    return result;
};

// Test volatile extended inline assembly
def test_volatile_extended() -> void {
    int value = 123;
    volatile asm {
        nop
        mov %0, %%eax
        nop
    } : : "r" (value) : "eax", "memory";
};

// Main function to test all extended asm features
def main() -> int {
    test_extended_output();
    test_extended_input();
    test_extended_full();
    test_volatile_extended();
    return 0;
};
