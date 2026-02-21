#import "standard.fx", "redmath.fx", "redwindows.fx", "redgraphing.fx", "redallocators.fx";

using standard::system::windows;
using standard::math;
using standard::graphing;
using standard::graphing::graph3d;
using standard::graphing::graph3d::generators;
using standard::memory::allocators::stdheap;

// ============================================================================
// LAYOUT
// 4x4 grid of panels, each 200x200 px with 30px margin between them.
// Total window: 4*200 + 5*30 = 950 px square.
// ============================================================================

const int COLS     = 4;
const int ROWS     = 4;
const int CELL     = 200;
const int GAP      = 30;
const int WIN_SIZE = COLS * CELL + (COLS + 1) * GAP;   // 950

const int CURVE_N  = 80;    // points for line/scatter curves
const int SURF_N   = 12;    // grid for surface plots (12x12)
const int BAR_N    = 5;     // bars per axis (5x5 = 25 bars)

// ============================================================================
// Panel setup
// ============================================================================

def setup_panel(Graph3D* g, int col, int row) -> void
{
    g.cx    = GAP + col * (CELL + GAP) + CELL / 2;
    g.cy    = GAP + row * (CELL + GAP) + CELL / 2;
    g.fov   = 220.0;
    g.cam_z = 9f;
    g.rot_z = 0.0;
    g.x_min = 0.0;  g.x_max = 1.0;
    g.y_min = 0.0;  g.y_max = 1.0;
    g.z_min = 0.0;  g.z_max = 1.0;
    g.scale = 3.75;
    return;
};

def draw_frame(Canvas* c, Graph3D* g, DWORD col_box, DWORD col_grid, DWORD col_axis, DWORD col_text, noopstr title) -> void
{
    draw_box3d(@c, @g, col_box, 1);
    draw_grid3d(@c, @g, 3, 3, col_grid);
    draw_axes3d(@c, @g, col_axis, 1);
    draw_title3d(@c, @g, title, col_text);
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("redgraphing.fx - 16 Panel 3D Demo\0", WIN_SIZE, WIN_SIZE, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    Canvas c(win.handle, win.device_context);

    // ---- Allocate surface arrays (SURF_N x SURF_N) ----
    int surf_cells = SURF_N * SURF_N;
    float* sx = (float*)fmalloc((u64)SURF_N     * 4);
    float* sy = (float*)fmalloc((u64)SURF_N     * 4);
    float* sz = (float*)fmalloc((u64)surf_cells * 4);

    // ---- Shared XYZ triple for curve/scatter plots ----
    float* ax = (float*)fmalloc((u64)CURVE_N * 4);
    float* ay = (float*)fmalloc((u64)CURVE_N * 4);
    float* az = (float*)fmalloc((u64)CURVE_N * 4);

    // ---- Bar arrays (BAR_N * BAR_N) ----
    int bar_cells = BAR_N * BAR_N;
    float* bx = (float*)fmalloc((u64)bar_cells * 4);
    float* by = (float*)fmalloc((u64)bar_cells * 4);
    float* bz = (float*)fmalloc((u64)bar_cells * 4);

    // ---- Saddle and interference are static — fill once ----
    gen_saddle(sx, sy, sz, SURF_N);

    // ---- Graph3D array: 16 panels ----
    Graph3D[16] g;

    int pi = 0;
    while (pi < 16)
    {
        int col = pi % COLS;
        int row = pi / COLS;
        setup_panel(@g[pi], col, row);
        pi = pi + 1;
    };

    // Per-panel pitch angles (variety)
    g[0].rot_x  = 0.50;  g[0].rot_y  = 0.30;
    g[1].rot_x  = 0.50;  g[1].rot_y  = 0.50;
    g[2].rot_x  = 0.45;  g[2].rot_y  = 0.40;
    g[3].rot_x  = 0.55;  g[3].rot_y  = 0.60;
    g[4].rot_x  = 0.40;  g[4].rot_y  = 0.30;
    g[5].rot_x  = 0.50;  g[5].rot_y  = 0.20;
    g[6].rot_x  = 0.45;  g[6].rot_y  = 0.70;
    g[7].rot_x  = 0.40;  g[7].rot_y  = 0.50;
    g[8].rot_x  = 0.55;  g[8].rot_y  = 0.40;
    g[9].rot_x  = 0.35;  g[9].rot_y  = 0.60;
    g[10].rot_x = 0.50;  g[10].rot_y = 0.30;
    g[11].rot_x = 0.45;  g[11].rot_y = 0.50;
    g[12].rot_x = 0.55;  g[12].rot_y = 0.40;
    g[13].rot_x = 0.40;  g[13].rot_y = 0.30;
    g[14].rot_x = 0.50;  g[14].rot_y = 0.60;
    g[15].rot_x = 0.45;  g[15].rot_y = 0.50;

    // Colors
    DWORD col_bg   = RGB( 14,  14,  20);
    DWORD col_grid = RGB( 35,  35,  50);
    DWORD col_axis = RGB( 90,  90, 110);
    DWORD col_box  = RGB( 55,  55,  75);
    DWORD col_text = RGB(190, 190, 210);

    // Per-panel data colors
    DWORD[16] colors;
    colors[0]  = RGB( 60, 180, 255);
    colors[1]  = RGB(255, 180,  40);
    colors[2]  = RGB(100, 255, 120);
    colors[3]  = RGB(220,  80, 255);
    colors[4]  = RGB(255,  80, 100);
    colors[5]  = RGB( 80, 220, 200);
    colors[6]  = RGB(255, 160,  60);
    colors[7]  = RGB(160, 100, 255);
    colors[8]  = RGB( 60, 255, 180);
    colors[9]  = RGB(255, 220,  60);
    colors[10] = RGB(255, 100, 180);
    colors[11] = RGB( 80, 160, 255);
    colors[12] = RGB(200, 255,  80);
    colors[13] = RGB(255, 140,  80);
    colors[14] = RGB(120, 255, 255);
    colors[15] = RGB(220, 180, 255);

    // Panel titles
    noopstr t0  = "Sine Ripple\0";
    noopstr t1  = "Saddle\0";
    noopstr t2  = "Peaks\0";
    noopstr t3  = "Torus Surf\0";
    noopstr t4  = "Helix\0";
    noopstr t5  = "Knot (2,3)\0";
    noopstr t6  = "Fig-8 Knot\0";
    noopstr t7  = "Lissajous\0";
    noopstr t8  = "Sphere\0";
    noopstr t9  = "Cone\0";
    noopstr t10 = "Double Helix\0";
    noopstr t11 = "Spiral Coil\0";
    noopstr t12 = "Bars 3D\0";
    noopstr t13 = "Viviani\0";
    noopstr t14 = "Cluster\0";
    noopstr t15 = "Interference\0";

    float phase = 0.0;

    while (win.process_messages())
    {
        // Rotate all panels - different speeds for variety
        g[0].rot_y  = g[0].rot_y  + 0.009;
        g[1].rot_y  = g[1].rot_y  + 0.007;
        g[2].rot_y  = g[2].rot_y  + 0.008;
        g[3].rot_y  = g[3].rot_y  + 0.010;
        g[4].rot_y  = g[4].rot_y  + 0.011;
        g[5].rot_y  = g[5].rot_y  + 0.009;
        g[6].rot_y  = g[6].rot_y  + 0.008;
        g[7].rot_y  = g[7].rot_y  + 0.010;
        g[8].rot_y  = g[8].rot_y  + 0.007;
        g[9].rot_y  = g[9].rot_y  + 0.009;
        g[10].rot_y = g[10].rot_y + 0.011;
        g[11].rot_y = g[11].rot_y + 0.008;
        g[12].rot_y = g[12].rot_y + 0.009;
        g[13].rot_y = g[13].rot_y + 0.010;
        g[14].rot_y = g[14].rot_y + 0.007;
        g[15].rot_y = g[15].rot_y + 0.008;

        c.clear(col_bg);

        // ---- 0: Sine ripple surface ----
        gen_ripple(sx, sy, sz, SURF_N, phase);
        draw_frame(@c, @g[0], col_box, col_grid, col_axis, col_text, t0);
        plot_surface(@c, @g[0], sx, sy, sz, SURF_N, SURF_N, colors[0], 1);

        // ---- 1: Saddle surface (static geometry) ----
        gen_saddle(sx, sy, sz, SURF_N);
        draw_frame(@c, @g[1], col_box, col_grid, col_axis, col_text, t1);
        plot_surface(@c, @g[1], sx, sy, sz, SURF_N, SURF_N, colors[1], 1);

        // ---- 2: Peaks surface ----
        gen_peaks(sx, sy, sz, SURF_N, phase);
        auto_range_z(@g[2], sz, surf_cells, 0.05);
        draw_frame(@c, @g[2], col_box, col_grid, col_axis, col_text, t2);
        plot_surface(@c, @g[2], sx, sy, sz, SURF_N, SURF_N, colors[2], 1);

        // ---- 3: Torus surface rows ----
        gen_torus_surf(sx, sy, sz, SURF_N, phase);
        draw_frame(@c, @g[3], col_box, col_grid, col_axis, col_text, t3);
        plot_surface(@c, @g[3], sx, sy, sz, SURF_N, SURF_N, colors[3], 1);

        // ---- 4: Helix - line only ----
        gen_helix(ax, ay, az, CURVE_N, phase);
        draw_frame(@c, @g[4], col_box, col_grid, col_axis, col_text, t4);
        plot_line3d(@c, @g[4], ax, ay, az, CURVE_N, colors[4], 2);

        // ---- 5: Torus knot (2,3) - line + square scatter ----
        gen_knot_23(ax, ay, az, CURVE_N, phase);
        auto_range3d(@g[5], ax, ay, az, CURVE_N, 0.05);
        draw_frame(@c, @g[5], col_box, col_grid, col_axis, col_text, t5);
        plot_line3d(@c, @g[5], ax, ay, az, CURVE_N, colors[5], 1);
        plot_scatter3d(@c, @g[5], ax, ay, az, CURVE_N / 5, colors[5], 2);

        // ---- 6: Figure-8 knot - line + circle scatter ----
        gen_fig8(ax, ay, az, CURVE_N, phase);
        auto_range3d(@g[6], ax, ay, az, CURVE_N, 0.05);
        draw_frame(@c, @g[6], col_box, col_grid, col_axis, col_text, t6);
        plot_line3d(@c, @g[6], ax, ay, az, CURVE_N, colors[6], 1);
        plot_scatter3d_circles(@c, @g[6], ax, ay, az, CURVE_N / 4, colors[6], 3);

        // ---- 7: Lissajous - line + circle scatter ----
        gen_lissajous(ax, ay, az, CURVE_N, phase);
        draw_frame(@c, @g[7], col_box, col_grid, col_axis, col_text, t7);
        plot_line3d(@c, @g[7], ax, ay, az, CURVE_N, colors[7], 1);
        plot_scatter3d_circles(@c, @g[7], ax, ay, az, CURVE_N / 3, colors[7], 2);

        // ---- 8: Sphere scatter - circles ----
        gen_sphere(ax, ay, az, CURVE_N, phase);
        draw_frame(@c, @g[8], col_box, col_grid, col_axis, col_text, t8);
        plot_scatter3d_circles(@c, @g[8], ax, ay, az, CURVE_N, colors[8], 3);

        // ---- 9: Cone scatter - squares ----
        gen_cone(ax, ay, az, CURVE_N, phase);
        draw_frame(@c, @g[9], col_box, col_grid, col_axis, col_text, t9);
        plot_scatter3d(@c, @g[9], ax, ay, az, CURVE_N, colors[9], 2);

        // ---- 10: Double helix - line ----
        gen_double_helix(ax, ay, az, CURVE_N, phase);
        draw_frame(@c, @g[10], col_box, col_grid, col_axis, col_text, t10);
        plot_line3d(@c, @g[10], ax, ay, az, CURVE_N, colors[10], 1);

        // ---- 11: Spiral coil - line + squares ----
        gen_spiral_coil(ax, ay, az, CURVE_N, phase);
        draw_frame(@c, @g[11], col_box, col_grid, col_axis, col_text, t11);
        plot_line3d(@c, @g[11], ax, ay, az, CURVE_N, colors[11], 1);
        plot_scatter3d(@c, @g[11], ax, ay, az, CURVE_N / 4, colors[11], 2);

        // ---- 12: 3D bars ----
        gen_bars(bx, by, bz, bar_cells, BAR_N, phase);
        draw_frame(@c, @g[12], col_box, col_grid, col_axis, col_text, t12);
        plot_bars3d(@c, @g[12], bx, by, bz, bar_cells, colors[12], 4);

        // ---- 13: Viviani curve - line + circles ----
        gen_viviani(ax, ay, az, CURVE_N, phase);
        draw_frame(@c, @g[13], col_box, col_grid, col_axis, col_text, t13);
        plot_line3d(@c, @g[13], ax, ay, az, CURVE_N, colors[13], 2);
        plot_scatter3d_circles(@c, @g[13], ax, ay, az, CURVE_N / 5, colors[13], 3);

        // ---- 14: Cluster scatter - squares ----
        gen_cluster(ax, ay, az, CURVE_N, phase);
        draw_frame(@c, @g[14], col_box, col_grid, col_axis, col_text, t14);
        plot_scatter3d(@c, @g[14], ax, ay, az, CURVE_N, colors[14], 2);

        // ---- 15: Wave interference surface ----
        gen_interference(sx, sy, sz, SURF_N, phase);
        draw_frame(@c, @g[15], col_box, col_grid, col_axis, col_text, t15);
        plot_surface(@c, @g[15], sx, sy, sz, SURF_N, SURF_N, colors[15], 1);

        phase = phase + 0.025;
        if (phase > 2.0 * PIF) { phase = phase - 2.0 * PIF; };

        Sleep(16);
    };

    c.__exit();
    win.__exit();

    ffree((u64)sx);
    ffree((u64)sy);
    ffree((u64)sz);
    ffree((u64)ax);
    ffree((u64)ay);
    ffree((u64)az);
    ffree((u64)bx);
    ffree((u64)by);
    ffree((u64)bz);

    return 0;
};
