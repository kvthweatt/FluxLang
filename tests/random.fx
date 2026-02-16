#import "redstandard.fx";
#import "redformat.fx";
#import "redrandom.fx";

using standard::format;
using standard::format::colors;
using standard::random;

def main() -> int
{
    print("\n\0");
    print_banner_colored("RANDOM NUMBER GENERATION DEMO\0", 70, colors::BRIGHT_CYAN);
    print("\n\0");
    
    // ============ DEMO 1: Basic Random Numbers ============
    print_banner("BASIC RANDOM NUMBERS\0", 70);
    print("\n\0");
    
    // Initialize global RNG
    init_random();
    
    print("10 random u32 values:\n\0");
    for (int i = 0; i < 10; i++)
    {
        print("  \0");
        print(random());
        print("\n\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 2: Random Ranges ============
    print_banner("RANDOM RANGES\0", 70);
    print("\n\0");
    
    print("10 random integers between 1 and 100:\n\0");
    for (int i = 0; i < 10; i++)
    {
        print("  \0");
        print(random_int(1, 100));
        print("\n\0");
    };
    
    print("\n10 random floats between 0.0 and 1.0:\n\0");
    for (int i = 0; i < 10; i++)
    {
        print("  \0");
        print(random_f(), 4);
        print("\n\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 3: Dice Rolling ============
    print_banner("DICE ROLLING\0", 70);
    print("\n\0");
    
    PCG32 rng;
    pcg32_init(@rng);
    
    print("Rolling a d6 (6-sided die) 10 times:\n\0");
    for (int i = 0; i < 10; i++)
    {
        print("  Roll \0");
        print(i + 1);
        print(": \0");
        print(roll_dice(@rng, 6));
        print("\n\0");
    };
    
    print("\nRolling 3d6 (sum of three 6-sided dice) 5 times:\n\0");
    for (int i = 0; i < 5; i++)
    {
        print("  Roll \0");
        print(i + 1);
        print(": \0");
        print(roll_dice_sum(@rng, 3, 6));
        print("\n\0");
    };
    
    print("\nCoin flips (10 times):\n\0");
    for (int i = 0; i < 10; i++)
    {
        print("  Flip \0");
        print(i + 1);
        print(": \0");
        
        if (flip_coin(@rng))
        {
            print_green("Heads\n\0");
        }
        else
        {
            print_red("Tails\n\0");
        };
    };
    
    print("\n\0");
    
    // ============ DEMO 4: Random Strings ============
    print_banner("RANDOM STRING GENERATION\0", 70);
    print("\n\0");
    
    byte[33] str_buffer;
    
    print("Random alphanumeric strings (16 chars each):\n\0");
    for (int i = 0; i < 5; i++)
    {
        random_alphanum(@rng, str_buffer, (u32)16);
        print("  \0");
        print(str_buffer);
        print("\n\0");
    };
    
    print("\nRandom hex strings (32 chars each):\n\0");
    for (int i = 0; i < 5; i++)
    {
        random_hex(@rng, str_buffer, (u32)32);
        print("  \0");
        print(str_buffer);
        print("\n\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 5: Random Bytes ============
    print_banner("RANDOM BYTES\0", 70);
    print("\n\0");
    
    byte[16] byte_buffer;
    
    print("Random 16-byte sequences (hex):\n\0");
    for (int i = 0; i < 3; i++)
    {
        random_bytes(@rng, byte_buffer, (u64)16);
        
        print("  \0");
        byte[3] hex_out;
        hex_out[2] = (byte)0;
        
        for (int j = 0; j < 16; j++)
        {
            byte[16] hex_chars = [
                '0', '1', '2', '3', '4', '5', '6', '7',
                '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
            ];
            
            hex_out[0] = hex_chars[(byte_buffer[j] >> 4) & 0x0F];
            hex_out[1] = hex_chars[byte_buffer[j] & 0x0F];
            print(hex_out);
            
            if (j == 7)
            {
                print(" \0");
            };
        };
        print("\n\0");
    };
    
    print("\n\0");
    
    // ============ DEMO 6: Array Shuffling ============
    print_banner("ARRAY SHUFFLING\0", 70);
    print("\n\0");
    
    u32[10] deck;
    for (u32 i = (u32)0; i < (u32)10; i++)
    {
        deck[i] = i + (u32)1;
    };
    
    print("Original array: \0");
    for (u32 i = (u32)0; i < (u32)10; i++)
    {
        print((int)deck[i]);
        print(" \0");
    };
    print("\n\0");
    
    shuffle_u32_array(@rng, deck, (u32)10);
    
    print("Shuffled array: \0");
    for (u32 i = (u32)0; i < (u32)10; i++)
    {
        print((int)deck[i]);
        print(" \0");
    };
    print("\n\n\0");
    
    // ============ DEMO 7: Different RNG Algorithms ============
    print_banner("COMPARING RNG ALGORITHMS\0", 70);
    print("\n\0");
    
    print("XorShift64 (5 values):\n  \0");
    XorShift64 xs64;
    xorshift64_init(@xs64);
    for (int i = 0; i < 5; i++)
    {
        print((int)(xorshift64_next(@xs64) % (u64)1000000));
        print(" \0");
    };
    print("\n\0");
    
    print("\nXorShift128 (5 values):\n  \0");
    XorShift128 xs128;
    xorshift128_init(@xs128);
    for (int i = 0; i < 5; i++)
    {
        print((int)(xorshift128_next(@xs128) % (u64)1000000));
        print(" \0");
    };
    print("\n\0");
    
    print("\nPCG32 (5 values):\n  \0");
    PCG32 pcg;
    pcg32_init(@pcg);
    for (int i = 0; i < 5; i++)
    {
        print((int)(pcg32_next(@pcg) % (u32)1000000));
        print(" \0");
    };
    print("\n\0");
    
    print("\nLCG (5 values):\n  \0");
    LCG lcg;
    lcg_init(@lcg);
    for (int i = 0; i < 5; i++)
    {
        print((int)(lcg_next(@lcg) % (u32)1000000));
        print(" \0");
    };
    print("\n\n\0");
    
    // ============ END ============
    hline_heavy(70);
    print_centered("End of Random Generation Demo\0", 70);
    hline_heavy(70);
    print("\n\0");
    
    return 0;
};
