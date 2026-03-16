#import "standard.fx";
#import "decimal.fx";

using standard::io::console;
using math::decimal;

// -----------------------------------------------------------------------
// Helper: print a labelled result line
// -----------------------------------------------------------------------
def print_label(byte* label) -> void
{
    print(label);
    print(": \0");
    return;
};

def pass_fail(bool ok) -> void
{
    if (ok)
    {
        print("  [PASS]\0");
    }
    else
    {
        print("  [FAIL]\0");
    };
    print("\n\0");
    return;
};

// -----------------------------------------------------------------------
// Section header
// -----------------------------------------------------------------------
def section(byte* name) -> void
{
    print("\n--- \0");
    print(name);
    print(" ---\n\0");
    return;
};

// -----------------------------------------------------------------------
// main
// -----------------------------------------------------------------------
def main() -> int
{
    print("=== Decimal Library Test Suite ===\n\0");

    // ===================================================================
    // 1. Precision control
    // ===================================================================
    section("Precision control\0");

    i32 default_prec = decimal_get_precision();
    print_label("Default precision\0");
    print((int)default_prec);
    print("\n\0");

    decimal_set_precision(10);
    print_label("Set to 10\0");
    print((int)decimal_get_precision());
    pass_fail(decimal_get_precision() == 10);

    decimal_set_precision(0);   // should clamp to 1
    print_label("Clamp to 1\0");
    print((int)decimal_get_precision());
    pass_fail(decimal_get_precision() == 1);

    decimal_set_precision(28);  // restore default

    // ===================================================================
    // 2. Initialisation
    // ===================================================================
    section("Initialisation\0");

    Decimal d;

    decimal_zero(@d);
    print_label("decimal_zero is_zero\0");
    pass_fail(decimal_is_zero(@d));

    decimal_one(@d);
    print_label("decimal_one is_positive\0");
    pass_fail(decimal_is_positive(@d));

    decimal_from_i64(@d, 42);
    print_label("from_i64(42)\0");
    decimal_print(@d);
    print("\n\0");

    decimal_from_i64(@d, -99);
    print_label("from_i64(-99)\0");
    decimal_print(@d);
    print("\n\0");

    decimal_from_u64(@d, 18446744073709551615);  // u64 max
    print_label("from_u64(u64_max)\0");
    decimal_print(@d);
    print("\n\0");

    // ===================================================================
    // 3. Parsing from string
    // ===================================================================
    section("Parsing from string\0");

    Decimal a, b, result;

    decimal_from_string(@a, "3.14159265358979323846\0");
    print_label("parse 3.14159...\0");
    decimal_print(@a);
    print("\n\0");

    decimal_from_string(@a, "-0.001\0");
    print_label("parse -0.001\0");
    decimal_print(@a);
    print("\n\0");

    decimal_from_string(@a, "1E+10\0");
    print_label("parse 1E+10\0");
    decimal_print(@a);
    print("\n\0");

    decimal_from_string(@a, "1.5e-3\0");
    print_label("parse 1.5e-3\0");
    decimal_print(@a);
    print("\n\0");

    decimal_from_string(@a, "+42\0");
    print_label("parse +42\0");
    decimal_print(@a);
    print("\n\0");

    decimal_from_string(@a, "0\0");
    print_label("parse 0 is_zero\0");
    pass_fail(decimal_is_zero(@a));

    // ===================================================================
    // 4. Predicates
    // ===================================================================
    section("Predicates\0");

    decimal_from_i64(@a, 5);
    decimal_from_i64(@b, -5);
    Decimal z;
    decimal_zero(@z);

    print_label("5 is_positive\0");
    pass_fail(decimal_is_positive(@a));

    print_label("-5 is_negative\0");
    pass_fail(decimal_is_negative(@b));

    print_label("0 is_zero\0");
    pass_fail(decimal_is_zero(@z));

    print_label("0 not is_positive\0");
    pass_fail(!decimal_is_positive(@z));

    print_label("0 not is_negative\0");
    pass_fail(!decimal_is_negative(@z));

    // ===================================================================
    // 5. Comparison
    // ===================================================================
    section("Comparison\0");

    decimal_from_string(@a, "1.5\0");
    decimal_from_string(@b, "2.5\0");

    print_label("1.5 < 2.5  => -1\0");
    pass_fail(decimal_cmp(@a, @b) == -1);

    print_label("2.5 > 1.5  => 1\0");
    pass_fail(decimal_cmp(@b, @a) == 1);

    decimal_from_string(@a, "3.0\0");
    decimal_from_string(@b, "3.0\0");
    print_label("3.0 == 3.0 => 0\0");
    pass_fail(decimal_cmp(@a, @b) == 0);

    decimal_from_string(@a, "-2.0\0");
    decimal_from_string(@b, "-3.0\0");
    print_label("-2 > -3 => 1\0");
    pass_fail(decimal_cmp(@a, @b) == 1);

    // cmp_abs ignores sign
    decimal_from_string(@a, "-5\0");
    decimal_from_string(@b, "3\0");
    print_label("cmp_abs(-5, 3) => 1\0");
    pass_fail(decimal_cmp_abs(@a, @b) == 1);

    // ===================================================================
    // 6. Addition
    // ===================================================================
    section("Addition\0");

    decimal_from_string(@a, "1.1\0");
    decimal_from_string(@b, "2.2\0");
    decimal_add(@result, @a, @b);
    print_label("1.1 + 2.2\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "-5\0");
    decimal_from_string(@b, "3\0");
    decimal_add(@result, @a, @b);
    print_label("-5 + 3\0");
    decimal_print(@result);
    print("\n\0");
    Decimal two_ref;
    decimal_from_i64(@two_ref, 2);
    pass_fail(decimal_cmp_abs(@result, @two_ref) == 0 & decimal_is_negative(@result));

    decimal_from_string(@a, "999.999\0");
    decimal_from_string(@b, "0.001\0");
    decimal_add(@result, @a, @b);
    print_label("999.999 + 0.001\0");
    decimal_print(@result);
    print("\n\0");

    // adding zero
    decimal_from_string(@a, "7\0");
    decimal_zero(@b);
    decimal_add(@result, @a, @b);
    print_label("7 + 0\0");
    decimal_print(@result);
    print("\n\0");

    // ===================================================================
    // 7. Subtraction
    // ===================================================================
    section("Subtraction\0");

    decimal_from_string(@a, "10\0");
    decimal_from_string(@b, "3.5\0");
    decimal_sub(@result, @a, @b);
    print_label("10 - 3.5\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "-4\0");
    decimal_from_string(@b, "-6\0");
    decimal_sub(@result, @a, @b);
    print_label("-4 - (-6)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "1\0");
    decimal_from_string(@b, "1\0");
    decimal_sub(@result, @a, @b);
    print_label("1 - 1 = 0\0");
    pass_fail(decimal_is_zero(@result));

    // ===================================================================
    // 8. Multiplication
    // ===================================================================
    section("Multiplication\0");

    decimal_from_string(@a, "3\0");
    decimal_from_string(@b, "4\0");
    decimal_mul(@result, @a, @b);
    print_label("3 * 4\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "-2.5\0");
    decimal_from_string(@b, "4\0");
    decimal_mul(@result, @a, @b);
    print_label("-2.5 * 4\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "1.23456789\0");
    decimal_from_string(@b, "9.87654321\0");
    decimal_mul(@result, @a, @b);
    print_label("1.23456789 * 9.87654321\0");
    decimal_print(@result);
    print("\n\0");

    // multiply by zero
    decimal_from_string(@a, "12345\0");
    decimal_zero(@b);
    decimal_mul(@result, @a, @b);
    print_label("12345 * 0 = 0\0");
    pass_fail(decimal_is_zero(@result));

    // ===================================================================
    // 9. Division
    // ===================================================================
    section("Division\0");

    decimal_from_string(@a, "10\0");
    decimal_from_string(@b, "4\0");
    decimal_div(@result, @a, @b);
    print_label("10 / 4\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "1\0");
    decimal_from_string(@b, "3\0");
    decimal_div(@result, @a, @b);
    print_label("1 / 3 (28 digits)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "22\0");
    decimal_from_string(@b, "7\0");
    decimal_div(@result, @a, @b);
    print_label("22 / 7 (pi approx)\0");
    decimal_print(@result);
    print("\n\0");

    // divide by 1
    decimal_from_string(@a, "9999\0");
    decimal_one(@b);
    decimal_div(@result, @a, @b);
    print_label("9999 / 1\0");
    decimal_print(@result);
    print("\n\0");

    // divide zero
    decimal_zero(@a);
    decimal_from_string(@b, "5\0");
    decimal_div(@result, @a, @b);
    print_label("0 / 5 = 0\0");
    pass_fail(decimal_is_zero(@result));

    // divide by zero (should return zero safely)
    decimal_from_string(@a, "5\0");
    decimal_zero(@b);
    decimal_div(@result, @a, @b);
    print_label("5 / 0 = 0 (safe)\0");
    pass_fail(decimal_is_zero(@result));

    // ===================================================================
    // 10. Modulo
    // ===================================================================
    section("Modulo\0");

    decimal_from_string(@a, "10\0");
    decimal_from_string(@b, "3\0");
    decimal_mod(@result, @a, @b);
    print_label("10 mod 3\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "7\0");
    decimal_from_string(@b, "7\0");
    decimal_mod(@result, @a, @b);
    print_label("7 mod 7 = 0\0");
    pass_fail(decimal_is_zero(@result));

    decimal_from_string(@a, "100\0");
    decimal_from_string(@b, "30\0");
    decimal_mod(@result, @a, @b);
    print_label("100 mod 30\0");
    decimal_print(@result);
    print("\n\0");

    // ===================================================================
    // 11. Power (integer exponent)
    // ===================================================================
    section("Power\0");

    decimal_from_string(@a, "2\0");
    decimal_pow_int(@result, @a, 10);
    print_label("2 ^ 10\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "3\0");
    decimal_pow_int(@result, @a, 0);
    print_label("3 ^ 0 = 1\0");
    Decimal pow_one;
    decimal_one(@pow_one);
    pass_fail(decimal_cmp(@result, @pow_one) == 0);

    decimal_from_string(@a, "10\0");
    decimal_pow_int(@result, @a, 6);
    print_label("10 ^ 6\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "2\0");
    decimal_pow_int(@result, @a, -3);
    print_label("2 ^ -3 = 0.125\0");
    decimal_print(@result);
    print("\n\0");

    // ===================================================================
    // 12. Negation and absolute value
    // ===================================================================
    section("Negate / Abs\0");

    decimal_from_string(@a, "7.5\0");
    decimal_neg(@result, @a);
    print_label("neg(7.5)\0");
    decimal_print(@result);
    print("\n\0");
    pass_fail(decimal_is_negative(@result));

    decimal_neg(@result, @result);
    print_label("neg(neg(7.5))\0");
    decimal_print(@result);
    print("\n\0");
    pass_fail(decimal_is_positive(@result));

    decimal_from_string(@a, "-42\0");
    decimal_abs(@result, @a);
    print_label("abs(-42)\0");
    decimal_print(@result);
    print("\n\0");
    pass_fail(decimal_is_positive(@result));

    // neg of zero stays positive
    decimal_zero(@a);
    decimal_neg(@result, @a);
    print_label("neg(0) stays 0\0");
    pass_fail(decimal_is_zero(@result) & !decimal_is_negative(@result));

    // ===================================================================
    // 13. Round
    // ===================================================================
    section("Rounding\0");

    decimal_from_string(@a, "3.14159\0");
    decimal_round(@result, @a, 2);
    print_label("round(3.14159, 2)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "2.5\0");
    decimal_round(@result, @a, 0);
    print_label("round(2.5, 0) half-up\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "-1.005\0");
    decimal_round(@result, @a, 2);
    print_label("round(-1.005, 2)\0");
    decimal_print(@result);
    print("\n\0");

    // ===================================================================
    // 14. Truncate
    // ===================================================================
    section("Truncate\0");

    decimal_from_string(@a, "9.9999\0");
    decimal_truncate(@result, @a, 2);
    print_label("truncate(9.9999, 2)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "-3.7\0");
    decimal_truncate(@result, @a, 0);
    print_label("truncate(-3.7, 0)\0");
    decimal_print(@result);
    print("\n\0");

    // ===================================================================
    // 15. Floor and Ceiling
    // ===================================================================
    section("Floor / Ceiling\0");

    decimal_from_string(@a, "3.7\0");
    decimal_floor(@result, @a);
    print_label("floor(3.7)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "-3.2\0");
    decimal_floor(@result, @a);
    print_label("floor(-3.2)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "3.2\0");
    decimal_ceil(@result, @a);
    print_label("ceil(3.2)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "-3.7\0");
    decimal_ceil(@result, @a);
    print_label("ceil(-3.7)\0");
    decimal_print(@result);
    print("\n\0");

    // exact integers are unchanged
    decimal_from_string(@a, "5\0");
    decimal_floor(@result, @a);
    print_label("floor(5) = 5\0");
    pass_fail(decimal_cmp(@result, @a) == 0);

    decimal_ceil(@result, @a);
    print_label("ceil(5) = 5\0");
    pass_fail(decimal_cmp(@result, @a) == 0);

    // ===================================================================
    // 16. Square root
    // ===================================================================
    section("Square root\0");

    decimal_from_string(@a, "2\0");
    decimal_sqrt(@result, @a);
    print_label("sqrt(2)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "9\0");
    decimal_sqrt(@result, @a);
    print_label("sqrt(9)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_string(@a, "0.25\0");
    decimal_sqrt(@result, @a);
    print_label("sqrt(0.25)\0");
    decimal_print(@result);
    print("\n\0");

    decimal_from_i64(@a, 0);
    decimal_sqrt(@result, @a);
    print_label("sqrt(0) = 0\0");
    pass_fail(decimal_is_zero(@result));

    // sqrt of negative => zero
    decimal_from_i64(@a, -4);
    decimal_sqrt(@result, @a);
    print_label("sqrt(-4) = 0 (undefined)\0");
    pass_fail(decimal_is_zero(@result));

    // ===================================================================
    // 17. Scientific-notation print
    // ===================================================================
    section("Scientific notation print\0");

    decimal_from_string(@a, "3.14159265358979\0");
    print_label("sci 3.14159...\0");
    decimal_print_sci(@a);
    print("\n\0");

    decimal_from_i64(@a, 0);
    print_label("sci 0\0");
    decimal_print_sci(@a);
    print("\n\0");

    decimal_from_string(@a, "-0.000123\0");
    print_label("sci -0.000123\0");
    decimal_print_sci(@a);
    print("\n\0");

    decimal_from_string(@a, "1000000\0");
    print_label("sci 1000000\0");
    decimal_print_sci(@a);
    print("\n\0");

    // ===================================================================
    // 18. Copy
    // ===================================================================
    section("Copy\0");

    decimal_from_string(@a, "123.456\0");
    decimal_copy(@b, @a);
    print_label("copy equals original\0");
    pass_fail(decimal_cmp(@a, @b) == 0);

    // Mutate copy, original unchanged
    decimal_from_i64(@b, 999);
    print_label("original after mutation\0");
    decimal_print(@a);
    print("\n\0");

    // ===================================================================
    // 19. High-precision arithmetic
    // ===================================================================
    section("High-precision (28 digits)\0");

    decimal_set_precision(28);

    // pi approximation: 355/113
    decimal_from_string(@a, "355\0");
    decimal_from_string(@b, "113\0");
    decimal_div(@result, @a, @b);
    print_label("355/113 (pi approx, 28 digits)\0");
    decimal_print(@result);
    print("\n\0");

    // Large multiplication
    decimal_from_string(@a, "123456789012345678\0");
    decimal_from_string(@b, "987654321098765432\0");
    decimal_mul(@result, @a, @b);
    print_label("large int multiply\0");
    decimal_print(@result);
    print("\n\0");

    // Chain: (1.1 + 2.2) * 3.3 / 4.4
    decimal_from_string(@a, "1.1\0");
    decimal_from_string(@b, "2.2\0");
    Decimal tmp, tmp2;
    decimal_add(@tmp, @a, @b);
    decimal_from_string(@a, "3.3\0");
    decimal_mul(@tmp2, @tmp, @a);
    decimal_from_string(@b, "4.4\0");
    decimal_div(@result, @tmp2, @b);
    print_label("(1.1+2.2)*3.3/4.4\0");
    decimal_print(@result);
    print("\n\0");

    // ===================================================================
    // 20. Edge cases
    // ===================================================================
    section("Edge cases\0");

    // Very small number
    decimal_from_string(@a, "0.000000000000001\0");
    print_label("very small: 1e-15\0");
    decimal_print(@a);
    print("\n\0");
    decimal_print_sci(@a);
    print("\n\0");

    // Very large number
    decimal_from_string(@a, "99999999999999999999999999\0");
    print_label("very large\0");
    decimal_print(@a);
    print("\n\0");

    // Subtraction to zero
    decimal_from_string(@a, "3.14\0");
    decimal_from_string(@b, "3.14\0");
    decimal_sub(@result, @a, @b);
    print_label("3.14 - 3.14 = 0\0");
    pass_fail(decimal_is_zero(@result));

    // Negative exponent from string
    decimal_from_string(@a, "1.5E-5\0");
    print_label("1.5E-5\0");
    decimal_print(@a);
    print("\n\0");

    // sqrt of a perfect square
    decimal_from_string(@a, "144\0");
    decimal_sqrt(@result, @a);
    print_label("sqrt(144)\0");
    decimal_print(@result);
    print("\n\0");

    print("\n=== Test suite complete ===\n\0");
    return 0;
};
