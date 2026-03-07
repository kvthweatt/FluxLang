#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// Mandelbrot Set - OpenGL Viewer
// W = zoom in, S = zoom out
// ============================================================================

const int WIN_W    = 900;
const int WIN_H    = 900;
const int MAX_ITER = 128;

// Virtual key codes
const int VK_W    = 0x57;
const int VK_S    = 0x53;
const int VK_A    = 0x41;
const int VK_D    = 0x44;
const int VK_UP   = 0x26;
const int VK_DOWN = 0x28;

// ============================================================================
// 256-bit signed fixed-point arithmetic.
//
// Layout: 4 x u64 limbs in little-endian order (limb[0] = least significant).
// The value is two's-complement with the binary point fixed after bit 1 of
// limb[3], i.e. 2 integer bits and 254 fractional bits.
// Range: roughly -2.0 to +2.0, which is plenty for Mandelbrot escape radius 4.
//
// All arithmetic functions take and return fp256* (pointer to struct).
// Callers allocate on the stack and pass @variable.
// ============================================================================

struct fp256
{
    u64 lo;   // limb 0 - least significant 64 bits
    u64 m1;   // limb 1
    u64 m2;   // limb 2
    u64 hi;   // limb 3 - most significant 64 bits (bits 63:62 = integer part)
};

// ------------------------------------------------------------------ helpers

// Reinterpret float bits as u32
def float_to_bits(float f) -> u32
{
    u32* p = (u32*)@f;
    return *p;
};

// Convert float to fp256 (only handles values in (-2, +2))
def fp256_from_float(float f, fp256* r) -> void
{
    // Decompose via bit manipulation: get sign, exponent, mantissa
    u64 bits, mantissa, frac;
    int exp, shift;
    u64 sign_mask;

    bits    = (u64)float_to_bits(f) `& 0xFFFFFFFF;
    sign_mask = (bits >> 31) `& 1;
    exp     = (int)((bits >> 23) `& 0xFF) - 127;  // unbiased exponent
    mantissa = (bits `& 0x7FFFFF) | 0x800000;      // implicit leading 1

    // The value is  (-1)^sign * mantissa * 2^(exp-23)
    // We want to place this into a Q2.254 fixed-point number.
    // The integer bit lives at position 254 from the LSB of the 256-bit value.
    // mantissa already has 24 bits.  We need to shift it so that bit 0 of
    // mantissa (weight 2^(exp-23)) aligns with the appropriate bit of the
    // 256-bit integer.
    //
    // Bit position in the 256-bit integer that represents 2^1 is bit 255.
    // Bit position that represents 2^0 is bit 254.
    // Bit position that represents 2^(exp-23) is bit 254 + (exp-23).
    // We want the MSB of our 24-bit mantissa (weight 2^exp) at bit 254+exp,
    // so shift = 254 + exp - 23 = 231 + exp.

    r.lo = (u64)0;
    r.m1 = (u64)0;
    r.m2 = (u64)0;
    r.hi = (u64)0;

    if (((bits >> 23) `& 0xFF) == (u64)0) { return; };  // zero or denormal
    if (exp < -225) { return; };  // too small to represent

    shift = 225 + exp;  // bit position of mantissa bit 0 in the 256-bit number (Q8.248 layout)

    // Place mantissa (24 bits) starting at bit `shift`
    // We do this limb by limb.  shift can range roughly from
    // 231-127=104 to 231+1=232.
    frac = (u64)mantissa;

    if (shift >= 192)
    {
        // Mantissa entirely in hi limb, possibly spilling into m2
        int s;
        s = shift - 192;
        r.hi = frac << s;
        if (s > 40) { r.m2 = frac >> (64 - s); };
    }
    elif (shift >= 128)
    {
        int s;
        s = shift - 128;
        r.m2 = frac << s;
        r.hi = frac >> (64 - s);
    }
    elif (shift >= 64)
    {
        int s;
        s = shift - 64;
        r.m1 = frac << s;
        r.m2 = frac >> (64 - s);
    }
    else
    {
        r.lo = frac << shift;
        if (shift > 40) { r.m1 = frac >> (64 - shift); };
    };

    // Negate if negative (two's complement)
    if (sign_mask != (u64)0)
    {
        // NOT each limb then add 1
        r.lo = `!r.lo;
        r.m1 = `!r.m1;
        r.m2 = `!r.m2;
        r.hi = `!r.hi;

        r.lo = r.lo + (u64)1;
        if (r.lo == (u64)0) { r.m1 = r.m1 + (u64)1; };
        if (r.m1 == (u64)0 `& r.lo == (u64)0) { r.m2 = r.m2 + (u64)1; };
        if (r.m2 == (u64)0 `& r.m1 == (u64)0 `& r.lo == (u64)0) { r.hi = r.hi + (u64)1; };
    };

    return;
};

// Convert fp256 to float (for magnitude comparison)
def fp256_to_float(fp256* a) -> float
{
    // Read the sign from bit 63 of hi limb
    u64 sign_bit, abs_hi, abs_m2, abs_m1, abs_lo;
    float result, f_hi, f_upper, f_lower;
    u64 hi_upper, hi_lower;

    sign_bit = (a.hi >> 63) `& (u64)1;

    abs_hi = a.hi;
    abs_m2 = a.m2;
    abs_m1 = a.m1;
    abs_lo = a.lo;

    if (sign_bit != (u64)0)
    {
        abs_lo = `!abs_lo;
        abs_m1 = `!abs_m1;
        abs_m2 = `!abs_m2;
        abs_hi = `!abs_hi;

        abs_lo = abs_lo + (u64)1;
        if (abs_lo == (u64)0) { abs_m1 = abs_m1 + (u64)1; };
        if (abs_m1 == (u64)0 `& abs_lo == (u64)0) { abs_m2 = abs_m2 + (u64)1; };
        if (abs_m2 == (u64)0 `& abs_m1 == (u64)0 `& abs_lo == (u64)0) { abs_hi = abs_hi + (u64)1; };
    };

    // abs_hi is a u64 but the compiler emits sitofp, which misreads values
    // with bit 63 set as negative.  Split into two 32-bit halves; each fits
    // safely in an i32 cast.
    // Layout is Q4.252: binary point at bit 252.
    // hi limb (bits 255:192) weight at bit 192 = 2^(192-252) = 2^-60
    // Upper half (bits 63:32 of hi) weight: 2^32 * 2^-60 = 2^-28
    // Lower half (bits 31:0  of hi) weight:        2^-60
    hi_upper = abs_hi >> 32;
    hi_lower = abs_hi `& 0xFFFFFFFF;
    f_upper = (float)(i32)hi_upper / 16777216.0;   // divide by 2^24
    f_lower = (float)(i32)hi_lower / 16777216.0;    // divide by 2^24
    f_lower = f_lower              / 4294967296.0;  // divide by 2^32 -> total 2^56
    f_hi = f_upper + f_lower;

    result = f_hi;

    if (sign_bit != (u64)0) { result = 0.0 - result; };

    return result;
};

// r = a + b  (256-bit two's complement, all pointers)
def fp256_add(fp256* a, fp256* b, fp256* r) -> void
{
    u64 lo, m1, m2, hi, c1, c2, c3;

    lo = a.lo + b.lo;
    c1 = (u64)0;
    if (lo < a.lo) { c1 = (u64)1; };

    m1 = a.m1 + b.m1 + c1;
    c2 = (u64)0;
    if (m1 < a.m1) { c2 = (u64)1; };
    if (c1 != (u64)0 `& m1 == a.m1) { c2 = (u64)1; };

    m2 = a.m2 + b.m2 + c2;
    c3 = (u64)0;
    if (m2 < a.m2) { c3 = (u64)1; };
    if (c2 != (u64)0 `& m2 == a.m2) { c3 = (u64)1; };

    hi = a.hi + b.hi + c3;

    r.lo = lo;
    r.m1 = m1;
    r.m2 = m2;
    r.hi = hi;

    return;
};

// r = a - b
def fp256_sub(fp256* a, fp256* b, fp256* r) -> void
{
    // Negate b into tmp, then add
    fp256 neg_b;
    neg_b.lo = `!b.lo;
    neg_b.m1 = `!b.m1;
    neg_b.m2 = `!b.m2;
    neg_b.hi = `!b.hi;

    neg_b.lo = neg_b.lo + (u64)1;
    if (neg_b.lo == (u64)0) { neg_b.m1 = neg_b.m1 + (u64)1; };
    if (neg_b.m1 == (u64)0 `& neg_b.lo == (u64)0) { neg_b.m2 = neg_b.m2 + (u64)1; };
    if (neg_b.m2 == (u64)0 `& neg_b.m1 == (u64)0 `& neg_b.lo == (u64)0) { neg_b.hi = neg_b.hi + (u64)1; };

    fp256_add(a, @neg_b, r);

    return;
};

// 64x64 -> 128 bit unsigned multiply, returning hi and lo halves
def umul128(u64 a, u64 b, u64* hi_out, u64* lo_out) -> void
{
    u64 a_lo, a_hi, b_lo, b_hi;
    u64 p0, p1, p2, p3, mid, carry;

    a_lo = a `& 0xFFFFFFFF;
    a_hi = a >> 32;
    b_lo = b `& 0xFFFFFFFF;
    b_hi = b >> 32;

    p0 = a_lo * b_lo;
    p1 = a_lo * b_hi;
    p2 = a_hi * b_lo;
    p3 = a_hi * b_hi;

    mid   = (p0 >> 32) + (p1 `& 0xFFFFFFFF) + (p2 `& 0xFFFFFFFF);
    carry = (mid >> 32) + (p1 >> 32) + (p2 >> 32) + p3;

    *lo_out = (p0 `& 0xFFFFFFFF) | (mid << 32);
    *hi_out = carry;

    return;
};

// r = a * b  (256-bit two's complement)
// Strategy: track signs, multiply magnitudes, re-apply sign.
def fp256_mul(fp256* a, fp256* b, fp256* r) -> void
{
    // Determine signs and get absolute values
    u64 sign_a, sign_b, sign_r;
    fp256 abs_a, abs_b;
    u64 c;

    sign_a = (a.hi >> 63) `& (u64)1;
    sign_b = (b.hi >> 63) `& (u64)1;
    sign_r = sign_a `^^ sign_b;

    // Compute |a|
    abs_a.lo = a.lo; abs_a.m1 = a.m1; abs_a.m2 = a.m2; abs_a.hi = a.hi;
    if (sign_a != (u64)0)
    {
        abs_a.lo = `!abs_a.lo; abs_a.m1 = `!abs_a.m1;
        abs_a.m2 = `!abs_a.m2; abs_a.hi = `!abs_a.hi;
        abs_a.lo = abs_a.lo + (u64)1;
        if (abs_a.lo == (u64)0) { abs_a.m1 = abs_a.m1 + (u64)1; };
        if (abs_a.m1 == (u64)0 `& abs_a.lo == (u64)0) { abs_a.m2 = abs_a.m2 + (u64)1; };
        if (abs_a.m2 == (u64)0 `& abs_a.m1 == (u64)0 `& abs_a.lo == (u64)0) { abs_a.hi = abs_a.hi + (u64)1; };
    };

    // Compute |b|
    abs_b.lo = b.lo; abs_b.m1 = b.m1; abs_b.m2 = b.m2; abs_b.hi = b.hi;
    if (sign_b != (u64)0)
    {
        abs_b.lo = `!abs_b.lo; abs_b.m1 = `!abs_b.m1;
        abs_b.m2 = `!abs_b.m2; abs_b.hi = `!abs_b.hi;
        abs_b.lo = abs_b.lo + (u64)1;
        if (abs_b.lo == (u64)0) { abs_b.m1 = abs_b.m1 + (u64)1; };
        if (abs_b.m1 == (u64)0 `& abs_b.lo == (u64)0) { abs_b.m2 = abs_b.m2 + (u64)1; };
        if (abs_b.m2 == (u64)0 `& abs_b.m1 == (u64)0 `& abs_b.lo == (u64)0) { abs_b.hi = abs_b.hi + (u64)1; };
    };

    // We only need the upper 256 bits of the 512-bit product (after shifting
    // right by 254 to account for the fixed-point scaling: Q2.254 * Q2.254
    // gives Q4.508, and we want Q2.254, so we keep bits 508:254 of the product,
    // which is bits 253:0 of the upper half after discarding the lowest 254 bits).
    //
    // Since values are < 4 in magnitude, the top few bits of the 512-bit product
    // are zero, so we really just need to multiply the lower limbs correctly.
    //
    // We perform a partial 256x256 multiply keeping only the bits we need.
    // The 256-bit number has limbs [lo, m1, m2, hi] = [L0, L1, L2, L3].
    // Product limbs (unshifted) at position i*64+j come from cross products.
    // We need bits 254..509 of the full product, i.e. we shift the 512-bit
    // result right by 254, which is 3*64+62 = right by 62 within the upper half.

    u64 p_lo, p_hi;
    // Accumulate into an 8-limb result array (only upper 4 limbs needed)
    u64 r0, r1, r2, r3, r4, r5, r6, r7;
    u64 t_lo, t_hi, prev;

    r0 = (u64)0; r1 = (u64)0; r2 = (u64)0; r3 = (u64)0;
    r4 = (u64)0; r5 = (u64)0; r6 = (u64)0; r7 = (u64)0;

    // L0 * L0 -> r0, r1
    umul128(abs_a.lo, abs_b.lo, @p_hi, @p_lo);
    r0 = r0 + p_lo; if (r0 < p_lo) { r1 = r1 + (u64)1; };
    r1 = r1 + p_hi; if (r1 < p_hi) { r2 = r2 + (u64)1; };

    // L0 * L1 -> r1, r2
    umul128(abs_a.lo, abs_b.m1, @p_hi, @p_lo);
    prev = r1; r1 = r1 + p_lo; if (r1 < prev) { r2 = r2 + (u64)1; };
    prev = r2; r2 = r2 + p_hi; if (r2 < prev) { r3 = r3 + (u64)1; };

    // L1 * L0 -> r1, r2
    umul128(abs_a.m1, abs_b.lo, @p_hi, @p_lo);
    prev = r1; r1 = r1 + p_lo; if (r1 < prev) { r2 = r2 + (u64)1; };
    prev = r2; r2 = r2 + p_hi; if (r2 < prev) { r3 = r3 + (u64)1; };

    // L0 * L2 -> r2, r3
    umul128(abs_a.lo, abs_b.m2, @p_hi, @p_lo);
    prev = r2; r2 = r2 + p_lo; if (r2 < prev) { r3 = r3 + (u64)1; };
    prev = r3; r3 = r3 + p_hi; if (r3 < prev) { r4 = r4 + (u64)1; };

    // L1 * L1 -> r2, r3
    umul128(abs_a.m1, abs_b.m1, @p_hi, @p_lo);
    prev = r2; r2 = r2 + p_lo; if (r2 < prev) { r3 = r3 + (u64)1; };
    prev = r3; r3 = r3 + p_hi; if (r3 < prev) { r4 = r4 + (u64)1; };

    // L2 * L0 -> r2, r3
    umul128(abs_a.m2, abs_b.lo, @p_hi, @p_lo);
    prev = r2; r2 = r2 + p_lo; if (r2 < prev) { r3 = r3 + (u64)1; };
    prev = r3; r3 = r3 + p_hi; if (r3 < prev) { r4 = r4 + (u64)1; };

    // L0 * L3 -> r3, r4
    umul128(abs_a.lo, abs_b.hi, @p_hi, @p_lo);
    prev = r3; r3 = r3 + p_lo; if (r3 < prev) { r4 = r4 + (u64)1; };
    prev = r4; r4 = r4 + p_hi; if (r4 < prev) { r5 = r5 + (u64)1; };

    // L1 * L2 -> r3, r4
    umul128(abs_a.m1, abs_b.m2, @p_hi, @p_lo);
    prev = r3; r3 = r3 + p_lo; if (r3 < prev) { r4 = r4 + (u64)1; };
    prev = r4; r4 = r4 + p_hi; if (r4 < prev) { r5 = r5 + (u64)1; };

    // L2 * L1 -> r3, r4
    umul128(abs_a.m2, abs_b.m1, @p_hi, @p_lo);
    prev = r3; r3 = r3 + p_lo; if (r3 < prev) { r4 = r4 + (u64)1; };
    prev = r4; r4 = r4 + p_hi; if (r4 < prev) { r5 = r5 + (u64)1; };

    // L3 * L0 -> r3, r4
    umul128(abs_a.hi, abs_b.lo, @p_hi, @p_lo);
    prev = r3; r3 = r3 + p_lo; if (r3 < prev) { r4 = r4 + (u64)1; };
    prev = r4; r4 = r4 + p_hi; if (r4 < prev) { r5 = r5 + (u64)1; };

    // L1 * L3 -> r4, r5
    umul128(abs_a.m1, abs_b.hi, @p_hi, @p_lo);
    prev = r4; r4 = r4 + p_lo; if (r4 < prev) { r5 = r5 + (u64)1; };
    prev = r5; r5 = r5 + p_hi; if (r5 < prev) { r6 = r6 + (u64)1; };

    // L3 * L1 -> r4, r5
    umul128(abs_a.hi, abs_b.m1, @p_hi, @p_lo);
    prev = r4; r4 = r4 + p_lo; if (r4 < prev) { r5 = r5 + (u64)1; };
    prev = r5; r5 = r5 + p_hi; if (r5 < prev) { r6 = r6 + (u64)1; };

    // L2 * L2 -> r4, r5
    umul128(abs_a.m2, abs_b.m2, @p_hi, @p_lo);
    prev = r4; r4 = r4 + p_lo; if (r4 < prev) { r5 = r5 + (u64)1; };
    prev = r5; r5 = r5 + p_hi; if (r5 < prev) { r6 = r6 + (u64)1; };

    // L2 * L3 -> r5, r6
    umul128(abs_a.m2, abs_b.hi, @p_hi, @p_lo);
    prev = r5; r5 = r5 + p_lo; if (r5 < prev) { r6 = r6 + (u64)1; };
    prev = r6; r6 = r6 + p_hi; if (r6 < prev) { r7 = r7 + (u64)1; };

    // L3 * L2 -> r5, r6
    umul128(abs_a.hi, abs_b.m2, @p_hi, @p_lo);
    prev = r5; r5 = r5 + p_lo; if (r5 < prev) { r6 = r6 + (u64)1; };
    prev = r6; r6 = r6 + p_hi; if (r6 < prev) { r7 = r7 + (u64)1; };

    // L3 * L3 -> r6, r7
    umul128(abs_a.hi, abs_b.hi, @p_hi, @p_lo);
    prev = r6; r6 = r6 + p_lo; if (r6 < prev) { r7 = r7 + (u64)1; };
    r7 = r7 + p_hi;

    // The 512-bit product is [r7,r6,r5,r4,r3,r2,r1,r0].
    // Fixed point: each operand is Q2.254, so product is Q4.508.
    // We want Q2.254, meaning we shift right by 254 bits = 3*64 + 62.
    // So we take limbs r3..r7 and shift right by 62 within them.
    // Result = (r3 >> 62) | (r4 << 2), etc.

    r.lo = (r3 >> 56) | (r4 << 8);
    r.m1 = (r4 >> 56) | (r5 << 8);
    r.m2 = (r5 >> 56) | (r6 << 8);
    r.hi = (r6 >> 56) | (r7 << 8);

    // Re-apply sign
    if (sign_r != (u64)0)
    {
        r.lo = `!r.lo; r.m1 = `!r.m1;
        r.m2 = `!r.m2; r.hi = `!r.hi;
        r.lo = r.lo + (u64)1;
        if (r.lo == (u64)0) { r.m1 = r.m1 + (u64)1; };
        if (r.m1 == (u64)0 `& r.lo == (u64)0) { r.m2 = r.m2 + (u64)1; };
        if (r.m2 == (u64)0 `& r.m1 == (u64)0 `& r.lo == (u64)0) { r.hi = r.hi + (u64)1; };
    };

    return;
};

// ------------------------------------------------------------------ Mandelbrot

def mandelbrot(fp256* x0, fp256* y0) -> int
{
    fp256 x, y, xx, yy, tmp, sum;
    float mag;
    int iter;

    fp256_from_float(0.0, @x);
    fp256_from_float(0.0, @y);
    iter = 0;

    while (iter < MAX_ITER)
    {
        fp256_mul(@x, @x, @xx);
        fp256_mul(@y, @y, @yy);

        fp256_add(@xx, @yy, @sum);
        mag = fp256_to_float(@sum);
        if (mag > 4.0) { return iter; };

        // xtemp = xx - yy + x0
        fp256_sub(@xx, @yy, @tmp);
        fp256_add(@tmp, x0, @xx);   // reuse xx as xtemp

        // y = 2*x*y + y0  ->  tmp = x*y, tmp += tmp (double), tmp += y0
        fp256_mul(@x, @y, @tmp);
        fp256_add(@tmp, @tmp, @y);
        fp256_add(@y, y0, @tmp);
        y.lo = tmp.lo; y.m1 = tmp.m1; y.m2 = tmp.m2; y.hi = tmp.hi;

        x.lo = xx.lo; x.m1 = xx.m1; x.m2 = xx.m2; x.hi = xx.hi;

        iter++;
    };

    return iter;
};

// Map iteration count to an RGB color using a smooth palette
def iter_to_color(int iter, float* r, float* g, float* b) -> void
{
    float t, s;

    if (iter == MAX_ITER)
    {
        // Inside the set - black
        *r = 0.0;
        *g = 0.0;
        *b = 0.0;
        return;
    };

    // t in [0,1] across one 64-step cycle - always positive
    t = (float)(iter % 64) / 63.0;

    // First half: blue -> cyan (r=0, g rises 0->1, b stays 1)
    // Second half: cyan -> orange (r rises, g falls slightly, b falls)
    if (t < 0.5)
    {
        s = t * 2.0;
        *r = 0.0;
        *g = s;
        *b = 1.0;
    }
    else
    {
        s = (t - 0.5) * 2.0;
        *r = s;
        *g = 1.0 - s * 0.5;
        *b = 1.0 - s;
    };

    return;
};

extern def !!GetTickCount() -> DWORD;

def main() -> int
{
    Window win( "Mandelbrot Set (256-bit) - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);

    fp256 cx, cy, zoom, half_zoom, x_min, y_min,
          x_range, y_range, fx, fy,
          zoom_delta, pan_delta, tmp;

    fp256_from_float(-0.5, @cx);
    fp256_from_float( 0.0, @cy);
    fp256_from_float( 3.0, @zoom);

    float zoom_speed, pan_speed, dt, zoom_hi;
    zoom_speed = 1.5;
    pan_speed  = 0.6;

    float px0, px1, py0, py1, r, gv, b;

    const int TILE = 4;
    int cols, rows, row, col, iter, cur_w, cur_h;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    WORD w_state, s_state, a_state, d_state, up_state, dn_state;

    while (win.process_messages())
    {
        t_now  = GetTickCount();
        dt     = (float)(t_now - t_last) / 1000.0;
        t_last = t_now;
        if (dt > 0.1) { dt = 0.1; };

        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };

        cols = cur_w / TILE;
        rows = cur_h / TILE;
        if (cols < 1) { cols = 1; };
        if (rows < 1) { rows = 1; };

        glViewport(0, 0, cur_w, cur_h);

        w_state  = GetAsyncKeyState(VK_W);
        s_state  = GetAsyncKeyState(VK_S);
        a_state  = GetAsyncKeyState(VK_A);
        d_state  = GetAsyncKeyState(VK_D);
        up_state = GetAsyncKeyState(VK_UP);
        dn_state = GetAsyncKeyState(VK_DOWN);

        if ((w_state `& 0x8000) != 0)
        {
            zoom_hi = fp256_to_float(@zoom);
            if (zoom_hi > 0.0000000001)
            {
                fp256_from_float(zoom_speed * dt, @zoom_delta);
                fp256_mul(@zoom, @zoom_delta, @tmp);
                fp256_sub(@zoom, @tmp, @zoom);
            };
        };

        if ((s_state `& 0x8000) != 0)
        {
            zoom_hi = fp256_to_float(@zoom);
            if (zoom_hi < 8.0)
            {
                fp256_from_float(zoom_speed * dt, @zoom_delta);
                fp256_mul(@zoom, @zoom_delta, @tmp);
                fp256_add(@zoom, @tmp, @zoom);
            };
        };

        if ((a_state `& 0x8000) != 0)
        {
            fp256_from_float(pan_speed * dt, @pan_delta);
            fp256_mul(@zoom, @pan_delta, @tmp);
            fp256_sub(@cx, @tmp, @cx);
        };

        if ((d_state `& 0x8000) != 0)
        {
            fp256_from_float(pan_speed * dt, @pan_delta);
            fp256_mul(@zoom, @pan_delta, @tmp);
            fp256_add(@cx, @tmp, @cx);
        };

        if ((up_state `& 0x8000) != 0)
        {
            fp256_from_float(pan_speed * dt, @pan_delta);
            fp256_mul(@zoom, @pan_delta, @tmp);
            fp256_sub(@cy, @tmp, @cy);
        };

        if ((dn_state `& 0x8000) != 0)
        {
            fp256_from_float(pan_speed * dt, @pan_delta);
            fp256_mul(@zoom, @pan_delta, @tmp);
            fp256_add(@cy, @tmp, @cy);
        };

        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        // half_zoom = zoom * 0.5
        fp256_from_float(0.5, @tmp);
        fp256_mul(@zoom, @tmp, @half_zoom);

        // x_min = cx - half_zoom
        fp256_sub(@cx, @half_zoom, @x_min);

        // y_min = cy - zoom * (cur_h/cur_w) * 0.5
        fp256_from_float((float)cur_h / (float)cur_w * 0.5, @tmp);
        fp256_mul(@zoom, @tmp, @y_min);
        fp256_sub(@cy, @y_min, @y_min);

        // x_range = zoom, y_range = zoom * (cur_h/cur_w)
        x_range.lo = zoom.lo; x_range.m1 = zoom.m1; x_range.m2 = zoom.m2; x_range.hi = zoom.hi;
        fp256_from_float((float)cur_h / (float)cur_w, @tmp);
        fp256_mul(@zoom, @tmp, @y_range);

        row = 0;
        while (row < rows)
        {
            col = 0;
            while (col < cols)
            {
                fp256_from_float(((float)col + 0.5) / (float)cols, @tmp);
                fp256_mul(@x_range, @tmp, @fx);
                fp256_add(@x_min, @fx, @fx);

                fp256_from_float(((float)row + 0.5) / (float)rows, @tmp);
                fp256_mul(@y_range, @tmp, @fy);
                fp256_add(@y_min, @fy, @fy);

                iter = mandelbrot(@fx, @fy);

                iter_to_color(iter, @r, @gv, @b);

                glColor3f(r, gv, b);

                px0 =  -1.0 + 2.0 * (float)(col * TILE) / (float)cur_w;
                py0 =   1.0 - 2.0 * (float)(row * TILE) / (float)cur_h;
                px1 =  -1.0 + 2.0 * (float)(col * TILE + TILE) / (float)cur_w;
                py1 =   1.0 - 2.0 * (float)(row * TILE + TILE) / (float)cur_h;

                glBegin(GL_QUADS);
                glVertex2f(px0, py0);
                glVertex2f(px1, py0);
                glVertex2f(px1, py1);
                glVertex2f(px0, py1);
                glEnd();

                col++;
            };
            row++;
        };

        gl.present();
        Sleep(16);
    };

    gl.__exit();
    win.__exit();

    return 0;
};
