import "standard.fx";

def test_volatile_only() -> void {
    volatile asm {
        nop
    };
};

def main() -> int {
    test_volatile_only();
    return 0;
};
