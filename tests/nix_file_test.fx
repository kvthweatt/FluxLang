#import "standard.fx";

def main() -> int
{
    print("Linux File I/O Test\n\0");
    
    // Test 1: Create and write to a file
    byte[] filename = "test_linux.txt\0";
    
    print("1. Creating file: \0");
    print(filename);
    print();
    
    i64 fd = open_write(filename);
    
    if (fd == -1)
    {
        print("Error: Failed to create file\n\0");
        return 1;
    };

    
    return 0;
};