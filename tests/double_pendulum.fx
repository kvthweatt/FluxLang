// Double Pendulum Simulation
// 50 simultaneous double pendulums with rainbow gradient colors
// Uses RK4 integration for accurate chaotic dynamics
// Rendered via OpenGL fixed-function immediate mode on Win32

#import <standard.fx>;
#import <math.fx>;
#import <windows.fx>;
#import <opengl.fx>;

using standard::system::windows,
      standard::math,
      OpenGL;

// ============================================================================
// CONSTANTS
// ============================================================================

#def NUM_PENDULUMS  50;
#def TRAIL_LEN      300;
#def WIN_W          1000;
#def WIN_H          900;

const float G          = 9.81,
            L1         = 0.38,     // arm 1 length  (world units)
            L2         = 0.32,     // arm 2 length
            M1         = 0.5,      // bob 1 mass
            M2         = 0.5,      // bob 2 mass
            DT         = 0.00003,    // timestep  (~60 fps physics)
            BASE_THETA1 = 2.1,     // starting angle arm 1  (radians)
            BASE_THETA2 = 1.8,     // starting angle arm 2
            DELTA       = 0.00001; // tiny per-pendulum offset to reveal chaos

// ============================================================================
// STRUCTS
// ============================================================================

struct PendulumState
{
    float theta1,   // angle of arm 1 from vertical
          omega1,   // angular velocity arm 1
          theta2,   // angle of arm 2 from vertical
          omega2;   // angular velocity arm 2
};

struct TrailPoint
{
    float x, y;     // tip-of-arm-2 position in world space
};

// ============================================================================
// GLOBAL SIM DATA  (heap so 50 * TRAIL_LEN * 2 floats fits fine)
// ============================================================================

heap PendulumState[NUM_PENDULUMS] g_states;
heap TrailPoint[NUM_PENDULUMS][TRAIL_LEN] g_trail;
heap int[NUM_PENDULUMS] g_trail_head,   // ring-buffer write head
                        g_trail_count;  // how many points are valid

// ============================================================================
// DOUBLE PENDULUM EQUATIONS OF MOTION
// Returns d(omega1)/dt and d(omega2)/dt given current state.
// Standard Lagrangian derivation.
// ============================================================================

def domega1(float t1, float w1, float t2, float w2) -> float
{
    float num1 = (0.0 - G) * (2.0 * M1 + M2) * sin(t1);
    float num2 = (0.0 - M2) * G * sin(t1 - 2.0 * t2);
    float num3 = (0.0 - 2.0) * sin(t1 - t2) * M2;
    float num4 = w2 * w2 * L2 + w1 * w1 * L1 * cos(t1 - t2);
    float denom = L1 * (2.0 * M1 + M2 - M2 * cos(2.0 * t1 - 2.0 * t2));
    return (num1 + num2 + num3 * num4) / denom;
};

def domega2(float t1, float w1, float t2, float w2) -> float
{
    float num1 = 2.0 * sin(t1 - t2);
    float num2 = w1 * w1 * L1 * (M1 + M2);
    float num3 = G * (M1 + M2) * cos(t1);
    float num4 = w2 * w2 * L2 * M2 * cos(t1 - t2);
    float denom = L2 * (2.0 * M1 + M2 - M2 * cos(2.0 * t1 - 2.0 * t2));
    return (num1 * (num2 + num3 + num4)) / denom;
};

// ============================================================================
// RK4 STEP - advances one pendulum state by dt
// ============================================================================

def rk4_step(PendulumState* s, float dt) -> void
{
    float t1 = s.theta1, w1 = s.omega1,
          t2 = s.theta2, w2 = s.omega2;

    // k1
    float k1_t1 = w1;
    float k1_w1 = domega1(t1, w1, t2, w2);
    float k1_t2 = w2;
    float k1_w2 = domega2(t1, w1, t2, w2);

    // k2
    float h = dt * 0.5;
    float k2_t1 = w1 + h * k1_w1;
    float k2_w1 = domega1(t1 + h * k1_t1, w1 + h * k1_w1,
                           t2 + h * k1_t2, w2 + h * k1_w2);
    float k2_t2 = w2 + h * k1_w2;
    float k2_w2 = domega2(t1 + h * k1_t1, w1 + h * k1_w1,
                           t2 + h * k1_t2, w2 + h * k1_w2);

    // k3
    float k3_t1 = w1 + h * k2_w1;
    float k3_w1 = domega1(t1 + h * k2_t1, w1 + h * k2_w1,
                           t2 + h * k2_t2, w2 + h * k2_w2);
    float k3_t2 = w2 + h * k2_w2;
    float k3_w2 = domega2(t1 + h * k2_t1, w1 + h * k2_w1,
                           t2 + h * k2_t2, w2 + h * k2_w2);

    // k4
    float k4_t1 = w1 + dt * k3_w1;
    float k4_w1 = domega1(t1 + dt * k3_t1, w1 + dt * k3_w1,
                           t2 + dt * k3_t2, w2 + dt * k3_w2);
    float k4_t2 = w2 + dt * k3_w2;
    float k4_w2 = domega2(t1 + dt * k3_t1, w1 + dt * k3_w1,
                           t2 + dt * k3_t2, w2 + dt * k3_w2);

    float sixth = dt / 6.0;
    s.theta1 = t1 + sixth * (k1_t1 + 2.0 * k2_t1 + 2.0 * k3_t1 + k4_t1);
    s.omega1 = w1 + sixth * (k1_w1 + 2.0 * k2_w1 + 2.0 * k3_w1 + k4_w1);
    s.theta2 = t2 + sixth * (k1_t2 + 2.0 * k2_t2 + 2.0 * k3_t2 + k4_t2);
    s.omega2 = w2 + sixth * (k1_w2 + 2.0 * k2_w2 + 2.0 * k3_w2 + k4_w2);
    return;
};

// ============================================================================
// HSV -> RGB  (h in [0,1], s=1, v=1)  returns r,g,b via out-params
// ============================================================================

def hsv_to_rgb(float h, float* r, float* g, float* b) -> void
{
    float hh = h * 6.0;
    int   i  = (int)hh;
    float f  = hh - float(i);
    float q  = 1.0 - f;

    switch (i)
    {
        case (0) { *r = 1.0; *g = f;   *b = 0.0; }
        case (1) { *r = q;   *g = 1.0; *b = 0.0; }
        case (2) { *r = 0.0; *g = 1.0; *b = f;   }
        case (3) { *r = 0.0; *g = q;   *b = 1.0; }
        case (4) { *r = f;   *g = 0.0; *b = 1.0; }
        default  { *r = 1.0; *g = 0.0; *b = q;   };
    };
    return;
};

// ============================================================================
// SIMULATION STEP  - advance all pendulums and record trail
// ============================================================================

def sim_step() -> void
{
    float x1, x2, y1, y2;
    int head;

    for (int i; i < NUM_PENDULUMS; i++)
    {
        rk4_step(@g_states[i], DT);

        // Compute tip of arm 2 in world coords (pivot at origin)
        x1 = L1 * sin(g_states[i].theta1);
        y1 = (0.0 - L1) * cos(g_states[i].theta1);
        x2 = x1 + L2 * sin(g_states[i].theta2);
        y2 = y1 + (0.0 - L2) * cos(g_states[i].theta2);

        head = g_trail_head[i];
        g_trail[i][head].x = x2;
        g_trail[i][head].y = y2;

        g_trail_head[i]  = (head + 1) % TRAIL_LEN;
        if (g_trail_count[i] < TRAIL_LEN) { g_trail_count[i] += 1; };
    };
    return;
};

// ============================================================================
// DRAW ONE PENDULUM + ITS TRAIL
// ============================================================================

def draw_pendulum(int idx, float r, float g, float b) -> void
{
    PendulumState* s = @g_states[idx];

    float x1 = L1 * sin(s.theta1),
          y1 = (0.0 - L1) * cos(s.theta1),
          x2 = x1 + L2 * sin(s.theta2),
          y2 = y1 + (0.0 - L2) * cos(s.theta2),
          alpha;

    // --- Draw trail ---
    int   count = g_trail_count[idx],
          head  = g_trail_head[idx],
          idx2;

    glBegin(GL_LINE_STRIP);
    for (int k; k < count; k++)
    {
        // oldest point first: (head - count + k) mod TRAIL_LEN
        idx2 = (head - count + k + TRAIL_LEN * 2) % TRAIL_LEN;
        alpha = float(k) / float(count);   // fade old end toward 0
        glColor4f(r, g, b, alpha * 0.75);
        glVertex2f(g_trail[idx][idx2].x, g_trail[idx][idx2].y);
    };
    glEnd();

    // --- Draw rods ---
    glColor4f(r, g, b, 1.0);
    glLineWidth(1.8);
    glBegin(GL_LINES);
    glVertex2f(0.0, 0.0);
    glVertex2f(x1,  y1);
    glVertex2f(x1,  y1);
    glVertex2f(x2,  y2);
    glEnd();

    // --- Draw pivot bob (small circle via GL_TRIANGLE_FAN) ---
    float BOB_R = 0.012,
          cx = x1, cy = y1,
          a1, a2;

    glBegin(GL_TRIANGLE_FAN);
    glVertex2f(cx, cy);
    for (int s2; s2 <= 12; s2++)
    {
        a1 = float(s2) * (PIF * 2.0 / 12.0);
        glVertex2f(cx + cos(a1) * BOB_R, cy + sin(a1) * BOB_R);
    };
    glEnd();

    // --- Draw tip bob ---
    cx = x2;
    cy = y2;
    glBegin(GL_TRIANGLE_FAN);
    glVertex2f(cx, cy);
    for (int s3; s3 <= 14; s3++)
    {
        a2 = float(s3) * (PIF * 2.0 / 14.0);
        glVertex2f(cx + cos(a2) * BOB_R * 1.3, cy + sin(a2) * BOB_R * 1.3);
    };
    glEnd();

    return;
};

// ============================================================================
// DRAW ORIGIN PIVOT MARKER
// ============================================================================

def draw_origin_pivot() -> void
{
    float R = 0.018,
          a;
    glColor4f(0.9, 0.9, 0.9, 1.0);
    glBegin(GL_TRIANGLE_FAN);
    glVertex2f(0.0, 0.0);
    for (int k; k <= 16; k++)
    {
        a = float(k) * (PIF * 2.0 / 16.0);
        glVertex2f(cos(a) * R, sin(a) * R);
    };
    glEnd();
    return;
};

// ============================================================================
// RENDER FRAME
// ============================================================================

def render_frame() -> void
{
    glClearColor(0.04, 0.04, 0.06, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);

    // Orthographic: world coords roughly -1..1 on both axes
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    float half = L1 + L2 + 0.08,
          r, g, b, hue;
    glOrtho((0.0 - half), half, (0.0 - half), half, (0.0 - 1.0), 1.0);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // Enable blending for trail fade
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_LINE_SMOOTH);

    // Draw each pendulum back-to-front (index 0 drawn first, 49 last/on top)
    for (int i; i < NUM_PENDULUMS; i++)
    {
        hue = float(i) / float(NUM_PENDULUMS);
        hsv_to_rgb(hue, @r, @g, @b);
        draw_pendulum(i, r, g, b);
    };

    draw_origin_pivot();
    return;
};

// ============================================================================
// INIT - seed all pendulum states
// ============================================================================

def init_pendulums() -> void
{
    for (int i; i < NUM_PENDULUMS; i++)
    {
        g_states[i].theta1 = BASE_THETA1 + float(i) * DELTA;
        g_states[i].omega1 = 0.0;
        g_states[i].theta2 = BASE_THETA2 + float(i) * DELTA;
        g_states[i].omega2 = 0.0;
        g_trail_head[i]    = 0;
        g_trail_count[i]   = 0;
    };
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("Double Pendulum - Chaos\0", WIN_W, WIN_H, 100, 100);
    GLContext gl(win.device_context);
    gl.load_extensions();

    init_pendulums();

    // Physics sub-steps per frame for smoother simulation
    #def SUBSTEPS 4;

    while (win.process_messages())
    {
        // Advance physics
        for (int sub; sub < SUBSTEPS; sub++)
        {
            sim_step();
        };

        render_frame();
        gl.present();
    };

    // Cleanup
    gl.__exit();
    win.__exit();

    (void)g_states;
    (void)g_trail;
    (void)g_trail_head;
    (void)g_trail_count;

    return 0;
};
