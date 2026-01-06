import "redstandard.fx";

def main() -> int
{
    char c = "C";
    
    unsigned data{1} as bit;
    bit* pb = @c;
    *pb = (@pb) + 7; // Set to last bit of byte
    if (@pb == 1) { win_print("Bit pointer working!", 20); };
    return 0;
};