#import "redstandard.fx";
#import "redmath.fx";
#import "redformat.fx";

using standard::format;

def sieve(u64 limit) -> void
{
    bool[limit + 1] is_prime;
    
    // Initialize all as true
    for (u64 i = 2; i <= limit; i++)
    {
        is_prime[i] = true;
    };
    
    // Sieve
    for (u64 p = 2; p * p <= limit; p++)
    {
        if (is_prime[p])
        {
            for (u64 i = p * p; i <= limit; i += p)
            {
                is_prime[i] = false;
            };
        };
    };
    
    // Print primes
    u64 count = 0;
    print_info("");
    print("Primes up to \0");
    print(limit);
    print(":\n\0");
    for (u64 i = 2; i <= limit; i++)
    {
        if (is_prime[i])
        {
            print(i);
            print("\n\0");
            count++;
        };
    };
    print("\n\0");
    print_success("");
    print("Found \0");
    print(count);
    print(" primes\n\0");
};

def main() -> int
{
    print_banner("Prime Number Sieve\0", 40);
    sieve(1000);
    
    system() <- "pause\0";
    return 0;
};