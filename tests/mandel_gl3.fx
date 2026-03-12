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
const int TILE_STILL   = 1;
const int TILE_MOVING  = 4;

const int VK_W    = 0x57;
const int VK_S    = 0x53;
const int VK_A    = 0x41;
const int VK_D    = 0x44;
const int VK_UP   = 0x26;
const int VK_DOWN = 0x28;

// ============================================================================
// All Decimals live here - heap allocated so pointer slots never on main stack
// ============================================================================
struct ViewState
{
    // Constants
    Decimal K_one;
    Decimal K_two;
    Decimal K_four;
    Decimal K_quarter;
    Decimal K_one16th;
    Decimal K_half;
    Decimal K_zoom_speed;
    Decimal K_pan_speed;
    // Scratch numerator/denominator
    Decimal nd;
    Decimal dd;
    // View state
    Decimal cx;
    Decimal cy;
    Decimal zoom;
    Decimal zoom_min;
    Decimal zoom_max;
    // Zoom depth thresholds
    Decimal thr_a;
    Decimal thr_b;
    Decimal thr_c;
    Decimal thr_d;
    // Per-frame working values
    Decimal half_zoom;
    Decimal x_min;
    Decimal y_min;
    Decimal x_range;
    Decimal y_range;
    Decimal x_step;
    Decimal y_step;
    Decimal fx_start;
    Decimal row_y;
    Decimal fx;
    Decimal fy;
    Decimal tmp_d;
    Decimal step;
    Decimal dt_d;
};

// ============================================================================
// Mandelbrot iteration - all Decimals in MandState to keep off call stack
// ============================================================================
struct MandState
{
    Decimal x;
    Decimal y;
    Decimal xx;
    Decimal yy;
    Decimal xy;
    Decimal xtemp;
    Decimal mag;
    Decimal tmp;
    Decimal cx;
    Decimal cy;
    Decimal q;
    Decimal qcx;
    Decimal cy2;
    Decimal bulb;
};

def mandelbrot(Decimal* x0, Decimal* y0, int max_iter,
               Decimal* K_one, Decimal* K_quarter, Decimal* K_one16th,
               Decimal* K_two, Decimal* K_four) -> int
{
    MandState* m = (MandState*)fmalloc(sizeof(MandState));
    int iter;
    int result;

    // Cardioid check
    decimal_sub(@m.cx, x0, K_quarter);
    decimal_copy(@m.cy, y0);
    decimal_mul(@m.xx, @m.cx, @m.cx);
    decimal_mul(@m.yy, @m.cy, @m.cy);
    decimal_add(@m.q, @m.xx, @m.yy);
    decimal_add(@m.qcx, @m.q, @m.cx);
    decimal_mul(@m.tmp, @m.q, @m.qcx);
    decimal_mul(@m.cy2, @m.yy, K_quarter);
    if (decimal_cmp(@m.tmp, @m.cy2) < 0)
    {
        result = max_iter;
    }
    else
    {
        // Period-2 bulb
        decimal_add(@m.cx, x0, K_one);
        decimal_mul(@m.xx, @m.cx, @m.cx);
        decimal_mul(@m.yy, y0, y0);
        decimal_add(@m.bulb, @m.xx, @m.yy);
        if (decimal_cmp(@m.bulb, K_one16th) < 0)
        {
            result = max_iter;
        }
        else
        {
            decimal_zero(@m.x);
            decimal_zero(@m.y);

            iter = 0;
            result = max_iter;
            while (iter < max_iter)
            {
                decimal_mul(@m.xx, @m.x, @m.x);
                decimal_mul(@m.yy, @m.y, @m.y);
                decimal_add(@m.mag, @m.xx, @m.yy);
                if (decimal_cmp(@m.mag, K_four) > 0)
                {
                    result = iter;
                    iter = max_iter;
                }
                else
                {
                    decimal_sub(@m.tmp, @m.xx, @m.yy);
                    decimal_add(@m.xtemp, @m.tmp, x0);
                    decimal_mul(@m.xy, @m.x, @m.y);
                    decimal_mul(@m.tmp, @m.xy, K_two);
                    decimal_add(@m.y, @m.tmp, y0);
                    decimal_copy(@m.x, @m.xtemp);
                    iter++;
                };
            };
        };
    };

    (void)m;
    return result;
};

// Map iteration count to RGB
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
    Window win("Mandelbrot Set (Decimal) - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);

    decimal_set_precision(40);

    ViewState* v = (ViewState*)fmalloc(sizeof(ViewState));

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    decimal_from_i64(@v.K_one,  1);
    decimal_from_i64(@v.K_two,  2);
    decimal_from_i64(@v.K_four, 4);

    decimal_from_i64(@v.nd, 1);
    decimal_from_i64(@v.dd, 4);
    decimal_div(@v.K_quarter, @v.nd, @v.dd);

    decimal_from_i64(@v.nd, 1);
    decimal_from_i64(@v.dd, 16);
    decimal_div(@v.K_one16th, @v.nd, @v.dd);

    decimal_from_i64(@v.nd, 1);
    decimal_from_i64(@v.dd, 2);
    decimal_div(@v.K_half, @v.nd, @v.dd);

    decimal_from_i64(@v.nd, 3);
    decimal_from_i64(@v.dd, 2);
    decimal_div(@v.K_zoom_speed, @v.nd, @v.dd);

    decimal_from_i64(@v.nd, 3);
    decimal_from_i64(@v.dd, 5);
    decimal_div(@v.K_pan_speed, @v.nd, @v.dd);

    // -------------------------------------------------------------------------
    // View state
    // -------------------------------------------------------------------------
    decimal_from_i64(@v.nd, -1);
    decimal_from_i64(@v.dd, 2);
    decimal_div(@v.cx, @v.nd, @v.dd);
    decimal_zero(@v.cy);
    decimal_from_i64(@v.zoom, 3);

    decimal_from_string(@v.zoom_min, "1E-38\0");
    decimal_from_i64(@v.zoom_max, 8);

    decimal_from_i64(@v.thr_a, 1);
    decimal_from_i64(@v.nd, 1); decimal_from_i64(@v.dd, 100);
    decimal_div(@v.thr_b, @v.nd, @v.dd);
    decimal_from_i64(@v.nd, 1); decimal_from_i64(@v.dd, 10000);
    decimal_div(@v.thr_c, @v.nd, @v.dd);
    decimal_from_string(@v.thr_d, "1E-12\0");

    // -------------------------------------------------------------------------
    // Main loop
    // -------------------------------------------------------------------------
    float px0, px1, py0, py1, r, gv, b;
    int tile, dyn_max_iter, cols, rows, row, col, iter,
        cur_w, cur_h, elapsed_ms;
    bool moving;
    DWORD t_now, t_last;
    t_last = GetTickCount();
    RECT client_rect;
    WORD w_state, s_state, a_state, d_state, up_state, dn_state;

    while (win.process_messages())
    {
        t_now = GetTickCount();
        elapsed_ms = (int)(t_now - t_last);
        t_last = t_now;
        if (elapsed_ms > 100) { elapsed_ms = 100; };
        decimal_from_i64(@v.nd, (i64)elapsed_ms);
        decimal_from_i64(@v.dd, 1000);
        decimal_div(@v.dt_d, @v.nd, @v.dd);

        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };

        glViewport(0, 0, cur_w, cur_h);

        w_state  = GetAsyncKeyState(VK_W);
        s_state  = GetAsyncKeyState(VK_S);
        a_state  = GetAsyncKeyState(VK_A);
        d_state  = GetAsyncKeyState(VK_D);
        up_state = GetAsyncKeyState(VK_UP);
        dn_state = GetAsyncKeyState(VK_DOWN);

        moving = ((w_state  `& 0x8000) != 0) |
                 ((s_state  `& 0x8000) != 0) |
                 ((a_state  `& 0x8000) != 0) |
                 ((d_state  `& 0x8000) != 0) |
                 ((up_state `& 0x8000) != 0) |
                 ((dn_state `& 0x8000) != 0);

        tile = moving ? TILE_MOVING : TILE_STILL;
        cols = cur_w / tile;
        rows = cur_h / tile;
        if (cols < 1) { cols = 1; };
        if (rows < 1) { rows = 1; };

        if (decimal_cmp(@v.zoom, @v.thr_a) > 0)      { dyn_max_iter = 128; }
        elif (decimal_cmp(@v.zoom, @v.thr_b) > 0)    { dyn_max_iter = 256; }
        elif (decimal_cmp(@v.zoom, @v.thr_c) > 0)    { dyn_max_iter = 512; }
        elif (decimal_cmp(@v.zoom, @v.thr_d) > 0)    { dyn_max_iter = 1024; }
        else                                           { dyn_max_iter = MAX_ITER; };
        if (moving) { dyn_max_iter = dyn_max_iter >> 1; };

        if ((w_state `& 0x8000) != 0)
        {
            decimal_mul(@v.step, @v.zoom, @v.K_zoom_speed);
            decimal_mul(@v.step, @v.step, @v.dt_d);
            decimal_sub(@v.tmp_d, @v.zoom, @v.step);
            decimal_copy(@v.zoom, @v.tmp_d);
            if (decimal_cmp(@v.zoom, @v.zoom_min) < 0) { decimal_copy(@v.zoom, @v.zoom_min); };
        };

        if ((s_state `& 0x8000) != 0)
        {
            decimal_mul(@v.step, @v.zoom, @v.K_zoom_speed);
            decimal_mul(@v.step, @v.step, @v.dt_d);
            decimal_add(@v.tmp_d, @v.zoom, @v.step);
            decimal_copy(@v.zoom, @v.tmp_d);
            if (decimal_cmp(@v.zoom, @v.zoom_max) > 0) { decimal_copy(@v.zoom, @v.zoom_max); };
        };

        if ((a_state `& 0x8000) != 0)
        {
            decimal_mul(@v.step, @v.zoom, @v.K_pan_speed);
            decimal_mul(@v.step, @v.step, @v.dt_d);
            decimal_sub(@v.tmp_d, @v.cx, @v.step);
            decimal_copy(@v.cx, @v.tmp_d);
        };

        if ((d_state `& 0x8000) != 0)
        {
            decimal_mul(@v.step, @v.zoom, @v.K_pan_speed);
            decimal_mul(@v.step, @v.step, @v.dt_d);
            decimal_add(@v.tmp_d, @v.cx, @v.step);
            decimal_copy(@v.cx, @v.tmp_d);
        };

        if ((up_state `& 0x8000) != 0)
        {
            decimal_mul(@v.step, @v.zoom, @v.K_pan_speed);
            decimal_mul(@v.step, @v.step, @v.dt_d);
            decimal_sub(@v.tmp_d, @v.cy, @v.step);
            decimal_copy(@v.cy, @v.tmp_d);
        };

        if ((dn_state `& 0x8000) != 0)
        {
            decimal_mul(@v.step, @v.zoom, @v.K_pan_speed);
            decimal_mul(@v.step, @v.step, @v.dt_d);
            decimal_add(@v.tmp_d, @v.cy, @v.step);
            decimal_copy(@v.cy, @v.tmp_d);
        };

        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        // Compute viewport extents
        decimal_mul(@v.half_zoom, @v.zoom, @v.K_half);
        decimal_sub(@v.x_min, @v.cx, @v.half_zoom);

        decimal_from_i64(@v.nd, (i64)cur_h);
        decimal_from_i64(@v.dd, (i64)cur_w);
        decimal_div(@v.tmp_d, @v.nd, @v.dd);
        decimal_mul(@v.y_range, @v.zoom, @v.tmp_d);

        decimal_mul(@v.tmp_d, @v.y_range, @v.K_half);
        decimal_sub(@v.y_min, @v.cy, @v.tmp_d);

        decimal_copy(@v.x_range, @v.zoom);

        decimal_from_i64(@v.nd, 1);
        decimal_from_i64(@v.dd, (i64)cols);
        decimal_div(@v.x_step, @v.nd, @v.dd);
        decimal_mul(@v.x_step, @v.x_range, @v.x_step);

        decimal_from_i64(@v.nd, 1);
        decimal_from_i64(@v.dd, (i64)rows);
        decimal_div(@v.y_step, @v.nd, @v.dd);
        decimal_mul(@v.y_step, @v.y_range, @v.y_step);

        decimal_mul(@v.tmp_d, @v.x_step, @v.K_half);
        decimal_add(@v.fx_start, @v.x_min, @v.tmp_d);

        decimal_mul(@v.tmp_d, @v.y_step, @v.K_half);
        decimal_add(@v.row_y, @v.y_min, @v.tmp_d);

        glBegin(GL_QUADS);
        row = 0;
        while (row < rows)
        {
            decimal_copy(@v.fx, @v.fx_start);
            col = 0;
            while (col < cols)
            {
                decimal_copy(@v.fy, @v.row_y);

                iter = mandelbrot(@v.fx, @v.fy, dyn_max_iter,
                                  @v.K_one, @v.K_quarter, @v.K_one16th,
                                  @v.K_two, @v.K_four);

                iter_to_color(iter, dyn_max_iter, @r, @gv, @b);
                glColor3f(r, gv, b);

                px0 = -1.0 + 2.0 * (float)(col * tile) / (float)cur_w;
                py0 =  1.0 - 2.0 * (float)(row * tile) / (float)cur_h;
                px1 = -1.0 + 2.0 * (float)(col * tile + tile) / (float)cur_w;
                py1 =  1.0 - 2.0 * (float)(row * tile + tile) / (float)cur_h;

                glVertex2f(px0, py0);
                glVertex2f(px1, py0);
                glVertex2f(px1, py1);
                glVertex2f(px0, py1);

                decimal_add(@v.tmp_d, @v.fx, @v.x_step);
                decimal_copy(@v.fx, @v.tmp_d);
                col++;
            };
            decimal_add(@v.tmp_d, @v.row_y, @v.y_step);
            decimal_copy(@v.row_y, @v.tmp_d);
            row++;
        };
        glEnd();

        gl.present();
    };

    (void)v;
    gl.__exit();
    win.__exit();

    return 0;
};
