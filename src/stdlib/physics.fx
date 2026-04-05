// Author: Karac V. Thweatt
//
// physics.fx - Flux Physics Engine
//
// Combined rigid body and soft body physics for Flux.
//
// RIGID BODY:
//   - 3D rigid body dynamics (position, velocity, forces, torque)
//   - Sphere, AABB, and plane colliders
//   - Broadphase AABB overlap, impulse-based narrowphase resolution
//   - Restitution, Coulomb friction, split-impulse position correction
//   - Body sleeping to eliminate resting-contact energy drift
//
// SOFT BODY:
//   - Mass-spring simulation: particles + structural/shear/bend springs
//   - Constructors: rope (1D), cloth (2D grid), blob (3D lattice)
//   - Ground plane and rigid sphere collision per-particle
//   - Pin/unpin individual particles
//
// Usage:
//   #import "physics.fx";
//   using physics;
//
//   PhysWorld pw;  world_init(@pw, 64, 512);
//   SoftWorld sw;  softworld_init(@sw, 8);
//   softworld_set_ground(@sw, vec3(0,1,0), 0.0);
//   i32 cloth = softworld_add_cloth(@sw, pos, 10, 10, 0.4, 0.1, 0.98, 180.0, 1.5);
//   softworld_pin(@sw, cloth, 0);
//   softworld_step(@sw, 0.016);
//   world_step(@pw, 0.016, 6);
//   softworld_collide_rigid(@sw, @pw);
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

#ifndef FLUX_PHYSICS
#def FLUX_PHYSICS 1;

using standard::vectors;
using standard::math;
using standard::memory::allocators::stdheap;

// ============================================================================
// CONSTANTS  (use #def — const globals have a known zero-init bug)
// ============================================================================

#def PHYS_EPSILON       0.0001;
#def PHYS_BAUMGARTE     0.3;       // Position correction fraction (split impulse)
#def PHYS_SLOP          0.012;     // Penetration slop before correction fires
#def PHYS_MAX_BODIES    1024;
#def PHYS_MAX_CONTACTS  4096;
#def PHYS_COLLIDER_SPHERE  0;
#def PHYS_COLLIDER_AABB    1;
#def PHYS_COLLIDER_PLANE   2;
#def PHYS_SLEEP_LIN_SQ     0.002;  // linear velocity squared threshold for sleep
#def PHYS_SLEEP_ANG_SQ     0.002;  // angular velocity squared threshold for sleep
#def PHYS_SLEEP_FRAMES     30;     // consecutive quiet frames before sleeping

// ============================================================================
// STRUCTS
// ============================================================================

// Quaternion representing orientation (w + xi + yj + zk)
struct Quat
{
    float w, x, y, z;
};

// 3x3 inertia tensor (row-major)
struct Mat3
{
    float m00, m01, m02,
          m10, m11, m12,
          m20, m21, m22;
};

// Sphere collider: centre is body origin, radius in world units
struct SphereCollider
{
    float radius;
};

// Axis-aligned bounding box collider: half-extents from body centre
struct AABBCollider
{
    Vec3 half_extents;
};

// Infinite plane collider: normal + signed distance from world origin
struct PlaneCollider
{
    Vec3  normal;
    float dist;
};

// Tagged union collider
struct Collider
{
    i32          kind;        // PHYS_COLLIDER_SPHERE / _AABB / _PLANE
    SphereCollider sphere;
    AABBCollider   aabb;
    PlaneCollider  plane;
};

// A single rigid body
struct RigidBody
{
    // Linear state
    Vec3  position;
    Vec3  velocity;
    Vec3  force_accum;
    float inv_mass;           // 0 = static/infinite mass

    // Angular state
    Quat  orientation;
    Vec3  angular_velocity;
    Vec3  torque_accum;
    Mat3  inv_inertia_local;  // Inverse inertia tensor in body space

    // Material
    float restitution;        // Coefficient of restitution [0,1]
    float friction;           // Coulomb friction coefficient

    // Collider
    Collider collider;

    // Bookkeeping
    bool  active;
    bool  sleeping;
    i32   sleep_timer;  // frames below sleep threshold
    i32   id;
};

// A contact manifold produced by narrowphase
struct Contact
{
    i32   body_a, body_b;     // Indices into world body array
    Vec3  normal;             // Points from B toward A
    Vec3  point;              // World-space contact point
    float penetration;        // Positive = overlapping
    float restitution;        // Combined
    float friction;           // Combined
};

// The physics world
struct PhysWorld
{
    RigidBody* bodies;        // Heap-allocated array
    Contact*   contacts;      // Heap-allocated array
    i32        body_count,
               body_cap,
               contact_count,
               contact_cap;
    Vec3       gravity;
};

// ============================================================================
// QUATERNION HELPERS
// ============================================================================

namespace physics
{
    def quat_identity() -> Quat
    {
        Quat q;
        q.w = 1.0;
        q.x = 0.0;
        q.y = 0.0;
        q.z = 0.0;
        return q;
    };

    def quat_mul(Quat a, Quat b) -> Quat
    {
        Quat r;
        r.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
        r.x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y;
        r.y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x;
        r.z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w;
        return r;
    };

    // Integrate angular velocity into orientation over dt
    def quat_integrate(Quat* q, Vec3 omega, float dt) -> void
    {
        Quat dq;
        float half = dt * 0.5;
        dq.w = 0.0;
        dq.x = omega.x * half;
        dq.y = omega.y * half;
        dq.z = omega.z * half;

        Quat delta = quat_mul(dq, *q);
        q.w += delta.w;
        q.x += delta.x;
        q.y += delta.y;
        q.z += delta.z;

        // Renormalise
        float len = sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
        if (len > PHYS_EPSILON)
        {
            q.w = q.w / len;
            q.x = q.x / len;
            q.y = q.y / len;
            q.z = q.z / len;
        };
    };

    // Rotate a Vec3 by quaternion
    def quat_rotate(Quat q, Vec3 v) -> Vec3
    {
        // t = 2 * cross(q.xyz, v)
        // result = v + q.w * t + cross(q.xyz, t)
        Vec3  qv;
        qv.x = q.x;
        qv.y = q.y;
        qv.z = q.z;

        Vec3 t = vec3_mul(vec3_cross(qv, v), 2.0);
        Vec3 r = vec3_add(v, vec3_add(vec3_mul(t, q.w), vec3_cross(qv, t)));
        return r;
    };

    // Build rotation matrix from quaternion then multiply by vector (== quat_rotate)
    def quat_to_mat3(Quat q) -> Mat3
    {
        Mat3 m;
        float xx = q.x * q.x,
              yy = q.y * q.y,
              zz = q.z * q.z,
              xy = q.x * q.y,
              xz = q.x * q.z,
              yz = q.y * q.z,
              wx = q.w * q.x,
              wy = q.w * q.y,
              wz = q.w * q.z;

        m.m00 = 1.0 - 2.0 * (yy + zz);
        m.m01 = 2.0 * (xy - wz);
        m.m02 = 2.0 * (xz + wy);

        m.m10 = 2.0 * (xy + wz);
        m.m11 = 1.0 - 2.0 * (xx + zz);
        m.m12 = 2.0 * (yz - wx);

        m.m20 = 2.0 * (xz - wy);
        m.m21 = 2.0 * (yz + wx);
        m.m22 = 1.0 - 2.0 * (xx + yy);
        return m;
    };

    // ============================================================================
    // MAT3 HELPERS
    // ============================================================================

    def mat3_identity() -> Mat3
    {
        Mat3 m;
        m.m00 = 1.0; m.m01 = 0.0; m.m02 = 0.0;
        m.m10 = 0.0; m.m11 = 1.0; m.m12 = 0.0;
        m.m20 = 0.0; m.m21 = 0.0; m.m22 = 1.0;
        return m;
    };

    def mat3_mul_vec3(Mat3 m, Vec3 v) -> Vec3
    {
        Vec3 r;
        r.x = m.m00 * v.x + m.m01 * v.y + m.m02 * v.z;
        r.y = m.m10 * v.x + m.m11 * v.y + m.m12 * v.z;
        r.z = m.m20 * v.x + m.m21 * v.y + m.m22 * v.z;
        return r;
    };

    // Multiply two 3x3 matrices
    def mat3_mul(Mat3 a, Mat3 b) -> Mat3
    {
        Mat3 r;
        r.m00 = a.m00*b.m00 + a.m01*b.m10 + a.m02*b.m20;
        r.m01 = a.m00*b.m01 + a.m01*b.m11 + a.m02*b.m21;
        r.m02 = a.m00*b.m02 + a.m01*b.m12 + a.m02*b.m22;

        r.m10 = a.m10*b.m00 + a.m11*b.m10 + a.m12*b.m20;
        r.m11 = a.m10*b.m01 + a.m11*b.m11 + a.m12*b.m21;
        r.m12 = a.m10*b.m02 + a.m11*b.m12 + a.m12*b.m22;

        r.m20 = a.m20*b.m00 + a.m21*b.m10 + a.m22*b.m20;
        r.m21 = a.m20*b.m01 + a.m21*b.m11 + a.m22*b.m21;
        r.m22 = a.m20*b.m02 + a.m21*b.m12 + a.m22*b.m22;
        return r;
    };

    // Transpose
    def mat3_transpose(Mat3 m) -> Mat3
    {
        Mat3 r;
        r.m00 = m.m00; r.m01 = m.m10; r.m02 = m.m20;
        r.m10 = m.m01; r.m11 = m.m11; r.m12 = m.m21;
        r.m20 = m.m02; r.m21 = m.m12; r.m22 = m.m22;
        return r;
    };

    // Transform inverse inertia from body space to world space:
    // I_world_inv = R * I_body_inv * R^T
    def inertia_world(Mat3 rot, Mat3 inv_local) -> Mat3
    {
        return mat3_mul(mat3_mul(rot, inv_local), mat3_transpose(rot));
    };

    // ============================================================================
    // INERTIA TENSOR HELPERS
    // ============================================================================

    // Solid sphere: I = 2/5 * m * r^2 on diagonal
    def sphere_inertia_inv(float mass, float radius) -> Mat3
    {
        Mat3 m;
        float i;
        if (mass < PHYS_EPSILON)
        {
            // Static body — zero inverse inertia
            m.m00 = 0.0; m.m01 = 0.0; m.m02 = 0.0;
            m.m10 = 0.0; m.m11 = 0.0; m.m12 = 0.0;
            m.m20 = 0.0; m.m21 = 0.0; m.m22 = 0.0;
            return m;
        };
        i = 5.0 / (2.0 * mass * radius * radius);
        m.m00 = i;   m.m01 = 0.0; m.m02 = 0.0;
        m.m10 = 0.0; m.m11 = i;   m.m12 = 0.0;
        m.m20 = 0.0; m.m21 = 0.0; m.m22 = i;
        return m;
    };

    // Solid box: I_xx = 1/12 * m * (y^2 + z^2), etc.  half_extents passed in
    def box_inertia_inv(float mass, Vec3 half) -> Mat3
    {
        Mat3 m;
        float ix, iy, iz;
        float hx = half.x, hy = half.y, hz = half.z;
        if (mass < PHYS_EPSILON)
        {
            m.m00 = 0.0; m.m01 = 0.0; m.m02 = 0.0;
            m.m10 = 0.0; m.m11 = 0.0; m.m12 = 0.0;
            m.m20 = 0.0; m.m21 = 0.0; m.m22 = 0.0;
            return m;
        };
        // Full extents = 2 * half
        ix = 1.0 / (mass / 3.0 * (4.0 * hy * hy + 4.0 * hz * hz));
        iy = 1.0 / (mass / 3.0 * (4.0 * hx * hx + 4.0 * hz * hz));
        iz = 1.0 / (mass / 3.0 * (4.0 * hx * hx + 4.0 * hy * hy));
        m.m00 = ix;  m.m01 = 0.0; m.m02 = 0.0;
        m.m10 = 0.0; m.m11 = iy;  m.m12 = 0.0;
        m.m20 = 0.0; m.m21 = 0.0; m.m22 = iz;
        return m;
    };

    // ============================================================================
    // BODY INITIALISATION
    // ============================================================================

    def body_init_sphere(RigidBody* b, Vec3 pos, float radius, float mass) -> void
    {
        b.position         = pos;
        b.velocity         = vec3_zero();
        b.force_accum      = vec3_zero();
        b.angular_velocity = vec3_zero();
        b.torque_accum     = vec3_zero();
        b.orientation      = quat_identity();
        b.restitution      = 0.4;
        b.friction         = 0.5;
        b.active           = true;

        if (mass < PHYS_EPSILON)
        {
            b.inv_mass = 0.0;
        }
        else
        {
            b.inv_mass = 1.0 / mass;
        };

        b.sleeping     = false;
        b.sleep_timer  = 0;
        b.inv_inertia_local  = sphere_inertia_inv(mass, radius);
        b.collider.kind      = PHYS_COLLIDER_SPHERE;
        b.collider.sphere.radius = radius;
    };

    def body_init_aabb(RigidBody* b, Vec3 pos, Vec3 half_extents, float mass) -> void
    {
        b.position         = pos;
        b.velocity         = vec3_zero();
        b.force_accum      = vec3_zero();
        b.angular_velocity = vec3_zero();
        b.torque_accum     = vec3_zero();
        b.orientation      = quat_identity();
        b.restitution      = 0.3;
        b.friction         = 0.6;
        b.active           = true;

        if (mass < PHYS_EPSILON)
        {
            b.inv_mass = 0.0;
        }
        else
        {
            b.inv_mass = 1.0 / mass;
        };

        b.sleeping     = false;
        b.sleep_timer  = 0;
        b.inv_inertia_local        = box_inertia_inv(mass, half_extents);
        b.collider.kind            = PHYS_COLLIDER_AABB;
        b.collider.aabb.half_extents = half_extents;
    };

    def body_init_plane(RigidBody* b, Vec3 normal, float dist) -> void
    {
        b.position         = vec3_zero();
        b.velocity         = vec3_zero();
        b.force_accum      = vec3_zero();
        b.angular_velocity = vec3_zero();
        b.torque_accum     = vec3_zero();
        b.orientation      = quat_identity();
        b.restitution      = 0.3;
        b.friction         = 0.7;
        b.inv_mass         = 0.0;
        b.active           = true;

        b.sleeping     = false;
        b.sleep_timer  = 0;
        b.inv_inertia_local    = mat3_identity();
        b.collider.kind        = PHYS_COLLIDER_PLANE;
        b.collider.plane.normal = normal;
        b.collider.plane.dist   = dist;
    };

    // ============================================================================
    // AABB WORLD-SPACE BOUNDS (for broadphase)
    // ============================================================================

    // Returns the AABB world min/max for any body collider type
    def body_aabb_min(RigidBody* b) -> Vec3
    {
        Vec3 result;
        float r;
        if (b.collider.kind == PHYS_COLLIDER_SPHERE)
        {
            r = b.collider.sphere.radius;
            result.x = b.position.x - r;
            result.y = b.position.y - r;
            result.z = b.position.z - r;
            return result;
        };
        if (b.collider.kind == PHYS_COLLIDER_AABB)
        {
            result.x = b.position.x - b.collider.aabb.half_extents.x;
            result.y = b.position.y - b.collider.aabb.half_extents.y;
            result.z = b.position.z - b.collider.aabb.half_extents.z;
            return result;
        };
        // Plane: treated as infinite — return large negative values
        result.x = -1000000.0;
        result.y = -1000000.0;
        result.z = -1000000.0;
        return result;
    };

    def body_aabb_max(RigidBody* b) -> Vec3
    {
        Vec3 result;
        float r;
        if (b.collider.kind == PHYS_COLLIDER_SPHERE)
        {
            r = b.collider.sphere.radius;
            result.x = b.position.x + r;
            result.y = b.position.y + r;
            result.z = b.position.z + r;
            return result;
        };
        if (b.collider.kind == PHYS_COLLIDER_AABB)
        {
            result.x = b.position.x + b.collider.aabb.half_extents.x;
            result.y = b.position.y + b.collider.aabb.half_extents.y;
            result.z = b.position.z + b.collider.aabb.half_extents.z;
            return result;
        };
        result.x = 1000000.0;
        result.y = 1000000.0;
        result.z = 1000000.0;
        return result;
    };

    def aabb_overlap(Vec3 min_a, Vec3 max_a, Vec3 min_b, Vec3 max_b) -> bool
    {
        if (max_a.x < min_b.x | min_a.x > max_b.x) { return false; };
        if (max_a.y < min_b.y | min_a.y > max_b.y) { return false; };
        if (max_a.z < min_b.z | min_a.z > max_b.z) { return false; };
        return true;
    };

    // ============================================================================
    // NARROWPHASE: COLLISION DETECTION
    // ============================================================================

    // Sphere vs Sphere — returns true and fills contact if colliding
    def collide_sphere_sphere(RigidBody* a, RigidBody* b, Contact* c) -> bool
    {
        Vec3  delta;
        float dist_sq, dist, ra, rb, pen;
        ra = a.collider.sphere.radius;
        rb = b.collider.sphere.radius;

        delta   = vec3_sub(a.position, b.position);
        dist_sq = vec3_length_squared(delta);

        if (dist_sq >= (ra + rb) * (ra + rb))
        {
            return false;
        };

        dist = sqrt(dist_sq);

        if (dist < PHYS_EPSILON)
        {
            // Perfectly overlapping centres — push along y
            c.normal.x    = 0.0;
            c.normal.y    = 1.0;
            c.normal.z    = 0.0;
            c.penetration = ra + rb;
        }
        else
        {
            c.normal      = vec3_div(delta, dist);
            c.penetration = (ra + rb) - dist;
        };

        pen = c.penetration;
        c.point.x = b.position.x + c.normal.x * rb;
        c.point.y = b.position.y + c.normal.y * rb;
        c.point.z = b.position.z + c.normal.z * rb;

        c.restitution = (a.restitution + b.restitution) * 0.5;
        c.friction    = (a.friction    + b.friction)    * 0.5;
        return true;
    };

    // Sphere vs Plane
    def collide_sphere_plane(RigidBody* sphere_body, RigidBody* plane_body, Contact* c) -> bool
    {
        Vec3  n;
        float d, pen, r;
        n = plane_body.collider.plane.normal;
        d = plane_body.collider.plane.dist;
        r = sphere_body.collider.sphere.radius;

        // Signed distance from sphere centre to plane
        float signed_dist = vec3_dot(sphere_body.position, n) - d;

        if (signed_dist >= r) { return false; };

        pen = r - signed_dist;
        c.normal      = n;
        c.penetration = pen;
        c.point.x     = sphere_body.position.x - n.x * signed_dist;
        c.point.y     = sphere_body.position.y - n.y * signed_dist;
        c.point.z     = sphere_body.position.z - n.z * signed_dist;
        c.restitution = (sphere_body.restitution + plane_body.restitution) * 0.5;
        c.friction    = (sphere_body.friction    + plane_body.friction)    * 0.5;
        return true;
    };

    // AABB vs AABB  — SAT on 3 axes, pick minimum penetration axis as normal
    def collide_aabb_aabb(RigidBody* a, RigidBody* b, Contact* c) -> bool
    {
        Vec3  overlap;
        float ox, oy, oz, min_pen;
        float ax_min, ax_max, bx_min, bx_max;
        float ay_min, ay_max, by_min, by_max;
        float az_min, az_max, bz_min, bz_max;

        ax_min = a.position.x - a.collider.aabb.half_extents.x;
        ax_max = a.position.x + a.collider.aabb.half_extents.x;
        bx_min = b.position.x - b.collider.aabb.half_extents.x;
        bx_max = b.position.x + b.collider.aabb.half_extents.x;

        ay_min = a.position.y - a.collider.aabb.half_extents.y;
        ay_max = a.position.y + a.collider.aabb.half_extents.y;
        by_min = b.position.y - b.collider.aabb.half_extents.y;
        by_max = b.position.y + b.collider.aabb.half_extents.y;

        az_min = a.position.z - a.collider.aabb.half_extents.z;
        az_max = a.position.z + a.collider.aabb.half_extents.z;
        bz_min = b.position.z - b.collider.aabb.half_extents.z;
        bz_max = b.position.z + b.collider.aabb.half_extents.z;

        // X axis overlap
        float pen_x_pos = ax_max - bx_min;
        float pen_x_neg = bx_max - ax_min;
        if (pen_x_pos <= 0.0 | pen_x_neg <= 0.0) { return false; };

        // Y axis overlap
        float pen_y_pos = ay_max - by_min;
        float pen_y_neg = by_max - ay_min;
        if (pen_y_pos <= 0.0 | pen_y_neg <= 0.0) { return false; };

        // Z axis overlap
        float pen_z_pos = az_max - bz_min;
        float pen_z_neg = bz_max - az_min;
        if (pen_z_pos <= 0.0 | pen_z_neg <= 0.0) { return false; };

        // Pick smallest penetration axis
        float pen_x = pen_x_pos < pen_x_neg ? pen_x_pos : pen_x_neg;
        float pen_y = pen_y_pos < pen_y_neg ? pen_y_pos : pen_y_neg;
        float pen_z = pen_z_pos < pen_z_neg ? pen_z_pos : pen_z_neg;

        // Normal direction sign
        float sign_x = pen_x_pos < pen_x_neg ? 1.0 : -1.0;
        float sign_y = pen_y_pos < pen_y_neg ? 1.0 : -1.0;
        float sign_z = pen_z_pos < pen_z_neg ? 1.0 : -1.0;

        if (pen_x <= pen_y & pen_x <= pen_z)
        {
            c.normal.x    = sign_x;
            c.normal.y    = 0.0;
            c.normal.z    = 0.0;
            c.penetration = pen_x;
        }
        elif (pen_y <= pen_x & pen_y <= pen_z)
        {
            c.normal.x    = 0.0;
            c.normal.y    = sign_y;
            c.normal.z    = 0.0;
            c.penetration = pen_y;
        }
        else
        {
            c.normal.x    = 0.0;
            c.normal.y    = 0.0;
            c.normal.z    = sign_z;
            c.penetration = pen_z;
        };

        // Contact point: midpoint of overlap centres
        c.point.x = (a.position.x + b.position.x) * 0.5;
        c.point.y = (a.position.y + b.position.y) * 0.5;
        c.point.z = (a.position.z + b.position.z) * 0.5;

        c.restitution = (a.restitution + b.restitution) * 0.5;
        c.friction    = (a.friction    + b.friction)    * 0.5;
        return true;
    };

    // Sphere vs AABB — find closest point on AABB to sphere centre
    def collide_sphere_aabb(RigidBody* sphere_body, RigidBody* aabb_body, Contact* c) -> bool
    {
        Vec3  closest, delta;
        float ax_min, ax_max, ay_min, ay_max, az_min, az_max;
        float dist_sq, dist, r, pen;

        r = sphere_body.collider.sphere.radius;

        ax_min = aabb_body.position.x - aabb_body.collider.aabb.half_extents.x;
        ax_max = aabb_body.position.x + aabb_body.collider.aabb.half_extents.x;
        ay_min = aabb_body.position.y - aabb_body.collider.aabb.half_extents.y;
        ay_max = aabb_body.position.y + aabb_body.collider.aabb.half_extents.y;
        az_min = aabb_body.position.z - aabb_body.collider.aabb.half_extents.z;
        az_max = aabb_body.position.z + aabb_body.collider.aabb.half_extents.z;

        closest.x = clamp(sphere_body.position.x, ax_min, ax_max);
        closest.y = clamp(sphere_body.position.y, ay_min, ay_max);
        closest.z = clamp(sphere_body.position.z, az_min, az_max);

        delta   = vec3_sub(sphere_body.position, closest);
        dist_sq = vec3_length_squared(delta);

        if (dist_sq >= r * r) { return false; };

        dist = sqrt(dist_sq);

        if (dist < PHYS_EPSILON)
        {
            c.normal.x    = 0.0;
            c.normal.y    = 1.0;
            c.normal.z    = 0.0;
            c.penetration = r;
        }
        else
        {
            c.normal      = vec3_div(delta, dist);
            c.penetration = r - dist;
        };

        c.point       = closest;
        c.restitution = (sphere_body.restitution + aabb_body.restitution) * 0.5;
        c.friction    = (sphere_body.friction    + aabb_body.friction)    * 0.5;
        return true;
    };

    // Dispatch narrowphase for any collider pair combination
    def collide_bodies(RigidBody* a, RigidBody* b, Contact* c) -> bool
    {
        i32 ka, kb;
        ka = a.collider.kind;
        kb = b.collider.kind;

        c.body_a = a.id;
        c.body_b = b.id;

        // Sphere-Sphere
        if (ka == PHYS_COLLIDER_SPHERE & kb == PHYS_COLLIDER_SPHERE)
        {
            return collide_sphere_sphere(a, b, c);
        };

        // Sphere-Plane (either order)
        if (ka == PHYS_COLLIDER_SPHERE & kb == PHYS_COLLIDER_PLANE)
        {
            return collide_sphere_plane(a, b, c);
        };
        if (ka == PHYS_COLLIDER_PLANE & kb == PHYS_COLLIDER_SPHERE)
        {
            bool hit = collide_sphere_plane(b, a, c);
            // Flip normal so it still points from B toward A
            c.normal = vec3_negate(c.normal);
            c.body_a = a.id;
            c.body_b = b.id;
            return hit;
        };

        // AABB-AABB
        if (ka == PHYS_COLLIDER_AABB & kb == PHYS_COLLIDER_AABB)
        {
            return collide_aabb_aabb(a, b, c);
        };

        // Sphere-AABB (either order)
        if (ka == PHYS_COLLIDER_SPHERE & kb == PHYS_COLLIDER_AABB)
        {
            return collide_sphere_aabb(a, b, c);
        };
        if (ka == PHYS_COLLIDER_AABB & kb == PHYS_COLLIDER_SPHERE)
        {
            bool hit = collide_sphere_aabb(b, a, c);
            c.normal = vec3_negate(c.normal);
            c.body_a = a.id;
            c.body_b = b.id;
            return hit;
        };

        // AABB-Plane (either order) — treat AABB vs plane as sphere vs plane
        // using the half-extent in the plane-normal direction as a pseudo-radius
        if (ka == PHYS_COLLIDER_AABB & kb == PHYS_COLLIDER_PLANE)
        {
            Vec3  n    = b.collider.plane.normal;
            float d    = b.collider.plane.dist;
            float proj = abs(n.x * a.collider.aabb.half_extents.x)
                       + abs(n.y * a.collider.aabb.half_extents.y)
                       + abs(n.z * a.collider.aabb.half_extents.z);
            float signed_dist = vec3_dot(a.position, n) - d;
            if (signed_dist >= proj) { return false; };
            c.normal      = n;
            c.penetration = proj - signed_dist;
            c.point.x     = a.position.x - n.x * signed_dist;
            c.point.y     = a.position.y - n.y * signed_dist;
            c.point.z     = a.position.z - n.z * signed_dist;
            c.restitution = (a.restitution + b.restitution) * 0.5;
            c.friction    = (a.friction    + b.friction)    * 0.5;
            return true;
        };
        if (ka == PHYS_COLLIDER_PLANE & kb == PHYS_COLLIDER_AABB)
        {
            Vec3  n    = a.collider.plane.normal;
            float d    = a.collider.plane.dist;
            float proj = abs(n.x * b.collider.aabb.half_extents.x)
                       + abs(n.y * b.collider.aabb.half_extents.y)
                       + abs(n.z * b.collider.aabb.half_extents.z);
            float signed_dist = vec3_dot(b.position, n) - d;
            if (signed_dist >= proj) { return false; };
            c.normal.x    = -n.x;
            c.normal.y    = -n.y;
            c.normal.z    = -n.z;
            c.penetration = proj - signed_dist;
            c.point.x     = b.position.x - n.x * signed_dist;
            c.point.y     = b.position.y - n.y * signed_dist;
            c.point.z     = b.position.z - n.z * signed_dist;
            c.restitution = (a.restitution + b.restitution) * 0.5;
            c.friction    = (a.friction    + b.friction)    * 0.5;
            return true;
        };

        return false;
    };

    // ============================================================================
    // IMPULSE-BASED COLLISION RESPONSE
    // ============================================================================

    def resolve_contact(RigidBody* a, RigidBody* b, Contact* c) -> void
    {
        float e, jt, mu, jt_abs, j_abs, sign_jt;
        Vec3  friction_impulse;
        // World-space inverse inertia tensors
        Mat3 rot_a    = quat_to_mat3(a.orientation);
        Mat3 rot_b    = quat_to_mat3(b.orientation);
        Mat3 iia      = inertia_world(rot_a, a.inv_inertia_local);
        Mat3 iib      = inertia_world(rot_b, b.inv_inertia_local);

        // Vectors from body centres to contact point
        Vec3 ra = vec3_sub(c.point, a.position);
        Vec3 rb = vec3_sub(c.point, b.position);

        // Relative velocity at contact point
        Vec3 va_contact = vec3_add(a.velocity, vec3_cross(a.angular_velocity, ra));
        Vec3 vb_contact = vec3_add(b.velocity, vec3_cross(b.angular_velocity, rb));
        Vec3 rel_vel    = vec3_sub(va_contact, vb_contact);

        float vel_along_normal = vec3_dot(rel_vel, c.normal);

        // Do not resolve if separating
        if (vel_along_normal > 0.0) { return; };

        // Angular contribution to effective mass along normal
        Vec3 ra_cross_n   = vec3_cross(ra, c.normal);
        Vec3 rb_cross_n   = vec3_cross(rb, c.normal);
        Vec3 iia_ra       = mat3_mul_vec3(iia, ra_cross_n);
        Vec3 iib_rb       = mat3_mul_vec3(iib, rb_cross_n);

        float ang_a = vec3_dot(vec3_cross(iia_ra, ra), c.normal);
        float ang_b = vec3_dot(vec3_cross(iib_rb, rb), c.normal);

        float inv_mass_sum = a.inv_mass + b.inv_mass + ang_a + ang_b;

        if (inv_mass_sum < PHYS_EPSILON) { return; };

        // Only apply restitution on impacts fast enough to matter.
        if (vel_along_normal < -0.5)
        {
            e = c.restitution;
        };

        // Impulse magnitude. Clamp >= 0: never pull bodies together.
        float j = -(1.0 + e) * vel_along_normal / inv_mass_sum;
        if (j < 0.0) { j = 0.0; };

        Vec3 impulse = vec3_mul(c.normal, j);

        // Apply linear impulse
        a.velocity = vec3_add(a.velocity, vec3_mul(impulse, a.inv_mass));
        b.velocity = vec3_sub(b.velocity, vec3_mul(impulse, b.inv_mass));

        // Apply angular impulse
        a.angular_velocity = vec3_add(a.angular_velocity, mat3_mul_vec3(iia, vec3_cross(ra, impulse)));
        b.angular_velocity = vec3_sub(b.angular_velocity, mat3_mul_vec3(iib, vec3_cross(rb, impulse)));

        // ---- Friction impulse ----
        // Tangent direction = relative velocity minus normal component
        Vec3 rel_vel2    = vec3_sub(vec3_add(a.velocity, vec3_cross(a.angular_velocity, ra)),
                                    vec3_add(b.velocity, vec3_cross(b.angular_velocity, rb)));
        float rv_dot_n   = vec3_dot(rel_vel2, c.normal);
        Vec3 tangent     = vec3_sub(rel_vel2, vec3_mul(c.normal, rv_dot_n));
        float tang_len   = vec3_length(tangent);

        if (tang_len > PHYS_EPSILON)
        {
            tangent = vec3_div(tangent, tang_len);

            Vec3 ra_cross_t    = vec3_cross(ra, tangent);
            Vec3 rb_cross_t    = vec3_cross(rb, tangent);
            Vec3 iia_rat       = mat3_mul_vec3(iia, ra_cross_t);
            Vec3 iib_rbt       = mat3_mul_vec3(iib, rb_cross_t);
            float ang_a_t      = vec3_dot(vec3_cross(iia_rat, ra), tangent);
            float ang_b_t      = vec3_dot(vec3_cross(iib_rbt, rb), tangent);
            float inv_mass_t   = a.inv_mass + b.inv_mass + ang_a_t + ang_b_t;

            if (inv_mass_t > PHYS_EPSILON)
            {
                jt = -vec3_dot(rel_vel2, tangent) / inv_mass_t;

                // Coulomb cone: clamp to mu * j
                mu      = c.friction;
                jt_abs  = abs(jt);
                j_abs   = abs(j);

                if (jt_abs < j_abs * mu)
                {
                    friction_impulse = vec3_mul(tangent, jt);
                }
                else
                {
                    sign_jt = jt > 0.0 ? 1.0 : -1.0;
                    friction_impulse = vec3_mul(tangent, sign_jt * j_abs * mu);
                };

                a.velocity = vec3_add(a.velocity, vec3_mul(friction_impulse, a.inv_mass));
                b.velocity = vec3_sub(b.velocity, vec3_mul(friction_impulse, b.inv_mass));
                a.angular_velocity = vec3_add(a.angular_velocity, mat3_mul_vec3(iia, vec3_cross(ra, friction_impulse)));
                b.angular_velocity = vec3_sub(b.angular_velocity, mat3_mul_vec3(iib, vec3_cross(rb, friction_impulse)));
            };
        };
    };


    // ============================================================================
    // POSITIONAL CORRECTION (SPLIT IMPULSE)
    // Moves positions only - never touches velocity, so no energy is injected.
    // Only fires above PHYS_SLOP to ignore float-noise resting contact.
    // ============================================================================

    def positional_correction(RigidBody* a, RigidBody* b, Contact* c) -> void
    {
        float pen, inv_sum, corr;
        Vec3  correction;

        pen = c.penetration - PHYS_SLOP;
        if (pen <= 0.0) { return; };

        inv_sum = a.inv_mass + b.inv_mass;
        if (inv_sum < PHYS_EPSILON) { return; };

        corr = (pen / inv_sum) * PHYS_BAUMGARTE;
        correction = vec3_mul(c.normal, corr);

        // Move positions proportional to inverse mass.
        // Skip sleeping bodies - they don't move.
        if (!a.sleeping) { a.position = vec3_add(a.position, vec3_mul(correction, a.inv_mass)); };
        if (!b.sleeping) { b.position = vec3_sub(b.position, vec3_mul(correction, b.inv_mass)); };
    };

    // ============================================================================
    // WORLD: INTEGRATION
    // ============================================================================

    def integrate_body(RigidBody* b, Vec3 gravity, float dt) -> void
    {
        // Skip static or sleeping bodies
        if (b.inv_mass < PHYS_EPSILON) { return; };
        if (b.sleeping) { return; };

        // Gravity as acceleration (F = m*a => a = F/m = F * inv_m)
        Vec3 accel = vec3_mul(gravity, 1.0);   // gravity is already acceleration
        Vec3 force_accel = vec3_mul(b.force_accum, b.inv_mass);
        accel = vec3_add(accel, force_accel);

        // Semi-implicit Euler
        b.velocity  = vec3_add(b.velocity,  vec3_mul(accel, dt));
        b.position  = vec3_add(b.position,  vec3_mul(b.velocity, dt));

        // Angular integration
        Vec3 alpha = mat3_mul_vec3(
            inertia_world(quat_to_mat3(b.orientation), b.inv_inertia_local),
            b.torque_accum
        );
        b.angular_velocity = vec3_add(b.angular_velocity, vec3_mul(alpha, dt));
        quat_integrate(@b.orientation, b.angular_velocity, dt);

        // Clear accumulators
        b.force_accum  = vec3_zero();
        b.torque_accum = vec3_zero();
    };

    // ============================================================================
    // WORLD API
    // ============================================================================

    def world_init(PhysWorld* w, i32 body_cap, i32 contact_cap) -> void
    {
        size_t body_bytes    = (size_t)(body_cap    * (i32)(sizeof(RigidBody) / 8));
        size_t contact_bytes = (size_t)(contact_cap * (i32)(sizeof(Contact)   / 8));

        w.bodies       = (RigidBody*)stdheap::fmalloc(body_bytes);
        w.contacts     = (Contact*)stdheap::fmalloc(contact_bytes);
        w.body_count   = 0;
        w.body_cap     = body_cap;
        w.contact_count = 0;
        w.contact_cap  = contact_cap;
        w.gravity.x    = 0.0;
        w.gravity.y    = -9.81;
        w.gravity.z    = 0.0;
    };

    def world_destroy(PhysWorld* w) -> void
    {
        stdheap::ffree((u64)w.bodies);
        stdheap::ffree((u64)w.contacts);
        w.bodies       = (RigidBody*)0;
        w.contacts     = (Contact*)0;
        w.body_count   = 0;
        w.contact_count = 0;
    };

    def world_set_gravity(PhysWorld* w, Vec3 g) -> void
    {
        w.gravity = g;
    };

    // Add a sphere body; returns its index, or -1 on failure
    def world_add_sphere(PhysWorld* w, Vec3 pos, float radius, float mass) -> i32
    {
        i32 idx;
        if (w.body_count >= w.body_cap) { return -1; };
        idx = w.body_count;
        w.body_count++;
        RigidBody* b = @w.bodies[idx];
        body_init_sphere(b, pos, radius, mass);
        b.id = idx;
        return idx;
    };

    // Add an AABB body; returns its index, or -1 on failure
    def world_add_aabb(PhysWorld* w, Vec3 pos, Vec3 half_extents, float mass) -> i32
    {
        i32 idx;
        if (w.body_count >= w.body_cap) { return -1; };
        idx = w.body_count;
        w.body_count++;
        RigidBody* b = @w.bodies[idx];
        body_init_aabb(b, pos, half_extents, mass);
        b.id = idx;
        return idx;
    };

    // Add an infinite plane; returns its index, or -1 on failure
    def world_add_plane(PhysWorld* w, Vec3 normal, float dist) -> i32
    {
        i32 idx;
        if (w.body_count >= w.body_cap) { return -1; };
        idx = w.body_count;
        w.body_count++;
        RigidBody* b = @w.bodies[idx];
        body_init_plane(b, normal, dist);
        b.id = idx;
        return idx;
    };

    // Get pointer to body by index
    def world_get_body(PhysWorld* w, i32 idx) -> RigidBody*
    {
        if (idx < 0 | idx >= w.body_count) { return (RigidBody*)0; };
        return @w.bodies[idx];
    };

    // Apply a force to a body (accumulates until next step)
    def world_apply_force(PhysWorld* w, i32 idx, Vec3 force) -> void
    {
        RigidBody* b;
        if (idx < 0 | idx >= w.body_count) { return; };
        b = @w.bodies[idx];
        b.force_accum = vec3_add(b.force_accum, force);
    };

    // Apply torque to a body
    def world_apply_torque(PhysWorld* w, i32 idx, Vec3 torque) -> void
    {
        RigidBody* b;
        if (idx < 0 | idx >= w.body_count) { return; };
        b = @w.bodies[idx];
        b.torque_accum = vec3_add(b.torque_accum, torque);
    };

    // Apply an impulse at a world-space point (bypasses accumulator — immediate)
    def world_apply_impulse_at(PhysWorld* w, i32 idx, Vec3 impulse, Vec3 point) -> void
    {
        RigidBody* b;
        Mat3       rot, iia;
        Vec3       r;

        if (idx < 0 | idx >= w.body_count) { return; };
        b = @w.bodies[idx];
        if (b.inv_mass < PHYS_EPSILON) { return; };

        rot = quat_to_mat3(b.orientation);
        iia = inertia_world(rot, b.inv_inertia_local);
        r   = vec3_sub(point, b.position);

        b.velocity         = vec3_add(b.velocity,         vec3_mul(impulse, b.inv_mass));
        b.angular_velocity = vec3_add(b.angular_velocity, mat3_mul_vec3(iia, vec3_cross(r, impulse)));
    };

    // Set material properties for a body
    def world_set_material(PhysWorld* w, i32 idx, float restitution, float friction) -> void
    {
        RigidBody* b;
        if (idx < 0 | idx >= w.body_count) { return; };
        b = @w.bodies[idx];
        b.restitution = restitution;
        b.friction    = friction;
    };

    // One physics tick
    // iteration_count: number of impulse solver passes (higher = more stable)
    def world_step(PhysWorld* w, float dt, i32 iteration_count) -> void
    {
        i32      i, j, k, ci;
        RigidBody* ba;
        RigidBody* bb;
        Contact    tmp_contact;
        Vec3 min_a, max_a, min_b, max_b;
        float lin_sq, ang_sq;

        // 1. Integrate forces and update transforms
        for (i = 0; i < w.body_count; i++)
        {
            integrate_body(@w.bodies[i], w.gravity, dt);
        };

        // 2. Broadphase + narrowphase: build contact list
        w.contact_count = 0;
        for (i = 0; i < w.body_count; i++)
        {
            ba = @w.bodies[i];
            if (!ba.active) { continue; };
            min_a = body_aabb_min(ba);
            max_a = body_aabb_max(ba);

            for (j = i + 1; j < w.body_count; j++)
            {
                bb = @w.bodies[j];
                if (!bb.active) { continue; };

                // Skip two static bodies
                if (ba.inv_mass < PHYS_EPSILON & bb.inv_mass < PHYS_EPSILON) { continue; };

                // Broadphase
                min_b = body_aabb_min(bb);
                max_b = body_aabb_max(bb);
                if (!aabb_overlap(min_a, max_a, min_b, max_b)) { continue; };

                // Narrowphase
                if (w.contact_count >= w.contact_cap) { break; };
                if (collide_bodies(ba, bb, @w.contacts[w.contact_count]))
                {
                    w.contact_count++;
                };
            };
        };

        // 3. Resolve contacts (multiple passes)
        for (k = 0; k < iteration_count; k++)
        {
            for (ci = 0; ci < w.contact_count; ci++)
            {
                Contact* contact = @w.contacts[ci];
                RigidBody* ra    = @w.bodies[contact.body_a];
                RigidBody* rb    = @w.bodies[contact.body_b];
                // Skip if the dynamic body in this contact is sleeping
                if (ra.sleeping & ra.inv_mass > PHYS_EPSILON) { continue; };
                if (rb.sleeping & rb.inv_mass > PHYS_EPSILON) { continue; };
                resolve_contact(ra, rb, contact);
            };
        };

        // 4. Positional correction.
        // Plane contacts: hard clamp position exactly out of the plane. No Baumgarte.
        // Dynamic-dynamic: Baumgarte for significant penetration only.
        for (ci = 0; ci < w.contact_count; ci++)
        {
            Contact* contact = @w.contacts[ci];
            RigidBody* ra    = @w.bodies[contact.body_a];
            RigidBody* rb    = @w.bodies[contact.body_b];
            if (ra.sleeping & ra.inv_mass > PHYS_EPSILON) { continue; };
            if (rb.sleeping & rb.inv_mass > PHYS_EPSILON) { continue; };

            if (ra.collider.kind == PHYS_COLLIDER_PLANE | rb.collider.kind == PHYS_COLLIDER_PLANE)
            {
                if (contact.penetration > 0.0)
                {
                    if (ra.inv_mass > PHYS_EPSILON)
                    {
                        ra.position.x += contact.normal.x * contact.penetration;
                        ra.position.y += contact.normal.y * contact.penetration;
                        ra.position.z += contact.normal.z * contact.penetration;
                    };
                    if (rb.inv_mass > PHYS_EPSILON)
                    {
                        rb.position.x -= contact.normal.x * contact.penetration;
                        rb.position.y -= contact.normal.y * contact.penetration;
                        rb.position.z -= contact.normal.z * contact.penetration;
                    };
                };
            }
            else
            {
                positional_correction(ra, rb, contact);
            };
        };

        // 5. Wake sleeping bodies that are in contact with a moving body
        for (ci = 0; ci < w.contact_count; ci++)
        {
            Contact* contact = @w.contacts[ci];
            RigidBody* ra    = @w.bodies[contact.body_a];
            RigidBody* rb    = @w.bodies[contact.body_b];
            if (ra.sleeping & rb.inv_mass > PHYS_EPSILON & !rb.sleeping)
            {
                ra.sleeping    = false;
                ra.sleep_timer = 0;
            };
            if (rb.sleeping & ra.inv_mass > PHYS_EPSILON & !ra.sleeping)
            {
                rb.sleeping    = false;
                rb.sleep_timer = 0;
            };
        };

        // 6. Sleep check pass
        for (i = 0; i < w.body_count; i++)
        {
            ba = @w.bodies[i];
            if (ba.inv_mass < PHYS_EPSILON | ba.sleeping) { continue; };

            lin_sq = vec3_length_squared(ba.velocity);
            ang_sq = vec3_length_squared(ba.angular_velocity);

            if (lin_sq < PHYS_SLEEP_LIN_SQ & ang_sq < PHYS_SLEEP_ANG_SQ)
            {
                ba.sleep_timer++;
                if (ba.sleep_timer >= PHYS_SLEEP_FRAMES)
                {
                    ba.sleeping         = true;
                    ba.velocity         = vec3_zero();
                    ba.angular_velocity = vec3_zero();
                };
            }
            else
            {
                ba.sleep_timer = 0;
            };
        };
    };
};


// ============================================================================
// SOFT BODY PHYSICS
// ============================================================================

// ============================================================================
// CONSTANTS
// ============================================================================

#def SOFT_SPRING_STRUCTURAL  0;
#def SOFT_SPRING_SHEAR       1;
#def SOFT_SPRING_BEND        2;
#def SOFT_EPSILON            0.0001;
#def SOFT_GROUND_RESTITUTION 0.2;
#def SOFT_GROUND_FRICTION    0.6;

// ============================================================================
// STRUCTS
// ============================================================================

// A single mass point
struct SoftParticle
{
    Vec3  position;
    Vec3  velocity;
    Vec3  force_accum;
    float inv_mass;       // 0 = pinned (infinite mass, immovable)
    float damping;        // linear velocity damping [0,1] applied each step
};

// A spring connecting two particles
struct SoftSpring
{
    i32   a, b;           // particle indices
    float rest_length;    // natural length
    float stiffness;      // spring constant k (N/m)
    float damping;        // spring damping coefficient
    i32   kind;           // SOFT_SPRING_STRUCTURAL / _SHEAR / _BEND
};

// A soft body: owns its particle and spring arrays on the heap
struct SoftBody
{
    SoftParticle* particles;
    SoftSpring*   springs;
    i32           particle_count,
                  particle_cap,
                  spring_count,
                  spring_cap;
    bool          active;
    i32           id;
};

// The soft body world
struct SoftWorld
{
    SoftBody* bodies;
    i32       body_count,
              body_cap;
    Vec3      gravity;
    // Ground plane (matches PhysWorld convention: normal=(0,1,0), dist=0)
    Vec3      ground_normal;
    float     ground_dist;
    bool      has_ground;
};

// ============================================================================
// SOFTBODY INTERNAL HELPERS
// ============================================================================

namespace physics
{
    // Allocate a SoftBody with given particle and spring capacities
    def softbody_alloc(SoftBody* sb, i32 pcap, i32 scap) -> void
    {
        size_t pbytes = (size_t)(pcap * (i32)(sizeof(SoftParticle) / 8));
        size_t sbytes = (size_t)(scap * (i32)(sizeof(SoftSpring)   / 8));
        sb.particles      = (SoftParticle*)stdheap::fmalloc(pbytes);
        sb.springs        = (SoftSpring*)  stdheap::fmalloc(sbytes);
        sb.particle_count = 0;
        sb.particle_cap   = pcap;
        sb.spring_count   = 0;
        sb.spring_cap     = scap;
        sb.active         = true;
    };

    def softbody_free(SoftBody* sb) -> void
    {
        stdheap::ffree((u64)sb.particles);
        stdheap::ffree((u64)sb.springs);
        sb.particles      = (SoftParticle*)0;
        sb.springs        = (SoftSpring*)0;
        sb.particle_count = 0;
        sb.spring_count   = 0;
    };

    // Add a particle; returns its index
    def sb_add_particle(SoftBody* sb, Vec3 pos, float mass, float damping) -> i32
    {
        i32 idx;
        SoftParticle* p;
        if (sb.particle_count >= sb.particle_cap) { return -1; };
        idx = sb.particle_count;
        sb.particle_count++;
        p = @sb.particles[idx];
        p.position   = pos;
        p.velocity   = vec3_zero();
        p.force_accum = vec3_zero();
        p.damping    = damping;
        if (mass < SOFT_EPSILON)
        {
            p.inv_mass = 0.0;
        }
        else
        {
            p.inv_mass = 1.0 / mass;
        };
        return idx;
    };

    // Add a spring between two particles; returns its index
    def sb_add_spring(SoftBody* sb, i32 a, i32 b, float stiffness, float damping, i32 kind) -> i32
    {
        i32 idx;
        Vec3 delta;
        float rest_len;
        SoftSpring* s;
        if (sb.spring_count >= sb.spring_cap) { return -1; };
        idx = sb.spring_count;
        sb.spring_count++;
        s = @sb.springs[idx];
        s.a          = a;
        s.b          = b;
        s.kind       = kind;
        s.stiffness  = stiffness;
        s.damping    = damping;
        // Rest length = current distance between the two particles
        delta        = vec3_sub(sb.particles[a].position, sb.particles[b].position);
        rest_len     = vec3_length(delta);
        s.rest_length = rest_len;
        return idx;
    };

    // Apply spring forces. Fully inlined arithmetic, no Vec3 calls, no per-call stack frames.
    def sb_apply_springs(SoftBody* sb) -> void
    {
        i32   si;
        float dx, dy, dz,
              dist, inv_dist,
              nx, ny, nz,
              extension, f_spring,
              rvx, rvy, rvz, rel_vel,
              f_damp, f_total,
              fx, fy, fz;
        SoftParticle* pa;
        SoftParticle* pb;
        SoftSpring*   s;

        for (si = 0; si < sb.spring_count; si++)
        {
            s  = @sb.springs[si];
            pa = @sb.particles[s.a];
            pb = @sb.particles[s.b];

            dx   = pa.position.x - pb.position.x;
            dy   = pa.position.y - pb.position.y;
            dz   = pa.position.z - pb.position.z;
            dist = sqrt(dx * dx + dy * dy + dz * dz);

            if (dist < SOFT_EPSILON) { continue; };

            inv_dist = 1.0 / dist;
            nx = dx * inv_dist;
            ny = dy * inv_dist;
            nz = dz * inv_dist;

            extension = dist - s.rest_length;
            f_spring  = s.stiffness * extension;

            rvx     = pa.velocity.x - pb.velocity.x;
            rvy     = pa.velocity.y - pb.velocity.y;
            rvz     = pa.velocity.z - pb.velocity.z;
            rel_vel = rvx * nx + rvy * ny + rvz * nz;
            f_damp  = s.damping * rel_vel;

            f_total = f_spring + f_damp;
            fx = nx * f_total;
            fy = ny * f_total;
            fz = nz * f_total;

            if (pa.inv_mass > SOFT_EPSILON)
            {
                pa.force_accum.x -= fx;
                pa.force_accum.y -= fy;
                pa.force_accum.z -= fz;
            };
            if (pb.inv_mass > SOFT_EPSILON)
            {
                pb.force_accum.x += fx;
                pb.force_accum.y += fy;
                pb.force_accum.z += fz;
            };
        };
    };

    // Integrate one soft body for dt seconds. Inlined to avoid Vec3 call depth.
    def sb_integrate(SoftBody* sb, Vec3 gravity, float dt) -> void
    {
        i32   pi;
        float ax, ay, az;
        SoftParticle* p;

        for (pi = 0; pi < sb.particle_count; pi++)
        {
            p = @sb.particles[pi];
            if (p.inv_mass < SOFT_EPSILON) { continue; };

            ax = gravity.x + p.force_accum.x * p.inv_mass;
            ay = gravity.y + p.force_accum.y * p.inv_mass;
            az = gravity.z + p.force_accum.z * p.inv_mass;

            p.velocity.x = (p.velocity.x + ax * dt) * p.damping;
            p.velocity.y = (p.velocity.y + ay * dt) * p.damping;
            p.velocity.z = (p.velocity.z + az * dt) * p.damping;

            p.position.x += p.velocity.x * dt;
            p.position.y += p.velocity.y * dt;
            p.position.z += p.velocity.z * dt;

            p.force_accum.x = 0.0;
            p.force_accum.y = 0.0;
            p.force_accum.z = 0.0;
        };
    };

    // Resolve particle collisions with the ground plane
    def sb_resolve_ground(SoftBody* sb, Vec3 normal, float dist, float restitution, float friction) -> void
    {
        i32 pi;
        float signed_dist, vel_along_normal, tang_len, friction_delta;
        Vec3  tangent, tang_vel, vn, vt;
        SoftParticle* p;

        for (pi = 0; pi < sb.particle_count; pi++)
        {
            p = @sb.particles[pi];
            if (p.inv_mass < SOFT_EPSILON) { continue; };

            signed_dist = vec3_dot(p.position, normal) - dist;
            if (signed_dist >= 0.0) { continue; };

            // Push particle out of the plane
            p.position = vec3_add(p.position, vec3_mul(normal, -signed_dist));

            // Velocity response
            vel_along_normal = vec3_dot(p.velocity, normal);
            if (vel_along_normal < 0.0)
            {
                // Reflect normal component with restitution
                vn = vec3_mul(normal, vel_along_normal);
                vt = vec3_sub(p.velocity, vn);

                // Friction on tangential component
                tang_len = vec3_length(vt);
                if (tang_len > SOFT_EPSILON)
                {
                    tangent   = vec3_div(vt, tang_len);
                    friction_delta = friction * abs(vel_along_normal);
                    if (friction_delta > tang_len)
                    {
                        vt = vec3_zero();
                    }
                    else
                    {
                        vt = vec3_sub(vt, vec3_mul(tangent, friction_delta));
                    };
                };

                p.velocity = vec3_add(vec3_mul(vn, -restitution), vt);
            };
        };
    };

    // Resolve particle collisions with a rigid body sphere
    def sb_resolve_sphere(SoftBody* sb, Vec3 sphere_pos, float radius, float restitution) -> void
    {
        i32 pi;
        Vec3  delta, normal;
        float dist, pen, vn;
        SoftParticle* p;

        for (pi = 0; pi < sb.particle_count; pi++)
        {
            p = @sb.particles[pi];
            if (p.inv_mass < SOFT_EPSILON) { continue; };

            delta = vec3_sub(p.position, sphere_pos);
            dist  = vec3_length(delta);

            if (dist >= radius | dist < SOFT_EPSILON) { continue; };

            normal = vec3_div(delta, dist);
            pen    = radius - dist;

            // Push out
            p.position = vec3_add(p.position, vec3_mul(normal, pen));

            // Reflect velocity
            vn = vec3_dot(p.velocity, normal);
            if (vn < 0.0)
            {
                p.velocity = vec3_sub(p.velocity, vec3_mul(normal, (1.0 + restitution) * vn));
            };
        };
    };

    // ============================================================================
    // SOFTWORLD API
    // ============================================================================

    def softworld_init(SoftWorld* sw, i32 body_cap) -> void
    {
        size_t bbytes = (size_t)(body_cap * (i32)(sizeof(SoftBody) / 8));
        sw.bodies      = (SoftBody*)stdheap::fmalloc(bbytes);
        sw.body_count  = 0;
        sw.body_cap    = body_cap;
        sw.gravity.x   = 0.0;
        sw.gravity.y   = -9.81;
        sw.gravity.z   = 0.0;
        sw.has_ground  = false;
        sw.ground_normal.x = 0.0;
        sw.ground_normal.y = 1.0;
        sw.ground_normal.z = 0.0;
        sw.ground_dist     = 0.0;
    };

    def softworld_destroy(SoftWorld* sw) -> void
    {
        i32 i;
        for (i = 0; i < sw.body_count; i++)
        {
            softbody_free(@sw.bodies[i]);
        };
        stdheap::ffree((u64)sw.bodies);
        sw.bodies     = (SoftBody*)0;
        sw.body_count = 0;
    };

    def softworld_set_gravity(SoftWorld* sw, Vec3 g) -> void
    {
        sw.gravity = g;
    };

    // Set a ground plane for particle collision (normal + signed dist from origin)
    def softworld_set_ground(SoftWorld* sw, Vec3 normal, float dist) -> void
    {
        sw.ground_normal = normal;
        sw.ground_dist   = dist;
        sw.has_ground    = true;
    };

    def softworld_get_body(SoftWorld* sw, i32 id) -> SoftBody*
    {
        if (id < 0 | id >= sw.body_count) { return (SoftBody*)0; };
        return @sw.bodies[id];
    };

    // Pin a particle (set inv_mass = 0, zero velocity) — it will not move
    def softworld_pin(SoftWorld* sw, i32 body_id, i32 particle_idx) -> void
    {
        SoftBody* sb;
        if (body_id < 0 | body_id >= sw.body_count) { return; };
        sb = @sw.bodies[body_id];
        if (particle_idx < 0 | particle_idx >= sb.particle_count) { return; };
        sb.particles[particle_idx].inv_mass  = 0.0;
        sb.particles[particle_idx].velocity  = vec3_zero();
    };

    // Unpin a particle with a given mass
    def softworld_unpin(SoftWorld* sw, i32 body_id, i32 particle_idx, float mass) -> void
    {
        SoftBody* sb;
        if (body_id < 0 | body_id >= sw.body_count) { return; };
        sb = @sw.bodies[body_id];
        if (particle_idx < 0 | particle_idx >= sb.particle_count) { return; };
        if (mass < SOFT_EPSILON) { return; };
        sb.particles[particle_idx].inv_mass = 1.0 / mass;
    };

    // Apply a force to a single particle
    def softworld_apply_force(SoftWorld* sw, i32 body_id, i32 particle_idx, Vec3 force) -> void
    {
        SoftBody* sb;
        if (body_id < 0 | body_id >= sw.body_count) { return; };
        sb = @sw.bodies[body_id];
        if (particle_idx < 0 | particle_idx >= sb.particle_count) { return; };
        sb.particles[particle_idx].force_accum =
            vec3_add(sb.particles[particle_idx].force_accum, force);
    };

    // Apply an impulse (velocity delta) directly to a particle
    def softworld_apply_impulse(SoftWorld* sw, i32 body_id, i32 particle_idx, Vec3 impulse) -> void
    {
        SoftBody* sb;
        SoftParticle* p;
        if (body_id < 0 | body_id >= sw.body_count) { return; };
        sb = @sw.bodies[body_id];
        if (particle_idx < 0 | particle_idx >= sb.particle_count) { return; };
        p = @sb.particles[particle_idx];
        if (p.inv_mass < SOFT_EPSILON) { return; };
        p.velocity = vec3_add(p.velocity, vec3_mul(impulse, p.inv_mass));
    };

    // Resolve soft body particles against all sphere rigid bodies in a PhysWorld
    def softworld_collide_rigid(SoftWorld* sw, PhysWorld* pw) -> void
    {
        i32 si, bi;
        SoftBody* sb;
        RigidBody* rb;

        for (si = 0; si < sw.body_count; si++)
        {
            sb = @sw.bodies[si];
            if (!sb.active) { continue; };

            for (bi = 0; bi < pw.body_count; bi++)
            {
                rb = @pw.bodies[bi];
                if (!rb.active) { continue; };
                if (rb.collider.kind != PHYS_COLLIDER_SPHERE) { continue; };

                sb_resolve_sphere(sb,
                                  rb.position,
                                  rb.collider.sphere.radius,
                                  0.3);
            };
        };
    };

    // Main step: spring forces -> integrate -> ground collision
    def softworld_step(SoftWorld* sw, float dt) -> void
    {
        i32 i;
        SoftBody* sb;

        for (i = 0; i < sw.body_count; i++)
        {
            sb = @sw.bodies[i];
            if (!sb.active) { continue; };

            sb_apply_springs(sb);
            sb_integrate(sb, sw.gravity, dt);

            if (sw.has_ground)
            {
                sb_resolve_ground(sb,
                                  sw.ground_normal,
                                  sw.ground_dist,
                                  SOFT_GROUND_RESTITUTION,
                                  SOFT_GROUND_FRICTION);
            };
        };
    };

    // ============================================================================
    // CONSTRUCTORS
    // ============================================================================

    // Rope: n particles in a straight line along +X from origin.
    // top particle (index 0) is pinned by default.
    // Returns body id or -1 on failure.
    def softworld_add_rope(SoftWorld* sw,
                           Vec3  origin,
                           i32   n,
                           float segment_length,
                           float particle_mass,
                           float damping,
                           float stiffness,
                           float spring_damping) -> i32
    {
        i32 id, pi, si;
        SoftBody* sb;
        Vec3 pos;

        if (sw.body_count >= sw.body_cap) { return -1; };
        id = sw.body_count;
        sw.body_count++;
        sb = @sw.bodies[id];
        sb.id = id;

        // n particles, n-1 structural springs
        softbody_alloc(sb, n, n);

        for (pi = 0; pi < n; pi++)
        {
            pos.x = origin.x;
            pos.y = origin.y - (float)pi * segment_length;
            pos.z = origin.z;
            sb_add_particle(sb, pos, particle_mass, damping);
        };

        for (si = 0; si < n - 1; si++)
        {
            sb_add_spring(sb, si, si + 1, stiffness, spring_damping, SOFT_SPRING_STRUCTURAL);
        };

        // Pin the top
        softworld_pin(sw, id, 0);

        return id;
    };

    // Cloth: rows x cols grid of particles in the XZ plane at given origin.
    // Top row (row 0) is pinned.
    // Springs: structural (horizontal+vertical), shear (diagonal), bend (skip-1).
    // Returns body id or -1 on failure.
    def softworld_add_cloth(SoftWorld* sw,
                            Vec3  origin,
                            i32   rows,
                            i32   cols,
                            float spacing,
                            float particle_mass,
                            float damping,
                            float stiffness,
                            float spring_damping) -> i32
    {
        i32 id, r, c, idx_a, idx_b;
        i32 spring_cap, particle_cap;
        SoftBody* sb;
        Vec3 pos;

        if (sw.body_count >= sw.body_cap) { return -1; };
        id = sw.body_count;
        sw.body_count++;
        sb = @sw.bodies[id];
        sb.id = id;

        particle_cap = rows * cols;
        // structural: (rows-1)*cols + rows*(cols-1)
        // shear:      (rows-1)*(cols-1)*2
        // bend:       (rows-2)*cols + rows*(cols-2)
        spring_cap = (rows - 1) * cols + rows * (cols - 1)
                   + (rows - 1) * (cols - 1) * 2
                   + (rows - 2) * cols + rows * (cols - 2);

        softbody_alloc(sb, particle_cap, spring_cap + 32);

        // Create particles
        for (r = 0; r < rows; r++)
        {
            for (c = 0; c < cols; c++)
            {
                pos.x = origin.x + (float)c * spacing;
                pos.y = origin.y;
                pos.z = origin.z + (float)r * spacing;
                sb_add_particle(sb, pos, particle_mass, damping);
            };
        };

        // Pin top row
        for (c = 0; c < cols; c++)
        {
            softworld_pin(sw, id, c);
        };

        // Structural springs — horizontal
        for (r = 0; r < rows; r++)
        {
            for (c = 0; c < cols - 1; c++)
            {
                idx_a = r * cols + c;
                idx_b = r * cols + c + 1;
                sb_add_spring(sb, idx_a, idx_b, stiffness, spring_damping, SOFT_SPRING_STRUCTURAL);
            };
        };

        // Structural springs — vertical
        for (r = 0; r < rows - 1; r++)
        {
            for (c = 0; c < cols; c++)
            {
                idx_a = r * cols + c;
                idx_b = (r + 1) * cols + c;
                sb_add_spring(sb, idx_a, idx_b, stiffness, spring_damping, SOFT_SPRING_STRUCTURAL);
            };
        };

        // Shear springs — both diagonals
        for (r = 0; r < rows - 1; r++)
        {
            for (c = 0; c < cols - 1; c++)
            {
                idx_a = r * cols + c;
                idx_b = (r + 1) * cols + c + 1;
                sb_add_spring(sb, idx_a, idx_b, stiffness * 0.5, spring_damping, SOFT_SPRING_SHEAR);

                idx_a = r * cols + c + 1;
                idx_b = (r + 1) * cols + c;
                sb_add_spring(sb, idx_a, idx_b, stiffness * 0.5, spring_damping, SOFT_SPRING_SHEAR);
            };
        };

        // Bend springs — horizontal (skip 1 column)
        for (r = 0; r < rows; r++)
        {
            for (c = 0; c < cols - 2; c++)
            {
                idx_a = r * cols + c;
                idx_b = r * cols + c + 2;
                sb_add_spring(sb, idx_a, idx_b, stiffness * 0.25, spring_damping, SOFT_SPRING_BEND);
            };
        };

        // Bend springs — vertical (skip 1 row)
        for (r = 0; r < rows - 2; r++)
        {
            for (c = 0; c < cols; c++)
            {
                idx_a = r * cols + c;
                idx_b = (r + 2) * cols + c;
                sb_add_spring(sb, idx_a, idx_b, stiffness * 0.25, spring_damping, SOFT_SPRING_BEND);
            };
        };

        return id;
    };

    // Blob: 3D tetrahedral lattice of sx x sy x sz particles.
    // No particles are pinned by default.
    // Returns body id or -1 on failure.
    def softworld_add_blob(SoftWorld* sw,
                           Vec3  origin,
                           i32   sx,
                           i32   sy,
                           i32   sz,
                           float spacing,
                           float particle_mass,
                           float damping,
                           float stiffness,
                           float spring_damping) -> i32
    {
        i32 id, x, y, z, idx_a, idx_b;
        i32 particle_cap, spring_cap;
        SoftBody* sb;
        Vec3 pos;

        if (sw.body_count >= sw.body_cap) { return -1; };
        id = sw.body_count;
        sw.body_count++;
        sb = @sw.bodies[id];
        sb.id = id;

        particle_cap = sx * sy * sz;
        // Structural: axial edges in each of the 3 directions
        // Plus face diagonals and body diagonals per cell
        spring_cap = particle_cap * 13;   // generous upper bound

        softbody_alloc(sb, particle_cap, spring_cap);

        // Create particles
        for (z = 0; z < sz; z++)
        {
            for (y = 0; y < sy; y++)
            {
                for (x = 0; x < sx; x++)
                {
                    pos.x = origin.x + (float)x * spacing;
                    pos.y = origin.y + (float)y * spacing;
                    pos.z = origin.z + (float)z * spacing;
                    sb_add_particle(sb, pos, particle_mass, damping);
                };
            };
        };

        // Helper macro for 3D index
        // idx = z * sy * sx + y * sx + x

        // Structural springs along each axis
        for (z = 0; z < sz; z++)
        {
            for (y = 0; y < sy; y++)
            {
                for (x = 0; x < sx; x++)
                {
                    idx_a = z * sy * sx + y * sx + x;

                    if (x + 1 < sx)
                    {
                        idx_b = z * sy * sx + y * sx + (x + 1);
                        sb_add_spring(sb, idx_a, idx_b, stiffness, spring_damping, SOFT_SPRING_STRUCTURAL);
                    };
                    if (y + 1 < sy)
                    {
                        idx_b = z * sy * sx + (y + 1) * sx + x;
                        sb_add_spring(sb, idx_a, idx_b, stiffness, spring_damping, SOFT_SPRING_STRUCTURAL);
                    };
                    if (z + 1 < sz)
                    {
                        idx_b = (z + 1) * sy * sx + y * sx + x;
                        sb_add_spring(sb, idx_a, idx_b, stiffness, spring_damping, SOFT_SPRING_STRUCTURAL);
                    };

                    // Face diagonals (XY, XZ, YZ planes)
                    if (x + 1 < sx & y + 1 < sy)
                    {
                        idx_b = z * sy * sx + (y + 1) * sx + (x + 1);
                        sb_add_spring(sb, idx_a, idx_b, stiffness * 0.6, spring_damping, SOFT_SPRING_SHEAR);
                    };
                    if (x + 1 < sx & z + 1 < sz)
                    {
                        idx_b = (z + 1) * sy * sx + y * sx + (x + 1);
                        sb_add_spring(sb, idx_a, idx_b, stiffness * 0.6, spring_damping, SOFT_SPRING_SHEAR);
                    };
                    if (y + 1 < sy & z + 1 < sz)
                    {
                        idx_b = (z + 1) * sy * sx + (y + 1) * sx + x;
                        sb_add_spring(sb, idx_a, idx_b, stiffness * 0.6, spring_damping, SOFT_SPRING_SHEAR);
                    };

                    // Body diagonal
                    if (x + 1 < sx & y + 1 < sy & z + 1 < sz)
                    {
                        idx_b = (z + 1) * sy * sx + (y + 1) * sx + (x + 1);
                        sb_add_spring(sb, idx_a, idx_b, stiffness * 0.5, spring_damping, SOFT_SPRING_SHEAR);
                    };
                };
            };
        };

        return id;
    };
};

#endif;
