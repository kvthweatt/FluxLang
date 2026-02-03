// Temperature Converter
#import "standard.fx";

def parse_int(byte* buffer) -> int
{
    int num = 0;
    int i = 0;
    int is_negative = 0;
    
    if (buffer[0] == '-')
    {
        is_negative = 1;
        i = 1;
    };
    
    while (buffer[i] >= '0' & buffer[i] <= '9')
    {
        num = num * 10 + (buffer[i] - '0');
        i++;
    };
    
    if (is_negative == 1)
    {
        num = -num;
    };
    
    return num;
};

def main() -> int
{
    print("=== Temperature Converter ===\n\0");
    print("1. Celsius to Fahrenheit\n\0");
    print("2. Fahrenheit to Celsius\n\0");
    print("3. Celsius to Kelvin\n\0");
    print("4. Kelvin to Celsius\n\0");
    print("Enter choice (1-4): \0");
    
    byte[100] buffer;
    win_input(buffer, 100);
    
    int choice = buffer[0] - '0';
    
    print("Enter temperature: \0");
    win_input(buffer, 100);
    int temp = parse_int(buffer);
    
    int result = 0;
    
    switch (choice)
    {
        case (1)
        {
            result = (temp * 9) / 5 + 32;
            print(temp);
            print("C = \0");
            print(result);
            print("F\n\0");
        }
        case (2)
        {
            result = ((temp - 32) * 5) / 9;
            print(temp);
            print("F = \0");
            print(result);
            print("C\n\0");
        }
        case (3)
        {
            result = temp + 273;
            print(temp);
            print("C = \0");
            print(result);
            print("K\n\0");
        }
        case (4)
        {
            result = temp - 273;
            print(temp);
            print("K = \0");
            print(result);
            print("C\n\0");
        }
        default
        {
            print("Invalid choice!\n\0");
            return 1;
        }
    };
    
    return 0;
};
