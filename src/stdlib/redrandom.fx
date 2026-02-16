// redrandom.fx - Random Number Generation Library
// Provides multiple RNG algorithms and utilities

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_RANDOM
#def FLUX_STANDARD_RANDOM 1;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

struct PCG32
{
    u64 state;
    u64 inc;
};

global PCG32 global_rng;
global bool global_rng_initialized = false;

namespace standard
{
    namespace random
    {
        // ============ ENTROPY SOURCES ============
        
        // Get entropy from RDTSC (CPU timestamp counter)
        def get_rdtsc() -> u64
        {
            u64 result = (u64)0;
            
            #ifdef __ARCH_X86_64__
            volatile asm
            {
                rdtsc                    // Read timestamp counter into EDX:EAX
                shlq $$32, %rdx          // Shift EDX left by 32 bits
                orq %rdx, %rax           // Combine into single 64-bit value
                movq %rax, $0            // Store result
            } : : "m"(result) : "rax", "rdx";
            #endif;
            
            #ifdef __ARCH_ARM64__
            volatile asm
            {
                mrs x0, cntvct_el0       // Read virtual count register
                str x0, $0               // Store result
            } : : "m"(result) : "x0";
            #endif;
            
            return result;
        };
        
        // Get entropy from multiple sources
        def get_entropy() -> u64
        {
            u64 t1 = get_rdtsc();
            u64 t2 = get_rdtsc();
            u64 t3 = get_rdtsc();
            
            // Mix the entropy sources
            return t1 ^^ (t2 << 21) ^^ (t3 >> 17);
        };
        
        // ============ XorShift64 RNG ============
        // Fast, simple, good quality PRNG
        
        struct XorShift64
        {
            u64 state;
        };
        
        // Initialize with seed
        def xorshift64_seed(XorShift64* rng, u64 seed) -> void
        {
            // Ensure state is never zero
            if (seed == (u64)0)
            {
                seed = (u64)0xDEADBEEFCAFEBABE;
            };
            rng.state = seed;
        };
        
        // Initialize with entropy
        def xorshift64_init(XorShift64* rng) -> void
        {
            u64 seed = get_entropy();
            xorshift64_seed(rng, seed);
        };
        
        // Generate next random u64
        def xorshift64_next(XorShift64* rng) -> u64
        {
            u64 x = rng.state;
            x = x ^^ (x << 13);
            x = x ^^ (x >> 7);
            x = x ^^ (x << 17);
            rng.state = x;
            return x;
        };
        
        // ============ XorShift128 RNG ============
        // Higher quality, longer period
        
        struct XorShift128
        {
            u64[2] state;
        };
        
        def xorshift128_seed(XorShift128* rng, u64 seed1, u64 seed2) -> void
        {
            // Ensure states are never zero
            if (seed1 == (u64)0)
            {
                seed1 = (u64)0xDEADBEEFCAFEBABE;
            };
            if (seed2 == (u64)0)
            {
                seed2 = (u64)0xFEEDFACEBAADF00D;
            };
            
            rng.state[0] = seed1;
            rng.state[1] = seed2;
        };
        
        def xorshift128_init(XorShift128* rng) -> void
        {
            u64 seed1 = get_entropy();
            u64 seed2 = get_entropy();
            xorshift128_seed(rng, seed1, seed2);
        };
        
        def xorshift128_next(XorShift128* rng) -> u64
        {
            u64 s1 = rng.state[0];
            u64 s0 = rng.state[1];
            
            rng.state[0] = s0;
            s1 = s1 ^^ (s1 << 23);
            s1 = s1 ^^ (s1 >> 17);
            s1 = s1 ^^ s0;
            s1 = s1 ^^ (s0 >> 26);
            rng.state[1] = s1;
            
            return s0 + s1;
        };
        
        // ============ PCG32 RNG ============
        // Permuted Congruential Generator - excellent statistical properties
        
        def pcg32_seed(PCG32* rng, u64 seed, u64 seq) -> void
        {
            rng.state = (u64)0;
            rng.inc = (seq << 1) | (u64)1;
            
            // Warm up the generator
            u64 dummy = (u64)0;
            rng.state = rng.state * (u64)6364136223846793005 + rng.inc;
            rng.state = rng.state + seed;
            rng.state = rng.state * (u64)6364136223846793005 + rng.inc;
        };
        
        def pcg32_init(PCG32* rng) -> void
        {
            u64 seed = get_entropy();
            u64 seq = get_entropy();
            pcg32_seed(rng, seed, seq);
        };
        
        def pcg32_next(PCG32* rng) -> u32
        {
            u64 oldstate = rng.state;
            
            // Advance internal state
            rng.state = oldstate * (u64)6364136223846793005 + rng.inc;
            
            // Calculate output function (XSH RR)
            u32 xorshifted = (u32)(((oldstate >> 18) ^^ oldstate) >> 27);
            u32 rot = (u32)(oldstate >> 59);
            
            return (xorshifted >> rot) | (xorshifted << ((u32)0 - rot));
        };
        
        // ============ LCG (Linear Congruential Generator) ============
        // Simple, fast, but lower quality - good for non-critical uses
        
        struct LCG
        {
            u64 state;
        };
        
        def lcg_seed(LCG* rng, u64 seed) -> void
        {
            rng.state = seed;
        };
        
        def lcg_init(LCG* rng) -> void
        {
            u64 seed = get_entropy();
            lcg_seed(rng, seed);
        };
        
        def lcg_next(LCG* rng) -> u32
        {
            // Using parameters from Numerical Recipes
            rng.state = rng.state * (u64)1664525 + (u64)1013904223;
            return (u32)(rng.state >> 32);
        };
        
        // ============ UTILITY FUNCTIONS ============
        
        // Generate random u64 in range [0, max)
        def random_range_u64(XorShift128* rng, u64 max) -> u64
        {
            if (max == (u64)0)
            {
                return (u64)0;
            };
            
            u64 val = xorshift128_next(rng);
            return val % max;
        };
        
        // Generate random u32 in range [0, max)
        def random_range_u32(PCG32* rng, u32 max) -> u32
        {
            if (max == (u32)0)
            {
                return (u32)0;
            };
            
            u32 val = pcg32_next(rng);
            return val % max;
        };
        
        // Generate random int in range [min, max]
        def random_range_int(PCG32* rng, int min, int max) -> int
        {
            if (min >= max)
            {
                return min;
            };
            
            u32 range = (u32)(max - min + 1);
            u32 val = random_range_u32(rng, range);
            return min + (int)val;
        };
        
        // Generate random float in range [0.0, 1.0)
        def random_float(PCG32* rng) -> float
        {
            u32 val = pcg32_next(rng);
            // Convert to float in range [0, 1)
            // Divide by 2^32
            return (float)val / 4294967296.0;
        };
        
        // Generate random float in range [min, max)
        def random_range_float(PCG32* rng, float min, float max) -> float
        {
            float t = random_float(rng);
            return min + t * (max - min);
        };
        
        // Generate random boolean
        def random_bool(PCG32* rng) -> bool
        {
            return (pcg32_next(rng) & (u32)1) == (u32)1;
        };
        
        // ============ ARRAY/BUFFER FILL ============
        
        // Fill buffer with random bytes
        def random_bytes(PCG32* rng, byte* buffer, u64 length) -> void
        {
            u64 i = (u64)0;
            
            // Fill 4 bytes at a time
            while (i + (u64)4 <= length)
            {
                u32 val = pcg32_next(rng);
                buffer[i + 0] = (byte)(val & 0xFF);
                buffer[i + 1] = (byte)((val >> 8) & 0xFF);
                buffer[i + 2] = (byte)((val >> 16) & 0xFF);
                buffer[i + 3] = (byte)((val >> 24) & 0xFF);
                i = i + (u64)4;
            };
            
            // Fill remaining bytes
            if (i < length)
            {
                u32 val = pcg32_next(rng);
                while (i < length)
                {
                    buffer[i] = (byte)(val & 0xFF);
                    val = val >> 8;
                    i++;
                };
            };
        };
        
        // Shuffle an array (Fisher-Yates shuffle)
        def shuffle_u32_array(PCG32* rng, u32* array, u32 length) -> void
        {
            u32 i = length - (u32)1;
            
            while (i > (u32)0)
            {
                u32 j = random_range_u32(rng, i + (u32)1);
                
                // Swap array[i] and array[j]
                u32 temp = array[i];
                array[i] = array[j];
                array[j] = temp;
                
                i--;
            };
        };
        
        // ============ DICE & GAMING ============
        
        // Roll a dice (1 to sides)
        def roll_dice(PCG32* rng, int sides) -> int
        {
            if (sides < 1)
            {
                return 1;
            };
            
            return random_range_int(rng, 1, sides);
        };
        
        // Roll multiple dice and sum
        def roll_dice_sum(PCG32* rng, int count, int sides) -> int
        {
            int total = 0;
            
            for (int i = 0; i < count; i++)
            {
                total = total + roll_dice(rng, sides);
            };
            
            return total;
        };
        
        // Flip a coin (returns true for heads, false for tails)
        def flip_coin(PCG32* rng) -> bool
        {
            return random_bool(rng);
        };
        
        // ============ STRING GENERATION ============
        
        // Character sets for random string generation
        global const byte[] CHARSET_ALPHA_LOWER = "abcdefghijklmnopqrstuvwxyz\0";
        global const byte[] CHARSET_ALPHA_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\0";
        global const byte[] CHARSET_DIGITS = "0123456789\0";
        global const byte[] CHARSET_ALPHANUMERIC = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\0";
        global const byte[] CHARSET_HEX_LOWER = "0123456789abcdef\0";
        global const byte[] CHARSET_HEX_UPPER = "0123456789ABCDEF\0";
        
        // Generate random string from character set
        def random_string(PCG32* rng, byte* buffer, u32 length, byte* charset) -> void
        {
            // Calculate charset length
            u32 charset_len = (u32)0;
            while (charset[charset_len] != (byte)0)
            {
                charset_len++;
            };
            
            if (charset_len == (u32)0)
            {
                buffer[0] = (byte)0;
                return;
            };
            
            // Generate random characters
            for (u32 i = (u32)0; i < length; i++)
            {
                u32 idx = random_range_u32(rng, charset_len);
                buffer[i] = charset[idx];
            };
            
            buffer[length] = (byte)0;
        };
        
        // Generate random alphanumeric string
        def random_alphanum(PCG32* rng, byte* buffer, u32 length) -> void
        {
            random_string(rng, buffer, length, CHARSET_ALPHANUMERIC);
        };
        
        // Generate random hex string
        def random_hex(PCG32* rng, byte* buffer, u32 length) -> void
        {
            random_string(rng, buffer, length, CHARSET_HEX_LOWER);
        };
        
        // ============ GLOBAL DEFAULT RNG ============
        // Convenient global instance for simple use cases
        
        // Initialize global RNG
        def init_random() -> void
        {
            if (!global_rng_initialized)
            {
                pcg32_init(@global_rng);
                global_rng_initialized = true;
            };
        };
        
        // Get random number using global RNG
        def random() -> u32
        {
            if (!global_rng_initialized)
            {
                init_random();
            };
            
            return pcg32_next(@global_rng);
        };
        
        // Get random int in range using global RNG
        def random_int(int min, int max) -> int
        {
            if (!global_rng_initialized)
            {
                init_random();
            };
            
            return random_range_int(@global_rng, min, max);
        };
        
        // Get random float [0, 1) using global RNG
        def random_f() -> float
        {
            if (!global_rng_initialized)
            {
                init_random();
            };
            
            return random_float(@global_rng);
        };
    };
};

#endif;
