#import "standard.fx";
#import "redmath.fx";
#import "redwindows.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// C runtime FFI
// ============================================================================
extern
{
    def !!
        Sleep(u32) -> void;
};

// ============================================================================
// MESH TYPES
// ============================================================================

#def MAX_VERTS 8192;
#def MAX_FACES 16384;

struct Vec3 { float x, y, z; };
struct Face { int a, b, c;   };

struct Mesh
{
    Vec3* verts;
    Face* faces;
    int   vert_count;
    int   face_count;
};

// ============================================================================
// OBJ LOADER
// ============================================================================

def load_obj(byte* path, Mesh* mesh) -> bool
{
    print("Loading object ...\n\0");
    file objfile("examples\\bugatti.obj\0", "rb\0");
    if (objfile.error_state == 1)
    {
        print("Error, bugatti.obj not found.\n\0");
        return false;
    };
    void* f = fopen(path, "r\0");
    if (f == (void*)0) { return false; };
    print("File loaded, initializing arrays...\n\0");

    mesh.verts      = (Vec3*)malloc((u64)MAX_VERTS * 12);
    mesh.faces      = (Face*)malloc((u64)MAX_FACES * 12);
    mesh.vert_count = 0;
    mesh.face_count = 0;

    byte[512] line;

    while (fgets(line, 512, f) != (void*)0)
    {
        if (line[0] == 'v' & line[1] == ' ')
        {
            if (mesh.vert_count < MAX_VERTS)
            {
                float vx = 0.0;
                float vy = 0.0;
                float vz = 0.0;
                sscanf(line, "v %f %f %f\0", @vx, @vy, @vz);
                mesh.verts[mesh.vert_count].x = vx;
                mesh.verts[mesh.vert_count].y = vy;
                mesh.verts[mesh.vert_count].z = vz;
                mesh.vert_count = mesh.vert_count + 1;
            };
        };

        if (line[0] == 'f' & line[1] == ' ')
        {
            if (mesh.face_count < MAX_FACES)
            {
                int fa = 0;
                int fb = 0;
                int fc = 0;
                sscanf(line, "f %d %d %d\0", @fa, @fb, @fc);
                mesh.faces[mesh.face_count].a = fa - 1;
                mesh.faces[mesh.face_count].b = fb - 1;
                mesh.faces[mesh.face_count].c = fc - 1;
                mesh.face_count = mesh.face_count + 1;
            };
        };
    };

    fclose(f);
    return true;
};

// ============================================================================
// 3D MATH
// ============================================================================

def rotate_x(Vec3* v, float s, float c) -> Vec3
{
    Vec3 r;
    r.x = v.x;
    r.y = v.y * c - v.z * s;
    r.z = v.y * s + v.z * c;
    return r;
};

def rotate_y(Vec3* v, float s, float c) -> Vec3
{
    Vec3 r;
    r.x =  v.x * c + v.z * s;
    r.y =  v.y;
    r.z = (v.x * (0.0 - s)) + v.z * c;
    return r;
};

def project(Vec3* v, int cx, int cy, float fov, float cam_z) -> POINT
{
    float dz = v.z + cam_z;
    POINT p;
    if (dz < 0.001)
    {
        p.x = cx;
        p.y = cy;
        return p;
    };
    p.x = cx + (int)(v.x * fov / dz);
    p.y = cy - (int)(v.y * fov / dz);
    return p;
};

// ============================================================================
// MAIN
// ============================================================================

def main(int argc, byte** argv) -> int
{
    Mesh mesh;
    bool loaded;

    if (argc == 2)
    {
        loaded = load_obj(@argv[1], @mesh);
    }
    else
    {
        print("Flux 3D Wireframe Renderer (.OBJ)
Usage: wireframe <file>.obj\n\0");
        loaded = false;
    };
    Window win("Flux 3D Wireframe\0", 900, 700, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    if (!loaded)
    {
        print("Falling back to spinning cube ...\n\0");
        // Fallback: spinning cube
        mesh.verts      = (Vec3*)malloc((u64)8  * 12);
        mesh.faces      = (Face*)malloc((u64)12 * 12);
        mesh.vert_count = 8;
        mesh.face_count = 12;

        mesh.verts[0].x = -1.0; mesh.verts[0].y = -1.0; mesh.verts[0].z = -1.0;
        mesh.verts[1].x =  1.0; mesh.verts[1].y = -1.0; mesh.verts[1].z = -1.0;
        mesh.verts[2].x =  1.0; mesh.verts[2].y =  1.0; mesh.verts[2].z = -1.0;
        mesh.verts[3].x = -1.0; mesh.verts[3].y =  1.0; mesh.verts[3].z = -1.0;
        mesh.verts[4].x = -1.0; mesh.verts[4].y = -1.0; mesh.verts[4].z =  1.0;
        mesh.verts[5].x =  1.0; mesh.verts[5].y = -1.0; mesh.verts[5].z =  1.0;
        mesh.verts[6].x =  1.0; mesh.verts[6].y =  1.0; mesh.verts[6].z =  1.0;
        mesh.verts[7].x = -1.0; mesh.verts[7].y =  1.0; mesh.verts[7].z =  1.0;

        mesh.faces[0].a  = 0; mesh.faces[0].b  = 1; mesh.faces[0].c  = 2;
        mesh.faces[1].a  = 0; mesh.faces[1].b  = 2; mesh.faces[1].c  = 3;
        mesh.faces[2].a  = 4; mesh.faces[2].b  = 6; mesh.faces[2].c  = 5;
        mesh.faces[3].a  = 4; mesh.faces[3].b  = 7; mesh.faces[3].c  = 6;
        mesh.faces[4].a  = 0; mesh.faces[4].b  = 3; mesh.faces[4].c  = 7;
        mesh.faces[5].a  = 0; mesh.faces[5].b  = 7; mesh.faces[5].c  = 4;
        mesh.faces[6].a  = 1; mesh.faces[6].b  = 5; mesh.faces[6].c  = 6;
        mesh.faces[7].a  = 1; mesh.faces[7].b  = 6; mesh.faces[7].c  = 2;
        mesh.faces[8].a  = 0; mesh.faces[8].b  = 4; mesh.faces[8].c  = 5;
        mesh.faces[9].a  = 0; mesh.faces[9].b  = 5; mesh.faces[9].c  = 1;
        mesh.faces[10].a = 3; mesh.faces[10].b = 2; mesh.faces[10].c = 6;
        mesh.faces[11].a = 3; mesh.faces[11].b = 6; mesh.faces[11].c = 7;
    };

    POINT* proj = (POINT*)malloc((u64)mesh.vert_count * 16);

    float angle_x = 0.0;
    float angle_y = 0.0;
    float fov     = 400.0;
    float cam_z   = 4.0;
    int   cx      = 450;
    int   cy      = 350;

    DWORD green = RGB(0, 255, 0);
    DWORD black = RGB(0, 0, 0);

    while (win.process_messages())
    {
        float sx   = sin(angle_x);
        float cxr  = cos(angle_x);
        float sy   = sin(angle_y);
        float cyr  = cos(angle_y);

        int i = 0;
        while (i < mesh.vert_count)
        {
            Vec3 v;
            v.x = mesh.verts[i].x;
            v.y = mesh.verts[i].y;
            v.z = mesh.verts[i].z;
            Vec3 rx = rotate_x(@v,  sx,  cxr);
            Vec3 ry = rotate_y(@rx, sy,  cyr);
            proj[i] = project(@ry, cx, cy, fov, cam_z);
            i = i + 1;
        };

        Canvas c(win.handle, win.device_context);
        c.clear(black);
        c.set_pen(green, 1);

        int fi = 0;
        while (fi < mesh.face_count)
        {
            int a  = mesh.faces[fi].a;
            int b  = mesh.faces[fi].b;
            int fv = mesh.faces[fi].c;
            c.line(proj[a].x,  proj[a].y,  proj[b].x,  proj[b].y);
            c.line(proj[b].x,  proj[b].y,  proj[fv].x, proj[fv].y);
            c.line(proj[fv].x, proj[fv].y, proj[a].x,  proj[a].y);
            fi = fi + 1;
        };

        angle_x = angle_x + 0.014;
        angle_y = angle_y + 0.020;

        Sleep(16);
    };

    free(proj);
    free(mesh.verts);
    free(mesh.faces);

    return 0;
};
