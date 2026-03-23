#import "standard.fx", "math.fx", "windows.fx", "opengl.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;

// ============================================================================
// Mandelbrot Set - OpenGL Viewer
// W = zoom in, S = zoom out
// ============================================================================

const int WIN_W        = 900,
          WIN_H        = 900,
          MAX_ITER     = 1024,
          TILE_STILL   = 1,   // Tile size when stationary
          TILE_MOVING  = 4,   // Tile size while a key is held - faster pan/zoom

// Virtual key codes
          VK_W    = 0x57,
          VK_S    = 0x53,
          VK_A    = 0x41,
          VK_D    = 0x44,
          VK_UP   = 0x26,
          VK_DOWN = 0x28;

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
    Window win( "Mandelbrot Set - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0", 100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);

    // Use identity matrix - emit vertices directly in NDC [-1, 1]
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_DEPTH_TEST);

    // View parameters as native doubles
    double cx, cy, zoom, half_zoom, x_min, y_min,
           x_range, y_range, fx, fy,
           r, gv, b;

    cx   = -0.5;
    cy   =  0.0;
    zoom =  3.0;

    // Scalar control parameters stay float
    float zoom_speed, pan_speed, dt;
    zoom_speed = 1.5;
    pan_speed  = 0.6;

    // NDC quad corners and color
    float px0, px1, py0, py1;

    // TILE and max_iter adapt based on whether any key is held:
    // moving = coarser tiles + fewer iterations for responsive panning/zooming
    int tile, dyn_max_iter,
        cols, rows, row, col, iter,
        cur_w, cur_h;
    bool moving;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    WORD w_state, s_state, a_state, d_state, up_state, dn_state;

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

        w_state  = GetAsyncKeyState(VK_W);
        s_state  = GetAsyncKeyState(VK_S);
        a_state  = GetAsyncKeyState(VK_A);
        d_state  = GetAsyncKeyState(VK_D);
        up_state = GetAsyncKeyState(VK_UP);
        dn_state = GetAsyncKeyState(VK_DOWN);

        // Detect if any movement key is held for adaptive quality
        moving = ((w_state  `& 0x8000) != 0) |
                 ((s_state  `& 0x8000) != 0) |
                 ((a_state  `& 0x8000) != 0) |
                 ((d_state  `& 0x8000) != 0) |
                 ((up_state `& 0x8000) != 0) |
                 ((dn_state `& 0x8000) != 0);

        // Coarser tile + fewer iters while navigating, full quality when still
        tile = moving ? TILE_MOVING : TILE_STILL;

        cols = cur_w / tile;
        rows = cur_h / tile;
        if (cols < 1) { cols = 1; };
        if (rows < 1) { rows = 1; };

        // Scale max iterations with zoom depth: shallow zoom needs far fewer iters.
        // zoom ranges from ~8.0 (fully out) to ~0.0000000001 (deep in).
        // At zoom 8 cap at 128; at zoom 1 cap at 256; deep zoom uses full MAX_ITER.
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
        // While moving, halve the iteration budget on top of tile coarsening
        if (moving) { dyn_max_iter = dyn_max_iter >> 1; };

        if ((w_state `& 0x8000) != 0)
        {
            zoom = zoom * (1.0 - (double)zoom_speed * (double)dt);
            if (zoom < 0.0000000001) { zoom = 0.0000000001; };
        };

        if ((s_state `& 0x8000) != 0)
        {
            zoom = zoom * (1.0 + (double)zoom_speed * (double)dt);
            if (zoom > 8.0) { zoom = 8.0; };
        };

        if ((a_state `& 0x8000) != 0)
        {
            cx = cx - zoom * (double)pan_speed * (double)dt;
        };

        if ((d_state `& 0x8000) != 0)
        {
            cx = cx + zoom * (double)pan_speed * (double)dt;
        };

        if ((up_state `& 0x8000) != 0)
        {
            cy = cy - zoom * (double)pan_speed * (double)dt;
        };

        if ((dn_state `& 0x8000) != 0)
        {
            cy = cy + zoom * (double)pan_speed * (double)dt;
        };

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

                // Map tile to NDC [-1, 1] using live window dimensions
                // Y is inverted: row 0 = top of screen = NDC +1
                px0 =  -1.0 + 2.0 * (float)(col * tile) / (float)cur_w;
                py0 =   1.0 - 2.0 * (float)(row * tile) / (float)cur_h;
                px1 =  -1.0 + 2.0 * (float)(col * tile + tile) / (float)cur_w;
                py1 =   1.0 - 2.0 * (float)(row * tile + tile) / (float)cur_h;

                glVertex2f(px0, py0);
                glVertex2f(px1, py0);
                glVertex2f(px1, py1);
                glVertex2f(px0, py1);

                col++;
            };
            row++;
        };

        glEnd();

        gl.present();
    };

    gl.__exit();
    win.__exit();

    return 0;
};
