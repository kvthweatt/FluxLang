// cube_stress.fx - Hundreds of Cubes Stress-Test Scene
//
// Scene setup:
//   - One shared cube mesh instanced NUM_CUBES times.
//   - Each instance placed at a random position in a large 3D volume
//     (X in [-40,40], Y in [-15,15], Z in [-40,40]) with random scale
//     [0.4, 2.5] and random initial rotation offsets so no two look identical.
//   - Each instance gets one of four tint colors drawn from a small palette
//     so depth-sorting / overdraw errors are visually obvious.
//   - Same three-point lighting rig and brushed-metal texture as the single
//     cube demo - any shading artifact will be reproducible across the field.
//   - Sky: deep blue -> near-black horizon (unchanged).
//   - Camera starts at origin, facing -Z.  Full free-fly controls so you can
//     navigate anywhere in the cube field.
//   - Controls:
//       W / S            - fly forward / back
//       A / D            - strafe left / right
//       Arrow Up / Down  - pitch up / down
//       Arrow Left / Right - yaw left / right
//       R                - reset camera to origin
//       Q / E            - fly up / down
//
// Architecture:
//   Single shared R3DMesh, NUM_CUBES R3DMeshInst instances.
//   r3d_scene_set_insts() receives a heap-allocated pointer array.
//   Rendering identical to cube_demo.fx: raycasting.fx -> u64 buffer ->
//   OpenGL RGBA texture -> fullscreen quad.
//
// Build:
//   fxc cube_stress.fx -o cube_stress.exe
// ============================================================================

#import <standard.fx>, <math.fx>, <vectors.fx>, <matrices.fx>, <windows.fx>, <opengl.fx>, <raycasting.fx>;

using standard::io::console,
      standard::system::windows,
      standard::math,
      standard::vectors,
      raycaster;

// ============================================================================
// WINDOW / RENDER DIMENSIONS
// ============================================================================

const int WIN_W = 1024,
          WIN_H = 768;

// ============================================================================
// NUMBER OF CUBE INSTANCES
// ============================================================================

const int NUM_CUBES = 300;

// ============================================================================
// CUBE GEOMETRY BUILDER  (identical to cube_demo.fx)
// ============================================================================

def build_cube_mesh(R3DMesh* mesh) -> void
{
    r3d_mesh_init(mesh, 24, 12, 1);   // 24 verts, 12 tris, texture slot 1

    // -- +Z face (front, nz = +1) ---------------------------------------------
    mesh.verts[ 0].x = -0.5; mesh.verts[ 0].y = -0.5; mesh.verts[ 0].z =  0.5;
    mesh.verts[ 0].u =  0.0; mesh.verts[ 0].v =  0.0;

    mesh.verts[ 1].x =  0.5; mesh.verts[ 1].y = -0.5; mesh.verts[ 1].z =  0.5;
    mesh.verts[ 1].u =  1.0; mesh.verts[ 1].v =  0.0;

    mesh.verts[ 2].x =  0.5; mesh.verts[ 2].y =  0.5; mesh.verts[ 2].z =  0.5;
    mesh.verts[ 2].u =  1.0; mesh.verts[ 2].v =  1.0;

    mesh.verts[ 3].x = -0.5; mesh.verts[ 3].y =  0.5; mesh.verts[ 3].z =  0.5;
    mesh.verts[ 3].u =  0.0; mesh.verts[ 3].v =  1.0;

    // -- -Z face (back, nz = -1) ----------------------------------------------
    mesh.verts[ 4].x =  0.5; mesh.verts[ 4].y = -0.5; mesh.verts[ 4].z = -0.5;
    mesh.verts[ 4].u =  0.0; mesh.verts[ 4].v =  0.0;

    mesh.verts[ 5].x = -0.5; mesh.verts[ 5].y = -0.5; mesh.verts[ 5].z = -0.5;
    mesh.verts[ 5].u =  1.0; mesh.verts[ 5].v =  0.0;

    mesh.verts[ 6].x = -0.5; mesh.verts[ 6].y =  0.5; mesh.verts[ 6].z = -0.5;
    mesh.verts[ 6].u =  1.0; mesh.verts[ 6].v =  1.0;

    mesh.verts[ 7].x =  0.5; mesh.verts[ 7].y =  0.5; mesh.verts[ 7].z = -0.5;
    mesh.verts[ 7].u =  0.0; mesh.verts[ 7].v =  1.0;

    // -- +X face (right, nx = +1) ---------------------------------------------
    mesh.verts[ 8].x =  0.5; mesh.verts[ 8].y = -0.5; mesh.verts[ 8].z =  0.5;
    mesh.verts[ 8].u =  0.0; mesh.verts[ 8].v =  0.0;

    mesh.verts[ 9].x =  0.5; mesh.verts[ 9].y = -0.5; mesh.verts[ 9].z = -0.5;
    mesh.verts[ 9].u =  1.0; mesh.verts[ 9].v =  0.0;

    mesh.verts[10].x =  0.5; mesh.verts[10].y =  0.5; mesh.verts[10].z = -0.5;
    mesh.verts[10].u =  1.0; mesh.verts[10].v =  1.0;

    mesh.verts[11].x =  0.5; mesh.verts[11].y =  0.5; mesh.verts[11].z =  0.5;
    mesh.verts[11].u =  0.0; mesh.verts[11].v =  1.0;

    // -- -X face (left, nx = -1) ----------------------------------------------
    mesh.verts[12].x = -0.5; mesh.verts[12].y = -0.5; mesh.verts[12].z = -0.5;
    mesh.verts[12].u =  0.0; mesh.verts[12].v =  0.0;

    mesh.verts[13].x = -0.5; mesh.verts[13].y = -0.5; mesh.verts[13].z =  0.5;
    mesh.verts[13].u =  1.0; mesh.verts[13].v =  0.0;

    mesh.verts[14].x = -0.5; mesh.verts[14].y =  0.5; mesh.verts[14].z =  0.5;
    mesh.verts[14].u =  1.0; mesh.verts[14].v =  1.0;

    mesh.verts[15].x = -0.5; mesh.verts[15].y =  0.5; mesh.verts[15].z = -0.5;
    mesh.verts[15].u =  0.0; mesh.verts[15].v =  1.0;

    // -- +Y face (top, ny = +1) -----------------------------------------------
    mesh.verts[16].x = -0.5; mesh.verts[16].y =  0.5; mesh.verts[16].z =  0.5;
    mesh.verts[16].u =  0.0; mesh.verts[16].v =  0.0;

    mesh.verts[17].x =  0.5; mesh.verts[17].y =  0.5; mesh.verts[17].z =  0.5;
    mesh.verts[17].u =  1.0; mesh.verts[17].v =  0.0;

    mesh.verts[18].x =  0.5; mesh.verts[18].y =  0.5; mesh.verts[18].z = -0.5;
    mesh.verts[18].u =  1.0; mesh.verts[18].v =  1.0;

    mesh.verts[19].x = -0.5; mesh.verts[19].y =  0.5; mesh.verts[19].z = -0.5;
    mesh.verts[19].u =  0.0; mesh.verts[19].v =  1.0;

    // -- -Y face (bottom, ny = -1) --------------------------------------------
    mesh.verts[20].x = -0.5; mesh.verts[20].y = -0.5; mesh.verts[20].z = -0.5;
    mesh.verts[20].u =  0.0; mesh.verts[20].v =  0.0;

    mesh.verts[21].x =  0.5; mesh.verts[21].y = -0.5; mesh.verts[21].z = -0.5;
    mesh.verts[21].u =  1.0; mesh.verts[21].v =  0.0;

    mesh.verts[22].x =  0.5; mesh.verts[22].y = -0.5; mesh.verts[22].z =  0.5;
    mesh.verts[22].u =  1.0; mesh.verts[22].v =  1.0;

    mesh.verts[23].x = -0.5; mesh.verts[23].y = -0.5; mesh.verts[23].z =  0.5;
    mesh.verts[23].u =  0.0; mesh.verts[23].v =  1.0;

    // -- Triangle indices (CCW winding when viewed from outside) --------------
    // Face 0 (+Z)
    mesh.tris[ 0].a =  0; mesh.tris[ 0].b =  1; mesh.tris[ 0].c =  2;
    mesh.tris[ 1].a =  0; mesh.tris[ 1].b =  2; mesh.tris[ 1].c =  3;
    // Face 1 (-Z)
    mesh.tris[ 2].a =  4; mesh.tris[ 2].b =  5; mesh.tris[ 2].c =  6;
    mesh.tris[ 3].a =  4; mesh.tris[ 3].b =  6; mesh.tris[ 3].c =  7;
    // Face 2 (+X)
    mesh.tris[ 4].a =  8; mesh.tris[ 4].b =  9; mesh.tris[ 4].c = 10;
    mesh.tris[ 5].a =  8; mesh.tris[ 5].b = 10; mesh.tris[ 5].c = 11;
    // Face 3 (-X)
    mesh.tris[ 6].a = 12; mesh.tris[ 6].b = 13; mesh.tris[ 6].c = 14;
    mesh.tris[ 7].a = 12; mesh.tris[ 7].b = 14; mesh.tris[ 7].c = 15;
    // Face 4 (+Y)
    mesh.tris[ 8].a = 16; mesh.tris[ 8].b = 17; mesh.tris[ 8].c = 18;
    mesh.tris[ 9].a = 16; mesh.tris[ 9].b = 18; mesh.tris[ 9].c = 19;
    // Face 5 (-Y)
    mesh.tris[10].a = 20; mesh.tris[10].b = 21; mesh.tris[10].c = 22;
    mesh.tris[11].a = 20; mesh.tris[11].b = 22; mesh.tris[11].c = 23;

    // Compute smooth per-vertex normals from averaged face normals
    r3d_mesh_compute_normals(mesh);

    return;
};

// ============================================================================
// PROCEDURAL TEXTURE  (identical to cube_demo.fx)
// ============================================================================

def make_metal_texture(RCTexturePalette* pal) -> void
{
    // 256x256 with 16-texel checker squares.
    // Each square is 4x more texels per side than the old 64x64/4-texel version,
    // so nearest-neighbor at close range renders actual detail instead of
    // zoomed-in 4-pixel blocks.
    const int TEX_W = 256,
              TEX_H = 256;

    size_t bytes;
    u64*   pixels;
    int    x, y, check, scratch_y;
    double r, g, b, noise, scratch;

    bytes  = (size_t)(TEX_W * TEX_H * 8);
    pixels = (u64*)fmalloc(bytes);

    y = 0;
    while (y < TEX_H)
    {
        x = 0;
        while (x < TEX_W)
        {
            // 16x16 checker squares (same visual proportion as 4x4 in 64x64)
            check = ((x / 16) + (y / 16)) % 2;

            // No per-square noise or scratch variation -- pure flat color per square.
            noise = 0.0;
            scratch = 0.0;

            if (check == 0)
            {
                // Dark face: charcoal steel
                r = 0.18 + noise - scratch;
                g = 0.18 + noise - scratch;
                b = 0.22 + noise - scratch;
            }
            else
            {
                // Light face: polished silver with slight blue tint
                r = 0.72 + noise - scratch;
                g = 0.75 + noise - scratch;
                b = 0.82 + noise - scratch;
            };

            // Clamp to [0, 1]
            if (r < 0.0) { r = 0.0; } elif (r > 1.0) { r = 1.0; };
            if (g < 0.0) { g = 0.0; } elif (g > 1.0) { g = 1.0; };
            if (b < 0.0) { b = 0.0; } elif (b > 1.0) { b = 1.0; };

            pixels[y * TEX_W + x] = color64_pack(r, g, b);

            x++;
        };
        y++;
    };

    // Slot index 1 (slot 0 reserved by raycasting.fx convention)
    rc_palette_add(pal, pixels, TEX_W, TEX_H);

    return;
};

// ============================================================================
// LCG - simple deterministic pseudo-random number generator
//
// Returns an integer in [0, 32767] and advances the seed.
// Using a standard LCG: next = seed * 1664525 + 1013904223
// ============================================================================

def lcg_next(u64* seed) -> int
{
    *seed = *seed * (u64)1664525 + (u64)1013904223;
    return (int)((*seed >> 17) `& (u64)0x7FFF);
};

// Returns a double in [0.0, 1.0)
def lcg_double(u64* seed) -> double
{
    return (double)lcg_next(seed) / 32768.0d;
};

// Returns a double in [lo, hi)
def lcg_range(u64* seed, double lo, double hi) -> double
{
    return lo + lcg_double(seed) * (hi - lo);
};

// ============================================================================
// MAIN
// ============================================================================

const int VK_LEFT  = 0x25,
          VK_RIGHT = 0x27,
          VK_UP    = 0x26,
          VK_DOWN  = 0x28,
          VK_W     = 0x57,
          VK_S     = 0x53,
          VK_A     = 0x41,
          VK_D     = 0x44,
          VK_Q     = 0x51,
          VK_E     = 0x45,
          VK_R     = 0x52;

def main() -> int
{
    // -- Window + GL context ---------------------------------------------------
    Window    win("Cube Stress - W/S: fly  A/D: strafe  Q/E: up/dn  Arrows: look  R: reset\0",
                  100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);
    gl.load_extensions();

    // Fixed-function setup identical to cube_demo.fx
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_TEXTURE_2D);

    i32 tex_id;
    glGenTextures(1, @tex_id);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // -- Pixel + depth buffers -------------------------------------------------
    size_t px_bytes, z_bytes;
    px_bytes = WIN_W * WIN_H * 8;
    z_bytes  = WIN_W * WIN_H * 8;

    u64*    pixels = (u64*)fmalloc(px_bytes);
    double* zbuf   = (double*)fmalloc(z_bytes);

    // -- Texture palette -------------------------------------------------------
    RCTexturePalette palette;
    rc_palette_init(@palette, 4);
    make_metal_texture(@palette);

    // -- Shared cube mesh ------------------------------------------------------
    // All NUM_CUBES instances reference this single mesh; only position,
    // rotation, scale, and tint differ per instance.
    R3DMesh cube_mesh;
    build_cube_mesh(@cube_mesh);

    // -- Allocate instance array on heap ---------------------------------------
    // NOTE: sizeof(R3DMeshInst)/8 = 92 but LLVM strides GEP by 96 due to
    // alignment of the trailing i64 field; sizeof does not account for this yet.
    // Use the correct stride (96) directly until the compiler handles alignment.
    size_t inst_bytes, ptr_bytes;
    inst_bytes = (size_t)(NUM_CUBES * 96);
    ptr_bytes  = (size_t)(NUM_CUBES * 8);   // array of NUM_CUBES pointers (8 bytes each)

    R3DMeshInst*  insts     = (R3DMeshInst*)fmalloc(inst_bytes);
    R3DMeshInst** inst_ptrs = (R3DMeshInst**)fmalloc(ptr_bytes);

    // -- Four debug tints ------------------------------------------------------
    // Packed u64 tints: 0xAAAARRRRGGGGBBBB, A=0xFFFF
    // Slight color cast per group makes depth / winding errors visible at a glance.
    u64[4] tints;
    //tints[0] = (u64)0;                        // no tint  (neutral)
    tints[1] = color64_pack(1.0d, 0.55d, 0.55d);  // warm red cast
    tints[2] = color64_pack(0.55d, 1.0d, 0.55d);  // cool green cast
    tints[3] = color64_pack(0.55d, 0.75d, 1.0d);  // blue cast

    // -- Scatter instances using a deterministic LCG ---------------------------
    // Seed chosen arbitrarily; change to get a different field layout.
    u64 rng_seed = (u64)0xDEADBEEF1337C0DE;
    int i;

    i = 0;
    while (i < NUM_CUBES)
    {
        r3d_inst_init(@insts[i], @cube_mesh);

        // Random position in a large volume
        insts[i].pos_x = lcg_range(@rng_seed, -40.0d, 40.0d);
        insts[i].pos_y = lcg_range(@rng_seed, -15.0d, 15.0d);
        insts[i].pos_z = lcg_range(@rng_seed, -40.0d, 40.0d);

        // Random uniform scale [0.4, 2.5]
        {
            double s;
            s = lcg_range(@rng_seed, 0.4d, 2.5d);
            insts[i].scale_x = s;
            insts[i].scale_y = s;
            insts[i].scale_z = s;
        };

        // Random initial rotation offsets so orientations vary
        insts[i].rot_x = lcg_range(@rng_seed, 0.0d, 6.2831853d);
        insts[i].rot_y = lcg_range(@rng_seed, 0.0d, 6.2831853d);
        insts[i].rot_z = lcg_range(@rng_seed, 0.0d, 6.2831853d);

        // Cycle through the four tints
        insts[i].tint = tints[i % 4];

        insts[i].shade_model = R3D_SHADE_GOURAUD;

        inst_ptrs[i] = @insts[i];

        i++;
    };

    // -- Lights (identical three-point rig from cube_demo.fx) ------------------
    R3DLight[3] lights;

    // Key light: sun-like warm white, shining from upper-left-front
    r3d_light_directional(@lights[0],
        -0.6, -0.8, -0.4,        // direction vector (points at scene)
         1.00, 0.95, 0.85,       // warm white color
         1.1);                    // intensity

    // Fill light: cool blue-tinted point light to the right
    r3d_light_point(@lights[1],
         3.0, 1.0, 2.0,          // position (right, mid-height, in front)
         0.6, 0.7, 1.0,          // cool blue tint
         0.8,                     // intensity
         1.0, 0.15, 0.03);        // attenuation: const, linear, quad

    // Rim light: icy silver from behind-right for edge definition
    r3d_light_directional(@lights[2],
         0.7, 0.3, 0.9,          // direction vector (from front-left, hitting back-right)
         0.85, 0.90, 1.0,        // near-white with cool cast
         0.45);                   // intensity

    // -- Sky -------------------------------------------------------------------
    RCSky sky;
    sky.color_top     = color64_pack(0.04d, 0.07d, 0.18d);   // deep midnight blue
    sky.color_horizon = color64_pack(0.01d, 0.02d, 0.06d);   // near-black at horizon

    // -- Camera + player -------------------------------------------------------
    R3DCamera cam;
    R3DPlayer player;

    r3d_camera_init(@cam, 70.0d, WIN_W, WIN_H, 0.05d, 200.0d);
    r3d_player_init(@player, 0.0d, 0.0d, 0.0d);   // start at origin

    player.yaw   = 0.0d;
    player.pitch = 0.0d;

    // -- Scene -----------------------------------------------------------------
    R3DScene scene;
    r3d_scene_init(@scene, @cam, @player, @palette, @sky);
    r3d_scene_set_insts(@scene, inst_ptrs, NUM_CUBES);
    r3d_scene_set_lights(@scene, @lights[0], 3);
    r3d_scene_set_ambient(@scene, 0.06d, 0.07d, 0.10d);
    scene.passes = R3D_PASS_ALL;

    // -- State variables -------------------------------------------------------
    DWORD t_start, t_last, t_now;
    double dt, elapsed;
    WORD  left_st, right_st, up_st, dn_st, w_st, s_st, a_st, d_st, q_st, e_st, r_st;
    RECT  cr;

    t_start = GetTickCount();
    t_last  = t_start;

    while (win.process_messages())
    {
        // -- Delta time -------------------------------------------------------
        t_now = GetTickCount();
        dt    = (double)(t_now - t_last) / 1000.0d;
        t_last = t_now;
        if (dt > 0.1d) { dt = 0.1d; };

        // -- Input ------------------------------------------------------------
        left_st  = GetAsyncKeyState(VK_LEFT);
        right_st = GetAsyncKeyState(VK_RIGHT);
        up_st    = GetAsyncKeyState(VK_UP);
        dn_st    = GetAsyncKeyState(VK_DOWN);
        w_st     = GetAsyncKeyState(VK_W);
        s_st     = GetAsyncKeyState(VK_S);
        a_st     = GetAsyncKeyState(VK_A);
        d_st     = GetAsyncKeyState(VK_D);
        q_st     = GetAsyncKeyState(VK_Q);
        e_st     = GetAsyncKeyState(VK_E);
        r_st     = GetAsyncKeyState(VK_R);

        // Yaw
        if ((left_st  `& 0x8000) != 0) { r3d_player_turn(@player, -dt * 1.5d, 0.0d); };
        if ((right_st `& 0x8000) != 0) { r3d_player_turn(@player,  dt * 1.5d, 0.0d); };

        // Pitch
        if ((up_st  `& 0x8000) != 0) { r3d_player_turn(@player, 0.0d,  dt * 1.2d); };
        if ((dn_st  `& 0x8000) != 0) { r3d_player_turn(@player, 0.0d, -dt * 1.2d); };

        // Fly forward / back
        if ((w_st `& 0x8000) != 0) { r3d_player_move(@player, 0.0d,  dt * 8.0d, 0.0d); };
        if ((s_st `& 0x8000) != 0) { r3d_player_move(@player, 0.0d, -dt * 8.0d, 0.0d); };

        // Strafe left / right
        if ((a_st `& 0x8000) != 0) { r3d_player_move(@player, -dt * 8.0d, 0.0d, 0.0d); };
        if ((d_st `& 0x8000) != 0) { r3d_player_move(@player,  dt * 8.0d, 0.0d, 0.0d); };

        // Fly up / down
        if ((q_st `& 0x8000) != 0) { r3d_player_move(@player, 0.0d, 0.0d,  dt * 8.0d); };
        if ((e_st `& 0x8000) != 0) { r3d_player_move(@player, 0.0d, 0.0d, -dt * 8.0d); };

        // Reset to origin
        if ((r_st `& 0x8000) != 0)
        {
            player.pos_x = 0.0d;
            player.pos_y = 0.0d;
            player.pos_z = 0.0d;
            player.yaw   = 0.0d;
            player.pitch = 0.0d;
        };

        // -- Rotate each cube on its own axes (slow drift) ---------------------
        elapsed = (double)(t_now - t_start) / 1000.0d;

        // Each cube gets a slightly different rotation speed derived from its
        // index so they do not all spin in lockstep.
        i = 0;
        while (i < NUM_CUBES)
        {
            double speed_y, speed_x;
            speed_y = 0.30d + (double)(i % 17) * 0.02d;
            speed_x = 0.15d + (double)(i % 11) * 0.018d;
            // Base offsets were seeded randomly at init; just add elapsed rotation
            // on top.  We stored the random offsets in rot_x/rot_y/rot_z at init
            // time so we read them back here and add the running component.
            // To keep this simple and avoid storing a separate base-offset array,
            // we use elapsed * speed as the full angle, with the per-instance
            // phase baked in via the index arithmetic.
            insts[i].rot_y = elapsed * speed_y + (double)i * 0.37d;
            insts[i].rot_x = elapsed * speed_x + (double)i * 0.21d;
            i++;
        };

        // -- Resize check -----------------------------------------------------
        GetClientRect(win.handle, @cr);
        {
            i32 cur_w, cur_h;
            cur_w = cr.right  - cr.left;
            cur_h = cr.bottom - cr.top;
            if (cur_w < 1) { cur_w = 1; };
            if (cur_h < 1) { cur_h = 1; };
            glViewport(0, 0, cur_w, cur_h);
        };

        // -- Sync camera matrices ---------------------------------------------
        r3d_camera_sync(@cam, @player);

        // -- Render 3D scene --------------------------------------------------
        r3d_render(@scene, pixels, zbuf);

        // -- Upload texture and draw fullscreen quad ---------------------------
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        glBindTexture(GL_TEXTURE_2D, tex_id);

        glTexImage2D(GL_TEXTURE_2D, 0, (i32)GL_RGBA, WIN_W, WIN_H, 0,
                     (i32)GL_RGBA, 0x1403 /// GL_UNSIGNED_SHORT ///, (void*)pixels);

        glBegin(GL_QUADS);
        glTexCoord2f(0.0, 1.0); glVertex2f(-1.0, -1.0);
        glTexCoord2f(1.0, 1.0); glVertex2f( 1.0, -1.0);
        glTexCoord2f(1.0, 0.0); glVertex2f( 1.0,  1.0);
        glTexCoord2f(0.0, 0.0); glVertex2f(-1.0,  1.0);
        glEnd();

        gl.present();
    };

    // -- Cleanup ---------------------------------------------------------------
    r3d_mesh_free(@cube_mesh);
    rc_palette_free(@palette);
    ffree((u64)insts);
    ffree((u64)inst_ptrs);
    ffree((u64)pixels);
    ffree((u64)zbuf);

    glDeleteTextures(1, @tex_id);
    gl.__exit();
    win.__exit();

    return 0;
};
