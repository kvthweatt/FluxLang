#ifndef FLUX_STANDARD_MATH
#import "redmath.fx";
#endif;

#ifndef FLUX_BIG_INTEGERS
#def FLUX_BIG_INTEGERS 1;

struct BigInt
{
    uint[128] digits;    // Can hold up to 4096 bits (128 * 32)
    uint length;         // Number of uint digits actually used
    bool negative;      // Sign: false = positive, true = negative
};

namespace math
{
    namespace bigint
    {
        // Initialize a BigInt to zero
        def bigint_zero(BigInt* num) -> void
        {
            uint* nd = @num.digits[0];
            uint i;
            for (i = 0; i < 128; i++)
            {
                nd[i] = 0;
            };
            num.length = 1;
            num.negative = false;
            return;
        };
        
        // Initialize a BigInt to one
        def bigint_one(BigInt* num) -> void
        {
            uint* nd = @num.digits[0];
            uint i;
            nd[0] = 1;
            for (i = 1; i < 128; i++)
            {
                nd[i] = 0;
            };
            num.length = 1;
            num.negative = false;
            return;
        };
        
        // Create a BigInt from a uint value
        def bigint_from_uint(BigInt* num, uint value) -> void
        {
            uint* nd = @num.digits[0];
            uint i;
            nd[0] = value;
            for (i = 1; i < 128; i++)
            {
                nd[i] = 0;
            };
            
            if (value == 0)
            {
                num.length = 1;
            }
            else
            {
                num.length = 1;
            };
            
            num.negative = false;
            return;
        };
        
        // Create a BigInt from a u64 value
        def bigint_from_u64(BigInt* num, u64 value) -> void
        {
            uint* nd = @num.digits[0];
            uint i;
            nd[0] = (uint)(value & 0xFFFFFFFF);
            nd[1] = (uint)(value >> 32);
            
            for (i = 2; i < 128; i++)
            {
                nd[i] = 0;
            };
            
            if (nd[1] != 0)
            {
                num.length = 2;
            }
            else
            {
                if (nd[0] != 0)
                {
                    num.length = 1;
                }
                else
                {
                    num.length = 1;
                };
            };
            
            num.negative = false;
            return;
        };
        
        // Check if BigInt is zero
        def bigint_is_zero(BigInt* num) -> bool
        {
            uint* nd = @num.digits[0];
            if (num.length == 1)
            {
                if (nd[0] == 0)
                {
                    return true;
                };
            };
            return false;
        };
        
        // Check if BigInt is one
        def bigint_is_one(BigInt* num) -> bool
        {
            uint* nd = @num.digits[0];
            if (num.negative)
            {
                return false;
            };
            
            if (num.length == 1)
            {
                if (nd[0] == 1)
                {
                    return true;
                };
            };
            
            return false;
        };
        
        // Print a single hex digit
        def print_hex_digit(uint digit) -> void
        {
            if (digit < 10)
            {
                print((byte)('0' + digit));
            }
            else
            {
                print((byte)('a' + (digit - 10)));
            };
            return;
        };
        
        // Print BigInt in hexadecimal format (for debugging)
        def bigint_print_hex(BigInt* num) -> void
        {
            uint* nd = @num.digits[0];
            if (num.negative)
            {
                print("-\0");
            };
            
            print("0x\0");
            
            // Print from most significant to least significant
            uint digit,
                j,
                nibble,
                i = num.length;
            while (i > 0)
            {
                i--;
                
                digit = nd[i];
                
                // Print all 8 hex digits for this uint
                for (j = 0; j < 8; j++)
                {
                    nibble = (digit >> (28 - j * 4)) & 0xF;
                    print_hex_digit(nibble);
                };
                
                // Add separator between digits for readability
                if (i > 0)
                {
                    print("_\0");
                };
            };
            
            return;
        };
        
        // Print BigInt in decimal format (simple version - converts to decimal string)
        // Note: This is a simplified version that only works for small numbers
        // We'll implement full decimal conversion later with division
        def bigint_print(BigInt* num) -> void
        {
            if (num.negative)
            {
                print("-\0");
            };
            
            // For now, only handle numbers that fit in u64
            if (num.length > 2)
            {
                print("[Large number - use hex print]\0");
                return;
            };
            
            uint* nd = @num.digits[0];
            u64 value;
            if (num.length == 2)
            {
                value = ((u64)nd[1] << 32) | (u64)nd[0];
            }
            else
            {
                value = (u64)nd[0];
            };
            
            // Print as u64
            print((int)value);
            
            return;
        };
        
        // Copy one BigInt to another
        def bigint_copy(BigInt* dest, BigInt* src) -> void
        {
            uint* dd = @dest.digits[0],
                 sd = @src.digits[0];
            uint i;
            for (i = 0; i < 128; i++)
            {
                dd[i] = sd[i];
            };
            dest.length = src.length;
            dest.negative = src.negative;
            return;
        };

        // Normalize: remove leading zero digits, ensure length >= 1
        def bigint_normalize(BigInt* num) -> void
        {
            uint* nd = @num.digits[0];
            uint top_idx;
            while (num.length > 1)
            {
                top_idx = num.length - 1;
                if (nd[top_idx] == 0)
                {
                    num.length--;
                }
                else
                {
                    break;
                };
            };
            // If the value is zero, clear sign
            if (num.length == 1)
            {
                if (nd[0] == 0)
                {
                    num.negative = false;
                };
            };
            return;
        };

        // Compare absolute values of two BigInts
        // Returns: -1 if |a| < |b|, 0 if equal, 1 if |a| > |b|
        def bigint_cmp_abs(BigInt* a, BigInt* b) -> int
        {
            uint* ad = @a.digits[0],
                 bd = @b.digits[0];
            if (a.length > b.length) { return 1; };
            if (a.length < b.length) { return -1; };

            // Same length - compare from most significant
            uint i = a.length;
            while (i > 0)
            {
                i--;
                if (ad[i] > bd[i]) { return 1; };
                if (ad[i] < bd[i]) { return -1; };
            };
            return 0;
        };

        // Compare two BigInts (signed)
        // Returns: -1 if a < b, 0 if equal, 1 if a > b
        def bigint_cmp(BigInt* a, BigInt* b) -> int
        {
            // Both zero
            if (bigint_is_zero(a) & bigint_is_zero(b)) { return 0; };

            // Sign-based shortcuts
            if (a.negative & !b.negative) { return -1; };
            if (!a.negative & b.negative) { return 1; };

            // Same sign
            if (!a.negative)
            {
                return bigint_cmp_abs(a, b);
            };
            // Both negative: larger absolute value means smaller overall
            return bigint_cmp_abs(b, a);
        };

        // Add absolute values: result = |a| + |b|  (sign not set here)
        def bigint_add_abs(BigInt* result, BigInt* a, BigInt* b) -> void
        {
            u64 carry = 0;
            uint max_len;
            if (a.length > b.length)
            {
                max_len = a.length;
            }
            else
            {
                max_len = b.length;
            };

            uint* rd = @result.digits[0],
                 ad = @a.digits[0],
                 bd = @b.digits[0];
            uint i = 0;
            u64 sum;
            while (i < max_len | carry != 0)
            {
                sum = carry;
                if (i < a.length)
                {
                    sum = sum + (u64)ad[i];
                };
                if (i < b.length)
                {
                    sum = sum + (u64)bd[i];
                };
                rd[i] = (uint)(sum & 0xFFFFFFFF);
                carry = sum >> 32;
                i++;
            };
            result.length = i;
            bigint_normalize(result);
            return;
        };

        // Subtract absolute values: result = |a| - |b|  (assumes |a| >= |b|, sign not set)
        def bigint_sub_abs(BigInt* result, BigInt* a, BigInt* b) -> void
        {
            uint* rd = @result.digits[0],
                 ad = @a.digits[0],
                 bd = @b.digits[0];
            i64 borrow = 0;
            uint i;
            i64 diff;
            for (i = 0; i < a.length; i++)
            {
                diff = (i64)ad[i] - borrow;
                if (i < b.length)
                {
                    diff = diff - (i64)bd[i];
                };
                if (diff < 0)
                {
                    rd[i] = (uint)(diff + (i64)4294967296);
                    borrow = 1;
                }
                else
                {
                    rd[i] = (uint)diff;
                    borrow = 0;
                };
            };
            result.length = a.length;
            bigint_normalize(result);
            return;
        };

        // Add: result = a + b  (signed)
        def bigint_add(BigInt* result, BigInt* a, BigInt* b) -> void
        {
            // Clear result
            bigint_zero(result);

            if (a.negative == b.negative)
            {
                // Same sign: add magnitudes, keep sign
                bigint_add_abs(result, a, b);
                result.negative = a.negative;
            }
            else
            {
                // Different signs: subtract smaller magnitude from larger
                int cmp;
                cmp = bigint_cmp_abs(a, b);
                if (cmp == 0)
                {
                    // Result is zero
                    bigint_zero(result);
                }
                elif (cmp > 0)
                {
                    bigint_sub_abs(result, a, b);
                    result.negative = a.negative;
                }
                else
                {
                    bigint_sub_abs(result, b, a);
                    result.negative = b.negative;
                };
            };
            bigint_normalize(result);
            return;
        };

        // Subtract: result = a - b  (signed)
        def bigint_sub(BigInt* result, BigInt* a, BigInt* b) -> void
        {
            // Negate b's sign temporarily via a copy
            BigInt neg_b;
            bigint_copy(@neg_b, b);
            if (bigint_is_zero(@neg_b))
            {
                neg_b.negative = false;
            }
            else
            {
                neg_b.negative = !b.negative;
            };
            bigint_add(result, a, @neg_b);
            return;
        };

        // Multiply: result = a * b  (signed, schoolbook long multiplication)
        def bigint_mul(BigInt* result, BigInt* a, BigInt* b) -> void
        {
            bigint_zero(result);

            if (bigint_is_zero(a) | bigint_is_zero(b))
            {
                return;
            };

            uint* rd = @result.digits[0],
                 ad = @a.digits[0],
                 bd = @b.digits[0];
            uint i, j;
            u64 carry, prod;
            for (i = 0; i < a.length; i++)
            {
                carry = 0;
                j = 0;
                while (j < b.length | carry != 0)
                {
                    prod = (u64)rd[i + j] + carry;
                    if (j < b.length)
                    {
                        prod = prod + (u64)ad[i] * (u64)bd[j];
                    };
                    rd[i + j] = (uint)(prod & 0xFFFFFFFF);
                    carry = prod >> 32;
                    j++;
                };
                if (i + j > result.length)
                {
                    result.length = i + j;
                };
            };

            if (a.negative == b.negative)
            {
                result.negative = false;
            }
            else
            {
                result.negative = true;
            };
            bigint_normalize(result);
            return;
        };

        // Shift left by one bit in-place
        def bigint_shift_left_1(BigInt* num) -> void
        {
            uint* nd = @num.digits[0];
            uint carry = 0,
                new_carry,
                len,
                i;
            for (i = 0; i < num.length; i++)
            {
                new_carry = nd[i] >> 31;
                nd[i] = (nd[i] << 1) | carry;
                carry = new_carry;
            };
            if (carry != 0)
            {
                len = num.length;
                nd[len] = carry;
                num.length++;
            };
            return;
        };

        // Shift right by one bit in-place
        def bigint_shift_right_1(BigInt* num) -> void
        {
            uint* nd = @num.digits[0];
            uint carry = 0,
                 new_carry,
                 i = num.length;
            while (i > 0)
            {
                i--;
                new_carry = nd[i] & 1;
                nd[i] = (nd[i] >> 1) | (carry << 31);
                carry = new_carry;
            };
            bigint_normalize(num);
            return;
        };

        // Shift left by n bits: result = a << n
        def bigint_shl(BigInt* result, BigInt* a, uint n) -> void
        {
            bigint_copy(result, a);
            uint i;
            for (i = 0; i < n; i++)
            {
                bigint_shift_left_1(result);
            };
            return;
        };

        // Shift right by n bits: result = a >> n
        def bigint_shr(BigInt* result, BigInt* a, uint n) -> void
        {
            bigint_copy(result, a);
            uint i;
            for (i = 0; i < n; i++)
            {
                bigint_shift_right_1(result);
            };
            return;
        };

        // Divide: quotient = a / b, remainder = a % b  (unsigned magnitudes, signs set after)
        // Uses binary long division
        def bigint_divmod(BigInt* quotient, BigInt* remainder, BigInt* a, BigInt* b) -> void
        {
            // Declare all locals first so they land in the IR entry block
            BigInt abs_a,
                   abs_b,
                   rem,
                   quot;

            bigint_zero(quotient);
            bigint_zero(remainder);

            if (bigint_is_zero(b))
            {
                // Division by zero - return zero for both (caller should check)
                return;
            };

            if (bigint_cmp_abs(a, b) < 0)
            {
                // |a| < |b|: quotient = 0, remainder = |a|
                bigint_copy(remainder, a);
                remainder.negative = false;
                return;
            };

            // Work on absolute values; fix signs after
            bigint_copy(@abs_a, a);
            abs_a.negative = false;
            bigint_copy(@abs_b, b);
            abs_b.negative = false;

            // Use pointers to local struct digit arrays for safe element access
            uint* abs_a_d = @abs_a.digits[0];

            // Count total bits in abs_a
            uint total_bits = (abs_a.length - 1) * 32,
                 top_idx = abs_a.length - 1,
                 top_digit = abs_a_d[top_idx],
                 bit_pos = 31;
            while (bit_pos > 0)
            {
                if (((top_digit >> bit_pos) & 1) != 0)
                {
                    break;
                };
                bit_pos--;
            };
            total_bits = total_bits + bit_pos;

            // Binary long division
            bigint_zero(@rem);
            bigint_zero(@quot);

            // Pointers to local struct digit arrays for safe element access
            uint* rem_d  = @rem.digits[0],
                  quot_d = @quot.digits[0];

            uint word_idx,
                 bit_idx,
                 the_bit,
                 q_word,
                 q_bit;
            int bit;
            for (bit = (int)total_bits; bit >= 0; bit--)
            {
                // rem = rem << 1
                bigint_shift_left_1(@rem);

                // rem |= bit 'bit' of abs_a
                word_idx = (uint)bit / 32;
                bit_idx  = (uint)bit % 32;
                the_bit  = (abs_a_d[word_idx] >> bit_idx) & 1;
                if (the_bit != 0)
                {
                    rem_d[0] = rem_d[0] | 1;
                };

                // if rem >= abs_b
                if (bigint_cmp_abs(@rem, @abs_b) >= 0)
                {
                    bigint_sub_abs(@rem, @rem, @abs_b);

                    // Set bit 'bit' in quot
                    q_word = (uint)bit / 32;
                    q_bit  = (uint)bit % 32;
                    quot_d[q_word] = quot_d[q_word] | (1 << q_bit);
                    if (q_word + 1 > quot.length)
                    {
                        quot.length = q_word + 1;
                    };
                };
            };

            bigint_normalize(@quot);
            bigint_normalize(@rem);

            bigint_copy(quotient, @quot);
            bigint_copy(remainder, @rem);

            // Fix signs: quotient sign = a.negative XOR b.negative
            //            remainder sign = a.negative
            if (a.negative == b.negative)
            {
                quotient.negative = false;
            }
            else
            {
                quotient.negative = true;
            };
            remainder.negative = a.negative;

            // Zero has no sign
            if (bigint_is_zero(quotient))  { quotient.negative  = false; };
            if (bigint_is_zero(remainder)) { remainder.negative = false; };

            return;
        };

        // Divide: result = a / b
        def bigint_div(BigInt* result, BigInt* a, BigInt* b) -> void
        {
            BigInt rem;
            bigint_divmod(result, @rem, a, b);
            return;
        };

        // Modulo: result = a % b
        def bigint_mod(BigInt* result, BigInt* a, BigInt* b) -> void
        {
            BigInt quot;
            bigint_divmod(@quot, result, a, b);
            return;
        };

        // Power: result = base ^ exp  (exp is a non-negative uint for simplicity)
        def bigint_pow_uint(BigInt* result, BigInt* base, uint exp) -> void
        {
            // Declare all locals first so they land in the IR entry block
            BigInt cur_base,
                   tmp;

            bigint_copy(@cur_base, base);
            bigint_one(result);

            if (exp == 0) { return; };

            uint e = exp;
            while (e > 0)
            {
                if ((e & 1) != 0)
                {
                    bigint_mul(@tmp, result, @cur_base);
                    bigint_copy(result, @tmp);
                };
                e = e >> 1;
                if (e > 0)
                {
                    bigint_mul(@tmp, @cur_base, @cur_base);
                    bigint_copy(@cur_base, @tmp);
                };
            };
            return;
        };

        // Convert u64 to decimal string and print it
        def print_u64_decimal(u64 value) -> void
        {
            if (value == 0)
            {
                print("0\0");
                return;
            };

            // Max u64 is 20 decimal digits
            byte[21] buf;
            uint idx, pos;
            u64 v;
            idx = 0;
            v = value;
            while (v > 0)
            {
                buf[idx] = (byte)('0' + (v % 10));
                v = v / 10;
                idx++;
            };

            // Print reversed
            pos = idx;
            while (pos > 0)
            {
                pos--;
                print(buf[pos]);
            };
            return;
        };

        // Print BigInt in decimal - full version using repeated division by 10^9
        def bigint_print_decimal(BigInt* num) -> void
        {
            // Declare all locals first so they land in the IR entry block
            BigInt divisor,
                   work,
                   quot,
                   rem;

            if (num.negative)
            {
                print("-\0");
            };

            if (bigint_is_zero(num))
            {
                print("0\0");
                return;
            };

            // Collect decimal chunks (base 10^9 = 1,000,000,000)
            // A 4096-bit number needs at most ceil(4096 * log10(2)) ~ 1234 digits, so ~138 chunks of 9
            uint[140] chunks;
            uint num_chunks = 0;

            bigint_from_uint(@divisor, 1000000000);

            bigint_copy(@work, num);
            work.negative = false;

            // Pointer to rem digits for safe element read
            uint* rem_d = @rem.digits[0];

            while (!bigint_is_zero(@work))
            {
                bigint_divmod(@quot, @rem, @work, @divisor);
                // rem_d[0] holds the remainder (0..999999999)
                chunks[num_chunks] = rem_d[0];
                num_chunks++;
                bigint_copy(@work, @quot);
            };

            // Print from most significant chunk
            uint c, d,
                 chunk_val,
                 digits_needed,
                 power,
                 digit_val;
            c = num_chunks;
            while (c > 0)
            {
                c--;
                if (c == num_chunks - 1)
                {
                    // First chunk: print without leading zeros
                    print_u64_decimal((u64)chunks[c]);
                }
                else
                {
                    // Remaining chunks: always print exactly 9 digits with leading zeros
                    chunk_val = chunks[c];
                    digits_needed = 9;
                    power = 100000000; // 10^8
                    for (d = 0; d < digits_needed; d++)
                    {
                        digit_val = chunk_val / power;
                        print((byte)('0' + digit_val));
                        chunk_val = chunk_val % power;
                        power = power / 10;
                    };
                };
            };
            return;
        };
    };
};

#endif; // FLUX_BIG_INTEGERS