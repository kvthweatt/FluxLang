#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx", "threading.fx", "decimal.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;
using standard::atomic;
using standard::threading;
using math::decimal;

// ============================================================================
// Mandelbrot Set - OpenGL Viewer (arbitrary-precision decimal arithmetic)
// W = zoom in, S = zoom out
// A/D = pan X,  Up/Down = pan Y
// ============================================================================

const int WIN_W        = 900,
          WIN_H        = 900,
          MAX_ITER     = 1024,
          TILE_STILL   = 1,   // Tile size when stationary
          TILE_MOVING  = 4,   // Tile size while a key is held - faster pan/zoom
          MAX_THREADS  = 64,

// Virtual key codes
          VK_W    = 0x57,
          VK_S    = 0x53,
          VK_A    = 0x41,
          VK_D    = 0x44,
          VK_UP   = 0x26,
          VK_DOWN = 0x28;

// Compute Mandelbrot iteration count using Decimal precision
def mandelbrot(Decimal* x0, Decimal* y0, int max_iter) -> int
{
    Decimal x, y, xx, yy, xtemp, cx, cy, q,
            tmp, tmp2, tmp3,
            four, two, quarter, one, one_sixteenth;

    int iter;

    decimal_from_string(@four,          "4\0");
    decimal_from_string(@two,           "2\0");
    decimal_from_string(@quarter,       "0.25\0");
    decimal_from_string(@one,           "1\0");
    decimal_from_string(@one_sixteenth, "0.0625\0");

    // Cardioid check: q*(q + cx) < cy*cy*0.25
    // cx = x0 - 0.25
    decimal_sub(@cx, x0, @quarter);
    // cy = y0
    decimal_copy(@cy, y0);
    // q = cx*cx + cy*cy
    decimal_mul(@tmp, @cx, @cx);
    decimal_mul(@tmp2, @cy, @cy);
    decimal_add(@q, @tmp, @tmp2);
    // lhs = q*(q + cx)
    decimal_add(@tmp3, @q, @cx);
    decimal_mul(@tmp, @q, @tmp3);
    // rhs = cy*cy*0.25
    decimal_mul(@tmp2, @tmp2, @quarter);
    if (decimal_cmp(@tmp, @tmp2) < 0) { return max_iter; };

    // Period-2 bulb check: (x0+1)^2 + cy^2 < 1/16
    decimal_add(@cx, x0, @one);
    decimal_mul(@tmp, @cx, @cx);
    decimal_mul(@tmp2, @cy, @cy);
    decimal_add(@tmp3, @tmp, @tmp2);
    if (decimal_cmp(@tmp3, @one_sixteenth) < 0) { return max_iter; };

    decimal_zero(@x);
    decimal_zero(@y);
    iter = 0;

    while (iter < max_iter)
    {
        // xx = x*x,  yy = y*y
        decimal_mul(@xx, @x, @x);
        decimal_mul(@yy, @y, @y);
        // escape: xx + yy > 4
        decimal_add(@tmp, @xx, @yy);
        if (decimal_cmp(@tmp, @four) > 0) { return iter; };
        // xtemp = xx - yy + x0
        decimal_sub(@tmp, @xx, @yy);
        decimal_add(@xtemp, @tmp, x0);
        // y = 2*x*y + y0
        decimal_mul(@tmp, @two, @x);
        decimal_mul(@tmp2, @tmp, @y);
        decimal_add(@y, @tmp2, y0);
        // x = xtemp
        decimal_copy(@x, @xtemp);
        iter++;
    };

    return iter;
};

// Map iteration count to an RGB color using a smooth palette
def iter_to_color(int iter, int max_iter, double palette_offset, double* r, double* g, double* b) -> void
{
    double t, s;

    if (iter == max_iter)
    {
        // Inside the set - black
        *r = 0.0;
        *g = 0.0;
        *b = 0.0;
        return;
    };

    // t in [0,1] across one 256-step cycle - always positive
    // palette_offset rotates the color band over time for a breathing animation
    t = (double)(iter % 256) / 255.0 + palette_offset;
    t = t - (double)(int)t;

    // 5-stop palette for deep contrast:
    // 0.00 - 0.20: black -> deep purple
    // 0.20 - 0.45: deep purple -> electric blue
    // 0.45 - 0.65: electric blue -> bright teal/cyan
    // 0.65 - 0.85: bright teal -> deep gold
    // 0.85 - 1.00: deep gold -> crimson -> fades back to black (matches t=0 for seamless wrap)
    if (t < 0.2)
    {
        s = t / 0.2;
        *r = s * 0.45;
        *g = 0.0;
        *b = s * 0.6;
    }
    elif (t < 0.45)
    {
        s = (t - 0.2) / 0.25;
        *r = 0.45 - s * 0.45;
        *g = s * 0.05;
        *b = 0.6 + s * 0.4;
    }
    elif (t < 0.65)
    {
        s = (t - 0.45) / 0.2;
        *r = s * 0.05;
        *g = s * 0.9;
        *b = 1.0;
    }
    elif (t < 0.85)
    {
        s = (t - 0.65) / 0.2;
        *r = 0.05 + s * 0.85;
        *g = 0.9 - s * 0.5;
        *b = 1.0 - s * 1.0;
    }
    else
    {
        // Fade from deep gold/crimson back to black so the wrap joins t=0 smoothly
        s = (t - 0.85) / 0.15;
        *r = 0.9 - s * 0.9;
        *g = 0.4 - s * 0.4;
        *b = 0.0;
    };

    return;
};

// SYSTEM_INFO layout on x64 Windows:
//   0  DWORD  dwOemId
//   4  DWORD  dwPageSize
//   8  void*  lpMinimumApplicationAddress
//  16  void*  lpMaximumApplicationAddress
//  24  u64    dwActiveProcessorMask
//  32  DWORD  dwNumberOfProcessors
struct SYSTEM_INFO_PARTIAL
{
    u32   dwOemId,
          dwPageSize;
    void* lpMin,
          lpMax;
    u64   dwActiveProcessorMask;
    u32   dwNumberOfProcessors,
          dwProcessorType,
          dwAllocationGranularity;
    u16   wProcessorLevel,
          wProcessorRevision;
};

extern def !! GetSystemInfo(void*) -> void,
              GetTickCount()       -> DWORD;

// ============================================================================
//  Pixel buffer - heap allocated, non-overlapping writes by workers
// ============================================================================

heap float* g_pixels = (float*)0;
heap int*   g_iters  = (int*)0;
int g_cols = 0,
    g_rows = 0;

// ============================================================================
//  Work descriptor per thread
// ============================================================================

struct WorkSlice
{
    int    row_start,
           row_end,
           cols,
           rows,
           dyn_max_iter,
           tile,
           recolor_only;
    Decimal x_min,
            y_min,
            x_range,
            y_range;
    double  palette_offset;
};

WorkSlice[64] g_slices;

// ============================================================================
//  Worker thread
// ============================================================================

def worker(void* arg) -> void*
{
    WorkSlice* sl = (WorkSlice*)arg;

    int row, col, iter, idx;
    double r, gv, b;

    Decimal fx, fy,
            col_d, row_d,
            cols_d, rows_d,
            half, tmp, tmp2;

    decimal_from_string(@half, "0.5\0");
    decimal_from_i64(@cols_d, (i64)sl.cols);
    decimal_from_i64(@rows_d, (i64)sl.rows);

    row = sl.row_start;
    while (row < sl.row_end)
    {
        col = 0;
        while (col < sl.cols)
        {
            idx = row * sl.cols + col;

            if (sl.recolor_only == 0)
            {
                // fx = x_min + x_range * (col + 0.5) / cols
                decimal_from_i64(@col_d, (i64)col);
                decimal_add(@tmp, @col_d, @half);
                decimal_mul(@tmp2, @sl.x_range, @tmp);
                decimal_div(@tmp, @tmp2, @cols_d);
                decimal_add(@fx, @sl.x_min, @tmp);

                // fy = y_min + y_range * (row + 0.5) / rows
                decimal_from_i64(@row_d, (i64)row);
                decimal_add(@tmp, @row_d, @half);
                decimal_mul(@tmp2, @sl.y_range, @tmp);
                decimal_div(@tmp, @tmp2, @rows_d);
                decimal_add(@fy, @sl.y_min, @tmp);

                iter = mandelbrot(@fx, @fy, sl.dyn_max_iter);
                g_iters[idx] = iter;
            }
            else
            {
                // Color-only pass: reuse cached iteration count
                iter = g_iters[idx];
            };

            iter_to_color(iter, sl.dyn_max_iter, sl.palette_offset, @r, @gv, @b);

            idx = idx * 3;
            g_pixels[idx]     = (float)r;
            g_pixels[idx + 1] = (float)gv;
            g_pixels[idx + 2] = (float)b;

            col++;
        };
        row++;
    };

    return (void*)0;
};

def main() -> int
{
    decimal_set_precision(28);

    // ── Query core count ──────────────────────────────────
    SYSTEM_INFO_PARTIAL sysinfo;
    GetSystemInfo((void*)@sysinfo);
    int num_threads = (int)sysinfo.dwNumberOfProcessors;
    if (num_threads < 1)           { num_threads = 1; };
    if (num_threads > MAX_THREADS) { num_threads = MAX_THREADS; };

    print("Logical cores: \0");
    print(num_threads);
    print("\n\0");
    print("Decimal precision: 28 digits\n\0");

    Window win( "Mandelbrot Set [Decimal 28] - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    // Use identity matrix - emit vertices directly in NDC [-1, 1]
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);

    // ── Texture setup - one fullscreen texture replaces per-pixel quad calls ─
    glEnable(GL_TEXTURE_2D);
    i32 tex_id;
    glGenTextures(1, @tex_id);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // View parameters as Decimals for full 28-digit precision
    Decimal cx, cy, zoom, half_zoom,
            x_min, y_min, x_range, y_range,
            tmp, tmp2, tmp3,
            zoom_delta,
            pan_delta;

    // Zoom threshold sentinels for dyn_max_iter selection
    Decimal thresh1, thresh2, thresh3;
    decimal_from_string(@thresh1, "1\0");
    decimal_from_string(@thresh2, "0.01\0");
    decimal_from_string(@thresh3, "0.0001\0");

    decimal_from_string(@cx,   "-0.5\0");
    decimal_from_string(@cy,   "0\0");
    decimal_from_string(@zoom, "3\0");

    // Scalar control parameters stay float/double - no high precision needed
    float zoom_speed, pan_speed, dt;
    zoom_speed = 1.5;
    pan_speed  = 0.6;

    double palette_time, palette_offset;
    palette_time = 0.0;

    // TILE and max_iter adapt based on whether any key is held:
    // moving = coarser tiles + fewer iterations for responsive panning/zooming
    int tile, dyn_max_iter,
        cols, rows,
        cur_w, cur_h,
        rows_per_thread, t;
    bool moving, recolor_only;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    WORD w_state, s_state, a_state, d_state, up_state, dn_state;

    Thread[64] threads;

    while (win.process_messages())
    {
        // Delta time
        t_now  = GetTickCount();
        dt     = (float)(t_now - t_last) / 1000.0;
        t_last = t_now;
        // Clamp dt so a stall doesn't cause a huge jump
        if (dt > 0.1) { dt = 0.1; };

        // Advance palette rotation time - 0.12 cycles/second for a gentle breathing effect
        palette_time = palette_time + (double)dt * 0.12;

        // Keep palette_time in [0,1) to prevent precision loss over long sessions
        if (palette_time >= 1.0) { palette_time = palette_time - 1.0; };

        palette_offset = palette_time;

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

        // Scale max iterations with zoom depth
        // zoom ranges from ~8 (fully out) down toward 10^-28 (deep in).
        if (decimal_cmp(@zoom, @thresh1) > 0)
        {
            dyn_max_iter = 128;
        }
        elif (decimal_cmp(@zoom, @thresh2) > 0)
        {
            dyn_max_iter = 256;
        }
        elif (decimal_cmp(@zoom, @thresh3) > 0)
        {
            dyn_max_iter = 512;
        }
        else
        {
            dyn_max_iter = MAX_ITER;
        };
        // While moving, halve the iteration budget on top of tile coarsening
        if (moving) { dyn_max_iter = dyn_max_iter >> 1; };

        // Zoom in: zoom *= (1 - zoom_speed * dt)
        if ((w_state `& 0x8000) != 0)
        {
            // zoom_delta = zoom * zoom_speed * dt  (scalar multiply via string)
            decimal_from_string(@tmp, "1\0");
            decimal_from_i64(@tmp2, (i64)(zoom_speed * dt * 1000000f));
            decimal_from_string(@tmp3, "1000000\0");
            decimal_div(@zoom_delta, @tmp2, @tmp3);
            // zoom_delta = zoom * zoom_delta
            decimal_mul(@tmp, @zoom, @zoom_delta);
            decimal_sub(@zoom, @zoom, @tmp);
            // Floor at 10^-27 so we never underflow the precision
            decimal_from_string(@tmp, "0.000000000000000000000000001\0");
            if (decimal_cmp(@zoom, @tmp) < 0)
            {
                decimal_copy(@zoom, @tmp);
            };
        };

        // Zoom out: zoom *= (1 + zoom_speed * dt)
        if ((s_state `& 0x8000) != 0)
        {
            decimal_from_i64(@tmp2, (i64)(zoom_speed * dt * 1000000f));
            decimal_from_string(@tmp3, "1000000\0");
            decimal_div(@zoom_delta, @tmp2, @tmp3);
            decimal_mul(@tmp, @zoom, @zoom_delta);
            decimal_add(@zoom, @zoom, @tmp);
            decimal_from_string(@tmp, "8\0");
            if (decimal_cmp(@zoom, @tmp) > 0)
            {
                decimal_copy(@zoom, @tmp);
            };
        };

        // Pan left: cx -= zoom * pan_speed * dt
        if ((a_state `& 0x8000) != 0)
        {
            decimal_from_i64(@tmp2, (i64)(pan_speed * dt * 1000000f));
            decimal_from_string(@tmp3, "1000000\0");
            decimal_div(@pan_delta, @tmp2, @tmp3);
            decimal_mul(@tmp, @zoom, @pan_delta);
            decimal_sub(@cx, @cx, @tmp);
        };

        // Pan right: cx += zoom * pan_speed * dt
        if ((d_state `& 0x8000) != 0)
        {
            decimal_from_i64(@tmp2, (i64)(pan_speed * dt * 1000000f));
            decimal_from_string(@tmp3, "1000000\0");
            decimal_div(@pan_delta, @tmp2, @tmp3);
            decimal_mul(@tmp, @zoom, @pan_delta);
            decimal_add(@cx, @cx, @tmp);
        };

        // Pan up: cy -= zoom * pan_speed * dt
        if ((up_state `& 0x8000) != 0)
        {
            decimal_from_i64(@tmp2, (i64)(pan_speed * dt * 1000000f));
            decimal_from_string(@tmp3, "1000000\0");
            decimal_div(@pan_delta, @tmp2, @tmp3);
            decimal_mul(@tmp, @zoom, @pan_delta);
            decimal_sub(@cy, @cy, @tmp);
        };

        // Pan down: cy += zoom * pan_speed * dt
        if ((dn_state `& 0x8000) != 0)
        {
            decimal_from_i64(@tmp2, (i64)(pan_speed * dt * 1000000f));
            decimal_from_string(@tmp3, "1000000\0");
            decimal_div(@pan_delta, @tmp2, @tmp3);
            decimal_mul(@tmp, @zoom, @pan_delta);
            decimal_add(@cy, @cy, @tmp);
        };

        // ── Reallocate pixel buffer if tile count changed ─
        if (cols != g_cols | rows != g_rows)
        {
            if ((u64)g_pixels != (u64)0)
            {
                ffree((u64)g_pixels);
            };
            if ((u64)g_iters != (u64)0)
            {
                ffree((u64)g_iters);
            };
            g_pixels = (float*)fmalloc((size_t)(cols * rows * 3 * 4));
            g_iters  = (int*)fmalloc((size_t)(cols * rows * 4));
            g_cols   = cols;
            g_rows   = rows;
            recolor_only = false;
        }
        else
        {
            // Only skip fractal recompute when stationary - moving always needs fresh iters
            recolor_only = !moving;
        };

        // ── Compute view parameters ───────────────────────
        // half_zoom = zoom * 0.5
        decimal_from_string(@tmp, "0.5\0");
        decimal_mul(@half_zoom, @zoom, @tmp);

        // x_min = cx - half_zoom
        decimal_sub(@x_min, @cx, @half_zoom);

        // y_range = zoom * cur_h / cur_w
        decimal_from_i64(@tmp, (i64)cur_h);
        decimal_from_i64(@tmp2, (i64)cur_w);
        decimal_mul(@tmp3, @zoom, @tmp);
        decimal_div(@y_range, @tmp3, @tmp2);

        // y_min = cy - y_range * 0.5
        decimal_from_string(@tmp, "0.5\0");
        decimal_mul(@tmp2, @y_range, @tmp);
        decimal_sub(@y_min, @cy, @tmp2);

        // x_range = zoom
        decimal_copy(@x_range, @zoom);

        // ── Partition rows across threads and launch ──────
        rows_per_thread = rows / num_threads;
        if (rows_per_thread < 1) { rows_per_thread = 1; };

        t = 0;
        while (t < num_threads)
        {
            g_slices[t].row_start      = t * rows_per_thread;
            g_slices[t].row_end        = (t == num_threads - 1)
                                         ? rows
                                         : (t + 1) * rows_per_thread;
            g_slices[t].cols           = cols;
            g_slices[t].rows           = rows;
            g_slices[t].dyn_max_iter   = dyn_max_iter;
            g_slices[t].tile           = tile;
            g_slices[t].recolor_only   = recolor_only ? 1 : 0;
            decimal_copy(@g_slices[t].x_min,    @x_min);
            decimal_copy(@g_slices[t].y_min,    @y_min);
            decimal_copy(@g_slices[t].x_range,  @x_range);
            decimal_copy(@g_slices[t].y_range,  @y_range);
            g_slices[t].palette_offset = palette_offset;

            thread_create(@worker, (void*)@g_slices[t], @threads[t]);
            t++;
        };

        // ── Wait for all workers ──────────────────────────
        t = 0;
        while (t < num_threads)
        {
            thread_join(@threads[t]);
            t++;
        };

        // Clear
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        // ── Upload pixel buffer as texture and draw one fullscreen quad ───
        glBindTexture(GL_TEXTURE_2D, tex_id);
        glTexImage2D(GL_TEXTURE_2D, 0, (i32)GL_RGB, cols, rows, 0,
                     (i32)GL_RGB, (i32)GL_FLOAT, (void*)g_pixels);

        glBegin(GL_QUADS);
        glTexCoord2f(0.0, 1.0); glVertex2f(-1.0, -1.0);
        glTexCoord2f(1.0, 1.0); glVertex2f( 1.0, -1.0);
        glTexCoord2f(1.0, 0.0); glVertex2f( 1.0,  1.0);
        glTexCoord2f(0.0, 0.0); glVertex2f(-1.0,  1.0);
        glEnd();

        gl.present();
    };

    // ── Cleanup ───────────────────────────────────────────
    if ((u64)g_pixels != (u64)0)
    {
        ffree((u64)g_pixels);
    };
    if ((u64)g_iters != (u64)0)
    {
        ffree((u64)g_iters);
    };

    glDeleteTextures(1, @tex_id);

    gl.__exit();
    win.__exit();

    return 0;
};
