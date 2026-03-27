// Author: Karac V. Thweatt
// rle.fx - Run Length Encoding / Decoding

#ifndef FLUX_STANDARD_STRINGS
#import "string_utilities.fx";
#endif;

#ifndef FLUX_RLE
#def FLUX_RLE 1;

namespace standard
{
    namespace rle
    {
        // Encode a byte buffer using RLE.
        // Output format: [count byte][value byte] pairs, count 1-255.
        // Returns heap-allocated encoded buffer. Caller must free.
        // out_size receives the number of bytes written.
        def encode(byte* input, int input_len, int* out_size) -> byte*
        {
            int max_out, out_pos, in_pos, run;
            byte current;
            byte* output;

            if (input == 0 | input_len <= 0)
            {
                *out_size = 0;
                return (byte*)0;
            };

            // Worst case: every byte is unique -> 2 bytes per input byte
            max_out = input_len * 2;
            output = (byte*)fmalloc((u64)max_out);
            if (output == 0)
            {
                *out_size = 0;
                return (byte*)0;
            };

            while (in_pos < input_len)
            {
                current = input[in_pos];
                run = 1;

                while (in_pos + run < input_len & input[in_pos + run] == current & run < 255)
                {
                    run = run + 1;
                };

                output[out_pos]     = (byte)run;
                output[out_pos + 1] = current;
                out_pos = out_pos + 2;
                in_pos  = in_pos + run;
            };

            *out_size = out_pos;
            return output;
        };

        // Decode an RLE-encoded buffer produced by encode().
        // Returns heap-allocated decoded buffer. Caller must free.
        // out_size receives the number of bytes written.
        def decode(byte* input, int input_len, int* out_size) -> byte*
        {
            int decoded_len, pos, in_pos, out_pos, run;
            byte val;
            byte* output;

            if (input == 0 | input_len <= 0)
            {
                *out_size = 0;
                return (byte*)0;
            };

            // First pass: calculate decoded size
            while (pos < input_len)
            {
                decoded_len = decoded_len + ((int)input[pos] & 0xFF);
                pos = pos + 2;
            };

            output = (byte*)fmalloc((u64)decoded_len + 1);
            if (output == 0)
            {
                *out_size = 0;
                return (byte*)0;
            };

            // Second pass: expand runs
            while (in_pos < input_len)
            {
                run    = (int)input[in_pos] & 0xFF;
                val    = input[in_pos + 1];
                in_pos = in_pos + 2;

                for (int r; r < run; r = r + 1)
                {
                    output[out_pos] = val;
                    out_pos = out_pos + 1;
                };
            };

            output[out_pos] = (byte)0;
            *out_size = out_pos;
            return output;
        };

        // Encode a null-terminated string into a human-readable RLE string.
        // Output format: "3A2B1C" etc.
        // Returns heap-allocated string. Caller must free.
        def encode_str(byte* input) -> byte*
        {
            int input_len, max_out, out_pos, in_pos, run, count_len, k;
            byte current;
            byte* output;
            byte[21] count_buf;

            if (input == 0 | input[0] == 0)
            {
                byte* empty = (byte*)fmalloc((u64)1);
                if (empty != 0) { empty[0] = (byte)0; };
                return empty;
            };

            input_len = standard::strings::strlen(input);

            // Worst case: each char unique -> 21 digit count + 1 char per input byte + null
            max_out = input_len * 22;
            output = (byte*)fmalloc((u64)max_out);
            if (output == 0)
            {
                return (byte*)0;
            };

            while (in_pos < input_len)
            {
                current = input[in_pos];
                run = 1;

                while (in_pos + run < input_len & input[in_pos + run] == current)
                {
                    run = run + 1;
                };

                // Write count digits
                count_len = (int)standard::strings::i32str(run, count_buf);
                for (k = 0; k < count_len; k = k + 1)
                {
                    output[out_pos] = count_buf[k];
                    out_pos = out_pos + 1;
                };

                // Write the character
                output[out_pos] = current;
                out_pos = out_pos + 1;

                in_pos = in_pos + run;
            };

            output[out_pos] = (byte)0;
            return output;
        };

        // Decode a human-readable RLE string produced by encode_str().
        // Input format: "3A2B1C" etc.
        // Returns heap-readable string. Caller must free.
        def decode_str(byte* input) -> byte*
        {
            int input_len, decoded_len, pos, in_pos, out_pos, run;
            byte val;
            byte* output;

            if (input == 0 | input[0] == 0)
            {
                byte* empty = (byte*)fmalloc((u64)1);
                if (empty != 0) { empty[0] = (byte)0; };
                return empty;
            };

            input_len = standard::strings::strlen(input);

            // First pass: calculate decoded length
            while (pos < input_len)
            {
                run = 0;
                while (pos < input_len & input[pos] >= (byte)48 & input[pos] <= (byte)57)
                {
                    run = run * 10 + ((int)input[pos] - 48);
                    pos = pos + 1;
                };
                decoded_len = decoded_len + run;
                pos = pos + 1; // skip value byte
            };

            output = (byte*)fmalloc((u64)decoded_len + 1);
            if (output == 0)
            {
                return (byte*)0;
            };

            // Second pass: expand
            while (in_pos < input_len)
            {
                run = 0;
                while (in_pos < input_len & input[in_pos] >= (byte)48 & input[in_pos] <= (byte)57)
                {
                    run = run * 10 + ((int)input[in_pos] - 48);
                    in_pos = in_pos + 1;
                };

                val    = input[in_pos];
                in_pos = in_pos + 1;

                for (int r; r < run; r = r + 1)
                {
                    output[out_pos] = val;
                    out_pos = out_pos + 1;
                };
            };

            output[out_pos] = (byte)0;
            return output;
        };
    };
};

#endif;
