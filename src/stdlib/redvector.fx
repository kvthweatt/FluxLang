// redvec.fx - Vector math library for 3D and 4D vectors
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_MATH
#import "redmath.fx";
#endif;

#ifndef FLUX_STANDARD_VECTORS
#def FLUX_STANDARD_VECTORS 1;
#endif;

namespace standard
{
    namespace vector
    {
        // ============================================
        // 3D Vector Struct
        // ============================================
        struct vec3
        {
            float x;
            float y;
            float z;
        };

        // ============================================
        // 4D Vector Struct
        // ============================================
        struct vec4
        {
            float x;
            float y;
            float z;
            float w;
        };

        // ============================================
        // VEC3 CONSTRUCTORS
        // ============================================

        def make_vec3(float x, float y, float z) -> vec3
        {
            vec3 v;
            v.x = x;
            v.y = y;
            v.z = z;
            return v;
        };

        def make_vec3(float scalar) -> vec3
        {
            vec3 v;
            v.x = scalar;
            v.y = scalar;
            v.z = scalar;
            return v;
        };

        def vec3_zero() -> vec3
        {
            return make_vec3(0.0, 0.0, 0.0);
        };

        def vec3_one() -> vec3
        {
            return make_vec3(1.0, 1.0, 1.0);
        };

        def vec3_up() -> vec3
        {
            return make_vec3(0.0, 1.0, 0.0);
        };

        def vec3_down() -> vec3
        {
            return make_vec3(0.0, -1.0, 0.0);
        };

        def vec3_left() -> vec3
        {
            return make_vec3(-1.0, 0.0, 0.0);
        };

        def vec3_right() -> vec3
        {
            return make_vec3(1.0, 0.0, 0.0);
        };

        def vec3_forward() -> vec3
        {
            return make_vec3(0.0, 0.0, 1.0);
        };

        def vec3_back() -> vec3
        {
            return make_vec3(0.0, 0.0, -1.0);
        };

        // ============================================
        // VEC4 CONSTRUCTORS
        // ============================================

        def make_vec4(float x, float y, float z, float w) -> vec4
        {
            vec4 v;
            v.x = x;
            v.y = y;
            v.z = z;
            v.w = w;
            return v;
        };

        def make_vec4(float scalar) -> vec4
        {
            vec4 v;
            v.x = scalar;
            v.y = scalar;
            v.z = scalar;
            v.w = scalar;
            return v;
        };

        def make_vec4(vec3 xyz, float w) -> vec4
        {
            vec4 v;
            v.x = xyz.x;
            v.y = xyz.y;
            v.z = xyz.z;
            v.w = w;
            return v;
        };

        def vec4_zero() -> vec4
        {
            return make_vec4(0.0, 0.0, 0.0, 0.0);
        };

        def vec4_one() -> vec4
        {
            return make_vec4(1.0, 1.0, 1.0, 1.0);
        };

        // ============================================
        // VEC3 BASIC OPERATIONS
        // ============================================

        def vec3_add(vec3 a, vec3 b) -> vec3
        {
            vec3 result;
            result.x = a.x + b.x;
            result.y = a.y + b.y;
            result.z = a.z + b.z;
            return result;
        };

        def vec3_sub(vec3 a, vec3 b) -> vec3
        {
            vec3 result;
            result.x = a.x - b.x;
            result.y = a.y - b.y;
            result.z = a.z - b.z;
            return result;
        };

        def vec3_mul(vec3 v, float scalar) -> vec3
        {
            vec3 result;
            result.x = v.x * scalar;
            result.y = v.y * scalar;
            result.z = v.z * scalar;
            return result;
        };

        def vec3_div(vec3 v, float scalar) -> vec3
        {
            vec3 result;
            result.x = v.x / scalar;
            result.y = v.y / scalar;
            result.z = v.z / scalar;
            return result;
        };

        def vec3_negate(vec3 v) -> vec3
        {
            vec3 result;
            result.x = -v.x;
            result.y = -v.y;
            result.z = -v.z;
            return result;
        };

        // Component-wise multiplication
        def vec3_mul_components(vec3 a, vec3 b) -> vec3
        {
            vec3 result;
            result.x = a.x * b.x;
            result.y = a.y * b.y;
            result.z = a.z * b.z;
            return result;
        };

        // ============================================
        // VEC4 BASIC OPERATIONS
        // ============================================

        def vec4_add(vec4 a, vec4 b) -> vec4
        {
            vec4 result;
            result.x = a.x + b.x;
            result.y = a.y + b.y;
            result.z = a.z + b.z;
            result.w = a.w + b.w;
            return result;
        };

        def vec4_sub(vec4 a, vec4 b) -> vec4
        {
            vec4 result;
            result.x = a.x - b.x;
            result.y = a.y - b.y;
            result.z = a.z - b.z;
            result.w = a.w - b.w;
            return result;
        };

        def vec4_mul(vec4 v, float scalar) -> vec4
        {
            vec4 result;
            result.x = v.x * scalar;
            result.y = v.y * scalar;
            result.z = v.z * scalar;
            result.w = v.w * scalar;
            return result;
        };

        def vec4_div(vec4 v, float scalar) -> vec4
        {
            vec4 result;
            result.x = v.x / scalar;
            result.y = v.y / scalar;
            result.z = v.z / scalar;
            result.w = v.w / scalar;
            return result;
        };

        def vec4_negate(vec4 v) -> vec4
        {
            vec4 result;
            result.x = -v.x;
            result.y = -v.y;
            result.z = -v.z;
            result.w = -v.w;
            return result;
        };

        // Component-wise multiplication
        def vec4_mul_components(vec4 a, vec4 b) -> vec4
        {
            vec4 result;
            result.x = a.x * b.x;
            result.y = a.y * b.y;
            result.z = a.z * b.z;
            result.w = a.w * b.w;
            return result;
        };

        // ============================================
        // VEC3 DOT & CROSS PRODUCTS
        // ============================================

        def vec3_dot(vec3 a, vec3 b) -> float
        {
            return a.x * b.x + a.y * b.y + a.z * b.z;
        };

        def vec3_cross(vec3 a, vec3 b) -> vec3
        {
            vec3 result;
            result.x = a.y * b.z - a.z * b.y;
            result.y = a.z * b.x - a.x * b.z;
            result.z = a.x * b.y - a.y * b.x;
            return result;
        };

        // ============================================
        // VEC4 DOT PRODUCT
        // ============================================

        def vec4_dot(vec4 a, vec4 b) -> float
        {
            return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        };

        // ============================================
        // VEC3 LENGTH & NORMALIZATION
        // ============================================

        def vec3_length_squared(vec3 v) -> float
        {
            return v.x * v.x + v.y * v.y + v.z * v.z;
        };

        def vec3_length(vec3 v) -> float
        {
            return sqrt(vec3_length_squared(v));
        };

        def vec3_normalize(vec3 v) -> vec3
        {
            float len = vec3_length(v);
            if (len < 0.000001)
            {
                return vec3_zero();
            };
            return vec3_div(v, len);
        };

        // ============================================
        // VEC4 LENGTH & NORMALIZATION
        // ============================================

        def vec4_length_squared(vec4 v) -> float
        {
            return v.x * v.x + v.y * v.y + v.z * v.z + v.w * v.w;
        };

        def vec4_length(vec4 v) -> float
        {
            return sqrt(vec4_length_squared(v));
        };

        def vec4_normalize(vec4 v) -> vec4
        {
            float len = vec4_length(v);
            if (len < 0.000001)
            {
                return vec4_zero();
            };
            return vec4_div(v, len);
        };

        // ============================================
        // VEC3 DISTANCE
        // ============================================

        def vec3_distance_squared(vec3 a, vec3 b) -> float
        {
            vec3 diff = vec3_sub(a, b);
            return vec3_length_squared(diff);
        };

        def vec3_distance(vec3 a, vec3 b) -> float
        {
            return sqrt(vec3_distance_squared(a, b));
        };

        // ============================================
        // VEC4 DISTANCE
        // ============================================

        def vec4_distance_squared(vec4 a, vec4 b) -> float
        {
            vec4 diff = vec4_sub(a, b);
            return vec4_length_squared(diff);
        };

        def vec4_distance(vec4 a, vec4 b) -> float
        {
            return sqrt(vec4_distance_squared(a, b));
        };

        // ============================================
        // VEC3 INTERPOLATION
        // ============================================

        def vec3_lerp(vec3 a, vec3 b, float t) -> vec3
        {
            vec3 result;
            result.x = lerp(a.x, b.x, t);
            result.y = lerp(a.y, b.y, t);
            result.z = lerp(a.z, b.z, t);
            return result;
        };

        // Spherical linear interpolation
        def vec3_slerp(vec3 a, vec3 b, float t) -> vec3
        {
            float dot = vec3_dot(a, b);
            
            // Clamp dot to avoid numerical errors
            if (dot > 1.0) { dot = 1.0; };
            if (dot < -1.0) { dot = -1.0; };
            
            float theta = acos(dot) * t;
            vec3 relative = vec3_sub(b, vec3_mul(a, dot));
            relative = vec3_normalize(relative);
            
            return vec3_add(vec3_mul(a, cos(theta)), vec3_mul(relative, sin(theta)));
        };

        // ============================================
        // VEC4 INTERPOLATION
        // ============================================

        def vec4_lerp(vec4 a, vec4 b, float t) -> vec4
        {
            vec4 result;
            result.x = lerp(a.x, b.x, t);
            result.y = lerp(a.y, b.y, t);
            result.z = lerp(a.z, b.z, t);
            result.w = lerp(a.w, b.w, t);
            return result;
        };

        // ============================================
        // VEC3 REFLECTION & PROJECTION
        // ============================================

        def vec3_reflect(vec3 v, vec3 normal) -> vec3
        {
            // r = v - 2 * dot(v, n) * n
            float d = vec3_dot(v, normal);
            vec3 scaled_normal = vec3_mul(normal, 2.0 * d);
            return vec3_sub(v, scaled_normal);
        };

        def vec3_project(vec3 v, vec3 onto) -> vec3
        {
            // proj = (dot(v, onto) / dot(onto, onto)) * onto
            float d = vec3_dot(v, onto);
            float onto_len_sq = vec3_length_squared(onto);
            if (onto_len_sq < 0.000001)
            {
                return vec3_zero();
            };
            return vec3_mul(onto, d / onto_len_sq);
        };

        // ============================================
        // VEC3 COMPARISON
        // ============================================

        def vec3_equals(vec3 a, vec3 b, float epsilon) -> bool
        {
            float dx = abs(a.x - b.x);
            float dy = abs(a.y - b.y);
            float dz = abs(a.z - b.z);
            return (dx < epsilon) & (dy < epsilon) & (dz < epsilon);
        };

        // ============================================
        // VEC4 COMPARISON
        // ============================================

        def vec4_equals(vec4 a, vec4 b, float epsilon) -> bool
        {
            float dx = abs(a.x - b.x);
            float dy = abs(a.y - b.y);
            float dz = abs(a.z - b.z);
            float dw = abs(a.w - b.w);
            return (dx < epsilon) & (dy < epsilon) & (dz < epsilon) & (dw < epsilon);
        };

        // ============================================
        // VEC3 MIN/MAX
        // ============================================

        def vec3_min(vec3 a, vec3 b) -> vec3
        {
            vec3 result;
            result.x = min(a.x, b.x);
            result.y = min(a.y, b.y);
            result.z = min(a.z, b.z);
            return result;
        };

        def vec3_max(vec3 a, vec3 b) -> vec3
        {
            vec3 result;
            result.x = max(a.x, b.x);
            result.y = max(a.y, b.y);
            result.z = max(a.z, b.z);
            return result;
        };

        def vec3_clamp(vec3 v, vec3 min_vec, vec3 max_vec) -> vec3
        {
            vec3 result;
            result.x = clamp(v.x, min_vec.x, max_vec.x);
            result.y = clamp(v.y, min_vec.y, max_vec.y);
            result.z = clamp(v.z, min_vec.z, max_vec.z);
            return result;
        };

        // ============================================
        // VEC4 MIN/MAX
        // ============================================

        def vec4_min(vec4 a, vec4 b) -> vec4
        {
            vec4 result;
            result.x = min(a.x, b.x);
            result.y = min(a.y, b.y);
            result.z = min(a.z, b.z);
            result.w = min(a.w, b.w);
            return result;
        };

        def vec4_max(vec4 a, vec4 b) -> vec4
        {
            vec4 result;
            result.x = max(a.x, b.x);
            result.y = max(a.y, b.y);
            result.z = max(a.z, b.z);
            result.w = max(a.w, b.w);
            return result;
        };

        def vec4_clamp(vec4 v, vec4 min_vec, vec4 max_vec) -> vec4
        {
            vec4 result;
            result.x = clamp(v.x, min_vec.x, max_vec.x);
            result.y = clamp(v.y, min_vec.y, max_vec.y);
            result.z = clamp(v.z, min_vec.z, max_vec.z);
            result.w = clamp(v.w, min_vec.w, max_vec.w);
            return result;
        };

        // ============================================
        // VEC3 ANGLE
        // ============================================

        def vec3_angle(vec3 a, vec3 b) -> float
        {
            float dot = vec3_dot(vec3_normalize(a), vec3_normalize(b));
            if (dot > 1.0) { dot = 1.0; };
            if (dot < -1.0) { dot = -1.0; };
            return acos(dot);
        };

        // ============================================
        // CONVERSIONS
        // ============================================

        def vec3_to_vec4(vec3 v, float w) -> vec4
        {
            return make_vec4(v.x, v.y, v.z, w);
        };

        def vec4_to_vec3(vec4 v) -> vec3
        {
            return make_vec3(v.x, v.y, v.z);
        };

        // ============================================
        // VEC3 UTILITY
        // ============================================

        def vec3_abs(vec3 v) -> vec3
        {
            vec3 result;
            result.x = abs(v.x);
            result.y = abs(v.y);
            result.z = abs(v.z);
            return result;
        };

        def vec3_floor(vec3 v) -> vec3
        {
            vec3 result;
            result.x = floor(v.x);
            result.y = floor(v.y);
            result.z = floor(v.z);
            return result;
        };

        def vec3_ceil(vec3 v) -> vec3
        {
            vec3 result;
            result.x = ceil(v.x);
            result.y = ceil(v.y);
            result.z = ceil(v.z);
            return result;
        };

        // ============================================
        // VEC4 UTILITY
        // ============================================

        def vec4_abs(vec4 v) -> vec4
        {
            vec4 result;
            result.x = abs(v.x);
            result.y = abs(v.y);
            result.z = abs(v.z);
            result.w = abs(v.w);
            return result;
        };

        def vec4_floor(vec4 v) -> vec4
        {
            vec4 result;
            result.x = floor(v.x);
            result.y = floor(v.y);
            result.z = floor(v.z);
            result.w = floor(v.w);
            return result;
        };

        def vec4_ceil(vec4 v) -> vec4
        {
            vec4 result;
            result.x = ceil(v.x);
            result.y = ceil(v.y);
            result.z = ceil(v.z);
            result.w = ceil(v.w);
            return result;
        };
    };
};

using standard::vec;
