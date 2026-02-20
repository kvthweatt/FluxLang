#import "standard.fx";
#import "redmath.fx";
#import "redwindows.fx";
#import "redopengl.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// TYPES
// ============================================================================

struct Vec3 { float x, y, z; };
struct Edge { int a, b; };

struct Shape
{
    Vec3* verts;
    Edge* edges;
    int   vert_count;
    int   edge_count;
    float world_x;
    float world_y;
    float world_z;
    float spin;
};

// ============================================================================
// MATH HELPERS
// ============================================================================

def rotate_y_vec(Vec3* v, float s, float c) -> Vec3
{
    Vec3 r;
    r.x =  v.x * c + v.z * s;
    r.y =  v.y;
    r.z = (v.x * (0.0 - s)) + v.z * c;
    return r;
};

def rotate_x_vec(Vec3* v, float s, float c) -> Vec3
{
    Vec3 r;
    r.x = v.x;
    r.y = v.y * c - v.z * s;
    r.z = v.y * s + v.z * c;
    return r;
};

def project_pt(Vec3* v, int cx, int cy, float fov, float cam_z) -> POINT
{
    float dz = v.z + cam_z;
    POINT p;
    if (dz < 0.1)
    {
        p.x = (LONG)(0 - 9999);
        p.y = (LONG)(0 - 9999);
        return p;
    };
    p.x = (LONG)(cx + (int)(v.x * fov / dz));
    p.y = (LONG)(cy - (int)(v.y * fov / dz));
    return p;
};

// ============================================================================
// SHAPE BUILDERS
// ============================================================================

def build_cube(Shape* s, float wx, float wy, float wz) -> void
{
    s.vert_count = 8;
    s.edge_count = 12;
    s.world_x = wx;
    s.world_y = wy;
    s.world_z = wz;
    s.spin    = 0.0;
    s.verts = (Vec3*)fmalloc((u64)8  * 12);
    s.edges = (Edge*)fmalloc((u64)12 * 8);

    s.verts[0].x = -1.0; s.verts[0].y = -1.0; s.verts[0].z = -1.0;
    s.verts[1].x =  1.0; s.verts[1].y = -1.0; s.verts[1].z = -1.0;
    s.verts[2].x =  1.0; s.verts[2].y =  1.0; s.verts[2].z = -1.0;
    s.verts[3].x = -1.0; s.verts[3].y =  1.0; s.verts[3].z = -1.0;
    s.verts[4].x = -1.0; s.verts[4].y = -1.0; s.verts[4].z =  1.0;
    s.verts[5].x =  1.0; s.verts[5].y = -1.0; s.verts[5].z =  1.0;
    s.verts[6].x =  1.0; s.verts[6].y =  1.0; s.verts[6].z =  1.0;
    s.verts[7].x = -1.0; s.verts[7].y =  1.0; s.verts[7].z =  1.0;

    s.edges[0].a  = 0; s.edges[0].b  = 1;
    s.edges[1].a  = 1; s.edges[1].b  = 2;
    s.edges[2].a  = 2; s.edges[2].b  = 3;
    s.edges[3].a  = 3; s.edges[3].b  = 0;
    s.edges[4].a  = 4; s.edges[4].b  = 5;
    s.edges[5].a  = 5; s.edges[5].b  = 6;
    s.edges[6].a  = 6; s.edges[6].b  = 7;
    s.edges[7].a  = 7; s.edges[7].b  = 4;
    s.edges[8].a  = 0; s.edges[8].b  = 4;
    s.edges[9].a  = 1; s.edges[9].b  = 5;
    s.edges[10].a = 2; s.edges[10].b = 6;
    s.edges[11].a = 3; s.edges[11].b = 7;
    return;
};

def build_pyramid(Shape* s, float wx, float wy, float wz) -> void
{
    s.vert_count = 5;
    s.edge_count = 8;
    s.world_x = wx;
    s.world_y = wy;
    s.world_z = wz;
    s.spin    = 0.0;
    s.verts = (Vec3*)fmalloc((u64)5 * 12);
    s.edges = (Edge*)fmalloc((u64)8 * 8);

    s.verts[0].x =  0.0; s.verts[0].y =  1.5; s.verts[0].z =  0.0;
    s.verts[1].x = -1.0; s.verts[1].y = -1.0; s.verts[1].z = -1.0;
    s.verts[2].x =  1.0; s.verts[2].y = -1.0; s.verts[2].z = -1.0;
    s.verts[3].x =  1.0; s.verts[3].y = -1.0; s.verts[3].z =  1.0;
    s.verts[4].x = -1.0; s.verts[4].y = -1.0; s.verts[4].z =  1.0;

    s.edges[0].a = 0; s.edges[0].b = 1;
    s.edges[1].a = 0; s.edges[1].b = 2;
    s.edges[2].a = 0; s.edges[2].b = 3;
    s.edges[3].a = 0; s.edges[3].b = 4;
    s.edges[4].a = 1; s.edges[4].b = 2;
    s.edges[5].a = 2; s.edges[5].b = 3;
    s.edges[6].a = 3; s.edges[6].b = 4;
    s.edges[7].a = 4; s.edges[7].b = 1;
    return;
};

def build_octahedron(Shape* s, float wx, float wy, float wz) -> void
{
    s.vert_count = 6;
    s.edge_count = 12;
    s.world_x = wx;
    s.world_y = wy;
    s.world_z = wz;
    s.spin    = 0.0;
    s.verts = (Vec3*)fmalloc((u64)6  * 12);
    s.edges = (Edge*)fmalloc((u64)12 * 8);

    s.verts[0].x =  0.0; s.verts[0].y =  1.4; s.verts[0].z =  0.0;
    s.verts[1].x =  0.0; s.verts[1].y = -1.4; s.verts[1].z =  0.0;
    s.verts[2].x =  1.0; s.verts[2].y =  0.0; s.verts[2].z =  0.0;
    s.verts[3].x = -1.0; s.verts[3].y =  0.0; s.verts[3].z =  0.0;
    s.verts[4].x =  0.0; s.verts[4].y =  0.0; s.verts[4].z =  1.0;
    s.verts[5].x =  0.0; s.verts[5].y =  0.0; s.verts[5].z = -1.0;

    s.edges[0].a  = 0; s.edges[0].b  = 2;
    s.edges[1].a  = 0; s.edges[1].b  = 3;
    s.edges[2].a  = 0; s.edges[2].b  = 4;
    s.edges[3].a  = 0; s.edges[3].b  = 5;
    s.edges[4].a  = 1; s.edges[4].b  = 2;
    s.edges[5].a  = 1; s.edges[5].b  = 3;
    s.edges[6].a  = 1; s.edges[6].b  = 4;
    s.edges[7].a  = 1; s.edges[7].b  = 5;
    s.edges[8].a  = 2; s.edges[8].b  = 4;
    s.edges[9].a  = 4; s.edges[9].b  = 3;
    s.edges[10].a = 3; s.edges[10].b = 5;
    s.edges[11].a = 5; s.edges[11].b = 2;
    return;
};

def build_diamond(Shape* s, float wx, float wy, float wz) -> void
{
    s.vert_count = 9;
    s.edge_count = 16;
    s.world_x = wx;
    s.world_y = wy;
    s.world_z = wz;
    s.spin    = 0.0;
    s.verts = (Vec3*)fmalloc((u64)9  * 12);
    s.edges = (Edge*)fmalloc((u64)16 * 8);

    s.verts[0].x =  0.0; s.verts[0].y =  1.8; s.verts[0].z =  0.0;
    s.verts[1].x =  0.0; s.verts[1].y = -1.2; s.verts[1].z =  0.0;

    s.verts[2].x =  1.0; s.verts[2].y =  0.3; s.verts[2].z =  0.0;
    s.verts[3].x =  0.0; s.verts[3].y =  0.3; s.verts[3].z =  1.0;
    s.verts[4].x = -1.0; s.verts[4].y =  0.3; s.verts[4].z =  0.0;
    s.verts[5].x =  0.0; s.verts[5].y =  0.3; s.verts[5].z = -1.0;

    s.verts[6].x =  0.7; s.verts[6].y =  0.8; s.verts[6].z =  0.7;
    s.verts[7].x = -0.7; s.verts[7].y =  0.8; s.verts[7].z =  0.7;
    s.verts[8].x =  0.0; s.verts[8].y =  0.8; s.verts[8].z = -1.0;

    s.edges[0].a  = 0; s.edges[0].b  = 6;
    s.edges[1].a  = 0; s.edges[1].b  = 7;
    s.edges[2].a  = 0; s.edges[2].b  = 8;
    s.edges[3].a  = 6; s.edges[3].b  = 2;
    s.edges[4].a  = 6; s.edges[4].b  = 3;
    s.edges[5].a  = 7; s.edges[5].b  = 3;
    s.edges[6].a  = 7; s.edges[6].b  = 4;
    s.edges[7].a  = 8; s.edges[7].b  = 4;
    s.edges[8].a  = 8; s.edges[8].b  = 5;
    s.edges[9].a  = 2; s.edges[9].b  = 1;
    s.edges[10].a = 3; s.edges[10].b = 1;
    s.edges[11].a = 4; s.edges[11].b = 1;
    s.edges[12].a = 5; s.edges[12].b = 1;
    s.edges[13].a = 2; s.edges[13].b = 5;
    s.edges[14].a = 6; s.edges[14].b = 8;
    s.edges[15].a = 7; s.edges[15].b = 8;
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main(int argc, byte** argv) -> int
{
    const int WIN_WIDTH  = 1280,
              WIN_HEIGHT = 720,
              LINE_WIDTH = 1,
              SLEEP_MS   = 5,
              NUM_SHAPES = 4;

    const float CAM_FOV  = 600.0,
                CAM_DIST = 3.0,
                PAN_SPEED = 0.01;

    Shape[4] shapes;

    build_cube(      @shapes[0],   0.0, 0.0,  8.0);
    build_pyramid(   @shapes[1],   8.0, 0.0,  0.0);
    build_octahedron(@shapes[2],   0.0, 0.0, -8.0);
    build_diamond(   @shapes[3],  -8.0, 0.0,  0.0);

    POINT* proj = (POINT*)fmalloc((u64)512 * 8);

    int cx = WIN_WIDTH  / 2;
    int cy = WIN_HEIGHT / 2;

    float cam_angle = 0.0;
    float[4] spin;
    spin[0] = 0.0;
    spin[1] = 0.0;
    spin[2] = 0.0;
    spin[3] = 0.0;

    DWORD[4] colors = [RGB(100, 180, 255),
                       RGB(255, 120,  60),
                       RGB( 80, 255, 140),
                       RGB(255, 210,  50)
                      ];

    DWORD bg_color = RGB(25, 25, 25);

    Window win("Flux 3D Panorama\0", WIN_WIDTH, WIN_HEIGHT, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);
    Canvas c(win.handle, win.device_context);

    float cam_sy   = 0.0;
    float cam_cy   = 0.0;
    float rel_x    = 0.0;
    float rel_z    = 0.0;
    Vec3  world;
    Vec3  lv;
    Vec3  spun;
    Vec3  cam_space;
    int   si       = 0;
    int   vi       = 0;
    int   ei       = 0;
    int   ea       = 0;
    int   eb       = 0;
    float spin_s   = 0.0;
    float spin_c   = 0.0;

    while (win.process_messages())
    {
        cam_sy = sin(cam_angle);
        cam_cy = cos(cam_angle);

        c.clear(bg_color);

        si = 0;
        while (si < NUM_SHAPES)
        {
            spin_s = sin(spin[si]);
            spin_c = cos(spin[si]);

            vi = 0;
            while (vi < shapes[si].vert_count)
            {
                lv.x = shapes[si].verts[vi].x;
                lv.y = shapes[si].verts[vi].y;
                lv.z = shapes[si].verts[vi].z;

                spun = rotate_y_vec(@lv, spin_s, spin_c);

                world.x = spun.x + shapes[si].world_x;
                world.y = spun.y + shapes[si].world_y;
                world.z = spun.z + shapes[si].world_z;

                rel_x = world.x * cam_cy - world.z * cam_sy;
                rel_z = world.x * cam_sy + world.z * cam_cy;

                cam_space.x = rel_x;
                cam_space.y = world.y;
                cam_space.z = rel_z;

                proj[vi] = project_pt(@cam_space, cx, cy, CAM_FOV, CAM_DIST);
                vi = vi + 1;
            };

            c.set_pen(colors[si], LINE_WIDTH);

            ei = 0;
            while (ei < shapes[si].edge_count)
            {
                ea = shapes[si].edges[ei].a;
                eb = shapes[si].edges[ei].b;
                c.line(proj[ea].x, proj[ea].y, proj[eb].x, proj[eb].y);
                ei = ei + 1;
            };

            spin[si] = spin[si] + 0.018;
            if (spin[si] > PIF) { spin[si] = spin[si] - 2.0 * PIF; };

            si = si + 1;
        };

        cam_angle = cam_angle + PAN_SPEED;
        if (cam_angle > 2.0 * PIF) { cam_angle = cam_angle - 2.0 * PIF; };

        Sleep(SLEEP_MS);
    };

    ffree((u64)proj);

    si = 0;
    while (si < NUM_SHAPES)
    {
        ffree((u64)shapes[si].verts);
        ffree((u64)shapes[si].edges);
        si = si + 1;
    };

    return 0;
};
