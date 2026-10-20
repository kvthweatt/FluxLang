// physics_demo_canvas.fx - 2D projected physics demo using GDI Canvas

#import <windows.fx>;
#import <physics.fx>;
#import <vectors.fx>;
#import <matrices.fx>;
#import <math.fx>;

using standard::windows;
using standard::physics;
using standard::vectors;
using standard::matrices;
using standard::math;

extern
{
    def GetTickCount() -> DWORD;
    def snprintf(byte*, size_t, byte*, ...) -> int;
};  // <-- semicolon REQUIRED after extern block

// ----------------------------------------------------------------------
def project(Vec3 world_pos, Mat4 view, Mat4 proj, int screen_w, int screen_h) -> POINT
{
    Vec4 clip = { world_pos.x, world_pos.y, world_pos.z, 1.0 };
    Mat4 mv = mat4_mul(proj, view);
    Vec4 out = mat4_mul_vec4(mv, clip);

    if (abs(out.w) < 0.0001) { out.w = 0.0001; };
    float inv_w = 1.0 / out.w;
    float ndc_x = out.x * inv_w;
    float ndc_y = out.y * inv_w;

    POINT p;
    p.x = (int)((ndc_x + 1.0) * 0.5 * (float)screen_w);
    p.y = (int)((1.0 - (ndc_y + 1.0) * 0.5) * (float)screen_h);
    return p;
};

def project_radius(Vec3 center, float radius, Mat4 view, Mat4 proj, int screen_w, int screen_h) -> int
{
    Vec3 right = { center.x + radius, center.y, center.z };
    POINT pc = project(center, view, proj, screen_w, screen_h);
    POINT pr = project(right, view, proj, screen_w, screen_h);
    int dx = pc.x - pr.x;
    int dy = pc.y - pr.y;
    return (int)sqrt((float)(dx*dx + dy*dy));
};

def draw_circle(Canvas* canvas, int cx, int cy, int r, DWORD color) -> void
{
    canvas.set_pen(color, 1);
    canvas.ellipse(cx - r, cy - r, cx + r, cy + r);
};

def draw_aabb(Canvas* canvas, Vec3 center, Vec3 half, Mat4 view, Mat4 proj, int screen_w, int screen_h, DWORD color) -> void
{
    Vec3[8] corners;
    corners[0] = { center.x - half.x, center.y - half.y, center.z - half.z };
    corners[1] = { center.x + half.x, center.y - half.y, center.z - half.z };
    corners[2] = { center.x + half.x, center.y - half.y, center.z + half.z };
    corners[3] = { center.x - half.x, center.y - half.y, center.z + half.z };
    corners[4] = { center.x - half.x, center.y + half.y, center.z - half.z };
    corners[5] = { center.x + half.x, center.y + half.y, center.z - half.z };
    corners[6] = { center.x + half.x, center.y + half.y, center.z + half.z };
    corners[7] = { center.x - half.x, center.y + half.y, center.z + half.z };

    POINT[8] scr;
    for (i32 i = 0; i < 8; i++)
    {
        scr[i] = project(corners[i], view, proj, screen_w, screen_h);
    };

    int min_x = scr[0].x, min_y = scr[0].y, max_x = scr[0].x, max_y = scr[0].y;
    for (i32 i = 1; i < 8; i++)
    {
        if (scr[i].x < min_x) { min_x = scr[i].x; };
        if (scr[i].x > max_x) { max_x = scr[i].x; };
        if (scr[i].y < min_y) { min_y = scr[i].y; };
        if (scr[i].y > max_y) { max_y = scr[i].y; };
    };
    canvas.set_pen(color, 1);
    canvas.rect(min_x, min_y, max_x, max_y);
};

def draw_text(Canvas* canvas, int x, int y, LPCSTR text) -> void
{
    HDC hdc = canvas.back_dc;
    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, RGB(255,255,255));
    TextOutA(hdc, x, y, text, -1);
};

def main() -> int
{
    Window win("Flux Physics Demo (Canvas)", 1024, 768, 100, 100);
    Canvas canvas(win.handle, win.device_context);

    // Camera
    Vec3 eye    = { 6.0, 5.0, 8.0 };
    Vec3 target = { 0.0, 1.0, 0.0 };
    Vec3 up     = { 0.0, 1.0, 0.0 };
    Mat4 view;
    mat4_lookat(@eye, @target, @up, @view);

    float aspect = (float)win.width / (float)win.height;
    Mat4 proj;
    mat4_perspective(3.14159 / 3.0, aspect, 0.1, 100.0, @proj);

    // Physics world
    PhysWorld world;
    world_init(@world, 64, 256);
    world_set_gravity(@world, vec3(0.0, -9.81, 0.0));

    world_add_plane(@world, vec3(0.0, 1.0, 0.0), 0.0);
    world_set_material(@world, 0, 0.5, 0.6);

    i32 sphere1 = world_add_sphere(@world, vec3(-2.0, 2.5, -1.5), 0.55, 1.0);
    i32 sphere2 = world_add_sphere(@world, vec3( 1.5, 3.0,  1.2), 0.55, 1.0);
    i32 sphere3 = world_add_sphere(@world, vec3( 0.0, 4.0, -2.0), 0.55, 1.0);
    i32 cube    = world_add_aabb(@world, vec3(-1.0, 2.0, 2.0), vec3(0.7,0.7,0.7), 1.2);

    world_set_material(@world, sphere1, 0.7, 0.3);
    world_set_material(@world, sphere2, 0.5, 0.5);
    world_set_material(@world, sphere3, 0.8, 0.2);
    world_set_material(@world, cube,     0.6, 0.4);

    DWORD last_time = GetTickCount();
    bool running = true;

    while (running)
    {
        if (!win.process_messages()) { running = false; break; };

        DWORD now = GetTickCount();
        float dt = (float)(now - last_time) / 1000.0;
        if (dt > 0.033) { dt = 0.033; };
        last_time = now;

        world_step(@world, dt, 6);

        canvas.clear(RGB(20, 20, 40));
        canvas.refresh_bounds();
        int w = canvas.width();
        int h = canvas.height();

        for (i32 i = 0; i < world.body_count; i++)
        {
            RigidBody* body = world_get_body(@world, i);
            if (!body.active) { continue; };

            DWORD color;
            if (body.collider.kind == PHYS_COLLIDER_SPHERE) { color = RGB(200,100,50); }
            elif (body.collider.kind == PHYS_COLLIDER_AABB) { color = RGB(50,150,200); }
            else { color = RGB(100,100,100); };

            if (body.collider.kind == PHYS_COLLIDER_SPHERE)
            {
                POINT center = project(body.position, view, proj, w, h);
                int r = project_radius(body.position, body.collider.sphere.radius, view, proj, w, h);
                if (r < 3) { r = 3; };
                draw_circle(@canvas, center.x, center.y, r, color);
            }
            elif (body.collider.kind == PHYS_COLLIDER_AABB)
            {
                draw_aabb(@canvas, body.position, body.collider.aabb.half_extents, view, proj, w, h, color);
            };
        };

        // Ground line
        Vec3 p1 = { -10.0, 0.0, -10.0 };
        Vec3 p2 = {  10.0, 0.0,  10.0 };
        POINT s1 = project(p1, view, proj, w, h);
        POINT s2 = project(p2, view, proj, w, h);
        canvas.set_pen(RGB(80,180,80), 2);
        canvas.line(s1.x, s1.y, s2.x, s2.y);

        byte[64] buf;
        snprintf(@buf[0], 64, "FPS: %.1f\0", 1.0 / dt);
        draw_text(@canvas, 10, 20, (LPCSTR)@buf[0]);

        InvalidateRect(win.handle, (RECT*)0, false);
        UpdateWindow(win.handle);
    };

    world_destroy(@world);
    return 0;
};