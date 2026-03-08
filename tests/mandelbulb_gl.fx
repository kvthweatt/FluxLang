#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// Mandelbulb - GPU Raymarched 3D Fractal
// Rendered entirely on the GPU via a GLSL fragment shader.
//
// Controls:
//   W / S         = zoom in / out
//   Up / Down     = increase / decrease power (morphs the bulb shape)
//   Left / Right  = spin faster / slower
// ============================================================================

const int WIN_W = 900;
const int WIN_H = 900;

const int VK_W     = 0x57;
const int VK_S     = 0x53;
const int VK_UP    = 0x26;
const int VK_DOWN  = 0x28;
const int VK_LEFT  = 0x25;
const int VK_RIGHT = 0x27;

// ============================================================================
// GLSL shader sources.
// Compatibility context: #version 120, UV passed via glTexCoord2f / gl_TexCoord[0].
// ============================================================================

// Vertex shader: pass-through, UV comes from glTexCoord2f.
byte[] VERT_SRC = "#version 120
void main() {
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_Position = gl_Vertex;
}
\0";

// Fragment shader: Mandelbulb SDF raymarcher with Phong lighting, AO, soft shadows.
byte[] FRAG_SRC = "#version 120
uniform vec2  u_res;
uniform vec3  u_eye;
uniform float u_power;
uniform float u_time;

// ---------- Mandelbulb distance estimator ----------
float de_mandelbulb(vec3 p) {
    vec3  z     = p;
    float dr    = 1.0;
    float r     = 0.0;
    float power = u_power;
    for (int i = 0; i < 12; i++) {
        r = length(z);
        if (r > 2.0) break;
        float theta = acos(clamp(z.z / r, -1.0, 1.0)) * power;
        float phi   = atan(z.y, z.x)                  * power;
        float rp    = pow(r, power);
        dr = rp * power * dr + 1.0;
        z  = rp * vec3(sin(theta)*cos(phi),
                       sin(theta)*sin(phi),
                       cos(theta)) + p;
    }
    return 0.5 * log(r) * r / dr;
}

// ---------- Raymarcher ----------
float raymarch(vec3 ro, vec3 rd, out int steps) {
    float t = 0.0;
    steps   = 0;
    for (int i = 0; i < 96; i++) {
        float d = de_mandelbulb(ro + rd * t);
        if (d < 0.0005) { steps = i; return t; }
        if (t > 5.0)    { steps = i; return -1.0; }
        t += d * 0.8;
    }
    steps = 96;
    return -1.0;
}

// ---------- Finite-difference normal ----------
vec3 calc_normal(vec3 p) {
    float e = 0.0005;
    return normalize(vec3(
        de_mandelbulb(p + vec3(e,0,0)) - de_mandelbulb(p - vec3(e,0,0)),
        de_mandelbulb(p + vec3(0,e,0)) - de_mandelbulb(p - vec3(0,e,0)),
        de_mandelbulb(p + vec3(0,0,e)) - de_mandelbulb(p - vec3(0,0,e))
    ));
}

// ---------- Ambient occlusion (step-based) ----------
float calc_ao(vec3 p, vec3 n) {
    float ao = 0.0;
    float w  = 1.0;
    for (int i = 1; i <= 5; i++) {
        float d = 0.06 * float(i);
        ao += w * (d - de_mandelbulb(p + n * d));
        w  *= 0.5;
    }
    return clamp(1.0 - 6.0 * ao, 0.0, 1.0);
}

// ---------- Soft shadow ----------
float soft_shadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
    float res = 1.0;
    float t   = mint;
    for (int i = 0; i < 24; i++) {
        float h = de_mandelbulb(ro + rd * t);
        res = min(res, k * h / t);
        t  += clamp(h, 0.01, 0.2);
        if (t > maxt) break;
    }
    return clamp(res, 0.0, 1.0);
}

void main() {
    // UV in [-1,1] from texcoord, aspect-corrected
    vec2 uv = gl_TexCoord[0].xy;
    uv.x *= u_res.x / u_res.y;

    // Camera basis from eye toward origin
    vec3 ro  = u_eye;
    vec3 fwd = normalize(-ro);
    vec3 rgt = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
    vec3 up2 = cross(rgt, fwd);
    vec3 rd  = normalize(fwd + uv.x * rgt + uv.y * up2);

    // Sky background (dark space)
    vec3 col = vec3(0.02, 0.02, 0.04);

    int steps;
    float t = raymarch(ro, rd, steps);

    if (t > 0.0) {
        vec3 p  = ro + rd * t;
        vec3 n  = calc_normal(p);

        // Two lights: key + fill
        vec3 lkey  = normalize(vec3(1.0,  1.6,  0.8));
        vec3 lfill = normalize(vec3(-0.8, -0.3, -0.5));

        float diff_key  = clamp(dot(n, lkey),  0.0, 1.0);
        float diff_fill = clamp(dot(n, lfill), 0.0, 1.0);

        float spec = pow(clamp(dot(reflect(-lkey, n), -rd), 0.0, 1.0), 32.0);

        float ao  = calc_ao(p, n);
        float sha = soft_shadow(p, lkey, 0.02, 2.0, 8.0);

        // Orbit-trap coloring: color by distance-to-axes
        float tr = min(abs(p.x), min(abs(p.y), abs(p.z)));
        tr = clamp(tr * 4.0, 0.0, 1.0);

        vec3 base_col = mix(
            vec3(0.05, 0.3,  0.9),
            vec3(0.9,  0.5,  0.05),
            tr
        );
        base_col = mix(base_col, vec3(0.9, 0.1, 0.5), clamp(length(p) - 0.5, 0.0, 1.0) * 0.5);

        col  = base_col * (diff_key * sha * 1.2 + diff_fill * 0.25 + 0.05) * ao;
        col += vec3(1.0) * spec * sha * 0.6;

        // Glow at grazing angles
        float rim = 1.0 - clamp(dot(-rd, n), 0.0, 1.0);
        col += base_col * pow(rim, 4.0) * 0.3 * ao;

        // Depth fog
        col = mix(col, vec3(0.02, 0.02, 0.04), clamp(t * 0.4, 0.0, 1.0));
    } else {
        // Step-count glow on miss (surface boundary halo)
        float glow = float(steps) / 96.0;
        col += vec3(0.1, 0.2, 0.5) * pow(glow, 6.0) * 3.0;
    }

    // Gamma correction
    col = pow(clamp(col, 0.0, 1.0), vec3(0.4545));

    gl_FragColor = vec4(col, 1.0);
}
\0";

extern def !!GetTickCount() -> DWORD;

// ============================================================================
// Global typed function pointer wrappers for the _gl* void* extension globals.
// Assigned in main() after gl.load_extensions() populates the _gl* globals.
// ============================================================================

def{}* glCreateShader_fp(int)                -> int;
def{}* glShaderSource_fp(int,int,byte**,int*)-> void;
def{}* glCompileShader_fp(int)               -> void;
def{}* glCreateProgram_fp()                  -> int;
def{}* glAttachShader_fp(int,int)            -> void;
def{}* glLinkProgram_fp(int)                 -> void;
def{}* glUseProgram_fp(int)                  -> void;
def{}* glGetUniformLocation_fp(int,byte*)    -> int;
def{}* glUniform1f_fp(int,float)             -> void;
def{}* glUniform2f_fp(int,float,float)       -> void;
def{}* glUniform3f_fp(int,float,float,float) -> void;
def{}* glDeleteShader_fp(int)                -> void;
def{}* glDeleteProgram_fp(int)               -> void;

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
    Window win("Mandelbulb - W/S: Zoom  Up/Down: Power  Left/Right: Spin speed\0",
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
    glUniform2f_fp          = _glUniform2f;
    glUniform3f_fp          = _glUniform3f;
    glDeleteShader_fp       = _glDeleteShader;
    glDeleteProgram_fp      = _glDeleteProgram;

    glDisable(GL_DEPTH_TEST);

    // Build shader program
    int vert_sh = compile_shader(GL_VERTEX_SHADER,   @VERT_SRC[0]);
    int frag_sh = compile_shader(GL_FRAGMENT_SHADER, @FRAG_SRC[0]);
    int prog    = link_program(vert_sh, frag_sh);

    // Uniform locations
    int u_res   = get_uniform(prog, "u_res\0");
    int u_eye   = get_uniform(prog, "u_eye\0");
    int u_power = get_uniform(prog, "u_power\0");
    int u_time  = get_uniform(prog, "u_time\0");

    // Camera and render state
    float cam_dist   = 2.5;
    float cam_yaw    = 0.0;
    float cam_pitch  = 0.35;
    float power      = 8.0;
    float spin_speed = 0.3;
    float elapsed    = 0.0;
    float dt;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    int cur_w, cur_h;

    WORD w_state, s_state, up_state, dn_state, lt_state, rt_state;

    while (win.process_messages())
    {
        t_now  = GetTickCount();
        dt     = (float)(t_now - t_last) / 1000.0;
        t_last = t_now;
        if (dt > 0.1) { dt = 0.1; };
        elapsed = elapsed + dt;

        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };
        glViewport(0, 0, cur_w, cur_h);

        w_state  = GetAsyncKeyState(VK_W);
        s_state  = GetAsyncKeyState(VK_S);
        up_state = GetAsyncKeyState(VK_UP);
        dn_state = GetAsyncKeyState(VK_DOWN);
        lt_state = GetAsyncKeyState(VK_LEFT);
        rt_state = GetAsyncKeyState(VK_RIGHT);

        // Zoom
        if ((w_state `& 0x8000) != 0)
        {
            cam_dist = cam_dist - dt * 1.2;
            if (cam_dist < 1.3) { cam_dist = 1.3; };
        };
        if ((s_state `& 0x8000) != 0)
        {
            cam_dist = cam_dist + dt * 1.2;
            if (cam_dist > 5.0) { cam_dist = 5.0; };
        };

        // Power (morphs the bulb shape)
        if ((up_state `& 0x8000) != 0)
        {
            power = power + dt * 1.5;
            if (power > 16.0) { power = 16.0; };
        };
        if ((dn_state `& 0x8000) != 0)
        {
            power = power - dt * 1.5;
            if (power < 2.0) { power = 2.0; };
        };

        // Spin speed
        if ((rt_state `& 0x8000) != 0)
        {
            spin_speed = spin_speed + dt * 0.5;
            if (spin_speed > 2.0) { spin_speed = 2.0; };
        };
        if ((lt_state `& 0x8000) != 0)
        {
            spin_speed = spin_speed - dt * 0.5;
            if (spin_speed < 0.0) { spin_speed = 0.0; };
        };

        // Auto-rotate yaw
        cam_yaw = cam_yaw + dt * spin_speed;

        // Compute eye position on a sphere around origin
        float ex = cam_dist * cos(cam_pitch) * sin(cam_yaw);
        float ey = cam_dist * sin(cam_pitch);
        float ez = cam_dist * cos(cam_pitch) * cos(cam_yaw);

        glClearColor(0.02, 0.02, 0.04, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);

        glUseProgram_fp(prog);
        glUniform2f_fp(u_res,   (float)cur_w, (float)cur_h);
        glUniform3f_fp(u_eye,   ex, ey, ez);
        glUniform1f_fp(u_power, power);
        glUniform1f_fp(u_time,  elapsed);

        // Fullscreen triangle via immediate mode - no VBO or VAO needed.
        // UV passed through glTexCoord2f, read in shader as gl_TexCoord[0].
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
