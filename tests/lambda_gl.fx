#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// Lambda Fractal - OpenGL Viewer
// Based on the complex logistic map: z_{n+1} = lambda * z * (1 - z)
//
// Two display modes (Tab to toggle):
//   Julia mode    - lambda fixed, z0 = pixel; explore the filled Julia set
//   Parameter mode - z0 = 0.5 (critical point), lambda = pixel; explore
//                    the connectedness locus (analogous to the Mandelbrot set)
//
// Navigation:
//   W / S        = zoom in / out
//   A / D        = pan left / right
//   Up / Down    = pan up / down
//   J / L        = shift lambda real part      (Julia mode only)
//   I / K        = shift lambda imaginary part (Julia mode only)
//   Tab          = toggle Julia <-> Parameter plane
// ============================================================================

const int WIN_W        = 900;
const int WIN_H        = 900;
const int MAX_ITER     = 1024;
const int TILE_STILL   = 1;
const int TILE_MOVING  = 4;

// Virtual key codes
const int VK_W   = 0x57;
const int VK_S   = 0x53;
const int VK_A   = 0x41;
const int VK_D   = 0x44;
const int VK_J   = 0x4A;
const int VK_L   = 0x4C;
const int VK_I   = 0x49;
const int VK_K   = 0x4B;
const int VK_TAB = 0x09;
const int VK_UP   = 0x26;
const int VK_DOWN = 0x28;

// ============================================================================
// Double-double arithmetic using Flux array packing.
// A dd (double-double) is two floats packed into a u64: [hi, lo]
// hi holds the main value, lo holds the error term.
// ============================================================================

def dd_pack(float hi, float lo) -> u64
{
    float[2] parts = [hi, lo];
    return (u64)parts;
};

def dd_hi(u64 dd) -> float
{
    float[2] parts = (float[2])dd;
    return parts[0];
};

def dd_lo(u64 dd) -> float
{
    float[2] parts = (float[2])dd;
    return parts[1];
};

def dd_add(u64 a, u64 b) -> u64
{
    float ahi, alo, bhi, blo, s, e;
    ahi = dd_hi(a);
    alo = dd_lo(a);
    bhi = dd_hi(b);
    blo = dd_lo(b);
    s   = ahi + bhi;
    e   = bhi - (s - ahi);
    return dd_pack(s, (alo + blo) + e);
};

def dd_sub(u64 a, u64 b) -> u64
{
    float ahi, alo, bhi, blo, s, e;
    ahi = dd_hi(a);
    alo = dd_lo(a);
    bhi = dd_hi(b);
    blo = dd_lo(b);
    s   = ahi - bhi;
    e   = (0.0 - bhi) - (s - ahi);
    return dd_pack(s, (alo - blo) + e);
};

def dd_mul(u64 a, u64 b) -> u64
{
    float ahi, alo, bhi, blo, p, e;
    ahi = dd_hi(a);
    alo = dd_lo(a);
    bhi = dd_hi(b);
    blo = dd_lo(b);
    p   = ahi * bhi;
    e   = ahi * blo + alo * bhi;
    return dd_pack(p, e);
};

def dd_scale(u64 a, float s) -> u64
{
    return dd_pack(dd_hi(a) * s, dd_lo(a) * s);
};

// ============================================================================
// Lambda map iteration: z_{n+1} = lambda * z * (1 - z)
//
// Expanding in real/imaginary components:
//   Let z = zx + zy*i,  lambda = lx + ly*i
//
//   w = z*(1-z) = z - z^2
//     z^2  = (zx^2 - zy^2)  +  (2*zx*zy)*i
//     w    = (zx - zx^2 + zy^2)  +  (zy - 2*zx*zy)*i
//          = wx + wy*i
//
//   lambda * w = (lx*wx - ly*wy)  +  (lx*wy + ly*wx)*i
//
// Bailout radius: |z| > 2  (same escape criterion as Mandelbrot / Julia)
// ============================================================================

// Julia-mode: lambda fixed, z0 = pixel coordinate
def lambda_julia(u64 zx0, u64 zy0, u64 lx, u64 ly, int max_iter) -> int
{
    u64  zx, zy, zx2, zy2, wx, wy, nzx, nzy;
    float zxh, zyh;
    int iter;

    zx   = zx0;
    zy   = zy0;
    iter = 0;

    while (iter < max_iter)
    {
        zx2 = dd_mul(zx, zx);
        zy2 = dd_mul(zy, zy);

        // Bailout: |z|^2 > 4
        zxh = dd_hi(zx2);
        zyh = dd_hi(zy2);
        if (zxh + zyh > 4.0) { return iter; };

        // w = z*(1-z):  wx = zx - zx^2 + zy^2,  wy = zy - 2*zx*zy
        wx  = dd_add(dd_sub(zx, zx2), zy2);
        wy  = dd_sub(zy, dd_scale(dd_mul(zx, zy), 2.0));

        // z' = lambda * w:  nzx = lx*wx - ly*wy,  nzy = lx*wy + ly*wx
        nzx = dd_sub(dd_mul(lx, wx), dd_mul(ly, wy));
        nzy = dd_add(dd_mul(lx, wy), dd_mul(ly, wx));

        zx = nzx;
        zy = nzy;
        iter++;
    };

    return iter;
};

// Parameter-mode: z0 = 0.5 (critical point), lambda = pixel coordinate
def lambda_param(u64 lx, u64 ly, int max_iter) -> int
{
    u64  zx, zy, zx2, zy2, wx, wy, nzx, nzy;
    float zxh, zyh;
    int iter;

    // Start at the critical point z0 = 0.5
    zx   = dd_pack(0.5, 0.0);
    zy   = dd_pack(0.0, 0.0);
    iter = 0;

    while (iter < max_iter)
    {
        zx2 = dd_mul(zx, zx);
        zy2 = dd_mul(zy, zy);

        zxh = dd_hi(zx2);
        zyh = dd_hi(zy2);
        if (zxh + zyh > 4.0) { return iter; };

        wx  = dd_add(dd_sub(zx, zx2), zy2);
        wy  = dd_sub(zy, dd_scale(dd_mul(zx, zy), 2.0));

        nzx = dd_sub(dd_mul(lx, wx), dd_mul(ly, wy));
        nzy = dd_add(dd_mul(lx, wy), dd_mul(ly, wx));

        zx = nzx;
        zy = nzy;
        iter++;
    };

    return iter;
};

// Map iteration count to an RGB color
def iter_to_color(int iter, int max_iter, float* r, float* g, float* b) -> void
{
    float t, s;

    if (iter == max_iter)
    {
        *r = 0.0;
        *g = 0.0;
        *b = 0.0;
        return;
    };

    // t in [0,1] across one 64-step cycle
    t = (float)(iter % 64) / 63.0;

    // First half: deep green -> bright cyan
    // Second half: bright cyan -> warm orange
    if (t < 0.5)
    {
        s = t * 2.0;
        *r = 0.0;
        *g = 0.4 + s * 0.6;
        *b = s;
    }
    else
    {
        s = (t - 0.5) * 2.0;
        *r = s;
        *g = 1.0 - s * 0.6;
        *b = 1.0 - s;
    };

    return;
};

extern def !!GetTickCount() -> DWORD;

def main() -> int
{
    Window win( "Lambda Fractal - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y  J/L: Re(lam)  I/K: Im(lam)  Tab: Mode\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);

    // View parameters
    u64 cx, cy, zoom, half_zoom, x_min, y_min,
        x_range, y_range, fx, fy;

    // Start parameter plane view centered on the interesting region
    cx   = dd_pack( 1.0, 0.0);
    cy   = dd_pack( 0.0, 0.0);
    zoom = dd_pack( 5.0, 0.0);

    // Lambda constant for Julia mode (a classic interesting value)
    u64 lx, ly;
    lx = dd_pack(0.85,  0.0);
    ly = dd_pack(0.6,   0.0);

    // 0 = parameter plane,  1 = Julia mode
    int mode;
    mode = 0;

    float zoom_speed, pan_speed, c_speed, dt, zoom_hi;
    zoom_speed = 1.5;
    pan_speed  = 0.6;
    c_speed    = 0.4;

    float px0, px1, py0, py1, r, gv, b;

    int tile, dyn_max_iter;
    int cols, rows, row, col, iter, cur_w, cur_h;
    bool moving;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    WORD w_state, s_state, a_state, d_state,
         up_state, dn_state,
         j_state, l_state, i_state, k_state,
         tab_state, tab_prev;

    tab_prev = 0;

    while (win.process_messages())
    {
        // Delta time
        t_now  = GetTickCount();
        dt     = (float)(t_now - t_last) / 1000.0;
        t_last = t_now;
        if (dt > 0.1) { dt = 0.1; };

        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };

        glViewport(0, 0, cur_w, cur_h);

        w_state   = GetAsyncKeyState(VK_W);
        s_state   = GetAsyncKeyState(VK_S);
        a_state   = GetAsyncKeyState(VK_A);
        d_state   = GetAsyncKeyState(VK_D);
        up_state  = GetAsyncKeyState(VK_UP);
        dn_state  = GetAsyncKeyState(VK_DOWN);
        j_state   = GetAsyncKeyState(VK_J);
        l_state   = GetAsyncKeyState(VK_L);
        i_state   = GetAsyncKeyState(VK_I);
        k_state   = GetAsyncKeyState(VK_K);
        tab_state = GetAsyncKeyState(VK_TAB);

        // Toggle mode on Tab press (rising edge)
        if (((tab_state `& 0x8000) != 0) `& ((tab_prev `& 0x8000) == 0))
        {
            if (mode == 0)
            {
                // Switch to Julia mode - center on the Julia set
                mode = 1;
                cx   = dd_pack(0.5,  0.0);
                cy   = dd_pack(0.0,  0.0);
                zoom = dd_pack(3.0,  0.0);
            }
            else
            {
                // Switch to parameter plane - restore parameter view
                mode = 0;
                cx   = dd_pack(1.0,  0.0);
                cy   = dd_pack(0.0,  0.0);
                zoom = dd_pack(5.0,  0.0);
            };
        };
        tab_prev = tab_state;

        moving = ((w_state  `& 0x8000) != 0) |
                 ((s_state  `& 0x8000) != 0) |
                 ((a_state  `& 0x8000) != 0) |
                 ((d_state  `& 0x8000) != 0) |
                 ((up_state `& 0x8000) != 0) |
                 ((dn_state `& 0x8000) != 0) |
                 ((j_state  `& 0x8000) != 0) |
                 ((l_state  `& 0x8000) != 0) |
                 ((i_state  `& 0x8000) != 0) |
                 ((k_state  `& 0x8000) != 0);

        tile = moving ? TILE_MOVING : TILE_STILL;

        cols = cur_w / tile;
        rows = cur_h / tile;
        if (cols < 1) { cols = 1; };
        if (rows < 1) { rows = 1; };

        zoom_hi = dd_hi(zoom);
        if (zoom_hi > 1.0)
        {
            dyn_max_iter = 128;
        }
        elif (zoom_hi > 0.01)
        {
            dyn_max_iter = 256;
        }
        elif (zoom_hi > 0.0001)
        {
            dyn_max_iter = 512;
        }
        else
        {
            dyn_max_iter = MAX_ITER;
        };
        if (moving) { dyn_max_iter = dyn_max_iter >> 1; };

        if ((w_state `& 0x8000) != 0)
        {
            zoom = dd_scale(zoom, 1.0 - zoom_speed * dt);
            if (dd_hi(zoom) < 0.0000000001) { zoom = dd_pack(0.0000000001, 0.0); };
        };

        if ((s_state `& 0x8000) != 0)
        {
            zoom = dd_scale(zoom, 1.0 + zoom_speed * dt);
            if (dd_hi(zoom) > 8.0) { zoom = dd_pack(8.0, 0.0); };
        };

        if ((a_state `& 0x8000) != 0)
        {
            cx = dd_sub(cx, dd_scale(zoom, pan_speed * dt));
        };

        if ((d_state `& 0x8000) != 0)
        {
            cx = dd_add(cx, dd_scale(zoom, pan_speed * dt));
        };

        if ((up_state `& 0x8000) != 0)
        {
            cy = dd_sub(cy, dd_scale(zoom, pan_speed * dt));
        };

        if ((dn_state `& 0x8000) != 0)
        {
            cy = dd_add(cy, dd_scale(zoom, pan_speed * dt));
        };

        // Adjust lambda (Julia mode only)
        if (mode == 1)
        {
            if ((j_state `& 0x8000) != 0)
            {
                lx = dd_sub(lx, dd_pack(c_speed * dt, 0.0));
            };

            if ((l_state `& 0x8000) != 0)
            {
                lx = dd_add(lx, dd_pack(c_speed * dt, 0.0));
            };

            if ((i_state `& 0x8000) != 0)
            {
                ly = dd_add(ly, dd_pack(c_speed * dt, 0.0));
            };

            if ((k_state `& 0x8000) != 0)
            {
                ly = dd_sub(ly, dd_pack(c_speed * dt, 0.0));
            };
        };

        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        half_zoom = dd_scale(zoom, 0.5);
        x_min   = dd_sub(cx, half_zoom);
        y_min   = dd_sub(cy, dd_scale(zoom, (float)cur_h / (float)cur_w * 0.5));
        x_range = zoom;
        y_range = dd_scale(zoom, (float)cur_h / (float)cur_w);

        glBegin(GL_QUADS);
        row = 0;
        while (row < rows)
        {
            col = 0;
            while (col < cols)
            {
                fx = dd_add(x_min, dd_scale(x_range, ((float)col + 0.5) / (float)cols));
                fy = dd_add(y_min, dd_scale(y_range, ((float)row + 0.5) / (float)rows));

                if (mode == 1)
                {
                    iter = lambda_julia(fx, fy, lx, ly, dyn_max_iter);
                }
                else
                {
                    iter = lambda_param(fx, fy, dyn_max_iter);
                };

                iter_to_color(iter, dyn_max_iter, @r, @gv, @b);

                glColor3f(r, gv, b);

                px0 =  -1.0 + 2.0 * (float)(col * tile) / (float)cur_w;
                py0 =   1.0 - 2.0 * (float)(row * tile) / (float)cur_h;
                px1 =  -1.0 + 2.0 * (float)(col * tile + tile) / (float)cur_w;
                py1 =   1.0 - 2.0 * (float)(row * tile + tile) / (float)cur_h;

                glVertex2f(px0, py0);
                glVertex2f(px1, py0);
                glVertex2f(px1, py1);
                glVertex2f(px0, py1);

                col++;
            };
            row++;
        };
        glEnd();

        gl.present();
    };

    gl.__exit();
    win.__exit();

    return 0;
};
