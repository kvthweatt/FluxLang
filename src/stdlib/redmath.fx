// redmath.fx - Comprehensive mathematical functions with overloads
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_MATH
#def FLUX_STANDARD_MATH 1;
#endif;

namespace standard
{
    namespace math
    {
        // Constants
        const i8 PI8 = 3;
        const i16 PI16 = 3;
        const i32 PI32 = 3;
        const i64 PI64 = 3;
        const float PIF = 3.14159265358979323846;
        
        const i8 E8 = 2;
        const i16 E16 = 2;
        const i32 E32 = 2;
        const i64 E64 = 2;
        const float EF = 2.71828182845904523536;
        
        // Absolute value overloads
        def abs(i8 x) -> i8
        {
            if (x < 0) {return -x;};
            return x;
        };
        
        def abs(i16 x) -> i16
        {
            if (x < 0) {return -x;};
            return x;
        };
        
        def abs(i32 x) -> i32
        {
            if (x < 0) {return -x;};
            return x;
        };
        
        def abs(i64 x) -> i64
        {
            if (x < 0) {return -x;};
            return x;
        };

        def abs(float x) -> float
        {
            if (x < 0.0) {return -x;};
            return x;
        };

        // Minimum overloads
        def min(i8 a, i8 b) -> i8
        {
            if (a < b) {return a;};
            return b;
        };
        
        def min(i16 a, i16 b) -> i16
        {
            if (a < b) {return a;};
            return b;
        };
        
        def min(i32 a, i32 b) -> i32
        {
            if (a < b) {return a;};
            return b;
        };
        
        def min(i64 a, i64 b) -> i64
        {
            if (a < b) {return a;};
            return b;
        };

        def min(float a, float b) -> float
        {
            if (a < b) {return a;};
            return b;
        };

        // Maximum overloads
        def max(i8 a, i8 b) -> i8
        {
            if (a > b) {return a;};
            return b;
        };
        
        def max(i16 a, i16 b) -> i16
        {
            if (a > b) {return a;};
            return b;
        };
        
        def max(i32 a, i32 b) -> i32
        {
            if (a > b) {return a;};
            return b;
        };
        
        def max(i64 a, i64 b) -> i64
        {
            if (a > b) {return a;};
            return b;
        };

        def max(float a, float b) -> float
        {
            if (a > b) {return a;};
            return b;
        };

        // Clamp overloads
        def clamp(i8 value, i8 low, i8 high) -> i8
        {
            if (value < low) {return low;};
            if (value > high) {return high;};
            return value;
        };
        
        def clamp(i16 value, i16 low, i16 high) -> i16
        {
            if (value < low) {return low;};
            if (value > high) {return high;};
            return value;
        };
        
        def clamp(i32 value, i32 low, i32 high) -> i32
        {
            if (value < low) {return low;};
            if (value > high) {return high;};
            return value;
        };
        
        def clamp(i64 value, i64 low, i64 high) -> i64
        {
            if (value < low) {return low;};
            if (value > high) {return high;};
            return value;
        };
        
        def clamp(float value, float low, float high) -> float
        {
            if (value < low) {return low;};
            if (value > high) {return high;};
            return value;
        };
        

        ///
        NOTE: These sqrt() functions reveal that type isn't auto-converted for literals
        ///
        // Square root overloads
        def sqrt(i8 x) -> i8
        {
            if (x <= 0) {return 0;};
            
            i8 y = x / 2;
            i8 prev_y = 0;
            
            while (y != prev_y)
            {
                prev_y = y;
                y = (y + x / y) / 2;
            };
            
            return y;
        };
        
        def sqrt(i16 x) -> i16
        {
            if (x <= 0) {return 0;};
            
            i16 y = x / 2;
            i16 prev_y = 0;
            
            while (y != prev_y)
            {
                prev_y = y;
                y = (y + x / y) / 2;
            };
            
            return y;
        };
        
        def sqrt(i32 x) -> i32
        {
            if (x <= 0) {return 0;};
            
            i32 y = x / 2;
            i32 prev_y = 0;
            
            while (y != prev_y)
            {
                prev_y = y;
                y = (y + x / y) / 2;
            };
            
            return y;
        };
        
        def sqrt(i64 x) -> i64
        {
            if (x <= 0) {return 0;};
            
            i64 y = x / 2;
            i64 prev_y = 0;
            
            while (y != prev_y)
            {
                prev_y = y;
                y = (y + x / y) / 2;
            };
            
            return y;
        };
        
        def sqrt(float x) -> float
        {
            if (x <= 0.0) {return 0.0;};
            
            float y = x / 2.0;
            float prev_y = 0.0;
            
            for (i32 i = 0; i < 20; i++)  // Fixed iterations
            {
                prev_y = y;
                y = (y + x / y) / 2.0;
                if (abs(y - prev_y) < 0.000001)
                {
                    break;
                };
            };
            
            return y;
        };
        

        // Factorial overloads
        def factorial(i8 n) -> i8
        {
            if (n <= 1) {return 1;};
            
            i8 result = 1;
            for (i8 i = 2; i <= n; i++)
            {
                result *= i;
            };
            return result;
        };
        
        def factorial(i16 n) -> i16
        {
            if (n <= 1) {return 1;};
            
            i16 result = 1;
            for (i16 i = 2; i <= n; i++)
            {
                result *= i;
            };
            return result;
        };
        
        def factorial(i32 n) -> i32
        {
            if (n <= 1) {return 1;};
            
            i32 result = 1;
            for (i32 i = 2; i <= n; i++)
            {
                result *= i;
            };
            return result;
        };
        
        def factorial(i64 n) -> i64
        {
            if (n <= 1) {return 1;};
            
            i64 result = 1;
            for (i64 i = 2; i <= n; i++)
            {
                result *= i;
            };
            return result;
        };

        // GCD overloads
        def gcd(i8 a, i8 b) -> i8
        {
            while (b != 0)
            {
                i8 temp = b;
                b = a % b;
                a = temp;
            };
            return a;
        };
        
        def gcd(i16 a, i16 b) -> i16
        {
            while (b != 0)
            {
                i16 temp = b;
                b = a % b;
                a = temp;
            };
            return a;
        };
        
        def gcd(i32 a, i32 b) -> i32
        {
            while (b != 0)
            {
                i32 temp = b;
                b = a % b;
                a = temp;
            };
            return a;
        };
        
        def gcd(i64 a, i64 b) -> i64
        {
            while (b != 0)
            {
                i64 temp = b;
                b = a % b;
                a = temp;
            };
            return a;
        };

        // LCM overloads
        def lcm(i8 a, i8 b) -> i8
        {
            if (a == 0 | b == 0) {return 0;};
            return abs(a * b) / gcd(a, b);
        };
        
        def lcm(i16 a, i16 b) -> i16
        {
            if (a == 0 | b == 0) {return 0;};
            return abs(a * b) / gcd(a, b);
        };
        
        def lcm(i32 a, i32 b) -> i32
        {
            if (a == 0 | b == 0) {return 0;};
            return abs(a * b) / gcd(a, b);
        };
        
        def lcm(i64 a, i64 b) -> i64
        {
            if (a == 0 | b == 0) {return 0;};
            return abs(a * b) / gcd(a, b);
        };

        // Rounding functions overloads
        def floor(float x) -> float
        {
            i64 int_part = (i64)x;
            if (x >= 0.0 | x == (float)int_part)
            {
                return (float)int_part;
            };
            return (float)(int_part - (i64)1);
        };
        
        def ceil(float x) -> float
        {
            i64 int_part = (i64)x;
            if (x <= 0.0 | x == (float)int_part)
            {
                return (float)int_part;
            };
            return (float)(int_part + (i64)1);
        };
        
        def round(float x) -> float
        {
            if (x >= 0.0)
            {
                return floor(x + 0.5);
            };
            return ceil(x - 0.5);
        };

        def floor(i8 x) -> i8 { return x; };
        def floor(i16 x) -> i16 { return x; };
        def floor(i32 x) -> i32 { return x; };
        def floor(i64 x) -> i64 { return x; };
        
        def ceil(i8 x) -> i8 { return x; };
        def ceil(i16 x) -> i16 { return x; };
        def ceil(i32 x) -> i32 { return x; };
        def ceil(i64 x) -> i64 { return x; };
        
        def round(i8 x) -> i8 { return x; };
        def round(i16 x) -> i16 { return x; };
        def round(i32 x) -> i32 { return x; };
        def round(i64 x) -> i64 { return x; };

        // Trigonometric functions (simplified approximations)
        def sin(float x) -> float
        {
            // Reduce to [-π, π]
            while (x > (float)PIF) { x -= 2.0 * (float)PIF; };
            while (x < (float)-PIF) { x += 2.0 * (float)PIF; };
            
            // Taylor series approximation
            float result = x;
            float term = x;
            float x2 = x * x;
            
            for (i32 i = 1; i <= 5; i++)
            {
                term = -term * x2 / (float)((2 * i) * (2 * i + 1));
                result += term;
            };
            
            return result;
        };

        def cos(float x) -> float
        {
            // cos(x) = sin(π/2 - x)
            return sin((float)PIF / 2.0 - x);
        };
 
        def tan(float x) -> float
        {
            float c = cos(x);
            if (abs(c) < 0.000001) {return 0.0;};  // Avoid division by zero
            return sin(x) / c;
        };

        // Exponential and logarithmic functions
        def exp(float x) -> float
        {
            // Simple Taylor series for exp(x)
            float result = 1.0;
            float term = 1.0;
            
            for (i32 i = 1; i <= 10; i++)
            {
                term = term * x / (float)i;
                result += term;
            };
            
            return result;
        };
        
        def log(float x) -> float
        {
            if (x <= 0.0) {return 0.0;};
            
            // Simple approximation using series
            float y = (x - 1.0) / (x + 1.0);
            float y2 = y * y;
            float result = 2.0 * y;
            float term = y;
            
            for (i32 i = 1; i <= 10; i += 2)
            {
                term = term * y2;
                result += (2.0 / (float)(2 * i + 1)) * term;
            };
            
            return result;
        };
        
        def log10(float x) -> float
        {
            return log(x) / 2.30258509299404568402;  // ln(10)
        };

        // RNG
        ///
        object Random
        {
            i64 seed;
            
            def __init() -> this
            {
                this.seed = (i64*)12345;
                return this;
            };
            
            def __init(i64 seed) -> this
            {
                if (seed == 0) {seed = 12345;};
                this.seed = seed & 0x7FFFFFFF;
                return this;
            };
            
            def next_i8() -> i8
            {
                this.seed = (this.seed * 1103515245 + 12345) & 0x7FFFFFFF;
                return (this.seed & 0xFF);
            };
            
            def next_i16() -> i16
            {
                this.seed = (this.seed * 1103515245 + 12345) & 0x7FFFFFFF;
                return (i16)(this.seed & 0xFFFF);
            };
            
            def next_i32() -> i32
            {
                this.seed = (this.seed * 1103515245 + 12345) & 0x7FFFFFFF;
                return (i32)(this.seed & 0xFFFFFFFF);
            };
            
            def next_i64() -> i64
            {
                this.seed = (this.seed * 1103515245 + 12345) & 0x7FFFFFFF;
                i64 high = this.next_i32();
                i64 low = this.next_i32();
                return (high << 32) | low;
            };
            
            def next_float() -> float
            {
                return (float)this.next_i32() / 2147483647.0;
            };
            
            def next_range_i8(i8 min_val, i8 max_val) -> i8
            {
                i8 range = max_val - min_val + 1;
                return min_val + (this.next_i8() % range);
            };
            
            def next_range_i16(i16 min_val, i16 max_val) -> i16
            {
                i16 range = max_val - min_val + 1;
                return min_val + (this.next_i16() % range);
            };
            
            def next_range_i32(i32 min_val, i32 max_val) -> i32
            {
                i32 range = max_val - min_val + 1;
                return min_val + (this.next_i32() % range);
            };
            
            def next_range_i64(i64 min_val, i64 max_val) -> i64
            {
                i64 range = max_val - min_val + 1;
                return min_val + (this.next_i64() % range);
            };
            
            def next_range_float(float min_val, float max_val) -> float
            {
                return min_val + this.next_float() * (max_val - min_val);
            };
            
            def next_bool() -> bool
            {
                return (this.next_i32() & 1) == 1;
            };
        };
        ///

        // Additional math utilities with overloads
        def lerp(i8 a, i8 b, float t) -> i8
        {
            return (i8)((float)a + (float)(b - a) * t);
        };
        
        def lerp(i16 a, i16 b, float t) -> i16
        {
            return (i16)((float)a + (float)(b - a) * t);
        };
        
        def lerp(i32 a, i32 b, float t) -> i32
        {
            return (i32)((float)a + (float)(b - a) * t);
        };

        def lerp(i64 a, i64 b, float t) -> i64
        {
            return (i64)((float)a + (float)(b - a) * t);
        };
        
        def lerp(float a, float b, float t) -> float
        {
            return a + (b - a) * t;
        };

        def sign(i8 x) -> i8
        {
            if (x > 0) {return 1;};
            if (x < 0) {return -1;};
            return 0;
        };
        
        def sign(i16 x) -> i16
        {
            if (x > 0) {return 1;};
            if (x < 0) {return -1;};
            return 0;
        };
        
        def sign(i32 x) -> i32
        {
            if (x > 0) {return 1;};
            if (x < 0) {return -1;};
            return 0;
        };
        
        def sign(i64 x) -> i64
        {
            if (x > 0) {return 1;};
            if (x < 0) {return -1;};
            return 0;
        };

        def sign(float x) -> float
        {
            if (x > 0.0) {return 1.0;};
            if (x < 0.0) {return -1.0;};
            return 0.0;
        };

        // Bit manipulation utilities
        // Signed
        def popcount(i8 x) -> i8
        {
            i8 count = 0;
            while (x != 0)
            {
                if (count == 8) { break; }; // Handle all 1s
                count += x & 1;
                x >>= 1;
            };
            return count;
        };
        
        def popcount(i16 x) -> i16
        {
            i16 count = 0;
            while (x != 0)
            {
                if (count == 16) { break; }; // Handle all 1s
                count += x & 1;
                x >>= 1;
            };
            return count;
        };
        
        def popcount(i32 x) -> i32
        {
            i32 count = 0;
            while (x != 0)
            {
                if (count == 32) { break; }; // Handle all 1s
                count += x & 1;
                x >>= 1;
            };
            return count;
        };
        
        def popcount(i64 x) -> i64
        {
            i64 count = 0;
            while (x != 0)
            {
                if (count == 64) { break; }; // Handle all 1s
                count += x & 1;
                x >>= 1;
            };
            return count;
        };
        
        // Unsigned
        def popcount(byte x) -> byte
        {
            byte count = 0;
            while (x != 0)
            {
                if (count == 8) { break; }; // Handle all 1s
                count += x & 1;
                x >>= 1;
            };
            return count;
        };
        
        def popcount(u16 x) -> u16
        {
            u16 count = 0;
            while (x != 0)
            {
                if (count == 16) { break; }; // Handle all 1s
                count += x & 1;
                x >>= 1;
            };
            return count;
        };
        
        def popcount(u32 x) -> u32
        {
            u32 count = 0;
            while (x != 0)
            {
                if (count == 32) { break; }; // Handle all 1s
                count += x & 1;
                x >>= 1;
            };
            return count;
        };

        def popcount(u64 x) -> u64
        {
            u64 count = 0;
            while (x != 0)
            {
                if (count == 64) { break; }; // Handle all 1s
                count += x & 1;
                x >>= 1;
            };
            return count;
        };

        def reverse_bits(byte x) -> byte
        {
            byte result = 0;
            for (byte i = 0; i < 8; i++)
            {
                result = (result << 1) | (x & 1);
                x >>= 1;
            };
            return result;
        };

        def reverse_bits(i8 x) -> i8
        {
            i8 result = 0;
            for (i8 i = 0; i < 8; i++)
            {
                result = (result << 1) | (x & 1);
                x >>= 1;
            };
            return result;
        };
        
        def reverse_bits(i16 x) -> i16
        {
            i16 result = 0;
            for (i16 i = 0; i < 16; i++)
            {
                result = (result << 1) | (x & 1);
                x >>= 1;
            };
            return result;
        };
        
        def reverse_bits(i32 x) -> i32
        {
            i32 result = 0;
            for (i32 i = 0; i < 32; i++)
            {
                result = (result << 1) | (x & 1);
                x >>= 1;
            };
            return result;
        };
        
        def reverse_bits(i64 x) -> i64
        {
            i64 result = 0;
            for (i64 i = 0; i < 64; i++)
            {
                result = (result << 1) | (x & 1);
                x >>= 1;
            };
            return result;
        };
    };
};

using standard::math;