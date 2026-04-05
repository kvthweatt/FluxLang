// Author: Karac V. Thweatt
//
// physics_demo_3d.fx - Live 3D Physics Engine Demo
//
// Opens an OpenGL window and renders the physics simulation in real time.
// Bodies:
//   - Ground plane rendered as a grid
//   - Three spheres dropped from different heights with offsets
//   - One box dropped from height
//   - One sphere launched sideways
//
// Controls: close window to quit.
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

// ============================================================================
// SPHERE WIREFRAME RENDERER
// Draws a sphere as latitude/longitude lines using glBegin/glEnd
// ============================================================================

#def SPHERE_SLICES 12;
#def SPHERE_PI     3.14159265;

def draw_sphere_wire(float cx, float cy, float cz, float r) -> void
{
    i32 i, j;
    float lat0, lat1, lng, lat;
    float x0, y0, z0, x1, y1, z1;
    float sin_lat0, cos_lat0, sin_lat1, cos_lat1, sin_lng, cos_lng;

    // Latitude rings
    for (i = 0; i <= SPHERE_SLICES; i++)
    {
        lat0 = SPHERE_PI * (-0.5 + (float)(i - 1) / (float)SPHERE_SLICES);
        lat1 = SPHERE_PI * (-0.5 + (float)i       / (float)SPHERE_SLICES);

        sin_lat0 = sin(lat0);
        cos_lat0 = cos(lat0);
        sin_lat1 = sin(lat1);
        cos_lat1 = cos(lat1);

        glBegin(GL_LINE_STRIP);
        for (j = 0; j <= SPHERE_SLICES; j++)
        {
            lng = 2.0 * SPHERE_PI * (float)j / (float)SPHERE_SLICES;
            sin_lng = sin(lng);
            cos_lng = cos(lng);

            glVertex3f(cx + r * cos_lat0 * cos_lng,
                       cy + r * sin_lat0,
                       cz + r * cos_lat0 * sin_lng);
            glVertex3f(cx + r * cos_lat1 * cos_lng,
                       cy + r * sin_lat1,
                       cz + r * cos_lat1 * sin_lng);
        };
        glEnd();
    };

    // Longitude lines
    for (j = 0; j < SPHERE_SLICES; j++)
    {
        lng = 2.0 * SPHERE_PI * (float)j / (float)SPHERE_SLICES;
        sin_lng = sin(lng);
        cos_lng = cos(lng);

        glBegin(GL_LINE_STRIP);
        for (i = 0; i <= SPHERE_SLICES; i++)
        {
            lat = SPHERE_PI * (-0.5 + (float)i / (float)SPHERE_SLICES);
            glVertex3f(cx + r * cos(lat) * cos_lng,
                       cy + r * sin(lat),
                       cz + r * cos(lat) * sin_lng);
        };
        glEnd();
    };
};

// ============================================================================
// AABB WIREFRAME RENDERER
// ============================================================================

def draw_aabb_wire(float cx, float cy, float cz, float hx, float hy, float hz) -> void
{
    float x0, x1, y0, y1, z0, z1;
    x0 = cx - hx; x1 = cx + hx;
    y0 = cy - hy; y1 = cy + hy;
    z0 = cz - hz; z1 = cz + hz;

    glBegin(GL_LINE_LOOP);
    glVertex3f(x0, y0, z0); glVertex3f(x1, y0, z0);
    glVertex3f(x1, y1, z0); glVertex3f(x0, y1, z0);
    glEnd();

    glBegin(GL_LINE_LOOP);
    glVertex3f(x0, y0, z1); glVertex3f(x1, y0, z1);
    glVertex3f(x1, y1, z1); glVertex3f(x0, y1, z1);
    glEnd();

    glBegin(GL_LINES);
    glVertex3f(x0, y0, z0); glVertex3f(x0, y0, z1);
    glVertex3f(x1, y0, z0); glVertex3f(x1, y0, z1);
    glVertex3f(x1, y1, z0); glVertex3f(x1, y1, z1);
    glVertex3f(x0, y1, z0); glVertex3f(x0, y1, z1);
    glEnd();
};

// ============================================================================
// GROUND GRID RENDERER
// Draws a flat grid on the XZ plane at y=0
// ============================================================================

def draw_ground_grid(float size, i32 divs) -> void
{
    i32 i;
    float t, step, half;
    step = size / (float)divs;
    half = size * 0.5;

    glColor3f(0.25, 0.45, 0.25);
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

// ============================================================================
// MAIN
// ============================================================================

#def PHYS_DT         0.01666;
#def FRAME_NS_TARGET 16666667;

def main() -> int
{
    // ---- Physics setup ----
    PhysWorld world;
    i32 ball_a, ball_b, ball_c, box_a;
    i32 ground;
    RigidBody* b;

    world_init(@world, 64, 512);
    world_set_gravity(@world, vec3(0.0, -9.81, 0.0));

    // Ground at y=0
    ground = world_add_plane(@world, vec3(0.0, 1.0, 0.0), 0.0);
    world_set_material(@world, ground, 0.3, 0.7);

    // Box: half-extent 0.6, so bottom at y = centre - 0.6. Start at y=0.61 (just above ground)
    box_a  = world_add_aabb(@world, vec3( 0.0,  0.61,  0.0), vec3(0.6, 0.6, 0.6), 3.0);
    world_set_material(@world, box_a, 0.2, 0.8);

    // Ball A: radius 0.5, rests on top of box (box top = 0.61+0.6=1.21, ball centre = 1.21+0.5+0.01)
    ball_a = world_add_sphere(@world, vec3( 0.1,  6.0,  0.0), 0.5, 1.0);
    world_set_material(@world, ball_a, 0.4, 0.5);

    // Ball B: radius 0.5, falls from higher, offset so it hits ball_a
    ball_b = world_add_sphere(@world, vec3( 0.0, 10.0,  0.2), 0.5, 1.5);
    world_set_material(@world, ball_b, 0.35, 0.5);

    // Ball C: radius 0.4, highest, slight offset
    ball_c = world_add_sphere(@world, vec3(-0.1, 14.0, -0.1), 0.4, 0.8);
    world_set_material(@world, ball_c, 0.3, 0.5);

    // ---- Window + GL context ----
    Window win("Flux Physics Demo - 3D\0", 1024, 768, 100, 100);
    GLContext gl(win.device_context);
    gl.load_extensions();

    gl.set_clear_color(0.05, 0.05, 0.12, 1.0);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_LINE_SMOOTH);
    glLineWidth(1.2);

    // ---- Projection matrix (built manually, column-major) ----
    // perspective: fovy=60deg, aspect=1024/768, near=0.1, far=200
    Matrix4 proj, view, tmp;
    mat4_perspective(1.0472, 1.3333, 0.1, 200.0, @proj);  // 60deg = 1.0472 rad

    // Camera: eye=(8,10,18), target=(0,3,0), up=(0,1,0)
    GLVec3 eye, target, up;
    eye.x    =  8.0; eye.y    = 10.0; eye.z    = 18.0;
    target.x =  0.0; target.y =  3.0; target.z =  0.0;
    up.x     =  0.0; up.y     =  1.0; up.z     =  0.0;
    mat4_lookat(@eye, @target, @up, @view);

    mat4_mul(@proj, @view, @tmp);

    // Load combined projection*view into GL_PROJECTION, identity into GL_MODELVIEW
    glMatrixMode(GL_PROJECTION);
    glLoadMatrixf(@tmp.m[0]);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // ---- Main loop: fixed timestep, capped at 60 fps ----
    i64 frame_start, frame_end, elapsed_ns, sleep_ns;
    frame_start = time_now();

    while (win.process_messages())
    {
        // Step physics with fixed dt
        world_step(@world, PHYS_DT, 6);

        // Render
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        // Ground grid
        draw_ground_grid(20.0, 20);

        // Ball A — cyan
        b = world_get_body(@world, ball_a);
        glColor3f(0.2, 0.9, 0.9);
        draw_sphere_wire(b.position.x, b.position.y, b.position.z,
                         b.collider.sphere.radius);

        // Ball B — orange
        b = world_get_body(@world, ball_b);
        glColor3f(1.0, 0.5, 0.1);
        draw_sphere_wire(b.position.x, b.position.y, b.position.z,
                         b.collider.sphere.radius);

        // Ball C — magenta
        b = world_get_body(@world, ball_c);
        glColor3f(0.9, 0.2, 0.9);
        draw_sphere_wire(b.position.x, b.position.y, b.position.z,
                         b.collider.sphere.radius);

        // Box — yellow
        b = world_get_body(@world, box_a);
        glColor3f(0.9, 0.85, 0.1);
        draw_aabb_wire(b.position.x, b.position.y, b.position.z,
                       b.collider.aabb.half_extents.x,
                       b.collider.aabb.half_extents.y,
                       b.collider.aabb.half_extents.z);

        gl.present();

        // Sleep to cap at ~60 fps
        frame_end   = time_now();
        elapsed_ns  = frame_end - frame_start;
        sleep_ns    = FRAME_NS_TARGET - elapsed_ns;
        if (sleep_ns > 0)
        {
            sleep_ms((u32)(sleep_ns / 1000000));
        };
        frame_start = time_now();
    };

    world_destroy(@world);
    gl.__exit();
    win.__exit();

    return 0;
};
