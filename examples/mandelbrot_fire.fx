#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx", "threading.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;
using standard::atomic;
using standard::threading;

// ============================================================================
// Mandelbrot Set - OpenGL Viewer
// W = zoom in, S = zoom out
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

// Compute Mandelbrot iteration count using native double precision
def mandelbrot(double x0, double y0, int max_iter) -> int
{
    double x, y, xx, yy, xtemp, cx, cy, q;
    int iter;

    // Cardioid and period-2 bulb check
    // Points inside either region are guaranteed to never escape - skip iteration entirely
    cx = x0 - 0.25;
    cy = y0;
    q  = cx * cx + cy * cy;
    // Main cardioid: q*(q + cx) < cy*cy*0.25
    if (q * (q + cx) < cy * cy * 0.25) { return max_iter; };
    // Period-2 bulb: (x+1)^2 + y^2 < 1/16
    cx = x0 + 1.0;
    if (cx * cx + cy * cy < 0.0625) { return max_iter; };

    x    = 0.0;
    y    = 0.0;
    iter = 0;

    while (iter < max_iter)
    {
        xx = x * x;
        yy = y * y;
        if (xx + yy > 4.0) { return iter; };
        xtemp = xx - yy + x0;
        y     = 2.0 * x * y + y0;
        x     = xtemp;
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

    // 5-stop fire palette - no blue:
    // 0.00 - 0.20: black -> deep purple
    // 0.20 - 0.40: deep purple -> dark pink
    // 0.40 - 0.60: dark pink -> red
    // 0.60 - 0.80: red -> orange
    // 0.80 - 1.00: orange -> yellow -> fades back to black (matches t=0 for seamless wrap)
    if (t < 0.2)
    {
        s = t / 0.2;
        *r = s * 0.5;
        *g = 0.0;
        *b = s * 0.5;
    }
    elif (t < 0.4)
    {
        s = (t - 0.2) / 0.2;
        *r = 0.5 + s * 0.35;
        *g = 0.0;
        *b = 0.5 - s * 0.3;
    }
    elif (t < 0.6)
    {
        s = (t - 0.4) / 0.2;
        *r = 0.85 + s * 0.15;
        *g = s * 0.1;
        *b = 0.2 - s * 0.2;
    }
    elif (t < 0.8)
    {
        s = (t - 0.6) / 0.2;
        *r = 1.0;
        *g = 0.1 + s * 0.45;
        *b = 0.0;
    }
    else
    {
        // Fade from orange/yellow back to black so the wrap joins t=0 smoothly
        s = (t - 0.8) / 0.2;
        *r = 1.0 - s * 1.0;
        *g = 0.55 + s * 0.45 - s * 1.0;
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
    double x_min,
           y_min,
           x_range,
           y_range,
           palette_offset;
};

WorkSlice[64] g_slices;

// ============================================================================
//  Worker thread
// ============================================================================

def worker(void* arg) -> void*
{
    WorkSlice* sl = (WorkSlice*)arg;

    int row, col, iter, idx;
    double fx, fy, r, gv, b;
    row = sl.row_start;
    while (row < sl.row_end)
    {
        col = 0;
        while (col < sl.cols)
        {
            idx = row * sl.cols + col;

            if (sl.recolor_only == 0)
            {
                // Full recompute: run fractal math and cache the iteration count
                fx = sl.x_min + sl.x_range * ((double)col + 0.5) / (double)sl.cols;
                fy = sl.y_min + sl.y_range * ((double)row + 0.5) / (double)sl.rows;
                iter = mandelbrot(fx, fy, sl.dyn_max_iter);
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
    // ── Query core count ──────────────────────────────────
    SYSTEM_INFO_PARTIAL sysinfo;
    GetSystemInfo((void*)@sysinfo);
    int num_threads = (int)sysinfo.dwNumberOfProcessors;
    if (num_threads < 1)           { num_threads = 1; };
    if (num_threads > MAX_THREADS) { num_threads = MAX_THREADS; };

    print("Logical cores: \0");
    print(num_threads);
    print("\n\0");

    Window win( "Mandelbrot Set - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0", 100, 100, WIN_W, WIN_H);
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

    // View parameters as native doubles
    double cx, cy, zoom, half_zoom, x_min, y_min,
           x_range, y_range,
           palette_time, palette_offset;

    cx   = -0.5;
    cy   =  0.0;
    zoom =  3.0;
    palette_time = 0.0;

    // Scalar control parameters stay float
    float zoom_speed, pan_speed, dt;
    zoom_speed = 1.5;
    pan_speed  = 0.6;

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

        // Scale max iterations with zoom depth: shallow zoom needs far fewer iters.
        // zoom ranges from ~8.0 (fully out) to ~0.0000000001 (deep in).
        // At zoom 8 cap at 128; at zoom 1 cap at 256; deep zoom uses full MAX_ITER.
        if (zoom > 1.0)
        {
            dyn_max_iter = 128;
        }
        elif (zoom > 0.01)
        {
            dyn_max_iter = 256;
        }
        elif (zoom > 0.0001)
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
            zoom = zoom * (1.0 - (double)zoom_speed * (double)dt);
            if (zoom < 0.0000000001) { zoom = 0.0000000001; };
        };

        if ((s_state `& 0x8000) != 0)
        {
            zoom = zoom * (1.0 + (double)zoom_speed * (double)dt);
            if (zoom > 8.0) { zoom = 8.0; };
        };

        if ((a_state `& 0x8000) != 0)
        {
            cx = cx - zoom * (double)pan_speed * (double)dt;
        };

        if ((d_state `& 0x8000) != 0)
        {
            cx = cx + zoom * (double)pan_speed * (double)dt;
        };

        if ((up_state `& 0x8000) != 0)
        {
            cy = cy - zoom * (double)pan_speed * (double)dt;
        };

        if ((dn_state `& 0x8000) != 0)
        {
            cy = cy + zoom * (double)pan_speed * (double)dt;
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
        half_zoom = zoom * 0.5;
        x_min   = cx - half_zoom;
        y_min   = cy - zoom * (double)cur_h / (double)cur_w * 0.5;
        x_range = zoom;
        y_range = zoom * (double)cur_h / (double)cur_w;

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
            g_slices[t].x_min          = x_min;
            g_slices[t].y_min          = y_min;
            g_slices[t].x_range        = x_range;
            g_slices[t].y_range        = y_range;
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
