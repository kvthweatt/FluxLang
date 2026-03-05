// redgraphing.fx - Flux Graphing Library
// Provides 2D line graphs, bar charts, scatter plots, and axes/grid rendering,
// plus a full 3D graphing system with parametric data generators.
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
            int   x,        // Left edge of plot area
                  y,        // Top edge of plot area
                  width,    // Width of plot area
                  height;   // Height of plot area

            // Data-space ranges
            float x_min,
                  x_max,
                  y_min,
                  y_max;
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
            int left   = g.x,
                right  = g.x + g.width,
                top    = g.y,
                bottom = g.y + g.height;

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

            int left   = g.x,
                right  = g.x + g.width,
                top    = g.y,
                bottom = g.y + g.height,
                i = 1, j = 1;

            // Vertical grid lines
            while (i < x_divs)
            {
                int px = left + (g.width * i) / x_divs;
                c.line(px, top, px, bottom);
                i = i + 1;
            };

            // Horizontal grid lines
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

            int prev_px = data_to_screen_x(g, xs[0]),
                prev_py = data_to_screen_y(g, ys[0]),
                i = 1;

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

            int base_py = data_to_screen_y(g, base_data_y),
                half = bar_width_px / 2,
                px, py, bx1, bx2, by1, by2,
                i = 0, tmp;

            while (i < count)
            {
                px  = data_to_screen_x(g, xs[i]);
                py  = data_to_screen_y(g, ys[i]);

                bx1 = px - half;
                bx2 = px + half;
                by1 = py;
                by2 = base_py;

                // Swap so top < bottom for Rectangle call
                if (by1 > by2)
                {
                    tmp = by1;
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

            int base_px = data_to_screen_x(g, base_data_x),
                half = bar_height_px / 2,
                px, py, bx1, bx2, by1, by2,
                i = 0, tmp;

            while (i < count)
            {
                px  = data_to_screen_x(g, xs[i]);
                py  = data_to_screen_y(g, ys[i]);

                bx1 = base_px;
                bx2 = px;
                by1 = py - half;
                by2 = py + half;

                if (bx1 > bx2)
                {
                    tmp = bx1;
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

            float base_data_y = 0.0, t;
            if (g.y_min > 0.0) { base_data_y = g.y_min; };
            if (g.y_max < 0.0) { base_data_y = g.y_max; };
            int base_py = data_to_screen_y(g, base_data_y),
                interp_y, xstep,
                x1, x2, y1, y2, dx,
                i = 0;


            // Fill using vertical lines between consecutive data columns
            while (i < count - 1)
            {
                x1 = data_to_screen_x(g, xs[i]);
                x2 = data_to_screen_x(g, xs[i + 1]);
                y1 = data_to_screen_y(g, ys[i]);
                y2 = data_to_screen_y(g, ys[i + 1]);

                // Step across pixels between x1 and x2
                dx = x2 - x1;
                if (dx < 0) { dx = -dx; };
                if (dx == 0) { dx = 1; };

                xstep = x1;
                while (xstep <= x2)
                {
                    // Interpolate Y at this column
                    t = 0.0;
                    if (x2 != x1)
                    {
                        t = (float)(xstep - x1) / (float)(x2 - x1);
                    };
                    interp_y = y1 + (int)((float)(y2 - y1) * t);
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

            int i = 0,
                px1, px2, py1, py2;

            while (i < count - 1)
            {
                px1 = data_to_screen_x(g, xs[i]);
                py1 = data_to_screen_y(g, ys[i]);
                px2 = data_to_screen_x(g, xs[i + 1]);
                py2 = data_to_screen_y(g, ys[i + 1]);

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

            int px     = data_to_screen_x(g, data_x),
                py     = data_to_screen_y(g, data_y),
                left   = g.x,
                right  = g.x + g.width,
                top    = g.y,
                bottom = g.y + g.height;

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

            int left   = g.x,
                bottom = g.y + g.height,
                top    = g.y,
                i = 0, j = 0, px, py;

            // X-axis ticks (along bottom)
            while (i <= x_ticks)
            {
                px = left + (g.width * i) / x_ticks;
                c.line(px, bottom, px, bottom + tick_len);
                i = i + 1;
            };

            // Y-axis ticks (along left)
            while (j <= y_ticks)
            {
                py = bottom - (g.height * j) / y_ticks;
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
            int px = data_to_screen_x(g, data_x),
                py = data_to_screen_y(g, data_y);

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
            int title_len = strlen(title),
                center_x = g.x + g.width / 2 - (title_len * 4),
                title_y  = g.y - 20;
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
            int label_len = strlen(label),
                center_x = g.x + g.width / 2 - (label_len * 4),
                label_y  = g.y + g.height;

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
            int label_len = strlen(label),
                label_x = g.x - (label_len * 8) - 8;
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

            float lo = vals[0],
                  hi = vals[0],
                  span;

            int i = 1;
            while (i < count)
            {
                if (vals[i] < lo) { lo = vals[i]; };
                if (vals[i] > hi) { hi = vals[i]; };
                i = i + 1;
            };

            span = hi - lo;
            if (span == 0.0) { span = 1.0; };

            g.x_min = lo - span * margin;
            g.x_max = hi + span * margin;
        };

        def auto_range_y(Graph* g, float* vals, int count, float margin) -> void
        {
            if (count <= 0) { return; };

            float lo = vals[0],
                  hi = vals[0],
                  span;

            int i = 1;
            while (i < count)
            {
                if (vals[i] < lo) { lo = vals[i]; };
                if (vals[i] > hi) { hi = vals[i]; };
                i = i + 1;
            };

            span = hi - lo;
            if (span == 0.0) { span = 1.0; };

            g.y_min = lo - span * margin;
            g.y_max = hi + span * margin;
        };

    };  // namespace graphing
};      // namespace standard


// ============================================================================
// 3D GRAPHING
// Built on top of standard::math Vec3 / rotate_x/y/z / project.
// Graph3D describes the data-space ranges and the screen viewport centre,
// plus the perspective camera parameters forwarded straight to project().
//
// Usage example:
//
//   #import "standard.fx";
//   #import "redwindows.fx";
//   #import "redgraphing.fx";
//
//   using standard::system::windows;
//   using standard::graphing;
//   using standard::graphing::graph3d;
//   using standard::graphing::graph3d::generators;
//
//   def main() -> int
//   {
//       Window win("3D Graph\0", 800, 600, CW_USEDEFAULT, CW_USEDEFAULT);
//       Canvas c(win.handle, win.device_context);
//
//       float[8] xs = [1.0, 2.0, 3.0, 4.0, 1.0, 2.0, 3.0, 4.0];
//       float[8] ys = [1.0, 1.0, 1.0, 1.0, 3.0, 3.0, 3.0, 3.0];
//       float[8] zs = [1.0, 3.0, 2.0, 4.0, 2.0, 1.0, 4.0, 3.0];
//
//       // Or generate data with a built-in generator:
//       float[80] gx; float[80] gy; float[80] gz;
//       generators::gen_helix(@gx[0], @gy[0], @gz[0], 80, 0.0);
//
//       Graph3D g;
//       g.cx     = 400;      // screen centre X
//       g.cy     = 300;      // screen centre Y
//       g.fov    = 300.0;    // perspective field-of-view scale
//       g.cam_z  = 6.0;      // camera distance along Z
//       g.rot_x  = 0.45;     // pitch  (radians)
//       g.rot_y  = 0.6;      // yaw    (radians)
//       g.x_min  = 0.0;  g.x_max = 5.0;
//       g.y_min  = 0.0;  g.y_max = 5.0;
//       g.z_min  = 0.0;  g.z_max = 5.0;
//       g.scale  = 1.0;      // uniform data-space scale
//
//       while (win.process_messages())
//       {
//           c.clear(RGB(20, 20, 20));
//           graph3d::draw_axes3d(@c, @g, RGB(180, 180, 180), 1);
//           graph3d::draw_grid3d(@c, @g, 5, 5, RGB(50, 50, 50));
//           graph3d::plot_scatter3d(@c, @g, @xs[0], @ys[0], @zs[0], 8,
//                                   RGB(0, 200, 255), 3);
//           graph3d::plot_line3d(@c, @g, @xs[0], @ys[0], @zs[0], 8,
//                                RGB(255, 100, 50), 1);
//       };
//
//       win.__exit();
//       return 0;
//   };
// ============================================================================

namespace standard
{
    namespace graphing
    {
        namespace graph3d
        {
            // ================================================================
            // Graph3D - viewport, camera, and data-range descriptor
            // ================================================================

            struct Graph3D
            {
                // Screen-space viewport centre (pixels)
                int   cx,       // Centre X on canvas
                      cy;       // Centre Y on canvas

                // Perspective camera parameters (passed to math::project)
                float fov,      // Field-of-view scale factor
                      cam_z,    // Camera distance from origin along Z

                // Euler rotation angles (radians) applied before projection
                      rot_x,    // Pitch around X axis
                      rot_y,    // Yaw   around Y axis
                      rot_z,    // Roll  around Z axis

                // Data-space ranges (used to normalise incoming data)
                      x_min,
                      x_max,
                      y_min,
                      y_max,
                      z_min,
                      z_max,

                // Uniform scale applied after normalisation
                      scale;
            };

            // ================================================================
            // Internal helpers
            // ================================================================

            // Normalise a single data value to a centred [-0.5, 0.5] range
            // then multiply by scale.  The same transform is applied to all
            // three axes so the graph fits symmetrically around the origin.
            def norm(float val, float lo, float hi, float sc) -> float
            {
                float range = hi - lo;
                if (range == 0.0) { return 0.0; };
                return ((val - lo) / range - 0.5) * sc;
            };

            // Build a Vec3 from raw data coordinates, normalise and rotate,
            // then project to a screen POINT via math::project.
            def data3_to_screen(Graph3D* g, float dx, float dy, float dz) -> POINT
            {
                Vec3 v;
                v.x =  norm(dx, g.x_min, g.x_max, g.scale);
                v.y =  norm(dy, g.y_min, g.y_max, g.scale);
                v.z =  norm(dz, g.z_min, g.z_max, g.scale);

                // Rotate around X then Y then Z
                float sx = sin(g.rot_x),
                      cx = cos(g.rot_x),
                      sy = sin(g.rot_y),
                      cy = cos(g.rot_y),
                      sz = sin(g.rot_z),
                      cz = cos(g.rot_z);

                Vec3 rx = rotate_x(@v,  sx, cx);
                Vec3 ry = rotate_y(@rx, sy, cy);
                Vec3 rz = rotate_z(@ry, sz, cz);

                return project(@rz, g.cx, g.cy, g.fov, g.cam_z);
            };

            // ================================================================
            // draw_axes3d
            // Draws the three principal axes (X, Y, Z) from min to max.
            // axis_color : DWORD color for all three axes
            // line_width : pen width in pixels
            // ================================================================
            def draw_axes3d(Canvas* c, Graph3D* g, DWORD axis_color, int line_width) -> void
            {
                c.set_pen(axis_color, line_width);

                // X axis  (y_min, z_min plane)
                POINT p0 = data3_to_screen(g, g.x_min, g.y_min, g.z_min);
                POINT p1 = data3_to_screen(g, g.x_max, g.y_min, g.z_min);
                c.line(p0.x, p0.y, p1.x, p1.y);

                // Y axis  (x_min, z_min plane)
                POINT p2 = data3_to_screen(g, g.x_min, g.y_min, g.z_min);
                POINT p3 = data3_to_screen(g, g.x_min, g.y_max, g.z_min);
                c.line(p2.x, p2.y, p3.x, p3.y);

                // Z axis  (x_min, y_min plane)
                POINT p4 = data3_to_screen(g, g.x_min, g.y_min, g.z_min);
                POINT p5 = data3_to_screen(g, g.x_min, g.y_min, g.z_max);
                c.line(p4.x, p4.y, p5.x, p5.y);
            };

            // ================================================================
            // draw_grid3d
            // Draws a floor grid on the XZ plane at y_min, plus a back wall
            // grid on the XY plane at z_min.
            // x_divs     : divisions along X
            // z_divs     : divisions along Z
            // grid_color : DWORD color for grid lines
            // ================================================================
            def draw_grid3d(Canvas* c, Graph3D* g, int x_divs, int z_divs, DWORD grid_color) -> void
            {
                c.set_pen(grid_color, 1);

                // Floor grid lines parallel to Z (along X divisions)
                int i = 0, j = 0;
                float fx, fz;
                POINT a, b;
                while (i <= x_divs)
                {
                    fx = g.x_min + (g.x_max - g.x_min) * (float)i / (float)x_divs;
                    a = data3_to_screen(g, fx, g.y_min, g.z_min);
                    b = data3_to_screen(g, fx, g.y_min, g.z_max);
                    c.line(a.x, a.y, b.x, b.y);
                    i = i + 1;
                };

                // Floor grid lines parallel to X (along Z divisions)
                while (j <= z_divs)
                {
                    fz = g.z_min + (g.z_max - g.z_min) * (float)j / (float)z_divs;
                    a = data3_to_screen(g, g.x_min, g.y_min, fz);
                    b = data3_to_screen(g, g.x_max, g.y_min, fz);
                    c.line(a.x, a.y, b.x, b.y);
                    j = j + 1;
                };
            };

            // ================================================================
            // draw_box3d
            // Draws the twelve edges of the data-range bounding box.
            // color      : DWORD color
            // line_width : pen width in pixels
            // ================================================================
            def draw_box3d(Canvas* c, Graph3D* g, DWORD color, int line_width) -> void
            {
                c.set_pen(color, line_width);

                float x0 = g.x_min; float x1 = g.x_max,
                      y0 = g.y_min; float y1 = g.y_max,
                      z0 = g.z_min; float z1 = g.z_max;

                // Bottom face
                POINT a = data3_to_screen(g, x0, y0, z0),
                      b = data3_to_screen(g, x1, y0, z0),
                      cc = data3_to_screen(g, x1, y0, z1),
                      d = data3_to_screen(g, x0, y0, z1);
                c.line(a.x, a.y, b.x, b.y);
                c.line(b.x, b.y, cc.x, cc.y);
                c.line(cc.x, cc.y, d.x, d.y);
                c.line(d.x, d.y, a.x, a.y);

                // Top face
                POINT e = data3_to_screen(g, x0, y1, z0),
                      f = data3_to_screen(g, x1, y1, z0),
                      gg = data3_to_screen(g, x1, y1, z1),
                      h = data3_to_screen(g, x0, y1, z1);
                c.line(e.x, e.y, f.x, f.y);
                c.line(f.x, f.y, gg.x, gg.y);
                c.line(gg.x, gg.y, h.x, h.y);
                c.line(h.x, h.y, e.x, e.y);

                // Vertical edges
                c.line(a.x, a.y, e.x, e.y);
                c.line(b.x, b.y, f.x, f.y);
                c.line(cc.x, cc.y, gg.x, gg.y);
                c.line(d.x, d.y, h.x, h.y);
            };

            // ================================================================
            // plot_scatter3d
            // Draws a small square marker at each (xs[i], ys[i], zs[i]) point.
            // xs, ys, zs : pointer to first element of float arrays
            // count      : number of points
            // color      : DWORD marker color
            // radius     : half-size of marker in pixels
            // ================================================================
            def plot_scatter3d(Canvas* c, Graph3D* g, float* xs, float* ys, float* zs, int count, DWORD color, int radius) -> void
            {
                c.set_pen(color, 1);

                int i = 0;
                POINT p;
                while (i < count)
                {
                    p = data3_to_screen(g, xs[i], ys[i], zs[i]);
                    c.rect(p.x - radius, p.y - radius, p.x + radius, p.y + radius);
                    i = i + 1;
                };
            };

            // ================================================================
            // plot_scatter3d_circles
            // Draws a circle marker at each (xs[i], ys[i], zs[i]) point.
            // xs, ys, zs : pointer to first element of float arrays
            // count      : number of points
            // color      : DWORD marker color
            // radius     : circle radius in pixels
            // ================================================================
            def plot_scatter3d_circles(Canvas* c, Graph3D* g, float* xs, float* ys, float* zs, int count, DWORD color, int radius) -> void
            {
                c.set_pen(color, 1);

                int i = 0;
                POINT p;
                while (i < count)
                {
                    p = data3_to_screen(g, xs[i], ys[i], zs[i]);
                    c.circle(p.x, p.y, radius);
                    i = i + 1;
                };
            };

            // ================================================================
            // plot_line3d
            // Draws a connected polyline through (xs[i], ys[i], zs[i]) points.
            // xs, ys, zs : pointer to first element of float arrays
            // count      : number of points
            // color      : DWORD line color
            // line_width : pen width in pixels
            // ================================================================
            def plot_line3d(Canvas* c, Graph3D* g, float* xs, float* ys, float* zs, int count, DWORD color, int line_width) -> void
            {
                if (count < 2) { return; };

                c.set_pen(color, line_width);

                POINT prev = data3_to_screen(g, xs[0], ys[0], zs[0]),
                      cur;

                int i = 1;
                while (i < count)
                {
                    cur = data3_to_screen(g, xs[i], ys[i], zs[i]);
                    c.line(prev.x, prev.y, cur.x, cur.y);
                    prev = cur;
                    i = i + 1;
                };
            };

            // ================================================================
            // plot_surface
            // Draws a wireframe surface from a 2D grid of Z values.
            // The grid has (x_count) columns and (y_count) rows.
            // xs         : pointer to x_count X values (column positions)
            // ys         : pointer to y_count Y values (row positions)
            // zs         : pointer to (x_count * y_count) Z values,
            //              stored row-major: zs[row * x_count + col]
            // color      : DWORD wireframe color
            // line_width : pen width in pixels
            // ================================================================
            def plot_surface(Canvas* c, Graph3D* g, float* xs, float* ys, float* zs, int x_count, int y_count, DWORD color, int line_width) -> void
            {
                if (x_count < 2 | y_count < 2) { return; };

                c.set_pen(color, line_width);

                int row = 0,
                    col;

                float z00, z01, z10;
                POINT a,b;

                while (row < y_count)
                {
                    col = 0;
                    while (col < x_count)
                    {
                        z00 = zs[row * x_count + col];

                        // Horizontal edge to next column
                        if (col < x_count - 1)
                        {
                            z01 = zs[row * x_count + col + 1];
                            a = data3_to_screen(g, xs[col],     ys[row], z00);
                            b = data3_to_screen(g, xs[col + 1], ys[row], z01);
                            c.line(a.x, a.y, b.x, b.y);
                        };

                        // Vertical edge to next row
                        if (row < y_count - 1)
                        {
                            z10 = zs[(row + 1) * x_count + col];
                            a = data3_to_screen(g, xs[col], ys[row],     z00);
                            b = data3_to_screen(g, xs[col], ys[row + 1], z10);
                            c.line(a.x, a.y, b.x, b.y);
                        };

                        col = col + 1;
                    };
                    row = row + 1;
                };
            };

            // ================================================================
            // plot_bars3d
            // Draws a vertical bar for each (xs[i], zs[i]) data point,
            // rising from y_min to ys[i].
            // xs, ys, zs  : pointer to first element of float arrays
            // count       : number of bars
            // color       : DWORD bar color
            // bar_size_px : half-width of the bar footprint in screen pixels
            // ================================================================
            def plot_bars3d(Canvas* c, Graph3D* g, float* xs, float* ys, float* zs, int count, DWORD color, int bar_size_px) -> void
            {
                c.set_pen(color, 1);

                int i = 0;
                POINT top, base;

                while (i < count)
                {
                    // Top and base of the bar
                    top  = data3_to_screen(g, xs[i], ys[i],    zs[i]);
                    base = data3_to_screen(g, xs[i], g.y_min,  zs[i]);

                    // Vertical stem
                    c.line(base.x, base.y, top.x, top.y);

                    // Small cross at the top to indicate the data point
                    c.line(top.x - bar_size_px, top.y, top.x + bar_size_px, top.y);
                    c.line(top.x, top.y - bar_size_px, top.x, top.y + bar_size_px);

                    i = i + 1;
                };
            };

            // ================================================================
            // draw_axes3d_labels
            // Renders text labels at the positive end of each axis.
            // x_label, y_label, z_label : null-terminated byte strings
            // color                     : DWORD text color
            // ================================================================
            def draw_axes3d_labels(Canvas* c, Graph3D* g, byte* x_label, byte* y_label, byte* z_label, DWORD color) -> void
            {
                SetBkMode(c.back_dc, TRANSPARENT);
                SetTextColor(c.back_dc, color);

                int x_len = strlen(x_label),
                    y_len = strlen(y_label),
                    z_len = strlen(z_label);

                POINT px = data3_to_screen(g, g.x_max, g.y_min, g.z_min),
                      py = data3_to_screen(g, g.x_min, g.y_max, g.z_min),
                      pz = data3_to_screen(g, g.x_min, g.y_min, g.z_max);

                TextOutA(c.back_dc, px.x + 4, px.y - 6, (LPCSTR)x_label, x_len);
                TextOutA(c.back_dc, py.x + 4, py.y - 6, (LPCSTR)y_label, y_len);
                TextOutA(c.back_dc, pz.x + 4, pz.y - 6, (LPCSTR)z_label, z_len);
            };

            // ================================================================
            // draw_title3d
            // Renders a title string centered above the viewport centre.
            // title : null-terminated byte string
            // color : DWORD text color
            // ================================================================
            def draw_title3d(Canvas* c, Graph3D* g, byte* title, DWORD color) -> void
            {
                int title_len = strlen(title),
                    tx = g.cx - (title_len * 4),
                    ty = g.cy - (int)(g.fov * 0.6);
                if (ty < 2) { ty = 2; };

                SetBkMode(c.back_dc, TRANSPARENT);
                SetTextColor(c.back_dc, color);
                TextOutA(c.back_dc, tx, ty, (LPCSTR)title, title_len);
            };

            // ================================================================
            // auto_range_z
            // Computes a tight range (with a small margin) from a float array.
            // Writes the result into the Graph3D's z_min / z_max.
            // vals   : pointer to first element of a float array
            // count  : number of elements
            // margin : fractional padding added to each side (e.g. 0.1 = 10%)
            // ================================================================
            def auto_range_z(Graph3D* g, float* vals, int count, float margin) -> void
            {
                if (count <= 0) { return; };

                float lo = vals[0],
                      hi = vals[0],
                      span;

                int i = 1;
                while (i < count)
                {
                    if (vals[i] < lo) { lo = vals[i]; };
                    if (vals[i] > hi) { hi = vals[i]; };
                    i = i + 1;
                };

                span = hi - lo;
                if (span == 0.0) { span = 1.0; };

                g.z_min = lo - span * margin;
                g.z_max = hi + span * margin;
            };

            // ================================================================
            // auto_range3d
            // Convenience wrapper: computes tight ranges for all three axes
            // from separate float arrays.
            // xs, ys, zs : pointers to first elements of float arrays
            // count      : number of elements in each array
            // margin     : fractional padding (e.g. 0.1 = 10%)
            // ================================================================
            def auto_range3d(Graph3D* g, float* xs, float* ys, float* zs, int count, float margin) -> void
            {
                if (count <= 0) { return; };

                float xlo = xs[0]; float xhi = xs[0],
                      ylo = ys[0]; float yhi = ys[0],
                      zlo = zs[0]; float zhi = zs[0],
                      xspan, yspan, zspan;

                int i = 1;
                while (i < count)
                {
                    if (xs[i] < xlo) { xlo = xs[i]; };
                    if (xs[i] > xhi) { xhi = xs[i]; };
                    if (ys[i] < ylo) { ylo = ys[i]; };
                    if (ys[i] > yhi) { yhi = ys[i]; };
                    if (zs[i] < zlo) { zlo = zs[i]; };
                    if (zs[i] > zhi) { zhi = zs[i]; };
                    i = i + 1;
                };

                xspan = xhi - xlo; if (xspan == 0.0) { xspan = 1.0; };
                yspan = yhi - ylo; if (yspan == 0.0) { yspan = 1.0; };
                zspan = zhi - zlo; if (zspan == 0.0) { zspan = 1.0; };

                g.x_min = xlo - xspan * margin;
                g.x_max = xhi + xspan * margin;
                g.y_min = ylo - yspan * margin;
                g.y_max = yhi + yspan * margin;
                g.z_min = zlo - zspan * margin;
                g.z_max = zhi + zspan * margin;
            };

            // ================================================================
            // namespace generators
            // Parametric data generators for common 3D curve and surface types.
            // All functions write into caller-supplied float* arrays.
            //
            // Surface generators fill xs[n] and ys[n] (axis samples) and
            // zs[n*n] (row-major grid values).
            //
            // Curve/scatter generators fill xs[n], ys[n], zs[n] point arrays.
            //
            // All output values are normalised to [0, 1] unless noted.
            // phase : animation parameter (radians); pass 0.0 for a static frame.
            // ================================================================
            namespace generators
            {
                // ============================================================
                // gen_ripple
                // Surface: z = (sin(r + phase) + 1) * 0.5
                // where r = sqrt((x-0.5)^2 + (y-0.5)^2) * 8
                // xs[n], ys[n] : axis sample positions (0..1)
                // zs[n*n]      : row-major z grid
                // ============================================================
                def gen_ripple(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0,
                        j = 0;

                    float fx, fy, r;

                    while (i < n)
                    {
                        xs[i] = (float)i / (float)(n - 1);
                        ys[i] = (float)i / (float)(n - 1);
                        j = 0;
                        while (j < n)
                        {
                            fx = xs[j] - 0.5;
                            fy = xs[i] - 0.5;
                            r  = sqrt(fx * fx + fy * fy) * 8.0;
                            zs[i * n + j] = (sin(r + phase) + 1.0) * 0.5;
                            j = j + 1;
                        };
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_saddle
                // Surface: z = (x^2 - y^2 + 1) * 0.5
                // xs[n], ys[n] : axis sample positions (0..1)
                // zs[n*n]      : row-major z grid
                // ============================================================
                def gen_saddle(float* xs, float* ys, float* zs, int n) -> void
                {
                    int i = 0,
                        j = 0;

                    float u, v;

                    while (i < n)
                    {
                        xs[i] = (float)i / (float)(n - 1);
                        ys[i] = (float)i / (float)(n - 1);
                        j = 0;
                        while (j < n)
                        {
                            u = xs[j] * 2.0 - 1.0;
                            v = xs[i] * 2.0 - 1.0;
                            zs[i * n + j] = (u * u - v * v + 1.0) * 0.5;
                            j = j + 1;
                        };
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_peaks
                // Surface: sum of three Gaussian peaks, output in [0, 1].
                // xs[n], ys[n] : axis sample positions (0..1)
                // zs[n*n]      : row-major z grid
                // ============================================================
                def gen_peaks(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0,
                        k = 0,
                        j = 0;

                    float x, y, z,
                          dx, dy;

                    while (k < n)
                    {
                        xs[k] = (float)k / (float)(n - 1);
                        ys[k] = (float)k / (float)(n - 1);
                        k = k + 1;
                    };
                    i = 0;
                    while (i < n)
                    {
                        j = 0;
                        while (j < n)
                        {
                            x = xs[j];
                            y = xs[i];
                            z = 0.0;
                            // Peak 1
                            dx = x - (0.3 + 0.1 * sin(phase));
                            dy = y - 0.3;
                            z = z + exp((0.0 - (dx * dx + dy * dy)) * 20.0);
                            // Peak 2
                            dx = x - 0.7;
                            dy = y - (0.7 + 0.1 * cos(phase));
                            z = z + exp((0.0 - (dx * dx + dy * dy)) * 20.0);
                            // Peak 3
                            dx = x - 0.5;
                            dy = y - 0.5;
                            z = z + exp((0.0 - (dx * dx + dy * dy)) * 8.0) * 0.5;
                            zs[i * n + j] = z / 2.5;
                            j = j + 1;
                        };
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_torus_surf
                // Surface: z-component of a torus mapped to [0, 1].
                // R = 0.6 (major radius), r = 0.3 (minor radius).
                // xs[n], ys[n] : axis sample positions (0..1)
                // zs[n*n]      : row-major z grid
                // ============================================================
                def gen_torus_surf(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i, j;

                    while (i < n)
                    {
                        xs[i] = (float)i / (float)(n - 1);
                        ys[i] = (float)i / (float)(n - 1);
                        int j = 0;
                        while (j < n)
                        {
                            float u = xs[j] * 2.0 * PIF;
                            float v = xs[i] * 2.0 * PIF + phase;
                            float R = 0.6;
                            float r = 0.3;
                            float x = (R + r * cos(v)) * cos(u);
                            float y = (R + r * cos(v)) * sin(u);
                            float z = r * sin(v);
                            zs[i * n + j] = (z + 1.0) * 0.5;
                            j = j + 1;
                        };
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_interference
                // Surface: z = sin(2x + phase) * cos(3y - phase*0.7), output [0,1].
                // xs[n], ys[n] : axis sample positions (0..1)
                // zs[n*n]      : row-major z grid
                // ============================================================
                def gen_interference(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        xs[i] = (float)i / (float)(n - 1);
                        ys[i] = (float)i / (float)(n - 1);
                        int j = 0;
                        while (j < n)
                        {
                            float x = xs[j] * 2.0 * PIF;
                            float y = xs[i] * 2.0 * PIF;
                            float z = sin(2.0 * x + phase) * cos(3.0 * y - phase * 0.7);
                            zs[i * n + j] = (z + 1.0) * 0.5;
                            j = j + 1;
                        };
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_helix
                // Curve: single-strand helix, 4 full turns.
                // xs[n], ys[n], zs[n] : output point arrays, values in [0,1]
                // ============================================================
                def gen_helix(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t = (float)i / (float)(n - 1);
                        float a = t * 4.0 * PIF + phase;
                        xs[i] = (cos(a) + 1.0) * 0.5;
                        ys[i] = t;
                        zs[i] = (sin(a) + 1.0) * 0.5;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_double_helix
                // Curve: two interleaved helices (even indices = strand A, odd = B).
                // xs[n], ys[n], zs[n] : output point arrays, values in [0,1]
                // ============================================================
                def gen_double_helix(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t   = (float)(i / 2) / (float)(n / 2 - 1);
                        float ang = t * 4.0 * PIF + phase;
                        if ((i % 2) == 0)
                        {
                            xs[i] = (cos(ang) + 1.0) * 0.5;
                            zs[i] = (sin(ang) + 1.0) * 0.5;
                        }
                        else
                        {
                            xs[i] = (cos(ang + PIF) + 1.0) * 0.5;
                            zs[i] = (sin(ang + PIF) + 1.0) * 0.5;
                        };
                        ys[i] = t;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_spiral_coil
                // Curve: Archimedes spiral projected into 3D (flat coil rising).
                // xs[n], ys[n], zs[n] : output point arrays, values in [0,1]
                // ============================================================
                def gen_spiral_coil(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t   = (float)i / (float)(n - 1);
                        float ang = t * 6.0 * PIF + phase;
                        float r   = t;
                        xs[i] = (r * cos(ang) + 1.0) * 0.5;
                        ys[i] = t * 0.5 + sin(t * 4.0 * PIF + phase) * 0.25 + 0.25;
                        zs[i] = (r * sin(ang) + 1.0) * 0.5;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_knot_23
                // Curve: torus knot (2,3).
                // Output is NOT normalised to [0,1]; use auto_range3d before plotting.
                // xs[n], ys[n], zs[n] : output point arrays
                // ============================================================
                def gen_knot_23(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t = (float)i / (float)(n - 1) * 2.0 * PIF + phase;
                        float r = 2.0 + cos(1.5 * t);
                        xs[i] = r * cos(t);
                        ys[i] = sin(1.5 * t);
                        zs[i] = r * sin(t);
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_fig8
                // Curve: figure-eight knot.
                // Output is NOT normalised to [0,1]; use auto_range3d before plotting.
                // xs[n], ys[n], zs[n] : output point arrays
                // ============================================================
                def gen_fig8(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t  = (float)i / (float)(n - 1) * 2.0 * PIF + phase;
                        float c  = cos(t);
                        float s  = sin(t);
                        float c2 = cos(2.0 * t);
                        xs[i] = (2.0 + c2) * c;
                        ys[i] = (2.0 + c2) * s;
                        zs[i] = sin(2.0 * t) * 1.5;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_lissajous
                // Curve: 3D Lissajous figure with frequencies 3, 4, 5.
                // xs[n], ys[n], zs[n] : output point arrays, values in [0,1]
                // ============================================================
                def gen_lissajous(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t = (float)i / (float)(n - 1) * 2.0 * PIF;
                        xs[i] = (sin(3.0 * t + phase)       + 1.0) * 0.5;
                        ys[i] = (sin(4.0 * t)               + 1.0) * 0.5;
                        zs[i] = (cos(5.0 * t + phase * 0.6) + 1.0) * 0.5;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_sphere
                // Scatter: golden-angle sphere distribution.
                // xs[n], ys[n], zs[n] : output point arrays, values in [0,1]
                // ============================================================
                def gen_sphere(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t    = (float)i / (float)n;
                        float phi  = t * PIF;
                        float thet = (float)i * 2.399963 + phase;
                        float sp   = sin(phi);
                        xs[i] = (cos(thet) * sp + 1.0) * 0.5;
                        ys[i] = (cos(phi)       + 1.0) * 0.5;
                        zs[i] = (sin(thet) * sp + 1.0) * 0.5;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_cone
                // Scatter: spiral cone.
                // xs[n], ys[n], zs[n] : output point arrays, values in [0,1]
                // ============================================================
                def gen_cone(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t   = (float)i / (float)(n - 1);
                        float r   = 1.0 - t;
                        float ang = t * 6.0 * PIF + phase;
                        xs[i] = (r * cos(ang) + 1.0) * 0.5;
                        ys[i] = t;
                        zs[i] = (r * sin(ang) + 1.0) * 0.5;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_viviani
                // Curve: Viviani's curve — x=(1+cos t)/2, y=sin(t)/2, z=sin(t/2).
                // xs[n], ys[n], zs[n] : output point arrays, values in [0,1]
                // ============================================================
                def gen_viviani(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t = (float)i / (float)(n - 1) * 4.0 * PIF + phase;
                        xs[i] = (1.0 + cos(t)) * 0.5;
                        ys[i] = (sin(t)        + 1.0) * 0.5;
                        zs[i] = (sin(t * 0.5)  + 1.0) * 0.5;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_cluster
                // Scatter: deterministic pseudo-random cluster (sin-based seed).
                // xs[n], ys[n], zs[n] : output point arrays, values approx [0,1]
                // ============================================================
                def gen_cluster(float* xs, float* ys, float* zs, int n, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        float t  = (float)i;
                        float px = sin(t * 1.3 + phase) * 0.5 + 0.5;
                        float py = sin(t * 2.7 + 1.0)   * 0.5 + 0.5;
                        float pz = sin(t * 3.9 + 2.0)   * 0.5 + 0.5;
                        // Small per-point spread
                        float dx = sin(t * 17.3) * 0.08;
                        float dy = sin(t * 23.1) * 0.08;
                        float dz = sin(t * 31.7) * 0.08;
                        xs[i] = px + dx;
                        ys[i] = py + dy;
                        zs[i] = pz + dz;
                        i = i + 1;
                    };
                };

                // ============================================================
                // gen_bars
                // Bar-chart data: xs and zs hold grid positions (0..1),
                // ys holds animated bar height (0..1).
                // n        : total bar count (typically BAR_N * BAR_N)
                // bar_cols : number of columns in the bar grid (i.e. BAR_N)
                // xs[n], ys[n], zs[n] : output point arrays
                // ============================================================
                def gen_bars(float* xs, float* ys, float* zs, int n, int bar_cols, float phase) -> void
                {
                    int i = 0;
                    while (i < n)
                    {
                        int   col = i % bar_cols;
                        int   row = i / bar_cols;
                        float fc  = (float)col / (float)(bar_cols - 1);
                        float fr  = (float)row / (float)(bar_cols - 1);
                        xs[i] = fc;
                        zs[i] = fr;
                        ys[i] = (sin((fc + fr) * PIF * 2.0 + phase) + 1.0) * 0.5;
                        i = i + 1;
                    };
                };

            };  // namespace generators

        };  // namespace graph3d
    };  // namespace graphing
};      // namespace standard

#endif;
