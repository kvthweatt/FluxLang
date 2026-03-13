#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;

// ============================================================================
// Mandelbrot Set - Auto Zoom Demo
// Slowly zooms into a deep interesting coordinate, fully rendered every frame
// ============================================================================

const int WIN_W    = 900,
          WIN_H    = 900,
          MAX_ITER = 1024;

// Zoom target: Misiurewicz point - boundary spiral, never collapses to black interior
const double TARGET_X = -1.23706216702671,
             TARGET_Y = -0.09294502320475;

// Compute Mandelbrot iteration count using native double precision
def mandelbrot(double x0, double y0, int max_iter) -> int
{
    double x, y, xx, yy, xtemp, cx, cy, q;
    int iter;

    // Cardioid and period-2 bulb check
    // Points inside either region are guaranteed to never escape - skip iteration entirely
    cx = x0 - 0.25;
    cy = y0;
    q  = cx * cx + cy * cy;
    // Main cardioid: q*(q + cx) < cy*cy*0.25
    if (q * (q + cx) < cy * cy * 0.25) { return max_iter; };
    // Period-2 bulb: (x+1)^2 + y^2 < 1/16
    cx = x0 + 1.0;
    if (cx * cx + cy * cy < 0.0625) { return max_iter; };

    x    = 0.0;
    y    = 0.0;
    iter = 0;

    while (iter < max_iter)
    {
        xx = x * x;
        yy = y * y;
        if (xx + yy > 4.0) { return iter; };
        xtemp = xx - yy + x0;
        y     = 2.0 * x * y + y0;
        x     = xtemp;
        iter++;
    };

    return iter;
};

// Map iteration count to an RGB color using a smooth palette
def iter_to_color(int iter, int max_iter, double* r, double* g, double* b) -> void
{
    double t, s;

    if (iter == max_iter)
    {
        // Inside the set - black
        *r = 0.0;
        *g = 0.0;
        *b = 0.0;
        return;
    };

    // t in [0,1] across one 256-step cycle - always positive
    t = (double)(iter % 256) / 255.0;

    // 5-stop palette for deep contrast:
    // 0.00 - 0.20: black -> deep purple
    // 0.20 - 0.45: deep purple -> electric blue
    // 0.45 - 0.65: electric blue -> bright teal/cyan
    // 0.65 - 0.85: bright teal -> deep gold
    // 0.85 - 1.00: deep gold -> crimson red
    if (t < 0.2)
    {
        s = t / 0.2;
        *r = s * 0.45;
        *g = 0.0;
        *b = s * 0.6;
    }
    elif (t < 0.45)
    {
        s = (t - 0.2) / 0.25;
        *r = 0.45 - s * 0.45;
        *g = s * 0.05;
        *b = 0.6 + s * 0.4;
    }
    elif (t < 0.65)
    {
        s = (t - 0.45) / 0.2;
        *r = s * 0.05;
        *g = s * 0.9;
        *b = 1.0;
    }
    elif (t < 0.85)
    {
        s = (t - 0.65) / 0.2;
        *r = 0.05 + s * 0.85;
        *g = 0.9 - s * 0.5;
        *b = 1.0 - s * 1.0;
    }
    else
    {
        s = (t - 0.85) / 0.15;
        *r = 0.9 + s * 0.1;
        *g = 0.4 - s * 0.4;
        *b = 0.0;
    };

    return;
};

extern def !!GetTickCount() -> DWORD;

def main() -> int
{
    Window win("Mandelbrot Set - Auto Zoom\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    // Use identity matrix - emit vertices directly in NDC [-1, 1]
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);

    // View parameters as native doubles
    double cx, cy, zoom, half_zoom, x_min, y_min,
           x_range, y_range, fx, fy;

    cx   = TARGET_X;
    cy   = TARGET_Y;
    zoom = 3.0;

    // Zoom speed: fraction of zoom shrunk per second
    double zoom_speed;
    zoom_speed = 0.18;

    // NDC quad corners and color
    double px0, px1, py0, py1,
           r, gv, b;

    int dyn_max_iter,
        cols, rows, row, col, iter,
        cur_w, cur_h;

    float dt;
    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;

    while (win.process_messages())
    {
        // Delta time
        t_now  = GetTickCount();
        dt     = (float)(t_now - t_last) / 1000.0;
        t_last = t_now;
        // Clamp dt so a stall doesn't cause a huge jump
        if (dt > 0.1) { dt = 0.1; };

        // Query actual client area each frame so resize/maximize works
        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };

        // Update viewport to match current window size
        glViewport(0, 0, cur_w, cur_h);

        // Auto zoom in continuously; reset to start when fully deep
        zoom = zoom * (1.0 - zoom_speed * (double)dt);
        if (zoom < 0.0000000001) { zoom = 3.0; };

        // Scale max iterations with zoom depth for detail at depth
        if (zoom > 1.0)
        {
            dyn_max_iter = 128;
        }
        elif (zoom > 0.01)
        {
            dyn_max_iter = 256;
        }
        elif (zoom > 0.0001)
        {
            dyn_max_iter = 512;
        }
        else
        {
            dyn_max_iter = MAX_ITER;
        };

        // Always fully rendered - tile size 1, every pixel
        cols = cur_w;
        rows = cur_h;

        // Clear
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        // Render Mandelbrot as colored quads - all complex math in double precision
        half_zoom = zoom * 0.5;
        x_min   = cx - half_zoom;
        y_min   = cy - zoom * (double)cur_h / (double)cur_w * 0.5;
        x_range = zoom;
        y_range = zoom * (double)cur_h / (double)cur_w;

        // Batch all quads into a single draw call - one glBegin/glEnd for the whole frame
        glBegin(GL_QUADS);
        row = 0;
        while (row < rows)
        {
            col = 0;
            while (col < cols)
            {
                fx = x_min + x_range * ((double)col + 0.5) / (double)cols;
                fy = y_min + y_range * ((double)row + 0.5) / (double)rows;

                iter = mandelbrot(fx, fy, dyn_max_iter);

                iter_to_color(iter, dyn_max_iter, @r, @gv, @b);

                glColor3f((float)r, (float)gv, (float)b);

                // Map pixel to NDC [-1, 1]
                // Y is inverted: row 0 = top of screen = NDC +1
                px0 =  -1.0 + 2.0 * (double)col       / (double)cur_w;
                py0 =   1.0 - 2.0 * (double)row       / (double)cur_h;
                px1 =  -1.0 + 2.0 * (double)(col + 1) / (double)cur_w;
                py1 =   1.0 - 2.0 * (double)(row + 1) / (double)cur_h;

                glVertex2f((float)px0, (float)py0);
                glVertex2f((float)px1, (float)py0);
                glVertex2f((float)px1, (float)py1);
                glVertex2f((float)px0, (float)py1);

                col++;
            };
            row++;
        };

        print("CX: \0"); print(cx); print();
        print("CY: \0"); print(cy); print();
        glEnd();

        gl.present();
    };

    gl.__exit();
    win.__exit();

    return 0;
};
