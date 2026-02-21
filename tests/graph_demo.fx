#import "standard.fx", "redmath.fx", "redwindows.fx", "redgraphing.fx", "redallocators.fx";

using standard::system::windows;
using standard::math;
using standard::graphing;
using standard::memory::allocators::stdheap;

extern
{
    def !!
        Sleep(u32) -> void;
};

// ============================================================================
// CONSTANTS
// ============================================================================

const int WIN_W     = 1010,
          WIN_H     = 1010,
          MARGIN    = 50,   // Pixels of margin around each panel
          PANEL_W   = 425,
          PANEL_H   = 425;

const int SAMPLE_COUNT = 64;

// ============================================================================
// Helpers: fill float arrays with data for each panel
// ============================================================================

// Panel 1: animated sine wave  (line chart)
def fill_sine(float* xs, float* ys, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t   = (float)i / (float)(count - 1);
        xs[i]     = t * 4.0 * PIF;          // 0 .. 4π
        ys[i]     = sin(xs[i] + phase);
        i = i + 1;
    };
};

// Panel 2: sine vs cosine scatter (scatter chart)
def fill_circle(float* xs, float* ys, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t   = (float)i / (float)(count - 1) * 2.0 * PIF;
        xs[i]     = cos(t + phase);
        ys[i]     = sin(t + phase);
        i = i + 1;
    };
};

// Panel 3: monthly bar chart (static values, 12 bars)
def fill_bars(float* xs, float* ys, int count) -> void
{
    float[12] monthly_vals = [42.0, 58.0, 35.0, 71.0, 88.0, 64.0,
                              95.0, 82.0, 49.0, 67.0, 53.0, 76.0];
    int i = 0;
    while (i < count)
    {
        xs[i] = (float)(i + 1);
        ys[i] = monthly_vals[i];
        i = i + 1;
    };
};

// Panel 4: animated step / square wave
// Explicitly places transition pairs so the wave scrolls smoothly with phase.
// Over 0..4pi there are 4 transitions (every pi).  We place:
//   - a plateau point just before each transition
//   - a duplicate x with the new y value immediately after (vertical edge)
// Total points: 5 transitions * 2 sides + interior plateau points = count (must match allocation)
// This function always writes exactly 20 points; SAMPLE_COUNT for panel 4 must be >= 20.
def fill_square(float* xs, float* ys, int count, float phase) -> void
{
    float domain = 4.0 * PIF;
    float period = 2.0 * PIF;

    // The 4 transition x-positions (every half-period), phase-shifted, wrapped to [0, domain)
    // Edge positions in data space: phase defines where the rising edge of cycle 0 lands.
    // Standard square: high on [0,pi), low on [pi,2pi) per cycle.
    // With phase shift p, high on [-p, pi-p), i.e. transition at x = -phase mod pi.

    // Build 5 transition x values across [0, 4pi]: t0..t4
    // The first rising edge within [0, 4pi] is at: period/2 - phase (mod period/2), i.e. every pi
    float half  = period * 0.5;   // pi

    // First transition x: where the edge lands in [0, half)
    float t_off = half - phase;
    // Wrap t_off into [0, half)
    while (t_off <  0.0)    { t_off = t_off + half; };
    while (t_off >= half)   { t_off = t_off - half; };

    // 4 transitions across the domain
    float tr0 = t_off;
    float tr1 = t_off + half;
    float tr2 = t_off + half * 2.0;
    float tr3 = t_off + half * 3.0;

    // Starting y: what is the wave value at x=0?
    float s0 = sin(0.0 - phase);
    float y_start;

    if (s0 >= 0.0) { y_start =  1.0; }
    else           { y_start = -1.0; };

    // We write segments: [0..tr0], [tr0..tr1], [tr1..tr2], [tr2..tr3], [tr3..domain]
    // Each segment: start point, end point (2 pts), then transition pair (2 pts) = 10 transitions * 2 = 20 pts total
    // Segment layout: start_x at cur_y, end_x at cur_y, end_x at next_y  (next segment starts at end_x, next_y)
    // 5 segments * 3 = 15, minus shared endpoints = 5*2 + 4*1 = 14... 
    // Simpler: write each segment as (left_x, cur_y), (right_x, cur_y), then flip y; last segment gets final point.
    // 5 segments * 2 pts = 10 pts, plus 4 transition duplicates = 14 pts. Add 1 start = still 14.
    // Use: for each segment write (x_start, y) and (x_end, y); at each interior boundary also write (x_end, next_y).
    // That gives 5*2 + 4 = 14. Let's use 14 points and adjust SAMPLE_COUNT below via a separate alloc.
    // Actually: just write all needed points cleanly.

    int out   = 0;
    float cur = y_start;
    float nxt;

    // Segment 0: [0, tr0]
    xs[out] = 0.0;    ys[out] = cur;   out = out + 1;
    xs[out] = tr0;    ys[out] = cur;   out = out + 1;

    if (cur ==  1.0) { nxt = -1.0; } else { nxt = 1.0; };

    xs[out] = tr0;    ys[out] = nxt;   out = out + 1;
    cur = nxt;

    // Segment 1: [tr0, tr1]
    xs[out] = tr1;    ys[out] = cur;   out = out + 1;

    if (cur ==  1.0) { nxt = -1.0; } else { nxt = 1.0; };

    xs[out] = tr1;    ys[out] = nxt;   out = out + 1;
    cur = nxt;

    // Segment 2: [tr1, tr2]
    xs[out] = tr2;    ys[out] = cur;   out = out + 1;

    if (cur ==  1.0) { nxt = -1.0; } else { nxt = 1.0; };

    xs[out] = tr2;    ys[out] = nxt;   out = out + 1;
    cur = nxt;

    // Segment 3: [tr2, tr3]
    xs[out] = tr3;    ys[out] = cur;   out = out + 1;

    if (cur ==  1.0) { nxt = -1.0; } else { nxt = 1.0; };

    xs[out] = tr3;    ys[out] = nxt;   out = out + 1;
    cur = nxt;

    // Segment 4: [tr3, domain]
    xs[out] = domain; ys[out] = cur;   out = out + 1;

    return;
};

// ============================================================================
// Setup a Graph panel at a given screen tile position
// ============================================================================

def setup_panel(Graph* g, int col, int row, float xlo, float xhi, float ylo, float yhi) -> void
{
    g.x      = MARGIN + col * (PANEL_W + MARGIN);
    g.y      = MARGIN + row * (PANEL_H + MARGIN);
    g.width  = PANEL_W;
    g.height = PANEL_H;
    g.x_min  = xlo;
    g.x_max  = xhi;
    g.y_min  = ylo;
    g.y_max  = yhi;
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("redgraphing.fx Demo\0", WIN_W, WIN_H, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    Canvas c(win.handle, win.device_context);

    // Allocate float arrays on the heap for each panel
    float* xs1 = (float*)fmalloc((u64)SAMPLE_COUNT * 4);
    float* ys1 = (float*)fmalloc((u64)SAMPLE_COUNT * 4);

    float* xs2 = (float*)fmalloc((u64)SAMPLE_COUNT * 4);
    float* ys2 = (float*)fmalloc((u64)SAMPLE_COUNT * 4);

    const int BAR_COUNT = 12;
    float* xs3 = (float*)fmalloc((u64)BAR_COUNT * 4);
    float* ys3 = (float*)fmalloc((u64)BAR_COUNT * 4);
    fill_bars(xs3, ys3, BAR_COUNT);

    const int SQ_COUNT = 10;
    float* xs4 = (float*)fmalloc((u64)SQ_COUNT * 4);
    float* ys4 = (float*)fmalloc((u64)SQ_COUNT * 4);

    // Pre-define graphs (layout fixed, ranges fixed for panels 3)
    Graph g1, g2, g3, g4;

    setup_panel(@g1, 0, 0,  0.0, 4.0 * PIF, -1.3,   1.3);   // sine wave
    setup_panel(@g2, 1, 0, -1.3,       1.3, -1.3,   1.3);   // circle scatter
    setup_panel(@g3, 0, 1,  0.0,      13.0,  0.0, 110.0);   // bar chart
    setup_panel(@g4, 1, 1,  0.0, 4.0 * PIF, -1.5,   1.5);   // step/square

    // Colors
    DWORD col_bg        = RGB( 18,  18,  24),
          col_grid      = RGB( 45,  45,  60),
          col_axis      = RGB(120, 120, 140),
          col_border    = RGB( 80,  80, 100),
          col_text      = RGB(200, 200, 220);

    DWORD col_sine      = RGB( 80, 200, 255);   // cyan
    DWORD col_area      = RGB( 40, 100, 128);   // dark cyan fill
    DWORD col_scatter   = RGB(255, 160,  40);   // orange
    DWORD col_bars      = RGB(100, 220, 130);   // green
    DWORD col_step      = RGB(220,  80, 160);   // pink

    float phase = 0.0;

    noopstr*   strarr = ["Sine Wave\0",    // 0
                         "Radians\0",      // 1
                         "Amplitutde\0",   // 2
                         "Unit Circle\0",  // 3
                         "cos(t)\0",       // 4
                         "sin(t)\0",       // 5
                         "Monthly Data\0", // 6
                         "Month\0",        // 7
                         "Value\0",        // 8
                         "Square Wave\0"   // 9
                         ];

    while (win.process_messages())
    {
        // Update animated panels
        fill_sine(xs1, ys1, SAMPLE_COUNT, phase);
        fill_circle(xs2, ys2, SAMPLE_COUNT, phase * 0.4);
        fill_square(xs4, ys4, SQ_COUNT, phase);

        // Clear background
        c.clear(col_bg);

        // ---- Panel 1: Sine wave (area fill + line) ----
        draw_grid(@c,   @g1, 8, 6, col_grid);
        draw_axes(@c,   @g1, col_axis, 1);
        draw_border(@c, @g1, col_border, 1);
        plot_area(@c,   @g1, xs1, ys1, SAMPLE_COUNT, col_area);
        plot_line(@c,   @g1, xs1, ys1, SAMPLE_COUNT, col_sine, 2);
        draw_tick_marks(@c, @g1, 8, 6, 4, col_axis);
        draw_title(@c,  @g1, strarr[0], col_text);
        draw_x_label(@c, @g1, strarr[1], col_text);
        draw_y_label(@c, @g1, strarr[2], col_text);

        // ---- Panel 2: Circle scatter ----
        draw_grid(@c,   @g2, 6, 6, col_grid);
        draw_axes(@c,   @g2, col_axis, 1);
        draw_border(@c, @g2, col_border, 1);
        plot_scatter_circles(@c, @g2, xs2, ys2, SAMPLE_COUNT, col_scatter, 4);
        draw_crosshair(@c, @g2, 0.0, 0.0, col_grid);
        draw_tick_marks(@c, @g2, 6, 6, 4, col_axis);
        draw_title(@c,  @g2, strarr[3], col_text);
        draw_x_label(@c, @g2, strarr[4], col_text);
        draw_y_label(@c, @g2, strarr[5], col_text);

        // ---- Panel 3: Monthly bar chart ----
        draw_grid(@c,   @g3, 12, 5, col_grid);
        draw_axes(@c,   @g3, col_axis, 1);
        draw_border(@c, @g3, col_border, 1);
        plot_bars(@c,   @g3, xs3, ys3, BAR_COUNT, col_bars, 26);
        draw_tick_marks(@c, @g3, 12, 5, 4, col_axis);
        draw_title(@c,  @g3, strarr[6], col_text);
        draw_x_label(@c, @g3, strarr[7], col_text);
        draw_y_label(@c, @g3, strarr[8], col_text);

        // ---- Panel 4: Step / square wave ----
        draw_grid(@c,   @g4, 8, 4, col_grid);
        draw_axes(@c,   @g4, col_axis, 1);
        draw_border(@c, @g4, col_border, 1);
        plot_step(@c,   @g4, xs4, ys4, SQ_COUNT, col_step, 2);
        draw_tick_marks(@c, @g4, 8, 4, 4, col_axis);
        draw_title(@c,  @g4, strarr[9], col_text);
        draw_x_label(@c, @g4, strarr[1], col_text);
        draw_y_label(@c, @g4, strarr[2], col_text);

        phase = phase + 0.03;
        if (phase > 2.0 * PIF) { phase = phase - 2.0 * PIF; };

        Sleep(5);
    };

    c.__exit();
    win.__exit();

    ffree((u64)xs1);
    ffree((u64)ys1);
    ffree((u64)xs2);
    ffree((u64)ys2);
    ffree((u64)xs3);
    ffree((u64)ys3);
    ffree((u64)xs4);
    ffree((u64)ys4);

    return 0;
};
