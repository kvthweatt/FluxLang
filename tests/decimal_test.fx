// Decimal Library for Flux - Arbitrary Precision Base-10 Floating Point
// Supports: init, print, copy, compare, add, subtract, multiply, divide, modulo, power, sqrt, round
#import "standard.fx", "decimal.fx";

// Decimal structure - stores arbitrary precision decimals as:
//   value = (-1)^negative * coefficient * 10^exponent
//   coefficient : BigInt (unsigned magnitude)
//   exponent    : i32    (power of ten, may be negative)
//   negative    : bool   (sign flag; zero is always positive)

using math::bigint;
using math::decimal;

def main() -> int
{
    Decimal a;
    Decimal b;
    Decimal result;
    Decimal result2;
    i32 cmp;

    print("==== DECIMAL LIBRARY FOUNDATION TEST ====\n\n\0");

    // Test 1: Zero
    print("Test 1: Zero\n\0");
    decimal_zero(@a);
    print("Value: \0");
    decimal_print(@a);
    print("\n");
    print("is_zero: \0");
    if (decimal_is_zero(@a))
    {
        print("true\n\0");
    }
    else
    {
        print("false\n\0");
    };
    print("\n\0");

    // Test 2: One
    print("Test 2: One\n\0");
    decimal_one(@a);
    print("Value: \0");
    decimal_print(@a);
    print("\n");
    print("is_zero: \0");
    if (decimal_is_zero(@a))
    {
        print("true\n\0");
    }
    else
    {
        print("false\n\0");
    };
    print("\n\0");

    // Test 3: From positive i64
    print("Test 3: From i64 (123456789)\n\0");
    decimal_from_i64(@a, 123456789);
    print("Value: \0");
    decimal_print(@a);
    print("\n\n\0");

    // Test 4: From negative i64
    print("Test 4: From i64 (-987654321)\n\0");
    decimal_from_i64(@a, -987654321);
    print("Value: \0");
    decimal_print(@a);
    print("\n");
    print("is_negative: \0");
    if (decimal_is_negative(@a))
    {
        print("true\n\0");
    }
    else
    {
        print("false\n\0");
    };
    print("\n\0");

    // Test 5: From string - simple decimal
    print("Test 5: From string (\"3.14\")\n\0");
    decimal_from_string(@a, "3.14\0");
    print("Value: \0");
    decimal_print(@a);
    print("\n\n\0");

    // Test 6: From string - negative decimal
    print("Test 6: From string (\"-2.71828\")\n\0");
    decimal_from_string(@a, "-2.71828\0");
    print("Value: \0");
    decimal_print(@a);
    print("\n\n\0");

    // Test 7: From string - scientific notation
    print("Test 7: From string (\"1.5E+3\")\n\0");
    decimal_from_string(@a, "1.5E+3\0");
    print("Value: \0");
    decimal_print(@a);
    print("\nSci:   \0");
    decimal_print_sci(@a);
    print("\n\n\0");

    // Test 8: From string - negative exponent
    print("Test 8: From string (\"9.99E-4\")\n\0");
    decimal_from_string(@a, "9.99E-4\0");
    print("Value: \0");
    decimal_print(@a);
    print("\nSci:   \0");
    decimal_print_sci(@a);
    print("\n\n\0");

    // Test 9: Add two positive decimals
    print("Test 9: Add (1.5 + 2.75)\n\0");
    decimal_from_string(@a, "1.5\0");
    decimal_from_string(@b, "2.75\0");
    decimal_add(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 10: Add positive and negative
    print("Test 10: Add (10.0 + -3.5)\n\0");
    decimal_from_string(@a, "10.0\0");
    decimal_from_string(@b, "-3.5\0");
    decimal_add(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 11: Subtract
    print("Test 11: Subtract (100.25 - 50.75)\n\0");
    decimal_from_string(@a, "100.25\0");
    decimal_from_string(@b, "50.75\0");
    decimal_sub(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 12: Subtract to negative
    print("Test 12: Subtract (3.0 - 7.5)\n\0");
    decimal_from_string(@a, "3.0\0");
    decimal_from_string(@b, "7.5\0");
    decimal_sub(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 13: Multiply
    print("Test 13: Multiply (12.5 * 4.0)\n\0");
    decimal_from_string(@a, "12.5\0");
    decimal_from_string(@b, "4.0\0");
    decimal_mul(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 14: Multiply with negative
    print("Test 14: Multiply (-3.0 * 2.5)\n\0");
    decimal_from_string(@a, "-3.0\0");
    decimal_from_string(@b, "2.5\0");
    decimal_mul(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 15: Divide exact
    print("Test 15: Divide (10.0 / 4.0)\n\0");
    decimal_from_string(@a, "10.0\0");
    decimal_from_string(@b, "4.0\0");
    decimal_div(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 16: Divide repeating
    print("Test 16: Divide (1.0 / 3.0)\n\0");
    decimal_from_string(@a, "1.0\0");
    decimal_from_string(@b, "3.0\0");
    decimal_div(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 17: Modulo
    print("Test 17: Modulo (10.0 % 3.0)\n\0");
    decimal_from_string(@a, "10.0\0");
    decimal_from_string(@b, "3.0\0");
    decimal_mod(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 18: Power (positive exponent)
    print("Test 18: Power (2.0 ^ 10)\n\0");
    decimal_from_string(@a, "2.0\0");
    decimal_pow_int(@result, @a, 10);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 19: Power (negative exponent)
    print("Test 19: Power (10.0 ^ -2)\n\0");
    decimal_from_string(@a, "10.0\0");
    decimal_pow_int(@result, @a, -2);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 20: Absolute value
    print("Test 20: Absolute value (|-42.5|)\n\0");
    decimal_from_string(@a, "-42.5\0");
    decimal_abs(@result, @a);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 21: Negate
    print("Test 21: Negate (-(-99.9))\n\0");
    decimal_from_string(@a, "-99.9\0");
    decimal_neg(@result, @a);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 22: Compare equal
    print("Test 22: Compare equal (1.50 == 1.5)\n\0");
    decimal_from_string(@a, "1.50\0");
    decimal_from_string(@b, "1.5\0");
    cmp = decimal_cmp(@a, @b);
    if (cmp == 0)
    {
        print("Equal: true\n\0");
    }
    else
    {
        print("Equal: false\n\0");
    };
    print("\n\0");

    // Test 23: Compare less than
    print("Test 23: Compare less than (0.999 < 1.0)\n\0");
    decimal_from_string(@a, "0.999\0");
    decimal_from_string(@b, "1.0\0");
    cmp = decimal_cmp(@a, @b);
    if (cmp < 0)
    {
        print("Less: true\n\0");
    }
    else
    {
        print("Less: false\n\0");
    };
    print("\n\0");

    // Test 24: Compare greater than
    print("Test 24: Compare greater than (100.001 > 100.0)\n\0");
    decimal_from_string(@a, "100.001\0");
    decimal_from_string(@b, "100.0\0");
    cmp = decimal_cmp(@a, @b);
    if (cmp > 0)
    {
        print("Greater: true\n\0");
    }
    else
    {
        print("Greater: false\n\0");
    };
    print("\n\0");

    // Test 25: Round half-up
    print("Test 25: Round (2.675 to 2 places)\n\0");
    decimal_from_string(@a, "2.675\0");
    decimal_round(@result, @a, 2);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 26: Truncate
    print("Test 26: Truncate (3.9999 to 2 places)\n\0");
    decimal_from_string(@a, "3.9999\0");
    decimal_truncate(@result, @a, 2);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 27: Floor
    print("Test 27: Floor (3.7)\n\0");
    decimal_from_string(@a, "3.7\0");
    decimal_floor(@result, @a);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 28: Floor negative
    print("Test 28: Floor (-3.2)\n\0");
    decimal_from_string(@a, "-3.2\0");
    decimal_floor(@result, @a);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 29: Ceiling
    print("Test 29: Ceiling (3.2)\n\0");
    decimal_from_string(@a, "3.2\0");
    decimal_ceil(@result, @a);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 30: Square root
    print("Test 30: Square root (sqrt(2.0))\n\0");
    decimal_from_string(@a, "2.0\0");
    decimal_sqrt(@result, @a);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 31: Square root (perfect square)
    print("Test 31: Square root (sqrt(144.0))\n\0");
    decimal_from_string(@a, "144.0\0");
    decimal_sqrt(@result, @a);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 32: Round-trip multiply then divide
    print("Test 32: Round-trip (123.456 * 1000 / 1000 == 123.456)\n\0");
    decimal_from_string(@a, "123.456\0");
    decimal_from_string(@b, "1000.0\0");
    decimal_mul(@result, @a, @b);
    decimal_div(@result2, @result, @b);
    cmp = decimal_cmp(@result2, @a);
    if (cmp == 0)
    {
        print("Round-trip: true\n\0");
    }
    else
    {
        print("Round-trip: false\n\0");
    };
    print("\n\0");

    // Test 33: Large integer from string
    print("Test 33: Large integer (\"99999999999999999999\")\n\0");
    decimal_from_string(@a, "99999999999999999999\0");
    print("Value: \0");
    decimal_print(@a);
    print("\n\n\0");

    // Test 34: Large multiply
    print("Test 34: Large multiply (99999999999999999999 * 2)\n\0");
    decimal_from_string(@a, "99999999999999999999\0");
    decimal_from_string(@b, "2.0\0");
    decimal_mul(@result, @a, @b);
    print("Result: \0");
    decimal_print(@result);
    print("\n\n\0");

    // Test 35: Precision and scientific notation
    print("Test 35: Scientific notation (0.000123456)\n\0");
    decimal_from_string(@a, "0.000123456\0");
    print("Standard: \0");
    decimal_print(@a);
    print("\nSci:      \0");
    decimal_print_sci(@a);
    print("\n\n\0");

    print("==== ALL TESTS COMPLETE ====\n\0");

    return 0;
};
