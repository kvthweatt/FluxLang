import "standard.fx";

def test_simple_asm() -> void {
    asm {
        nop
    };
};

def test_volatile_asm() -> void {
    volatile asm {
        nop
        nop
    };
};

def main() -> int {
    test_simple_asm();
    test_volatile_asm();
    return 0;
};
