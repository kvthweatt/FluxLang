// Author: Karac V. Thweatt
//
// softbody_demo.fx - Combined Soft Body + Rigid Body Demo
//
// Scene:
//   - Ground plane
//   - Hanging cloth (10x10, top row pinned)
//   - Hanging rope (8 segments, top pinned)
//   - Blob (3x3x3 jelly cube) dropped from above
//   - Rigid sphere rolling into the cloth from the side
//

#import "standard.fx";
#import "timing.fx";
#import "windows.fx";
#import "opengl.fx";
#import "physics.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;
using standard::time;
using physics;

#def DEMO_DT          0.008;
#def DEMO_FRAME_NS    8000000;
#def DEMO_SUBSTEPS    3;

// Draw a soft body as a point cloud + spring lines
def draw_softbody_points(SoftBody* sb) -> void
{
    i32 pi;
    SoftParticle* p;

    glBegin(GL_POINTS);
    for (pi = 0; pi < sb.particle_count; pi++)
    {
        p = @sb.particles[pi];
        glVertex3f(p.position.x, p.position.y, p.position.z);
    };
    glEnd();
};

def draw_softbody_springs(SoftBody* sb, i32 kind) -> void
{
    i32 si;
    SoftSpring*   s;
    SoftParticle* pa;
    SoftParticle* pb;

    glBegin(GL_LINES);
    for (si = 0; si < sb.spring_count; si++)
    {
        s = @sb.springs[si];
        if (s.kind != kind) { continue; };
        pa = @sb.particles[s.a];
        pb = @sb.particles[s.b];
        glVertex3f(pa.position.x, pa.position.y, pa.position.z);
        glVertex3f(pb.position.x, pb.position.y, pb.position.z);
    };
    glEnd();
};

// Draw cloth as a quad mesh (structural springs form rows/cols)
def draw_cloth_mesh(SoftBody* sb, i32 rows, i32 cols) -> void
{
    i32 r, c, idx;
    SoftParticle* p00;
    SoftParticle* p10;
    SoftParticle* p01;
    SoftParticle* p11;

    glBegin(GL_LINES);
    for (r = 0; r < rows; r++)
    {
        for (c = 0; c < cols - 1; c++)
        {
            p00 = @sb.particles[r * cols + c];
            p10 = @sb.particles[r * cols + c + 1];
            glVertex3f(p00.position.x, p00.position.y, p00.position.z);
            glVertex3f(p10.position.x, p10.position.y, p10.position.z);
        };
    };
    for (r = 0; r < rows - 1; r++)
    {
        for (c = 0; c < cols; c++)
        {
            p00 = @sb.particles[r       * cols + c];
            p01 = @sb.particles[(r + 1) * cols + c];
            glVertex3f(p00.position.x, p00.position.y, p00.position.z);
            glVertex3f(p01.position.x, p01.position.y, p01.position.z);
        };
    };
    glEnd();
};

// Ground grid
def draw_ground_grid(float size, i32 divs) -> void
{
    i32 i;
    float t, step, half;
    step = size / (float)divs;
    half = size * 0.5;

    glColor3f(0.2, 0.4, 0.2);
    glBegin(GL_LINES);
    for (i = 0; i <= divs; i++)
    {
        t = (float)i * step - half;
        glVertex3f(t,    0.0, -half);
        glVertex3f(t,    0.0,  half);
        glVertex3f(-half, 0.0, t);
        glVertex3f( half, 0.0, t);
    };
    glEnd();
};

// Wireframe sphere
#def SB_SLICES 8;
#def SB_PI     3.14159265;

def draw_sphere_wire(float cx, float cy, float cz, float r) -> void
{
    i32 i, j;
    float lat0, lat1, lng, lat;
    float sin_lat0, cos_lat0, sin_lat1, cos_lat1, sin_lng, cos_lng;

    for (i = 0; i <= SB_SLICES; i++)
    {
        lat0 = SB_PI * (-0.5 + (float)(i - 1) / (float)SB_SLICES);
        lat1 = SB_PI * (-0.5 + (float)i       / (float)SB_SLICES);
        sin_lat0 = sin(lat0); cos_lat0 = cos(lat0);
        sin_lat1 = sin(lat1); cos_lat1 = cos(lat1);

        glBegin(GL_LINE_STRIP);
        for (j = 0; j <= SB_SLICES; j++)
        {
            lng = 2.0 * SB_PI * (float)j / (float)SB_SLICES;
            sin_lng = sin(lng); cos_lng = cos(lng);
            glVertex3f(cx + r * cos_lat0 * cos_lng, cy + r * sin_lat0, cz + r * cos_lat0 * sin_lng);
            glVertex3f(cx + r * cos_lat1 * cos_lng, cy + r * sin_lat1, cz + r * cos_lat1 * sin_lng);
        };
        glEnd();
    };
};

def main() -> int
{
    // ---- Rigid body world (just a ground plane + rolling sphere) ----
    PhysWorld pw;
    i32 ground_rb, sphere_rb;
    RigidBody* rb;

    world_init(@pw, 16, 256);
    world_set_gravity(@pw, vec3(0.0, -9.81, 0.0));

    ground_rb = world_add_plane(@pw, vec3(0.0, 1.0, 0.0), 0.0);
    world_set_material(@pw, ground_rb, 0.3, 0.7);

    // Sphere that will roll into the cloth
    sphere_rb = world_add_sphere(@pw, vec3(-6.0, 1.5, 0.0), 0.8, 2.0);
    world_set_material(@pw, sphere_rb, 0.4, 0.5);
    world_apply_impulse_at(@pw, sphere_rb, vec3(5.0, 1.0, 0.0), vec3(-6.0, 1.5, 0.0));

    // ---- Soft body world ----
    SoftWorld sw;
    i32 cloth_id, rope_id, blob_id;
    SoftBody* sb;

    softworld_init(@sw, 8);
    softworld_set_gravity(@sw, vec3(0.0, -9.81, 0.0));
    softworld_set_ground(@sw, vec3(0.0, 1.0, 0.0), 0.0);

    // Cloth: 8x8 hanging from y=6
    cloth_id = softworld_add_cloth(@sw,
                                   vec3(-1.75, 6.0, -1.75),
                                   8, 8,
                                   0.5,         // spacing
                                   0.1,         // particle mass
                                   0.98,        // damping
                                   180.0,       // stiffness
                                   1.5          // spring damping
                                   );

    // Rope: 8 segments hanging from x=4, y=7
    rope_id = softworld_add_rope(@sw,
                                 vec3(4.0, 7.0, 0.0),
                                 8,
                                 0.5,           // segment length
                                 0.15,          // particle mass
                                 0.97,          // damping
                                 220.0,         // stiffness
                                 2.0            // spring damping
                                 );

    // Blob: 2x2x2 jelly cube dropped from y=5
    blob_id = softworld_add_blob(@sw,
                                 vec3(-1.0, 5.0, 3.0),
                                 2, 2, 2,
                                 0.5,           // spacing
                                 0.2,           // particle mass
                                 0.97,          // damping
                                 300.0,         // stiffness
                                 2.5            // spring damping
                                 );

    // ---- Window + GL ----
    Window win("Flux Soft Body Demo\0", 1280, 720, 80, 80);
    GLContext gl(win.device_context);
    gl.load_extensions();

    gl.set_clear_color(0.04, 0.04, 0.10, 1.0);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_LINE_SMOOTH);
    glPointSize(3.0);
    glLineWidth(1.0);

    // Camera + projection
    Matrix4 proj, view, combined;
    mat4_perspective(1.0472, 1.7778, 0.1, 200.0, @proj);

    GLVec3 eye, target, up;
    eye.x    = 8.0; eye.y    = 10.0; eye.z = 18.0;
    target.x = 0.0; target.y =  3.0; target.z = 0.0;
    up.x     = 0.0; up.y     =  1.0; up.z    = 0.0;
    mat4_lookat(@eye, @target, @up, @view);
    mat4_mul(@proj, @view, @combined);

    glMatrixMode(GL_PROJECTION);
    glLoadMatrixf(@combined.m[0]);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // ---- Main loop ----
    i32 sub;
    i64 frame_start, frame_end, elapsed_ns, sleep_ns;
    frame_start = time_now();

    while (win.process_messages())
    {
        // Physics: multiple substeps per frame for stability
        for (sub = 0; sub < DEMO_SUBSTEPS; sub++)
        {
            world_step(@pw, DEMO_DT, 6);
            softworld_step(@sw, DEMO_DT);
            // Soft vs rigid sphere coupling
            softworld_collide_rigid(@sw, @pw);
        };

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        // Ground
        draw_ground_grid(24.0, 24);

        // Cloth — cyan structural, dark blue shear
        sb = softworld_get_body(@sw, cloth_id);
        glColor3f(0.1, 0.8, 0.9);
        draw_cloth_mesh(sb, 8, 8);
        glColor3f(0.05, 0.3, 0.5);
        draw_softbody_springs(sb, SOFT_SPRING_SHEAR);

        // Rope — orange
        sb = softworld_get_body(@sw, rope_id);
        glColor3f(1.0, 0.55, 0.1);
        draw_softbody_springs(sb, SOFT_SPRING_STRUCTURAL);
        glColor3f(1.0, 0.7, 0.3);
        draw_softbody_points(sb);

        // Blob — green structural + points
        sb = softworld_get_body(@sw, blob_id);
        glColor3f(0.2, 0.9, 0.3);
        draw_softbody_springs(sb, SOFT_SPRING_STRUCTURAL);
        glColor3f(0.4, 1.0, 0.5);
        draw_softbody_springs(sb, SOFT_SPRING_SHEAR);
        glColor3f(0.8, 1.0, 0.8);
        draw_softbody_points(sb);

        // Rigid sphere — magenta
        rb = world_get_body(@pw, sphere_rb);
        glColor3f(0.9, 0.2, 0.8);
        draw_sphere_wire(rb.position.x, rb.position.y, rb.position.z,
                         rb.collider.sphere.radius);

        gl.present();

        // Cap framerate
        frame_end  = time_now();
        elapsed_ns = frame_end - frame_start;
        sleep_ns   = DEMO_FRAME_NS - elapsed_ns;
        if (sleep_ns > 0)
        {
            sleep_ms((u32)(sleep_ns / 1000000));
        };
        frame_start = time_now();
    };

    softworld_destroy(@sw);
    world_destroy(@pw);
    gl.__exit();
    win.__exit();

    return 0;
};
