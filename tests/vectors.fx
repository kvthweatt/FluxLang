#import "standard.fx";
#import "redmath.fx";

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


def main() -> int
{
	return 0;
};