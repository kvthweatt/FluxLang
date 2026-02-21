#import "standard.fx", "redmath.fx", "redwindows.fx", "redgraphing.fx", "redallocators.fx";

using standard::system::windows;
using standard::math;
using standard::graphing;
using standard::graphing::graph3d;
using standard::memory::allocators::stdheap;

extern
{
    def !!
        Sleep(u32) -> void;
};

// ============================================================================
// CONSTANTS
// ============================================================================

const int WIN_W   = 1010,
          WIN_H   = 1010,
          MARGIN  = 50,
          PANEL_W = 425,
          PANEL_H = 425;

const int CURVE_COUNT = 120;   // points for line/scatter curves
const int SURF_N      = 18;    // grid resolution for saddle surface
const int CONE_COUNT  = 80;    // points for cone scatter

// ============================================================================
// Panel setup helper
// ============================================================================

def setup_panel3d(Graph3D* g, int col, int row) -> void
{
    g.cx    = MARGIN + col * (PANEL_W + MARGIN) + PANEL_W / 2;
    g.cy    = MARGIN + row * (PANEL_H + MARGIN) + PANEL_H / 2;
    g.fov   = 220.0;
    g.cam_z = 4.0;
    g.rot_z = 0.0;
    g.x_min = 0.0;  g.x_max = 1.0;
    g.y_min = 0.0;  g.y_max = 1.0;
    g.z_min = 0.0;  g.z_max = 1.0;
    g.scale = 2.0;
    return;
};

// ============================================================================
// Panel 1: Torus knot  (3,2)
// x = (2 + cos(3t/2)) * cos(t)
// y = (2 + cos(3t/2)) * sin(t)
// z =  sin(3t/2)
// Normalised into [0,1] after generation via auto_range3d.
// Drawn as a line with square scatter markers at every 4th point.
// ============================================================================

def fill_torus_knot(float* xs, float* ys, float* zs, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t  = (float)i / (float)(count - 1) * 2.0 * PIF + phase;
        float r  = 2.0 + cos(1.5 * t);
        xs[i]    = r * cos(t);
        ys[i]    = sin(1.5 * t);
        zs[i]    = r * sin(t);
        i = i + 1;
    };
};

// ============================================================================
// Panel 2: Saddle surface  z = x^2 - y^2  (hyperbolic paraboloid)
// Rendered as a wireframe surface via plot_surface.
// ============================================================================

def fill_saddle(float* xs, float* ys, float* zs, int n) -> void
{
    // xs and ys are the axis ticks; zs is the n*n height grid
    int i = 0;
    while (i < n)
    {
        float t  = (float)i / (float)(n - 1);   // 0..1
        float v  = t * 2.0 - 1.0;               // -1..1
        xs[i]    = t;
        ys[i]    = t;

        int j = 0;
        while (j < n)
        {
            float u = (float)j / (float)(n - 1) * 2.0 - 1.0;  // -1..1
            // z = u^2 - v^2, remapped from [-1,1] to [0,1]
            zs[i * n + j] = (u * u - v * v + 1.0) * 0.5;
            j = j + 1;
        };
        i = i + 1;
    };
};

// ============================================================================
// Panel 3: Lissajous 3D curve  a=3, b=2, c=5
// x = sin(at + phase)
// y = sin(bt)
// z = cos(ct + phase*0.7)
// ============================================================================

def fill_lissajous(float* xs, float* ys, float* zs, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t  = (float)i / (float)(count - 1) * 2.0 * PIF;
        xs[i]    = (sin(3.0 * t + phase)       + 1.0) * 0.5;
        ys[i]    = (sin(2.0 * t)               + 1.0) * 0.5;
        zs[i]    = (cos(5.0 * t + phase * 0.7) + 1.0) * 0.5;
        i = i + 1;
    };
};

// ============================================================================
// Panel 4: Parametric cone scatter
// Points sampled on the surface of a cone: r = 1 - h, x=r*cos(a), z=r*sin(a)
// Slowly rotates the spiral angle with phase.
// ============================================================================

def fill_cone(float* xs, float* ys, float* zs, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t   = (float)i / (float)(count - 1);
        float h   = t;                                   // height 0..1
        float r   = 1.0 - h;                            // radius narrows to tip
        float ang = t * 6.0 * PIF + phase;
        xs[i]     = (r * cos(ang) + 1.0) * 0.5;
        ys[i]     = h;
        zs[i]     = (r * sin(ang) + 1.0) * 0.5;
        i = i + 1;
    };
};

// ============================================================================
// Common panel draw wrapper: box, grid, axes, labels
// ============================================================================

def draw_frame(Canvas* c, Graph3D* g, DWORD col_box, DWORD col_grid, DWORD col_axis, DWORD col_text, byte* title, byte* lx, byte* ly, byte* lz) -> void
{
    draw_box3d(@c, @g, col_box, 1);
    draw_grid3d(@c, @g, 4, 4, col_grid);
    draw_axes3d(@c, @g, col_axis, 1);
    draw_axes3d_labels(@c, @g, lx, ly, lz, col_text);
    draw_title3d(@c, @g, title, col_text);
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("redgraphing.fx 3D Demo 2\0", WIN_W, WIN_H, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    Canvas c(win.handle, win.device_context);

    // ---- Panel 1: torus knot ----
    float* tk_xs = (float*)fmalloc((u64)CURVE_COUNT * 4);
    float* tk_ys = (float*)fmalloc((u64)CURVE_COUNT * 4);
    float* tk_zs = (float*)fmalloc((u64)CURVE_COUNT * 4);

    // ---- Panel 2: saddle surface ----
    int surf_cells = SURF_N * SURF_N;
    float* sd_xs = (float*)fmalloc((u64)SURF_N      * 4);
    float* sd_ys = (float*)fmalloc((u64)SURF_N      * 4);
    float* sd_zs = (float*)fmalloc((u64)surf_cells  * 4);
    fill_saddle(sd_xs, sd_ys, sd_zs, SURF_N);   // static, fill once

    // ---- Panel 3: Lissajous ----
    float* lj_xs = (float*)fmalloc((u64)CURVE_COUNT * 4);
    float* lj_ys = (float*)fmalloc((u64)CURVE_COUNT * 4);
    float* lj_zs = (float*)fmalloc((u64)CURVE_COUNT * 4);

    // ---- Panel 4: cone scatter ----
    float* cn_xs = (float*)fmalloc((u64)CONE_COUNT * 4);
    float* cn_ys = (float*)fmalloc((u64)CONE_COUNT * 4);
    float* cn_zs = (float*)fmalloc((u64)CONE_COUNT * 4);

    // ---- Graph3D descriptors ----
    Graph3D g1, g2, g3, g4;

    setup_panel3d(@g1, 0, 0);
    setup_panel3d(@g2, 1, 0);
    setup_panel3d(@g3, 0, 1);
    setup_panel3d(@g4, 1, 1);

    g1.rot_x = 0.45;  g1.rot_y = 0.3;
    g2.rot_x = 0.5;   g2.rot_y = 0.6;
    g3.rot_x = 0.4;   g3.rot_y = 0.5;
    g4.rot_x = 0.35;  g4.rot_y = 0.4;

    // Colors
    DWORD col_bg     = RGB( 18,  18,  24);
    DWORD col_grid   = RGB( 40,  40,  58);
    DWORD col_axis   = RGB(110, 110, 130);
    DWORD col_box    = RGB( 60,  60,  80);
    DWORD col_text   = RGB(200, 200, 220);

    DWORD col_tk_ln  = RGB( 80, 220, 255);   // torus knot line  - cyan
    DWORD col_tk_sc  = RGB(255,  80, 160);   // torus knot dots  - pink
    DWORD col_saddle = RGB(255, 180,  40);   // saddle surface   - amber
    DWORD col_lj_ln  = RGB(140, 255, 100);   // Lissajous line   - lime
    DWORD col_lj_sc  = RGB(255, 255, 100);   // Lissajous dots   - yellow
    DWORD col_cone   = RGB(180,  80, 255);   // cone scatter     - violet

    noopstr lbl_x = "X\0";
    noopstr lbl_y = "Y\0";
    noopstr lbl_z = "Z\0";

    noopstr lbl_tk  = "Torus Knot (3,2)\0";
    noopstr lbl_sd  = "Saddle Surface\0";
    noopstr lbl_lj  = "Lissajous 3D\0";
    noopstr lbl_cn  = "Cone Scatter\0";

    float phase = 0.0;

    while (win.process_messages())
    {
        // Animate rotation
        g1.rot_y = g1.rot_y + 0.009;
        g2.rot_y = g2.rot_y + 0.007;
        g3.rot_y = g3.rot_y + 0.011;
        g4.rot_y = g4.rot_y + 0.008;

        // Rebuild animated data
        fill_torus_knot(tk_xs, tk_ys, tk_zs, CURVE_COUNT, phase);
        auto_range3d(@g1, tk_xs, tk_ys, tk_zs, CURVE_COUNT, 0.05);

        fill_lissajous(lj_xs, lj_ys, lj_zs, CURVE_COUNT, phase);
        fill_cone(cn_xs, cn_ys, cn_zs, CONE_COUNT, phase);

        c.clear(col_bg);

        // ---- Panel 1: Torus knot - line + square scatter every 4th point ----
        draw_frame(@c, @g1, col_box, col_grid, col_axis, col_text, lbl_tk, lbl_x, lbl_y, lbl_z);
        plot_line3d(@c, @g1, tk_xs, tk_ys, tk_zs, CURVE_COUNT, col_tk_ln, 1);
        plot_scatter3d(@c, @g1, tk_xs, tk_ys, tk_zs, CURVE_COUNT / 4, col_tk_sc, 3);

        // ---- Panel 2: Saddle surface - static geometry, only rotates ----
        draw_frame(@c, @g2, col_box, col_grid, col_axis, col_text, lbl_sd, lbl_x, lbl_y, lbl_z);
        plot_surface(@c, @g2, sd_xs, sd_ys, sd_zs, SURF_N, SURF_N, col_saddle, 1);

        // ---- Panel 3: Lissajous - line + circle scatter ----
        draw_frame(@c, @g3, col_box, col_grid, col_axis, col_text, lbl_lj, lbl_x, lbl_y, lbl_z);
        plot_line3d(@c, @g3, lj_xs, lj_ys, lj_zs, CURVE_COUNT, col_lj_ln, 1);
        plot_scatter3d_circles(@c, @g3, lj_xs, lj_ys, lj_zs, CURVE_COUNT / 3, col_lj_sc, 3);

        // ---- Panel 4: Cone scatter - square markers ----
        draw_frame(@c, @g4, col_box, col_grid, col_axis, col_text, lbl_cn, lbl_x, lbl_y, lbl_z);
        plot_scatter3d(@c, @g4, cn_xs, cn_ys, cn_zs, CONE_COUNT, col_cone, 3);

        phase = phase + 0.025;
        if (phase > 2.0 * PIF) { phase = phase - 2.0 * PIF; };

        Sleep(16);
    };

    c.__exit();
    win.__exit();

    ffree((u64)tk_xs);
    ffree((u64)tk_ys);
    ffree((u64)tk_zs);
    ffree((u64)sd_xs);
    ffree((u64)sd_ys);
    ffree((u64)sd_zs);
    ffree((u64)lj_xs);
    ffree((u64)lj_ys);
    ffree((u64)lj_zs);
    ffree((u64)cn_xs);
    ffree((u64)cn_ys);
    ffree((u64)cn_zs);

    return 0;
};
