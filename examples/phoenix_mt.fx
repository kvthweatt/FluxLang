#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx", "threading.fx";

using standard::system::windows;
using standard::math;
using standard::atomic;
using standard::threading;
using standard::io::console;

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

const int WIN_W        = 900,
          WIN_H        = 900,
          MAX_ITER     = 1024,
          TILE_STILL   = 1,
          TILE_MOVING  = 4,
          MAX_THREADS  = 64,
          VK_W   = 0x57,
          VK_S   = 0x53,
          VK_A   = 0x41,
          VK_D   = 0x44,
          VK_J   = 0x4A,
          VK_L   = 0x4C,
          VK_I   = 0x49,
          VK_K   = 0x4B,
          VK_N   = 0x4E,
          VK_M   = 0x4D,
          VK_TAB = 0x09,
          VK_UP   = 0x26,
          VK_DOWN = 0x28;



// ============================================================================
// Phoenix iteration
//
// z_{n+1} = z_n^2 + c + p * z_{n-1}
//
// Expanding in real/imaginary (c = cr + ci*i, p treated as real scalar here
// p is treated as a real scalar here:
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

def phoenix(double fx, double fy,
            double cr, double ci,
            double pr, double pi,
            int max_iter) -> int
{
    double zx, zy, px, py, nzx, nzy, zx2, zy2;
    int iter;

    // z_{-1}: swapped pixel (Im + Re*i)
    zx = fy;
    zy = fx;

    // z_{-2} = 0
    px = 0.0;
    py = 0.0;

    iter = 0;

    while (iter < max_iter)
    {
        zx2 = zx * zx;
        zy2 = zy * zy;

        // Bailout: |z|^2 > 4
        if (zx2 + zy2 > 4.0) { return iter; };

        // new_zx = zx^2 - zy^2 + cr + pr*px - pi*py
        nzx = zx2 - zy2 + cr + pr * px - pi * py;

        // new_zy = 2*zx*zy + ci + pr*py + pi*px
        nzy = 2.0 * zx * zy + ci + pr * py + pi * px;

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
def phoenix_param(double fx, double fy,
                  double pr, double pi,
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
           tile,
           mode;
    double x_min,
           y_min,
           x_range,
           y_range,
           cr,
           ci,
           pr,
           pi_p;
};

WorkSlice[64] g_slices;

// ============================================================================
//  Worker thread
// ============================================================================

def worker(void* arg) -> void*
{
    WorkSlice* sl = (WorkSlice*)arg;

    int row, col, iter, idx;
    double fx, fy;
    float r, gv, b;
    row = sl.row_start;
    while (row < sl.row_end)
    {
        col = 0;
        while (col < sl.cols)
        {
            fx = sl.x_min + sl.x_range * ((double)col + 0.5) / (double)sl.cols;
            fy = sl.y_min + sl.y_range * ((double)row + 0.5) / (double)sl.rows;

            if (sl.mode == 0)
            {
                iter = phoenix(fx, fy, sl.cr, sl.ci, sl.pr, sl.pi_p, sl.dyn_max_iter);
            }
            else
            {
                iter = phoenix_param(fx, fy, sl.pr, sl.pi_p, sl.dyn_max_iter);
            };

            iter_to_color(iter, sl.dyn_max_iter, @r, @gv, @b);

            idx = (row * sl.cols + col) * 3;
            g_pixels[idx]     = r;
            g_pixels[idx + 1] = gv;
            g_pixels[idx + 2] = b;

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

    Window win( "Phoenix Fractal - W/S: Zoom  A/D/Up/Down: Pan  J/L: Re(c)  I/K: Im(c)  N/M: Re(p)  Tab: Mode\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

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

    // View parameters
    double cx, cy, zoom, half_zoom, x_min, y_min,
           x_range, y_range;

    // Start in Julia mode on the classic phoenix: c=0.5667, p=-0.5
    cx   =  0.0;
    cy   =  0.0;
    zoom =  2.7;

    // c and p parameters (complex; p is typically real)
    double cr, ci, pr, pi_p;
    cr   =  0.5667;
    ci   =  0.0;
    pr   = -0.5;
    pi_p =  0.0;

    // 0 = Julia mode, 1 = parameter plane
    int mode;
    mode = 0;

    float zoom_speed, pan_speed, c_speed, dt;
    zoom_speed = 1.5;
    pan_speed  = 0.6;
    c_speed    = 0.3;

    int tile, dyn_max_iter,
        cols, rows,
        cur_w, cur_h,
        rows_per_thread, t;
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

    Thread[64] threads;

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
                cx   =  0.0;
                cy   =  0.0;
                zoom =  3.0;
            }
            else
            {
                mode = 0;
                cx   =  0.0;
                cy   =  0.0;
                zoom =  2.7;
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

        if (zoom > 1.0)
        {
            dyn_max_iter = 128;
        }
        else
        {
            dyn_max_iter = MAX_ITER;
        };
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

        // Adjust c and p in Julia mode
        if (mode == 0)
        {
            if ((j_state `& 0x8000) != 0)
            {
                cr = cr - (double)c_speed * (double)dt;
            };

            if ((l_state `& 0x8000) != 0)
            {
                cr = cr + (double)c_speed * (double)dt;
            };

            if ((i_state `& 0x8000) != 0)
            {
                ci = ci + (double)c_speed * (double)dt;
            };

            if ((k_state `& 0x8000) != 0)
            {
                ci = ci - (double)c_speed * (double)dt;
            };

            if ((n_state `& 0x8000) != 0)
            {
                pr = pr - (double)c_speed * (double)dt;
            };

            if ((m_state `& 0x8000) != 0)
            {
                pr = pr + (double)c_speed * (double)dt;
            };
        };

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
            g_slices[t].mode         = mode;
            g_slices[t].x_min        = x_min;
            g_slices[t].y_min        = y_min;
            g_slices[t].x_range      = x_range;
            g_slices[t].y_range      = y_range;
            g_slices[t].cr           = cr;
            g_slices[t].ci           = ci;
            g_slices[t].pr           = pr;
            g_slices[t].pi_p         = pi_p;

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
        free(g_pixels);
    };

    glDeleteTextures(1, @tex_id);

    gl.__exit();
    win.__exit();

    return 0;
};
