// Author: Karac V. Thweatt
//
// rt_demo.fx - Raytracing Library Demo (Multithreaded)
//
// Renders a 3D scene using raytracing.fx progressively.
// One batch of tiles per frame — one tile per thread — so all cores
// stay saturated while the window remains live between batches.
//
// Controls:
//   1   - Classic scene (diffuse, metal, glass spheres)
//   2   - Metal showcase (gold, silver, copper + checkerboard grid)
//   3   - Emissive light sources scene
//   ESC - Quit
//

#import "standard.fx", "windows.fx", "opengl.fx", "threading.fx", "raytracing.fx";

using standard::system::windows;
using standard::math;
using standard::memory::allocators::stdheap;
using standard::threading;
using raytracer;

extern def !!glPixelStorei(int, int) -> void;

#def GL_UNPACK_ROW_LENGTH 0x0CF2;

// ============================================================================
// CONSTANTS
// ============================================================================

#def IMG_W      800;
#def IMG_H      450;
#def SAMPLES    64;
#def DEPTH      8;
#def MAX_THREADS 64;

// ============================================================================
// WORK SLICE — one per thread, describes one tile to render
// ============================================================================

struct RTWorkSlice
{
    RTScene*  scene;
    RTCamera* cam;
    u32*      pixels;
    i32       tile_x,
              tile_y,
              tw, th,
              img_w, img_h,
              samples, depth;
    u64       seed;
};

RTWorkSlice[64] g_rt_slices;

// ============================================================================
// WORKER — called on each thread, renders one tile
// ============================================================================

def rt_worker(void* arg) -> void*
{
    RTWorkSlice* sl;
    PCG32        rng;

    sl = (RTWorkSlice*)arg;
    pcg32_seed(@rng, sl.seed, (u64)(sl.tile_x + 1));

    rt_render_tile(sl.scene, sl.cam, sl.pixels,
                   sl.tile_x, sl.tile_y,
                   sl.tw,     sl.th,
                   sl.img_w,  sl.img_h,
                   sl.samples, sl.depth,
                   @rng);

    return (void*)0;
};

// ============================================================================
// SCENE BUILDERS
// ============================================================================

def build_scene_classic(RTScene* s, RTCamera* cam) -> void
{
    rt_scene_add_plane(s, vec3(0.0, 1.0, 0.0), 0.0,
                       mat_lambertian(vec3(0.5, 0.5, 0.5)));

    rt_scene_add_sphere(s, vec3(-1.2, 0.5, -2.5), 0.5,
                        mat_lambertian(vec3(0.8, 0.2, 0.1)));

    rt_scene_add_sphere(s, vec3(0.0, 0.5, -2.0), 0.5,
                        mat_dielectric(1.5));
    rt_scene_add_sphere(s, vec3(0.0, 0.5, -2.0), -0.45,
                        mat_dielectric(1.5));

    rt_scene_add_sphere(s, vec3(1.2, 0.5, -2.5), 0.5,
                        mat_metal(vec3(0.8, 0.6, 0.2), 0.05));

    rt_scene_add_sphere(s, vec3(-2.2, 0.25, -4.0), 0.25,
                        mat_lambertian(vec3(0.2, 0.7, 0.3)));
    rt_scene_add_sphere(s, vec3(-0.6, 0.25, -4.2), 0.25,
                        mat_lambertian(vec3(0.9, 0.8, 0.1)));
    rt_scene_add_sphere(s, vec3( 0.8, 0.25, -4.0), 0.25,
                        mat_metal(vec3(0.7, 0.7, 0.9), 0.3));
    rt_scene_add_sphere(s, vec3( 2.1, 0.25, -3.8), 0.25,
                        mat_lambertian(vec3(0.3, 0.3, 0.9)));
    rt_scene_add_sphere(s, vec3(-1.5, 0.25, -5.5), 0.25,
                        mat_lambertian(vec3(0.9, 0.4, 0.7)));
    rt_scene_add_sphere(s, vec3( 1.5, 0.25, -5.5), 0.25,
                        mat_metal(vec3(0.9, 0.5, 0.1), 0.15));

    rt_scene_add_sphere(s, vec3(0.0, 1.0, -7.0), 1.0,
                        mat_lambertian(vec3(0.4, 0.4, 0.8)));

    rt_camera_init(cam,
                   vec3(0.0, 1.2, 1.5),
                   vec3(0.0, 0.4, -2.0),
                   vec3(0.0, 1.0, 0.0),
                   50.0,
                   (float)IMG_W / (float)IMG_H,
                   0.04,
                   3.6);
};

def build_scene_metals(RTScene* s, RTCamera* cam) -> void
{
    i32   gx, gz;
    float fx, fz;

    rt_scene_add_plane(s, vec3(0.0, 1.0, 0.0), 0.0,
                       mat_lambertian(vec3(0.6, 0.55, 0.5)));

    rt_scene_add_sphere(s, vec3(-2.0, 0.7, -3.0), 0.7,
                        mat_metal(vec3(1.0, 0.78, 0.34), 0.0));
    rt_scene_add_sphere(s, vec3(0.0, 0.7, -3.5), 0.7,
                        mat_metal(vec3(0.9, 0.9, 0.95), 0.4));
    rt_scene_add_sphere(s, vec3(2.0, 0.7, -3.0), 0.7,
                        mat_metal(vec3(0.95, 0.64, 0.54), 0.15));

    rt_scene_add_sphere(s, vec3(-1.0, 0.3, -1.8), 0.3,
                        mat_dielectric(1.5));
    rt_scene_add_sphere(s, vec3(-1.0, 0.3, -1.8), -0.27,
                        mat_dielectric(1.5));
    rt_scene_add_sphere(s, vec3( 1.0, 0.3, -1.8), 0.3,
                        mat_dielectric(1.8));

    gx = -4;
    while (gx <= 4)
    {
        gz = -8;
        while (gz <= -1)
        {
            fx = (float)gx * 0.9;
            fz = (float)gz * 0.9;
            if ((gx + gz) & 1)
            {
                rt_scene_add_sphere(s, vec3(fx, 0.12, fz), 0.12,
                                    mat_metal(vec3(0.8, 0.8, 0.85), 0.05));
            }
            else
            {
                rt_scene_add_sphere(s, vec3(fx, 0.12, fz), 0.12,
                                    mat_lambertian(vec3(0.2, 0.2, 0.25)));
            };
            gz++;
        };
        gx++;
    };

    rt_camera_init(cam,
                   vec3(0.0, 2.0, 2.5),
                   vec3(0.0, 0.5, -2.5),
                   vec3(0.0, 1.0, 0.0),
                   55.0,
                   (float)IMG_W / (float)IMG_H,
                   0.05,
                   5.0);
};

def build_scene_lights(RTScene* s, RTCamera* cam) -> void
{
    rt_scene_add_plane(s, vec3(0.0, 1.0, 0.0), 0.0,
                       mat_lambertian(vec3(0.08, 0.08, 0.08)));

    rt_scene_add_sphere(s, vec3(0.0, 0.0, -8.0), 4.5,
                        mat_lambertian(vec3(0.15, 0.15, 0.2)));

    rt_scene_add_sphere(s, vec3(-1.8, 1.2, -3.0), 0.4,
                        mat_emissive(vec3(1.0, 0.4, 0.1), 8.0));
    rt_scene_add_sphere(s, vec3( 0.0, 1.5, -2.5), 0.4,
                        mat_emissive(vec3(0.4, 0.7, 1.0), 8.0));
    rt_scene_add_sphere(s, vec3( 1.8, 1.2, -3.0), 0.4,
                        mat_emissive(vec3(0.5, 1.0, 0.3), 8.0));

    rt_scene_add_sphere(s, vec3(0.0, 6.0, -2.5), 2.5,
                        mat_emissive(vec3(1.0, 0.95, 0.9), 1.5));

    rt_scene_add_sphere(s, vec3(-1.0, 0.35, -1.5), 0.35,
                        mat_lambertian(vec3(0.85, 0.85, 0.85)));
    rt_scene_add_sphere(s, vec3( 1.0, 0.35, -1.5), 0.35,
                        mat_metal(vec3(0.9, 0.9, 0.9), 0.02));
    rt_scene_add_sphere(s, vec3( 0.0, 0.35, -1.2), 0.35,
                        mat_dielectric(1.5));

    rt_scene_add_sphere(s, vec3(-2.4, 0.15, -2.5), 0.15,
                        mat_metal(vec3(0.95, 0.95, 0.95), 0.0));
    rt_scene_add_sphere(s, vec3( 0.0, 0.15, -2.0), 0.15,
                        mat_metal(vec3(0.95, 0.95, 0.95), 0.0));
    rt_scene_add_sphere(s, vec3( 2.4, 0.15, -2.5), 0.15,
                        mat_metal(vec3(0.95, 0.95, 0.95), 0.0));

    rt_camera_init(cam,
                   vec3(0.0, 1.5, 2.0),
                   vec3(0.0, 0.8, -2.0),
                   vec3(0.0, 1.0, 0.0),
                   60.0,
                   (float)IMG_W / (float)IMG_H,
                   0.0,
                   1.0);
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    // ---- Query core count ----
    SYSTEM_INFO_PARTIAL sysinfo;
    GetSystemInfo((void*)@sysinfo);
    i32 num_threads;
    num_threads = (i32)sysinfo.dwNumberOfProcessors;
    if (num_threads < 1)            { num_threads = 1; };
    if (num_threads > MAX_THREADS)  { num_threads = MAX_THREADS; };

    // ---- Pixel buffer ----
    size_t   buf_bytes;
    u32*     pixels;
    buf_bytes = (size_t)(IMG_W * IMG_H * (i32)(sizeof(u32) / 8));
    pixels    = (u32*)fmalloc(buf_bytes);

    // ---- Window and GL context ----
    Window win("Flux Raytracer - 1/2/3 change scene  ESC quit\0",
               IMG_W, IMG_H, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    GLContext gl(win.device_context);
    gl.load_extensions();

    // ---- Render texture ----
    int tex_id;
    tex_id = 0;
    glGenTextures(1, @tex_id);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA,
                 IMG_W, IMG_H, 0,
                 0x80E1, GL_UNSIGNED_BYTE, (void*)pixels);

    // ---- Scene ----
    RTScene  scene;
    RTCamera cam;
    rt_scene_init(@scene, 64);
    build_scene_classic(@scene, @cam);
    bvh_build(@scene);

    // ---- Thread pool ----
    Thread[64] threads;

    // ---- Progressive tile state ----
    // The pending tile list: we track the next tile to dispatch as (tile_x, tile_y).
    // Each frame we launch up to num_threads tiles in parallel, join, upload, present.
    i32  tile_x, tile_y;
    bool rendering;
    tile_x    = 0;
    tile_y    = 0;
    rendering = true;

    // ---- Frame loop vars ----
    RECT    client_rect;
    int     cur_w, cur_h;
    Matrix4 ortho;
    bool    key1_prev, key2_prev, key3_prev,
            key1_now,  key2_now,  key3_now;
    i32     new_scene, current_scene;
    i32     t, tw, th, batch;
    i32     bx, by, btw, bth;
    u64     tile_seed;

    key1_prev     = false;
    key2_prev     = false;
    key3_prev     = false;
    current_scene = 1;
    new_scene     = 0;

    while (win.process_messages())
    {
        if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0) { PostQuitMessage(0); };

        // ---- Scene switch ----
        key1_now = (GetAsyncKeyState(0x31) & 0x8000) != 0;
        key2_now = (GetAsyncKeyState(0x32) & 0x8000) != 0;
        key3_now = (GetAsyncKeyState(0x33) & 0x8000) != 0;

        new_scene = 0;
        if (key1_now & !key1_prev) { new_scene = 1; };
        if (key2_now & !key2_prev) { new_scene = 2; };
        if (key3_now & !key3_prev) { new_scene = 3; };

        key1_prev = key1_now;
        key2_prev = key2_now;
        key3_prev = key3_now;

        if (new_scene != 0 & new_scene != current_scene)
        {
            rt_scene_free(@scene);
            rt_scene_init(@scene, 64);

            switch (new_scene)
            {
                case (1) { build_scene_classic(@scene, @cam); }
                case (2) { build_scene_metals(@scene, @cam); }
                case (3) { build_scene_lights(@scene, @cam); }
                default  { build_scene_classic(@scene, @cam); };
            };

            bvh_build(@scene);
            current_scene = new_scene;

            memset((void*)pixels, 0, buf_bytes);
            glBindTexture(GL_TEXTURE_2D, tex_id);
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, IMG_W, IMG_H,
                            0x80E1, GL_UNSIGNED_BYTE, (void*)pixels);

            tile_x    = 0;
            tile_y    = 0;
            rendering = true;
        };

        // ---- Dispatch a batch of up to num_threads tiles in parallel ----
        if (rendering)
        {
            batch = 0;
            t     = 0;
            while (t < num_threads & rendering)
            {
                tw = IMG_W - tile_x;
                th = IMG_H - tile_y;
                if (tw > RT_TILE_SIZE) { tw = RT_TILE_SIZE; };
                if (th > RT_TILE_SIZE) { th = RT_TILE_SIZE; };

                tile_seed = (u64)(tile_y * 65537 + tile_x * 131);

                g_rt_slices[t].scene   = @scene;
                g_rt_slices[t].cam     = @cam;
                g_rt_slices[t].pixels  = pixels;
                g_rt_slices[t].tile_x  = tile_x;
                g_rt_slices[t].tile_y  = tile_y;
                g_rt_slices[t].tw      = tw;
                g_rt_slices[t].th      = th;
                g_rt_slices[t].img_w   = IMG_W;
                g_rt_slices[t].img_h   = IMG_H;
                g_rt_slices[t].samples = SAMPLES;
                g_rt_slices[t].depth   = DEPTH;
                g_rt_slices[t].seed    = tile_seed;

                thread_create(@rt_worker, (void*)@g_rt_slices[t], @threads[t]);
                batch++;

                // Advance tile cursor
                tile_x += RT_TILE_SIZE;
                if (tile_x >= IMG_W)
                {
                    tile_x  = 0;
                    tile_y += RT_TILE_SIZE;
                    if (tile_y >= IMG_H)
                    {
                        rendering = false;
                    };
                };

                t++;
            };

            // Join all launched threads and upload their tiles
            t = 0;
            while (t < batch)
            {
                thread_join(@threads[t]);
                t++;
            };

            // Upload each completed tile
            t = 0;
            while (t < batch)
            {
                bx  = g_rt_slices[t].tile_x;
                by  = g_rt_slices[t].tile_y;
                btw = g_rt_slices[t].tw;
                bth = g_rt_slices[t].th;

                glBindTexture(GL_TEXTURE_2D, tex_id);
                glPixelStorei(GL_UNPACK_ROW_LENGTH, IMG_W);
                glTexSubImage2D(GL_TEXTURE_2D, 0,
                                bx, by, btw, bth,
                                0x80E1, GL_UNSIGNED_BYTE,
                                (void*)(pixels + by * IMG_W + bx));
                glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
                t++;
            };
        };

        // ---- Blit texture to screen ----
        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_h == 0) { cur_h = 1; };

        glViewport(0, 0, cur_w, cur_h);
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        mat4_ortho(0.0, 1.0, 0.0, 1.0, -1.0, 1.0, @ortho);
        glLoadMatrixf(@ortho.m[0]);

        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();

        glEnable(GL_TEXTURE_2D);
        glBindTexture(GL_TEXTURE_2D, tex_id);
        glColor3f(1.0, 1.0, 1.0);

        glBegin(GL_QUADS);
            glTexCoord2f(0.0, 1.0);  glVertex2f(0.0, 0.0);
            glTexCoord2f(1.0, 1.0);  glVertex2f(1.0, 0.0);
            glTexCoord2f(1.0, 0.0);  glVertex2f(1.0, 1.0);
            glTexCoord2f(0.0, 0.0);  glVertex2f(0.0, 1.0);
        glEnd();

        glDisable(GL_TEXTURE_2D);

        gl.present();
        Sleep(1);
    };

    rt_scene_free(@scene);
    ffree((u64)pixels);
    gl.__exit();
    win.__exit();

    return 0;
};
