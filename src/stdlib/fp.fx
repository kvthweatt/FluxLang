// fp.fx - Flux Floating Point Runtime (Pure Assembly)
// Copyright (C) 2026 Flux Community
// License: MIT

import "standard.fx";
using standard::io, standard::types;

namespace standard
{
    namespace floatpoint
    {
        // ============ FLOATING POINT CONTROL/STATUS ============
        struct MXCSR
        {
            unsigned data{32} value;
            
            public
            {
                def get() -> unsigned data{32}
                {
                    unsigned data{32} result;
                    volatile asm
                    {
                        stmxcsr result
                    };
                    return result;
                };
                
                def set(unsigned data{32} val) -> void
                {
                    volatile asm
                    {
                        ldmxcsr val
                    };
                    return void;
                };
                
                def enable_all_exceptions() -> void
                {
                    unsigned data{32} mxcsr = this.get();
                    mxcsr = mxcsr & 0xFFFFFFC0;  // Clear exception masks
                    this.set(mxcsr);
                    return void;
                };
                
                def disable_all_exceptions() -> void
                {
                    unsigned data{32} mxcsr = this.get();
                    mxcsr = mxcsr | 0x00001F80;  // Set all exception masks
                    this.set(mxcsr);
                    return void;
                };
                
                def set_rounding_mode(int mode) -> void
                {
                    // 00 = nearest, 01 = down, 10 = up, 11 = truncate
                    unsigned data{32} mxcsr = this.get();
                    mxcsr = (mxcsr & 0xFFFF9FFF) | ((mode & 3) << 13);
                    this.set(mxcsr);
                    return void;
                };
                
                def flush_denormals_to_zero(bool enable) -> void
                {
                    unsigned data{32} mxcsr = this.get();
                    if (enable)
                    {
                        mxcsr = mxcsr | 0x8040;  // Set FTZ and DAZ
                    }
                    else
                    {
                        mxcsr = mxcsr & 0xFFFF7FBF;
                    };
                    this.set(mxcsr);
                    return void;
                };
            };
        };

        struct FPUControl
        {
            unsigned data{16} value;
            
            public
            {
                def get() -> unsigned data{16}
                {
                    unsigned data{16} result;
                    volatile asm
                    {
                        fstcw result
                    };
                    return result;
                };
                
                def set(unsigned data{16} val) -> void
                {
                    volatile asm
                    {
                        fldcw val
                    };
                    return void;
                };
                
                def init() -> void
                {
                    volatile asm
                    {
                        finit
                    };
                    return void;
                };
                
                def set_precision(int prec) -> void
                {
                    // 00 = 24-bit (single), 01 = reserved, 10 = 53-bit (double), 11 = 64-bit (extended)
                    unsigned data{16} cw = this.get();
                    cw = (cw & 0xFCFF) | ((prec & 3) << 8);
                    this.set(cw);
                    return void;
                };
                
                def set_rounding_mode(int mode) -> void
                {
                    unsigned data{16} cw = this.get();
                    cw = (cw & 0xF3FF) | ((mode & 3) << 10);
                    this.set(cw);
                    return void;
                };
            };
        };

        // ============ FLOATING POINT INSTRUCTIONS ============

        namespace FPU
        {
            // x87 FPU operations
            def add(float a, float b) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr a
                    fld dword ptr b
                    faddp st(1), st(0)
                    fstp dword ptr result
                };
                return result;
            };
            
            def sub(float a, float b) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr a
                    fld dword ptr b
                    fsubp st(1), st(0)
                    fstp dword ptr result
                };
                return result;
            };
            
            def mul(float a, float b) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr a
                    fld dword ptr b
                    fmulp st(1), st(0)
                    fstp dword ptr result
                };
                return result;
            };
            
            def div(float a, float b) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr a
                    fld dword ptr b
                    fdivp st(1), st(0)
                    fstp dword ptr result
                };
                return result;
            };
            
            def sqrt(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fsqrt
                    fstp dword ptr result
                };
                return result;
            };
            
            def sin(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fsin
                    fstp dword ptr result
                };
                return result;
            };
            
            def cos(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fcos
                    fstp dword ptr result
                };
                return result;
            };
            
            def tan(float x) -> float
            {
                // tan(x) = sin(x)/cos(x)
                volatile asm
                {
                    fld dword ptr x
                    fsincos          // st(0)=cos, st(1)=sin
                    fdivp st(1), st(0)
                    fstp dword ptr result
                };
                return result;
            };
            
            def atan(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fld1
                    fpatan           // atan2(1, x) = atan(x)
                    fstp dword ptr result
                };
                return result;
            };
            
            def atan2(float y, float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr y
                    fld dword ptr x
                    fpatan
                    fstp dword ptr result
                };
                return result;
            };
            
            def ln(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld1
                    fld dword ptr x
                    fyl2x            // st(0)=log2(x)
                    fldl2e           // log2(e)
                    fdivp st(1), st(0)  // ln(x) = log2(x)/log2(e)
                    fstp dword ptr result
                };
                return result;
            };
            
            def log2(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld1
                    fld dword ptr x
                    fyl2x
                    fstp dword ptr result
                };
                return result;
            };
            
            def log10(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld1
                    fld dword ptr x
                    fyl2x            // st(0)=log2(x)
                    fldl2t           // log2(10)
                    fdivp st(1), st(0)  // log10(x) = log2(x)/log2(10)
                    fstp dword ptr result
                };
                return result;
            };
            
            def exp(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fldl2e           // log2(e)
                    fmulp st(1), st(0)  // x * log2(e)
                    f2xm1            // 2^(fraction) - 1
                    fld1
                    faddp st(1), st(0)  // 2^(fraction)
                    fscale           // 2^(integer) * 2^(fraction)
                    fstp st(1)       // Pop integer
                    fstp dword ptr result
                };
                return result;
            };
            
            def pow(float x, float y) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr y
                    fld dword ptr x
                    fyl2x            // y * log2(x)
                    f2xm1            // 2^(fraction) - 1
                    fld1
                    faddp st(1), st(0)  // 2^(fraction)
                    fscale           // 2^(integer) * 2^(fraction)
                    fstp st(1)       // Pop integer
                    fstp dword ptr result
                };
                return result;
            };
            
            def fmod(float x, float y) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr y
                    fld dword ptr x
                    fprem            // Partial remainder
                    fstp dword ptr result
                    fstp st(0)       // Clear stack
                };
                return result;
            };
            
            def floor(float x) -> float
            {
                float result;
                volatile asm {
                    fld dword ptr x
                    frndint          // Round to integer (using current rounding mode)
                    fstp dword ptr result
                };
                return result;
            };
            
            def ceil(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fld1
                    fld st(1)        // Duplicate x
                    fprem            // Get fractional part
                    fstp st(0)       // Discard fractional part
                    fsubp st(1), st(0)  // 1 - fractional part
                    fld dword ptr x
                    faddp st(1), st(0)  // x + (1 - fract(x))
                    frndint
                    fstp dword ptr result
                };
                return result;
            };
            
            def round(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    frndint          // Uses current rounding mode (should be nearest)
                    fstp dword ptr result
                };
                return result;
            };
            
            def trunc(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fld st(0)
                    frndint          // Round to integer
                    fcomip st(1)     // Compare with original
                    fstp st(0)       // Clear stack
                    fstp dword ptr result
                };
                return result;
            };
            
            def abs(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fabs
                    fstp dword ptr result
                };
                return result;
            };
            
            def chs(float x) -> float
            {
                float result;
                volatile asm
                {
                    fld dword ptr x
                    fchs             // Change sign
                    fstp dword ptr result
                };
                return result;
            };
            
            // Stack management
            def push(float x) -> void
            {
                volatile asm
                {
                    fld dword ptr x
                };
                return void;
            };
            
            def pop() -> float
            {
                float result;
                volatile asm
                {
                    fstp dword ptr result
                };
                return result;
            };
            
            def dup() -> void
            {
                volatile asm
                {
                    fld st(0)
                };
                return void;
            };
            
            def swap() -> void
            {
                volatile asm
                {
                    fxch st(1)
                };
                return void;
            };
            
            def clear_stack() -> void
            {
                volatile asm
                {
                    ffree st(0)
                    ffree st(1)
                    ffree st(2)
                    ffree st(3)
                    ffree st(4)
                    ffree st(5)
                    ffree st(6)
                    ffree st(7)
                };
                return void;
            };
        };

        // ============ SSE/AVX INSTRUCTIONS ============

        namespace SSE
        {
            // Single-precision vector operations (4 floats)
            def add_ps(float[4] a, float[4] b) -> float[4]
            {
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    addps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            def mul_ps(float[4] a, float[4] b) -> float[4]
            {
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    mulps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            def sqrt_ps(float[4] a) -> float[4]
            {
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    sqrtps xmm0
                    movups result, xmm0
                };
                return result;
            };
            
            def rsqrt_ps(float[4] a) -> float[4]
            {
                // Reciprocal square root approximation (12-bit)
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    rsqrtps xmm0
                    movups result, xmm0
                };
                return result;
            };
            
            def rcp_ps(float[4] a) -> float[4]
            {
                // Reciprocal approximation (12-bit)
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    rcpps xmm0
                    movups result, xmm0
                };
                return result;
            };
            
            def min_ps(float[4] a, float[4] b) -> float[4]
            {
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    minps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            def max_ps(float[4] a, float[4] b) -> float[4]
            {
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    maxps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            def and_ps(float[4] a, float[4] b) -> float[4]
            {
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    andps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            def or_ps(float[4] a, float[4] b) -> float[4]
            {
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    orps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            def xor_ps(float[4] a, float[4] b) -> float[4]
            {
                float[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    xorps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            // Scalar operations (single float)
            def add_ss(float a, float b) -> float
            {
                float result;
                volatile asm
                {
                    movss xmm0, a
                    movss xmm1, b
                    addss xmm0, xmm1
                    movss result, xmm0
                };
                return result;
            };
            
            def mul_ss(float a, float b) -> float
            {
                float result;
                volatile asm
                {
                    movss xmm0, a
                    movss xmm1, b
                    mulss xmm0, xmm1
                    movss result, xmm0
                };
                return result;
            };
            
            def sqrt_ss(float a) -> float
            {
                float result;
                volatile asm
                {
                    movss xmm0, a
                    sqrtss xmm0
                    movss result, xmm0
                };
                return result;
            };
            
            def rsqrt_ss(float a) -> float
            {
                float result;
                volatile asm
                {
                    movss xmm0, a
                    rsqrtss xmm0
                    movss result, xmm0
                };
                return result;
            };
            
            // Comparison operations
            def cmp_eq_ps(float[4] a, float[4] b) -> int[4]
            {
                int[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    cmpeqps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            def cmp_lt_ps(float[4] a, float[4] b) -> int[4]
            {
                int[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    cmpltps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
            
            def cmp_le_ps(float[4] a, float[4] b) -> int[4]
            {
                int[4] result;
                volatile asm
                {
                    movups xmm0, a
                    movups xmm1, b
                    cmpleps xmm0, xmm1
                    movups result, xmm0
                };
                return result;
            };
        };

        // ============ DOUBLE PRECISION OPERATIONS ============

        namespace Double {
            def add(double a, double b) -> double
            {
                double result;
                volatile asm
                {
                    fld qword ptr a
                    fld qword ptr b
                    faddp st(1), st(0)
                    fstp qword ptr result
                };
                return result;
            };
            
            def mul(double a, double b) -> double
            {
                double result;
                volatile asm
                {
                    fld qword ptr a
                    fld qword ptr b
                    fmulp st(1), st(0)
                    fstp qword ptr result
                };
                return result;
            };
            
            def sqrt(double x) -> double
            {
                double result;
                volatile asm
                {
                    fld qword ptr x
                    fsqrt
                    fstp qword ptr result
                };
                return result;
            };
            
            // SSE2 double-precision operations
            def add_pd(double[2] a, double[2] b) -> double[2]
            {
                double[2] result;
                volatile asm
                {
                    movupd xmm0, a
                    movupd xmm1, b
                    addpd xmm0, xmm1
                    movupd result, xmm0
                };
                return result;
            };
            
            def mul_pd(double[2] a, double[2] b) -> double[2]
            {
                double[2] result;
                volatile asm
                {
                    movupd xmm0, a
                    movupd xmm1, b
                    mulpd xmm0, xmm1
                    movupd result, xmm0
                };
                return result;
            };
            
            def sqrt_pd(double[2] a) -> double[2]
            {
                double[2] result;
                volatile asm
                {
                    movupd xmm0, a
                    sqrtpd xmm0
                    movupd result, xmm0
                };
                return result;
            };
        };

        // ============ VECTOR MATH ============

        namespace Vector
        {
            struct Vec2
            {
                float x, y;
                
                public
                {
                    def __init(float x, float y) -> this
                    {
                        this.x = x;
                        this.y = y;
                        return this;
                    };
                    
                    def __exit() -> void
                    {
                        return void;
                    };
                    
                    def add(Vec2 other) -> Vec2
                    {
                        Vec2 result;
                        result.x = FPU::add(this.x, other.x);
                        result.y = FPU::add(this.y, other.y);
                        return result;
                    };
                    
                    def length() -> float
                    {
                        return FPU::sqrt(FPU::add(FPU::mul(this.x, this.x), FPU::mul(this.y, this.y)));
                    };
                    
                    def normalize() -> Vec2
                    {
                        float len = this.length();
                        if (len == 0.0) { return Vec2(0.0, 0.0); };
                        Vec2 result;
                        result.x = FPU::div(this.x, len);
                        result.y = FPU::div(this.y, len);
                        return result;
                    };
                    
                    def dot(Vec2 other) -> float
                    {
                        return FPU::add(FPU::mul(this.x, other.x), FPU::mul(this.y, other.y));
                    };
                };
            };
            
            struct Vec3
            {
                float x, y, z;
                
                public
                {
                    def __init(float x, float y, float z) -> this
                    {
                        this.x = x;
                        this.y = y;
                        this.z = z;
                        return this;
                    };
                    
                    def __exit() -> void
                    {
                        return void;
                    };
                    
                    def cross(Vec3 other) -> Vec3
                    {
                        Vec3 result;
                        result.x = FPU::sub(FPU::mul(this.y, other.z), FPU::mul(this.z, other.y));
                        result.y = FPU::sub(FPU::mul(this.z, other.x), FPU::mul(this.x, other.z));
                        result.z = FPU::sub(FPU::mul(this.x, other.y), FPU::mul(this.y, other.x));
                        return result;
                    };
                    
                    def length() -> float
                    {
                        return FPU::sqrt(FPU::add(FPU::add(
                            FPU::mul(this.x, this.x),
                            FPU::mul(this.y, this.y)),
                            FPU::mul(this.z, this.z)
                        ));
                    };
                };
            };
            
            struct Vec4
            {
                float x, y, z, w;
                
                public
                {
                    def __init(float x, float y, float z, float w) -> this
                    {
                        this.x = x;
                        this.y = y;
                        this.z = z;
                        this.w = w;
                        return this;
                    };
                    
                    def __exit() -> void
                    {
                        return void;
                    };
                    
                    // SSE-optimized operations
                    def add(Vec4 other) -> Vec4
                    {
                        Vec4 result;
                        float[4] a = [this.x, this.y, this.z, this.w];
                        float[4] b = [other.x, other.y, other.z, other.w];
                        float[4] r = SSE::add_ps(a, b);
                        result.x = r[0];
                        result.y = r[1];
                        result.z = r[2];
                        result.w = r[3];
                        return result;
                    };
                };
            };
            
            struct Mat4 {
                float[16] data;
                
                public
                {
                    def __init() -> this
                    {
                        // Identity matrix
                        for (int i = 0; i < 16; i++)
                        {
                            this.data[i] = (i % 5 == 0) ? 1.0 : 0.0;
                        };
                        return this;
                    };
                    
                    def __exit() -> void
                    {
                        return void;
                    };
                    
                    def mul(Mat4 other) -> Mat4
                    {
                        Mat4 result;
                        for (int row = 0; row < 4; row++)
                        {
                            for (int col = 0; col < 4; col++)
                            {
                                float sum = 0.0;
                                for (int k = 0; k < 4; k++)
                                {
                                    sum = FPU::add(sum, 
                                        FPU::mul(
                                            this.data[row * 4 + k],
                                            other.data[k * 4 + col]
                                        )
                                    );
                                };
                                result.data[row * 4 + col] = sum;
                            };
                        };
                        return result;
                    };
                    
                    def transform(Vec4 v) -> Vec4
                    {
                        Vec4 result;
                        result.x = FPU::add(
                            FPU::add(
                                FPU::mul(this.data[0], v.x),
                                FPU::mul(this.data[1], v.y)
                            ),
                            FPU::add(
                                FPU::mul(this.data[2], v.z),
                                FPU::mul(this.data[3], v.w)
                            )
                        );
                        result.y = FPU::add(
                            FPU::add(
                                FPU::mul(this.data[4], v.x),
                                FPU::mul(this.data[5], v.y)
                            ),
                            FPU::add(
                                FPU::mul(this.data[6], v.z),
                                FPU::mul(this.data[7], v.w)
                            )
                        );
                        // ... TODO: and so on for z and w
                        return result;
                    };
                };
            };
        };

        // ============ INITIALIZATION ============

        def __fp_init() -> void
        {
            // Initialize x87 FPU
            volatile asm
            {
                finit
                fwait
            };
            
            // Set x87 control word (default: 0x037F)
            // Precision: 64-bit, Rounding: nearest, Exception mask: all
            unsigned data{16} cw = 0x037F;
            volatile asm
            {
                fldcw cw
            };
            
            // Initialize SSE control/status register (default: 0x1F80)
            unsigned data{32} mxcsr = 0x1F80;
            volatile asm
            {
                ldmxcsr mxcsr
            };
            
            return void;
        };

        // ============ DIAGNOSTICS ============

        def __fp_dump_state() -> void
        {
            print("=== FPU State ===");
            
            // Get x87 control word
            unsigned data{16} cw;
            volatile asm
            {
                fstcw cw
            };
            print(f"Control Word: 0x{cw:04X}");
            
            // Get x87 status word
            unsigned data{16} sw;
            volatile asm
            {
                fstsw sw
            };
            print(f"Status Word: 0x{sw:04X}");
            
            // Get MXCSR
            unsigned data{32} mxcsr;
            volatile asm
            {
                stmxcsr mxcsr
            };
            print(f"MXCSR: 0x{mxcsr:08X}");
            
            // Check FPU stack
            unsigned data{16} tag;
            volatile asm
            {
                fstenv tag
            };
            print(f"Tag Word: 0x{tag:04X}");
            
            return void;
        };

        // ============ EXCEPTION HANDLING ============

        namespace FPExceptions
        {
            def check_status() -> string
            {
                unsigned data{16} sw;
                volatile asm
                {
                    fstsw sw
                };
                
                if (sw & 0x0001) { return "Invalid operation"; };
                if (sw & 0x0002) { return "Denormal operand"; };
                if (sw & 0x0004) { return "Divide by zero"; };
                if (sw & 0x0008) { return "Overflow"; };
                if (sw & 0x0010) { return "Underflow"; };
                if (sw & 0x0020) { return "Precision"; };
                
                return "No exceptions";
            };
            
            def clear_exceptions() -> void
            {
                volatile asm
                {
                    fclex
                };
                return void;
            };
            
            def wait() -> void
            {
                volatile asm
                {
                    fwait
                };
                return void;
            };
        };

        // ============ COMPILE-TIME FP EVALUATION ============

        compt
        {
            // Pre-compute common constants at compile time
            def compute_pi() -> float
            {
                // Machin's formula: π/4 = 4*arctan(1/5) - arctan(1/239)
                float pi_over_4 = FPU::sub(
                    FPU::mul(4.0, FPU::atan(0.2)),
                    FPU::atan(1.0/239.0)
                );
                return FPU::mul(pi_over_4, 4.0);
            };
            
            global def PI compute_pi();
            global def E FPU::exp(1.0);
            global def LN2 FPU::ln(2.0);
        };

        // ============ FIXED-POINT ARITHMETIC ============

        namespace Fixed
        {
            // 32-bit fixed point with 16 bits integer, 16 bits fractional
            struct Q16_16
            {
                int value;  // Actually signed data{32}
                
                public
                {
                    def __init(int whole, int frac) -> this
                    {
                        this.value = (whole << 16) | (frac & 0xFFFF);
                        return this;
                    };
                    
                    def __exit() -> void
                    {
                        return void;
                    };
                    
                    def add(Q16_16 other) -> Q16_16
                    {
                        Q16_16 result;
                        result.value = this.value + other.value;
                        return result;
                    };
                    
                    def mul(Q16_16 other) -> Q16_16
                    {
                        Q16_16 result;
                        // Multiply 64-bit, then shift right 16 bits
                        long long product = (long long)this.value * (long long)other.value;
                        result.value = (int)(product >> 16);
                        return result;
                    };
                    
                    def to_float() -> float
                    {
                        return (float)this.value / 65536.0;
                    };
                    
                    def from_float(float x) -> Q16_16
                    {
                        Q16_16 result;
                        result.value = (int)(x * 65536.0);
                        return result;
                    };
                };
            };
        };
    };
};