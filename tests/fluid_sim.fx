// fluid_sim.fx
// Fluid simulation - click and hold to spill fluid
// OpenGL texture pipeline, fmalloc/ffree, double-precision Navier-Stokes
// Optimizations:
//   - Persistent thread pool with semaphore dispatch + memory fences
//   - Red-black Gauss-Seidel (fully parallel per color pass)
//   - Parallel project (divergence + gradient loops threaded)
//   - Concurrent vx/vy diffuse (dispatched together, not sequentially)
//   - Fused decay+pixel pass
//   - Row ranges computed once at startup
//   - Division replaced with multiply where possible
//   - set_bnd deferred to end of lin_solve iteration loop

#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx", "threading.fx";

using standard::system::windows,
      standard::math,
      standard::threading,
      standard::atomic;

// ============================================================================
// SIMULATION CONSTANTS
// ============================================================================

// All simulation constants as #def - zero global memory loads in hot paths
#def SIM_W     256;
#def SIM_H     192;
#def ITER      4;
#def VISCOSITY 0.00008;
#def DIFFUSION 0.0008;
#def DT        0.15;
#def DECAY     0.995;
#def INV255    0.00392156862745098;

const int    WIN_W        = 1024,
             WIN_H        = 768,
             MAX_THREADS  = 64;

// ============================================================================
// FIELD STORAGE
// ============================================================================

heap double* g_dens      = (double*)0,
             g_dens_prev = (double*)0,
             g_vx        = (double*)0,
             g_vy        = (double*)0,
             g_vx_prev   = (double*)0,
             g_vy_prev   = (double*)0;

heap float*  g_pixels    = (float*)0;

// ============================================================================
// PARTICLE SYSTEM
// ============================================================================

#def NUM_PARTICLES 4096;

heap float* g_part_x = (float*)0;   // particle x in grid coords [0, SIM_W)
heap float* g_part_y = (float*)0;   // particle y in grid coords [0, SIM_H)

global int g_rand_seed = 12345;

// ============================================================================
// THREAD POOL
// ============================================================================

const int PHASE_LINSOLVE_RED   = 0,
          PHASE_LINSOLVE_BLACK = 1,
          PHASE_ADVECT         = 2,
          PHASE_PROJECT_DIV    = 3,
          PHASE_PROJECT_GRAD   = 4,
          PHASE_DECAY_PIXELS   = 5,
          PHASE_EXIT           = 6;

// Hot fields written every dispatch - kept together for cache locality
// Cold fields (row_start/row_end) set once at startup, never change
struct WorkSlice
{
    // Cold - set once at startup
    int     row_start;
    int     row_end;
    // Hot - written each dispatch
    int     phase;
    int     ls_color;
    double* ls_x;
    double* ls_x0;
    double  ls_a;
    double  ls_c_inv;
    double* adv_dst;
    double* adv_src;
    double* adv_u;
    double* adv_v;
    double* proj_u;
    double* proj_v;
    double* proj_p;
    double* proj_div;
    double  proj_hx;
    double  proj_hy;
    double  proj_hx_inv;
    double  proj_hy_inv;
    // decay_pixels - passed as params to avoid global pointer reloads
    double* dp_dens;
    float*  dp_pixels;
};

WorkSlice[64]  g_slices;
Thread[64]     g_threads;
Semaphore      g_work_sem;
Semaphore      g_done_sem;
global int     g_num_threads    = 1;
global int     g_rows_per_thread = 1;

// Second pool for concurrent dual-field lin_solve (vx and vy diffuse together)
WorkSlice[64]  g_slices2;
Thread[64]     g_threads2;
Semaphore      g_work_sem2;
Semaphore      g_done_sem2;

// ============================================================================
// MOUSE / WINDOW STATE
// ============================================================================

global bool mouse_down = false;
global int  mouse_x    = 0,
            mouse_y    = 0,
            mouse_px   = 0,
            mouse_py   = 0;

global int  cur_w      = WIN_W,
            cur_h      = WIN_H;

// Smoothed injection velocity - exponential moving average of mouse delta
global double g_smooth_vx = 0.0,
              g_smooth_vy = 0.0;

// ============================================================================
// WINDOW PROCEDURE
// ============================================================================

def FluidWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) -> LRESULT
{
    int nx;
    int ny;

    if (msg == WM_CLOSE)      { DestroyWindow(hwnd); return 0; };
    if (msg == WM_DESTROY)    { PostQuitMessage(0);  return 0; };
    if (msg == WM_ERASEBKGND) { return 1; };

    if (msg == WM_PAINT)
    {
        PAINTSTRUCT ps;
        BeginPaint(hwnd, @ps);
        EndPaint(hwnd, @ps);
        return 0;
    };

    if (msg == WM_LBUTTONDOWN)
    {
        mouse_down = true;
        mouse_px   = (int)(lParam & 0xFFFF);
        mouse_py   = (int)((lParam >> 16) & 0xFFFF);
        mouse_x    = mouse_px;
        mouse_y    = mouse_py;
        return 0;
    };

    if (msg == WM_LBUTTONUP)
    {
        mouse_down = false;
        return 0;
    };

    if (msg == WM_MOUSEMOVE)
    {
        nx       = (int)(lParam & 0xFFFF);
        ny       = (int)((lParam >> 16) & 0xFFFF);
        mouse_px = mouse_x;
        mouse_py = mouse_y;
        mouse_x  = nx;
        mouse_y  = ny;
        return 0;
    };

    return DefWindowProcA(hwnd, msg, wParam, lParam);
};

// ============================================================================
// HELPER: flat index - manually expanded in hot loops to avoid call overhead
// ============================================================================

def IX(int x, int y) -> int
{
    return y * SIM_W + x;
};

// ============================================================================
// BOUNDARY CONDITIONS
// ============================================================================

def set_bnd(int b, double* x) -> void
{
    int i;

    for (i = 1; i < SIM_H - 1; i++)
    {
        if (b == 1)
        {
            x[i * SIM_W]              = (0.0 - x[i * SIM_W + 1]);
            x[i * SIM_W + SIM_W - 1]  = (0.0 - x[i * SIM_W + SIM_W - 2]);
        }
        else
        {
            x[i * SIM_W]              = x[i * SIM_W + 1];
            x[i * SIM_W + SIM_W - 1]  = x[i * SIM_W + SIM_W - 2];
        };
    };

    for (i = 1; i < SIM_W - 1; i++)
    {
        if (b == 2)
        {
            x[i]                       = (0.0 - x[i + SIM_W]);
            x[(SIM_H-1) * SIM_W + i]   = (0.0 - x[(SIM_H-2) * SIM_W + i]);
        }
        else
        {
            x[i]                       = x[i + SIM_W];
            x[(SIM_H-1) * SIM_W + i]   = x[(SIM_H-2) * SIM_W + i];
        };
    };

    x[0]                          = 0.5 * (x[1]           + x[SIM_W]);
    x[SIM_W - 1]                  = 0.5 * (x[SIM_W - 2]   + x[SIM_W + SIM_W - 1]);
    x[(SIM_H-1) * SIM_W]          = 0.5 * (x[(SIM_H-1) * SIM_W + 1]       + x[(SIM_H-2) * SIM_W]);
    x[(SIM_H-1) * SIM_W + SIM_W-1]= 0.5 * (x[(SIM_H-1) * SIM_W + SIM_W-2] + x[(SIM_H-2) * SIM_W + SIM_W-1]);

    return;
};

// ============================================================================
// WORKER BAND FUNCTIONS
// ============================================================================

def linsolve_band(int row_start, int row_end, int color,
                  double* x, double* x0, double a, double c_inv) -> void
{
    int jstart;
    int jend;
    int i_start;
    int i;
    int j;
    int base;     // j * SIM_W - row base offset

    jstart = row_start;
    jend   = row_end;
    if (jstart < 1)       { jstart = 1;       };
    if (jend   > SIM_H-1) { jend   = SIM_H-1; };

    for (j = jstart; j < jend; j++)
    {
        base    = j * SIM_W;
        i_start = 1 + ((j + color + 1) & 1);
        i       = i_start;
        while (i < SIM_W - 1)
        {
            x[base + i] = (x0[base + i] + a * (x[base + i - 1] + x[base + i + 1] +
                                                x[base + i - SIM_W] + x[base + i + SIM_W])) * c_inv;
            i = i + 2;
        };
    };
    return;
};

def advect_band(int row_start, int row_end,
                double* d, double* d0, double* u, double* v) -> void
{
    double dt0x;
    double dt0y;
    double max_x;
    double max_y;
    double bx;
    double by;
    double s0;
    double s1;
    double t0;
    double t1;
    int jstart;
    int jend;
    int i;
    int j;
    int i0;
    int j0;
    int i1;
    int j1;
    int base;
    int base00;
    int base01;

    dt0x  = DT * (double)(SIM_W - 2);
    dt0y  = DT * (double)(SIM_H - 2);
    max_x = (double)(SIM_W - 2) + 0.5;
    max_y = (double)(SIM_H - 2) + 0.5;

    jstart = row_start;
    jend   = row_end;
    if (jstart < 1)       { jstart = 1;       };
    if (jend   > SIM_H-1) { jend   = SIM_H-1; };

    for (j = jstart; j < jend; j++)
    {
        base = j * SIM_W;
        for (i = 1; i < SIM_W - 1; i++)
        {
            bx = (double)i - dt0x * u[base + i];
            by = (double)j - dt0y * v[base + i];

            if (bx < 0.5)   { bx = 0.5;   };
            if (bx > max_x) { bx = max_x; };
            if (by < 0.5)   { by = 0.5;   };
            if (by > max_y) { by = max_y; };

            i0 = (int)bx;
            j0 = (int)by;
            i1 = i0 + 1;
            j1 = j0 + 1;

            s1 = bx - (double)i0;
            s0 = 1.0 - s1;
            t1 = by - (double)j0;
            t0 = 1.0 - t1;

            base00 = j0 * SIM_W;
            base01 = j1 * SIM_W;

            d[base + i] = s0 * (t0 * d0[base00 + i0] + t1 * d0[base01 + i0]) +
                           s1 * (t0 * d0[base00 + i1] + t1 * d0[base01 + i1]);
        };
    };
    return;
};

// Compute divergence and zero pressure - parallel
def project_div_band(int row_start, int row_end,
                     double* u, double* v, double* p, double* div,
                     double hx, double hy) -> void
{
    int jstart;
    int jend;
    int i;
    int j;
    int base;

    jstart = row_start;
    jend   = row_end;
    if (jstart < 1)       { jstart = 1;       };
    if (jend   > SIM_H-1) { jend   = SIM_H-1; };

    for (j = jstart; j < jend; j++)
    {
        base = j * SIM_W;
        for (i = 1; i < SIM_W - 1; i++)
        {
            div[base + i] = (0.0 - 0.5) * (hx * (u[base + i + 1] - u[base + i - 1]) +
                                             hy * (v[base + i + SIM_W] - v[base + i - SIM_W]));
            p[base + i]   = 0.0;
        };
    };
    return;
};

// Subtract pressure gradient - parallel, division replaced with multiply
def project_grad_band(int row_start, int row_end,
                      double* u, double* v, double* p,
                      double hx_inv, double hy_inv) -> void
{
    int jstart;
    int jend;
    int i;
    int j;
    int base;

    jstart = row_start;
    jend   = row_end;
    if (jstart < 1)       { jstart = 1;       };
    if (jend   > SIM_H-1) { jend   = SIM_H-1; };

    for (j = jstart; j < jend; j++)
    {
        base = j * SIM_W;
        for (i = 1; i < SIM_W - 1; i++)
        {
            u[base + i] -= 0.5 * (p[base + i + 1]      - p[base + i - 1])      * hx_inv;
            v[base + i] -= 0.5 * (p[base + i + SIM_W]  - p[base + i - SIM_W])  * hy_inv;
        };
    };
    return;
};

// Fused decay + plasma color mapping - dark saturated palette, never blows to white
def decay_pixels_band(int row_start, int row_end, double* dens, float* pixels) -> void
{
    int    i;
    int    j;
    int    base;
    int    pidx;
    double d;
    double t;
    double s;
    float  r;
    float  g;
    float  b;

    for (j = row_start; j < row_end; j++)
    {
        base = j * SIM_W;
        for (i = 0; i < SIM_W; i++)
        {
            d = dens[base + i] * DECAY;
            if (d < 0.0001) { d = 0.0; };
            dens[base + i] = d;

            // Clamp and remap - t never exceeds 0.75 so we stay in deep color range
            if (d > 200.0) { d = 200.0; };
            t = d * INV255;
            s = 0.0;
            r = 0.0;
            g = 0.0;
            b = 0.0;

            // Deep plasma palette: black -> deep blue -> cyan -> teal/green
            // Caps at bright cyan, never reaches white
            if (t < 0.15)
            {
                s = t * 6.667;
                b = (float)(s * 0.6);
            }
            elif (t < 0.35)
            {
                s = (t - 0.15) * 5.0;
                r = 0.0;
                g = (float)(s * 0.4);
                b = (float)(0.6 + s * 0.4);
            }
            elif (t < 0.55)
            {
                s = (t - 0.35) * 5.0;
                r = 0.0;
                g = (float)(0.4 + s * 0.5);
                b = 1.0;
            }
            elif (t < 0.75)
            {
                s = (t - 0.55) * 5.0;
                r = (float)(s * 0.2);
                g = (float)(0.9 + s * 0.1);
                b = (float)(1.0 - s * 0.3);
            }
            else
            {
                // Deep magenta/purple peak - still dark, never white
                s = (t - 0.75) * 4.0;
                r = (float)(0.2 + s * 0.4);
                g = (float)(1.0 - s * 0.5);
                b = (float)(0.7 + s * 0.1);
            };

            // Scale down overall brightness - keeps it translucent-feeling
            r = r * 0.75;
            g = g * 0.75;
            b = b * 0.75;

            pidx = (base + i) * 3;
            pixels[pidx]     = r;
            pixels[pidx + 1] = g;
            pixels[pidx + 2] = b;
        };
    };
    return;
};

// ============================================================================
// PARTICLE SYSTEM
// ============================================================================

def fast_rand() -> int
{
    g_rand_seed = g_rand_seed * 1664525 + 1013904223;
    return g_rand_seed & 0x7FFFFFFF;
};

def particles_init() -> void
{
    int i;
    for (i = 0; i < NUM_PARTICLES; i++)
    {
        g_rand_seed = g_rand_seed * 1664525 + 1013904223;
        g_part_x[i] = (float)(g_rand_seed & 0x7FFFFFFF) / (float)0x7FFFFFFF * (float)SIM_W;
        g_rand_seed = g_rand_seed * 1664525 + 1013904223;
        g_part_y[i] = (float)(g_rand_seed & 0x7FFFFFFF) / (float)0x7FFFFFFF * (float)SIM_H;
    };
    return;
};

def particles_update_render(float* pixels) -> void
{
    int    i;
    int    pi;
    int    pj;
    int    pidx;
    float  px;
    float  py;
    float  vx;
    float  vy;
    double dens_here;

    for (i = 0; i < NUM_PARTICLES; i++)
    {
        px = g_part_x[i];
        py = g_part_y[i];

        pi = (int)px;
        pj = (int)py;

        if (pi < 1)       { pi = 1;       };
        if (pi > SIM_W-2) { pi = SIM_W-2; };
        if (pj < 1)       { pj = 1;       };
        if (pj > SIM_H-2) { pj = SIM_H-2; };

        // Sample velocity field - scale up significantly since solver values are small
        vx = (float)(g_vx[pj * SIM_W + pi] * 15.0);
        vy = (float)(g_vy[pj * SIM_W + pi] * 15.0);

        // Thermal drift - strong enough to prevent lattice settling
        g_rand_seed = g_rand_seed * 1664525 + 1013904223;
        vx = vx + (float)((g_rand_seed & 0xFF) - 128) * 0.012;
        g_rand_seed = g_rand_seed * 1664525 + 1013904223;
        vy = vy + (float)((g_rand_seed & 0xFF) - 128) * 0.012;

        px = px + vx;
        py = py + vy;

        // Wrap
        if (px < 0.0)           { px = px + (float)SIM_W; };
        if (px >= (float)SIM_W) { px = px - (float)SIM_W; };
        if (py < 0.0)           { py = py + (float)SIM_H; };
        if (py >= (float)SIM_H) { py = py - (float)SIM_H; };

        g_part_x[i] = px;
        g_part_y[i] = py;

        // Render only inside fluid
        pi = (int)px;
        pj = (int)py;
        if (pi >= 1 & pi < SIM_W-1 & pj >= 1 & pj < SIM_H-1)
        {
            dens_here = g_dens[pj * SIM_W + pi];
            if (dens_here > 15.0)
            {
                pidx = (pj * SIM_W + pi) * 3;
                pixels[pidx]     = 1.0;
                pixels[pidx + 1] = 1.0;
                pixels[pidx + 2] = 1.0;
            };
        };
    };
    return;
};

// ============================================================================
// PERSISTENT WORKER
// ============================================================================

def worker(void* arg) -> void*
{
    WorkSlice* sl;
    sl = (WorkSlice*)arg;

    while (true)
    {
        semaphore_wait(@g_work_sem);
        load_fence();

        if (sl.phase == PHASE_EXIT) { return (void*)0; };

        if (sl.phase == PHASE_LINSOLVE_RED | sl.phase == PHASE_LINSOLVE_BLACK)
        {
            linsolve_band(sl.row_start, sl.row_end, sl.ls_color,
                          sl.ls_x, sl.ls_x0, sl.ls_a, sl.ls_c_inv);
        }
        elif (sl.phase == PHASE_ADVECT)
        {
            advect_band(sl.row_start, sl.row_end,
                        sl.adv_dst, sl.adv_src, sl.adv_u, sl.adv_v);
        }
        elif (sl.phase == PHASE_PROJECT_DIV)
        {
            project_div_band(sl.row_start, sl.row_end,
                             sl.proj_u, sl.proj_v, sl.proj_p, sl.proj_div,
                             sl.proj_hx, sl.proj_hy);
        }
        elif (sl.phase == PHASE_PROJECT_GRAD)
        {
            project_grad_band(sl.row_start, sl.row_end,
                              sl.proj_u, sl.proj_v, sl.proj_p,
                              sl.proj_hx_inv, sl.proj_hy_inv);
        }
        elif (sl.phase == PHASE_DECAY_PIXELS)
        {
            decay_pixels_band(sl.row_start, sl.row_end, sl.dp_dens, sl.dp_pixels);
        };

        semaphore_post(@g_done_sem);
    };

    return (void*)0;
};

def worker2(void* arg) -> void*
{
    WorkSlice* sl;
    sl = (WorkSlice*)arg;

    while (true)
    {
        semaphore_wait(@g_work_sem2);
        load_fence();

        if (sl.phase == PHASE_EXIT) { return (void*)0; };

        if (sl.phase == PHASE_LINSOLVE_RED | sl.phase == PHASE_LINSOLVE_BLACK)
        {
            linsolve_band(sl.row_start, sl.row_end, sl.ls_color,
                          sl.ls_x, sl.ls_x0, sl.ls_a, sl.ls_c_inv);
        }
        elif (sl.phase == PHASE_ADVECT)
        {
            advect_band(sl.row_start, sl.row_end,
                        sl.adv_dst, sl.adv_src, sl.adv_u, sl.adv_v);
        }
        elif (sl.phase == PHASE_PROJECT_DIV)
        {
            project_div_band(sl.row_start, sl.row_end,
                             sl.proj_u, sl.proj_v, sl.proj_p, sl.proj_div,
                             sl.proj_hx, sl.proj_hy);
        }
        elif (sl.phase == PHASE_PROJECT_GRAD)
        {
            project_grad_band(sl.row_start, sl.row_end,
                              sl.proj_u, sl.proj_v, sl.proj_p,
                              sl.proj_hx_inv, sl.proj_hy_inv);
        }
        elif (sl.phase == PHASE_DECAY_PIXELS)
        {
            decay_pixels_band(sl.row_start, sl.row_end, sl.dp_dens, sl.dp_pixels);
        };

        semaphore_post(@g_done_sem2);
    };

    return (void*)0;
};

def dispatch_linsolve2(int color, double* x, double* x0, double a, double c_inv) -> void
{
    int t;

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices2[t].phase    = color == 0 ? PHASE_LINSOLVE_RED : PHASE_LINSOLVE_BLACK;
        g_slices2[t].ls_x     = x;
        g_slices2[t].ls_x0    = x0;
        g_slices2[t].ls_a     = a;
        g_slices2[t].ls_c_inv = c_inv;
        g_slices2[t].ls_color = color;
    };
    store_fence();
    for (t = 0; t < g_num_threads; t++) { semaphore_post(@g_work_sem2); };
    return;
};

def collect2() -> void
{
    int t;
    for (t = 0; t < g_num_threads; t++) { semaphore_wait(@g_done_sem2); };
    return;
};

def dispatch_linsolve_post(int color, double* x, double* x0, double a, double c_inv) -> void
{
    int t;

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].phase    = color == 0 ? PHASE_LINSOLVE_RED : PHASE_LINSOLVE_BLACK;
        g_slices[t].ls_x     = x;
        g_slices[t].ls_x0    = x0;
        g_slices[t].ls_a     = a;
        g_slices[t].ls_c_inv = c_inv;
        g_slices[t].ls_color = color;
    };
    store_fence();
    for (t = 0; t < g_num_threads; t++) { semaphore_post(@g_work_sem); };
    return;
};

def collect1() -> void
{
    int t;
    for (t = 0; t < g_num_threads; t++) { semaphore_wait(@g_done_sem); };
    return;
};

def dispatch_linsolve(int color, double* x, double* x0, double a, double c_inv) -> void
{
    int t;

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].phase    = color == 0 ? PHASE_LINSOLVE_RED : PHASE_LINSOLVE_BLACK;
        g_slices[t].ls_x     = x;
        g_slices[t].ls_x0    = x0;
        g_slices[t].ls_a     = a;
        g_slices[t].ls_c_inv = c_inv;
        g_slices[t].ls_color = color;
    };
    store_fence();
    for (t = 0; t < g_num_threads; t++) { semaphore_post(@g_work_sem); };
    for (t = 0; t < g_num_threads; t++) { semaphore_wait(@g_done_sem); };
    return;
};

def dispatch_advect(double* dst, double* src, double* u, double* v) -> void
{
    int t;

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].phase   = PHASE_ADVECT;
        g_slices[t].adv_dst = dst;
        g_slices[t].adv_src = src;
        g_slices[t].adv_u   = u;
        g_slices[t].adv_v   = v;
    };
    store_fence();
    for (t = 0; t < g_num_threads; t++) { semaphore_post(@g_work_sem); };
    for (t = 0; t < g_num_threads; t++) { semaphore_wait(@g_done_sem); };
    return;
};

def dispatch_project_div(double* u, double* v, double* p, double* div,
                          double hx, double hy) -> void
{
    int t;

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].phase    = PHASE_PROJECT_DIV;
        g_slices[t].proj_u   = u;
        g_slices[t].proj_v   = v;
        g_slices[t].proj_p   = p;
        g_slices[t].proj_div = div;
        g_slices[t].proj_hx  = hx;
        g_slices[t].proj_hy  = hy;
    };
    store_fence();
    for (t = 0; t < g_num_threads; t++) { semaphore_post(@g_work_sem); };
    for (t = 0; t < g_num_threads; t++) { semaphore_wait(@g_done_sem); };
    return;
};

def dispatch_project_grad(double* u, double* v, double* p,
                           double hx_inv, double hy_inv) -> void
{
    int t;

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].phase       = PHASE_PROJECT_GRAD;
        g_slices[t].proj_u      = u;
        g_slices[t].proj_v      = v;
        g_slices[t].proj_p      = p;
        g_slices[t].proj_hx_inv = hx_inv;
        g_slices[t].proj_hy_inv = hy_inv;
    };
    store_fence();
    for (t = 0; t < g_num_threads; t++) { semaphore_post(@g_work_sem); };
    for (t = 0; t < g_num_threads; t++) { semaphore_wait(@g_done_sem); };
    return;
};

def dispatch_decay_pixels() -> void
{
    int t;

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].phase     = PHASE_DECAY_PIXELS;
        g_slices[t].dp_dens   = g_dens;
        g_slices[t].dp_pixels = g_pixels;
    };
    store_fence();
    for (t = 0; t < g_num_threads; t++) { semaphore_post(@g_work_sem); };
    for (t = 0; t < g_num_threads; t++) { semaphore_wait(@g_done_sem); };
    return;
};

// ============================================================================
// RED-BLACK LIN_SOLVE - set_bnd deferred to end of all iterations
// ============================================================================

def lin_solve_parallel(int b, double* x, double* x0, double a, double c) -> void
{
    double c_inv;
    int k;

    c_inv = 1.0 / c;

    for (k = 0; k < ITER; k++)
    {
        dispatch_linsolve(0, x, x0, a, c_inv);
        dispatch_linsolve(1, x, x0, a, c_inv);
        // set_bnd only on final iteration - intermediate boundaries
        // don't need to be exact for convergence
        if (k == ITER - 1) { set_bnd(b, x); };
    };
    return;
};

// ============================================================================
// DIFFUSE
// ============================================================================

def diffuse(int b, double* x, double* x0, double diff) -> void
{
    double a;
    a = DT * diff * (double)(SIM_W - 2) * (double)(SIM_H - 2);
    lin_solve_parallel(b, x, x0, a, 1.0 + 4.0 * a);
    return;
};

// ============================================================================
// PROJECT - divergence and gradient passes both threaded
// ============================================================================

def project(double* u, double* v, double* p, double* div) -> void
{
    double hx;
    double hy;
    double hx_inv;
    double hy_inv;

    hx     = 1.0 / (double)(SIM_W - 2);
    hy     = 1.0 / (double)(SIM_H - 2);
    hx_inv = (double)(SIM_W - 2);   // 1/hx = SIM_W-2
    hy_inv = (double)(SIM_H - 2);   // 1/hy = SIM_H-2

    dispatch_project_div(u, v, p, div, hx, hy);
    set_bnd(0, div);
    set_bnd(0, p);
    lin_solve_parallel(0, p, div, 1.0, 4.0);
    dispatch_project_grad(u, v, p, hx_inv, hy_inv);
    set_bnd(1, u);
    set_bnd(2, v);
    return;
};

// ============================================================================
// LIN_SOLVE ON POOL2
// ============================================================================

def lin_solve_parallel2(int b, double* x, double* x0, double a, double c) -> void
{
    double c_inv;
    int k;

    c_inv = 1.0 / c;

    for (k = 0; k < ITER; k++)
    {
        dispatch_linsolve2(0, x, x0, a, c_inv);
        collect2();
        dispatch_linsolve2(1, x, x0, a, c_inv);
        collect2();
        if (k == ITER - 1) { set_bnd(b, x); };
    };
    return;
};

// ============================================================================
// CONCURRENT DIFFUSE - runs two independent fields across both pools at once
// ============================================================================

def diffuse_concurrent(int b1, double* x1, double* x10, double diff1,
                        int b2, double* x2, double* x20, double diff2) -> void
{
    double a1;
    double a2;
    double c_inv1;
    double c_inv2;
    int k;

    a1     = DT * diff1 * (double)(SIM_W - 2) * (double)(SIM_H - 2);
    a2     = DT * diff2 * (double)(SIM_W - 2) * (double)(SIM_H - 2);
    c_inv1 = 1.0 / (1.0 + 4.0 * a1);
    c_inv2 = 1.0 / (1.0 + 4.0 * a2);

    for (k = 0; k < ITER; k++)
    {
        // Red pass: post both pools simultaneously, then collect both
        dispatch_linsolve_post(0, x1, x10, a1, c_inv1);
        dispatch_linsolve2(0, x2, x20, a2, c_inv2);
        collect1();
        collect2();

        // Black pass: same
        dispatch_linsolve_post(1, x1, x10, a1, c_inv1);
        dispatch_linsolve2(1, x2, x20, a2, c_inv2);
        collect1();
        collect2();

        if (k == ITER - 1)
        {
            set_bnd(b1, x1);
            set_bnd(b2, x2);
        };
    };
    return;
};

// ============================================================================
// VELOCITY STEP
// vx and vy diffuse run concurrently across both thread pools
// ============================================================================

def vel_step() -> void
{
    // Diffuse vx (pool1) and vy (pool2) concurrently - independent fields
    diffuse_concurrent(1, g_vx_prev, g_vx, VISCOSITY,
                       2, g_vy_prev, g_vy, VISCOSITY);

    project(g_vx_prev, g_vy_prev, g_vx, g_vy);

    dispatch_advect(g_vx, g_vx_prev, g_vx_prev, g_vy_prev);
    set_bnd(1, g_vx);
    dispatch_advect(g_vy, g_vy_prev, g_vx_prev, g_vy_prev);
    set_bnd(2, g_vy);

    project(g_vx, g_vy, g_vx_prev, g_vy_prev);
    return;
};

// ============================================================================
// DENSITY STEP
// ============================================================================

def dens_step() -> void
{
    diffuse(0, g_dens_prev, g_dens, DIFFUSION);
    dispatch_advect(g_dens, g_dens_prev, g_vx, g_vy);
    set_bnd(0, g_dens);
    return;
};

// ============================================================================
// ADD SOURCE AT MOUSE
// ============================================================================

def add_source() -> void
{
    int    gx;
    int    gy;
    int    r;
    int    i;
    int    j;
    double raw_vx;
    double raw_vy;
    double dx;
    double dy;
    double dist;
    double fall;

    if (!mouse_down)
    {
        // Decay smoothed velocity when not pressing so next press starts fresh
        g_smooth_vx = g_smooth_vx * 0.85;
        g_smooth_vy = g_smooth_vy * 0.85;
        return;
    };

    gx = mouse_x * SIM_W / cur_w;
    gy = mouse_y * SIM_H / cur_h;

    if (gx < 1)       { gx = 1;       };
    if (gx > SIM_W-2) { gx = SIM_W-2; };
    if (gy < 1)       { gy = 1;       };
    if (gy > SIM_H-2) { gy = SIM_H-2; };

    // Raw delta scaled to grid space
    raw_vx = (double)(mouse_x - mouse_px) * (double)SIM_W / (double)cur_w;
    raw_vy = (double)(mouse_y - mouse_py) * (double)SIM_H / (double)cur_h;

    // Exponential moving average - smooths direction, follows gesture
    g_smooth_vx = g_smooth_vx * 0.8 + raw_vx * 0.2;
    g_smooth_vy = g_smooth_vy * 0.8 + raw_vy * 0.2;

    r = 6;

    for (j = gy - r; j <= gy + r; j++)
    {
        for (i = gx - r; i <= gx + r; i++)
        {
            if (i < 1 | i > SIM_W-2) { continue; };
            if (j < 1 | j > SIM_H-2) { continue; };

            dx   = (double)(i - gx);
            dy   = (double)(j - gy);
            dist = sqrt(dx * dx + dy * dy);
            fall = 1.0 - dist / (double)(r + 1);
            if (fall < 0.0) { fall = 0.0; };

            // Dense emission at source
            g_dens[IX(i,j)] += fall * 180.0;

            // Radial outward push from center - makes fluid bloom, not jet
            if (dist > 0.001)
            {
                g_vx[IX(i,j)] += fall * (dx / dist) * 0.8;
                g_vy[IX(i,j)] += fall * (dy / dist) * 0.8;
            };

            // Gentle directional bias from mouse movement - subtle, not dominant
            g_vx[IX(i,j)] += fall * g_smooth_vx * 0.3;
            g_vy[IX(i,j)] += fall * g_smooth_vy * 0.3;
        };
    };
    return;
};

// ============================================================================
// SYSTEM_INFO for core count
// ============================================================================

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

extern def !! GetSystemInfo(void*) -> void;

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    size_t field_bytes;
    size_t pixel_bytes;
    HINSTANCE hInstance;
    HWND hwnd;
    HDC  hdc;
    MSG  msg;
    bool running;
    int  tex_id;
    int  t;
    RECT client_rect;
    SYSTEM_INFO_PARTIAL sysinfo;

    GetSystemInfo((void*)@sysinfo);
    g_num_threads = (int)sysinfo.dwNumberOfProcessors;
    if (g_num_threads < 1)           { g_num_threads = 1;           };
    if (g_num_threads > MAX_THREADS) { g_num_threads = MAX_THREADS; };

    field_bytes = (size_t)(SIM_W * SIM_H * 8);
    pixel_bytes = (size_t)(SIM_W * SIM_H * 3 * 4);

    g_dens      = (double*)fmalloc(field_bytes);
    g_dens_prev = (double*)fmalloc(field_bytes);
    g_vx        = (double*)fmalloc(field_bytes);
    g_vy        = (double*)fmalloc(field_bytes);
    g_vx_prev   = (double*)fmalloc(field_bytes);
    g_vy_prev   = (double*)fmalloc(field_bytes);
    g_pixels    = (float*)fmalloc(pixel_bytes);
    g_part_x    = (float*)fmalloc((size_t)(NUM_PARTICLES * 4));
    g_part_y    = (float*)fmalloc((size_t)(NUM_PARTICLES * 4));

    particles_init();

    semaphore_init(@g_work_sem, 0);
    semaphore_init(@g_done_sem, 0);
    semaphore_init(@g_work_sem2, 0);
    semaphore_init(@g_done_sem2, 0);

    // Row ranges computed once at startup - never change
    g_rows_per_thread = SIM_H / g_num_threads;
    if (g_rows_per_thread < 1) { g_rows_per_thread = 1; };

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].row_start  = t * g_rows_per_thread;
        g_slices[t].row_end    = (t == g_num_threads - 1) ? SIM_H : (t + 1) * g_rows_per_thread;
        g_slices[t].phase      = PHASE_DECAY_PIXELS;
        g_slices2[t].row_start = t * g_rows_per_thread;
        g_slices2[t].row_end   = (t == g_num_threads - 1) ? SIM_H : (t + 1) * g_rows_per_thread;
        g_slices2[t].phase     = PHASE_DECAY_PIXELS;
        thread_create((void*)@worker,  (void*)@g_slices[t],  @g_threads[t]);
        thread_create((void*)@worker2, (void*)@g_slices2[t], @g_threads2[t]);
    };

    hInstance = GetModuleHandleA((LPCSTR)0);

    byte* class_name = "FluidSim\0",
          win_title  = "Fluid Simulation\0";

    WNDCLASSEXA wc;
    wc.cbSize        = (UINT)(sizeof(WNDCLASSEXA) / 8);
    wc.style         = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wc.lpfnWndProc   = (WNDPROC)@FluidWindowProc;
    wc.cbClsExtra    = 0;
    wc.cbWndExtra    = 0;
    wc.hInstance     = hInstance;
    wc.hIcon         = LoadIconA((HINSTANCE)0, (LPCSTR)32512);
    wc.hCursor       = LoadCursorA((HINSTANCE)0, (LPCSTR)32512);
    wc.hbrBackground = GetStockObject(BLACK_BRUSH);
    wc.lpszMenuName  = (LPCSTR)0;
    wc.lpszClassName = (LPCSTR)class_name;
    wc.hIconSm       = (HICON)0;

    RegisterClassExA(@wc);

    hwnd = CreateWindowExA(
        WS_EX_APPWINDOW,
        (LPCSTR)class_name,
        (LPCSTR)win_title,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        100, 100, WIN_W, WIN_H,
        (HWND)0, (HMENU)0, hInstance, STDLIB_GVP);

    hdc = GetDC(hwnd);

    GLContext gl(hdc);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_TEXTURE_2D);

    tex_id = 0;
    glGenTextures(1, @tex_id);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glTexImage2D(GL_TEXTURE_2D, 0, (i32)GL_RGB, SIM_W, SIM_H, 0,
                 (i32)GL_RGB, (i32)GL_FLOAT, (void*)g_pixels);

    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    running = true;

    while (running)
    {
        while (PeekMessageA(@msg, (HWND)0, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT) { running = false; };
            TranslateMessage(@msg);
            DispatchMessageA(@msg);
        };

        if (!running) { break; };

        GetClientRect(hwnd, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };
        glViewport(0, 0, cur_w, cur_h);

        add_source();
        vel_step();
        dens_step();
        dispatch_decay_pixels();

        // Particle update + render on top of density field, single-threaded
        // (4096 particles is trivial cost vs the solver)
        particles_update_render(g_pixels);

        glBindTexture(GL_TEXTURE_2D, tex_id);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, SIM_W, SIM_H,
                        (i32)GL_RGB, (i32)GL_FLOAT, (void*)g_pixels);

        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);

        glBegin(GL_QUADS);
        glTexCoord2f(0.0, 1.0); glVertex2f(-1.0, -1.0);
        glTexCoord2f(1.0, 1.0); glVertex2f( 1.0, -1.0);
        glTexCoord2f(1.0, 0.0); glVertex2f( 1.0,  1.0);
        glTexCoord2f(0.0, 0.0); glVertex2f(-1.0,  1.0);
        glEnd();

        gl.present();
    };

    // Shut down both thread pools
    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].phase  = PHASE_EXIT;
        g_slices2[t].phase = PHASE_EXIT;
        semaphore_post(@g_work_sem);
        semaphore_post(@g_work_sem2);
    };
    for (t = 0; t < g_num_threads; t++)
    {
        thread_join(@g_threads[t]);
        thread_join(@g_threads2[t]);
    };

    semaphore_destroy(@g_work_sem);
    semaphore_destroy(@g_done_sem);
    semaphore_destroy(@g_work_sem2);
    semaphore_destroy(@g_done_sem2);

    glDeleteTextures(1, @tex_id);
    gl.__exit();

    ffree((u64)g_dens);
    ffree((u64)g_dens_prev);
    ffree((u64)g_vx);
    ffree((u64)g_vy);
    ffree((u64)g_vx_prev);
    ffree((u64)g_vy_prev);
    ffree((u64)g_pixels);
    ffree((u64)g_part_x);
    ffree((u64)g_part_y);

    ReleaseDC(hwnd, hdc);
    UnregisterClassA((LPCSTR)class_name, hInstance);

    return 0;
};
