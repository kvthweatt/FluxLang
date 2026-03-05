#import "standard.fx", "redmath.fx", "redwindows.fx", "redgraphing.fx", "redopengl.fx", "redallocators.fx";

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
// OpenGL helpers - convert a packed DWORD RGB color to float r,g,b [0..1]
// ============================================================================

def dword_to_r(DWORD c) -> float { return (float)((c) & 0xFF) / 255.0; };
def dword_to_g(DWORD c) -> float { return (float)(((c) >> 8) & 0xFF) / 255.0; };
def dword_to_b(DWORD c) -> float { return (float)(((c) >> 16) & 0xFF) / 255.0; };

// ============================================================================
// GL 3D helpers - replicates the software-projection pipeline from redgraphing
// but emits real 3D geometry into OpenGL's fixed-function pipeline.
//
// Each panel is drawn by:
//   1. Setting a scissor rect and viewport to the panel cell.
//   2. Loading a perspective projection and a look-at view matrix.
//   3. Loading a model matrix that applies the Graph3D euler rotations and
//      the normalisation scale so data maps to [-0.5, 0.5] on each axis.
//   4. Issuing glBegin/glEnd calls that match the original draw_* semantics.
// ============================================================================

// Map a data value to normalised [-0.5, 0.5] space (same formula as redgraphing norm())
def gnorm(float val, float lo, float hi, float sc) -> float
{
    float range = hi - lo;
    if (range == 0.0) { return 0.0; };
    return ((val - lo) / range - 0.5) * sc;
};

// Set up the projection and modelview matrices for a panel.
// Call this once per panel before issuing any geometry.
def setup_panel_gl(Graph3D* g, int win_w, int win_h) -> void
{
    // Compute pixel rect for this panel (same formula as setup_panel in the original)
    int px = g.cx - CELL / 2;
    int py = g.cy - CELL / 2;

    // OpenGL viewport origin is bottom-left; window origin is top-left.
    int gl_y = win_h - py - CELL;

    glViewport(px, gl_y, CELL, CELL);
    glScissor(px, gl_y, CELL, CELL);

    // Projection
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    Matrix4 proj;
    mat4_perspective(0.872665, 1.0, 0.1, 100.0, @proj);
    glLoadMatrixf(@proj.m[0]);

    // View: camera sits at (0, 0, cam_z) looking at origin
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    GLVec3 eye;    eye.x    = 0.0; eye.y    = 0.0; eye.z    = g.cam_z;
    GLVec3 target; target.x = 0.0; target.y = 0.0; target.z = 0.0;
    GLVec3 up;     up.x     = 0.0; up.y     = 1.0; up.z     = 0.0;
    Matrix4 view;
    mat4_lookat(@eye, @target, @up, @view);
    glLoadMatrixf(@view.m[0]);

    // Model: apply euler rotations matching the original rot_x / rot_y / rot_z
    glRotatef(g.rot_x * 57.2958, 1.0, 0.0, 0.0);
    glRotatef(g.rot_y * 57.2958, 0.0, 1.0, 0.0);
    glRotatef(g.rot_z * 57.2958, 0.0, 0.0, 1.0);

    return;
};

// ============================================================================
// GL draw_frame - box + grid + axes (replaces the original draw_frame)
// ============================================================================

def gl_draw_box(Graph3D* g, DWORD col) -> void
{
    float r = dword_to_r(col);
    float gv = dword_to_g(col);
    float b = dword_to_b(col);
    glColor3f(r, gv, b);

    float x0 = gnorm(g.x_min, g.x_min, g.x_max, g.scale);
    float x1 = gnorm(g.x_max, g.x_min, g.x_max, g.scale);
    float y0 = gnorm(g.y_min, g.y_min, g.y_max, g.scale);
    float y1 = gnorm(g.y_max, g.y_min, g.y_max, g.scale);
    float z0 = gnorm(g.z_min, g.z_min, g.z_max, g.scale);
    float z1 = gnorm(g.z_max, g.z_min, g.z_max, g.scale);

    glBegin(GL_LINES);
        // Bottom face
        glVertex3f(x0, y0, z0); glVertex3f(x1, y0, z0);
        glVertex3f(x1, y0, z0); glVertex3f(x1, y0, z1);
        glVertex3f(x1, y0, z1); glVertex3f(x0, y0, z1);
        glVertex3f(x0, y0, z1); glVertex3f(x0, y0, z0);
        // Top face
        glVertex3f(x0, y1, z0); glVertex3f(x1, y1, z0);
        glVertex3f(x1, y1, z0); glVertex3f(x1, y1, z1);
        glVertex3f(x1, y1, z1); glVertex3f(x0, y1, z1);
        glVertex3f(x0, y1, z1); glVertex3f(x0, y1, z0);
        // Vertical edges
        glVertex3f(x0, y0, z0); glVertex3f(x0, y1, z0);
        glVertex3f(x1, y0, z0); glVertex3f(x1, y1, z0);
        glVertex3f(x1, y0, z1); glVertex3f(x1, y1, z1);
        glVertex3f(x0, y0, z1); glVertex3f(x0, y1, z1);
    glEnd();
    return;
};

def gl_draw_grid(Graph3D* g, int x_divs, int z_divs, DWORD col) -> void
{
    float r = dword_to_r(col);
    float gv = dword_to_g(col);
    float b = dword_to_b(col);
    glColor3f(r, gv, b);

    float y0 = gnorm(g.y_min, g.y_min, g.y_max, g.scale);
    float nz0 = gnorm(g.z_min, g.z_min, g.z_max, g.scale);
    float nz1 = gnorm(g.z_max, g.z_min, g.z_max, g.scale);
    float nx0 = gnorm(g.x_min, g.x_min, g.x_max, g.scale);
    float nx1 = gnorm(g.x_max, g.x_min, g.x_max, g.scale);

    glBegin(GL_LINES);

    int i = 0;
    while (i <= x_divs)
    {
        float fx = g.x_min + (g.x_max - g.x_min) * (float)i / (float)x_divs;
        float nx = gnorm(fx, g.x_min, g.x_max, g.scale);
        glVertex3f(nx, y0, nz0);
        glVertex3f(nx, y0, nz1);
        i = i + 1;
    };

    int j = 0;
    while (j <= z_divs)
    {
        float fz = g.z_min + (g.z_max - g.z_min) * (float)j / (float)z_divs;
        float nz = gnorm(fz, g.z_min, g.z_max, g.scale);
        glVertex3f(nx0, y0, nz);
        glVertex3f(nx1, y0, nz);
        j = j + 1;
    };

    glEnd();
    return;
};

def gl_draw_axes(Graph3D* g, DWORD col) -> void
{
    float r = dword_to_r(col),
          gv = dword_to_g(col),
          b = dword_to_b(col),
          x0, x1, y0, y1, z0, z1;

    glColor3f(r, gv, b);

    x0 = gnorm(g.x_min, g.x_min, g.x_max, g.scale);
    x1 = gnorm(g.x_max, g.x_min, g.x_max, g.scale);
    y0 = gnorm(g.y_min, g.y_min, g.y_max, g.scale);
    y1 = gnorm(g.y_max, g.y_min, g.y_max, g.scale);
    z0 = gnorm(g.z_min, g.z_min, g.z_max, g.scale);
    z1 = gnorm(g.z_max, g.z_min, g.z_max, g.scale);

    glBegin(GL_LINES);
        glVertex3f(x0, y0, z0); glVertex3f(x1, y0, z0);  // X
        glVertex3f(x0, y0, z0); glVertex3f(x0, y1, z0);  // Y
        glVertex3f(x0, y0, z0); glVertex3f(x0, y0, z1);  // Z
    glEnd();
    return;
};

def gl_draw_frame(Graph3D* g, DWORD col_box, DWORD col_grid, DWORD col_axis) -> void
{
    gl_draw_box(@g, col_box);
    gl_draw_grid(@g, 3, 3, col_grid);
    gl_draw_axes(@g, col_axis);
    return;
};

// ============================================================================
// GL plot functions
// ============================================================================

def gl_plot_line(Graph3D* g, float* xs, float* ys, float* zs, int count, DWORD col) -> void
{
    float r = dword_to_r(col);
    float gv = dword_to_g(col);
    float b = dword_to_b(col);
    glColor3f(r, gv, b);

    glBegin(GL_LINE_STRIP);
    int i = 0;
    while (i < count)
    {
        float nx = gnorm(xs[i], g.x_min, g.x_max, g.scale);
        float ny = gnorm(ys[i], g.y_min, g.y_max, g.scale);
        float nz = gnorm(zs[i], g.z_min, g.z_max, g.scale);
        glVertex3f(nx, ny, nz);
        i = i + 1;
    };
    glEnd();
    return;
};

def gl_plot_scatter(Graph3D* g, float* xs, float* ys, float* zs, int count, DWORD col, float pt_size) -> void
{
    float r = dword_to_r(col);
    float gv = dword_to_g(col);
    float b = dword_to_b(col);
    glColor3f(r, gv, b);
    glPointSize(pt_size);

    glBegin(GL_POINTS);
    int i = 0;
    while (i < count)
    {
        float nx = gnorm(xs[i], g.x_min, g.x_max, g.scale);
        float ny = gnorm(ys[i], g.y_min, g.y_max, g.scale);
        float nz = gnorm(zs[i], g.z_min, g.z_max, g.scale);
        glVertex3f(nx, ny, nz);
        i = i + 1;
    };
    glEnd();
    glPointSize(1.0);
    return;
};

def gl_plot_surface(Graph3D* g, float* xs, float* ys, float* zs, int x_count, int y_count, DWORD col) -> void
{
    float r = dword_to_r(col);
    float gv = dword_to_g(col);
    float b = dword_to_b(col);
    glColor3f(r, gv, b);

    glBegin(GL_LINES);
    int row = 0;
    while (row < y_count)
    {
        int col_i = 0;
        while (col_i < x_count)
        {
            float z00 = zs[row * x_count + col_i];

            if (col_i < x_count - 1)
            {
                float z01 = zs[row * x_count + col_i + 1];
                glVertex3f(gnorm(xs[col_i],      g.x_min, g.x_max, g.scale),
                           gnorm(ys[row],         g.y_min, g.y_max, g.scale),
                           gnorm(z00,             g.z_min, g.z_max, g.scale));
                glVertex3f(gnorm(xs[col_i + 1],  g.x_min, g.x_max, g.scale),
                           gnorm(ys[row],         g.y_min, g.y_max, g.scale),
                           gnorm(z01,             g.z_min, g.z_max, g.scale));
            };

            if (row < y_count - 1)
            {
                float z10 = zs[(row + 1) * x_count + col_i];
                glVertex3f(gnorm(xs[col_i],  g.x_min, g.x_max, g.scale),
                           gnorm(ys[row],     g.y_min, g.y_max, g.scale),
                           gnorm(z00,         g.z_min, g.z_max, g.scale));
                glVertex3f(gnorm(xs[col_i],  g.x_min, g.x_max, g.scale),
                           gnorm(ys[row + 1], g.y_min, g.y_max, g.scale),
                           gnorm(z10,         g.z_min, g.z_max, g.scale));
            };

            col_i = col_i + 1;
        };
        row = row + 1;
    };
    glEnd();
    return;
};

def gl_plot_bars(Graph3D* g, float* xs, float* ys, float* zs, int count, DWORD col, float bar_px) -> void
{
    float r = dword_to_r(col);
    float gv = dword_to_g(col);
    float b = dword_to_b(col);
    glColor3f(r, gv, b);

    float y_base = gnorm(g.y_min, g.y_min, g.y_max, g.scale);
    float cap = bar_px * 0.015;

    glBegin(GL_LINES);
    int i = 0;
    while (i < count)
    {
        float nx = gnorm(xs[i], g.x_min, g.x_max, g.scale);
        float ny = gnorm(ys[i], g.y_min, g.y_max, g.scale);
        float nz = gnorm(zs[i], g.z_min, g.z_max, g.scale);

        // Vertical stem
        glVertex3f(nx, y_base, nz);
        glVertex3f(nx, ny, nz);

        // Cross cap at top
        glVertex3f(nx - cap, ny, nz);
        glVertex3f(nx + cap, ny, nz);
        glVertex3f(nx, ny, nz - cap);
        glVertex3f(nx, ny, nz + cap);

        i = i + 1;
    };
    glEnd();
    return;
};

// ============================================================================
// Panel setup (identical logic to original, retained as-is)
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

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("redgraphing.fx - 16 Panel 3D Demo\0", WIN_SIZE, WIN_SIZE, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    GLContext gl(win.device_context);
    gl.load_extensions();

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_SCISSOR_TEST);
    glDepthFunc(GL_LESS);

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

        // Clear the full window once
        glDisable(GL_SCISSOR_TEST);
        glViewport(0, 0, WIN_SIZE, WIN_SIZE);
        gl.set_clear_color(dword_to_r(col_bg), dword_to_g(col_bg), dword_to_b(col_bg), 1.0);
        gl.clear();
        glEnable(GL_SCISSOR_TEST);

        // ---- 0: Sine ripple surface ----
        gen_ripple(sx, sy, sz, SURF_N, phase);
        setup_panel_gl(@g[0], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[0], col_box, col_grid, col_axis);
        gl_plot_surface(@g[0], sx, sy, sz, SURF_N, SURF_N, colors[0]);

        // ---- 1: Saddle surface (static geometry) ----
        gen_saddle(sx, sy, sz, SURF_N);
        setup_panel_gl(@g[1], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[1], col_box, col_grid, col_axis);
        gl_plot_surface(@g[1], sx, sy, sz, SURF_N, SURF_N, colors[1]);

        // ---- 2: Peaks surface ----
        gen_peaks(sx, sy, sz, SURF_N, phase);
        auto_range_z(@g[2], sz, surf_cells, 0.05);
        setup_panel_gl(@g[2], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[2], col_box, col_grid, col_axis);
        gl_plot_surface(@g[2], sx, sy, sz, SURF_N, SURF_N, colors[2]);

        // ---- 3: Torus surface rows ----
        gen_torus_surf(sx, sy, sz, SURF_N, phase);
        setup_panel_gl(@g[3], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[3], col_box, col_grid, col_axis);
        gl_plot_surface(@g[3], sx, sy, sz, SURF_N, SURF_N, colors[3]);

        // ---- 4: Helix - line only ----
        gen_helix(ax, ay, az, CURVE_N, phase);
        setup_panel_gl(@g[4], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[4], col_box, col_grid, col_axis);
        gl_plot_line(@g[4], ax, ay, az, CURVE_N, colors[4]);

        // ---- 5: Torus knot (2,3) - line + scatter ----
        gen_knot_23(ax, ay, az, CURVE_N, phase);
        auto_range3d(@g[5], ax, ay, az, CURVE_N, 0.05);
        setup_panel_gl(@g[5], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[5], col_box, col_grid, col_axis);
        gl_plot_line(@g[5], ax, ay, az, CURVE_N, colors[5]);
        gl_plot_scatter(@g[5], ax, ay, az, CURVE_N / 5, colors[5], 4.0);

        // ---- 6: Figure-8 knot - line + scatter ----
        gen_fig8(ax, ay, az, CURVE_N, phase);
        auto_range3d(@g[6], ax, ay, az, CURVE_N, 0.05);
        setup_panel_gl(@g[6], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[6], col_box, col_grid, col_axis);
        gl_plot_line(@g[6], ax, ay, az, CURVE_N, colors[6]);
        gl_plot_scatter(@g[6], ax, ay, az, CURVE_N / 4, colors[6], 6.0);

        // ---- 7: Lissajous - line + scatter ----
        gen_lissajous(ax, ay, az, CURVE_N, phase);
        setup_panel_gl(@g[7], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[7], col_box, col_grid, col_axis);
        gl_plot_line(@g[7], ax, ay, az, CURVE_N, colors[7]);
        gl_plot_scatter(@g[7], ax, ay, az, CURVE_N / 3, colors[7], 4.0);

        // ---- 8: Sphere scatter ----
        gen_sphere(ax, ay, az, CURVE_N, phase);
        setup_panel_gl(@g[8], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[8], col_box, col_grid, col_axis);
        gl_plot_scatter(@g[8], ax, ay, az, CURVE_N, colors[8], 6.0);

        // ---- 9: Cone scatter ----
        gen_cone(ax, ay, az, CURVE_N, phase);
        setup_panel_gl(@g[9], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[9], col_box, col_grid, col_axis);
        gl_plot_scatter(@g[9], ax, ay, az, CURVE_N, colors[9], 4.0);

        // ---- 10: Double helix - line ----
        gen_double_helix(ax, ay, az, CURVE_N, phase);
        setup_panel_gl(@g[10], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[10], col_box, col_grid, col_axis);
        gl_plot_line(@g[10], ax, ay, az, CURVE_N, colors[10]);

        // ---- 11: Spiral coil - line + scatter ----
        gen_spiral_coil(ax, ay, az, CURVE_N, phase);
        setup_panel_gl(@g[11], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[11], col_box, col_grid, col_axis);
        gl_plot_line(@g[11], ax, ay, az, CURVE_N, colors[11]);
        gl_plot_scatter(@g[11], ax, ay, az, CURVE_N / 4, colors[11], 4.0);

        // ---- 12: 3D bars ----
        gen_bars(bx, by, bz, bar_cells, BAR_N, phase);
        setup_panel_gl(@g[12], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[12], col_box, col_grid, col_axis);
        gl_plot_bars(@g[12], bx, by, bz, bar_cells, colors[12], 4.0);

        // ---- 13: Viviani curve - line + scatter ----
        gen_viviani(ax, ay, az, CURVE_N, phase);
        setup_panel_gl(@g[13], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[13], col_box, col_grid, col_axis);
        gl_plot_line(@g[13], ax, ay, az, CURVE_N, colors[13]);
        gl_plot_scatter(@g[13], ax, ay, az, CURVE_N / 5, colors[13], 6.0);

        // ---- 14: Cluster scatter ----
        gen_cluster(ax, ay, az, CURVE_N, phase);
        setup_panel_gl(@g[14], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[14], col_box, col_grid, col_axis);
        gl_plot_scatter(@g[14], ax, ay, az, CURVE_N, colors[14], 4.0);

        // ---- 15: Wave interference surface ----
        gen_interference(sx, sy, sz, SURF_N, phase);
        setup_panel_gl(@g[15], WIN_SIZE, WIN_SIZE);
        gl_draw_frame(@g[15], col_box, col_grid, col_axis);
        gl_plot_surface(@g[15], sx, sy, sz, SURF_N, SURF_N, colors[15]);

        phase = phase + 0.025;
        if (phase > 2.0 * PIF) { phase = phase - 2.0 * PIF; };

        gl.present();
        Sleep(16);
    };

    gl.__exit();
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
