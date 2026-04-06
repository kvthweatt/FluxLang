// Author: Karac V. Thweatt
//
// raytracing.fx - Flux Path Tracing Library
//
// A physically-based path tracer built on Flux stdlib primitives.
//
// PRIMITIVES:
//   Sphere, Triangle, AABB (axis-aligned bounding box), Plane
//
// BVH:
//   Two-level bounding volume hierarchy for O(log n) intersection.
//   Build with bvh_build(), free with bvh_free().
//
// MATERIALS:
//   RT_MAT_LAMBERTIAN  - Diffuse (Lambertian reflection)
//   RT_MAT_METAL       - Specular with configurable fuzz
//   RT_MAT_DIELECTRIC  - Glass/refraction (Schlick Fresnel)
//   RT_MAT_EMISSIVE    - Light source (no shadow ray needed)
//
// CAMERA:
//   Configurable origin, look-at, up, vertical FOV.
//   Aperture + focus distance for depth of field.
//
// RENDERER:
//   rt_render() writes 0xAARRGGBB u32 pixels into a caller-supplied buffer.
//   Tile-based; each tile is independent for future threading integration.
//
// Usage:
//   #import "raytracing.fx";
//   using raytracer;
//
//   RTScene scene;  rt_scene_init(@scene, 64);
//   rt_scene_add_sphere(@scene, vec3(0,0,-1), 0.5, mat_lambertian(vec3(0.8,0.3,0.3)));
//   rt_scene_add_sphere(@scene, vec3(0,-100.5,-1), 100.0, mat_lambertian(vec3(0.8,0.8,0.0)));
//   RTCamera cam;  rt_camera_init(@cam, vec3(0,0,0), vec3(0,0,-1), vec3(0,1,0), 90.0, 1.0, 0.0, 1.0);
//   u32* buf = (u32*)fmalloc((size_t)(width * height * (sizeof(u32) / 8)));
//   rt_render(@scene, @cam, buf, width, height, 64, 8);
//   rt_scene_free(@scene);
//

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_MATH
#import "math.fx";
#endif;

#ifndef FLUX_STANDARD_VECTORS
#import "vectors.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "memory.fx";
#endif;

#ifndef FLUX_STANDARD_ALLOCATORS
#import "allocators.fx";
#endif;

#ifndef FLUX_STANDARD_RANDOM
#import "random.fx";
#endif;

#ifndef FLUX_RAYTRACING
#def FLUX_RAYTRACING 1;

using standard::vectors;
using standard::math;
using standard::memory::allocators::stdheap;
using standard::random;

// ============================================================================
// CONSTANTS
// ============================================================================

#def RT_EPSILON         0.001;       // Shadow acne offset
#def RT_INF             1000000000.0; // Effective infinity for t comparisons
#def RT_PI              3.14159265358979323846;
#def RT_MAX_DEPTH       64;          // Maximum bounce depth

#def RT_MAT_LAMBERTIAN  0;
#def RT_MAT_METAL       1;
#def RT_MAT_DIELECTRIC  2;
#def RT_MAT_EMISSIVE    3;

#def RT_PRIM_SPHERE     0;
#def RT_PRIM_TRIANGLE   1;
#def RT_PRIM_PLANE      2;

#def RT_TILE_SIZE       32;          // Pixels per tile edge

// ============================================================================
// STRUCTS
// ============================================================================

// Material descriptor — all variants packed into one struct
struct RTMaterial
{
    i32   kind;          // RT_MAT_*
    Vec3  albedo;        // Base colour / emission colour
    float fuzz;          // Metal: roughness [0,1]. Dielectric: unused.
    float ior;           // Dielectric index of refraction (e.g. 1.5 for glass)
    float emission;      // Emissive: luminance scale
};

// Ray: origin + unit direction
struct RTRay
{
    Vec3 origin;
    Vec3 dir;
};

// Hit record filled by intersection tests
struct RTHit
{
    float    t;          // Ray parameter at hit
    Vec3     point;      // World-space hit point
    Vec3     normal;     // Surface normal (always opposite to ray)
    bool     front;      // True if ray hit the outside face
    i32      mat_idx;    // Index into scene material array
};

// Sphere primitive
struct RTSphere
{
    Vec3  center;
    float radius;
    i32   mat_idx;
};

// Triangle primitive (vertices A, B, C; precomputed normal)
struct RTTriangle
{
    Vec3 a, b, c;
    Vec3 normal;         // Precomputed, normalised
    i32  mat_idx;
};

// Infinite plane (normal + D such that dot(normal, p) = d)
struct RTPlane
{
    Vec3  normal;
    float d;
    i32   mat_idx;
};

// Generic primitive wrapper
struct RTPrimitive
{
    i32        kind;      // RT_PRIM_*
    i32        idx;       // Index into the appropriate array
    // AABB for BVH build
    Vec3       aabb_min;
    Vec3       aabb_max;
};

// BVH node — either an internal node (left/right children) or a leaf
struct RTBVHNode
{
    Vec3  aabb_min;
    Vec3  aabb_max;
    i32   left;          // Child index, or -1 if leaf
    i32   right;         // Child index, or -1 if leaf
    i32   prim_start;    // Leaf: first primitive index in sorted array
    i32   prim_count;    // Leaf: primitive count (0 = internal node)
};

// Scene container
struct RTScene
{
    // Materials
    RTMaterial* materials;
    i32         mat_count, mat_cap;

    // Primitives by type
    RTSphere*   spheres;
    i32         sphere_count, sphere_cap;

    RTTriangle* triangles;
    i32         tri_count, tri_cap;

    RTPlane*    planes;
    i32         plane_count, plane_cap;

    // Unified primitive list (for BVH)
    RTPrimitive* prims;
    i32          prim_count, prim_cap;

    // BVH
    RTBVHNode*  bvh_nodes;
    i32         bvh_node_count;
    i32*        bvh_prim_order;   // Sorted primitive indices
};

// Camera
struct RTCamera
{
    Vec3  origin;
    Vec3  lower_left;    // Lower-left corner of the virtual film plane
    Vec3  horizontal;    // Full horizontal span of film plane
    Vec3  vertical;      // Full vertical span of film plane
    Vec3  u, v, w;       // Camera basis vectors
    float lens_radius;   // 0 = pinhole
    float focus_dist;
};

// ============================================================================
// MATERIAL CONSTRUCTORS
// ============================================================================

namespace raytracer
{
    def mat_lambertian(Vec3 albedo) -> RTMaterial
    {
        RTMaterial m;
        m.kind   = RT_MAT_LAMBERTIAN;
        m.albedo = albedo;
        m.fuzz   = 0.0;
        m.ior    = 1.0;
        m.emission = 0.0;
        return m;
    };

    def mat_metal(Vec3 albedo, float fuzz) -> RTMaterial
    {
        RTMaterial m;
        m.kind    = RT_MAT_METAL;
        m.albedo  = albedo;
        m.fuzz    = clamp(fuzz, 0.0, 1.0);
        m.ior     = 1.0;
        m.emission = 0.0;
        return m;
    };

    def mat_dielectric(float ior) -> RTMaterial
    {
        RTMaterial m;
        m.kind    = RT_MAT_DIELECTRIC;
        m.albedo  = vec3(1.0, 1.0, 1.0);
        m.fuzz    = 0.0;
        m.ior     = ior;
        m.emission = 0.0;
        return m;
    };

    def mat_emissive(Vec3 colour, float strength) -> RTMaterial
    {
        RTMaterial m;
        m.kind     = RT_MAT_EMISSIVE;
        m.albedo   = colour;
        m.fuzz     = 0.0;
        m.ior      = 1.0;
        m.emission = strength;
        return m;
    };

    // ============================================================================
    // SCENE MANAGEMENT
    // ============================================================================

    def rt_scene_init(RTScene* s, i32 initial_cap) -> void
    {
        size_t mat_bytes, prim_bytes, sphere_bytes, tri_bytes, plane_bytes;

        mat_bytes    = (size_t)(initial_cap * (i32)(sizeof(RTMaterial)  / 8));
        prim_bytes   = (size_t)(initial_cap * (i32)(sizeof(RTPrimitive) / 8));
        sphere_bytes = (size_t)(initial_cap * (i32)(sizeof(RTSphere)    / 8));
        tri_bytes    = (size_t)(initial_cap * (i32)(sizeof(RTTriangle)  / 8));
        plane_bytes  = (size_t)(initial_cap * (i32)(sizeof(RTPlane)     / 8));

        s.materials    = (RTMaterial*)fmalloc(mat_bytes);
        s.mat_count    = 0;
        s.mat_cap      = initial_cap;

        s.spheres      = (RTSphere*)fmalloc(sphere_bytes);
        s.sphere_count = 0;
        s.sphere_cap   = initial_cap;

        s.triangles    = (RTTriangle*)fmalloc(tri_bytes);
        s.tri_count    = 0;
        s.tri_cap      = initial_cap;

        s.planes       = (RTPlane*)fmalloc(plane_bytes);
        s.plane_count  = 0;
        s.plane_cap    = initial_cap;

        s.prims        = (RTPrimitive*)fmalloc(prim_bytes);
        s.prim_count   = 0;
        s.prim_cap     = initial_cap;

        s.bvh_nodes        = (RTBVHNode*)0;
        s.bvh_node_count   = 0;
        s.bvh_prim_order   = (i32*)0;
    };

    def rt_scene_free(RTScene* s) -> void
    {
        ffree((u64)s.materials);
        ffree((u64)s.spheres);
        ffree((u64)s.triangles);
        ffree((u64)s.planes);
        ffree((u64)s.prims);
        if ((u64)s.bvh_nodes != (u64)0)
        {
            ffree((u64)s.bvh_nodes);
        };
        if ((u64)s.bvh_prim_order != (u64)0)
        {
            ffree((u64)s.bvh_prim_order);
        };
    };

    def rt_scene_add_material(RTScene* s, RTMaterial mat) -> i32
    {
        i32      idx;
        size_t   new_bytes;
        RTMaterial* new_buf;

        if (s.mat_count >= s.mat_cap)
        {
            s.mat_cap  = s.mat_cap * 2;
            new_bytes  = (size_t)(s.mat_cap * (i32)(sizeof(RTMaterial) / 8));
            new_buf    = (RTMaterial*)fmalloc(new_bytes);
            memcpy((void*)new_buf, (void*)s.materials, (size_t)((s.mat_count) * (i32)(sizeof(RTMaterial) / 8)));
            ffree((u64)s.materials);
            s.materials = new_buf;
        };
        idx = s.mat_count;
        s.materials[idx] = mat;
        s.mat_count++;
        return idx;
    };

    // Internal: register a primitive into the unified list and compute its AABB
    def rt_scene_push_prim(RTScene* s, i32 kind, i32 type_idx, Vec3 bb_min, Vec3 bb_max) -> void
    {
        RTPrimitive* new_buf;
        size_t new_bytes;
        i32 idx;

        if (s.prim_count >= s.prim_cap)
        {
            s.prim_cap = s.prim_cap * 2;
            new_bytes  = (size_t)(s.prim_cap * (i32)(sizeof(RTPrimitive) / 8));
            new_buf    = (RTPrimitive*)fmalloc(new_bytes);
            memcpy((void*)new_buf, (void*)s.prims, (size_t)(s.prim_count * (i32)(sizeof(RTPrimitive) / 8)));
            ffree((u64)s.prims);
            s.prims = new_buf;
        };
        idx = s.prim_count;
        s.prims[idx].kind     = kind;
        s.prims[idx].idx      = type_idx;
        s.prims[idx].aabb_min = bb_min;
        s.prims[idx].aabb_max = bb_max;
        s.prim_count++;
    };

    def rt_scene_add_sphere(RTScene* s, Vec3 center, float radius, RTMaterial mat) -> i32
    {
        RTSphere*  new_buf;
        size_t     new_bytes;
        i32        mat_idx, sphere_idx;
        Vec3       bb_min, bb_max;

        mat_idx = rt_scene_add_material(s, mat);

        if (s.sphere_count >= s.sphere_cap)
        {
            s.sphere_cap = s.sphere_cap * 2;
            new_bytes    = (size_t)(s.sphere_cap * (i32)(sizeof(RTSphere) / 8));
            new_buf      = (RTSphere*)fmalloc(new_bytes);
            memcpy((void*)new_buf, (void*)s.spheres, (size_t)(s.sphere_count * (i32)(sizeof(RTSphere) / 8)));
            ffree((u64)s.spheres);
            s.spheres = new_buf;
        };
        sphere_idx = s.sphere_count;
        s.spheres[sphere_idx].center  = center;
        s.spheres[sphere_idx].radius  = radius;
        s.spheres[sphere_idx].mat_idx = mat_idx;
        s.sphere_count++;

        bb_min = vec3(center.x - radius, center.y - radius, center.z - radius);
        bb_max = vec3(center.x + radius, center.y + radius, center.z + radius);
        rt_scene_push_prim(s, RT_PRIM_SPHERE, sphere_idx, bb_min, bb_max);

        return sphere_idx;
    };

    def rt_scene_add_triangle(RTScene* s, Vec3 a, Vec3 b, Vec3 c, RTMaterial mat) -> i32
    {
        RTTriangle* new_buf;
        size_t      new_bytes;
        i32         mat_idx, tri_idx;
        Vec3        ab, ac, normal, bb_min, bb_max;

        mat_idx = rt_scene_add_material(s, mat);

        if (s.tri_count >= s.tri_cap)
        {
            s.tri_cap = s.tri_cap * 2;
            new_bytes = (size_t)(s.tri_cap * (i32)(sizeof(RTTriangle) / 8));
            new_buf   = (RTTriangle*)fmalloc(new_bytes);
            memcpy((void*)new_buf, (void*)s.triangles, (size_t)(s.tri_count * (i32)(sizeof(RTTriangle) / 8)));
            ffree((u64)s.triangles);
            s.triangles = new_buf;
        };
        tri_idx = s.tri_count;

        ab     = vec3_sub(b, a);
        ac     = vec3_sub(c, a);
        normal = vec3_normalize(vec3_cross(ab, ac));

        s.triangles[tri_idx].a       = a;
        s.triangles[tri_idx].b       = b;
        s.triangles[tri_idx].c       = c;
        s.triangles[tri_idx].normal  = normal;
        s.triangles[tri_idx].mat_idx = mat_idx;
        s.tri_count++;

        bb_min = vec3(min(a.x, min(b.x, c.x)) - RT_EPSILON,
                      min(a.y, min(b.y, c.y)) - RT_EPSILON,
                      min(a.z, min(b.z, c.z)) - RT_EPSILON);
        bb_max = vec3(max(a.x, max(b.x, c.x)) + RT_EPSILON,
                      max(a.y, max(b.y, c.y)) + RT_EPSILON,
                      max(a.z, max(b.z, c.z)) + RT_EPSILON);
        rt_scene_push_prim(s, RT_PRIM_TRIANGLE, tri_idx, bb_min, bb_max);

        return tri_idx;
    };

    def rt_scene_add_plane(RTScene* s, Vec3 normal, float d, RTMaterial mat) -> i32
    {
        RTPlane* new_buf;
        size_t   new_bytes;
        i32      mat_idx, plane_idx;
        Vec3     bb_min, bb_max;

        mat_idx = rt_scene_add_material(s, mat);

        if (s.plane_count >= s.plane_cap)
        {
            s.plane_cap = s.plane_cap * 2;
            new_bytes   = (size_t)(s.plane_cap * (i32)(sizeof(RTPlane) / 8));
            new_buf     = (RTPlane*)fmalloc(new_bytes);
            memcpy((void*)new_buf, (void*)s.planes, (size_t)(s.plane_count * (i32)(sizeof(RTPlane) / 8)));
            ffree((u64)s.planes);
            s.planes = new_buf;
        };
        plane_idx = s.plane_count;
        s.planes[plane_idx].normal  = vec3_normalize(normal);
        s.planes[plane_idx].d       = d;
        s.planes[plane_idx].mat_idx = mat_idx;
        s.plane_count++;

        // Planes are infinite — give them a very large AABB
        bb_min = vec3(-RT_INF, -RT_INF, -RT_INF);
        bb_max = vec3( RT_INF,  RT_INF,  RT_INF);
        rt_scene_push_prim(s, RT_PRIM_PLANE, plane_idx, bb_min, bb_max);

        return plane_idx;
    };

    // ============================================================================
    // AABB INTERSECTION (slab method)
    // ============================================================================

    def rt_aabb_hit(Vec3 bb_min, Vec3 bb_max, RTRay* ray, float t_min, float t_max) -> bool
    {
        float inv, t0, t1, tmp;

        // X slab
        inv = 1.0 / ray.dir.x;
        t0  = (bb_min.x - ray.origin.x) * inv;
        t1  = (bb_max.x - ray.origin.x) * inv;
        if (inv < 0.0) { tmp = t0; t0 = t1; t1 = tmp; };
        if (t0 > t_min) { t_min = t0; };
        if (t1 < t_max) { t_max = t1; };
        if (t_max <= t_min) { return false; };

        // Y slab
        inv = 1.0 / ray.dir.y;
        t0  = (bb_min.y - ray.origin.y) * inv;
        t1  = (bb_max.y - ray.origin.y) * inv;
        if (inv < 0.0) { tmp = t0; t0 = t1; t1 = tmp; };
        if (t0 > t_min) { t_min = t0; };
        if (t1 < t_max) { t_max = t1; };
        if (t_max <= t_min) { return false; };

        // Z slab
        inv = 1.0 / ray.dir.z;
        t0  = (bb_min.z - ray.origin.z) * inv;
        t1  = (bb_max.z - ray.origin.z) * inv;
        if (inv < 0.0) { tmp = t0; t0 = t1; t1 = tmp; };
        if (t0 > t_min) { t_min = t0; };
        if (t1 < t_max) { t_max = t1; };
        if (t_max <= t_min) { return false; };

        return true;
    };

    // ============================================================================
    // PRIMITIVE INTERSECTION
    // ============================================================================

    def rt_sphere_hit(RTSphere* sp, RTRay* ray, float t_min, float t_max, RTHit* hit) -> bool
    {
        Vec3  oc;
        float a, half_b, c, discriminant, sqrtd, root;
        Vec3  outward_normal;
        float dot_result;

        oc      = vec3_sub(ray.origin, sp.center);
        a       = vec3_dot(ray.dir, ray.dir);
        half_b  = vec3_dot(oc, ray.dir);
        c       = vec3_dot(oc, oc) - sp.radius * sp.radius;

        discriminant = half_b * half_b - a * c;
        if (discriminant < 0.0) { return false; };

        sqrtd = sqrt(discriminant);
        root  = (-half_b - sqrtd) / a;

        if (root < t_min | root > t_max)
        {
            root = (-half_b + sqrtd) / a;
            if (root < t_min | root > t_max) { return false; };
        };

        hit.t        = root;
        hit.point    = vec3_add(ray.origin, vec3_mul(ray.dir, root));
        outward_normal = vec3_div(vec3_sub(hit.point, sp.center), sp.radius);

        dot_result = vec3_dot(ray.dir, outward_normal);
        hit.front  = dot_result < 0.0;
        hit.normal = hit.front ? outward_normal : vec3_negate(outward_normal);
        hit.mat_idx = sp.mat_idx;

        return true;
    };

    // Möller–Trumbore triangle intersection
    def rt_triangle_hit(RTTriangle* tri, RTRay* ray, float t_min, float t_max, RTHit* hit) -> bool
    {
        Vec3  ab, ac, h, s, q;
        float a, f, u, v, t;
        float dot_result;

        ab = vec3_sub(tri.b, tri.a);
        ac = vec3_sub(tri.c, tri.a);
        h  = vec3_cross(ray.dir, ac);
        a  = vec3_dot(ab, h);

        if (a > -RT_EPSILON & a < RT_EPSILON) { return false; };

        f = 1.0 / a;
        s = vec3_sub(ray.origin, tri.a);
        u = f * vec3_dot(s, h);

        if (u < 0.0 | u > 1.0) { return false; };

        q = vec3_cross(s, ab);
        v = f * vec3_dot(ray.dir, q);

        if (v < 0.0 | u + v > 1.0) { return false; };

        t = f * vec3_dot(ac, q);
        if (t < t_min | t > t_max) { return false; };

        hit.t       = t;
        hit.point   = vec3_add(ray.origin, vec3_mul(ray.dir, t));
        dot_result  = vec3_dot(ray.dir, tri.normal);
        hit.front   = dot_result < 0.0;
        hit.normal  = hit.front ? tri.normal : vec3_negate(tri.normal);
        hit.mat_idx = tri.mat_idx;

        return true;
    };

    def rt_plane_hit(RTPlane* pl, RTRay* ray, float t_min, float t_max, RTHit* hit) -> bool
    {
        float denom, t;
        float dot_result;

        denom = vec3_dot(pl.normal, ray.dir);
        if (abs(denom) < RT_EPSILON) { return false; };

        t = (pl.d - vec3_dot(pl.normal, ray.origin)) / denom;
        if (t < t_min | t > t_max) { return false; };

        hit.t       = t;
        hit.point   = vec3_add(ray.origin, vec3_mul(ray.dir, t));
        dot_result  = vec3_dot(ray.dir, pl.normal);
        hit.front   = dot_result < 0.0;
        hit.normal  = hit.front ? pl.normal : vec3_negate(pl.normal);
        hit.mat_idx = pl.mat_idx;

        return true;
    };

    // ============================================================================
    // BVH BUILD
    // ============================================================================

    // Returns centroid on axis 0=x, 1=y, 2=z
    def prim_centroid(RTPrimitive* p, i32 axis) -> float
    {
        if (axis == 0) { return (p.aabb_min.x + p.aabb_max.x) * 0.5; };
        if (axis == 1) { return (p.aabb_min.y + p.aabb_max.y) * 0.5; };
        return (p.aabb_min.z + p.aabb_max.z) * 0.5;
    };

    // Compute the AABB of a range of primitives
    def range_aabb(i32* order, RTPrimitive* prims, i32 start, i32 end, Vec3* out_min, Vec3* out_max) -> void
    {
        i32  i, idx;
        Vec3 mn, mx;

        idx = order[start];
        mn  = prims[idx].aabb_min;
        mx  = prims[idx].aabb_max;

        i = start + 1;
        while (i < end)
        {
            idx  = order[i];
            mn   = vec3_min(mn, prims[idx].aabb_min);
            mx   = vec3_max(mx, prims[idx].aabb_max);
            i++;
        };

        *out_min = mn;
        *out_max = mx;
    };

    // Partition order[start..end) around median centroid on given axis (insertion sort by centroid)
    def partition_by_axis(i32* order, RTPrimitive* prims, i32 start, i32 end, i32 axis) -> i32
    {
        i32   i, j, tmp;
        float ci, cj;

        // Insertion sort on centroids — adequate for small counts, BVH nodes stay small
        i = start + 1;
        while (i < end)
        {
            j  = i;
            ci = prim_centroid(@prims[order[i]], axis);
            while (j > start)
            {
                cj = prim_centroid(@prims[order[j - 1]], axis);
                if (cj <= ci) { break; };
                tmp        = order[j];
                order[j]   = order[j - 1];
                order[j-1] = tmp;
                j--;
            };
            i++;
        };

        return (start + end) / 2;
    };

    // Recursively build BVH nodes into the node array, return node index
    def bvh_build_recursive(RTScene* s, i32* order, i32 start, i32 end) -> i32
    {
        RTBVHNode* new_buf;
        size_t     new_bytes;
        i32        node_idx, count, axis, mid, left_idx, right_idx;
        Vec3       extent, mn, mx;
        RTBVHNode  node;

        count = end - start;

        // Grow node array if needed
        if (s.bvh_node_count >= s.prim_count * 2 + 8)
        {
            // Shouldn't happen with correct cap, but be safe
        };

        node_idx = s.bvh_node_count;
        s.bvh_node_count++;

        range_aabb(order, s.prims, start, end, @node.aabb_min, @node.aabb_max);

        if (count <= 4)
        {
            // Leaf
            node.left        = -1;
            node.right       = -1;
            node.prim_start  = start;
            node.prim_count  = count;
            s.bvh_nodes[node_idx] = node;
            return node_idx;
        };

        // Choose longest axis
        extent = vec3_sub(node.aabb_max, node.aabb_min);
        axis   = 0;
        if (extent.y > extent.x) { axis = 1; };
        if (extent.z > (axis == 0 ? extent.x : extent.y)) { axis = 2; };

        mid = partition_by_axis(order, s.prims, start, end, axis);

        // Ensure at least one prim on each side
        if (mid == start) { mid = start + 1; };
        if (mid == end)   { mid = end   - 1; };

        // Store node now (its children are filled in below)
        node.left       = -1;
        node.right      = -1;
        node.prim_start = 0;
        node.prim_count = 0;
        s.bvh_nodes[node_idx] = node;

        left_idx  = bvh_build_recursive(s, order, start, mid);
        right_idx = bvh_build_recursive(s, order, mid,   end);

        s.bvh_nodes[node_idx].left  = left_idx;
        s.bvh_nodes[node_idx].right = right_idx;

        return node_idx;
    };

    def bvh_build(RTScene* s) -> void
    {
        i32    i, node_cap;
        size_t order_bytes, node_bytes;

        if (s.prim_count == 0) { return; };

        // Free previous BVH if any
        if ((u64)s.bvh_nodes != (u64)0)
        {
            ffree((u64)s.bvh_nodes);
        };
        if ((u64)s.bvh_prim_order != (u64)0)
        {
            ffree((u64)s.bvh_prim_order);
        };

        order_bytes = (size_t)(s.prim_count * (i32)(sizeof(i32) / 8));
        s.bvh_prim_order = (i32*)fmalloc(order_bytes);

        i = 0;
        while (i < s.prim_count)
        {
            s.bvh_prim_order[i] = i;
            i++;
        };

        // 2*N-1 is the max BVH node count for N leaves
        node_cap     = s.prim_count * 2 + 8;
        node_bytes   = (size_t)(node_cap * (i32)(sizeof(RTBVHNode) / 8));
        s.bvh_nodes      = (RTBVHNode*)fmalloc(node_bytes);
        s.bvh_node_count = 0;

        bvh_build_recursive(s, s.bvh_prim_order, 0, s.prim_count);
    };

    // ============================================================================
    // SCENE INTERSECTION (BVH traversal)
    // ============================================================================

    def rt_prim_hit(RTScene* s, i32 prim_idx, RTRay* ray, float t_min, float t_max, RTHit* hit) -> bool
    {
        i32 kind, idx;
        kind = s.prims[prim_idx].kind;
        idx  = s.prims[prim_idx].idx;

        switch (kind)
        {
            case (RT_PRIM_SPHERE)
            {
                return rt_sphere_hit(@s.spheres[idx], ray, t_min, t_max, hit);
            }
            case (RT_PRIM_TRIANGLE)
            {
                return rt_triangle_hit(@s.triangles[idx], ray, t_min, t_max, hit);
            }
            case (RT_PRIM_PLANE)
            {
                return rt_plane_hit(@s.planes[idx], ray, t_min, t_max, hit);
            }
            default
            {
                return false;
            };
        };
        return false;
    };

    def rt_bvh_hit(RTScene* s, RTRay* ray, float t_min, float t_max, RTHit* hit) -> bool
    {
        // Iterative BVH traversal with an explicit stack
        // Stack holds node indices
        i32[64] node_stack;
        i32   stack_top, node_idx, i, prim_abs, leaf_end;
        bool  found, prim_hit_result;
        RTHit temp_hit;

        node_stack[0]  = 0;
        stack_top = 1;
        found     = false;

        while (stack_top > 0)
        {
            stack_top--;
            node_idx = node_stack[stack_top];

            if (!rt_aabb_hit(s.bvh_nodes[node_idx].aabb_min,
                             s.bvh_nodes[node_idx].aabb_max,
                             ray, t_min, t_max))
            {
                continue;
            };

            if (s.bvh_nodes[node_idx].prim_count > 0)
            {
                // Leaf — test all primitives
                i         = s.bvh_nodes[node_idx].prim_start;
                leaf_end  = i + s.bvh_nodes[node_idx].prim_count;
                while (i < leaf_end)
                {
                    prim_abs = s.bvh_prim_order[i];
                    prim_hit_result = rt_prim_hit(s, prim_abs, ray, t_min, t_max, @temp_hit);
                    if (prim_hit_result)
                    {
                        found   = true;
                        t_max   = temp_hit.t;
                        *hit    = temp_hit;
                    };
                    i++;
                };
            }
            else
            {
                // Internal node — push children
                if (stack_top < 62)
                {
                    node_stack[stack_top] = s.bvh_nodes[node_idx].left;
                    stack_top++;
                    node_stack[stack_top] = s.bvh_nodes[node_idx].right;
                    stack_top++;
                };
            };
        };

        return found;
    };

    // Linear fallback if BVH not built
    def rt_scene_hit_linear(RTScene* s, RTRay* ray, float t_min, float t_max, RTHit* hit) -> bool
    {
        bool  found;
        RTHit temp_hit;
        i32   i;

        found = false;
        i     = 0;
        while (i < s.prim_count)
        {
            if (rt_prim_hit(s, i, ray, t_min, t_max, @temp_hit))
            {
                found = true;
                t_max = temp_hit.t;
                *hit  = temp_hit;
            };
            i++;
        };
        return found;
    };

    def rt_scene_hit(RTScene* s, RTRay* ray, float t_min, float t_max, RTHit* hit) -> bool
    {
        if ((u64)s.bvh_nodes != (u64)0 & s.prim_count > 0)
        {
            return rt_bvh_hit(s, ray, t_min, t_max, hit);
        };
        return rt_scene_hit_linear(s, ray, t_min, t_max, hit);
    };

    // ============================================================================
    // RANDOM HELPERS (per-tile RNG state)
    // ============================================================================

    // Random float [0,1)
    def rt_randf(PCG32* rng) -> float
    {
        return random_float(rng);
    };

    // Random Vec3 with each component in [-1, 1)
    def rt_rand_vec3(PCG32* rng) -> Vec3
    {
        Vec3 v;
        v.x = random_range_float(rng, -1.0, 1.0);
        v.y = random_range_float(rng, -1.0, 1.0);
        v.z = random_range_float(rng, -1.0, 1.0);
        return v;
    };

    // Random Vec3 inside unit sphere (rejection)
    def rt_rand_in_unit_sphere(PCG32* rng) -> Vec3
    {
        Vec3 v;
        i32 guard;
        guard = 0;
        v     = rt_rand_vec3(rng);
        while (vec3_length_squared(v) >= 1.0 & guard < 32)
        {
            v = rt_rand_vec3(rng);
            guard++;
        };
        return v;
    };

    // Random unit Vec3 (on sphere surface)
    def rt_rand_unit_vec3(PCG32* rng) -> Vec3
    {
        return vec3_normalize(rt_rand_in_unit_sphere(rng));
    };

    // Random Vec3 in unit disk (for DoF lens sampling)
    def rt_rand_in_unit_disk(PCG32* rng) -> Vec3
    {
        Vec3 v;
        i32  guard;
        guard = 0;
        v.x = random_range_float(rng, -1.0, 1.0);
        v.y = random_range_float(rng, -1.0, 1.0);
        v.z = 0.0;
        while (v.x * v.x + v.y * v.y >= 1.0 & guard < 32)
        {
            v.x = random_range_float(rng, -1.0, 1.0);
            v.y = random_range_float(rng, -1.0, 1.0);
            guard++;
        };
        return v;
    };

    // ============================================================================
    // CAMERA
    // ============================================================================

    // vfov_deg: vertical field of view in degrees
    // aspect:   width / height
    // aperture: lens diameter (0 = pinhole, no DoF)
    // focus_dist: distance to the focus plane
    def rt_camera_init(RTCamera* cam,
                       Vec3  origin,
                       Vec3  look_at,
                       Vec3  up,
                       float vfov_deg,
                       float aspect,
                       float aperture,
                       float focus_dist) -> void
    {
        float theta, h, viewport_h, viewport_w;
        Vec3  w_vec, u_vec, v_vec;

        theta      = vfov_deg * RT_PI / 180.0;
        h          = tan(theta * 0.5);
        viewport_h = 2.0 * h;
        viewport_w = aspect * viewport_h;

        w_vec = vec3_normalize(vec3_sub(origin, look_at));
        u_vec = vec3_normalize(vec3_cross(up, w_vec));
        v_vec = vec3_cross(w_vec, u_vec);

        cam.origin     = origin;
        cam.w          = w_vec;
        cam.u          = u_vec;
        cam.v          = v_vec;
        cam.horizontal = vec3_mul(u_vec, focus_dist * viewport_w);
        cam.vertical   = vec3_mul(v_vec, focus_dist * viewport_h);
        cam.lower_left = vec3_sub(
                            vec3_sub(
                                vec3_sub(origin, vec3_mul(cam.horizontal, 0.5)),
                                vec3_mul(cam.vertical, 0.5)),
                            vec3_mul(w_vec, focus_dist));
        cam.lens_radius = aperture * 0.5;
        cam.focus_dist  = focus_dist;
    };

    def rt_camera_get_ray(RTCamera* cam, float s, float t, PCG32* rng) -> RTRay
    {
        RTRay ray;
        Vec3  rd, offset, origin;

        rd     = vec3_mul(rt_rand_in_unit_disk(rng), cam.lens_radius);
        offset = vec3_add(vec3_mul(cam.u, rd.x), vec3_mul(cam.v, rd.y));
        origin = vec3_add(cam.origin, offset);

        ray.origin = origin;
        ray.dir    = vec3_normalize(
                        vec3_sub(
                            vec3_add(
                                vec3_add(cam.lower_left,
                                         vec3_mul(cam.horizontal, s)),
                                vec3_mul(cam.vertical, t)),
                            origin));
        return ray;
    };

    // ============================================================================
    // VECTOR REFRACTION (Snell's law)
    // v must be unit length; n must be unit length; etai_over_etat = ni/nt
    // ============================================================================

    def vec3_refract(Vec3 v, Vec3 n, float etai_over_etat) -> Vec3
    {
        float cos_theta, sin2_theta, inv_sqrt;
        Vec3  r_out_perp, r_out_parallel, result;
        float cos_theta_neg, perp_len_sq, parallel_mag;

        cos_theta_neg = vec3_dot(v, n);
        if (cos_theta_neg > 0.0) { cos_theta = cos_theta_neg; }
        else                     { cos_theta = -cos_theta_neg; };

        // r_out_perp = etai_over_etat * (v + cos_theta * n)
        r_out_perp = vec3_mul(vec3_add(v, vec3_mul(n, cos_theta)), etai_over_etat);

        perp_len_sq   = vec3_length_squared(r_out_perp);
        parallel_mag  = 1.0 - perp_len_sq;
        if (parallel_mag < 0.0) { parallel_mag = 0.0; };
        parallel_mag  = -sqrt(parallel_mag);

        r_out_parallel = vec3_mul(n, parallel_mag);

        result = vec3_add(r_out_perp, r_out_parallel);
        return result;
    };

    // ============================================================================
    // SCHLICK FRESNEL APPROXIMATION (no pow — expanded to 5 multiplies)
    // ============================================================================

    def schlick(float cosine, float ref_idx) -> float
    {
        float r0, x, x2, x4;
        r0 = (1.0 - ref_idx) / (1.0 + ref_idx);
        r0 = r0 * r0;
        // (1 - cosine)^5 without pow()
        x  = 1.0 - cosine;
        x2 = x  * x;
        x4 = x2 * x2;
        return r0 + (1.0 - r0) * x4 * x;
    };

    // ============================================================================
    // MATERIAL SCATTER
    // Returns false for emissive (no scatter, sample emission instead)
    // ============================================================================

    def rt_scatter(RTMaterial* mat, RTRay* ray_in, RTHit* hit,
                   Vec3* attenuation, RTRay* scattered, PCG32* rng) -> bool
    {
        Vec3  reflected, refracted, scatter_dir, rand_disk;
        float ni_over_nt, cosine, reflect_prob, ref_val;
        bool  cannot_refract;
        RTRay s;

        switch (mat.kind)
        {
            case (RT_MAT_LAMBERTIAN)
            {
                scatter_dir = vec3_add(hit.normal, rt_rand_unit_vec3(rng));
                // Degenerate scatter guard
                if (vec3_length_squared(scatter_dir) < 0.000001)
                {
                    scatter_dir = hit.normal;
                };
                s.origin     = hit.point;
                s.dir        = vec3_normalize(scatter_dir);
                *scattered   = s;
                *attenuation = mat.albedo;
                return true;
            }
            case (RT_MAT_METAL)
            {
                reflected = vec3_reflect(ray_in.dir, hit.normal);
                reflected = vec3_add(reflected, vec3_mul(rt_rand_unit_vec3(rng), mat.fuzz));
                s.origin  = hit.point;
                s.dir     = vec3_normalize(reflected);
                *scattered   = s;
                *attenuation = mat.albedo;
                return vec3_dot(s.dir, hit.normal) > 0.0;
            }
            case (RT_MAT_DIELECTRIC)
            {
                *attenuation = vec3(1.0, 1.0, 1.0);

                ni_over_nt = hit.front ? (1.0 / mat.ior) : mat.ior;
                cosine     = -vec3_dot(ray_in.dir, hit.normal);
                if (cosine < 0.0) { cosine = 0.0; };

                // Snell's law — check for total internal reflection
                cannot_refract = ni_over_nt * ni_over_nt * (1.0 - cosine * cosine) > 1.0;
                reflect_prob   = schlick(cosine, ni_over_nt);

                if (cannot_refract | rt_randf(rng) < reflect_prob)
                {
                    reflected = vec3_reflect(ray_in.dir, hit.normal);
                    s.origin  = hit.point;
                    s.dir     = vec3_normalize(reflected);
                }
                else
                {
                    refracted = vec3_refract(ray_in.dir, hit.normal, ni_over_nt);
                    s.origin  = hit.point;
                    s.dir     = vec3_normalize(refracted);
                };

                *scattered = s;
                return true;
            }
            case (RT_MAT_EMISSIVE)
            {
                return false;
            }
            default
            {
                return false;
            };
        };
        return false;
    };

    // ============================================================================
    // PATH TRACER
    // ============================================================================

    // Trace one ray through the scene; returns HDR colour
    def rt_trace(RTScene* s, RTRay ray, i32 depth, PCG32* rng) -> Vec3
    {
        Vec3       colour, attenuation, emitted;
        RTHit      hit;
        RTRay      scattered;
        RTMaterial mat;
        bool       did_scatter;
        i32        bounce;
        float      sky_t;

        colour      = vec3(1.0, 1.0, 1.0);  // accumulated throughput
        attenuation = vec3(0.0, 0.0, 0.0);
        bounce      = 0;

        while (bounce < depth)
        {
            if (!rt_scene_hit(s, @ray, RT_EPSILON, RT_INF, @hit))
            {
                // Sky gradient: lerp white -> light blue
                sky_t  = 0.5 * (ray.dir.y + 1.0);
                colour = vec3_scale(colour,
                            vec3_add(
                                vec3_mul(vec3(1.0, 1.0, 1.0), 1.0 - sky_t),
                                vec3_mul(vec3(0.5, 0.7, 1.0), sky_t)));
                return colour;
            };

            mat = s.materials[hit.mat_idx];

            if (mat.kind == RT_MAT_EMISSIVE)
            {
                emitted = vec3_mul(mat.albedo, mat.emission);
                colour  = vec3_scale(colour, emitted);
                return colour;
            };

            did_scatter = rt_scatter(@mat, @ray, @hit, @attenuation, @scattered, rng);
            if (!did_scatter)
            {
                colour = vec3(0.0, 0.0, 0.0);
                return colour;
            };

            colour = vec3_scale(colour, attenuation);
            ray    = scattered;
            bounce++;
        };

        // Exceeded bounce depth — path absorbed
        return vec3(0.0, 0.0, 0.0);
    };

    // ============================================================================
    // TONE MAPPING
    // ============================================================================

    // Reinhard tone map: maps HDR [0,inf) -> [0,1)
    def rt_reinhard(Vec3 hdr) -> Vec3
    {
        Vec3 result;
        result.x = hdr.x / (hdr.x + 1.0);
        result.y = hdr.y / (hdr.y + 1.0);
        result.z = hdr.z / (hdr.z + 1.0);
        return result;
    };

    // Gamma correct (gamma 2.2 approximation via sqrt)
    def rt_gamma(Vec3 linear) -> Vec3
    {
        Vec3 result;
        result.x = sqrt(linear.x);
        result.y = sqrt(linear.y);
        result.z = sqrt(linear.z);
        return result;
    };

    // Pack normalised float RGB into 0xAARRGGBB u32
    def rt_pack_argb(Vec3 colour) -> u32
    {
        u32 r, g, b;
        r = (u32)(clamp(colour.x, 0.0, 1.0) * 255.0);
        g = (u32)(clamp(colour.y, 0.0, 1.0) * 255.0);
        b = (u32)(clamp(colour.z, 0.0, 1.0) * 255.0);
        return (u32)0xFF000000 | (r << 16) | (g << 8) | b;
    };

    // ============================================================================
    // RENDERER
    // ============================================================================

    // Render a single tile of the image.
    // tile_x, tile_y: tile origin in pixels
    // tw, th:         tile width/height (may be smaller at edges)
    // img_w, img_h:   full image dimensions
    // samples:        samples per pixel
    // depth:          max ray bounces
    def rt_render_tile(RTScene*   s,
                       RTCamera*  cam,
                       u32*       buf,
                       i32        tile_x, i32 tile_y,
                       i32        tw,     i32 th,
                       i32        img_w,  i32 img_h,
                       i32        samples,
                       i32        depth,
                       PCG32*     rng) -> void
    {
        i32    px, py, si, pixel_idx;
        float  u, v, inv_samp;
        Vec3   accum, sample_col, final_col;
        RTRay  ray;

        inv_samp = 1.0 / (float)samples;

        py = 0;
        while (py < th)
        {
            px = 0;
            while (px < tw)
            {
                accum.x = 0.0;
                accum.y = 0.0;
                accum.z = 0.0;

                si = 0;
                while (si < samples)
                {
                    u = ((float)(tile_x + px) + rt_randf(rng)) / (float)(img_w - 1);
                    v = ((float)(img_h - 1 - (tile_y + py)) + rt_randf(rng)) / (float)(img_h - 1);

                    ray        = rt_camera_get_ray(cam, u, v, rng);
                    sample_col = rt_trace(s, ray, depth, rng);
                    accum      = vec3_add(accum, sample_col);
                    si++;
                };

                // Average, tone map, gamma correct
                final_col = vec3_mul(accum, inv_samp);
                final_col = rt_reinhard(final_col);
                final_col = rt_gamma(final_col);

                pixel_idx = (tile_y + py) * img_w + (tile_x + px);
                buf[pixel_idx] = rt_pack_argb(final_col);
                px++;
            };
            py++;
        };
    };

    // Full-image render.  buf must be caller-allocated: width * height * sizeof(u32) bytes.
    // A fresh PCG32 is seeded per tile for reproducibility.
    def rt_render(RTScene*  s,
                  RTCamera* cam,
                  u32*      buf,
                  i32       width,
                  i32       height,
                  i32       samples,
                  i32       depth) -> void
    {
        i32   tx, ty, tw, th;
        u64   tile_seed;
        PCG32 rng;

        ty = 0;
        while (ty < height)
        {
            tx = 0;
            while (tx < width)
            {
                tw = width  - tx;
                th = height - ty;
                if (tw > RT_TILE_SIZE) { tw = RT_TILE_SIZE; };
                if (th > RT_TILE_SIZE) { th = RT_TILE_SIZE; };

                // Seed per tile for deterministic parallel-friendly output
                tile_seed = (u64)(ty * 65537 + tx * 131);
                pcg32_seed(@rng, tile_seed, (u64)(tx + 1));

                rt_render_tile(s, cam, buf, tx, ty, tw, th,
                               width, height, samples, depth, @rng);

                tx += RT_TILE_SIZE;
            };
            ty += RT_TILE_SIZE;
        };
    };

    // ============================================================================
    // PPM OUTPUT HELPER
    // ============================================================================

    // Write rendered buffer to a PPM file (for quick validation without a window)
    def rt_write_ppm(u32* buf, i32 width, i32 height, byte* path) -> bool
    {
        // Caller passes a path; uses file_object_raw to write
        // Returns true on success
        i32   i, r, g, b;
        u32   pixel;
        bool  ok;

        // Use ffifio for raw file output
        // We build the file content as raw byte writes
        // This requires file_object_raw.fx to be imported by the consumer
        // To keep this lib self-contained we declare the dependency here as a note
        // and provide the loop so the user can paste it into their write loop.
        // (file_object_raw brings in Windows/Linux IO deps which we do not force.)

        // NOT implemented here to avoid forced file IO dependency.
        // See rt_write_ppm_to_fd() in the usage notes.
        return false;
    };

};  // namespace raytracer

#endif;
