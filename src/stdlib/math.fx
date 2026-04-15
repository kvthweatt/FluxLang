// Author Hemansh2633B
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_MATH
#def FLUX_STANDARD_MATH 1;
#endif;

namespace standard
{
    namespace math
    {
        const i8 PI8 = 3;
        const i16 PI16 = 3;
        const i32 PI32 = 3;
        const i64 PI64 = 3;
        const float PIF = 3.14159265358979323846f;
        const double PID = 3.14159265358979323846;
        
        const i8 E8 = 2;
        const i16 E16 = 2;
        const i32 E32 = 2;
        const i64 E64 = 2;
        const float EF = 2.71828182845904523536f;
        const double ED = 2.71828182845904523536;

        const float PI_F = 3.14159265358979323846f;
        const double PI_D = 3.14159265358979323846;
        const float E_F = 2.71828182845904523536f;
        const double E_D = 2.71828182845904523536;
        const float TAU_F = 6.28318530717958647692f;
        const double TAU_D = 6.28318530717958647692;
        const float PHI_F = 1.61803398874989484820f;
        const double PHI_D = 1.61803398874989484820;

        struct Vec3  { float x, y, z;    };
        struct Vec4  { float w, x, y, z; };
        struct Face  { int   a, b, c;    };
        struct Edge  { int   a, b;       };
        struct POINT { int   x, y;       };

        struct Complex
        {
            double re,
                   im;
        };

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
            if (x < 0.0f) {return -x;};
            return x;
        };

        def abs(double x) -> double
        {
            if (x < 0.0) {return -x;};
            return x;
        };

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

        def min(double a, double b) -> double
        {
            if (a < b) {return a;};
            return b;
        };

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

        def max(double a, double b) -> double
        {
            if (a > b) {return a;};
            return b;
        };

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

        def clamp(double value, double low, double high) -> double
        {
            if (value < low) {return low;};
            if (value > high) {return high;};
            return value;
        };

        def sqrt(i8 x) -> i8
        {
            if (x <= 0) {return 0;};
            i8 y = x >> 1;
            i8 prev_y;
            while (true)
            {
                prev_y = y;
                y = (y + x / y) >> 1;
                if (y >= prev_y) {break;};
            };
            return y;
        };
        
        def sqrt(i16 x) -> i16
        {
            if (x <= 0) {return 0;};
            i16 y = x >> 1;
            i16 prev_y;
            while (true)
            {
                prev_y = y;
                y = (y + x / y) >> 1;
                if (y >= prev_y) {break;};
            };
            return y;
        };
        
        def sqrt(i32 x) -> i32
        {
            if (x <= 0) {return 0;};
            i32 y = x >> 1;
            i32 prev_y;
            while (true)
            {
                prev_y = y;
                y = (y + x / y) >> 1;
                if (y >= prev_y) {break;};
            };
            return y;
        };
        
        def sqrt(i64 x) -> i64
        {
            if (x <= 0) {return 0;};
            i64 y = x >> 1;
            i64 prev_y;
            while (true)
            {
                prev_y = y;
                y = (y + x / y) >> 1;
                if (y >= prev_y) {break;};
            };
            return y;
        };
        
        def sqrt(float x) -> float
        {
            if (x <= 0.0f) {return 0.0f;};
            float y = x * 0.5f;
            float prev_y;
            for (i32 i = 0; i < 20; i++)
            {
                prev_y = y;
                y = (y + x / y) * 0.5f;
                if (abs(y - prev_y) < 0.000001f) {break;};
            };
            return y;
        };
        
        def sqrt(double x) -> double
        {
            if (x <= 0.0) {return 0.0;};
            double y = x * 0.5;
            double prev_y;
            for (i32 i = 0; i < 40; i++)
            {
                prev_y = y;
                y = (y + x / y) * 0.5;
                if (abs(y - prev_y) < 1e-15) {break;};
            };
            return y;
        };

        def cbrt(float x) -> float
        {
            if (x == 0.0f) {return 0.0f;};
            float y = x > 0.0f ? x / 3.0f : -(-x / 3.0f);
            float prev_y;
            for (i32 i = 0; i < 20; i++)
            {
                prev_y = y;
                y = (2.0f * y + x / (y * y)) / 3.0f;
                if (abs(y - prev_y) < 0.000001f) {break;};
            };
            return y;
        };

        def cbrt(double x) -> double
        {
            if (x == 0.0) {return 0.0;};
            double y = x > 0.0 ? x / 3.0 : -(-x / 3.0);
            double prev_y;
            for (i32 i = 0; i < 40; i++)
            {
                prev_y = y;
                y = (2.0 * y + x / (y * y)) / 3.0;
                if (abs(y - prev_y) < 1e-15) {break;};
            };
            return y;
        };

        def pow(float base, float exp) -> float
        {
            if (base == 0.0f)
            {
                if (exp > 0.0f) {return 0.0f;};
                if (exp == 0.0f) {return 1.0f;};
                return 0.0f;
            };
            if (exp == 0.0f) {return 1.0f;};
            if (exp == 1.0f) {return base;};
            if (exp == 2.0f) {return base * base;};
            if (exp == 0.5f) {return sqrt(base);};
            bool neg_exp = exp < 0.0f;
            float abs_exp = neg_exp ? -exp : exp;
            i32 int_part = (i32)abs_exp;
            float frac_part = abs_exp - (float)int_part;
            float result = 1.0f;
            float cur = base;
            i32 e = int_part;
            while (e > 0)
            {
                if (e & 1) {result *= cur;};
                cur *= cur;
                e >>= 1;
            };
            if (frac_part > 0.0f)
            {
                result *= exp(frac_part * log(base));
            };
            if (neg_exp) {result = 1.0f / result;};
            return result;
        };

        def pow(double base, double exp) -> double
        {
            if (base == 0.0)
            {
                if (exp > 0.0) {return 0.0;};
                if (exp == 0.0) {return 1.0;};
                return 0.0;
            };
            if (exp == 0.0) {return 1.0;};
            if (exp == 1.0) {return base;};
            if (exp == 2.0) {return base * base;};
            if (exp == 0.5) {return sqrt(base);};
            bool neg_exp = exp < 0.0;
            double abs_exp = neg_exp ? -exp : exp;
            i64 int_part = (i64)abs_exp;
            double frac_part = abs_exp - (double)int_part;
            double result = 1.0;
            double cur = base;
            i64 e = int_part;
            while (e > 0)
            {
                if (e & 1) {result *= cur;};
                cur *= cur;
                e >>= 1;
            };
            if (frac_part > 0.0)
            {
                result *= exp(frac_part * log(base));
            };
            if (neg_exp) {result = 1.0 / result;};
            return result;
        };

        def hypot(float x, float y) -> float
        {
            float ax = abs(x);
            float ay = abs(y);
            if (ax > ay)
            {
                float r = ay / ax;
                return ax * sqrt(1.0f + r * r);
            };
            if (ay > 0.0f)
            {
                float r = ax / ay;
                return ay * sqrt(1.0f + r * r);
            };
            return 0.0f;
        };

        def hypot(double x, double y) -> double
        {
            double ax = abs(x);
            double ay = abs(y);
            if (ax > ay)
            {
                double r = ay / ax;
                return ax * sqrt(1.0 + r * r);
            };
            if (ay > 0.0)
            {
                double r = ax / ay;
                return ay * sqrt(1.0 + r * r);
            };
            return 0.0;
        };

        def factorial(i8 n) -> i8
        {
            if (n <= 1) {return 1;};
            i8 result = 1;
            for (i8 i = 2; i <= n; i++) {result *= i;};
            return result;
        };
        
        def factorial(i16 n) -> i16
        {
            if (n <= 1) {return 1;};
            i16 result = 1;
            for (i16 i = 2; i <= n; i++) {result *= i;};
            return result;
        };
        
        def factorial(i32 n) -> i32
        {
            if (n <= 1) {return 1;};
            i32 result = 1;
            for (i32 i = 2; i <= n; i++) {result *= i;};
            return result;
        };
        
        def factorial(i64 n) -> i64
        {
            if (n <= 1) {return 1;};
            i64 result = 1;
            for (i64 i = 2; i <= n; i++) {result *= i;};
            return result;
        };

        def gcd(i8 a, i8 b) -> i8
        {
            i8 temp;
            while (b != 0)
            {
                temp = b;
                b = a % b;
                a = temp;
            };
            return a;
        };
        
        def gcd(i16 a, i16 b) -> i16
        {
            i16 temp;
            while (b != 0)
            {
                temp = b;
                b = a % b;
                a = temp;
            };
            return a;
        };
        
        def gcd(i32 a, i32 b) -> i32
        {
            i32 temp;
            while (b != 0)
            {
                temp = b;
                b = a % b;
                a = temp;
            };
            return a;
        };
        
        def gcd(i64 a, i64 b) -> i64
        {
            i64 temp;
            while (b != 0)
            {
                temp = b;
                b = a % b;
                a = temp;
            };
            return a;
        };

        def lcm(i8 a, i8 b) -> i8
        {
            if (a == 0 || b == 0) {return 0;};
            return abs(a * b) / gcd(a, b);
        };
        
        def lcm(i16 a, i16 b) -> i16
        {
            if (a == 0 || b == 0) {return 0;};
            return abs(a * b) / gcd(a, b);
        };
        
        def lcm(i32 a, i32 b) -> i32
        {
            if (a == 0 || b == 0) {return 0;};
            return abs(a * b) / gcd(a, b);
        };
        
        def lcm(i64 a, i64 b) -> i64
        {
            if (a == 0 || b == 0) {return 0;};
            return abs(a * b) / gcd(a, b);
        };

        def floor(float x) -> float
        {
            i64 int_part = (i64)x;
            if (x >= 0.0f || x == (float)int_part) {return (float)int_part;};
            return (float)(int_part - 1);
        };
        
        def floor(double x) -> double
        {
            i64 int_part = (i64)x;
            if (x >= 0.0 || x == (double)int_part) {return (double)int_part;};
            return (double)(int_part - 1);
        };

        def ceil(float x) -> float
        {
            i64 int_part = (i64)x;
            if (x <= 0.0f || x == (float)int_part) {return (float)int_part;};
            return (float)(int_part + 1);
        };
        
        def ceil(double x) -> double
        {
            i64 int_part = (i64)x;
            if (x <= 0.0 || x == (double)int_part) {return (double)int_part;};
            return (double)(int_part + 1);
        };

        def round(float x) -> float
        {
            if (x >= 0.0f) {return floor(x + 0.5f);};
            return ceil(x - 0.5f);
        };
        
        def round(double x) -> double
        {
            if (x >= 0.0) {return floor(x + 0.5);};
            return ceil(x - 0.5);
        };

        def trunc(float x) -> float
        {
            return (float)((i64)x);
        };
        
        def trunc(double x) -> double
        {
            return (double)((i64)x);
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

        def sin(float x) -> float
        {
            float y = x;
            while (y > PI_F) { y -= 2.0f * PI_F; };
            while (y < -PI_F) { y += 2.0f * PI_F; };
            float x2 = y * y;
            float result = y;
            float term = y;
            for (i32 i = 1; i <= 6; i++)
            {
                term *= -x2 / (float)((2 * i) * (2 * i + 1));
                result += term;
            };
            return result;
        };

        def sin(double x) -> double
        {
            double y = x;
            while (y > PI_D) { y -= 2.0 * PI_D; };
            while (y < -PI_D) { y += 2.0 * PI_D; };
            double x2 = y * y;
            double result = y;
            double term = y;
            for (i32 i = 1; i <= 10; i++)
            {
                term *= -x2 / (double)((2 * i) * (2 * i + 1));
                result += term;
            };
            return result;
        };

        def cos(float x) -> float
        {
            return sin(PI_F * 0.5f - x);
        };

        def cos(double x) -> double
        {
            return sin(PI_D * 0.5 - x);
        };

        def tan(float x) -> float
        {
            float c = cos(x);
            if (abs(c) < 0.000001f) {return 0.0f;};
            return sin(x) / c;
        };

        def tan(double x) -> double
        {
            double c = cos(x);
            if (abs(c) < 1e-12) {return 0.0;};
            return sin(x) / c;
        };

        def asin(float x) -> float
        {
            if (x >= 1.0f) {return PI_F * 0.5f;};
            if (x <= -1.0f) {return -PI_F * 0.5f;};
            return atan(x / sqrt(1.0f - x * x));
        };

        def asin(double x) -> double
        {
            if (x >= 1.0) {return PI_D * 0.5;};
            if (x <= -1.0) {return -PI_D * 0.5;};
            return atan(x / sqrt(1.0 - x * x));
        };

        def acos(float x) -> float
        {
            return PI_F * 0.5f - asin(x);
        };

        def acos(double x) -> double
        {
            return PI_D * 0.5 - asin(x);
        };

        def atan(float x) -> float
        {
            bool neg = x < 0.0f;
            if (neg) { x = -x; };
            bool recip = x > 1.0f;
            if (recip) { x = 1.0f / x; };
            float x2 = x * x;
            float r = x * (1.0f
                - x2 * (0.333333333f
                - x2 * (0.2f
                - x2 * (0.142857143f
                - x2 * (0.111111111f
                - x2 * (0.089764464f
                - x2 * (0.060035485f)))))));
            if (recip) { r = PI_F * 0.5f - r; };
            if (neg) { r = -r; };
            return r;
        };

        def atan(double x) -> double
        {
            bool neg = x < 0.0;
            if (neg) { x = -x; };
            bool recip = x > 1.0;
            if (recip) { x = 1.0 / x; };
            double x2 = x * x;
            double r = x * (1.0
                - x2 * (0.3333333333333333
                - x2 * (0.2
                - x2 * (0.14285714285714285
                - x2 * (0.1111111111111111
                - x2 * (0.08976446425679978
                - x2 * (0.06003548500086211)))))));
            if (recip) { r = PI_D * 0.5 - r; };
            if (neg) { r = -r; };
            return r;
        };

        def atan2(float y, float x) -> float
        {
            if (x > 0.0f) {return atan(y / x);};
            if (x < 0.0f)
            {
                if (y >= 0.0f) {return atan(y / x) + PI_F;};
                return atan(y / x) - PI_F;
            };
            if (y > 0.0f) {return PI_F * 0.5f;};
            if (y < 0.0f) {return -PI_F * 0.5f;};
            return 0.0f;
        };

        def atan2(double y, double x) -> double
        {
            if (x > 0.0) {return atan(y / x);};
            if (x < 0.0)
            {
                if (y >= 0.0) {return atan(y / x) + PI_D;};
                return atan(y / x) - PI_D;
            };
            if (y > 0.0) {return PI_D * 0.5;};
            if (y < 0.0) {return -PI_D * 0.5;};
            return 0.0;
        };

        def sinh(float x) -> float
        {
            float e = exp(x);
            return (e - 1.0f / e) * 0.5f;
        };

        def sinh(double x) -> double
        {
            double e = exp(x);
            return (e - 1.0 / e) * 0.5;
        };

        def cosh(float x) -> float
        {
            float e = exp(x);
            return (e + 1.0f / e) * 0.5f;
        };

        def cosh(double x) -> double
        {
            double e = exp(x);
            return (e + 1.0 / e) * 0.5;
        };

        def tanh(float x) -> float
        {
            float e2 = exp(2.0f * x);
            return (e2 - 1.0f) / (e2 + 1.0f);
        };

        def tanh(double x) -> double
        {
            double e2 = exp(2.0 * x);
            return (e2 - 1.0) / (e2 + 1.0);
        };

        def asinh(float x) -> float
        {
            return log(x + sqrt(x * x + 1.0f));
        };

        def asinh(double x) -> double
        {
            return log(x + sqrt(x * x + 1.0));
        };

        def acosh(float x) -> float
        {
            if (x < 1.0f) {return 0.0f;};
            return log(x + sqrt(x * x - 1.0f));
        };

        def acosh(double x) -> double
        {
            if (x < 1.0) {return 0.0;};
            return log(x + sqrt(x * x - 1.0));
        };

        def atanh(float x) -> float
        {
            if (x <= -1.0f || x >= 1.0f) {return 0.0f;};
            return 0.5f * log((1.0f + x) / (1.0f - x));
        };

        def atanh(double x) -> double
        {
            if (x <= -1.0 || x >= 1.0) {return 0.0;};
            return 0.5 * log((1.0 + x) / (1.0 - x));
        };

        def degrees(float rad) -> float
        {
            return rad * (180.0f / PI_F);
        };

        def degrees(double rad) -> double
        {
            return rad * (180.0 / PI_D);
        };

        def radians(float deg) -> float
        {
            return deg * (PI_F / 180.0f);
        };

        def radians(double deg) -> double
        {
            return deg * (PI_D / 180.0);
        };

        def exp(float x) -> float
        {
            if (x > 88.0f) {return 3.402823e38f;};
            if (x < -87.0f) {return 0.0f;};
            float result = 1.0f;
            float term = 1.0f;
            for (i32 i = 1; i <= 15; i++)
            {
                term *= x / (float)i;
                result += term;
                if (abs(term) < 0.000001f) {break;};
            };
            return result;
        };

        def exp(double x) -> double
        {
            if (x > 709.0) {return 1.797693e308;};
            if (x < -708.0) {return 0.0;};
            double result = 1.0;
            double term = 1.0;
            for (i32 i = 1; i <= 25; i++)
            {
                term *= x / (double)i;
                result += term;
                if (abs(term) < 1e-15) {break;};
            };
            return result;
        };

        def expm1(float x) -> float
        {
            if (abs(x) < 0.1f)
            {
                float result = x;
                float term = x;
                float x2 = x * x;
                for (i32 i = 2; i <= 8; i++)
                {
                    term *= x / (float)i;
                    result += term;
                };
                return result;
            };
            return exp(x) - 1.0f;
        };

        def expm1(double x) -> double
        {
            if (abs(x) < 0.1)
            {
                double result = x;
                double term = x;
                for (i32 i = 2; i <= 15; i++)
                {
                    term *= x / (double)i;
                    result += term;
                };
                return result;
            };
            return exp(x) - 1.0;
        };

        def log(float x) -> float
        {
            if (x <= 0.0f) {return 0.0f;};
            if (x == 1.0f) {return 0.0f;};
            float m = x;
            i32 e = 0;
            while (m >= 2.0f)
            {
                m *= 0.5f;
                e++;
            };
            while (m < 1.0f)
            {
                m *= 2.0f;
                e--;
            };
            float t = (m - 1.0f) / (m + 1.0f);
            float t2 = t * t;
            float term = t;
            float result = t;
            for (i32 i = 1; i <= 10; i++)
            {
                term *= t2;
                result += term / (float)(2 * i + 1);
            };
            return 2.0f * result + (float)e * 0.6931471805599453f;
        };

        def log(double x) -> double
        {
            if (x <= 0.0) {return 0.0;};
            if (x == 1.0) {return 0.0;};
            double m = x;
            i32 e = 0;
            while (m >= 2.0)
            {
                m *= 0.5;
                e++;
            };
            while (m < 1.0)
            {
                m *= 2.0;
                e--;
            };
            double t = (m - 1.0) / (m + 1.0);
            double t2 = t * t;
            double term = t;
            double result = t;
            for (i32 i = 1; i <= 25; i++)
            {
                term *= t2;
                double add = term / (double)(2 * i + 1);
                result += add;
                if (abs(add) < 1e-16) {break;};
            };
            return 2.0 * result + (double)e * 0.6931471805599453;
        };

        def log1p(float x) -> float
        {
            if (abs(x) < 0.1f)
            {
                float result = x;
                float term = x;
                float xn = x;
                for (i32 i = 2; i <= 10; i++)
                {
                    xn *= -x;
                    term = xn / (float)i;
                    result += term;
                };
                return result;
            };
            return log(1.0f + x);
        };

        def log1p(double x) -> double
        {
            if (abs(x) < 0.1)
            {
                double result = x;
                double term = x;
                double xn = x;
                for (i32 i = 2; i <= 20; i++)
                {
                    xn *= -x;
                    term = xn / (double)i;
                    result += term;
                };
                return result;
            };
            return log(1.0 + x);
        };

        def log2(float x) -> float
        {
            return log(x) * 1.4426950408889634f;
        };

        def log2(double x) -> double
        {
            return log(x) * 1.4426950408889634;
        };

        def log10(float x) -> float
        {
            return log(x) * 0.4342944819032518f;
        };

        def log10(double x) -> double
        {
            return log(x) * 0.4342944819032518;
        };

        def erf(float x) -> float
        {
            float sign = x < 0.0f ? -1.0f : 1.0f;
            float a = abs(x);
            float t = 1.0f / (1.0f + 0.3275911f * a);
            float t2 = t * t;
            float t3 = t2 * t;
            float t4 = t2 * t2;
            float t5 = t4 * t;
            float result = 1.0f - (0.254829592f * t - 0.284496736f * t2 + 1.421413741f * t3 - 1.453152027f * t4 + 1.061405429f * t5) * exp(-a * a);
            return sign * result;
        };

        def erf(double x) -> double
        {
            double sign = x < 0.0 ? -1.0 : 1.0;
            double a = abs(x);
            double t = 1.0 / (1.0 + 0.3275911 * a);
            double t2 = t * t;
            double t3 = t2 * t;
            double t4 = t2 * t2;
            double t5 = t4 * t;
            double result = 1.0 - (0.254829592 * t - 0.284496736 * t2 + 1.421413741 * t3 - 1.453152027 * t4 + 1.061405429 * t5) * exp(-a * a);
            return sign * result;
        };

        def erfc(float x) -> float
        {
            return 1.0f - erf(x);
        };

        def erfc(double x) -> double
        {
            return 1.0 - erf(x);
        };

        def tgamma(float x) -> float
        {
            if (x <= 0.0f)
            {
                if (x == floor(x)) {return 0.0f;};
                return PI_F / (sin(PI_F * x) * tgamma(1.0f - x));
            };
            float p[8] = {676.5203681218851f, -1259.1392167224028f, 771.32342877765313f, -176.61502916214059f, 12.507343278686905f, -0.13857109526572012f, 9.9843695780195716e-6f, 1.5056327351493116e-7f};
            float z = x - 1.0f;
            float y = 0.99999999999980993f;
            for (i32 i = 0; i < 8; i++) { y += p[i] / (z + (float)i + 1.0f); };
            float t = z + 7.5f;
            return sqrt(2.0f * PI_F) * pow(t, z + 0.5f) * exp(-t) * y;
        };

        def tgamma(double x) -> double
        {
            if (x <= 0.0)
            {
                if (x == floor(x)) {return 0.0;};
                return PI_D / (sin(PI_D * x) * tgamma(1.0 - x));
            };
            double p[8] = {676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7};
            double z = x - 1.0;
            double y = 0.99999999999980993;
            for (i32 i = 0; i < 8; i++) { y += p[i] / (z + (double)i + 1.0); };
            double t = z + 7.5;
            return sqrt(2.0 * PI_D) * pow(t, z + 0.5) * exp(-t) * y;
        };

        def lgamma(float x) -> float
        {
            return log(tgamma(x));
        };

        def lgamma(double x) -> double
        {
            return log(tgamma(x));
        };

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

        def lerp(double a, double b, double t) -> double
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
            if (x > 0.0f) {return 1.0f;};
            if (x < 0.0f) {return -1.0f;};
            return 0.0f;
        };

        def sign(double x) -> double
        {
            if (x > 0.0) {return 1.0;};
            if (x < 0.0) {return -1.0;};
            return 0.0;
        };

        def copysign(float mag, float sgn) -> float
        {
            if (sgn < 0.0f) {return -abs(mag);};
            return abs(mag);
        };

        def copysign(double mag, double sgn) -> double
        {
            if (sgn < 0.0) {return -abs(mag);};
            return abs(mag);
        };

        def fmod(float x, float y) -> float
        {
            if (y == 0.0f) {return 0.0f;};
            float n = floor(x / y);
            return x - n * y;
        };

        def fmod(double x, double y) -> double
        {
            if (y == 0.0) {return 0.0;};
            double n = floor(x / y);
            return x - n * y;
        };

        def frexp(float x, i32* exp) -> (float, i32)
        {
            if (x == 0.0f) {*exp = 0; return 0.0f;};
            i32 e = 0;
            float m = abs(x);
            if (m >= 1.0f) {while (m >= 1.0f) {m *= 0.5f; e++;};}
            else {while (m < 0.5f) {m *= 2.0f; e--;};};
            *exp = e;
            return copysign(m, x);
        };

        def frexp(double x, i32* exp) -> (double, i32)
        {
            if (x == 0.0) {*exp = 0; return 0.0;};
            i32 e = 0;
            double m = abs(x);
            if (m >= 1.0) {while (m >= 1.0) {m *= 0.5; e++;};}
            else {while (m < 0.5) {m *= 2.0; e--;};};
            *exp = e;
            return copysign(m, x);
        };

        def ldexp(float x, i32 exp) -> float
        {
            return x * pow(2.0f, (float)exp);
        };

        def ldexp(double x, i32 exp) -> double
        {
            return x * pow(2.0, (double)exp);
        };

        def modf(float x, float* intpart) -> (float, float)
        {
            *intpart = trunc(x);
            return x - *intpart;
        };

        def modf(double x, double* intpart) -> (double, double)
        {
            *intpart = trunc(x);
            return x - *intpart;
        };

        def fabs(float x) -> float
        {
            return abs(x);
        };

        def fabs(double x) -> double
        {
            return abs(x);
        };

        def fma(float x, float y, float z) -> float
        {
            return x * y + z;
        };

        def fma(double x, double y, double z) -> double
        {
            return x * y + z;
        };

        def isfinite(float x) -> bool
        {
            return x == x && x - x == 0.0f;
        };

        def isfinite(double x) -> bool
        {
            return x == x && x - x == 0.0;
        };

        def isinf(float x) -> bool
        {
            return x != x || x - x != 0.0f;
        };

        def isinf(double x) -> bool
        {
            return x != x || x - x != 0.0;
        };

        def isnan(float x) -> bool
        {
            return x != x;
        };

        def isnan(double x) -> bool
        {
            return x != x;
        };

        def nextafter(float x, float y) -> float
        {
            if (x == y) {return x;};
            if (isnan(x) || isnan(y)) {return x;};
            if (!isfinite(x)) {return x;};
            i32 ix = *(i32*)&x;
            if ((x < y) == (x > 0.0f)) {ix++;} else {ix--;};
            return *(float*)&ix;
        };

        def nextafter(double x, double y) -> double
        {
            if (x == y) {return x;};
            if (isnan(x) || isnan(y)) {return x;};
            if (!isfinite(x)) {return x;};
            i64 ix = *(i64*)&x;
            if ((x < y) == (x > 0.0)) {ix++;} else {ix--;};
            return *(double*)&ix;
        };

        def ulp(float x) -> float
        {
            return nextafter(x, 1e38f) - x;
        };

        def ulp(double x) -> double
        {
            return nextafter(x, 1e308) - x;
        };

        def popcount(byte x) -> byte
        {
            x = x - ((x >> 1) & 0x55);
            x = (x & 0x33) + ((x >> 2) & 0x33);
            x = (x + (x >> 4)) & 0x0F;
            return x;
        };

        def popcount(i8 x) -> i8
        {
            u8 u = (u8)x;
            u = u - ((u >> 1) & 0x55);
            u = (u & 0x33) + ((u >> 2) & 0x33);
            u = (u + (u >> 4)) & 0x0F;
            return (i8)u;
        };

        def popcount(u16 x) -> u16
        {
            x = x - ((x >> 1) & 0x5555);
            x = (x & 0x3333) + ((x >> 2) & 0x3333);
            x = (x + (x >> 4)) & 0x0F0F;
            x = (x + (x >> 8)) & 0x00FF;
            return x;
        };

        def popcount(i16 x) -> i16
        {
            u16 u = (u16)x;
            u = u - ((u >> 1) & 0x5555);
            u = (u & 0x3333) + ((u >> 2) & 0x3333);
            u = (u + (u >> 4)) & 0x0F0F;
            u = (u + (u >> 8)) & 0x00FF;
            return (i16)u;
        };

        def popcount(u32 x) -> u32
        {
            x = x - ((x >> 1) & 0x55555555);
            x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
            x = (x + (x >> 4)) & 0x0F0F0F0F;
            x = x + (x >> 8);
            x = x + (x >> 16);
            return x & 0x3F;
        };

        def popcount(i32 x) -> i32
        {
            u32 u = (u32)x;
            u = u - ((u >> 1) & 0x55555555);
            u = (u & 0x33333333) + ((u >> 2) & 0x33333333);
            u = (u + (u >> 4)) & 0x0F0F0F0F;
            u = u + (u >> 8);
            u = u + (u >> 16);
            return (i32)(u & 0x3F);
        };

        def popcount(u64 x) -> u64
        {
            x = x - ((x >> 1) & 0x5555555555555555);
            x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
            x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0F;
            x = x + (x >> 8);
            x = x + (x >> 16);
            x = x + (x >> 32);
            return x & 0x7F;
        };

        def popcount(i64 x) -> i64
        {
            u64 u = (u64)x;
            u = u - ((u >> 1) & 0x5555555555555555);
            u = (u & 0x3333333333333333) + ((u >> 2) & 0x3333333333333333);
            u = (u + (u >> 4)) & 0x0F0F0F0F0F0F0F0F;
            u = u + (u >> 8);
            u = u + (u >> 16);
            u = u + (u >> 32);
            return (i64)(u & 0x7F);
        };

        def reverse_bits(byte x) -> byte
        {
            x = ((x & 0xF0) >> 4) | ((x & 0x0F) << 4);
            x = ((x & 0xCC) >> 2) | ((x & 0x33) << 2);
            x = ((x & 0xAA) >> 1) | ((x & 0x55) << 1);
            return x;
        };

        def reverse_bits(i8 x) -> i8
        {
            u8 u = (u8)x;
            u = ((u & 0xF0) >> 4) | ((u & 0x0F) << 4);
            u = ((u & 0xCC) >> 2) | ((u & 0x33) << 2);
            u = ((u & 0xAA) >> 1) | ((u & 0x55) << 1);
            return (i8)u;
        };

        def reverse_bits(u16 x) -> u16
        {
            x = ((x & 0xFF00) >> 8) | ((x & 0x00FF) << 8);
            x = ((x & 0xF0F0) >> 4) | ((x & 0x0F0F) << 4);
            x = ((x & 0xCCCC) >> 2) | ((x & 0x3333) << 2);
            x = ((x & 0xAAAA) >> 1) | ((x & 0x5555) << 1);
            return x;
        };

        def reverse_bits(i16 x) -> i16
        {
            u16 u = (u16)x;
            u = ((u & 0xFF00) >> 8) | ((u & 0x00FF) << 8);
            u = ((u & 0xF0F0) >> 4) | ((u & 0x0F0F) << 4);
            u = ((u & 0xCCCC) >> 2) | ((u & 0x3333) << 2);
            u = ((u & 0xAAAA) >> 1) | ((u & 0x5555) << 1);
            return (i16)u;
        };

        def reverse_bits(u32 x) -> u32
        {
            x = ((x & 0xFFFF0000) >> 16) | ((x & 0x0000FFFF) << 16);
            x = ((x & 0xFF00FF00) >> 8) | ((x & 0x00FF00FF) << 8);
            x = ((x & 0xF0F0F0F0) >> 4) | ((x & 0x0F0F0F0F) << 4);
            x = ((x & 0xCCCCCCCC) >> 2) | ((x & 0x33333333) << 2);
            x = ((x & 0xAAAAAAAA) >> 1) | ((x & 0x55555555) << 1);
            return x;
        };

        def reverse_bits(i32 x) -> i32
        {
            u32 u = (u32)x;
            u = ((u & 0xFFFF0000) >> 16) | ((u & 0x0000FFFF) << 16);
            u = ((u & 0xFF00FF00) >> 8) | ((u & 0x00FF00FF) << 8);
            u = ((u & 0xF0F0F0F0) >> 4) | ((u & 0x0F0F0F0F) << 4);
            u = ((u & 0xCCCCCCCC) >> 2) | ((u & 0x33333333) << 2);
            u = ((u & 0xAAAAAAAA) >> 1) | ((u & 0x55555555) << 1);
            return (i32)u;
        };

        def reverse_bits(u64 x) -> u64
        {
            x = ((x & 0xFFFFFFFF00000000) >> 32) | ((x & 0x00000000FFFFFFFF) << 32);
            x = ((x & 0xFFFF0000FFFF0000) >> 16) | ((x & 0x0000FFFF0000FFFF) << 16);
            x = ((x & 0xFF00FF00FF00FF00) >> 8) | ((x & 0x00FF00FF00FF00FF) << 8);
            x = ((x & 0xF0F0F0F0F0F0F0F0) >> 4) | ((x & 0x0F0F0F0F0F0F0F0F) << 4);
            x = ((x & 0xCCCCCCCCCCCCCCCC) >> 2) | ((x & 0x3333333333333333) << 2);
            x = ((x & 0xAAAAAAAAAAAAAAAA) >> 1) | ((x & 0x5555555555555555) << 1);
            return x;
        };

        def reverse_bits(i64 x) -> i64
        {
            u64 u = (u64)x;
            u = ((u & 0xFFFFFFFF00000000) >> 32) | ((u & 0x00000000FFFFFFFF) << 32);
            u = ((u & 0xFFFF0000FFFF0000) >> 16) | ((u & 0x0000FFFF0000FFFF) << 16);
            u = ((u & 0xFF00FF00FF00FF00) >> 8) | ((u & 0x00FF00FF00FF00FF) << 8);
            u = ((u & 0xF0F0F0F0F0F0F0F0) >> 4) | ((u & 0x0F0F0F0F0F0F0F0F) << 4);
            u = ((u & 0xCCCCCCCCCCCCCCCC) >> 2) | ((u & 0x3333333333333333) << 2);
            u = ((u & 0xAAAAAAAAAAAAAAAA) >> 1) | ((u & 0x5555555555555555) << 1);
            return (i64)u;
        };

        def rotate_x(Vec3* v, float s, float c) -> Vec3
        {
            Vec3 r;
            r.x = v.x;
            r.y = v.y * c - v.z * s;
            r.z = v.y * s + v.z * c;
            return r;
        };

        def rotate_y(Vec3* v, float s, float c) -> Vec3
        {
            Vec3 r;
            r.x =  v.x * c + v.z * s;
            r.y =  v.y;
            r.z = (v.x * -s) + v.z * c;
            return r;
        };

        def rotate_z(Vec3* v, float s, float c) -> Vec3
        {
            Vec3 r;
            r.x = v.x * c - v.y * s;
            r.y = v.x * s + v.y * c;
            r.z = v.z;
            return r;
        };

        def project(Vec3* v, int cx, int cy, float fov, float cam_z) -> POINT
        {
            float dz = v.z + cam_z;
            POINT p;
            if (dz < 0.001f)
            {
                p.x = cx;
                p.y = cy;
                return p;
            };
            p.x = cx + (int)(v.x * fov / dz);
            p.y = cy - (int)(v.y * fov / dz);
            return p;
        };
    };
};
