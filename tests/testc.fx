#import "standard.fx";

using standard::io::console;
using standard::collections;

// Custom data type - 12-bit signed value, 16-bit aligned
signed data{12:16} as fixed12;

// Trait - the only way to impose contracts on objects
trait Drawable
{
    def draw() -> void,
        area() -> float;
};

// Template function
def clamp<T>(T value, T min, T max) -> T
{
    return (value < min) ? min : (value > max) ? max : value;
};

// Custom operator
operator (int[] L, int[] R) [dot] -> int
{
    if (sizeof(L) != sizeof(R) | sizeof(L) == 0)
    {
        return 0;
    };
    
    int result = 0;
    for (int i = 0; i < sizeof(L) / sizeof(int); i++)
    {
        result += L[i] * R[i];
    };
    return result;
};

// Rectangle implements ALL trait methods
Drawable object Rectangle
{
    float width, height;
    
    def __init(float w, float h) -> this
    {
        this.width = w;
        this.height = h;
        return this;
    };
    
    def draw() -> void
    {
        print("Drawing a rectangle!\0");
    };
    
    def area() -> float
    {
        return this.width * this.height;
    };
    
    def __exit() -> void
    {
        return;
    };
};

// Circle implements ALL trait methods
Drawable object Circle
{
    float radius;
    
    def __init(float r) -> this
    {
        this.radius = r;
        return this;
    };
    
    def draw() -> void
    {
        print("Drawing a circle!\0");
    };
    
    def area() -> float
    {
        return 3.14159 * this.radius * this.radius;
    };
    
    def __exit() -> void
    {
        return;
    };
};

// Error handling object
object MathError
{
    string message;
    int code;
    
    def __init(string msg, int c) -> this
    {
        this.message = msg;
        this.code = c;
        return this;
    };
    
    def __exit() -> void
    {
        return;
    };
};

def safe_divide(float a, float b) -> float
{
    if (b == 0.0)
    {
        MathError err("Division by zero\0", 100);
        throw(err);
    };
    return a / b;
};

// Bit manipulation
def reverse_bits(byte x) -> byte
{
    byte result = 0;
    for (int i = 0; i < 8; i++)
    {
        result = (result << 1) | ((x >> i) & 1);
    };
    return result;
};

// Struct with custom bit-width fields (tightly packed)
struct RGB565
{
    unsigned data{5} as r5 r;
    unsigned data{6} as g6 g;
    unsigned data{5} as b5 b;
};

def rgb565_to_rgb888(RGB565 color) -> void
{
    // Expand 5-bit to 8-bit (multiply by 8)
    byte r = (byte)(color.r << 3);
    byte g = (byte)(color.g << 2);
    byte b = (byte)(color.b << 3);
    
    print(f"R: {r}, G: {g}, B: {b}\0");
};

// Stringification example
def main() -> int
{
    int magic = 42;
    print(f"The answer is: {magic}\0");
    print();
    
    // Test template
    float clamped = clamp<float>(15.7, 0.0, 10.0);
    print(f"Clamped value: {clamped}\0");
    
    // Test objects
    Rectangle rect(10.0, 5.0);
    Circle circ(7.0);
    
    rect.draw();
    print(f"Rectangle area: {rect.area()}\0");
    circ.draw();
    print(f"Circle area: {circ.area()}\0");
    
    // Test array dot product with custom operator
    int[3] a = [1, 2, 3];
    int[3] b = [4, 5, 6];
    int result = a dot b;  // 1*4 + 2*5 + 3*6 = 32
    print(f"Dot product: {result}\0");
    
    // Test error handling
    try
    {
        float div = safe_divide(10.0, 0.0);
    }
    catch (MathError e)
    {
        print(f"Error {e.code}: {e.message}\0");
    };
    
    // Test bit reversal
    byte original = 0b10110010;
    byte reversed = reverse_bits(original);
    print(f"Original: {original}, Reversed: {reversed}\0");
    
    // Test RGB565 struct
    RGB565 pixel = {r = 31, g = 63, b = 31};  // Max values
    rgb565_to_rgb888(pixel);
    
    // Test singinit (single initialization across calls)
    singinit int counter = 0;
    for (int i = 0; i < 5; i++)
    {
        counter++;
        print(f"Call {i+1}: counter = {counter}\0");
    };
    
    return 0;
};