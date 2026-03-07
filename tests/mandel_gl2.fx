#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// Mandelbrot Set - OpenGL Viewer
// W = zoom in, S = zoom out
// ============================================================================

const int WIN_W        = 900;
const int WIN_H        = 900;
const int MAX_ITER     = 1024;
const int TILE_STILL   = 1;   // Tile size when stationary
const int TILE_MOVING  = 4;   // Tile size while a key is held - faster pan/zoom

// Virtual key codes
const int VK_W    = 0x57;
const int VK_S    = 0x53;
const int VK_A    = 0x41;
const int VK_D    = 0x44;
const int VK_UP   = 0x26;
const int VK_DOWN = 0x28;

// ============================================================================
// Double-double arithmetic using Flux array packing.
// A dd (double-double) is two floats packed into a u64: [hi, lo]
// hi holds the main value, lo holds the error term.
// Together they give ~14 decimal digits of precision.
// ============================================================================

// Pack two floats into a u64
def dd_pack(float hi, float lo) -> u64
{
    float[2] parts = [hi, lo];
    return (u64)parts;
};

// Unpack hi part
def dd_hi(u64 dd) -> float
{
    float[2] parts = (float[2])dd;
    return parts[0];
};

// Unpack lo part
def dd_lo(u64 dd) -> float
{
    float[2] parts = (float[2])dd;
    return parts[1];
};

// Add dd + dd, return dd
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

// Subtract dd - dd, return dd
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

// Multiply dd * dd, return dd
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

// Scale dd by a float, return dd
def dd_scale(u64 a, float s) -> u64
{
    return dd_pack(dd_hi(a) * s, dd_lo(a) * s);
};

// Compute Mandelbrot iteration count using double-double precision
def mandelbrot(u64 x0, u64 y0, int max_iter) -> int
{
    u64 x, y, xx, yy, xtemp;
    float cx, cy, q, xhi, yhi, xxhi, yyhi;
    int iter;

    // Cardioid and period-2 bulb check using hi parts only (float precision sufficient)
    // Points inside either region are guaranteed to never escape - skip iteration entirely
    cx = dd_hi(x0) - 0.25;
    cy = dd_hi(y0);
    q  = cx * cx + cy * cy;
    // Main cardioid: q*(q + cx) < cy*cy*0.25
    if (q * (q + cx) < cy * cy * 0.25) { return max_iter; };
    // Period-2 bulb: (x+1)^2 + y^2 < 1/16
    cx = dd_hi(x0) + 1.0;
    if (cx * cx + cy * cy < 0.0625) { return max_iter; };

    x    = dd_pack(0.0, 0.0);
    y    = dd_pack(0.0, 0.0);
    iter = 0;

    while (iter < max_iter)
    {
        xx    = dd_mul(x, x);
        yy    = dd_mul(y, y);
        // Use hi parts only for the magnitude bailout check - avoids a full dd_add
        xxhi  = dd_hi(xx);
        yyhi  = dd_hi(yy);
        if (xxhi + yyhi > 4.0) { return iter; };
        xtemp = dd_add(dd_sub(xx, yy), x0);
        y     = dd_add(dd_scale(dd_mul(x, y), 2.0), y0);
        x     = xtemp;
        iter++;
    };

    return iter;
};

// Map iteration count to an RGB color using a smooth palette
def iter_to_color(int iter, int max_iter, float* r, float* g, float* b) -> void
{
    float t, s;

    if (iter == max_iter)
    {
        // Inside the set - black
        *r = 0.0;
        *g = 0.0;
        *b = 0.0;
        return;
    };

    // t in [0,1] across one 64-step cycle - always positive
    t = (float)(iter % 64) / 63.0;

    // First half: blue -> cyan (r=0, g rises 0->1, b stays 1)
    // Second half: cyan -> orange (r rises, g falls slightly, b falls)
    if (t < 0.5)
    {
        s = t * 2.0;
        *r = 0.0;
        *g = s;
        *b = 1.0;
    }
    else
    {
        s = (t - 0.5) * 2.0;
        *r = s;
        *g = 1.0 - s * 0.5;
        *b = 1.0 - s;
    };

    return;
};

extern def !!GetTickCount() -> DWORD;

def main() -> int
{
    Window win( "Mandelbrot Set - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    // Use identity matrix - emit vertices directly in NDC [-1, 1]
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);

    // View parameters as double-double (u64 = packed float[hi, lo])
    u64 cx, cy, zoom, half_zoom, x_min, y_min,
        x_range, y_range, fx, fy;

    cx   = dd_pack(-0.5, 0.0);
    cy   = dd_pack( 0.0, 0.0);
    zoom = dd_pack( 3.0, 0.0);

    // Scalar control parameters stay float
    float zoom_speed, pan_speed, dt, zoom_hi;
    zoom_speed = 1.5;
    pan_speed  = 0.6;

    // NDC quad corners and color
    float px0, px1, py0, py1,
          r, gv, b;

    // TILE and max_iter adapt based on whether any key is held:
    // moving = coarser tiles + fewer iterations for responsive panning/zooming
    int tile, dyn_max_iter;
    int cols, rows, row, col, iter,
        cur_w, cur_h;
    bool moving;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    WORD w_state, s_state, a_state, d_state, up_state, dn_state;

    while (win.process_messages())
    {
        // Delta time
        t_now  = GetTickCount();
        dt     = (float)(t_now - t_last) / 1000.0;
        t_last = t_now;
        // Clamp dt so a stall doesn't cause a huge jump
        if (dt > 0.1) { dt = 0.1; };

        // Query actual client area each frame so resize/maximize works
        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };

        // Update viewport to match current window size
        glViewport(0, 0, cur_w, cur_h);

        w_state  = GetAsyncKeyState(VK_W);
        s_state  = GetAsyncKeyState(VK_S);
        a_state  = GetAsyncKeyState(VK_A);
        d_state  = GetAsyncKeyState(VK_D);
        up_state = GetAsyncKeyState(VK_UP);
        dn_state = GetAsyncKeyState(VK_DOWN);

        // Detect if any movement key is held for adaptive quality
        moving = ((w_state  `& 0x8000) != 0) |
                 ((s_state  `& 0x8000) != 0) |
                 ((a_state  `& 0x8000) != 0) |
                 ((d_state  `& 0x8000) != 0) |
                 ((up_state `& 0x8000) != 0) |
                 ((dn_state `& 0x8000) != 0);

        // Coarser tile + fewer iters while navigating, full quality when still
        tile = moving ? TILE_MOVING : TILE_STILL;

        cols = cur_w / tile;
        rows = cur_h / tile;
        if (cols < 1) { cols = 1; };
        if (rows < 1) { rows = 1; };

        // Scale max iterations with zoom depth: shallow zoom needs far fewer iters.
        // zoom_hi ranges from ~8.0 (fully out) to ~0.0000000001 (deep in).
        // At zoom 8 cap at 128; at zoom 1 cap at 256; deep zoom uses full MAX_ITER.
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
        // While moving, halve the iteration budget on top of tile coarsening
        if (moving) { dyn_max_iter = dyn_max_iter >> 1; };

        if ((w_state `& 0x8000) != 0)
        {
            zoom   = dd_scale(zoom, 1.0 - zoom_speed * dt);
            if (dd_hi(zoom) < 0.0000000001) { zoom = dd_pack(0.0000000001, 0.0); };
        };

        if ((s_state `& 0x8000) != 0)
        {
            zoom   = dd_scale(zoom, 1.0 + zoom_speed * dt);
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

        // Clear
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        // Render Mandelbrot as colored quads - all complex math in double-double
        half_zoom = dd_scale(zoom, 0.5);
        x_min   = dd_sub(cx, half_zoom);
        y_min   = dd_sub(cy, dd_scale(zoom, (float)cur_h / (float)cur_w * 0.5));
        x_range = zoom;
        y_range = dd_scale(zoom, (float)cur_h / (float)cur_w);

        // Batch all quads into a single draw call - one glBegin/glEnd for the whole frame
        glBegin(GL_QUADS);
        row = 0;
        while (row < rows)
        {
            col = 0;
            while (col < cols)
            {
                fx = dd_add(x_min, dd_scale(x_range, ((float)col + 0.5) / (float)cols));
                fy = dd_add(y_min, dd_scale(y_range, ((float)row + 0.5) / (float)rows));

                iter = mandelbrot(fx, fy, dyn_max_iter);

                iter_to_color(iter, dyn_max_iter, @r, @gv, @b);

                glColor3f(r, gv, b);

                // Map tile to NDC [-1, 1] using live window dimensions
                // Y is inverted: row 0 = top of screen = NDC +1
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
