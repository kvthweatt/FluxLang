#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx", "threading.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;
using standard::atomic;
using standard::threading;

// ============================================================================
// Mandelbrot Set - Auto Zoom Demo
// Slowly zooms into a deep interesting coordinate, fully rendered every frame
// ============================================================================

const int WIN_W    = 900,
          WIN_H    = 900,
          MAX_ITER = 1024,
          MAX_THREADS = 64;

// Zoom target: Misiurewicz point - boundary spiral, never collapses to black interior
const double TARGET_X = -1.23706216702671,
             TARGET_Y = -0.09294502320475;

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
def iter_to_color(int iter, int max_iter, double* r, double* g, double* b) -> void
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
    t = (double)(iter % 256) / 255.0;

    // 5-stop palette for deep contrast:
    // 0.00 - 0.20: black -> deep purple
    // 0.20 - 0.45: deep purple -> electric blue
    // 0.45 - 0.65: electric blue -> bright teal/cyan
    // 0.65 - 0.85: bright teal -> deep gold
    // 0.85 - 1.00: deep gold -> crimson red
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
        s = (t - 0.85) / 0.15;
        *r = 0.9 + s * 0.1;
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
           dyn_max_iter;
    double x_min,
           y_min,
           x_range,
           y_range;
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
            fx = sl.x_min + sl.x_range * ((double)col + 0.5) / (double)sl.cols;
            fy = sl.y_min + sl.y_range * ((double)row + 0.5) / (double)sl.rows;

            iter = mandelbrot(fx, fy, sl.dyn_max_iter);

            iter_to_color(iter, sl.dyn_max_iter, @r, @gv, @b);

            idx = (row * sl.cols + col) * 3;
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

    Window win("Mandelbrot Set - Auto Zoom\0", 100, 100, WIN_W, WIN_H);
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
           x_range, y_range;

    cx   = TARGET_X;
    cy   = TARGET_Y;
    zoom = 3.0;

    // Zoom speed: fraction of zoom shrunk per second
    double zoom_speed;
    zoom_speed = 0.18;

    int dyn_max_iter,
        cols, rows,
        cur_w, cur_h,
        rows_per_thread, t;

    float dt;
    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;

    Thread[64] threads;

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

        // Auto zoom in continuously; reset to start when fully deep
        zoom = zoom * (1.0 - zoom_speed * (double)dt);
        if (zoom < 0.0000000001) { zoom = 3.0; };

        // Scale max iterations with zoom depth for detail at depth
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

        // Always fully rendered - tile size 1, every pixel
        cols = cur_w;
        rows = cur_h;

        // ── Reallocate pixel buffer if size changed ───────
        if (cols != g_cols | rows != g_rows)
        {
            if ((u64)g_pixels != (u64)0)
            {
                ffree(g_pixels);
            };
            g_pixels = (float*)fmalloc((size_t)(cols * rows * 3 * 4));
            g_cols   = cols;
            g_rows   = rows;
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
            g_slices[t].row_start    = t * rows_per_thread;
            g_slices[t].row_end      = (t == num_threads - 1)
                                       ? rows
                                       : (t + 1) * rows_per_thread;
            g_slices[t].cols         = cols;
            g_slices[t].rows         = rows;
            g_slices[t].dyn_max_iter = dyn_max_iter;
            g_slices[t].x_min        = x_min;
            g_slices[t].y_min        = y_min;
            g_slices[t].x_range      = x_range;
            g_slices[t].y_range      = y_range;

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
        ffree(g_pixels);
    };

    glDeleteTextures(1, @tex_id);

    gl.__exit();
    win.__exit();

    return 0;
};
