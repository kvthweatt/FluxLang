#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// Window size
// ============================================================================

const int WIN_W = 900;
const int WIN_H = 600;

// ============================================================================
// Virtual key codes for WASD
// ============================================================================

const int VK_W = 0x57;
const int VK_A = 0x41;
const int VK_S = 0x53;
const int VK_D = 0x44;

// ============================================================================
// Draw the ground plane as a grid of lines at Y = 0
// ============================================================================

def draw_ground(int grid_half, int step) -> void
{
    float extent = (float)grid_half;
    float fs     = (float)step;

    glColor3f(0.25, 0.55, 0.25);
    glBegin(GL_LINES);

    float x = (0.0 - extent);
    while (x <= extent)
    {
        glVertex3f(x, 0.0,  extent);
        glVertex3f(x, 0.0, (0.0 - extent));
        x = x + fs;
    };

    float z = (0.0 - extent);
    while (z <= extent)
    {
        glVertex3f( extent, 0.0, z);
        glVertex3f((0.0 - extent), 0.0, z);
        z = z + fs;
    };

    glEnd();
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("WASD Camera Demo - W/A/S/D to move, ESC to quit\0", WIN_W, WIN_H, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    GLContext gl(win.device_context);
    gl.load_extensions();

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);

    // ---- Camera state ----
    float cam_x   = 0.0;   // world position
    float cam_y   = 1.7;   // eye height
    float cam_z   = 5.0;
    float cam_yaw = 0.0;   // radians, rotation around Y axis
    float move_speed = 0.5;
    float turn_speed = 0.03;
    float aspect;
    float fwd_x, fwd_z, str_x, str_z;
    RECT client_rect;

    int cur_w, cur_h;

    while (win.process_messages())
    {
        // ---- Query current client area size each frame ----
        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_h == 0) { cur_h = 1; };
        aspect = (float)cur_w / (float)cur_h;

        // ---- Keyboard input ----
        if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0)
        {
            // Post quit and break
            PostQuitMessage(0);
        };

        // Forward direction vector (flat, ignore Y)
        fwd_x = sin(cam_yaw);
        fwd_z = (0.0 - cos(cam_yaw));

        // Strafe direction (perpendicular, 90 degrees)
        str_x =  fwd_z;
        str_z = (0.0 - fwd_x);

        if ((GetAsyncKeyState(VK_W) & 0x8000) != 0)
        {
            cam_x = cam_x + fwd_x * move_speed;
            cam_z = cam_z + fwd_z * move_speed;
        };

        if ((GetAsyncKeyState(VK_S) & 0x8000) != 0)
        {
            cam_x = cam_x - fwd_x * move_speed;
            cam_z = cam_z - fwd_z * move_speed;
        };

        if ((GetAsyncKeyState(VK_A) & 0x8000) != 0)
        {
            cam_yaw = cam_yaw - turn_speed;
        };

        if ((GetAsyncKeyState(VK_D) & 0x8000) != 0)
        {
            cam_yaw = cam_yaw + turn_speed;
        };

        // ---- Setup viewport and clear ----
        glViewport(0, 0, cur_w, cur_h);
        gl.set_clear_color(0.05, 0.05, 0.1, 1.0);
        gl.clear();

        // ---- Projection ----
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        Matrix4 proj;
        mat4_perspective(1.0472, aspect, 0.1, 500.0, @proj);  // 60 deg FOV
        glLoadMatrixf(@proj.m[0]);

        // ---- View (look-at) ----
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();

        GLVec3 eye;
        eye.x = cam_x;
        eye.y = cam_y;
        eye.z = cam_z;

        GLVec3 target;
        target.x = cam_x + fwd_x;
        target.y = cam_y;
        target.z = cam_z + fwd_z;

        GLVec3 up;
        up.x = 0.0;
        up.y = 1.0;
        up.z = 0.0;

        Matrix4 view;
        mat4_lookat(@eye, @target, @up, @view);
        glLoadMatrixf(@view.m[0]);

        // ---- Draw ground ----
        draw_ground(50, 1);

        gl.present();
        Sleep(16);
    };

    gl.__exit();
    win.__exit();

    return 0;
};
