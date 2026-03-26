///
 spectrum_analyzer.fx
 Real-time spectrum analyzer with WASAPI loopback capture.
 Captures system audio output and displays the frequency spectrum.
 - Worker thread: reads ring buffer, applies Hann window, runs FFT, dB scale
 - Main thread: drains WASAPI into ring safely, uploads texture, renders
 - R key toggles bars / waveform mode
///

#import "standard.fx", "math.fx", "windows.fx", "opengl.fx", "threading.fx", "fourier.fx", "wasapi.fx";

using standard::system::windows,
      standard::math,
      standard::math::fourier,
      standard::threading,
      standard::atomic;

// ============================================================================
// CONSTANTS
// ============================================================================

// FFT size - power of two.  1024 gives 512 displayable bins.
#def FFT_SIZE  1024;

// Positive frequency bins displayed (FFT_SIZE / 2)
#def DISP_BINS  512;

// Audio ring buffer size - must be power of two and > FFT_SIZE
#def RING_SIZE 4096;

// Hann window table size matches FFT_SIZE
#def WIN_SIZE  1024;

const int WIN_W = 1024,
          WIN_H = 512;

const int DISP_BARS = 0,
          DISP_WAVE = 1;

const int PHASE_FFT  = 0,
          PHASE_EXIT = 1;

// dB display range.
// WASAPI shared-mode float samples peak at [-1,1]; after FFT mag_scale=2/1024
// a full-scale tone lands around -54 dB.
#def DB_FLOOR  -80.0;
#def DB_RANGE   80.0;

// ============================================================================
// GLOBAL STATE
// ============================================================================

global float[WIN_SIZE] g_hann;

// Audio ring buffer - main writes, worker reads
heap float* g_ring       = (float*)0;
global int  g_ring_write = 0,
            g_ring_read  = 0;

// Magnitude double buffer
heap float* g_mag_front  = (float*)0,
            g_mag_back   = (float*)0;

// FFT complex work buffer
heap Complex* g_fft_buf = (Complex*)0;

// Smoothed magnitudes and GL upload buffer
heap float* g_mag_smooth = (float*)0,
            g_mag_tex    = (float*)0;

// WASAPI capture context
WasapiCapture g_wasapi;

global int g_disp_mode = 0;
global int cur_w       = WIN_W,
           cur_h       = WIN_H;

// ============================================================================
// THREADING
// ============================================================================

struct FFTSlice
{
    int      phase;
    float*   out_mag;
    float*   hann;
    float*   ring;
    int*     ring_read;
    Complex* fft_buf;
};

FFTSlice  g_fft_slice;
Thread    g_fft_thread;
Semaphore g_work_sem,
          g_done_sem;

// ============================================================================
// HANN WINDOW
// ============================================================================

def init_hann() -> void
{
    float two_pi_over_n = 2.0 * standard::math::PIF / (float)(WIN_SIZE - 1);
    for (int i = 0; i < WIN_SIZE; i++)
    {
        g_hann[i] = 0.5 * (1.0 - standard::math::cos(two_pi_over_n * (float)i));
    };
    return;
};

// ============================================================================
// FFT WORKER
// Reads FFT_SIZE samples from the ring buffer, applies Hann window,
// runs in-place FFT, writes dB-normalized magnitudes to out_mag.
// ============================================================================

def fft_worker(void* arg) -> void*
{
    FFTSlice* sl;
    float     mag_scale,
              sample,
              lin,
              db,
              norm;
    int       i,
              read_idx;

    sl        = (FFTSlice*)arg;
    mag_scale = 2.0 / (float)FFT_SIZE;

    while (true)
    {
        semaphore_wait(@g_work_sem);
        load_fence();

        if (sl.phase == PHASE_EXIT) { return (void*)0; };

        read_idx = sl.ring_read[0];

        for (i = 0; i < FFT_SIZE; i++)
        {
            sample = sl.ring[(read_idx + i) & (RING_SIZE - 1)];
            sl.fft_buf[i].re = (double)(sample * sl.hann[i]);
            sl.fft_buf[i].im = 0.0;
        };

        fft(sl.fft_buf, FFT_SIZE);

        for (i = 0; i < DISP_BINS; i++)
        {
            lin = (float)complex_mag(@sl.fft_buf[i]) * mag_scale;
            if (lin < 0.000001) { lin = 0.000001; };
            db   = 20.0 * standard::math::log10(lin);
            norm = (db - DB_FLOOR) / DB_RANGE;
            if (norm < 0.0) { norm = 0.0; };
            if (norm > 1.0) { norm = 1.0; };
            sl.out_mag[i] = norm;
        };

        store_fence();
        semaphore_post(@g_done_sem);
    };

    return (void*)0;
};

// ============================================================================
// RING WRITE HELPER
// Writes samples into the ring buffer safely, wrapping at RING_SIZE.
// ============================================================================

def ring_write(float* ring, int write_head, float* src, int count) -> int
{
    int first_chunk,
        second_chunk;

    first_chunk = RING_SIZE - write_head;
    if (first_chunk > count) { first_chunk = count; };
    second_chunk = count - first_chunk;

    memcpy((void*)(ring + write_head), (void*)src, (size_t)(first_chunk * 4));
    if (second_chunk > 0)
    {
        memcpy((void*)ring, (void*)(src + first_chunk), (size_t)(second_chunk * 4));
    };

    return (write_head + count) & (RING_SIZE - 1);
};

// ============================================================================
// WINDOW PROCEDURE
// ============================================================================

def SpectrumWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) -> LRESULT
{
    if (msg == WM_CLOSE)      { DestroyWindow(hwnd); return 0; };
    if (msg == WM_DESTROY)    { PostQuitMessage(0);  return 0; };
    if (msg == WM_ERASEBKGND) { return 1; };

    if (msg == WM_PAINT)
    {
        PAINTSTRUCT ps;
        BeginPaint(hwnd, @ps);
        EndPaint(hwnd, @ps);
        return 0;
    };

    if (msg == WM_KEYDOWN)
    {
        if (wParam == 0x52)
        {
            if (g_disp_mode == DISP_BARS) { g_disp_mode = DISP_WAVE; }
            else                          { g_disp_mode = DISP_BARS; };
            return 0;
        };
        return 0;
    };

    return DefWindowProcA(hwnd, msg, wParam, lParam);
};

// ============================================================================
// SHADER SOURCES
// ============================================================================

byte[] VERT_SRC = "#version 120
void main() {
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_Position    = gl_Vertex;
}
\0";

byte[] FRAG_SRC = "#version 120
uniform sampler2D u_mag;
uniform int       u_mode;
uniform float     u_width;
uniform float     u_height;

void main() {
    vec2  uv  = gl_TexCoord[0].xy;
    float bx  = uv.x;
    float by  = uv.y;

    // Bin 427 = 20kHz at 48kHz sample rate (427/512 * 24000 = 19980Hz).
    // Scale bx so the right screen edge samples exactly bin 427, not bin 511.
    float audible_uv = 427.0 / 512.0;
    float sample_x = (1.0 - log(1.0 + (1.0 - bx) * 511.0) / log(512.0)) * audible_uv;

    float mag = texture2D(u_mag, vec2(sample_x, 0.5)).r;

    float lit;
    if (u_mode == 0) {
        // Bars mode: fill from bottom
        float r   = clamp(mag * 2.0,       0.0, 1.0);
        float g   = clamp(2.0 - mag * 2.0, 0.0, 1.0);
        float glow = exp(-abs(by - mag) * 50.0) * mag * 0.4;
        lit = by < mag ? 1.0 : 0.0;
        vec3 col = vec3(r, g, 0.0) * lit + vec3(r, g, 0.0) * glow;
        gl_FragColor = vec4(col, clamp(lit + glow, 0.0, 1.0));
    } else {
        // Waveform mode: centered, anti-staircased line.
        // Sample prev and next bins, compute distance to the line segment
        // between them so steep slopes don't leave gaps.
        float bin_step = audible_uv / u_width;
        float mag_prev = texture2D(u_mag, vec2(sample_x - bin_step, 0.5)).r;
        float mag_next = texture2D(u_mag, vec2(sample_x + bin_step, 0.5)).r;

        // Shift line to vertical center. mag for quiet content ~0.65, center is 0.5.
        float cy      = mag      - 0.15;
        float cy_prev = mag_prev - 0.15;
        float cy_next = mag_next - 0.15;

        // Distance from this pixel to the line segment prev->next (in pixel space)
        float ax = -1.0,  ay = cy_prev * u_height;
        float bxp =  1.0, byp = cy_next * u_height;
        float px  =  0.0, py  = by      * u_height;
        vec2 ab = vec2(bxp - ax, byp - ay);
        vec2 ap = vec2(px  - ax, py  - ay);
        float t = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0);
        float dist_px = length(ap - t * ab);

        lit = dist_px < 1.5 ? 1.0 : 0.0;
        float glow = exp(-dist_px * 0.2) * 0.6;
        vec3 col = vec3(0.0, 1.0, 0.0) * lit + vec3(0.0, 1.0, 0.0) * glow;
        gl_FragColor = vec4(col, clamp(lit + glow, 0.0, 1.0));
    }
}
\0";

// ============================================================================
// EXTRA EXTENSION POINTER
// ============================================================================

def{}* glUniform1f_fp(int, float) -> void;

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    HINSTANCE hInstance;
    HWND      hwnd;
    HDC       hdc;
    MSG       msg;
    bool      running;
    int       tex_mag,
              vert_sh,
              frag_sh,
              prog,
              u_mag,
              u_mode,
              u_width,
              u_height,
              i,
              samples_read;
    size_t    mag_bytes,
              fft_bytes,
              ring_bytes;
    float     decay,
              raw,
              cur,
              v;
    float*    tmp_ptr;
    // Temp heap buffer for WASAPI drain - avoids passing a ring-wrapped pointer
    heap float* drain_buf = (float*)0;
    RECT      client_rect;

    init_hann();

    mag_bytes  = (size_t)(DISP_BINS * 4);
    fft_bytes  = (size_t)(FFT_SIZE * (sizeof(Complex) / 8));
    ring_bytes = (size_t)(RING_SIZE * 4);

    g_ring       = (float*)fmalloc(ring_bytes);
    g_mag_front  = (float*)fmalloc(mag_bytes);
    g_mag_back   = (float*)fmalloc(mag_bytes);
    g_mag_smooth = (float*)fmalloc(mag_bytes);
    g_mag_tex    = (float*)fmalloc(mag_bytes);
    g_fft_buf    = (Complex*)fmalloc(fft_bytes);
    drain_buf    = (float*)fmalloc(ring_bytes);
    defer ffree((u64)g_ring);
    defer ffree((u64)g_mag_front);
    defer ffree((u64)g_mag_back);
    defer ffree((u64)g_mag_smooth);
    defer ffree((u64)g_mag_tex);
    defer ffree((u64)g_fft_buf);
    defer ffree((u64)drain_buf);

    // Open WASAPI loopback - non-fatal if it fails
    wasapi_open(@g_wasapi);

    // Launch FFT worker
    semaphore_init(@g_work_sem, 0);
    semaphore_init(@g_done_sem, 0);

    g_fft_slice.phase     = PHASE_FFT;
    g_fft_slice.out_mag   = g_mag_back;
    g_fft_slice.hann      = @g_hann[0];
    g_fft_slice.ring      = g_ring;
    g_fft_slice.ring_read = @g_ring_read;
    g_fft_slice.fft_buf   = g_fft_buf;

    thread_create_stack((void*)@fft_worker, (void*)@g_fft_slice, @g_fft_thread, (size_t)67108864);

    // Create window
    hInstance = GetModuleHandleA((LPCSTR)0);

    byte* class_name = "SpectrumAnalyzer\0",
          win_title  = "Spectrum Analyzer  [R] mode\0";

    WNDCLASSEXA wc;
    wc.cbSize        = (UINT)(sizeof(WNDCLASSEXA) / 8);
    wc.style         = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wc.lpfnWndProc   = (WNDPROC)@SpectrumWindowProc;
    wc.cbClsExtra    = 0;
    wc.cbWndExtra    = 0;
    wc.hInstance     = hInstance;
    wc.hIcon         = LoadIconA((HINSTANCE)0, (LPCSTR)32512);
    wc.hCursor       = LoadCursorA((HINSTANCE)0, (LPCSTR)32512);
    wc.hbrBackground = GetStockObject(BLACK_BRUSH);
    wc.lpszMenuName  = (LPCSTR)0;
    wc.lpszClassName = (LPCSTR)class_name;
    wc.hIconSm       = (HICON)0;

    RegisterClassExA(@wc);

    hwnd = CreateWindowExA(
        WS_EX_APPWINDOW,
        (LPCSTR)class_name,
        (LPCSTR)win_title,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        100, 100, WIN_W, WIN_H,
        (HWND)0, (HMENU)0, hInstance, STDLIB_GVP);

    hdc = GetDC(hwnd);

    GLContext gl(hdc);
    gl.load_extensions();

    glCreateShader_fp       = _glCreateShader;
    glShaderSource_fp       = _glShaderSource;
    glCompileShader_fp      = _glCompileShader;
    glCreateProgram_fp      = _glCreateProgram;
    glAttachShader_fp       = _glAttachShader;
    glLinkProgram_fp        = _glLinkProgram;
    glUseProgram_fp         = _glUseProgram;
    glGetUniformLocation_fp = _glGetUniformLocation;
    glUniform1i_fp          = _glUniform1i;
    glActiveTexture_fp      = _glActiveTexture;
    glDeleteShader_fp       = _glDeleteShader;
    glDeleteProgram_fp      = _glDeleteProgram;
    glUniform1f_fp          = _glUniform1f;

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_TEXTURE_2D);

    vert_sh = compile_shader(GL_VERTEX_SHADER,   @VERT_SRC[0]);
    frag_sh = compile_shader(GL_FRAGMENT_SHADER, @FRAG_SRC[0]);
    prog    = link_program(vert_sh, frag_sh);

    u_mag    = glGetUniformLocation_fp(prog, "u_mag\0");
    u_mode   = glGetUniformLocation_fp(prog, "u_mode\0");
    u_width  = glGetUniformLocation_fp(prog, "u_width\0");
    u_height = glGetUniformLocation_fp(prog, "u_height\0");

    tex_mag = 0;
    glGenTextures(1, @tex_mag);
    glBindTexture(GL_TEXTURE_2D, tex_mag);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, (i32)GL_LUMINANCE, DISP_BINS, 1, 0,
                 (i32)GL_LUMINANCE, (i32)GL_FLOAT, (void*)g_mag_tex);

    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    // Prime the ring and kick first FFT
    g_ring_write = FFT_SIZE;
    semaphore_post(@g_work_sem);

    decay   = 0.75;
    running = true;

    while (running)
    {
        while (PeekMessageA(@msg, (HWND)0, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT) { running = false; };
            TranslateMessage(@msg);
            DispatchMessageA(@msg);
        };

        if (!running) { break; };

        // Drain WASAPI loopback into ring buffer
        if (g_wasapi.ready)
        {
            samples_read = (int)wasapi_read_samples(@g_wasapi, drain_buf, (u32)(RING_SIZE / 2));

            // wasapi_read_samples sets ready=false on AUDCLNT_E_DEVICE_INVALIDATED.
            // Close the dead session and immediately try to reopen on the new default device.
            if (!g_wasapi.ready)
            {
                wasapi_close(@g_wasapi);
                wasapi_open(@g_wasapi);
            }
            else if (samples_read > 0)
            {
                store_fence();
                g_ring_write = ring_write(g_ring, g_ring_write, drain_buf, samples_read);
            };
        };

        // Collect finished FFT
        semaphore_wait(@g_done_sem);
        load_fence();

        tmp_ptr     = g_mag_front;
        g_mag_front = g_mag_back;
        g_mag_back  = tmp_ptr;

        // Hop ring read head forward by FFT_SIZE
        g_ring_read = (g_ring_read + FFT_SIZE) & (RING_SIZE - 1);

        g_fft_slice.out_mag = g_mag_back;
        store_fence();
        semaphore_post(@g_work_sem);

        // Smooth and upload
        for (i = 0; i < DISP_BINS; i++)
        {
            raw = g_mag_front[i];
            cur = g_mag_smooth[i];
            if (raw > cur)
            {
                g_mag_smooth[i] = raw;
            }
            else
            {
                g_mag_smooth[i] = cur * decay + raw * (1.0 - decay);
            };
            v = g_mag_smooth[i];
            if (v > 1.0) { v = 1.0; };
            g_mag_tex[i] = v;
        };

        glBindTexture(GL_TEXTURE_2D, tex_mag);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, DISP_BINS, 1,
                        (i32)GL_LUMINANCE, (i32)GL_FLOAT, (void*)g_mag_tex);

        GetClientRect(hwnd, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };
        glViewport(0, 0, cur_w, cur_h);

        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE);

        glUseProgram_fp(prog);
        glUniform1i_fp(u_mag,  0);
        glUniform1i_fp(u_mode, g_disp_mode);
        glUniform1f_fp(u_width,  (float)cur_w);
        glUniform1f_fp(u_height, (float)cur_h);

        glActiveTexture_fp(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, tex_mag);

        glBegin(GL_QUADS);
        glTexCoord2f(0.0, 0.0); glVertex2f(-1.0, -1.0);
        glTexCoord2f(1.0, 0.0); glVertex2f( 1.0, -1.0);
        glTexCoord2f(1.0, 1.0); glVertex2f( 1.0,  1.0);
        glTexCoord2f(0.0, 1.0); glVertex2f(-1.0,  1.0);
        glEnd();

        glUseProgram_fp(0);
        glDisable(GL_BLEND);

        gl.present();
    };

    // Shutdown
    wasapi_close(@g_wasapi);

    g_fft_slice.phase = PHASE_EXIT;
    store_fence();
    semaphore_post(@g_work_sem);
    thread_join(@g_fft_thread);

    semaphore_destroy(@g_work_sem);
    semaphore_destroy(@g_done_sem);

    glDeleteShader_fp(vert_sh);
    glDeleteShader_fp(frag_sh);
    glDeleteProgram_fp(prog);
    glDeleteTextures(1, @tex_mag);
    gl.__exit();

    ReleaseDC(hwnd, hdc);
    UnregisterClassA((LPCSTR)class_name, hInstance);

    return 0;
};
