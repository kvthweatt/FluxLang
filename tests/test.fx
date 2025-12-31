
import "redstandard.fx";

using standard::io;

struct T {
    noopstr a, b;
};

def main() -> int {
    
    T newt = {a = "Test", b = "ing!"};

    win_print(newt.a, 4);
    return 0;
};