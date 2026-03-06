#import "standard.fx", "redmath.fx", "redwindows.fx", "direct2d.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// CONSTANTS
// ============================================================================

const int WIN_W   = 1010,
          WIN_H   = 1010,
          MARGIN  = 50,
          PANEL_W = 425,
          PANEL_H = 425;

const int SAMPLE_COUNT = 64;

// ============================================================================
// Panel layout struct
// ============================================================================

struct Panel
{
    float px, py;        // top-left pixel corner
    float pw, ph;        // pixel width / height
    float x_min, x_max;
    float y_min, y_max;
};

// ============================================================================
// Data-space -> pixel-space mapping
// ============================================================================

def data_to_px_x(Panel* p, float x) -> float
{
    return p.px + (x - p.x_min) / (p.x_max - p.x_min) * p.pw;
};

def data_to_px_y(Panel* p, float y) -> float
{
    // Y is inverted: data y_max maps to top pixel
    return p.py + (1.0 - (y - p.y_min) / (p.y_max - p.y_min)) * p.ph;
};

// ============================================================================
// Panel setup helper
// ============================================================================

def setup_panel(Panel* p, int col, int row,
                float xlo, float xhi, float ylo, float yhi) -> void
{
    p.px     = (float)(MARGIN + col * (PANEL_W + MARGIN));
    p.py     = (float)(MARGIN + row * (PANEL_H + MARGIN));
    p.pw     = (float)PANEL_W;
    p.ph     = (float)PANEL_H;
    p.x_min  = xlo;
    p.x_max  = xhi;
    p.y_min  = ylo;
    p.y_max  = yhi;
    return;
};

// ============================================================================
// Draw helpers built on D2DContext
// ============================================================================

// Draw the grid lines inside the panel clip region
def draw_panel_grid(D2DContext* ctx, Panel* p, int nx, int ny,
                    ID2D1SolidColorBrush br) -> void
{
    ctx.push_clip(p.px, p.py, p.px + p.pw, p.py + p.ph);

    int i = 0;
    while (i <= nx)
    {
        float x = p.px + (float)i / (float)nx * p.pw;
        ctx.draw_line(x, p.py, x, p.py + p.ph, br, 1.0);
        i = i + 1;
    };

    i = 0;
    while (i <= ny)
    {
        float y = p.py + (float)i / (float)ny * p.ph;
        ctx.draw_line(p.px, y, p.px + p.pw, y, br, 1.0);
        i = i + 1;
    };

    ctx.pop_clip();
    return;
};

// Draw x=0 and y=0 axes if they fall inside the panel
def draw_panel_axes(D2DContext* ctx, Panel* p, ID2D1SolidColorBrush br) -> void
{
    ctx.push_clip(p.px, p.py, p.px + p.pw, p.py + p.ph);

    // Y axis (x = 0 in data space)
    if (p.x_min <= 0.0 & 0.0 <= p.x_max)
    {
        float ax = data_to_px_x(p, 0.0);
        ctx.draw_line(ax, p.py, ax, p.py + p.ph, br, 1.5);
    };

    // X axis (y = 0 in data space)
    if (p.y_min <= 0.0 & 0.0 <= p.y_max)
    {
        float ay = data_to_px_y(p, 0.0);
        ctx.draw_line(p.px, ay, p.px + p.pw, ay, br, 1.5);
    };

    ctx.pop_clip();
    return;
};

// Draw a 1-px border rectangle around the panel
def draw_panel_border(D2DContext* ctx, Panel* p, ID2D1SolidColorBrush br) -> void
{
    ctx.draw_rect(p.px, p.py, p.px + p.pw, p.py + p.ph, br, 1.0);
    return;
};

// Draw small tick marks along the axes inside the panel
def draw_panel_ticks(D2DContext* ctx, Panel* p, int nx, int ny,
                     float tick_len, ID2D1SolidColorBrush br) -> void
{
    float half = tick_len * 0.5;

    // X axis ticks
    if (p.y_min <= 0.0 & 0.0 <= p.y_max)
    {
        float ay = data_to_px_y(p, 0.0);
        int i = 0;
        while (i <= nx)
        {
            float x = p.px + (float)i / (float)nx * p.pw;
            ctx.draw_line(x, ay - half, x, ay + half, br, 1.0);
            i = i + 1;
        };
    };

    // Y axis ticks
    if (p.x_min <= 0.0 & 0.0 <= p.x_max)
    {
        float ax = data_to_px_x(p, 0.0);
        int i = 0;
        while (i <= ny)
        {
            float y = p.py + (float)i / (float)ny * p.ph;
            ctx.draw_line(ax - half, y, ax + half, y, br, 1.0);
            i = i + 1;
        };
    };
    return;
};

// Draw a connected polyline through (xs,ys) data points
def plot_line(D2DContext* ctx, Panel* p,
              float* xs, float* ys, int count,
              ID2D1SolidColorBrush br, float sw) -> void
{
    ctx.push_clip(p.px, p.py, p.px + p.pw, p.py + p.ph);

    int i = 1;
    while (i < count)
    {
        float x0 = data_to_px_x(p, xs[i - 1]);
        float y0 = data_to_px_y(p, ys[i - 1]);
        float x1 = data_to_px_x(p, xs[i]);
        float y1 = data_to_px_y(p, ys[i]);
        ctx.draw_line(x0, y0, x1, y1, br, sw);
        i = i + 1;
    };

    ctx.pop_clip();
    return;
};

// Fill the area under a polyline down to y=0 using thin vertical slabs
def plot_area(D2DContext* ctx, Panel* p,
              float* xs, float* ys, int count,
              ID2D1SolidColorBrush br) -> void
{
    ctx.push_clip(p.px, p.py, p.px + p.pw, p.py + p.ph);

    float zero_y = data_to_px_y(p, 0.0);

    int i = 0;
    while (i < count - 1)
    {
        float x0 = data_to_px_x(p, xs[i]);
        float x1 = data_to_px_x(p, xs[i + 1]);
        float y0 = data_to_px_y(p, ys[i]);
        float y1 = data_to_px_y(p, ys[i + 1]);

        // Average the two sample heights as a simple trapezoidal slab
        float top    = y0 < y1 ? y0 : y1;
        float bottom = zero_y;
        if (y0 > zero_y & y1 > zero_y)
        {
            top    = zero_y;
            bottom = y0 > y1 ? y0 : y1;
        };

        if (x1 > x0)
        {
            ctx.fill_rect(x0, top, x1, bottom, br);
        };
        i = i + 1;
    };

    ctx.pop_clip();
    return;
};

// Draw filled circles at each data point (scatter plot)
def plot_scatter(D2DContext* ctx, Panel* p,
                 float* xs, float* ys, int count,
                 ID2D1SolidColorBrush br, float radius) -> void
{
    ctx.push_clip(p.px, p.py, p.px + p.pw, p.py + p.ph);

    int i = 0;
    while (i < count)
    {
        float cx = data_to_px_x(p, xs[i]);
        float cy = data_to_px_y(p, ys[i]);
        ctx.fill_circle(cx, cy, radius, br);
        i = i + 1;
    };

    ctx.pop_clip();
    return;
};

// Draw bar chart: one filled rectangle per sample, bar width in pixels
def plot_bars(D2DContext* ctx, Panel* p,
              float* xs, float* ys, int count,
              ID2D1SolidColorBrush br, float bar_w_px) -> void
{
    ctx.push_clip(p.px, p.py, p.px + p.pw, p.py + p.ph);

    float zero_y = data_to_px_y(p, 0.0);
    float half   = bar_w_px * 0.5;

    int i = 0;
    while (i < count)
    {
        float cx  = data_to_px_x(p, xs[i]);
        float top = data_to_px_y(p, ys[i]);
        ctx.fill_rect(cx - half, top, cx + half, zero_y, br);
        i = i + 1;
    };

    ctx.pop_clip();
    return;
};

// Draw a step / square-wave polyline
def plot_step(D2DContext* ctx, Panel* p,
              float* xs, float* ys, int count,
              ID2D1SolidColorBrush br, float sw) -> void
{
    ctx.push_clip(p.px, p.py, p.px + p.pw, p.py + p.ph);

    int i = 1;
    while (i < count)
    {
        float x0 = data_to_px_x(p, xs[i - 1]);
        float y0 = data_to_px_y(p, ys[i - 1]);
        float x1 = data_to_px_x(p, xs[i]);
        float y1 = data_to_px_y(p, ys[i]);
        ctx.draw_line(x0, y0, x1, y1, br, sw);
        i = i + 1;
    };

    ctx.pop_clip();
    return;
};

// Draw a crosshair at a data-space point
def draw_crosshair(D2DContext* ctx, Panel* p,
                   float dx, float dy, ID2D1SolidColorBrush br) -> void
{
    ctx.push_clip(p.px, p.py, p.px + p.pw, p.py + p.ph);
    float cx = data_to_px_x(p, dx);
    float cy = data_to_px_y(p, dy);
    ctx.draw_line(cx, p.py, cx, p.py + p.ph, br, 1.0);
    ctx.draw_line(p.px, cy, p.px + p.pw, cy, br, 1.0);
    ctx.pop_clip();
    return;
};

// Draw a centred title above the panel
def draw_title(D2DContext* ctx, Panel* p,
               LPCSTR text, DWORD text_len,
               IDWriteTextFormat fmt, ID2D1SolidColorBrush br) -> void
{
    float left   = p.px;
    float top    = p.py - 28.0;
    float right  = p.px + p.pw;
    float bottom = p.py - 4.0;
    ctx.draw_text(text, text_len, fmt, left, top, right, bottom, br);
    return;
};

// Draw an x-axis label centred below the panel
def draw_x_label(D2DContext* ctx, Panel* p,
                 LPCSTR text, DWORD text_len,
                 IDWriteTextFormat fmt, ID2D1SolidColorBrush br) -> void
{
    float left   = p.px;
    float top    = p.py + p.ph + 6.0;
    float right  = p.px + p.pw;
    float bottom = top + 20.0;
    ctx.draw_text(text, text_len, fmt, left, top, right, bottom, br);
    return;
};

// Draw a y-axis label to the left of the panel (rotated via transform)
def draw_y_label(D2DContext* ctx, Panel* p,
                 LPCSTR text, DWORD text_len,
                 IDWriteTextFormat fmt, ID2D1SolidColorBrush br) -> void
{
    // Rotate -90 degrees about the label centre
    float cx = p.px - 32.0;
    float cy = p.py + p.ph * 0.5;

    D2D1_MATRIX_3X2_F rot;
    d2d_matrix_rotate((0.0 - PIF * 0.5), @rot);
    // Adjust translation so we rotate about (cx, cy)
    rot._31 = cx - cx * rot._11 - cy * rot._21;
    rot._32 = cy - cx * rot._12 - cy * rot._22;

    ctx.set_transform(@rot);
    // After rotation the text rect is described in the rotated frame
    float hw = p.ph * 0.5;
    ctx.draw_text(text, text_len, fmt,
                  cx - hw, cy - 10.0,
                  cx + hw, cy + 10.0,
                  br);
    ctx.reset_transform();
    return;
};

// ============================================================================
// Data fill functions (identical logic to graph_demo.fx)
// ============================================================================

def fill_sine(float* xs, float* ys, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t = (float)i / (float)(count - 1);
        xs[i]   = t * 4.0 * PIF;
        ys[i]   = sin(xs[i] + phase);
        i = i + 1;
    };
    return;
};

def fill_circle(float* xs, float* ys, int count, float phase) -> void
{
    int i = 0;
    while (i < count)
    {
        float t = (float)i / (float)(count - 1) * 2.0 * PIF;
        xs[i]   = cos(t + phase);
        ys[i]   = sin(t + phase);
        i = i + 1;
    };
    return;
};

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
    return;
};

def fill_square(float* xs, float* ys, int count, float phase) -> void
{
    float domain = 4.0 * PIF;
    float period = 2.0 * PIF;
    float half   = period * 0.5;

    float t_off = half - phase;
    while (t_off <  0.0)  { t_off = t_off + half; };
    while (t_off >= half) { t_off = t_off - half; };

    float tr0 = t_off;
    float tr1 = t_off + half;
    float tr2 = t_off + half * 2.0;
    float tr3 = t_off + half * 3.0;

    float s0 = sin(0.0 - phase);
    float y_start;
    if (s0 >= 0.0) { y_start =  1.0; }
    else           { y_start = -1.0; };

    int   out = 0;
    float cur = y_start;
    float nxt;

    // Segment 0
    xs[out] = 0.0;    ys[out] = cur;   out = out + 1;
    xs[out] = tr0;    ys[out] = cur;   out = out + 1;
    if (cur ==  1.0) { nxt = -1.0; } else { nxt = 1.0; };
    xs[out] = tr0;    ys[out] = nxt;   out = out + 1;
    cur = nxt;

    // Segment 1
    xs[out] = tr1;    ys[out] = cur;   out = out + 1;
    if (cur ==  1.0) { nxt = -1.0; } else { nxt = 1.0; };
    xs[out] = tr1;    ys[out] = nxt;   out = out + 1;
    cur = nxt;

    // Segment 2
    xs[out] = tr2;    ys[out] = cur;   out = out + 1;
    if (cur ==  1.0) { nxt = -1.0; } else { nxt = 1.0; };
    xs[out] = tr2;    ys[out] = nxt;   out = out + 1;
    cur = nxt;

    // Segment 3
    xs[out] = tr3;    ys[out] = cur;   out = out + 1;
    if (cur ==  1.0) { nxt = -1.0; } else { nxt = 1.0; };
    xs[out] = tr3;    ys[out] = nxt;   out = out + 1;
    cur = nxt;

    // Segment 4
    xs[out] = domain; ys[out] = cur;   out = out + 1;

    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("direct2d.fx Graph Demo\0", WIN_W, WIN_H, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    D2DContext ctx(win.handle, WIN_W, WIN_H);

    // ---- Text formats ----
    IDWriteTextFormat fmt_title  = ctx.create_text_format("Segoe UI\0", 14.0);
    IDWriteTextFormat fmt_label  = ctx.create_text_format("Segoe UI\0", 11.0);

    // Centre-align titles / labels
    ctx.set_text_alignment(fmt_title, DWRITE_TEXT_ALIGNMENT_CENTER);
    ctx.set_paragraph_alignment(fmt_title, DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
    ctx.set_text_alignment(fmt_label, DWRITE_TEXT_ALIGNMENT_CENTER);
    ctx.set_paragraph_alignment(fmt_label, DWRITE_PARAGRAPH_ALIGNMENT_CENTER);

    // ---- Allocate data arrays ----
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

    // ---- Panel definitions ----
    Panel g1, g2, g3, g4;

    setup_panel(@g1, 0, 0,  0.0, 4.0 * PIF, -1.3,   1.3);   // sine wave
    setup_panel(@g2, 1, 0, -1.3,       1.3, -1.3,   1.3);   // unit circle scatter
    setup_panel(@g3, 0, 1,  0.0,      13.0,  0.0, 110.0);   // bar chart
    setup_panel(@g4, 1, 1,  0.0, 4.0 * PIF, -1.5,   1.5);   // square wave

    // ---- Colours (0-1 float) ----
    // Background
    float bg_r = 18.0 / 255.0,  bg_g = 18.0 / 255.0,  bg_b = 24.0 / 255.0;
    // Grid / axes / border / text
    float gr_r = 45.0 / 255.0,  gr_g = 45.0 / 255.0,  gr_b = 60.0 / 255.0;
    float ax_r = 120.0 / 255.0, ax_g = 120.0 / 255.0, ax_b = 140.0 / 255.0;
    float bd_r = 80.0 / 255.0,  bd_g = 80.0 / 255.0,  bd_b = 100.0 / 255.0;
    float tx_r = 200.0 / 255.0, tx_g = 200.0 / 255.0, tx_b = 220.0 / 255.0;
    // Chart colours
    float sn_r = 80.0 / 255.0,  sn_g = 200.0 / 255.0, sn_b = 255.0 / 255.0;  // cyan  - sine line
    float ar_r = 40.0 / 255.0,  ar_g = 100.0 / 255.0, ar_b = 128.0 / 255.0;  // dark cyan - area
    float sc_r = 255.0 / 255.0, sc_g = 160.0 / 255.0, sc_b = 40.0 / 255.0;   // orange - scatter
    float ba_r = 100.0 / 255.0, ba_g = 220.0 / 255.0, ba_b = 130.0 / 255.0;  // green - bars
    float sq_r = 220.0 / 255.0, sq_g = 80.0 / 255.0,  sq_b = 160.0 / 255.0;  // pink - step

    // ---- Create brushes ----
    ID2D1SolidColorBrush br_grid    = ctx.create_brush(gr_r, gr_g, gr_b, 1.0);
    ID2D1SolidColorBrush br_axis    = ctx.create_brush(ax_r, ax_g, ax_b, 1.0);
    ID2D1SolidColorBrush br_border  = ctx.create_brush(bd_r, bd_g, bd_b, 1.0);
    ID2D1SolidColorBrush br_text    = ctx.create_brush(tx_r, tx_g, tx_b, 1.0);
    ID2D1SolidColorBrush br_sine    = ctx.create_brush(sn_r, sn_g, sn_b, 1.0);
    ID2D1SolidColorBrush br_area    = ctx.create_brush(ar_r, ar_g, ar_b, 0.6);
    ID2D1SolidColorBrush br_scatter = ctx.create_brush(sc_r, sc_g, sc_b, 1.0);
    ID2D1SolidColorBrush br_bars    = ctx.create_brush(ba_r, ba_g, ba_b, 1.0);
    ID2D1SolidColorBrush br_step    = ctx.create_brush(sq_r, sq_g, sq_b, 1.0);

    float phase = 0.0;

    while (win.process_messages())
    {
        // Update animated data
        fill_sine(xs1, ys1, SAMPLE_COUNT, phase);
        fill_circle(xs2, ys2, SAMPLE_COUNT, phase * 0.4);
        fill_square(xs4, ys4, SQ_COUNT, phase);

        ctx.begin_draw();

        // Clear background
        ctx.clear(bg_r, bg_g, bg_b, 1.0);

        // ---- Panel 1: Sine wave (area fill + line) ----
        draw_panel_grid(@ctx,   @g1, 8, 6, br_grid);
        draw_panel_axes(@ctx,   @g1, br_axis);
        draw_panel_border(@ctx, @g1, br_border);
        plot_area(@ctx,         @g1, xs1, ys1, SAMPLE_COUNT, br_area);
        plot_line(@ctx,         @g1, xs1, ys1, SAMPLE_COUNT, br_sine, 2.0);
        draw_panel_ticks(@ctx,  @g1, 8, 6, 4.0, br_axis);
        draw_title(@ctx,        @g1, "Sine Wave\0",  9, fmt_title, br_text);
        draw_x_label(@ctx,      @g1, "Radians\0",    7, fmt_label, br_text);
        draw_y_label(@ctx,      @g1, "Amplitude\0",  9, fmt_label, br_text);

        // ---- Panel 2: Unit circle scatter ----
        draw_panel_grid(@ctx,   @g2, 6, 6, br_grid);
        draw_panel_axes(@ctx,   @g2, br_axis);
        draw_panel_border(@ctx, @g2, br_border);
        draw_crosshair(@ctx,    @g2, 0.0, 0.0, br_grid);
        plot_scatter(@ctx,      @g2, xs2, ys2, SAMPLE_COUNT, br_scatter, 4.0);
        draw_panel_ticks(@ctx,  @g2, 6, 6, 4.0, br_axis);
        draw_title(@ctx,        @g2, "Unit Circle\0", 11, fmt_title, br_text);
        draw_x_label(@ctx,      @g2, "cos(t)\0",      6, fmt_label, br_text);
        draw_y_label(@ctx,      @g2, "sin(t)\0",      6, fmt_label, br_text);

        // ---- Panel 3: Monthly bar chart ----
        draw_panel_grid(@ctx,   @g3, 12, 5, br_grid);
        draw_panel_axes(@ctx,   @g3, br_axis);
        draw_panel_border(@ctx, @g3, br_border);
        plot_bars(@ctx,         @g3, xs3, ys3, BAR_COUNT, br_bars, 26.0);
        draw_panel_ticks(@ctx,  @g3, 12, 5, 4.0, br_axis);
        draw_title(@ctx,        @g3, "Monthly Data\0", 12, fmt_title, br_text);
        draw_x_label(@ctx,      @g3, "Month\0",         5, fmt_label, br_text);
        draw_y_label(@ctx,      @g3, "Value\0",          5, fmt_label, br_text);

        // ---- Panel 4: Step / square wave ----
        draw_panel_grid(@ctx,   @g4, 8, 4, br_grid);
        draw_panel_axes(@ctx,   @g4, br_axis);
        draw_panel_border(@ctx, @g4, br_border);
        plot_step(@ctx,         @g4, xs4, ys4, SQ_COUNT, br_step, 2.0);
        draw_panel_ticks(@ctx,  @g4, 8, 4, 4.0, br_axis);
        draw_title(@ctx,        @g4, "Square Wave\0", 11, fmt_title, br_text);
        draw_x_label(@ctx,      @g4, "Radians\0",      7, fmt_label, br_text);
        draw_y_label(@ctx,      @g4, "Amplitude\0",    9, fmt_label, br_text);

        ctx.end_draw();

        phase = phase + 0.03;
        if (phase > 2.0 * PIF) { phase = phase - 2.0 * PIF; };

        Sleep(5);
    };

    // ---- Release brushes ----
    ctx.release_brush(br_grid);
    ctx.release_brush(br_axis);
    ctx.release_brush(br_border);
    ctx.release_brush(br_text);
    ctx.release_brush(br_sine);
    ctx.release_brush(br_area);
    ctx.release_brush(br_scatter);
    ctx.release_brush(br_bars);
    ctx.release_brush(br_step);

    // ---- Release text formats ----
    ctx.release_text_format(fmt_title);
    ctx.release_text_format(fmt_label);

    // ---- Release context and window ----
    ctx.__exit();
    win.__exit();

    // ---- Free data arrays ----
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
