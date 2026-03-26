// Author: Karac V. Thweatt
// fourier.fx - Discrete and Fast Fourier Transform

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_MATH
#import "math.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "memory.fx";
#endif;

#ifndef FLUX_FOURIER
#def FLUX_FOURIER 1;
#endif;

using standard::memory::allocators::stdheap;

namespace standard
{
    namespace math
    {
        namespace fourier
        {
            // complex_add: result = a + b
            def complex_add(Complex* result, Complex* a, Complex* b) -> void
            {
                result.re = a.re + b.re;
                result.im = a.im + b.im;
                return;
            };

            // complex_sub: result = a - b
            def complex_sub(Complex* result, Complex* a, Complex* b) -> void
            {
                result.re = a.re - b.re;
                result.im = a.im - b.im;
                return;
            };

            // complex_mul: result = a * b  (uses double to avoid alias corruption)
            def complex_mul(Complex* result, Complex* a, Complex* b) -> void
            {
                double re = a.re * b.re - a.im * b.im,
                       im = a.re * b.im + a.im * b.re;
                result.re = re;
                result.im = im;
                return;
            };

            // complex_mag: |c| = sqrt(re^2 + im^2)
            def complex_mag(Complex* c) -> double
            {
                return standard::math::sqrt(c.re * c.re + c.im * c.im);
            };

            // complex_phase: angle in radians via atan2
            def complex_phase(Complex* c) -> double
            {
                return standard::math::atan2(c.im, c.re);
            };

            // complex_from_polar: result = mag * e^(i*phase)
            def complex_from_polar(Complex* result, double mag, double phase) -> void
            {
                result.re = mag * standard::math::cos((float)phase);
                result.im = mag * standard::math::sin((float)phase);
                return;
            };

            // ============================================================
            // dft
            // Naive O(N^2) Discrete Fourier Transform.
            // out must point to a caller-allocated array of N Complex.
            // in  must point to a caller-allocated array of N Complex.
            // ============================================================
            def dft(Complex* out, Complex* xin, i32 n) -> void
            {
                double two_pi_over_n = 2.0f * (double)standard::math::PIF / (double)n,
                       angle,
                       re_sum,
                       im_sum;
                i32 k,
                    j;

                for (k = 0; k < n; k++)
                {
                    re_sum = 0.0f;
                    im_sum = 0.0f;

                    for (j = 0; j < n; j++)
                    {
                        angle  = two_pi_over_n * (double)k * (double)j;
                        re_sum = re_sum + xin[j].re * standard::math::cos((float)angle)
                                       + xin[j].im * standard::math::sin((float)angle);
                        im_sum = im_sum + xin[j].im * standard::math::cos((float)angle)
                                       - xin[j].re * standard::math::sin((float)angle);
                    };

                    out[k].re = re_sum;
                    out[k].im = im_sum;
                };
                return;
            };

            // ============================================================
            // idft
            // Naive O(N^2) Inverse Discrete Fourier Transform.
            // out must point to a caller-allocated array of N Complex.
            // in  must point to a caller-allocated array of N Complex.
            // ============================================================
            def idft(Complex* out, Complex* xin, i32 n) -> void
            {
                double two_pi_over_n = 2.0f * (double)standard::math::PIF / (double)n,
                       inv_n        = 1.0f / (double)n,
                       angle,
                       re_sum,
                       im_sum;
                i32 k,
                    j;

                for (k = 0; k < n; k++)
                {
                    re_sum = 0.0f;
                    im_sum = 0.0f;

                    for (j = 0; j < n; j++)
                    {
                        // IDFT uses +angle (positive exponent) and divides by N
                        angle  = two_pi_over_n * (double)k * (double)j;
                        re_sum = re_sum + xin[j].re * standard::math::cos((float)angle)
                                       - xin[j].im * standard::math::sin((float)angle);
                        im_sum = im_sum + xin[j].im * standard::math::cos((float)angle)
                                       + xin[j].re * standard::math::sin((float)angle);
                    };

                    out[k].re = re_sum * inv_n;
                    out[k].im = im_sum * inv_n;
                };
                return;
            };

            // ============================================================
            // fft_butterfly
            // In-place Cooley-Tukey FFT butterfly pass over buf[0..n).
            // n must be a power of two.
            // inverse = true performs the backward transform (no 1/N scaling).
            // Call fft() or ifft() instead of this directly.
            // ============================================================
            def fft_butterfly(Complex* buf, i32 n, bool inverse) -> void
            {
                // Bit-reversal permutation
                i32 i,
                    j,
                    bit,
                    len;
                double angle,
                       inv_n;
                Complex tmp,
                        twiddle,
                        even_val,
                        odd_val;

                j = 0;
                for (i = 1; i < n; i++)
                {
                    bit = n >> 1;
                    while (j & bit)
                    {
                        j = j xor bit;
                        bit = bit >> 1;
                    };
                    j = j | bit;

                    if (i < j)
                    {
                        // Swap buf[i] and buf[j]
                        tmp.re    = buf[i].re;
                        tmp.im    = buf[i].im;
                        buf[i].re = buf[j].re;
                        buf[i].im = buf[j].im;
                        buf[j].re = tmp.re;
                        buf[j].im = tmp.im;
                    };
                };

                // Cooley-Tukey iterative butterfly
                for (len = 2; len <= n; len = len << 1)
                {
                    // Twiddle factor angle per half-length
                    // Forward: -2*pi/len   Inverse: +2*pi/len
                    if (inverse)
                    {
                        angle = 2.0f * (double)standard::math::PIF / (double)len;
                    }
                    else
                    {
                        angle = 0.0f - (2.0f * (double)standard::math::PIF / (double)len);
                    };

                    for (i = 0; i < n; i = i + len)
                    {
                        j = 0;
                        while (j < len / 2)
                        {
                            // twiddle = e^(i * angle * j)
                            twiddle.re = standard::math::cos((float)(angle * (double)j));
                            twiddle.im = standard::math::sin((float)(angle * (double)j));

                            even_val.re = buf[i + j].re;
                            even_val.im = buf[i + j].im;

                            // odd_val = twiddle * buf[i + j + len/2]
                            complex_mul(@odd_val, @twiddle, @buf[i + j + len / 2]);

                            // Butterfly: even + odd, even - odd
                            complex_add(@buf[i + j],             @even_val, @odd_val);
                            complex_sub(@buf[i + j + len / 2],   @even_val, @odd_val);

                            j++;
                        };
                    };
                };
                return;
            };

            // ============================================================
            // fft
            // In-place forward FFT (Cooley-Tukey, radix-2, iterative).
            // buf must be a heap-allocated array of N Complex, N a power of 2.
            // ============================================================
            def fft(Complex* buf, i32 n) -> void
            {
                fft_butterfly(buf, n, false);
                return;
            };

            // ============================================================
            // ifft
            // In-place inverse FFT.  Scales output by 1/N.
            // buf must be a heap-allocated array of N Complex, N a power of 2.
            // ============================================================
            def ifft(Complex* buf, i32 n) -> void
            {
                double inv_n;
                i32 i;

                fft_butterfly(buf, n, true);

                inv_n = 1.0f / (double)n;
                for (i = 0; i < n; i++)
                {
                    buf[i].re = buf[i].re * inv_n;
                    buf[i].im = buf[i].im * inv_n;
                };
                return;
            };

            // ============================================================
            // is_power_of_two
            // Returns true if n is a positive power of two.
            // ============================================================
            def is_power_of_two(i32 n) -> bool
            {
                if (n <= 0) { return false; };
                return (n & (n - 1)) == 0;
            };

            // ============================================================
            // next_power_of_two
            // Returns the smallest power of two >= n.
            // ============================================================
            def next_power_of_two(i32 n) -> i32
            {
                i32 p;
                p = 1;
                while (p < n)
                {
                    p = p << 1;
                };
                return p;
            };

            // ============================================================
            // fft_alloc
            // Allocates a heap buffer of n Complex and returns a pointer.
            // Caller is responsible for ffree((u64)ptr) when done.
            // ============================================================
            def fft_alloc(i32 n) -> Complex*
            {
                size_t byte_count;
                byte_count = (size_t)(n * (sizeof(Complex) / 8));
                return (Complex*)fmalloc(byte_count);
            };

            // ============================================================
            // fft_load_real
            // Fills buf[0..n) from a double array of real samples.
            // Imaginary parts are set to zero.
            // ============================================================
            def fft_load_real(Complex* buf, double* samples, i32 n) -> void
            {
                i32 i;
                for (i = 0; i < n; i++)
                {
                    buf[i].re = samples[i];
                    buf[i].im = 0.0f;
                };
                return;
            };

            // ============================================================
            // fft_magnitude
            // Writes |buf[k]| into mag[0..n) for spectrum analysis.
            // mag must be a caller-allocated array of n doubles.
            // ============================================================
            def fft_magnitude(double* mag, Complex* buf, i32 n) -> void
            {
                i32 i;
                for (i = 0; i < n; i++)
                {
                    mag[i] = complex_mag(@buf[i]);
                };
                return;
            };
        };
    };
};
