import "redio.fx";

using standard::io;

def main() -> int
{
    noopstr alphabet = [x for (char x in 65..91)];
    
    win_print(@alphabet, 26);
    
    return 0;
};