// math.fx - Flux Math Library
// Copyright (C) 2026 Flux Community
// License: MIT

import "standard.fx";
using standard::io; using standard::types;

// ============ BIT-EXACT FLOATING POINT TYPES ============

namespace standard
{
    namespace math
    {
        // IEEE 754 single precision (32-bit)
        struct Float32
        {
            unsigned data{1} sign;        // Sign bit (0=positive, 1=negative)
            unsigned data{8} exponent;    // Exponent (biased by 127)
            unsigned data{23} mantissa;   // Mantissa (with implicit leading 1)
        };

        // IEEE 754 double precision (64-bit)  
        struct Float64
        {
            unsigned data{1} sign;        // Sign bit
            unsigned data{11} exponent;   // Exponent (biased by 1023)
            unsigned data{52} mantissa;   // Mantissa (with implicit leading 1)
        };

        // IEEE 754 half precision (16-bit)
        struct Float16
        {
            unsigned data{1} sign;        // Sign bit
            unsigned data{5} exponent;    // Exponent (biased by 15)
            unsigned data{10} mantissa;   // Mantissa
        };

        // ============ CONSTANTS ============

        namespace Constants
        {
            // Pi and related
            const float PI        = 3.14159265358979323846;
            const float PI_2      = 1.57079632679489661923;  // π/2
            const float PI_4      = 0.78539816339744830962;  // π/4
            const float TAU       = 6.28318530717958647692;  // 2π
            const float ONE_OVER_PI = 0.31830988618379067154;  // 1/π
            const float TWO_OVER_PI = 0.63661977236758134308;  // 2/π
            
            // Euler's number and related
            const float E         = 2.71828182845904523536;
            const float LOG2E     = 1.44269504088896340736;  // log2(e)
            const float LOG10E    = 0.43429448190325182765;  // log10(e)
            const float LN2       = 0.69314718055994530942;  // ln(2)
            const float LN10      = 2.30258509299404568402;  // ln(10)
            
            // Square roots
            const float ROOT2     = 1.41421356237309504880;  // root(2)
            const float ROOT1_2   = 0.70710678118654752440;  // 1/root(2)
            const float ROOT3     = 1.73205080756887729353;  // root(3)
            
            // Small values
            //const float EPSILON   = 1.1920929 * 10^-7; // exponent parsing fails
            //const float EPSILON_D = 2.2204460492503131 * (10^-16);  // Double precision epsilon
            //const float MIN_NORM  = 1.175494351 * (10^-38);  // Single precision min normal
            //const float MAX_FLOAT = 3.402823466 * (10^+38);  // Single precision max
        };

        // ============ BASIC OPERATIONS ============

        namespace Basic
        {
            def abs(float x) -> float
            {
                if (x < 0) { return -x; };
                return x;
            };
            
            def sign(float x) -> float
            {
                if (x > 0) { return 1.0; };
                if (x < 0) { return -1.0; };
                return 0.0;
            };
            
            def floor(float x) -> float
            {
                int n = (int)x;
                if (x >= 0 or x == (float)n)
                {
                    return (float)n;
                };
                return (float)(n - 1);
            };
            
            def ceil(float x) -> float
            {
                int n = (int)x;
                if (x <= 0 or x == (float)n)
                {
                    return (float)n;
                };
                return (float)(n + 1);
            };
            
            def round(float x) -> float
            {
                return floor(x + 0.5);
            };
            
            def trunc(float x) -> float
            {
                return (float)((int)x);
            };
            
            def fract(float x) -> float
            {
                return x - floor(x);
            };
            
            def mod(float x, float y) -> float
            {
                return x - y * floor(x / y);
            };
            
            def min(float a, float b) -> float
            {
                if (a < b) { return a; };
                return b;
            };
            
            def max(float a, float b) -> float
            {
                if (a > b) { return a; };
                return b;
            };
            
            def clamp(float x, float min_val, float max_val) -> float
            {
                if (x < min_val) { return min_val; };
                if (x > max_val) { return max_val; };
                return x;
            };
            
            def saturate(float x) -> float
            {
                return clamp(x, 0.0, 1.0);
            };
            
            def lerp(float a, float b, float t) -> float
            {
                return a + (b - a) * t;
            };
            
            def step(float edge, float x) -> float
            {
                if (x < edge) { return 0.0; };
                return 1.0;
            };
            
            def smoothstep(float edge0, float edge1, float x) -> float
            {
                float t = saturate((x - edge0) / (edge1 - edge0));
                return t * t * (3.0 - 2.0 * t);
            };
        };

        // ============ EXPONENTIAL FUNCTIONS ============

        namespace Exponential
        {
            // Fast exponential using bit manipulation (IEEE 754)
            def exp(float x) -> float
            {
                // exp(x) = 2^(x/ln(2))
                // Use identity: 2^x = 2^(floor(x)) * 2^(fract(x))
                
                // Clamp to avoid overflow
                if (x > 88.0) { return float.MAX; };
                if (x < -88.0) { return 0.0; };
                
                // x * log2(e)
                float z = x * 1.44269504088896340736;
                
                // Separate integer and fractional parts
                float n = Basic::floor(z);
                float f = z - n;
                
                // Polynomial approximation for 2^f
                // Minimax polynomial for 2^x on [0,1]
                float f2 = f * f;
                float f3 = f2 * f;
                float f4 = f2 * f2;
                
                float p = 1.0 + 
                          f * 0.6931471805599453 + 
                          f2 * 0.2402265069591007 +
                          f3 * 0.0555041086648216 +
                          f4 * 0.0096181291076285;
                
                // Reconstruct: 2^n * 2^f
                // Add n to exponent bits directly
                int i = (int)n;
                Float32 result_bits;
                result_bits.sign = 0;
                result_bits.exponent = 127 + i;  // Bias + integer part
                result_bits.mantissa = (unsigned data{23})((p - 1.0) * 8388608.0);  // 2^23
                
                return (float)result_bits;
            };
            
            def exp2(float x) -> float
            {
                // 2^x = exp(x * ln(2))
                return exp(x * Constants::LN2);
            };
            
            def exp10(float x) -> float
            {
                // 10^x = exp(x * ln(10))
                return exp(x * Constants::LN10);
            };
            
            // Natural logarithm using argument reduction and polynomial approximation
            def log(float x) -> float
            {
                if (x <= 0.0)
                {
                    throw("log: domain error (x <= 0)");
                };
                
                // Extract exponent and mantissa
                Float32 bits = (Float32)x;
                int e = (int)bits.exponent - 127;  // Unbias exponent
                
                // Normalize mantissa to [1, 2)
                float m = 1.0 + (float)bits.mantissa / 8388608.0;  // 2^23
                
                // Reduce to [√2/2, √2]
                if (m > Constants::ROOT2)
                {
                    m *= 0.5;
                    e += 1;
                }
                elif (m < Constants::ROOT1_2)
                {
                    m *= 2.0;
                    e -= 1;
                };
                
                // Compute f = m - 1
                float f = m - 1.0;
                
                // Minimax polynomial approximation for log(1+f) on [-0.2929, 0.4142]
                float f2 = f * f;
                float f3 = f2 * f;
                float f4 = f2 * f2;
                float f5 = f3 * f2;
                
                float p = f * (1.0 + 
                    f * (-0.5 + 
                    f * (0.3333333333333333 + 
                    f * (-0.25 + 
                    f * 0.2))));
                
                // log(x) = log(m * 2^e) = log(m) + e * ln(2)
                return p + (float)e * Constants::LN2;
            };
            
            def log2(float x) -> float
            {
                // log2(x) = log(x) / ln(2)
                return log(x) / Constants::LN2;
            };
            
            def log10(float x) -> float {
                // log10(x) = log(x) / ln(10)
                return log(x) / Constants::LN10;
            };
            
            def pow(float x, float y) -> float
            {
                // x^y = exp(y * log(x))
                return exp(y * log(x));
            };
            
            def sqrt(float x) -> float
            {
                if (x < 0.0)
                {
                    throw("sqrt: domain error (x < 0)");
                };
                if (x == 0.0) { return 0.0; };
                
                // Fast inverse square root approximation (Quake III algorithm)
                Float32 bits = (Float32)x;
                
                // Magic number for single precision
                int i = (int)bits;
                i = 0x5f3759df - (i >> 1);
                
                Float32 y_bits = (Float32)i;
                float y = (float)y_bits;
                
                // Newton-Raphson iteration: y = y * (1.5 - 0.5 * x * y^2)
                y = y * (1.5 - 0.5 * x * y * y);
                
                // Return sqrt(x) = x * (1/sqrt(x))
                return x * y;
            };
            
            def cbrt(float x) -> float
            {
                // Cube root: sign(x) * |x|^(1/3)
                float sign = Basic::sign(x);
                float abs_x = Basic::abs(x);
                
                // x^(1/3) = exp(log(x)/3)
                float result = exp(log(abs_x) / 3.0);
                return sign * result;
            };
            
            def hypot(float x, float y) -> float
            {
                // sqrt(x² + y²) with overflow protection
                float ax = Basic::abs(x);
                float ay = Basic::abs(y);
                
                if (ax > ay)
                {
                    float r = ay / ax;
                    return ax * sqrt(1.0 + r * r);
                }
                elif (ay > 0.0)
                {
                    float r = ax / ay;
                    return ay * sqrt(1.0 + r * r);
                };
                
                return 0.0;
            };
        };

        // ============ TRIGONOMETRIC FUNCTIONS ============

        namespace Trigonometric
        {
            // Range reduction to [-π/4, π/4]
            def reduce_range(float x) -> (float, int)
            {
                // Reduce x modulo π/2
                float y = x * Constants::TWO_OVER_PI;
                int q = (int)Basic::round(y);
                float r = x - q * Constants::PI_2;
                
                // Further reduce to [-π/4, π/4]
                if (q % 2 != 0)
                {
                    q += 1;
                    r -= Constants::PI_2;
                };
                
                return (r, q);
            };
            
            // Minimax polynomial approximation for sin(x) on [-π/4, π/4]
            def sin_poly(float x) -> float
            {
                float x2 = x * x;
                float x3 = x2 * x;
                float x5 = x3 * x2;
                float x7 = x5 * x2;
                float x9 = x7 * x2;
                
                return x * (1.0 +
                    x2 * (-0.16666666666666666 +
                    x2 * (0.008333333333333333 +
                    x2 * (-0.0001984126984126984 +
                    x2 * 0.0000027557319223985893))));
            };
            
            def sin(float x) -> float
            {
                // Reduce range
                (float r, int q) = reduce_range(x);
                
                // sin(x) approximation
                float result = sin_poly(r);
                
                // Apply quadrant correction
                if (q % 4 == 1 || q % 4 == 2) {
                    result = -result;
                };
                
                return result;
            };
            
            def cos(float x) -> float
            {
                // cos(x) = sin(x + π/2)
                return sin(x + Constants::PI_2);
            };
            
            def tan(float x) -> float
            {
                // tan(x) = sin(x)/cos(x)
                float s = sin(x);
                float c = cos(x);
                
                if (Basic::abs(c) < Constants::EPSILON)
                {
                    throw("tan: undefined (cos(x) ≈ 0)");
                };
                
                return s / c;
            };
            
            // Inverse trigonometric functions using polynomial approximations
            def asin(float x) -> float
            {
                if (x < -1.0 || x > 1.0)
                {
                    throw("asin: domain error (|x| > 1)");
                };
                
                // Use identity: asin(x) = atan(x/sqrt(1-x²))
                return atan(x / sqrt(1.0 - x * x));
            };
            
            def acos(float x) -> float
            {
                if (x < -1.0 || x > 1.0)
                {
                    throw("acos: domain error (|x| > 1)");
                };
                
                // acos(x) = π/2 - asin(x)
                return Constants::PI_2 - asin(x);
            };
            
            def atan(float x) -> float
            {
                // Range reduction
                bool complement = false;
                bool negative = false;
                
                if (x < 0.0)
                {
                    x = -x;
                    negative = true;
                };
                
                if (x > 1.0)
                {
                    x = 1.0 / x;
                    complement = true;
                };
                
                // Minimax polynomial approximation for atan(x) on [0, 1]
                float x2 = x * x;
                float x3 = x2 * x;
                float x5 = x3 * x2;
                float x7 = x5 * x2;
                float x9 = x7 * x2;
                
                float result = x * (1.0 +
                    x2 * (-0.3333333333333333 +
                    x2 * (0.2 +
                    x2 * (-0.14285714285714285 +
                    x2 * (0.1111111111111111 +
                    x2 * -0.09090909090909091)))));
                
                // Range expansion
                if (complement)
                {
                    result = Constants::PI_2 - result;
                };
                
                if (negative)
                {
                    result = -result;
                };
                
                return result;
            };
            
            def atan2(float y, float x) -> float
            {
                if (x == 0.0 && y == 0.0) {
                    throw("atan2: undefined at origin");
                };
                
                if (x > 0.0)
                {
                    return atan(y / x);
                }
                elif (x < 0.0)
                {
                    if (y >= 0.0)
                    {
                        return atan(y / x) + Constants::PI;
                    }
                    else
                    {
                        return atan(y / x) - Constants::PI;
                    };
                }
                elif (y > 0.0)
                {
                    return Constants::PI_2;
                }
                else
                {
                    return -Constants::PI_2;
                };
            };
            
            def sinc(float x) -> float
            {
                if (x == 0.0) { return 1.0; };
                return sin(x) / x;
            };
        };

        // ============ HYPERBOLIC FUNCTIONS ============

        namespace Hyperbolic
        {
            def sinh(float x) -> float
            {
                // sinh(x) = (exp(x) - exp(-x))/2
                if (x > 88.0) { return float.MAX; };
                if (x < -88.0) { return -float.MAX; };
                
                float ex = Exponential::exp(x);
                float emx = 1.0 / ex;
                
                return 0.5 * (ex - emx);
            };
            
            def cosh(float x) -> float
            {
                // cosh(x) = (exp(x) + exp(-x))/2
                if (x > 88.0) { return float.MAX; };
                if (x < -88.0) { return float.MAX; };
                
                float ex = Exponential::exp(x);
                float emx = 1.0 / ex;
                
                return 0.5 * (ex + emx);
            };
            
            def tanh(float x) -> float
            {
                // tanh(x) = sinh(x)/cosh(x)
                if (x > 19.0) { return 1.0; };
                if (x < -19.0) { return -1.0; };
                
                float ex = Exponential::exp(x);
                float emx = 1.0 / ex;
                
                return (ex - emx) / (ex + emx);
            };
            
            def asinh(float x) -> float
            {
                // asinh(x) = log(x + sqrt(x² + 1))
                return Exponential::log(x + Exponential::sqrt(x * x + 1.0));
            };
            
            def acosh(float x) -> float
            {
                // acosh(x) = log(x + sqrt(x² - 1)), x ≥ 1
                if (x < 1.0)
                {
                    throw("acosh: domain error (x < 1)");
                };
                
                return Exponential::log(x + Exponential::sqrt(x * x - 1.0));
            };
            
            def atanh(float x) -> float
            {
                // atanh(x) = 0.5 * log((1+x)/(1-x)), |x| < 1
                if (x <= -1.0 || x >= 1.0)
                {
                    throw("atanh: domain error (|x| ≥ 1)");
                };
                
                return 0.5 * Exponential::log((1.0 + x) / (1.0 - x));
            };
        };
    };
};