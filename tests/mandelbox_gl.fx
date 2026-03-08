#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx";

using standard::system::windows;
using standard::math;

// ============================================================================
// Mandelbox - GPU Raymarched 3D Fractal
//
// Controls:
//   W / S           = zoom in / out
//   A / D           = orbit left / right
//   Up / Down       = orbit up / down
//   J / L           = scale parameter down / up
//   I / K           = fold limit down / up
//   Left / Right    = spin faster / slower
// ============================================================================

const int WIN_W = 900;
const int WIN_H = 900;

const int VK_W     = 0x57;
const int VK_S     = 0x53;
const int VK_A     = 0x41;
const int VK_D     = 0x44;
const int VK_J     = 0x4A;
const int VK_L     = 0x4C;
const int VK_I     = 0x49;
const int VK_K     = 0x4B;
const int VK_UP    = 0x26;
const int VK_DOWN  = 0x28;
const int VK_LEFT  = 0x25;
const int VK_RIGHT = 0x27;

byte[] VERT_SRC = "#version 120
void main() {
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_Position    = gl_Vertex;
}
\0";

byte[] FRAG_SRC = "#version 120
uniform vec2  u_res;
uniform vec3  u_eye;
uniform vec3  u_target;
uniform float u_scale;
uniform float u_fold;
uniform float u_time;

float de_mandelbox(vec3 pos) {
    float scale   = u_scale;
    float fold    = u_fold;
    float minR2   = 0.25;
    float fixedR2 = 1.0;

    vec3  z  = pos;
    float dz = 1.0;

    for (int i = 0; i < 16; i++) {
        // Box fold
        z = clamp(z, -fold, fold) * 2.0 - z;

        // Sphere fold
        float r2 = dot(z, z);
        if (r2 < minR2) {
            z  *= fixedR2 / minR2;
            dz *= fixedR2 / minR2;
        } else if (r2 < fixedR2) {
            z  *= fixedR2 / r2;
            dz *= fixedR2 / r2;
        }

        z  = z * scale + pos;
        dz = dz * abs(scale) + 1.0;
    }

    return length(z) / abs(dz);
}

float raymarch(vec3 ro, vec3 rd, out int steps) {
    float t  = 0.0;
    float dt = 0.0;
    steps    = 0;
    for (int i = 0; i < 256; i++) {
        dt = de_mandelbox(ro + rd * t);
        if (dt < 0.0001) { steps = i; return t; }
        if (t > 30.0)    { steps = i; return -1.0; }
        t += dt * 0.65;
    }
    steps = 256;
    return -1.0;
}

vec3 calc_normal(vec3 p) {
    float e = 0.0005;
    return normalize(vec3(
        de_mandelbox(p + vec3(e,0,0)) - de_mandelbox(p - vec3(e,0,0)),
        de_mandelbox(p + vec3(0,e,0)) - de_mandelbox(p - vec3(0,e,0)),
        de_mandelbox(p + vec3(0,0,e)) - de_mandelbox(p - vec3(0,0,e))
    ));
}

float calc_ao(vec3 p, vec3 n) {
    float ao = 0.0;
    float w  = 1.0;
    for (int i = 1; i <= 5; i++) {
        float d = 0.08 * float(i);
        ao += w * (d - de_mandelbox(p + n * d));
        w  *= 0.5;
    }
    return clamp(1.0 - 5.0 * ao, 0.0, 1.0);
}

float soft_shadow(vec3 ro, vec3 rd, float mint, float maxt, float k) {
    float res = 1.0;
    float t   = mint;
    for (int i = 0; i < 32; i++) {
        float h = de_mandelbox(ro + rd * t);
        res = min(res, k * h / t);
        t  += clamp(h, 0.005, 0.3);
        if (t > maxt) break;
    }
    return clamp(res, 0.0, 1.0);
}

vec3 orbit_color(vec3 pos) {
    float scale   = u_scale;
    float fold    = u_fold;
    float minR2   = 0.25;
    float fixedR2 = 1.0;

    vec3  z = pos;
    float trap_r  = 1e10;
    float trap_x  = 1e10;
    float trap_xz = 1e10;

    for (int i = 0; i < 16; i++) {
        z = clamp(z, -fold, fold) * 2.0 - z;

        float r2 = dot(z, z);
        if (r2 < minR2) {
            z *= fixedR2 / minR2;
        } else if (r2 < fixedR2) {
            z *= fixedR2 / r2;
        }

        z = z * scale + pos;

        trap_r  = min(trap_r,  dot(z, z));
        trap_x  = min(trap_x,  abs(z.x));
        trap_xz = min(trap_xz, length(z.xz));
    }

    float r = clamp(1.0 - trap_r  * 0.15, 0.0, 1.0);
    float g = clamp(trap_x  * 0.5,        0.0, 1.0);
    float b = clamp(1.0 - trap_xz * 0.4,  0.0, 1.0);
    return vec3(r, g, b);
}

void main() {
    vec2 uv = gl_TexCoord[0].xy;
    uv.x *= u_res.x / u_res.y;

    vec3 ro  = u_eye;
    vec3 fwd = normalize(u_target - ro);
    vec3 rgt = normalize(cross(fwd, vec3(0.0, 1.0, 0.0)));
    vec3 up2 = cross(rgt, fwd);
    vec3 rd  = normalize(fwd * 1.5 + uv.x * rgt + uv.y * up2);

    float bg_grad = clamp(uv.y * 0.3 + 0.2, 0.0, 1.0);
    vec3 col = mix(vec3(0.01, 0.01, 0.03), vec3(0.03, 0.02, 0.06), bg_grad);

    int steps;
    float t = raymarch(ro, rd, steps);

    if (t > 0.0) {
        vec3 p = ro + rd * t;
        vec3 n = calc_normal(p);

        vec3 base_col = orbit_color(p);

        vec3 lkey  = normalize(vec3(0.8, 1.2, 0.6));
        vec3 lfill = normalize(vec3(-0.5, 0.3, -0.8));
        vec3 lback = normalize(vec3(0.0, -1.0, 0.3));

        float diff_key  = clamp(dot(n, lkey),  0.0, 1.0);
        float diff_fill = clamp(dot(n, lfill), 0.0, 1.0) * 0.3;
        float diff_back = clamp(dot(n, lback), 0.0, 1.0) * 0.15;

        float spec = pow(clamp(dot(reflect(-lkey, n), -rd), 0.0, 1.0), 48.0);

        float ao  = calc_ao(p, n);
        float sha = soft_shadow(p, lkey, 0.02, 8.0, 12.0);

        col  = base_col * (diff_key * sha + diff_fill + diff_back + 0.04) * ao;
        col += vec3(0.9, 0.95, 1.0) * spec * sha * 0.5;

        float rim = 1.0 - clamp(dot(-rd, n), 0.0, 1.0);
        col += vec3(0.1, 0.3, 0.8) * pow(rim, 5.0) * 0.4 * ao;

        float fog = clamp(t / 20.0, 0.0, 1.0);
        col = mix(col, vec3(0.01, 0.01, 0.03), fog * fog);
    } else {
        float glow = float(steps) / 256.0;
        col += vec3(0.05, 0.1, 0.4) * pow(glow, 8.0) * 2.0;
    }

    float vig = 1.0 - dot(gl_TexCoord[0].xy * 0.5, gl_TexCoord[0].xy * 0.5);
    col *= clamp(vig * 1.2, 0.0, 1.0);

    col = pow(clamp(col, 0.0, 1.0), vec3(0.4545));

    gl_FragColor = vec4(col, 1.0);
}
\0";

extern def !!GetTickCount() -> DWORD;

def{}* glCreateShader_fp(int)                -> int,
       glShaderSource_fp(int,int,byte**,int*)-> void,
       glCompileShader_fp(int)               -> void,
       glCreateProgram_fp()                  -> int,
       glAttachShader_fp(int,int)            -> void,
       glLinkProgram_fp(int)                 -> void,
       glUseProgram_fp(int)                  -> void,
       glGetUniformLocation_fp(int,byte*)    -> int,
       glUniform1f_fp(int,float)             -> void,
       glUniform2f_fp(int,float,float)       -> void,
       glUniform3f_fp(int,float,float,float) -> void,
       glDeleteShader_fp(int)                -> void,
       glDeleteProgram_fp(int)               -> void;

def compile_shader(int shader_type, byte* src) -> int
{
    int shader = glCreateShader_fp(shader_type);
    byte[1]* src_arr = [src];
    int[1]   len_arr = [-1];
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
    Window win("Mandelbox - W/S:Zoom  A/D:Orbit  J/L:Scale  I/K:Fold  Arrows:Tilt/Spin\0",
               100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);
    gl.load_extensions();

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

    int vert_sh = compile_shader(GL_VERTEX_SHADER,   @VERT_SRC[0]),
        frag_sh = compile_shader(GL_FRAGMENT_SHADER, @FRAG_SRC[0]),
        prog    = link_program(vert_sh, frag_sh),

        u_res    = get_uniform(prog, "u_res\0"),
        u_eye    = get_uniform(prog, "u_eye\0"),
        u_target = get_uniform(prog, "u_target\0"),
        u_scale  = get_uniform(prog, "u_scale\0"),
        u_fold   = get_uniform(prog, "u_fold\0"),
        u_time   = get_uniform(prog, "u_time\0");

    float cam_dist   = 14.0,
          cam_yaw    = 0.4,
          cam_pitch  = 0.3,
          spin_speed = 0.1,

          mb_scale = -2.0,
          mb_fold  = 1.0,

          elapsed = 0.0,
          dt,
          ex, ey, ez;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    int cur_w, cur_h;

    WORD w_state, s_state, a_state, d_state,
         j_state, l_state, i_state, k_state,
         up_state, dn_state, lt_state, rt_state;

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
        a_state  = GetAsyncKeyState(VK_A);
        d_state  = GetAsyncKeyState(VK_D);
        j_state  = GetAsyncKeyState(VK_J);
        l_state  = GetAsyncKeyState(VK_L);
        i_state  = GetAsyncKeyState(VK_I);
        k_state  = GetAsyncKeyState(VK_K);
        up_state = GetAsyncKeyState(VK_UP);
        dn_state = GetAsyncKeyState(VK_DOWN);
        lt_state = GetAsyncKeyState(VK_LEFT);
        rt_state = GetAsyncKeyState(VK_RIGHT);

        if ((w_state `& 0x8000) != 0)
        {
            cam_dist = cam_dist - dt * 3.0;
            if (cam_dist < 0.05) { cam_dist = 0.05; };
        };
        if ((s_state `& 0x8000) != 0)
        {
            cam_dist = cam_dist + dt * 3.0;
            if (cam_dist > 30.0) { cam_dist = 30.0; };
        };

        if ((a_state `& 0x8000) != 0) { cam_yaw = cam_yaw - dt * 1.0; };
        if ((d_state `& 0x8000) != 0) { cam_yaw = cam_yaw + dt * 1.0; };

        if ((up_state `& 0x8000) != 0)
        {
            cam_pitch = cam_pitch + dt * 0.8;
            if (cam_pitch > 1.4) { cam_pitch = 1.4; };
        };
        if ((dn_state `& 0x8000) != 0)
        {
            cam_pitch = cam_pitch - dt * 0.8;
            if (cam_pitch < -1.4) { cam_pitch = -1.4; };
        };

        if ((rt_state `& 0x8000) != 0)
        {
            spin_speed = spin_speed + dt * 0.3;
            if (spin_speed > 1.5) { spin_speed = 1.5; };
        };
        if ((lt_state `& 0x8000) != 0)
        {
            spin_speed = spin_speed - dt * 0.3;
            if (spin_speed < 0.0) { spin_speed = 0.0; };
        };

        if ((l_state `& 0x8000) != 0)
        {
            mb_scale = mb_scale - dt * 0.3;
            if (mb_scale < -3.0) { mb_scale = -3.0; };
        };
        if ((j_state `& 0x8000) != 0)
        {
            mb_scale = mb_scale + dt * 0.3;
            if (mb_scale > -1.2) { mb_scale = -1.2; };
        };

        if ((i_state `& 0x8000) != 0)
        {
            mb_fold = mb_fold + dt * 0.3;
            if (mb_fold > 2.0) { mb_fold = 2.0; };
        };
        if ((k_state `& 0x8000) != 0)
        {
            mb_fold = mb_fold - dt * 0.3;
            if (mb_fold < 0.3) { mb_fold = 0.3; };
        };

        cam_yaw = cam_yaw + dt * spin_speed;

        ex = cam_dist * cos(cam_pitch) * sin(cam_yaw);
        ey = cam_dist * sin(cam_pitch);
        ez = cam_dist * cos(cam_pitch) * cos(cam_yaw);

        glClearColor(0.01, 0.01, 0.03, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);

        glUseProgram_fp(prog);
        glUniform2f_fp(u_res,    (float)cur_w, (float)cur_h);
        glUniform3f_fp(u_eye,    ex, ey, ez);
        glUniform3f_fp(u_target, 0.0, 0.0, 0.0);
        glUniform1f_fp(u_scale,  mb_scale);
        glUniform1f_fp(u_fold,   mb_fold);
        glUniform1f_fp(u_time,   elapsed);

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
