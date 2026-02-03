// Number Guessing Game
#import "standard.fx";

def simple_random(int seed, int max) -> int
{
    // Simple hash-based random for small seeds
    int value = seed * 48271;
    if (value < 0)
    {
        value = -value;
    };
    value = value % max;
    if (value <= 0)
    {
        value = 1;
    };
    return value;
};

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
    print("=== Number Guessing Game ===\n\0");
    print("I'm thinking of a number between 1 and 100.\n\0");
    print("Can you guess it?\n\n\0");
    
    int seed = 137; // Better seed
    int secret_number = simple_random(seed, 100);
    
    int attempts = 0;
    int max_attempts = 10;
    int guessed = 0;
    
    byte[100] buffer;
    
    while (attempts < max_attempts & guessed == 0)
    {
        print("Attempt \0");
        print(attempts + 1);
        print("/\0");
        print(max_attempts);
        print(" - Enter your guess: \0");
        
        win_input(buffer, 100);
        int guess = parse_int(buffer);
        
        attempts++;
        
        if (guess == secret_number)
        {
            print("\nCongratulations! You guessed it in \0");
            print(attempts);
            print(" attempts!\n\0");
            guessed = 1;
        }
        else
        {
            if (guess < secret_number)
            {
                print("Too low! Try again.\n\n\0");
            }
            else
            {
                print("Too high! Try again.\n\n\0");
            };
        };
    };
    
    if (guessed == 0)
    {
        print("\nSorry! You've run out of attempts.\n\0");
        print("The number was: \0");
        print(secret_number);
        print("\n\0");
    };
    
    return 0;
};
