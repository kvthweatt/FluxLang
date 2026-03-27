// Author: Karac V. Thweatt
//
// d2d_graphing.fx  -  Direct2D overloads for the standard graphing functions
//
// Provides D2DCanvas* overloads of every drawing and plot function from
// graphing.fx so that graph programs can switch to Direct2D rendering
// without any other code changes.
//
// Every function here has the exact same body as its graphing.fx counterpart
// with Canvas* replaced by D2DCanvas*.  The Graph struct and coordinate
// mapping helpers are shared from graphing.fx (imported first).
//
// Import order in your program:
//   #import "standard.fx";
//   #import "direct2d.fx";
//   #import "graphing.fx";
//   #import "d2d_graphing.fx";
//
// Then call draw_grid, plot_line, etc. with D2DCanvas* as the first argument
// and the compiler will resolve to the overloads defined here.

#ifndef FLUX_STANDARD_DIRECT2D
#import "direct2d.fx";
#endif;

#ifndef FLUX_STANDARD_GRAPHING
#import "graphing.fx";
#endif;

#ifndef FLUX_D2D_GRAPHING
#def FLUX_D2D_GRAPHING 1;

using standard::system::windows;
using standard::math;
using standard::graphing;
using standard::d2d;

namespace standard
{
    namespace graphing
    {
        // ====================================================================
        // draw_axes  (D2DCanvas* overload)
        // ====================================================================
        def draw_axes(D2DCanvas* c, Graph* g, DWORD axis_color, int line_width) -> void
        {
            c.set_pen(axis_color, line_width);

            int left   = g.x,
                right  = g.x + g.width,
                top    = g.y,
                bottom = g.y + g.height;

            c.line(left, bottom, right, bottom);
            c.line(left, top,    left,  bottom);
        };

        // ====================================================================
        // draw_grid  (D2DCanvas* overload)
        // ====================================================================
        def draw_grid(D2DCanvas* c, Graph* g, int x_divs, int y_divs, DWORD grid_color) -> void
        {
            c.set_pen(grid_color, 1);

            int left   = g.x,
                right  = g.x + g.width,
                top    = g.y,
                bottom = g.y + g.height,
                i = 1, j = 1;

            while (i < x_divs)
            {
                int px = left + (g.width * i) / x_divs;
                c.line(px, top, px, bottom);
                i = i + 1;
            };

            while (j < y_divs)
            {
                int py = top + (g.height * j) / y_divs;
                c.line(left, py, right, py);
                j = j + 1;
            };
        };

        // ====================================================================
        // draw_border  (D2DCanvas* overload)
        // ====================================================================
        def draw_border(D2DCanvas* c, Graph* g, DWORD border_color, int line_width) -> void
        {
            c.set_pen(border_color, line_width);

            int left   = g.x,
                right  = g.x + g.width,
                top    = g.y,
                bottom = g.y + g.height;

            c.line(left,  top,    right, top);
            c.line(right, top,    right, bottom);
            c.line(right, bottom, left,  bottom);
            c.line(left,  bottom, left,  top);
        };

        // ====================================================================
        // plot_line  (D2DCanvas* overload)
        // ====================================================================
        def plot_line(D2DCanvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int line_width) -> void
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

        // ====================================================================
        // plot_scatter  (D2DCanvas* overload)
        // ====================================================================
        def plot_scatter(D2DCanvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int radius) -> void
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

        // ====================================================================
        // plot_scatter_circles  (D2DCanvas* overload)
        // ====================================================================
        def plot_scatter_circles(D2DCanvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int radius) -> void
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

        // ====================================================================
        // plot_bars  (D2DCanvas* overload)
        // ====================================================================
        def plot_bars(D2DCanvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int bar_width_px) -> void
        {
            c.set_pen(color, 1);

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

        // ====================================================================
        // plot_horizontal_bars  (D2DCanvas* overload)
        // ====================================================================
        def plot_horizontal_bars(D2DCanvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int bar_height_px) -> void
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

        // ====================================================================
        // plot_area  (D2DCanvas* overload)
        // ====================================================================
        def plot_area(D2DCanvas* c, Graph* g, float* xs, float* ys, int count, DWORD color) -> void
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

            while (i < count - 1)
            {
                x1 = data_to_screen_x(g, xs[i]);
                x2 = data_to_screen_x(g, xs[i + 1]);
                y1 = data_to_screen_y(g, ys[i]);
                y2 = data_to_screen_y(g, ys[i + 1]);

                dx = x2 - x1;
                if (dx < 0) { dx = -dx; };
                if (dx == 0) { dx = 1; };

                xstep = x1;
                while (xstep <= x2)
                {
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

        // ====================================================================
        // plot_step  (D2DCanvas* overload)
        // ====================================================================
        def plot_step(D2DCanvas* c, Graph* g, float* xs, float* ys, int count, DWORD color, int line_width) -> void
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

                c.line(px1, py1, px2, py1);
                c.line(px2, py1, px2, py2);

                i = i + 1;
            };
        };

        // ====================================================================
        // draw_crosshair  (D2DCanvas* overload)
        // ====================================================================
        def draw_crosshair(D2DCanvas* c, Graph* g, float data_x, float data_y, DWORD color) -> void
        {
            c.set_pen(color, 1);

            int px     = data_to_screen_x(g, data_x),
                py     = data_to_screen_y(g, data_y),
                left   = g.x,
                right  = g.x + g.width,
                top    = g.y,
                bottom = g.y + g.height;

            c.line(left, py,  right,  py);
            c.line(px,   top, px,     bottom);
        };

        // ====================================================================
        // draw_tick_marks  (D2DCanvas* overload)
        // ====================================================================
        def draw_tick_marks(D2DCanvas* c, Graph* g, int x_ticks, int y_ticks, int tick_len, DWORD color) -> void
        {
            c.set_pen(color, 1);

            int left   = g.x,
                bottom = g.y + g.height,
                top    = g.y,
                i = 0, j = 0, px, py;

            while (i <= x_ticks)
            {
                px = left + (g.width * i) / x_ticks;
                c.line(px, bottom, px, bottom + tick_len);
                i = i + 1;
            };

            while (j <= y_ticks)
            {
                py = bottom - (g.height * j) / y_ticks;
                c.line(left - tick_len, py, left, py);
                j = j + 1;
            };
        };

        // ====================================================================
        // draw_title  (D2DCanvas* overload)
        // Uses D2DCanvas.draw_text_utf8 to render the title centered above
        // the plot area.
        // ====================================================================
        def draw_title(D2DCanvas* c, Graph* g, byte* title, DWORD color) -> void
        {
            int title_len = strlen(title),
                center_x  = g.x + g.width / 2 - (title_len * 4),
                title_y   = g.y - 20;
            if (title_y < 0) { title_y = 2; };
            c.draw_text_utf8(title, center_x, title_y, title_len * 9, 18, color, 0.0);
        };

        // ====================================================================
        // draw_x_label  (D2DCanvas* overload)
        // ====================================================================
        def draw_x_label(D2DCanvas* c, Graph* g, byte* xlabel, DWORD color) -> void
        {
            int label_len = strlen(xlabel),
                center_x  = g.x + g.width / 2 - (label_len * 4),
                label_y   = g.y + g.height;
            c.draw_text_utf8(xlabel, center_x, label_y, label_len * 9, 18, color, 0.0);
        };

        // ====================================================================
        // draw_y_label  (D2DCanvas* overload)
        // ====================================================================
        def draw_y_label(D2DCanvas* c, Graph* g, byte* xlabel, DWORD color) -> void
        {
            int label_len = strlen(xlabel),
                label_x   = g.x - (label_len * 8) - 8;
            if (label_x < 0) { label_x = 2; };
            int label_y = g.y + g.height / 2 - 8;
            c.draw_text_utf8(xlabel, label_x, label_y, label_len * 9, 18, color, 0.0);
        };

        // ====================================================================
        // draw_data_point_label  (D2DCanvas* overload)
        // ====================================================================
        def draw_data_point_label(D2DCanvas* c, Graph* g, float data_x, float data_y, byte* xlabel, int label_len, DWORD text_color) -> void
        {
            int px = data_to_screen_x(g, data_x),
                py = data_to_screen_y(g, data_y);

            c.set_pen(text_color, 1);
            c.line(px - 3, py,     px + 3, py);
            c.line(px,     py - 3, px,     py + 3);

            c.draw_text_utf8(xlabel, px + 5, py - 14, label_len * 9, 18, text_color, 0.0);
        };

    };  // namespace graphing
};      // namespace standard

#endif;
