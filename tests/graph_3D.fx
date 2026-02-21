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

// Surface grid resolution (GRID_N x GRID_N vertices)
const int GRID_N = 16;

// Number of scatter / line points
const int PT_COUNT = 48;

// Number of bars (4x4 grid)
const int BAR_N = 4;

// ============================================================================
// Helpers: setup a Graph3D for a given tile in the 2x2 layout
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
// Panel 1: animated wireframe surface  z = sin(r + phase)
// xs_surf[col], ys_surf[row], zs_surf[row * GRID_N + col]
// ============================================================================

def fill_surface(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int col = 0;
    while (col < n)
    {
        xs[col] = (float)col / (float)(n - 1);
        col = col + 1;
    };

    int row = 0;
    while (row < n)
    {
        ys[row] = (float)row / (float)(n - 1);
        row = row + 1;
    };

    row = 0;
    while (row < n)
    {
        col = 0;
        while (col < n)
        {
            float fx = xs[col] - 0.5;
            float fy = ys[row] - 0.5;
            float r  = sqrt(fx * fx + fy * fy) * 8.0;
            float z  = (sin(r + phase) + 1.0) * 0.5;
            zs[row * n + col] = z;
            col = col + 1;
        };
        row = row + 1;
    };
};

// ============================================================================
// Panel 2: animated 3D helix line + scatter
// ============================================================================

def fill_helix(float* xs, float* ys, float* zs, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t  = (float)i / (float)(count - 1);
        float ang = t * 4.0 * PIF + phase;
        xs[i] = (cos(ang) + 1.0) * 0.5;
        ys[i] = t;
        zs[i] = (sin(ang) + 1.0) * 0.5;
        i = i + 1;
    };
};

// ============================================================================
// Panel 3: 3D scatter cloud  (points on a unit sphere, slowly rotating dataset)
// ============================================================================

def fill_sphere_scatter(float* xs, float* ys, float* zs, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t    = (float)i / (float)count;
        float phi  = t * PIF;
        float thet = (float)i * 2.399963 + phase;   // golden-angle spiral
        float sp   = sin(phi);
        xs[i] = (cos(thet) * sp + 1.0) * 0.5;
        ys[i] = (cos(phi)       + 1.0) * 0.5;
        zs[i] = (sin(thet) * sp + 1.0) * 0.5;
        i = i + 1;
    };
};

// ============================================================================
// Panel 4: 3D bar chart on a 4x4 grid, animated heights
// xs_bar[i] = col position, zs_bar[i] = row position, ys_bar[i] = height
// ============================================================================

def fill_bars3d(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i = 0;
    while (i < n)
    {
        int col = i % BAR_N;
        int row = i / BAR_N;
        float fc = (float)col / (float)(BAR_N - 1);
        float fr = (float)row / (float)(BAR_N - 1);
        xs[i] = fc;
        zs[i] = fr;
        float ang = (fc + fr) * PIF * 2.0 + phase;
        ys[i] = (sin(ang) + 1.0) * 0.5;
        i = i + 1;
    };
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("redgraphing.fx 3D Demo\0", WIN_W, WIN_H, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    Canvas c(win.handle, win.device_context);

    // ---- Allocate surface arrays (GRID_N x GRID_N) ----
    int surf_cells = GRID_N * GRID_N;
    float* surf_xs = (float*)fmalloc((u64)GRID_N      * 4);
    float* surf_ys = (float*)fmalloc((u64)GRID_N      * 4);
    float* surf_zs = (float*)fmalloc((u64)surf_cells  * 4);

    // ---- Allocate helix arrays ----
    float* hel_xs = (float*)fmalloc((u64)PT_COUNT * 4);
    float* hel_ys = (float*)fmalloc((u64)PT_COUNT * 4);
    float* hel_zs = (float*)fmalloc((u64)PT_COUNT * 4);

    // ---- Allocate sphere scatter arrays ----
    float* sph_xs = (float*)fmalloc((u64)PT_COUNT * 4);
    float* sph_ys = (float*)fmalloc((u64)PT_COUNT * 4);
    float* sph_zs = (float*)fmalloc((u64)PT_COUNT * 4);

    // ---- Allocate bar arrays ----
    int bar_count = BAR_N * BAR_N;
    float* bar_xs = (float*)fmalloc((u64)bar_count * 4);
    float* bar_ys = (float*)fmalloc((u64)bar_count * 4);
    float* bar_zs = (float*)fmalloc((u64)bar_count * 4);

    // ---- Setup Graph3D descriptors ----
    Graph3D g1, g2, g3, g4;

    setup_panel3d(@g1, 0, 0);
    setup_panel3d(@g2, 1, 0);
    setup_panel3d(@g3, 0, 1);
    setup_panel3d(@g4, 1, 1);

    // Each panel gets a slightly different viewing angle
    g1.rot_x = 0.5;   g1.rot_y = 0.5;
    g2.rot_x = 0.4;   g2.rot_y = 0.3;
    g3.rot_x = 0.35;  g3.rot_y = 0.6;
    g4.rot_x = 0.55;  g4.rot_y = 0.4;

    // Colors
    DWORD col_bg        = RGB( 18,  18,  24);
    DWORD col_grid      = RGB( 40,  40,  58);
    DWORD col_axis      = RGB(110, 110, 130);
    DWORD col_box       = RGB( 60,  60,  80);
    DWORD col_text      = RGB(200, 200, 220);

    DWORD col_surf      = RGB( 60, 180, 255);
    DWORD col_helix_ln  = RGB(255, 120,  40);
    DWORD col_helix_sc  = RGB(255, 220,  60);
    DWORD col_sphere    = RGB(120, 255, 140);
    DWORD col_bars      = RGB(200,  80, 255);

    float phase = 0.0;

    // Label strings
    noopstr lbl_surf   = "sin(r) Surface\0";
    noopstr lbl_helix  = "Helix\0";
    noopstr lbl_sphere = "Sphere Scatter\0";
    noopstr lbl_bars   = "3D Bar Chart\0";
    noopstr lbl_x      = "X\0";
    noopstr lbl_y      = "Y\0";
    noopstr lbl_z      = "Z\0";

    while (win.process_messages())
    {
        // Slowly rotate all panels by incrementing rot_y each frame
        g1.rot_y = g1.rot_y + 0.008;
        g2.rot_y = g2.rot_y + 0.010;
        g3.rot_y = g3.rot_y + 0.007;
        g4.rot_y = g4.rot_y + 0.009;

        // Rebuild data
        fill_surface(surf_xs, surf_ys, surf_zs, GRID_N, phase);
        fill_helix(hel_xs, hel_ys, hel_zs, PT_COUNT, phase);
        fill_sphere_scatter(sph_xs, sph_ys, sph_zs, PT_COUNT, phase);
        fill_bars3d(bar_xs, bar_ys, bar_zs, bar_count, phase);

        c.clear(col_bg);

        // ---- Panel 1: Wireframe surface ----
        draw_box3d(@c, @g1, col_box, 1);
        draw_grid3d(@c, @g1, 4, 4, col_grid);
        draw_axes3d(@c, @g1, col_axis, 1);
        plot_surface(@c, @g1, surf_xs, surf_ys, surf_zs, GRID_N, GRID_N, col_surf, 1);
        draw_axes3d_labels(@c, @g1, lbl_x, lbl_y, lbl_z, col_text);
        draw_title3d(@c, @g1, lbl_surf, col_text);

        // ---- Panel 2: Helix line + scatter ----
        draw_box3d(@c, @g2, col_box, 1);
        draw_grid3d(@c, @g2, 4, 4, col_grid);
        draw_axes3d(@c, @g2, col_axis, 1);
        plot_line3d(@c, @g2, hel_xs, hel_ys, hel_zs, PT_COUNT, col_helix_ln, 2);
        plot_scatter3d_circles(@c, @g2, hel_xs, hel_ys, hel_zs, PT_COUNT, col_helix_sc, 3);
        draw_axes3d_labels(@c, @g2, lbl_x, lbl_y, lbl_z, col_text);
        draw_title3d(@c, @g2, lbl_helix, col_text);

        // ---- Panel 3: Sphere scatter ----
        draw_box3d(@c, @g3, col_box, 1);
        draw_grid3d(@c, @g3, 4, 4, col_grid);
        draw_axes3d(@c, @g3, col_axis, 1);
        plot_scatter3d(@c, @g3, sph_xs, sph_ys, sph_zs, PT_COUNT, col_sphere, 3);
        draw_axes3d_labels(@c, @g3, lbl_x, lbl_y, lbl_z, col_text);
        draw_title3d(@c, @g3, lbl_sphere, col_text);

        // ---- Panel 4: 3D bar chart ----
        draw_box3d(@c, @g4, col_box, 1);
        draw_grid3d(@c, @g4, 4, 4, col_grid);
        draw_axes3d(@c, @g4, col_axis, 1);
        plot_bars3d(@c, @g4, bar_xs, bar_ys, bar_zs, bar_count, col_bars, 4);
        draw_axes3d_labels(@c, @g4, lbl_x, lbl_y, lbl_z, col_text);
        draw_title3d(@c, @g4, lbl_bars, col_text);

        phase = phase + 0.03;
        if (phase > 2.0 * PIF) { phase = phase - 2.0 * PIF; };

        Sleep(16);
    };

    c.__exit();
    win.__exit();

    ffree((u64)surf_xs);
    ffree((u64)surf_ys);
    ffree((u64)surf_zs);
    ffree((u64)hel_xs);
    ffree((u64)hel_ys);
    ffree((u64)hel_zs);
    ffree((u64)sph_xs);
    ffree((u64)sph_ys);
    ffree((u64)sph_zs);
    ffree((u64)bar_xs);
    ffree((u64)bar_ys);
    ffree((u64)bar_zs);

    return 0;
};
