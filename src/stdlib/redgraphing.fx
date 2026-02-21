// redgraphing.fx - Flux 2D Graphing Library
// Provides line graphs, bar charts, scatter plots, and axes/grid rendering
// Built on top of redwindows.fx (Canvas/GDI) and redmath.fx
//
// Usage example:
//
//   #import "standard.fx";
//   #import "redwindows.fx";
//   #import "redgraphing.fx";
//
//   using standard::system::windows;
//   using standard::graphing;
//
//   def main() -> int
//   {
//       Window win("My Graph\0", 800, 600, CW_USEDEFAULT, CW_USEDEFAULT);
//       Canvas c(win.handle, win.device_context);
//
//       float[5] xs = [1.0, 2.0, 3.0, 4.0, 5.0];
//       float[5] ys = [2.0, 4.0, 1.0, 5.0, 3.0];
//
//       Graph g;
//       g.x      = 60;
//       g.y      = 20;
//       g.width  = 700;
//       g.height = 540;
//       g.x_min  = 0.0;
//       g.x_max  = 6.0;
//       g.y_min  = 0.0;
//       g.y_max  = 6.0;
//
//       while (win.process_messages())
//       {
//           c.clear(RGB(20, 20, 20));
//           draw_axes(@c, @g);
//           draw_grid(@c, @g, 5, 5);
//           plot_line(@c, @g, @xs[0], @ys[0], 5, RGB(0, 200, 255), 2);
//           plot_scatter(@c, @g, @xs[0], @ys[0], 5, RGB(255, 100, 50), 4);
//       };
//
//       win.__exit();
//       return 0;
//   };

#ifndef FLUX_STANDARD_MATH
#import "redmath.fx";
#endif

#ifndef __WIN32_INTERFACE__
#import "redwindows.fx";
#endif

#ifndef FLUX_STANDARD_GRAPHING
#def FLUX_STANDARD_GRAPHING 1;

using standard::system::windows;
using standard::math;

namespace standard
{
    namespace graphing
    {
        // ============================================================================
        // Graph - layout and data-range descriptor
        // ============================================================================
        // All drawing functions take a Graph* to know where on the canvas to render
        // and how to map data coordinates to screen coordinates.

        struct Graph
        {
            // Screen-space position and size of the plot area (pixels)
            int   x;        // Left edge of plot area
            int   y;        // Top edge of plot area
            int   width;    // Width of plot area
            int   height;   // Height of plot area

            // Data-space ranges
            float x_min;
            float x_max;
            float y_min;
            float y_max;
        };

        // ============================================================================
        // Coordinate mapping helpers
        // ============================================================================

        // Map a data-space X value to a screen-space pixel X within the graph area.
        def data_to_screen_x(Graph* g, float data_x) -> int
        {
            float range = g.x_max - g.x_min;
            if (range == 0.0) { return g.x; };
            float t = (data_x - g.x_min) / range;
            return g.x + (int)(t * (float)g.width);
        };

        // Map a data-space Y value to a screen-space pixel Y within the graph area.
        // Screen Y is inverted: y_max maps to the top (g.y), y_min maps to the bottom.
        def data_to_screen_y(Graph* g, float data_y) -> int
        {
            float range = g.y_max - g.y_min;
            if (range == 0.0) { return g.y + g.height; };
            float t = (data_y - g.y_min) / range;
            return g.y + g.height - (int)(t * (float)g.height);
        };

        // ============================================================================
        // draw_axes
        // Draws the X and Y axes as solid lines through the plot area border.
        // axis_color : DWORD color for both axes
        // line_width : pen width in pixels
        // ============================================================================
        def draw_axes(Canvas* c, Graph* g, DWORD axis_color, int line_width) -> void
        {
            c.set_pen(axis_color, line_width);

            // Bottom border (X axis baseline)
            int left   = g.x;
            int right  = g.x + g.width;
            int top    = g.y;
            int bottom = g.y + g.height;

            c.line(left, bottom, right, bottom);  // X axis
            c.line(left, top,    left,  bottom);  // Y axis
        };

        // ============================================================================
        // draw_grid
        // Draws evenly-spaced vertical and horizontal grid lines inside the plot area.
        // x_divs : number of vertical divisions
        // y_divs : number of horizontal divisions
        // grid_color : DWORD color for grid lines
        // ============================================================================
        def draw_grid(Canvas* c, Graph* g, int x_divs, int y_divs, DWORD grid_color) -> void
        {
            c.set_pen(grid_color, 1);

            int left   = g.x;
            int right  = g.x + g.width;
            int top    = g.y;
            int bottom = g.y + g.height;

            // Vertical grid lines
            int i = 1;
            while (i < x_divs)
            {
                int px = left + (g.width * i) / x_divs;
                c.line(px, top, px, bottom);
                i = i + 1;
            };

            // Horizontal grid lines
            int j = 1;
            while (j < y_divs)
            {
                int py = top + (g.height * j) / y_divs;
                c.line(left, py, right, py);
                j = j + 1;
            };
        };

        // ============================================================================
        // draw_border
        // Draws a rectangular border around the entire plot area.
        // border_color : DWORD color
        // line_width   : pen width in pixels
        // ============================================================================
        def draw_border(Canvas* c, Graph* g, DWORD border_color, int line_width) -> void
        {
            c.set_pen(border_color, line_width);

            int left   = g.x;
            int right  = g.x + g.width;
            int top    = g.y;
            int bottom = g.y + g.height;

            c.line(left,  top,    right, top);
            c.line(right, top,    right, bottom);
            c.line(right, bottom, left,  bottom);
            c.line(left,  bottom, left,  top);
        };

        // ============================================================================
        // plot_line
        // Draws a connected polyline through (xs[i], ys[i]) data points.
        // xs, ys    : pointer to the first element of float arrays
        // count     : number of points
        // color     : DWORD line color
        // line_width: pen width in pixels
        // ============================================================================
        def plot_line(Canvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int line_width) -> void
        {
            if (count < 2) { return; };

            c.set_pen(color, line_width);

            int prev_px = data_to_screen_x(g, xs[0]);
            int prev_py = data_to_screen_y(g, ys[0]);

            int i = 1;
            while (i < count)
            {
                int px = data_to_screen_x(g, xs[i]);
                int py = data_to_screen_y(g, ys[i]);
                c.line(prev_px, prev_py, px, py);
                prev_px = px;
                prev_py = py;
                i = i + 1;
            };
        };

        // ============================================================================
        // plot_scatter
        // Draws a filled square marker at each (xs[i], ys[i]) data point.
        // xs, ys    : pointer to the first element of float arrays
        // count     : number of points
        // color     : DWORD marker color
        // radius    : half-size of marker in pixels
        // ============================================================================
        def plot_scatter(Canvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int radius) -> void
        {
            c.set_pen(color, 1);

            int i = 0;
            while (i < count)
            {
                int px = data_to_screen_x(g, xs[i]);
                int py = data_to_screen_y(g, ys[i]);
                c.rect(px - radius, py - radius, px + radius, py + radius);
                i = i + 1;
            };
        };

        // ============================================================================
        // plot_scatter_circles
        // Draws a circle marker at each (xs[i], ys[i]) data point.
        // xs, ys    : pointer to the first element of float arrays
        // count     : number of points
        // color     : DWORD marker color
        // radius    : circle radius in pixels
        // ============================================================================
        def plot_scatter_circles(Canvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int radius) -> void
        {
            c.set_pen(color, 1);

            int i = 0;
            while (i < count)
            {
                int px = data_to_screen_x(g, xs[i]);
                int py = data_to_screen_y(g, ys[i]);
                c.circle(px, py, radius);
                i = i + 1;
            };
        };

        // ============================================================================
        // plot_bars
        // Draws a vertical bar chart.  Each bar is centered at xs[i] and reaches
        // from y=0 (or y_min if y_min > 0) up to ys[i].
        // xs, ys     : pointer to the first element of float arrays
        // count      : number of bars
        // color      : DWORD fill/outline color
        // bar_width_px : width of each bar in screen pixels
        // ============================================================================
        def plot_bars(Canvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int bar_width_px) -> void
        {
            c.set_pen(color, 1);

            // Baseline: screen Y for data Y = 0 (clamped inside the plot area)
            float base_data_y = 0.0;
            if (g.y_min > 0.0) { base_data_y = g.y_min; };
            if (g.y_max < 0.0) { base_data_y = g.y_max; };
            int base_py = data_to_screen_y(g, base_data_y);

            int half = bar_width_px / 2;

            int i = 0;
            while (i < count)
            {
                int px  = data_to_screen_x(g, xs[i]);
                int py  = data_to_screen_y(g, ys[i]);

                int bx1 = px - half;
                int bx2 = px + half;
                int by1 = py;
                int by2 = base_py;

                // Swap so top < bottom for Rectangle call
                if (by1 > by2)
                {
                    int tmp = by1;
                    by1 = by2;
                    by2 = tmp;
                };

                c.rect(bx1, by1, bx2, by2);
                i = i + 1;
            };
        };

        // ============================================================================
        // plot_horizontal_bars
        // Draws a horizontal bar chart.  Each bar is centered at ys[i] and stretches
        // from x=0 (or x_min if x_min > 0) to xs[i].
        // xs, ys      : pointer to the first element of float arrays
        // count       : number of bars
        // color       : DWORD fill/outline color
        // bar_height_px : height of each bar in screen pixels
        // ============================================================================
        def plot_horizontal_bars(Canvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int bar_height_px) -> void
        {
            c.set_pen(color, 1);

            float base_data_x = 0.0;
            if (g.x_min > 0.0) { base_data_x = g.x_min; };
            if (g.x_max < 0.0) { base_data_x = g.x_max; };
            int base_px = data_to_screen_x(g, base_data_x);

            int half = bar_height_px / 2;

            int i = 0;
            while (i < count)
            {
                int px  = data_to_screen_x(g, xs[i]);
                int py  = data_to_screen_y(g, ys[i]);

                int bx1 = base_px;
                int bx2 = px;
                int by1 = py - half;
                int by2 = py + half;

                if (bx1 > bx2)
                {
                    int tmp = bx1;
                    bx1 = bx2;
                    bx2 = tmp;
                };

                c.rect(bx1, by1, bx2, by2);
                i = i + 1;
            };
        };

        // ============================================================================
        // plot_area
        // Draws a filled area under a line graph (like plot_line but fills down to
        // the baseline y=0).  Uses individual vertical line segments to fill.
        // xs, ys    : pointer to the first element of float arrays
        // count     : number of points
        // color     : DWORD fill color
        // ============================================================================
        def plot_area(Canvas* c, Graph* g, float* xs, float* ys, int count, DWORD color) -> void
        {
            if (count < 2) { return; };

            c.set_pen(color, 1);

            float base_data_y = 0.0;
            if (g.y_min > 0.0) { base_data_y = g.y_min; };
            if (g.y_max < 0.0) { base_data_y = g.y_max; };
            int base_py = data_to_screen_y(g, base_data_y);

            // Fill using vertical lines between consecutive data columns
            int i = 0;
            while (i < count - 1)
            {
                int x1 = data_to_screen_x(g, xs[i]);
                int x2 = data_to_screen_x(g, xs[i + 1]);
                int y1 = data_to_screen_y(g, ys[i]);
                int y2 = data_to_screen_y(g, ys[i + 1]);

                // Step across pixels between x1 and x2
                int dx = x2 - x1;
                if (dx < 0) { dx = -dx; };
                if (dx == 0) { dx = 1; };

                int xstep = x1;
                while (xstep <= x2)
                {
                    // Interpolate Y at this column
                    float t = 0.0;
                    if (x2 != x1)
                    {
                        t = (float)(xstep - x1) / (float)(x2 - x1);
                    };
                    int interp_y = y1 + (int)((float)(y2 - y1) * t);
                    c.line(xstep, interp_y, xstep, base_py);
                    xstep = xstep + 1;
                };
                i = i + 1;
            };
        };

        // ============================================================================
        // plot_step
        // Draws a step (staircase) chart connecting data points with horizontal then
        // vertical segments.
        // xs, ys    : pointer to the first element of float arrays
        // count     : number of points
        // color     : DWORD line color
        // line_width: pen width in pixels
        // ============================================================================
        def plot_step(Canvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int line_width) -> void
        {
            if (count < 2) { return; };

            c.set_pen(color, line_width);

            int i = 0;
            while (i < count - 1)
            {
                int px1 = data_to_screen_x(g, xs[i]);
                int py1 = data_to_screen_y(g, ys[i]);
                int px2 = data_to_screen_x(g, xs[i + 1]);
                int py2 = data_to_screen_y(g, ys[i + 1]);

                // Horizontal segment at current Y
                c.line(px1, py1, px2, py1);
                // Vertical segment to next Y
                c.line(px2, py1, px2, py2);

                i = i + 1;
            };
        };

        // ============================================================================
        // draw_crosshair
        // Draws a crosshair at a specific data-space coordinate.
        // data_x, data_y : the point in data space
        // color          : DWORD line color
        // ============================================================================
        def draw_crosshair(Canvas* c, Graph* g, float data_x, float data_y, DWORD color) -> void
        {
            c.set_pen(color, 1);

            int px     = data_to_screen_x(g, data_x);
            int py     = data_to_screen_y(g, data_y);
            int left   = g.x;
            int right  = g.x + g.width;
            int top    = g.y;
            int bottom = g.y + g.height;

            c.line(left,  py, right,  py);   // Horizontal
            c.line(px,   top,   px, bottom); // Vertical
        };

        // ============================================================================
        // draw_tick_marks
        // Draws small tick marks along the X and Y axes at regular intervals.
        // x_ticks    : number of ticks along X axis
        // y_ticks    : number of ticks along Y axis
        // tick_len   : length of each tick in pixels
        // color      : DWORD tick color
        // ============================================================================
        def draw_tick_marks(Canvas* c, Graph* g, int x_ticks, int y_ticks, int tick_len, DWORD color) -> void
        {
            c.set_pen(color, 1);

            int left   = g.x;
            int bottom = g.y + g.height;
            int top    = g.y;

            // X-axis ticks (along bottom)
            int i = 0;
            while (i <= x_ticks)
            {
                int px = left + (g.width * i) / x_ticks;
                c.line(px, bottom, px, bottom + tick_len);
                i = i + 1;
            };

            // Y-axis ticks (along left)
            int j = 0;
            while (j <= y_ticks)
            {
                int py = bottom - (g.height * j) / y_ticks;
                c.line(left - tick_len, py, left, py);
                j = j + 1;
            };
        };

        // ============================================================================
        // draw_data_point_label
        // Draws a small dot and uses GDI TextOutA to render a label string at
        // a data-space coordinate.  Caller is responsible for the null-terminated
        // label string and its length.
        // data_x, data_y : position in data space
        // label          : null-terminated byte string
        // label_len      : character count (excluding null terminator)
        // text_color     : DWORD color for the text
        // ============================================================================
        def draw_data_point_label(Canvas* c, Graph* g, float data_x, float data_y, byte* label, int label_len, DWORD text_color) -> void
        {
            int px = data_to_screen_x(g, data_x);
            int py = data_to_screen_y(g, data_y);

            // Draw a small cross marker at the point
            c.set_pen(text_color, 1);
            c.line(px - 3, py,     px + 3, py);
            c.line(px,     py - 3, px,     py + 3);

            // Render label text offset slightly above-right of the point
            SetBkMode(c.back_dc, TRANSPARENT);
            SetTextColor(c.back_dc, text_color);
            TextOutA(c.back_dc, px + 5, py - 14, (LPCSTR)label, label_len);
        };

        // ============================================================================
        // draw_title
        // Renders a title string centered horizontally above the plot area.
        // title     : null-terminated byte string
        // title_len : character count (excluding null terminator)
        // color     : DWORD text color
        // ============================================================================
        def draw_title(Canvas* c, Graph* g, byte* title, DWORD color) -> void
        {
            int title_len = strlen(title);
            int center_x = g.x + g.width / 2 - (title_len * 4);
            int title_y  = g.y - 20;
            if (title_y < 0) { title_y = 2; };

            SetBkMode(c.back_dc, TRANSPARENT);
            SetTextColor(c.back_dc, color);
            TextOutA(c.back_dc, center_x, title_y, (LPCSTR)title, title_len);
        };

        // ============================================================================
        // draw_x_label
        // Renders an X-axis label centered below the plot area.
        // label     : null-terminated byte string
        // label_len : character count (excluding null terminator)
        // color     : DWORD text color
        // ============================================================================
        def draw_x_label(Canvas* c, Graph* g, byte* label, DWORD color) -> void
        {
            int label_len = strlen(label);
            int center_x = g.x + g.width / 2 - (label_len * 4);
            int label_y  = g.y + g.height;

            SetBkMode(c.back_dc, TRANSPARENT);
            SetTextColor(c.back_dc, color);
            TextOutA(c.back_dc, center_x, label_y, (LPCSTR)label, label_len);
        };

        // ============================================================================
        // draw_y_label
        // Renders a Y-axis label to the left of the plot area.
        // label     : null-terminated byte string
        // label_len : character count (excluding null terminator)
        // color     : DWORD text color
        // ============================================================================
        def draw_y_label(Canvas* c, Graph* g, byte* label, DWORD color) -> void
        {
            int label_len = strlen(label);
            int label_x = g.x - (label_len * 8) - 8;
            if (label_x < 0) { label_x = 2; };
            int label_y = g.y + g.height / 2 - 8;

            SetBkMode(c.back_dc, TRANSPARENT);
            SetTextColor(c.back_dc, color);
            TextOutA(c.back_dc, label_x, label_y, (LPCSTR)label, label_len);
        };

        // ============================================================================
        // auto_range_x / auto_range_y
        // Computes a tight range (with a small margin) from an array of floats.
        // Writes the result directly into the Graph's x_min/x_max or y_min/y_max.
        // vals   : pointer to the first element of a float array
        // count  : number of elements
        // margin : fractional padding added to each side (e.g. 0.1 = 10%)
        // ============================================================================
        def auto_range_x(Graph* g, float* vals, int count, float margin) -> void
        {
            if (count <= 0) { return; };

            float lo = vals[0];
            float hi = vals[0];

            int i = 1;
            while (i < count)
            {
                if (vals[i] < lo) { lo = vals[i]; };
                if (vals[i] > hi) { hi = vals[i]; };
                i = i + 1;
            };

            float span = hi - lo;
            if (span == 0.0) { span = 1.0; };

            g.x_min = lo - span * margin;
            g.x_max = hi + span * margin;
        };

        def auto_range_y(Graph* g, float* vals, int count, float margin) -> void
        {
            if (count <= 0) { return; };

            float lo = vals[0];
            float hi = vals[0];

            int i = 1;
            while (i < count)
            {
                if (vals[i] < lo) { lo = vals[i]; };
                if (vals[i] > hi) { hi = vals[i]; };
                i = i + 1;
            };

            float span = hi - lo;
            if (span == 0.0) { span = 1.0; };

            g.y_min = lo - span * margin;
            g.y_max = hi + span * margin;
        };

    };  // namespace graphing
};      // namespace standard

#endif;
