// Master Flux Example Program - Demonstrates ALL Flux keywords and features
// File: master_example.fx

import "standard.fx" as std;
import "math.fx";

using std::io, std::types;

// Namespace demonstration
namespace MathUtils
{
    // Template function with volatile modifier
    volatile def max<T>(T x, T y) -> T
    {
        return (x > y) ? x : y;
    };

    // Function with signed data type
    def calculate(signed data{32} value) -> signed data{32}
    {
        return value * 2;
    };
};

namespace DataStructures
{
    // Struct with various data types
    struct Point
    {
        float x, y;
        unsigned data{16} as flags;
    };

    // Object with inheritance and magic methods
    object Vector
    {
        float x, y, z;
        const bool is_normalized;

        def __init(float x, float y, float z) -> this
        {
            this.x = x;
            this.y = y;
            this.z = z;
            this.is_normalized = false;
            return this;
        };

        def __exit() -> void
        {
            return void;
        };

        def __add(this other) -> this
        {
            float new_x = this.x + other.x;
            float new_y = this.y + other.y;
            float new_z = this.z + other.z;
            return this(new_x, new_y, new_z);
        };

        def __eq(this other) -> bool
        {
            return (this.x == other.x) and (this.y == other.y) and (this.z == other.z);
        };

        def __expr() -> string
        {
            return i"Vector({}, {}, {})":{this.x; this.y; this.z;};
        };

        def magnitude() -> float
        {
            return (this.x ^ 2 + this.y ^ 2 + this.z ^ 2) ^ 0.5;
        };

        def normalize() -> this
        {
            float mag = this.magnitude();
            if (mag > 0.0)
            {
                this.x /= mag;
                this.y /= mag;
                this.z /= mag;
                this.is_normalized = true;
            };
            return this;
        };
    };

    // Inherited object method usage
    object Vector3D : Vector
    {
        float w;

        def __init(float x, float y, float z, float w) -> this
        {
            virtual::__init(x, y, z);
            this.w = w;
            return this;
        };

        def magnitude() -> float
        {
            float base_mag = super.magnitude();
            return (base_mag ^ 2 + this.w ^ 2) ^ 0.5;
        };

        // Nested object
        object Quaternion
        {
            super parent_vector();

            def __init() -> this
            {
                return this;
            };

            def __exit() -> void
            {
                return void;
            };
        };
    };
};

// Error handling object
object MathError
{
    string message;
    int error_code;

    def __init(string msg, int code) -> this
    {
        this.message = msg;
        this.error_code = code;
        return this;
    };

    def __expr() -> string
    {
        return i"MathError: {} (Code: {})":{this.message; this.error_code;};
    };

    def __exit() -> void
    {
        return void;
    };
};

// Template function with multiple parameters
def convert_and_operate<V,K,R>(V value1, K value2) -> R
{
    R result = (R)(value1 + value2);
    return result;
};

// Function demonstrating various data types and operations
def demonstrate_data_types() -> void
{
    // Basic types
    int integer_val = 42;
    float float_val = 3.14159;
    char character = "A";
    bool boolean_true = true;
    bool boolean_false = false;

    // Data types with different bit widths
    signed data{8} byte_val = 127;
    unsigned data{16} word_val = 65535;
    signed data{32} dword_val = -2147483648;
    unsigned data{64} qword_val = 18446744073709551615;

    // Binary literal
    unsigned data{8} binary_val = 10101010b;

    // Array types
    int[] int_array = [1, 2, 3, 4, 5];
    float[] float_array = [1.1, 2.2, 3.3];

    // String and character arrays
    string text = "Hello, Flux!";
    char[] char_array = ["H", "e", "l", "l", "o"];

    // Pointer types
    int* int_ptr = @integer_val;
    float* float_ptr = @float_val;

    // Function pointer
    int (*func_ptr)(int, int) = @MathUtils::calculate;

    // Template pointer
    template* tmpl_ptr = @MathUtils::max;

    // Demonstrate sizeof and typeof
    print(i"Size of int: {}":{sizeof(int);});
    print(i"Type of float_val: {}":{typeof(float_val);});

    // Demonstrate pointer arithmetic and dereferencing
    *int_ptr += 10;
    print(i"Dereferenced int_ptr: {}":{*int_ptr;});

    // Auto type inference
    auto {a, b} = DataStructures::Point{x,y};

    return void;
};

// Function demonstrating control flow with all keywords
def demonstrate_control_flow() -> int
{
    int result = 0;
    int counter = 0;

    // While loop with continue and break
    while (counter < 10)
    {
        counter++;
        
        if (counter % 2 == 0)
        {
            continue;
        }
        else if (counter > 7)
        {
            break;
        }
        else
        {
            result += counter;
        };
    };

    // For loop with array
    int[] numbers = [1, 2, 3, 4, 5];
    for (num in numbers)
    {
        result += num;
    };

    // Switch statement
    switch (result)
    {
        case (15)
        {
            print("Result is fifteen");
        };
        case (20)
        {
            print("Result is twenty");
        };
        default
        {
            print(i"Result is {}":{result;});
        };
    };

    // Do-while equivalent (using while with initial execution)
    do
    {
        result--;
    } while (result > 0);

    return result;
};

// Function demonstrating logical and bitwise operations
def demonstrate_operations() -> void
{
    int a = 5;
    int b = 3;
    bool flag1 = true;
    bool flag2 = false;

    // Logical operations using keywords
    if (flag1 and flag2)
    {
        print("Both flags are true");
    }
    else if (flag1 or flag2)
    {
        print("At least one flag is true");
    }
    else if (not flag1)
    {
        print("flag1 is false");
    }
    else if (flag1 xor flag2)
    {
        print("Exactly one flag is true");
    };

    // Identity operations
    if (a is int)
    {
        print("a is an integer");
    };

    if (flag1 is not void)
    {
        print("flag1 is not void");
    };

    // Casting with 'as' keyword
    float float_a = a as float;
    char char_b = (char)b;

    // Bitwise operations with special operators
    unsigned data{8} x = 170;  // 10101010b
    unsigned data{8} y = 85;   // 01010101b

    unsigned data{8} and_result = x `&& y;
    unsigned data{8} nand_result = x `!& y;
    unsigned data{8} or_result = x `| y;
    unsigned data{8} nor_result = x `!| y;
    unsigned data{8} xor_result = x `^^ y;
    unsigned data{8} xnor_result = x `^!| y;

    // Demonstrate 'in' operator
    if (3 in numbers)
    {
        print("3 is in the array");
    };

    return void;
};

// Function demonstrating error handling
def demonstrate_error_handling() -> int
{
    int result = 0;

    try
    {
        try
        {
            // Simulate a division by zero error
            int divisor = 0;
            if (divisor == 0)
            {
                MathError error("Division by zero", 100);
                throw(error);
            };
        }
        catch (auto err)  // Auto-typed catch
        {
            print(i"Caught error: {}":{err;});
            throw("Re-throwing as string error");
        };
    }
    catch (string error_msg)
    {
        print(i"Final catch: {}":{error_msg;});
        result = -1;
    };

    return result;
};

// Function with inline assembly
def demonstrate_assembly() -> int
{
    int result = 42;
    
    // Inline assembly block
    asm
    {
        mov eax, result
        mov ebx, 0
        int 0x80
    };

    return result;
};

// Function demonstrating array comprehensions and destructuring
def demonstrate_advanced_features() -> void
{
    // Array comprehensions
    int[] squares = [x ^ 2 for (x in 1..10)];
    int[] evens = [x for (x in 1..20) if (x % 2 == 0)];

    // Multi-dimensional array comprehension
    int[][] matrix = [i * j for (j in 1..5)][i * k for (k in 1..5)];

    // Destructuring assignment
    DataStructures::Point p = {x = 10.0, y = 20.0};
    auto {px, py} = p{x, y};

    // I-string with complex expressions
    string formatted = i"Point at ({}, {}) with squares [{}, {}]":
    {
        px;
        py;
        squares[0];
        squares[1];
    };

    print(formatted);

    return void;
};

// Enum demonstration (using object pattern since enum is a keyword but not fully specified)
object Color
{
    const int RED = 1;
    const int GREEN = 2;
    const int BLUE = 3;
};

// Assert demonstration function
def demonstrate_assertions(int value) -> bool
{
    assert(value > 0);  // Assert keyword usage
    assert(value < 100);
    return true;
};

// Main function - entry point
def main() -> int
{
    print("=== Flux Language Master Example ===");

    // Demonstrate all major language features
    print("\n1. Data Types Demonstration:");
    demonstrate_data_types();

    print("\n2. Control Flow Demonstration:");
    int control_result = demonstrate_control_flow();

    print("\n3. Operations Demonstration:");
    demonstrate_operations();

    print("\n4. Error Handling Demonstration:");
    int error_result = demonstrate_error_handling();

    print("\n5. Assembly Demonstration:");
    int asm_result = demonstrate_assembly();

    print("\n6. Advanced Features Demonstration:");
    demonstrate_advanced_features();

    print("\n7. Object-Oriented Features:");
    DataStructures::Vector vec1(1.0, 2.0, 3.0);
    DataStructures::Vector vec2(4.0, 5.0, 6.0);
    DataStructures::Vector vec3 = vec1 + vec2;
    
    print(i"Vector 1: {}":{vec1;});
    print(i"Vector 2: {}":{vec2;});
    print(i"Sum: {}":{vec3;});

    // Test inheritance
    DataStructures::Vector3D vec4d(1.0, 2.0, 3.0, 4.0);
    print(i"4D Vector magnitude: {}":{vec4d.magnitude();});

    print("\n8. Template Usage:");
    int max_int = MathUtils::max<int>(10, 20);
    float max_float = MathUtils::max<float>(3.14, 2.71);
    print(i"Max int: {}, Max float: {}":{max_int; max_float;});

    print("\n9. Namespace Usage:");
    signed data{32} calc_result = MathUtils::calculate(15);
    print(i"Calculation result: {}":{calc_result;});

    print("\n10. Assertion Testing:");
    bool assertion_result = demonstrate_assertions(50);

    // Final results
    print("\n=== Program Execution Complete ===");
    print(i"Control flow result: {}":{control_result;});
    print(i"Error handling result: {}":{error_result;});
    print(i"Assembly result: {}":{asm_result;});

    // Demonstrate const and volatile
    const int final_value = 42;
    volatile int changing_value = final_value;

    return 0;  // Success
};