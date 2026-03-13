#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;

// ============================================================================
// Mandelbrot Set - OpenGL Shader Viewer
// W = zoom in, S = zoom out, A/D = pan X, Up/Down = pan Y
// ============================================================================

const int WIN_W    = 900,
          WIN_H    = 900,
          MAX_ITER = 1024;

const int VK_W    = 0x57,
          VK_S    = 0x53,
          VK_A    = 0x41,
          VK_D    = 0x44,
          VK_UP   = 0x26,
          VK_DOWN = 0x28;

// ============================================================================
// GLSL shader sources
// ============================================================================

// Vertex shader: pass-through, UV comes from glTexCoord2f.
byte[] VERT_SRC = "#version 120
void main() {
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_Position = gl_Vertex;
}
\0";

// Fragment shader: full Mandelbrot per pixel on the GPU.
// Palette matches the 5-stop CPU version from the original example.
byte[] FRAG_SRC = "#version 120
uniform float u_cx;
uniform float u_cy;
uniform float u_zoom;
uniform float u_max_iter;
uniform float u_win_w;
uniform float u_win_h;

vec3 palette(int iter, int max_iter) {
    if (iter == max_iter) return vec3(0.0);
    float t = float(iter % 96) / 95.0;
    float s;
    if (t < 0.2) {
        s = t / 0.2;
        return vec3(s * 0.45, 0.0, s * 0.6);
    } else if (t < 0.45) {
        s = (t - 0.2) / 0.25;
        return vec3(0.45 - s*0.45, s*0.05, 0.6 + s*0.4);
    } else if (t < 0.65) {
        s = (t - 0.45) / 0.2;
        return vec3(s*0.05, s*0.9, 1.0);
    } else if (t < 0.85) {
        s = (t - 0.65) / 0.2;
        return vec3(0.05 + s*0.85, 0.9 - s*0.5, 1.0 - s);
    } else {
        s = (t - 0.85) / 0.15;
        return vec3(0.9 + s*0.1, 0.4 - s*0.4, 0.0);
    }
}

void main() {
    vec2 uv = gl_TexCoord[0].xy;

    int   max_iter = int(u_max_iter);
    float half_zoom = u_zoom * 0.5;
    float y_range   = u_zoom * u_win_h / u_win_w;
    float x0 = u_cx - half_zoom + u_zoom  * (uv.x * 0.5 + 0.5);
    float y0 = u_cy - y_range * 0.5 + y_range * (uv.y * 0.5 + 0.5);

    // Cardioid / period-2 bulb fast reject
    float cx = x0 - 0.25, cy = y0;
    float q  = cx*cx + cy*cy;
    int   iter = max_iter;
    if (q*(q+cx) >= cy*cy*0.25) {
        cx = x0 + 1.0;
        if (cx*cx + cy*cy >= 0.0625) {
            float x = 0.0, y = 0.0, xx, yy, xt;
            iter = 0;
            while (iter < max_iter) {
                xx = x*x; yy = y*y;
                if (xx + yy > 4.0) break;
                xt = xx - yy + x0;
                y  = 2.0*x*y + y0;
                x  = xt;
                iter++;
            }
        }
    }

    gl_FragColor = vec4(palette(iter, max_iter), 1.0);
}
\0";

extern def !!GetTickCount() -> DWORD;

// ============================================================================
// Global typed function pointer wrappers for the _gl* void* extension globals.
// Assigned in main() after gl.load_extensions() populates the _gl* globals.
// ============================================================================

def{}* glCreateShader_fp(int)                 -> int;
def{}* glShaderSource_fp(int,int,byte**,int*) -> void;
def{}* glCompileShader_fp(int)                -> void;
def{}* glCreateProgram_fp()                   -> int;
def{}* glAttachShader_fp(int,int)             -> void;
def{}* glLinkProgram_fp(int)                  -> void;
def{}* glUseProgram_fp(int)                   -> void;
def{}* glGetUniformLocation_fp(int,byte*)     -> int;
def{}* glUniform1f_fp(int,float)              -> void;
def{}* glDeleteShader_fp(int)                 -> void;
def{}* glDeleteProgram_fp(int)                -> void;

// ============================================================================
// Shader helpers
// ============================================================================

def compile_shader(int shader_type, byte* src) -> int
{
    int shader = glCreateShader_fp(shader_type);
    byte[1]* src_arr = [src];
    int[1]   len_arr = [-1]; // null-terminated
    glShaderSource_fp(shader, 1, @src_arr[0], @len_arr[0]);
    glCompileShader_fp(shader);
    return shader;
};

def link_program(int vert, int frag) -> int
{
    int prog = glCreateProgram_fp();
    glAttachShader_fp(prog, vert);
    glAttachShader_fp(prog, frag);
    glLinkProgram_fp(prog);
    return prog;
};

def get_uniform(int prog, byte* name) -> int
{
    return glGetUniformLocation_fp(prog, name);
};

def main() -> int
{
    Window win("Mandelbrot Set (Shader) - W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0",
               100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);
    gl.load_extensions();

    // Bind function pointers now that extensions are loaded
    glCreateShader_fp       = _glCreateShader;
    glShaderSource_fp       = _glShaderSource;
    glCompileShader_fp      = _glCompileShader;
    glCreateProgram_fp      = _glCreateProgram;
    glAttachShader_fp       = _glAttachShader;
    glLinkProgram_fp        = _glLinkProgram;
    glUseProgram_fp         = _glUseProgram;
    glGetUniformLocation_fp = _glGetUniformLocation;
    glUniform1f_fp          = _glUniform1f;
    glDeleteShader_fp       = _glDeleteShader;
    glDeleteProgram_fp      = _glDeleteProgram;

    glDisable(GL_DEPTH_TEST);

    // Build shader program
    int vert_sh = compile_shader(GL_VERTEX_SHADER,   @VERT_SRC[0]);
    int frag_sh = compile_shader(GL_FRAGMENT_SHADER, @FRAG_SRC[0]);
    int prog    = link_program(vert_sh, frag_sh);

    // Uniform locations
    int u_cx       = get_uniform(prog, "u_cx\0");
    int u_cy       = get_uniform(prog, "u_cy\0");
    int u_zoom     = get_uniform(prog, "u_zoom\0");
    int u_max_iter = get_uniform(prog, "u_max_iter\0");
    int u_win_w    = get_uniform(prog, "u_win_w\0");
    int u_win_h    = get_uniform(prog, "u_win_h\0");

    // View state (kept as double for accurate pan/zoom math)
    double cx, cy, zoom;
    cx   = -0.5;
    cy   =  0.0;
    zoom =  3.0;

    float zoom_speed, pan_speed, dt;
    zoom_speed = 1.5;
    pan_speed  = 0.6;

    int dyn_max_iter, cur_w, cur_h;
    bool moving;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    WORD w_state, s_state, a_state, d_state, up_state, dn_state;

    while (win.process_messages())
    {
        t_now  = GetTickCount();
        dt     = (float)(t_now - t_last) / 1000.0;
        t_last = t_now;
        if (dt > 0.1) { dt = 0.1; };

        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };
        glViewport(0, 0, cur_w, cur_h);

        w_state  = GetAsyncKeyState(VK_W);
        s_state  = GetAsyncKeyState(VK_S);
        a_state  = GetAsyncKeyState(VK_A);
        d_state  = GetAsyncKeyState(VK_D);
        up_state = GetAsyncKeyState(VK_UP);
        dn_state = GetAsyncKeyState(VK_DOWN);

        moving = ((w_state  `& 0x8000) != 0) |
                 ((s_state  `& 0x8000) != 0) |
                 ((a_state  `& 0x8000) != 0) |
                 ((d_state  `& 0x8000) != 0) |
                 ((up_state `& 0x8000) != 0) |
                 ((dn_state `& 0x8000) != 0);

        // Adaptive iteration budget
        if (zoom > 1.0)      { dyn_max_iter = 128; }
        elif (zoom > 0.01)   { dyn_max_iter = 256; }
        elif (zoom > 0.0001) { dyn_max_iter = 512; }
        else                 { dyn_max_iter = MAX_ITER; };
        if (moving) { dyn_max_iter = dyn_max_iter >> 1; };

        // Zoom
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

        // Pan
        if ((a_state `& 0x8000) != 0) { cx = cx - zoom * (double)pan_speed * (double)dt; };
        if ((d_state `& 0x8000) != 0) { cx = cx + zoom * (double)pan_speed * (double)dt; };
        if ((up_state `& 0x8000) != 0) { cy = cy - zoom * (double)pan_speed * (double)dt; };
        if ((dn_state `& 0x8000) != 0) { cy = cy + zoom * (double)pan_speed * (double)dt; };

        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);

        glUseProgram_fp(prog);
        glUniform1f_fp(u_cx,       (float)cx);
        glUniform1f_fp(u_cy,       (float)cy);
        glUniform1f_fp(u_zoom,     (float)zoom);
        glUniform1f_fp(u_max_iter, (float)dyn_max_iter);
        glUniform1f_fp(u_win_w,    (float)cur_w);
        glUniform1f_fp(u_win_h,    (float)cur_h);

        // Fullscreen triangle via immediate mode - UV passed through glTexCoord2f.
        glBegin(GL_TRIANGLES);
            glTexCoord2f(-1.0, -1.0);  glVertex2f(-1.0, -1.0);
            glTexCoord2f( 3.0, -1.0);  glVertex2f( 3.0, -1.0);
            glTexCoord2f(-1.0,  3.0);  glVertex2f(-1.0,  3.0);
        glEnd();

        gl.present();
    };

    glDeleteShader_fp(vert_sh);
    glDeleteShader_fp(frag_sh);
    glDeleteProgram_fp(prog);

    gl.__exit();
    win.__exit();

    return 0;
};
