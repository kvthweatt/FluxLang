#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// Phoenix Fractal - OpenGL Viewer
// Discovered by Shigehiro Ushiki (1988)
//
// Formula: z_{n+1} = z_n^2 + c + p * z_{n-1}
// Initial conditions:
//   z_{-1} = Im(pixel) + Re(pixel)*i   (swapped real/imaginary of the pixel)
//   z_{-2} = 0
//
// Two display modes (Tab to toggle):
//   Julia mode     - c and p fixed, pixel = z_{-1} initial point
//   Parameter mode - pixel = c (real part), p fixed; z_{-1} = pixel swapped
//
// Navigation:
//   W / S        = zoom in / out
//   A / D        = pan left / right
//   Up / Down    = pan up / down
//   J / L        = shift c real part      (Julia mode)
//   I / K        = shift c imaginary part (Julia mode)
//   N / M        = shift p real part      (Julia mode)
//   Tab          = toggle Julia <-> Parameter plane
// ============================================================================

const int WIN_W        = 900;
const int WIN_H        = 900;
const int MAX_ITER     = 1024;
const int TILE_STILL   = 1;
const int TILE_MOVING  = 4;

const int VK_W   = 0x57;
const int VK_S   = 0x53;
const int VK_A   = 0x41;
const int VK_D   = 0x44;
const int VK_J   = 0x4A;
const int VK_L   = 0x4C;
const int VK_I   = 0x49;
const int VK_K   = 0x4B;
const int VK_N   = 0x4E;
const int VK_M   = 0x4D;
const int VK_TAB = 0x09;
const int VK_UP   = 0x26;
const int VK_DOWN = 0x28;

// ============================================================================
// Double-double arithmetic
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
// Phoenix iteration
//
// z_{n+1} = z_n^2 + c + p * z_{n-1}
//
// Expanding in real/imaginary (c = cr + ci*i, p treated as real scalar here
// but stored as dd for generality; we only use dd_scale with dd_hi(p)):
//
//   z_n^2:
//     real = zx^2 - zy^2
//     imag = 2 * zx * zy
//
//   p * z_{n-1}  (p complex: pr + pi*i, z_prev = px + py*i):
//     real = pr*px - pi*py
//     imag = pr*py + pi*px
//
//   full:
//     new_zx = (zx^2 - zy^2) + cr + pr*px - pi*py
//     new_zy = (2*zx*zy)     + ci + pr*py + pi*px
//
// Initial conditions:
//   pixel = (fx, fy)  [the screen point being tested]
//   z_{-1} = fy + fx*i    (Im + Re*i  - the canonical phoenix swap)
//   z_{-2} = 0 + 0*i
// ============================================================================

def phoenix(u64 fx, u64 fy,
            u64 cr, u64 ci,
            u64 pr, u64 pi,
            int max_iter) -> int
{
    u64  zx, zy, px, py, nzx, nzy;
    u64  zx2, zy2;
    float zxh, zyh;
    float prh, pih;
    int iter;

    // z_{-1}: swapped pixel (Im + Re*i)
    zx = fy;
    zy = fx;

    // z_{-2} = 0
    px = dd_pack(0.0, 0.0);
    py = dd_pack(0.0, 0.0);

    prh = dd_hi(pr);
    pih = dd_hi(pi);

    iter = 0;

    while (iter < max_iter)
    {
        zx2 = dd_mul(zx, zx);
        zy2 = dd_mul(zy, zy);

        // Bailout: |z|^2 > 4
        zxh = dd_hi(zx2);
        zyh = dd_hi(zy2);
        if (zxh + zyh > 4.0) { return iter; };

        // new_zx = zx^2 - zy^2 + cr + pr*px - pi*py
        nzx = dd_add(
                dd_add(dd_sub(zx2, zy2), cr),
                dd_sub(dd_scale(px, prh), dd_scale(py, pih))
              );

        // new_zy = 2*zx*zy + ci + pr*py + pi*px
        nzy = dd_add(
                dd_add(dd_scale(dd_mul(zx, zy), 2.0), ci),
                dd_add(dd_scale(py, prh), dd_scale(px, pih))
              );

        // Shift: prev becomes current, current becomes new
        px = zx;
        py = zy;
        zx = nzx;
        zy = nzy;

        iter++;
    };

    return iter;
};

// Parameter-plane mode: pixel drives c (real part only for classic view),
// p is fixed.  z_{-1} uses the same phoenix swap on the pixel.
def phoenix_param(u64 fx, u64 fy,
                  u64 pr, u64 pi,
                  int max_iter) -> int
{
    // In parameter mode the pixel IS c (cr = fx, ci = fy)
    // and we use the canonical phoenix initial condition on the pixel
    return phoenix(fx, fy, fx, fy, pr, pi, max_iter);
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

    t = (float)(iter % 64) / 63.0;

    // First half: deep red -> bright orange
    // Second half: bright orange -> gold -> white tip
    if (t < 0.5)
    {
        s = t * 2.0;
        *r = 0.5 + s * 0.5;
        *g = s * 0.5;
        *b = 0.0;
    }
    else
    {
        s = (t - 0.5) * 2.0;
        *r = 1.0;
        *g = 0.5 + s * 0.5;
        *b = s * 0.7;
    };

    return;
};

extern def !!GetTickCount() -> DWORD;

def main() -> int
{
    Window win( "Phoenix Fractal - W/S: Zoom  A/D/Up/Down: Pan  J/L: Re(c)  I/K: Im(c)  N/M: Re(p)  Tab: Mode\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);

    // View parameters
    u64 cx, cy, zoom, half_zoom, x_min, y_min,
        x_range, y_range, fx, fy;

    // Start in Julia mode on the classic phoenix: c=0.5667, p=-0.5
    cx   = dd_pack( 0.0, 0.0);
    cy   = dd_pack( 0.0, 0.0);
    zoom = dd_pack( 2.7, 0.0);

    // c and p parameters (complex; p is typically real)
    u64 cr, ci, pr, pi_p;
    cr   = dd_pack( 0.5667, 0.0);
    ci   = dd_pack( 0.0,    0.0);
    pr   = dd_pack(-0.5,    0.0);
    pi_p = dd_pack( 0.0,    0.0);

    // 0 = Julia mode, 1 = parameter plane
    int mode;
    mode = 0;

    float zoom_speed, pan_speed, c_speed, dt, zoom_hi;
    zoom_speed = 1.5;
    pan_speed  = 0.6;
    c_speed    = 0.3;

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
         n_state, m_state,
         tab_state, tab_prev;

    tab_prev = 0;

    while (win.process_messages())
    {
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
        n_state   = GetAsyncKeyState(VK_N);
        m_state   = GetAsyncKeyState(VK_M);
        tab_state = GetAsyncKeyState(VK_TAB);

        // Toggle mode on Tab rising edge
        if (((tab_state `& 0x8000) != 0) `& ((tab_prev `& 0x8000) == 0))
        {
            if (mode == 0)
            {
                mode = 1;
                cx   = dd_pack( 0.0, 0.0);
                cy   = dd_pack( 0.0, 0.0);
                zoom = dd_pack( 3.0, 0.0);
            }
            else
            {
                mode = 0;
                cx   = dd_pack( 0.0, 0.0);
                cy   = dd_pack( 0.0, 0.0);
                zoom = dd_pack( 2.7, 0.0);
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
                 ((k_state  `& 0x8000) != 0) |
                 ((n_state  `& 0x8000) != 0) |
                 ((m_state  `& 0x8000) != 0);

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

        // Adjust c and p in Julia mode
        if (mode == 0)
        {
            if ((j_state `& 0x8000) != 0)
            {
                cr = dd_sub(cr, dd_pack(c_speed * dt, 0.0));
            };

            if ((l_state `& 0x8000) != 0)
            {
                cr = dd_add(cr, dd_pack(c_speed * dt, 0.0));
            };

            if ((i_state `& 0x8000) != 0)
            {
                ci = dd_add(ci, dd_pack(c_speed * dt, 0.0));
            };

            if ((k_state `& 0x8000) != 0)
            {
                ci = dd_sub(ci, dd_pack(c_speed * dt, 0.0));
            };

            if ((n_state `& 0x8000) != 0)
            {
                pr = dd_sub(pr, dd_pack(c_speed * dt, 0.0));
            };

            if ((m_state `& 0x8000) != 0)
            {
                pr = dd_add(pr, dd_pack(c_speed * dt, 0.0));
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

                if (mode == 0)
                {
                    iter = phoenix(fx, fy, cr, ci, pr, pi_p, dyn_max_iter);
                }
                else
                {
                    iter = phoenix_param(fx, fy, pr, pi_p, dyn_max_iter);
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
