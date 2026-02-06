// Simple Calculator Program
#import "standard.fx";

def parse_int(byte* buffer) -> int
{
    int num = 0;
    int i = 0;
    
    while (buffer[i] >= '0' & buffer[i] <= '9')
    {
        num = num * 10 + (buffer[i] - '0');
        i++;
    };
    
    return num;
};

def main() -> int
{
    print("=== Simple Calculator ===\n\0");
    print("Select operation:\n\0");
    print("1. Add\n\0");
    print("2. Subtract\n\0");
    print("3. Multiply\n\0");
    print("4. Divide\n\0");
    print("Enter choice (1-4): \0");
    
    byte[100] buffer;
    win_input(buffer, 100);
    
    int choice = buffer[0] - '0';
    
    print("Enter first number: \0");
    win_input(buffer, 100);
    int num1 = parse_int(buffer);
    
    print("Enter second number: \0");
    win_input(buffer, 100);
    int num2 = parse_int(buffer);
    
    int result = 0;
    
    switch (choice)
    {
        case (1)
        {
            result = num1 + num2;
            print("Result: \0");
            print(result);
            print("\n\0");
        }

        default
        {
            print("Invalid choice!\n\0");
            return 1;
        };
    };
    
    return 0;
};
