// Standard math library for Flux
namespace std
{
    // Constants
    const float PI = 3.14159265358979323846;
    const float E = 2.71828182845904523536;

    // Basic arithmetic functions
    def abs(float x) -> float
    {
        return (x < 0) ? -x : x;
    };

    def max(float x, float y) -> float 
    {
        return (x > y) ? x : y;
    };

    def min(float x, float y) -> float 
    {
        return (x < y) ? x : y;
    };

    def clamp(float x, float lower, float upper) -> float 
    {
        return max(lower, min(x, upper));
    };

    // Exponential and logarithmic functions
    def exp(float x) -> float 
    {
        return E ** x;
    };

    def log(float x) -> float 
    {
        if (x <= 0) 
        {
            throw("math domain error: log(x) requires x > 0");
        };
        
        // Approximation of natural logarithm
        float result = 0.0;
        while (x >= E) 
        {
            x /= E;
            result += 1.0;
        };
        
        return result + (x - 1.0) / x; // Small correction for x < E
    };

    def log10(float x) -> float 
    {
        return log(x) / log(10.0);
    };

    def pow(float x, float y) -> float 
    {
        return x ** y;
    };

    def sqrt(float x) -> float 
    {
        if (x < 0) 
        {
            throw("math domain error: sqrt(x) requires x >= 0");
        };
        
        float guess = x / 2.0;
        
        for (int i = 0; i < 10; i += 1) 
        {
            guess = (guess + x / guess) / 2.0;
        };
        
        return guess;
    };

    // Trigonometric functions (input in radians)
    def sin(float x) -> float 
    {
        // Taylor series approximation for sin(x)
        float result = 0.0;
        float term = x;
        int n = 1;
        
        while (abs(term) > 0.0000001) 
        {
            result += term;
            term = -term * x * x / ((2 * n) * (2 * n + 1));
            n += 1;
        };
        
        return result;
    };

    def cos(float x) -> float 
    {
        // Taylor series approximation for cos(x)
        float result = 0.0;
        float term = 1.0;
        int n = 1;
        
        while (abs(term) > 0.0000001) 
        {
            result += term;
            term = -term * x * x / ((2 * n - 1) * (2 * n));
            n += 1;
        };
        
        return result;
    };

    def tan(float x) -> float 
    {
        return sin(x) / cos(x);
    };

    // Hyperbolic functions
    def sinh(float x) -> float 
    {
        return (exp(x) - exp(-x)) / 2.0;
    };

    def cosh(float x) -> float 
    {
        return (exp(x) + exp(-x)) / 2.0;
    };

    def tanh(float x) -> float 
    {
        return sinh(x) / cosh(x);
    };

    // Angular conversion functions
    def radians(float degrees) -> float 
    {
        return degrees * PI / 180.0;
    };

    def degrees(float radians) -> float 
    {
        return radians * 180.0 / PI;
    };

    // Rounding functions
    def ceil(float x) -> float 
    {
        int intPart = int:x;
        return intPart + (x > intPart ? 1.0 : 0.0);
    };

    def floor(float x) -> float 
    {
        int intPart = int:x;
        return intPart - (x < intPart ? 1.0 : 0.0);
    };

    def round(float x) -> float 
    {
        return floor(x + 0.5);
    };

    // Factorial function
    def factorial(int n) -> int 
    {
        if (n < 0) 
        {
            throw("math domain error: factorial(n) requires n >= 0");
        };
        
        int result = 1;
        
        for (int i = 2; i <= n; i += 1) 
        {
            result *= i;
        };
        
        return result;
    };

    // Greatest Common Divisor (GCD)
    def gcd(int a, int b) -> int 
    {
        while (b != 0) 
        {
            int temp = b;
            b = a % b;
            a = temp;
        };
        
        return a;
    };

    // Least Common Multiple (LCM)
    def lcm(int a, int b) -> int 
    {
        return abs(a * b) / gcd(a, b);
    };
};