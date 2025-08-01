// Vectors - Flux Standard Library

if (!def(FLUX_STANDARD_MATH))
{
    global import "math.fx";
};

using standard::math;

namespace standard
{
    const namespace vectors
    {
        // -- Forward Declarations --
        def length(Vec2 v) -> float;
        def length(Vec3 v) -> float;
        def length(Vec4 v) -> float;
        // -- /Forward Declarations --

        // ---- Contracts ----
        contract NoOverflow {
            assert(
                abs(a.x) + abs(b.x) < float.max &&
                abs(a.y) + abs(b.y) < float.max &&
                abs(a.z) + abs(b.z) < float.max,
                "Vector addition overflow"
            );
        };

        contract ValidVector2 {
            assert(!(is_nan(x) || is_nan(y)), "Vector contains NaN");
        };

        contract ValidVector3 {
            assert(!(is_nan(x) || is_nan(y) || is_nan(z)), "Vector contains NaN");
        };

        contract ValidVector4 {
            assert(!(is_nan(x) || is_nan(y) || is_nan(z) || is_nan(w)), "Vector contains NaN");
        };

        contract PositiveResult {
            assert(result >= 0, "Length cannot be negative");
        };
        // ---- /Contracts ----

        // ---- Structures ----
        struct Vec2 {
            float x, y;
        } : ValidVector2;

        struct Vec3 {
            float x, y, z;
        } : ValidVector3;

        struct Vec4 {
            float x, y, z, w;
        } : ValidVector4;

        // ---- Operators ----
        // -- 2D --
        operator (Vec3 a, Vec3 b)[+] -> Vec3 {
            return Vec3(a.x + b.x, a.y + b.y, a.z + b.z);
        } : NoOverflow;

        operator (Vec3 a, Vec3 b)[-] -> Vec3 {
            return Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
        };

        operator (Vec3 a, float s)[*] -> Vec3 {
            return Vec3(a.x * s, a.y * s, a.z * s);
        };
        // -- /2D --

        // --- 3D ---
        operator (Vec3 a, Vec3 b)[+] -> Vec3 {
            return Vec3(a.x + b.x, a.y + b.y, a.z + b.z);
        } : NoOverflow;

        operator (Vec3 a, Vec3 b)[-] -> Vec3 {
            return Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
        };

        operator (Vec3 a, float s)[*] -> Vec3 {
            return Vec3(a.x * s, a.y * s, a.z * s);
        };
        // --- /3D ---

        // ---- 4D ----
        operator (Vec3 a, Vec3 b)[+] -> Vec3 {
            return Vec3(a.x + b.x, a.y + b.y, a.z + b.z);
        } : NoOverflow;

        operator (Vec3 a, Vec3 b)[-] -> Vec3 {
            return Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
        };

        operator (Vec3 a, float s)[*] -> Vec3 {
            return Vec3(a.x * s, a.y * s, a.z * s);
        };
        // ---- /4D ----
        // ---- /Operators ----

        // -- Math Functions --
        def length(Vec2 v) -> float : ValidVector2 
        {
            return sqrt(v.x^2 + v.y^2);
        } : PositiveResult;

        // Calculate magnitude (length) of Vec3
        def length(Vec3 v) -> float : ValidVector3
        {
            return sqrt(v.x^2 + v.y^2 + v.z^2);
        } : PositiveResult;

        // Calculate magnitude of Vec4
        def length(Vec4 v) -> float : ValidVector4
        {
            return sqrt(v.x^2 + v.y^2 + v.z^2 + v.w^2);
        } : PositiveResult;

        // Normalize Vec2 to unit length
        def normalize(Vec2 v) -> Vec2 : ValidVector2
        {
            float len = length(v);
            assert(len > 0, "Cannot normalize zero-length vector");
            return Vec2(v.x/len, v.y/len);
        } : UnitLength;

        // Normalize Vec3 to unit length
        def normalize(Vec3 v) -> Vec3 : ValidVector3
        {
            float len = length(v);
            assert(len > 0, "Cannot normalize zero-length vector");
            return Vec3(v.x/len, v.y/len, v.z/len);
        } : UnitLength;

        // Normalize Vec4 to unit length
        def normalize(Vec4 v) -> Vec4 : ValidVector4
        {
            float len = length(v);
            assert(len > 0, "Cannot normalize zero-length vector");
            return Vec4(v.x/len, v.y/len, v.z/len, v.w/len);
        } : UnitLength;

        // Dot product for Vec2
        def dot(Vec2 a, Vec2 b) -> float : ValidVector2
        {
            return a.x*b.x + a.y*b.y;
        };

        // Dot product for Vec3
        def dot(Vec3 a, Vec3 b) -> float : ValidVector3
        {
            return a.x*b.x + a.y*b.y + a.z*b.z;
        };

        // Dot product for Vec4
        def dot(Vec4 a, Vec4 b) -> float : ValidVector4
        {
            return a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
        };

        // Cross product (3D only)
        def cross(Vec3 a, Vec3 b) -> Vec3 : ValidVector3
        {
            return Vec3(
                a.y*b.z - a.z*b.y,
                a.z*b.x - a.x*b.z,
                a.x*b.y - a.y*b.x
            );
        };

        // Distance between two Vec2 points
        def distance(Vec2 a, Vec2 b) -> float
        {
            return length(Vec2(b.x-a.x, b.y-a.y));
        } : PositiveResult;

        // Distance between two Vec3 points
        def distance(Vec3 a, Vec3 b) -> float
        {
            return length(Vec3(b.x-a.x, b.y-a.y, b.z-a.z));
        } : PositiveResult;

        // Distance between two Vec4 points  
        def distance(Vec4 a, Vec4 b) -> float
        {
            return length(Vec4(b.x-a.x, b.y-a.y, b.z-a.z, b.w-a.w));
        } : PositiveResult;

        // Linear interpolation between vectors
        def lerp(Vec2 a, Vec2 b, float t) -> Vec2
        {
            Vec2 v = {float a = a.x + (b.x-a.x) * t,
                      float b = a.y + (b.y-a.y) * t};
            return v;
        };
        def lerp(Vec3 a, Vec3 b, float t) -> Vec3
        {
            Vec2 v = {float a = a.x + (b.x-a.x) * t,
                      float b = a.y + (b.y-a.y) * t,
                      float c = a.z + (b.z-a.z) * t};
            return v;
        };

        // Linear interpolation for Vec4
        def lerp(Vec4 a, Vec4 b, float t) -> Vec4
        {
            Vec2 v = {float a = a.x + (b.x-a.x) * t,
                      float b = a.y + (b.y-a.y) * t,
                      float c = a.z + (b.z-a.z) * t,
                      float d = a.w + (b.w-a.w) * t};
            return v;
        };

        // Reflect vector about normal
        def reflect(Vec3 incident, Vec3 normal) -> Vec3
        {
            return incident - normal * (2.0 * dot(incident, normal));
        };

        // ---- Homogeneous Coordinate Operations ----
        def to_3d(Vec4 v) -> Vec3 
        {
            assert(v.w != 0, "Cannot project point at infinity");
            return Vec3(v.x/v.w, v.y/v.w, v.z/v.w);
        };

        def to_4d(Vec3 v, float w = 1.0) -> Vec4
        {
            return Vec4(v.x, v.y, v.z, w);
        };

        // ---- Additional Vector Operations ----
        def hadamard(Vec4 a, Vec4 b) -> Vec4  // Component-wise multiplication
        {
            return Vec4(a.x*b.x, a.y*b.y, a.z*b.z, a.w*b.w);
        };

        def max_component(Vec4 v) -> float
        {
            return max(max(v.x, v.y), max(v.z, v.w));
        };

        def min_component(Vec4 v) -> float 
        {
            return min(min(v.x, v.y), min(v.z, v.w));
        };
        // -- /Math Functions --
    };
};