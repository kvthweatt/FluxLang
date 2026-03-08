#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx", "bigint.fx", "decimal.fx";

using standard::system::windows;
using standard::math;
using math::bigint;
using math::decimal;

// ============================================================================
// Mandelbrot Set - OpenGL Viewer  (arbitrary-precision via Decimal library)
// W = zoom in, S = zoom out
// A/D = pan X,  Up/Down = pan Y
// ============================================================================

const int WIN_W        = 900;
const int WIN_H        = 900;
const int MAX_ITER     = 2048;
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
// Mandelbrot iteration - all constants passed in, computed once by caller
// ============================================================================
def mandelbrot(Decimal* x0, Decimal* y0, int max_iter,
               Decimal* K_one, Decimal* K_quarter, Decimal* K_one16th,
               Decimal* K_two, Decimal* K_four) -> int
{
    Decimal x, y, xx, yy, xtemp, mag, tmp;
    Decimal cx, cy, q, qcx, cy2, bulb;
    int iter;

    // Cardioid check: q*(q+cx) < cy^2 * 0.25
    // where cx = x0 - 0.25, cy = y0
    decimal_sub(@cx, x0, K_quarter);      // cx = x0 - 0.25
    decimal_copy(@cy, y0);                // cy = y0

    decimal_mul(@xx, @cx, @cx);           // cx^2
    decimal_mul(@yy, @cy, @cy);           // cy^2
    decimal_add(@q, @xx, @yy);            // q = cx^2 + cy^2
    decimal_add(@qcx, @q, @cx);           // q + cx
    decimal_mul(@tmp, @q, @qcx);          // q*(q+cx)
    decimal_mul(@cy2, @yy, K_quarter);    // cy^2 * 0.25
    if (decimal_cmp(@tmp, @cy2) < 0) { return max_iter; };

    // Period-2 bulb: (x0+1)^2 + y0^2 < 1/16
    decimal_add(@cx, x0, K_one);           // cx = x0 + 1
    decimal_mul(@xx, @cx, @cx);           // (x0+1)^2
    decimal_mul(@yy, y0, y0);             // y0^2
    decimal_add(@bulb, @xx, @yy);
    if (decimal_cmp(@bulb, K_one16th) < 0) { return max_iter; };

    decimal_zero(@x);
    decimal_zero(@y);

    iter = 0;
    while (iter < max_iter)
    {
        // xx = x*x
        decimal_mul(@xx, @x, @x);
        // yy = y*y
        decimal_mul(@yy, @y, @y);

        // Bailout: |z|^2 = xx + yy > 4
        decimal_add(@mag, @xx, @yy);
        if (decimal_cmp(@mag, K_four) > 0) { return iter; };

        // xtemp = xx - yy + x0
        decimal_sub(@tmp, @xx, @yy);
        decimal_add(@xtemp, @tmp, x0);

        // y = 2*x*y + y0
        decimal_mul(@xtemp, @x, @y);
        decimal_mul(@tmp, @xtemp, K_two);
        decimal_add(@y, @tmp, y0);

        // x = xtemp
        decimal_copy(@x, @xtemp);

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
    Window win( "Mandelbrot Set (Decimal) - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    // Use identity matrix - emit vertices directly in NDC [-1, 1]
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);

    // Precision: 40 decimal digits gives ~10^-40 zoom depth
    decimal_set_precision(40);

    // -------------------------------------------------------------------------
    // One-time constants - computed once here, never recomputed
    // -------------------------------------------------------------------------
    Decimal K_one, K_two, K_four, K_quarter, K_one16th;
    Decimal K_half, K_zoom_speed, K_pan_speed;
    decimal_from_i64(@K_one,  1);
    decimal_from_i64(@K_two,  2);
    decimal_from_i64(@K_four, 4);

    // 1/4
    Decimal nd, dd;
    decimal_from_i64(@nd, 1);
    decimal_from_i64(@dd, 4);
    decimal_div(@K_quarter, @nd, @dd);

    // 1/16
    decimal_from_i64(@nd, 1);
    decimal_from_i64(@dd, 16);
    decimal_div(@K_one16th, @nd, @dd);

    // 1/2
    decimal_from_i64(@nd, 1);
    decimal_from_i64(@dd, 2);
    decimal_div(@K_half, @nd, @dd);

    // zoom_speed = 3/2
    decimal_from_i64(@nd, 3);
    decimal_from_i64(@dd, 2);
    decimal_div(@K_zoom_speed, @nd, @dd);

    // pan_speed = 3/5
    decimal_from_i64(@nd, 3);
    decimal_from_i64(@dd, 5);
    decimal_div(@K_pan_speed, @nd, @dd);

    // -------------------------------------------------------------------------
    // View state
    // -------------------------------------------------------------------------
    Decimal cx, cy, zoom;
    decimal_from_i64(@nd, -1);
    decimal_from_i64(@dd, 2);
    decimal_div(@cx, @nd, @dd);    // cx = -0.5
    decimal_zero(@cy);
    decimal_from_i64(@zoom, 3);

    // Zoom limits: min = 1/10^38, max = 8
    Decimal zoom_min, zoom_max;
    decimal_from_string(@zoom_min, "1E-38\0");
    decimal_from_i64(@zoom_max, 8);

    // Zoom depth thresholds for dyn_max_iter (compared with decimal_cmp)
    Decimal thr_a, thr_b, thr_c, thr_d;
    decimal_from_i64(@thr_a, 1);
    decimal_from_i64(@nd, 1); decimal_from_i64(@dd, 100);
    decimal_div(@thr_b, @nd, @dd);
    decimal_from_i64(@nd, 1); decimal_from_i64(@dd, 10000);
    decimal_div(@thr_c, @nd, @dd);
    decimal_from_string(@thr_d, "1E-12\0");

    // Working Decimals
    Decimal half_zoom, x_min, y_min, x_range, y_range,
            x_step, y_step, fx_start, row_y,
            fx, fy, tmp_d, step, dt_d;

    // NDC quad corners and color
    float px0, px1, py0, py1,
          r, gv, b;

    // TILE and max_iter adapt based on whether any key is held
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
        // Delta time as Decimal: dt_d = elapsed_ms / 1000
        t_now  = GetTickCount();
        int elapsed_ms = (int)(t_now - t_last);
        t_last = t_now;
        // Clamp elapsed_ms so a stall doesn't cause a huge jump (max 100 ms)
        if (elapsed_ms > 100) { elapsed_ms = 100; };
        decimal_from_i64(@nd, (i64)elapsed_ms);
        decimal_from_i64(@dd, 1000);
        decimal_div(@dt_d, @nd, @dd);

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

        // Scale max iterations with zoom depth via Decimal comparisons
        if (decimal_cmp(@zoom, @thr_a) > 0)
        {
            dyn_max_iter = 128;
        }
        elif (decimal_cmp(@zoom, @thr_b) > 0)
        {
            dyn_max_iter = 256;
        }
        elif (decimal_cmp(@zoom, @thr_c) > 0)
        {
            dyn_max_iter = 512;
        }
        elif (decimal_cmp(@zoom, @thr_d) > 0)
        {
            dyn_max_iter = 1024;
        }
        else
        {
            dyn_max_iter = MAX_ITER;
        };
        // While moving, halve the iteration budget on top of tile coarsening
        if (moving) { dyn_max_iter = dyn_max_iter >> 1; };

        if ((w_state `& 0x8000) != 0)
        {
            // zoom -= zoom * zoom_speed * dt
            decimal_mul(@step, @zoom, @K_zoom_speed);
            decimal_mul(@step, @step, @dt_d);
            decimal_sub(@tmp_d, @zoom, @step);
            decimal_copy(@zoom, @tmp_d);
            if (decimal_cmp(@zoom, @zoom_min) < 0)
            {
                decimal_copy(@zoom, @zoom_min);
            };
        };

        if ((s_state `& 0x8000) != 0)
        {
            // zoom += zoom * zoom_speed * dt
            decimal_mul(@step, @zoom, @K_zoom_speed);
            decimal_mul(@step, @step, @dt_d);
            decimal_add(@tmp_d, @zoom, @step);
            decimal_copy(@zoom, @tmp_d);
            if (decimal_cmp(@zoom, @zoom_max) > 0)
            {
                decimal_copy(@zoom, @zoom_max);
            };
        };

        if ((a_state `& 0x8000) != 0)
        {
            // cx -= zoom * pan_speed * dt
            decimal_mul(@step, @zoom, @K_pan_speed);
            decimal_mul(@step, @step, @dt_d);
            decimal_sub(@tmp_d, @cx, @step);
            decimal_copy(@cx, @tmp_d);
        };

        if ((d_state `& 0x8000) != 0)
        {
            // cx += zoom * pan_speed * dt
            decimal_mul(@step, @zoom, @K_pan_speed);
            decimal_mul(@step, @step, @dt_d);
            decimal_add(@tmp_d, @cx, @step);
            decimal_copy(@cx, @tmp_d);
        };

        if ((up_state `& 0x8000) != 0)
        {
            // cy -= zoom * pan_speed * dt
            decimal_mul(@step, @zoom, @K_pan_speed);
            decimal_mul(@step, @step, @dt_d);
            decimal_sub(@tmp_d, @cy, @step);
            decimal_copy(@cy, @tmp_d);
        };

        if ((dn_state `& 0x8000) != 0)
        {
            // cy += zoom * pan_speed * dt
            decimal_mul(@step, @zoom, @K_pan_speed);
            decimal_mul(@step, @step, @dt_d);
            decimal_add(@tmp_d, @cy, @step);
            decimal_copy(@cy, @tmp_d);
        };

        // Clear
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        // Compute viewport extents in Decimal
        // half_zoom = zoom * 0.5
        decimal_mul(@half_zoom, @zoom, @K_half);

        // x_min = cx - half_zoom
        decimal_sub(@x_min, @cx, @half_zoom);

        // y aspect: y_range = zoom * cur_h / cur_w  (integer ratio, one div per frame)
        decimal_from_i64(@nd, (i64)cur_h);
        decimal_from_i64(@dd, (i64)cur_w);
        decimal_div(@tmp_d, @nd, @dd);
        decimal_mul(@y_range, @zoom, @tmp_d);

        // y_min = cy - y_range * 0.5
        decimal_mul(@tmp_d, @y_range, @K_half);
        decimal_sub(@y_min, @cy, @tmp_d);

        // x_range = zoom
        decimal_copy(@x_range, @zoom);

        // Per-tile steps - one div per axis per frame
        decimal_from_i64(@nd, 1);
        decimal_from_i64(@dd, (i64)cols);
        decimal_div(@x_step, @nd, @dd);
        decimal_mul(@x_step, @x_range, @x_step);

        decimal_from_i64(@nd, 1);
        decimal_from_i64(@dd, (i64)rows);
        decimal_div(@y_step, @nd, @dd);
        decimal_mul(@y_step, @y_range, @y_step);

        // First pixel center: x_min + x_step/2,  y_min + y_step/2
        decimal_mul(@tmp_d, @x_step, @K_half);
        decimal_add(@fx_start, @x_min, @tmp_d);

        decimal_mul(@tmp_d, @y_step, @K_half);
        decimal_add(@row_y, @y_min, @tmp_d);

        // Batch all quads into a single draw call - one glBegin/glEnd for the whole frame
        glBegin(GL_QUADS);
        row = 0;
        while (row < rows)
        {
            // Reset fx to first column center for this row
            decimal_copy(@fx, @fx_start);
            col = 0;
            while (col < cols)
            {
                // fy is the current row's y center
                decimal_copy(@fy, @row_y);

                iter = mandelbrot(@fx, @fy, dyn_max_iter,
                                  @K_one, @K_quarter, @K_one16th, @K_two, @K_four);

                iter_to_color(iter, dyn_max_iter, @r, @gv, @b);

                glColor3f(r, gv, b);

                // Map tile to NDC [-1, 1] using live window dimensions
                // Y is inverted: row 0 = top of screen = NDC +1
                // Integer pixel arithmetic cast to float only for OpenGL vertex coords
                px0 =  -1.0 + 2.0 * (float)(col * tile) / (float)cur_w;
                py0 =   1.0 - 2.0 * (float)(row * tile) / (float)cur_h;
                px1 =  -1.0 + 2.0 * (float)(col * tile + tile) / (float)cur_w;
                py1 =   1.0 - 2.0 * (float)(row * tile + tile) / (float)cur_h;

                glVertex2f(px0, py0);
                glVertex2f(px1, py0);
                glVertex2f(px1, py1);
                glVertex2f(px0, py1);

                // Advance to next column
                decimal_add(@tmp_d, @fx, @x_step);
                decimal_copy(@fx, @tmp_d);

                col++;
            };
            // Advance to next row
            decimal_add(@tmp_d, @row_y, @y_step);
            decimal_copy(@row_y, @tmp_d);
            row++;
        };
        glEnd();

        gl.present();
    };

    gl.__exit();
    win.__exit();

    return 0;
};
