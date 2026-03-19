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
#def DECAY     0.994;
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

// Upload buffers - floats for GL texture upload (solver uses double internally)
// g_dens_tex: 1 float per cell for GL_LUMINANCE upload
// g_vel_tex:  2 floats per cell (vx, vy) for GL_LUMINANCE_ALPHA upload
heap float*  g_dens_tex = (float*)0,
             g_vel_tex  = (float*)0;

// ============================================================================
// PARTICLE SYSTEM
// ============================================================================

#def NUM_PARTICLES 300;

heap float* g_part_x = (float*)0,   // particle x in grid coords [0, SIM_W)
            g_part_y = (float*)0;   // particle y in grid coords [0, SIM_H)

global int g_rand_seed = 12345;

// ============================================================================
// THREAD POOL
// ============================================================================

const int PHASE_LINSOLVE_RED   = 0,
          PHASE_LINSOLVE_BLACK = 1,
          PHASE_ADVECT         = 2,
          PHASE_PROJECT_DIV    = 3,
          PHASE_PROJECT_GRAD   = 4,
          PHASE_DECAY          = 5,
          PHASE_EXIT           = 6;

// Hot fields written every dispatch - kept together for cache locality
// Cold fields (row_start/row_end) set once at startup, never change
struct WorkSlice
{
    // Cold - set once at startup
    int     row_start,
            row_end,
    // Hot - written each dispatch
            phase,
            ls_color;
    double* ls_x, ls_x0;
    double  ls_a, ls_c_inv;
    double* adv_dst,
            adv_src,
            adv_u,
            adv_v,
            proj_u,
            proj_v,
            proj_p,
            proj_div;
    double  proj_hx,
            proj_hy,
            proj_hx_inv,
            proj_hy_inv;
    // decay - passed as param to avoid global pointer reload
    double* dp_dens;
};

WorkSlice[64]  g_slices, g_slices2;
Thread[64]     g_threads, g_threads2;
Semaphore      g_work_sem, g_done_sem, g_work_sem2, g_done_sem2;
int g_num_threads    = 1,
    g_rows_per_thread = 1;

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

global int g_palette = 0;

// Smoothed injection velocity - exponential moving average of mouse delta
global double g_smooth_vx = 0.0,
              g_smooth_vy = 0.0;

// ============================================================================
// WINDOW PROCEDURE
// ============================================================================

def FluidWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) -> LRESULT
{
    int nx, ny;

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

    if (msg == WM_KEYDOWN)
    {
        if (wParam == 0x31) { g_palette = 0; return 0; };
        if (wParam == 0x32) { g_palette = 1; return 0; };
        if (wParam == 0x33) { g_palette = 2; return 0; };
        if (wParam == 0x34) { g_palette = 3; return 0; };
        if (wParam == 0x35) { g_palette = 4; return 0; };
        if (wParam == 0x36) { g_palette = 5; return 0; };
        if (wParam == 0x37) { g_palette = 6; return 0; };
        if (wParam == 0x38) { g_palette = 7; return 0; };
        if (wParam == 0x39) { g_palette = 8; return 0; };
        if (wParam == 0x30) { g_palette = 9; return 0; };
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
    int jstart,
        jend,
        i_start,
        i, j,
        base;     // j * SIM_W - row base offset

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
    double dt0x,
           dt0y,
           max_x,
           max_y,
           bx,
           by,
           s0,
           s1,
           t0,
           t1;
    int jstart, jend,
        i,  j,
        i0, j0,
        i1, j1,
        base, base00, base01;

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
    int jstart, jend,
        i, j,
        base;

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
    int jstart, jend,
        i, j,
        base;

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

// Decay only - shader does color mapping on GPU
def decay_band(int row_start, int row_end, double* dens) -> void
{
    int i, j, base;
    double d;

    for (j = row_start; j < row_end; j++)
    {
        base = j * SIM_W;
        for (i = 0; i < SIM_W; i++)
        {
            d = dens[base + i] * DECAY;
            if (d < 0.0001) { d = 0.0; };
            dens[base + i] = d;
        };
    };
    return;
};

// Convert double fields to float upload buffers for GL texture upload
// ============================================================================
// PARTICLE SYSTEM - update only, rendering done by GPU point sprites
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

def particles_update() -> void
{
    int   i, pi, pj;
    float px,
          py,
          vx,
          vy;

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

        vx = (float)(g_vx[pj * SIM_W + pi] * 15.0);
        vy = (float)(g_vy[pj * SIM_W + pi] * 15.0);

        g_rand_seed = g_rand_seed * 1664525 + 1013904223;
        vx = vx + (float)((g_rand_seed & 0xFF) - 128) * 0.012;
        g_rand_seed = g_rand_seed * 1664525 + 1013904223;
        vy = vy + (float)((g_rand_seed & 0xFF) - 128) * 0.012;

        px = px + vx;
        py = py + vy;

        if (px < 0.0)           { px = px + (float)SIM_W; };
        if (px >= (float)SIM_W) { px = px - (float)SIM_W; };
        if (py < 0.0)           { py = py + (float)SIM_H; };
        if (py >= (float)SIM_H) { py = py - (float)SIM_H; };

        g_part_x[i] = px;
        g_part_y[i] = py;
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
        elif (sl.phase == PHASE_DECAY)
        {
            decay_band(sl.row_start, sl.row_end, sl.dp_dens);
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
        elif (sl.phase == PHASE_DECAY)
        {
            decay_band(sl.row_start, sl.row_end, sl.dp_dens);
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

def dispatch_decay() -> void
{
    int t;

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].phase   = PHASE_DECAY;
        g_slices[t].dp_dens = g_dens;
    };
    store_fence();
    for (t = 0; t < g_num_threads; t++) { semaphore_post(@g_work_sem); };
    for (t = 0; t < g_num_threads; t++) { semaphore_wait(@g_done_sem); };
    return;
};

// Convert double fields to float upload buffers - single-threaded, cheap
def upload_textures() -> void
{
    int   i, n, vidx;
    float d, scale;

    scale = 4.0;
    n     = SIM_W * SIM_H;

    for (i = 0; i < n; i++)
    {
        d = (float)(g_dens[i] * INV255);
        if (d > 1.0) { d = 1.0; };
        g_dens_tex[i] = d;

        vidx = i * 2;
        g_vel_tex[vidx]     = (float)(g_vx[i] * scale) + 0.5;
        g_vel_tex[vidx + 1] = (float)(g_vy[i] * scale) + 0.5;
    };
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
    double hx, hy, hx_inv, hy_inv;

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
    double a1, a2,
           c_inv1, c_inv2;
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
    int    gx, gy, r, i, j;
    double raw_vx,
           raw_vy,
           dx, dy,
           dist, fall;

    if (!mouse_down)
    {
        // Decay smoothed velocity when not pressing so next press starts fresh
        g_smooth_vx = g_smooth_vx * 0.85;
        g_smooth_vy = g_smooth_vy * 0.85;
        return;
    };

    gx = mouse_x * SIM_W / cur_w;
    gy = (cur_h - 1 - mouse_y) * SIM_H / cur_h;

    if (gx < 1)       { gx = 1;       };
    if (gx > SIM_W-2) { gx = SIM_W-2; };
    if (gy < 1)       { gy = 1;       };
    if (gy > SIM_H-2) { gy = SIM_H-2; };

    // Raw delta scaled to grid space
    raw_vx = (double)(mouse_x - mouse_px) * (double)SIM_W / (double)cur_w;
    raw_vy = (double)(mouse_py - mouse_y) * (double)SIM_H / (double)cur_h;

    // Exponential moving average - smooths direction, follows gesture
    g_smooth_vx = g_smooth_vx * 0.8 + raw_vx * 0.2;
    g_smooth_vy = g_smooth_vy * 0.8 + raw_vy * 0.2;

    r = 3;

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
// GLSL SHADER SOURCES
// ============================================================================

byte[] VERT_SRC = "#version 120
void main() {
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_Position    = gl_Vertex;
}
\0";

byte[] FRAG_SRC = "#version 120
uniform sampler2D u_dens;
uniform sampler2D u_vel;
uniform vec2      u_res;
uniform int       u_palette;

void main() {
    vec2 uv = gl_TexCoord[0].xy;

    float d  = texture2D(u_dens, uv).r;
    vec2  v  = texture2D(u_vel,  uv).ra - 0.5;
    float vm = length(v) * 2.0;
    float t  = clamp(d, 0.0, 1.0);

    // Wide bloom - 8-tap gather at two radii
    vec2  px   = 1.0 / u_res;
    float blur = 0.0;
    blur += texture2D(u_dens, uv + vec2(-px.x,       0.0      )).r;
    blur += texture2D(u_dens, uv + vec2( px.x,       0.0      )).r;
    blur += texture2D(u_dens, uv + vec2( 0.0,       -px.y     )).r;
    blur += texture2D(u_dens, uv + vec2( 0.0,        px.y     )).r;
    blur += texture2D(u_dens, uv + vec2(-px.x*2.5,  -px.y*2.5 )).r;
    blur += texture2D(u_dens, uv + vec2( px.x*2.5,  -px.y*2.5 )).r;
    blur += texture2D(u_dens, uv + vec2(-px.x*2.5,   px.y*2.5 )).r;
    blur += texture2D(u_dens, uv + vec2( px.x*2.5,   px.y*2.5 )).r;
    blur *= 0.125;
    float glow = clamp(blur * 3.0 + vm * t * 0.5, 0.0, 1.0);

    vec3 col = vec3(0.0);

    // 1: Classic plasma - blue/cyan/magenta
    if (u_palette == 0) {
        col.r = 0.5 - 0.5 * cos(3.14159 * (t * 1.2 + 0.0));
        col.g = 0.5 - 0.5 * cos(3.14159 * (t * 1.2 + 0.4));
        col.b = 0.5 - 0.5 * cos(3.14159 * (t * 1.2 + 0.8));
    }
    // 2: Fire - black -> red -> orange -> yellow
    else if (u_palette == 1) {
        col.r = clamp(t * 3.0,       0.0, 1.0);
        col.g = clamp(t * 3.0 - 1.0, 0.0, 1.0);
        col.b = clamp(t * 3.0 - 2.0, 0.0, 1.0);
    }
    // 3: Toxic - green/yellow-green
    else if (u_palette == 2) {
        col.r = 0.5 - 0.5 * cos(3.14159 * (t * 1.2 + 0.9));
        col.g = 0.5 - 0.5 * cos(3.14159 * (t * 1.2 + 0.3));
        col.b = 0.5 - 0.5 * cos(3.14159 * (t * 1.2 + 1.3));
    }
    // 4: Ice - deep blue -> cyan -> white
    else if (u_palette == 3) {
        col.r = 0.5 - 0.5 * cos(3.14159 * (t * 1.0 + 1.0));
        col.g = 0.5 - 0.5 * cos(3.14159 * (t * 1.0 + 0.6));
        col.b = 0.5 - 0.5 * cos(3.14159 * (t * 1.0 + 0.1));
    }
    // 5: Sunset - purple -> magenta -> orange
    else if (u_palette == 4) {
        col.r = 0.5 - 0.5 * cos(3.14159 * (t * 1.1 + 0.1));
        col.g = 0.5 - 0.5 * cos(3.14159 * (t * 1.1 + 0.9));
        col.b = 0.5 - 0.5 * cos(3.14159 * (t * 1.1 + 0.5));
    }
    // 6: Deep ocean - navy -> teal -> seafoam
    else if (u_palette == 5) {
        col.r = 0.5 - 0.5 * cos(3.14159 * (t * 1.3 + 1.2));
        col.g = 0.5 - 0.5 * cos(3.14159 * (t * 1.3 + 0.7));
        col.b = 0.5 - 0.5 * cos(3.14159 * (t * 1.3 + 0.2));
    }
    // 7: Neon - hot pink -> purple -> electric blue
    else if (u_palette == 6) {
        col.r = 0.5 - 0.5 * cos(3.14159 * (t * 1.4 + 0.2));
        col.g = 0.5 - 0.5 * cos(3.14159 * (t * 1.4 + 1.1));
        col.b = 0.5 - 0.5 * cos(3.14159 * (t * 1.4 + 0.6));
    }
    // 8: Gold - brown -> gold -> bright yellow
    else if (u_palette == 7) {
        col.r = clamp(t * 2.5,       0.0, 1.0);
        col.g = clamp(t * 2.5 - 0.4, 0.0, 1.0);
        col.b = clamp(t * 3.0 - 2.2, 0.0, 0.3);
    }
    // 9: Monochrome - white core with soft halo
    else if (u_palette == 8) {
        float lum = t * t * 2.0;
        col = vec3(clamp(lum, 0.0, 1.0));
    }
    // 0: Rainbow - full hue cycle across density
    else {
        float h = t * 6.0;
        float f = clamp(h - floor(h), 0.0, 1.0);
        if      (h < 1.0) { col = vec3(1.0,     f,       0.0     ); }
        else if (h < 2.0) { col = vec3(1.0-f,   1.0,     0.0     ); }
        else if (h < 3.0) { col = vec3(0.0,     1.0,     f       ); }
        else if (h < 4.0) { col = vec3(0.0,     1.0-f,   1.0     ); }
        else if (h < 5.0) { col = vec3(f,       0.0,     1.0     ); }
        else              { col = vec3(1.0,     0.0,     1.0-f   ); }
        col *= t;
    }

    // Saturation boost
    float grey = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(grey), col, 1.8);

    // Additive glow halo
    col += col * glow * 1.4;

    // Velocity shimmer
    col += vec3(0.08, 0.2, 0.4) * vm * d * 0.6;

    col *= t;
    float alpha = clamp(t * 8.0, 0.0, 1.0);
    gl_FragColor = vec4(col, alpha);
}
\0";

// ============================================================================
// GL EXTENSION FUNCTION POINTERS
// ============================================================================

def{}* glCreateShader_fp(int)                 -> int;
def{}* glShaderSource_fp(int,int,byte**,int*) -> void;
def{}* glCompileShader_fp(int)                -> void;
def{}* glCreateProgram_fp()                   -> int;
def{}* glAttachShader_fp(int,int)             -> void;
def{}* glLinkProgram_fp(int)                  -> void;
def{}* glUseProgram_fp(int)                   -> void;
def{}* glGetUniformLocation_fp(int,byte*)     -> int;
def{}* glUniform1i_fp(int,int)                -> void;
def{}* glUniform2f_fp(int,float,float)        -> void;
def{}* glActiveTexture_fp(int)                -> void;
def{}* glDeleteShader_fp(int)                 -> void;
def{}* glDeleteProgram_fp(int)                -> void;

def compile_shader(int shader_type, byte* src) -> int
{
    int shader;
    byte[1]* src_arr;
    int[1]   len_arr;
    shader       = glCreateShader_fp(shader_type);
    src_arr      = [src];
    len_arr[0]   = -1;
    glShaderSource_fp(shader, 1, @src_arr[0], @len_arr[0]);
    glCompileShader_fp(shader);
    return shader;
};

def link_program(int vert, int frag) -> int
{
    int prog;
    prog = glCreateProgram_fp();
    glAttachShader_fp(prog, vert);
    glAttachShader_fp(prog, frag);
    glLinkProgram_fp(prog);
    return prog;
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
    size_t field_bytes, dens_tex_bytes, vel_tex_bytes;
    HINSTANCE hInstance;
    HWND hwnd;
    HDC  hdc;
    MSG  msg;
    bool running;
    int  tex_dens,
         tex_vel,
         vert_sh,
         frag_sh,
         prog,
         u_dens,
         u_vel, u_res,
         u_palette,
         t, i;
    float px, py;
    RECT client_rect;
    SYSTEM_INFO_PARTIAL sysinfo;

    GetSystemInfo((void*)@sysinfo);
    g_num_threads = (int)sysinfo.dwNumberOfProcessors;
    if (g_num_threads < 1)           { g_num_threads = 1;           };
    if (g_num_threads > MAX_THREADS) { g_num_threads = MAX_THREADS; };

    field_bytes    = (size_t)(SIM_W * SIM_H * 8);
    dens_tex_bytes = (size_t)(SIM_W * SIM_H * 4);        // 1 float per cell
    vel_tex_bytes  = (size_t)(SIM_W * SIM_H * 4 * 2);    // 2 floats per cell

    g_dens      = (double*)fmalloc(field_bytes);
    g_dens_prev = (double*)fmalloc(field_bytes);
    g_vx        = (double*)fmalloc(field_bytes);
    g_vy        = (double*)fmalloc(field_bytes);
    g_vx_prev   = (double*)fmalloc(field_bytes);
    g_vy_prev   = (double*)fmalloc(field_bytes);
    g_dens_tex  = (float*)fmalloc(dens_tex_bytes);
    g_vel_tex   = (float*)fmalloc(vel_tex_bytes);
    g_part_x    = (float*)fmalloc((size_t)(NUM_PARTICLES * 4));
    g_part_y    = (float*)fmalloc((size_t)(NUM_PARTICLES * 4));

    particles_init();

    semaphore_init(@g_work_sem, 0);
    semaphore_init(@g_done_sem, 0);
    semaphore_init(@g_work_sem2, 0);
    semaphore_init(@g_done_sem2, 0);

    g_rows_per_thread = SIM_H / g_num_threads;
    if (g_rows_per_thread < 1) { g_rows_per_thread = 1; };

    for (t = 0; t < g_num_threads; t++)
    {
        g_slices[t].row_start  = t * g_rows_per_thread;
        g_slices[t].row_end    = (t == g_num_threads - 1) ? SIM_H : (t + 1) * g_rows_per_thread;
        g_slices[t].phase      = PHASE_DECAY;
        g_slices2[t].row_start = t * g_rows_per_thread;
        g_slices2[t].row_end   = (t == g_num_threads - 1) ? SIM_H : (t + 1) * g_rows_per_thread;
        g_slices2[t].phase     = PHASE_DECAY;
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
    gl.load_extensions();

    // Bind extension function pointers
    glCreateShader_fp       = _glCreateShader;
    glShaderSource_fp       = _glShaderSource;
    glCompileShader_fp      = _glCompileShader;
    glCreateProgram_fp      = _glCreateProgram;
    glAttachShader_fp       = _glAttachShader;
    glLinkProgram_fp        = _glLinkProgram;
    glUseProgram_fp         = _glUseProgram;
    glGetUniformLocation_fp = _glGetUniformLocation;
    glUniform1i_fp          = _glUniform1i;
    glUniform2f_fp          = _glUniform2f;
    glActiveTexture_fp      = _glActiveTexture;
    glDeleteShader_fp       = _glDeleteShader;
    glDeleteProgram_fp      = _glDeleteProgram;

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_TEXTURE_2D);

    // Compile and link shader
    vert_sh = compile_shader(GL_VERTEX_SHADER,   @VERT_SRC[0]);
    frag_sh = compile_shader(GL_FRAGMENT_SHADER, @FRAG_SRC[0]);
    prog    = link_program(vert_sh, frag_sh);

    u_dens    = glGetUniformLocation_fp(prog, "u_dens\0");
    u_vel     = glGetUniformLocation_fp(prog, "u_vel\0");
    u_res     = glGetUniformLocation_fp(prog, "u_res\0");
    u_palette = glGetUniformLocation_fp(prog, "u_palette\0");

    // Density texture - single channel float
    tex_dens = 0;
    glGenTextures(1, @tex_dens);
    glBindTexture(GL_TEXTURE_2D, tex_dens);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, (i32)GL_LUMINANCE, SIM_W, SIM_H, 0,
                 (i32)GL_LUMINANCE, (i32)GL_FLOAT, (void*)g_dens_tex);

    // Velocity texture - two channel (vx=luminance, vy=alpha)
    tex_vel = 0;
    glGenTextures(1, @tex_vel);
    glBindTexture(GL_TEXTURE_2D, tex_vel);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, (i32)GL_LUMINANCE_ALPHA, SIM_W, SIM_H, 0,
                 (i32)GL_LUMINANCE_ALPHA, (i32)GL_FLOAT, (void*)g_vel_tex);

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

        // Simulate
        add_source();
        vel_step();
        dens_step();
        dispatch_decay();

        // Update particles CPU-side
        particles_update();

        // Convert double fields to float upload buffers
        upload_textures();

        // Upload density texture to unit 0
        glActiveTexture_fp(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, tex_dens);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, SIM_W, SIM_H,
                        (i32)GL_LUMINANCE, (i32)GL_FLOAT, (void*)g_dens_tex);

        // Upload velocity texture to unit 1
        glActiveTexture_fp(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, tex_vel);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, SIM_W, SIM_H,
                        (i32)GL_LUMINANCE_ALPHA, (i32)GL_FLOAT, (void*)g_vel_tex);

        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);

        // Draw fluid via shader - fullscreen triangle
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glUseProgram_fp(prog);
        glUniform1i_fp(u_dens, 0);
        glUniform1i_fp(u_vel,  1);
        glUniform2f_fp(u_res, (float)SIM_W, (float)SIM_H);
        glUniform1i_fp(u_palette, g_palette);

        glBegin(GL_TRIANGLES);
        glTexCoord2f(0.0, 0.0); glVertex2f(-1.0, -1.0);
        glTexCoord2f(2.0, 0.0); glVertex2f( 3.0, -1.0);
        glTexCoord2f(0.0, 2.0); glVertex2f(-1.0,  3.0);
        glEnd();

        glUseProgram_fp(0);
        glDisable(GL_BLEND);

        // Draw particles as GL_POINTS on top of fluid
        // Switch to unit 0 so fixed-function point rendering works
        glActiveTexture_fp(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, 0);
        glActiveTexture_fp(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, 0);
        glActiveTexture_fp(GL_TEXTURE0);

        glPointSize(2.0);
        glColor4f(1.0, 1.0, 1.0, 1.0);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE);

        glBegin(GL_POINTS);
        for (i = 0; i < NUM_PARTICLES; i++)
        {
            px = g_part_x[i];
            py = g_part_y[i];
            // Only draw where density is present
            if (g_dens[(int)py * SIM_W + (int)px] > 15.0)
            {
                // Convert grid coords to NDC
                glVertex2f((px / (float)SIM_W) * 2.0 - 1.0,
                           (py / (float)SIM_H) * 2.0 - 1.0);
            };
        };
        glEnd();

        glDisable(GL_BLEND);

        gl.present();
    };

    // Shutdown
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

    glDeleteShader_fp(vert_sh);
    glDeleteShader_fp(frag_sh);
    glDeleteProgram_fp(prog);
    glDeleteTextures(1, @tex_dens);
    glDeleteTextures(1, @tex_vel);
    gl.__exit();

    ffree((u64)g_dens);
    ffree((u64)g_dens_prev);
    ffree((u64)g_vx);
    ffree((u64)g_vy);
    ffree((u64)g_vx_prev);
    ffree((u64)g_vy_prev);
    ffree((u64)g_dens_tex);
    ffree((u64)g_vel_tex);
    ffree((u64)g_part_x);
    ffree((u64)g_part_y);

    ReleaseDC(hwnd, hdc);
    UnregisterClassA((LPCSTR)class_name, hInstance);

    return 0;
};
