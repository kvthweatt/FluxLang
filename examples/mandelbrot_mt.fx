// mandelbrot_mt.fx
// Multithreaded Mandelbrot Set viewer.
// One worker thread per logical CPU core; each thread owns a contiguous
// band of rows.  The main thread dispatches a frame, waits for all
// workers to finish, then issues a single OpenGL draw call.
//
// Controls: W/S = zoom in/out   A/D = pan X   Up/Down = pan Y

#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx", "threading.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;
using standard::atomic;
using standard::threading;

// ============================================================================
//  Constants
// ============================================================================

const int WIN_W       = 900,
          WIN_H       = 900,
          MAX_ITER    = 1024,
          TILE_STILL  = 1,
          TILE_MOVING = 4,
          MAX_THREADS = 64,

          VK_W    = 0x57,
          VK_S    = 0x53,
          VK_A    = 0x41,
          VK_D    = 0x44,
          VK_UP   = 0x26,
          VK_DOWN = 0x28;

// ============================================================================
//  Win32 FFI
// ============================================================================

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
           dyn_max_iter,
           tile;
    double x_min,
           y_min,
           x_range,
           y_range;
};

WorkSlice[64] g_slices;

// ============================================================================
//  Mandelbrot iteration (unchanged from original)
// ============================================================================

def mandelbrot(double x0, double y0, int max_iter) -> int
{
    double cx, cy, q;
    cx = x0 - 0.25;
    cy = y0;
    q  = cx * cx + cy * cy;
    if (q * (q + cx) < cy * cy * 0.25) { return max_iter; };
    cx = x0 + 1.0;
    if (cx * cx + cy * cy < 0.0625)    { return max_iter; };

    double x, y, xx, yy, xtemp;
    int iter;
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

// ============================================================================
//  Color mapping (unchanged from original)
// ============================================================================

def iter_to_color(int iter, int max_iter, double* r, double* g, double* b) -> void
{
    double t, s;
    if (iter == max_iter)
    {
        *r = 0.0; *g = 0.0; *b = 0.0;
        return;
    };
    t = (double)(iter % 256) / 255.0;
    if (t < 0.2)
    {
        s = t / 0.2;
        *r = s * 0.45; *g = 0.0; *b = s * 0.6;
    }
    elif (t < 0.45)
    {
        s = (t - 0.2) / 0.25;
        *r = 0.45 - s * 0.45; *g = s * 0.05; *b = 0.6 + s * 0.4;
    }
    elif (t < 0.65)
    {
        s = (t - 0.45) / 0.2;
        *r = s * 0.05; *g = s * 0.9; *b = 1.0;
    }
    elif (t < 0.85)
    {
        s = (t - 0.65) / 0.2;
        *r = 0.05 + s * 0.85; *g = 0.9 - s * 0.5; *b = 1.0 - s * 1.0;
    }
    else
    {
        s = (t - 0.85) / 0.15;
        *r = 0.9 + s * 0.1; *g = 0.4 - s * 0.4; *b = 0.0;
    };
};

// ============================================================================
//  Worker thread
// ============================================================================

def worker(void* arg) -> void*
{
    WorkSlice* sl = (WorkSlice*)arg;

    int row = sl.row_start;
    int col, iter, idx;
    double fx, fy, r, gv, b;
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

// ============================================================================
//  Main
// ============================================================================

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

    // ── Window and GL setup ──────────────────────────────
    Window win("Mandelbrot MT - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);

    // ── View state ───────────────────────────────────────
    int t, rows_per_thread, idx;

    double cx, cy, zoom, half_zoom,
           x_min, y_min, x_range, y_range;
    cx   = -0.5;
    cy   =  0.0;
    zoom =  3.0;

    float zoom_speed, pan_speed, dt,
          px0, px1, py0, py1;
    zoom_speed = 1.5;
    pan_speed  = 0.6;

    int tile, dyn_max_iter,
        cols, rows, row, col,
        cur_w, cur_h;
    bool moving;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    WORD w_state, s_state, a_state, d_state, up_state, dn_state;

    Thread[64] threads;

    // ── Main loop ────────────────────────────────────────
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

        if (zoom > 1.0)      { dyn_max_iter = 128; }
        elif (zoom > 0.01)   { dyn_max_iter = 256; }
        elif (zoom > 0.0001) { dyn_max_iter = 512; }
        else                 { dyn_max_iter = MAX_ITER; };
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
        if ((a_state `& 0x8000) != 0) { cx = cx - zoom * (double)pan_speed * (double)dt; };
        if ((d_state `& 0x8000) != 0) { cx = cx + zoom * (double)pan_speed * (double)dt; };
        if ((up_state `& 0x8000) != 0) { cy = cy - zoom * (double)pan_speed * (double)dt; };
        if ((dn_state `& 0x8000) != 0) { cy = cy + zoom * (double)pan_speed * (double)dt; };

        // ── Reallocate pixel buffer if tile count changed ─
        if (cols != g_cols | rows != g_rows)
        {
            if ((u64)g_pixels != (u64)0)
            {
                free(g_pixels);
            };
            g_pixels = (float*)malloc((size_t)(cols * rows * 3 * 4));
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
            g_slices[t].tile         = tile;
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

        // ── Draw pixel buffer as quads ────────────────────
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        glBegin(GL_QUADS);
        row = 0;
        while (row < rows)
        {
            col = 0;
            while (col < cols)
            {
                idx = (row * cols + col) * 3;
                glColor3f(g_pixels[idx], g_pixels[idx + 1], g_pixels[idx + 2]);

                px0 = -1.0 + 2.0 * (float)(col * tile) / (float)cur_w;
                py0 =  1.0 - 2.0 * (float)(row * tile) / (float)cur_h;
                px1 = -1.0 + 2.0 * (float)(col * tile + tile) / (float)cur_w;
                py1 =  1.0 - 2.0 * (float)(row * tile + tile) / (float)cur_h;

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

    // ── Cleanup ───────────────────────────────────────────
    if ((u64)g_pixels != (u64)0)
    {
        free(g_pixels);
    };

    gl.__exit();
    win.__exit();

    return 0;
};
