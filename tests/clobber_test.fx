import "standard.fx";

def test_clobber_only() -> void {
    asm {
        nop
    } : : : "memory";
};

def test_input_and_clobber() -> void {
    int value = 42;
    asm {
        mov %0, %%eax
    } : : "r" (value) : "eax", "memory";
};

def main() -> int {
    test_clobber_only();
    test_input_and_clobber();
    return 0;
};
