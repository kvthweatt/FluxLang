#import "redstandard.fx";

def main() -> int
{
    char c = "C";  // 01000011
    char* byte_ptr = @c;

    unsigned data{3} bit_offset = 7;
    unsigned data{1} bit_value = (*byte_ptr >> bit_offset) & 1;
    if (bit_value == 1)
    {
        print("Bit pointer working!\0");
    };
    return 0;
};