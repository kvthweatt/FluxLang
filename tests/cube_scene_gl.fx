// cube_demo.fx - Rotating Cube with Realistic Lighting
//
// Scene setup:
//   - A single cube mesh centred at the world origin, auto-rotating on Y and X.
//   - Procedural brushed-metal checkerboard texture (64×64, no file I/O needed).
//   - Three lights:
//       Key  : directional warm white  (sun-like, upper-left)
//       Fill : point light cool blue   (right side, gentle)
//       Rim  : directional cool silver (back-right edge highlight)
//   - Gouraud shading + per-vertex smooth normals.
//   - Sky: deep blue → near-black horizon.
//   - Camera orbits slightly above the cube looking down.
//   - Controls:
//       Arrow keys   - orbit camera (yaw / pitch)
//       W / S        - dolly in / out
//       R            - reset camera
//
// Architecture:
//   raycasting.fx 3D engine renders into a u64 pixel buffer each frame.
//   The buffer is uploaded as an OpenGL RGBA texture and drawn as one
//   fullscreen quad - identical pattern to the Mandelbrot demo.
//
// Build:
//   fxc cube_demo.fx -o cube_demo.exe
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
// CUBE GEOMETRY BUILDER
//
// A unit cube (±0.5 on each axis) with 24 unique vertices (4 per face) so
// that per-face normals are distinct before smooth-averaging, giving correct
// Gouraud shading across each face.
//
// UV layout: each face maps [0,1]×[0,1] independently.
// ============================================================================

// One face's worth of raw vertex data (position + normal + uv) - used inline.
def build_cube_mesh(R3DMesh* mesh) -> void
{
    r3d_mesh_init(mesh, 24, 12, 1);   // 24 verts, 12 tris, texture slot 1

    // Helper: set one vertex
    // Vertex layout in mesh.verts[idx]:
    //   x y z  nx ny nz  u v
    //
    // We set positions and UVs here; normals are computed via
    // r3d_mesh_compute_normals() after all triangles are set.

    // ── Face indices: v0..v3 = quad corners, two tris per face ──────────────
    //
    //  Face 0: +Z  (front)   verts  0.. 3
    //  Face 1: -Z  (back)    verts  4.. 7
    //  Face 2: +X  (right)   verts  8..11
    //  Face 3: -X  (left)    verts 12..15
    //  Face 4: +Y  (top)     verts 16..19
    //  Face 5: -Y  (bottom)  verts 20..23

    // ── +Z face (front, nz = +1) ─────────────────────────────────────────────
    mesh.verts[ 0].x = -0.5; mesh.verts[ 0].y = -0.5; mesh.verts[ 0].z =  0.5;
    mesh.verts[ 0].u =  0.0; mesh.verts[ 0].v =  0.0;

    mesh.verts[ 1].x =  0.5; mesh.verts[ 1].y = -0.5; mesh.verts[ 1].z =  0.5;
    mesh.verts[ 1].u =  1.0; mesh.verts[ 1].v =  0.0;

    mesh.verts[ 2].x =  0.5; mesh.verts[ 2].y =  0.5; mesh.verts[ 2].z =  0.5;
    mesh.verts[ 2].u =  1.0; mesh.verts[ 2].v =  1.0;

    mesh.verts[ 3].x = -0.5; mesh.verts[ 3].y =  0.5; mesh.verts[ 3].z =  0.5;
    mesh.verts[ 3].u =  0.0; mesh.verts[ 3].v =  1.0;

    // ── -Z face (back, nz = -1) ──────────────────────────────────────────────
    mesh.verts[ 4].x =  0.5; mesh.verts[ 4].y = -0.5; mesh.verts[ 4].z = -0.5;
    mesh.verts[ 4].u =  0.0; mesh.verts[ 4].v =  0.0;

    mesh.verts[ 5].x = -0.5; mesh.verts[ 5].y = -0.5; mesh.verts[ 5].z = -0.5;
    mesh.verts[ 5].u =  1.0; mesh.verts[ 5].v =  0.0;

    mesh.verts[ 6].x = -0.5; mesh.verts[ 6].y =  0.5; mesh.verts[ 6].z = -0.5;
    mesh.verts[ 6].u =  1.0; mesh.verts[ 6].v =  1.0;

    mesh.verts[ 7].x =  0.5; mesh.verts[ 7].y =  0.5; mesh.verts[ 7].z = -0.5;
    mesh.verts[ 7].u =  0.0; mesh.verts[ 7].v =  1.0;

    // ── +X face (right, nx = +1) ─────────────────────────────────────────────
    mesh.verts[ 8].x =  0.5; mesh.verts[ 8].y = -0.5; mesh.verts[ 8].z =  0.5;
    mesh.verts[ 8].u =  0.0; mesh.verts[ 8].v =  0.0;

    mesh.verts[ 9].x =  0.5; mesh.verts[ 9].y = -0.5; mesh.verts[ 9].z = -0.5;
    mesh.verts[ 9].u =  1.0; mesh.verts[ 9].v =  0.0;

    mesh.verts[10].x =  0.5; mesh.verts[10].y =  0.5; mesh.verts[10].z = -0.5;
    mesh.verts[10].u =  1.0; mesh.verts[10].v =  1.0;

    mesh.verts[11].x =  0.5; mesh.verts[11].y =  0.5; mesh.verts[11].z =  0.5;
    mesh.verts[11].u =  0.0; mesh.verts[11].v =  1.0;

    // ── -X face (left, nx = -1) ──────────────────────────────────────────────
    mesh.verts[12].x = -0.5; mesh.verts[12].y = -0.5; mesh.verts[12].z = -0.5;
    mesh.verts[12].u =  0.0; mesh.verts[12].v =  0.0;

    mesh.verts[13].x = -0.5; mesh.verts[13].y = -0.5; mesh.verts[13].z =  0.5;
    mesh.verts[13].u =  1.0; mesh.verts[13].v =  0.0;

    mesh.verts[14].x = -0.5; mesh.verts[14].y =  0.5; mesh.verts[14].z =  0.5;
    mesh.verts[14].u =  1.0; mesh.verts[14].v =  1.0;

    mesh.verts[15].x = -0.5; mesh.verts[15].y =  0.5; mesh.verts[15].z = -0.5;
    mesh.verts[15].u =  0.0; mesh.verts[15].v =  1.0;

    // ── +Y face (top, ny = +1) ───────────────────────────────────────────────
    mesh.verts[16].x = -0.5; mesh.verts[16].y =  0.5; mesh.verts[16].z =  0.5;
    mesh.verts[16].u =  0.0; mesh.verts[16].v =  0.0;

    mesh.verts[17].x =  0.5; mesh.verts[17].y =  0.5; mesh.verts[17].z =  0.5;
    mesh.verts[17].u =  1.0; mesh.verts[17].v =  0.0;

    mesh.verts[18].x =  0.5; mesh.verts[18].y =  0.5; mesh.verts[18].z = -0.5;
    mesh.verts[18].u =  1.0; mesh.verts[18].v =  1.0;

    mesh.verts[19].x = -0.5; mesh.verts[19].y =  0.5; mesh.verts[19].z = -0.5;
    mesh.verts[19].u =  0.0; mesh.verts[19].v =  1.0;

    // ── -Y face (bottom, ny = -1) ────────────────────────────────────────────
    mesh.verts[20].x = -0.5; mesh.verts[20].y = -0.5; mesh.verts[20].z = -0.5;
    mesh.verts[20].u =  0.0; mesh.verts[20].v =  0.0;

    mesh.verts[21].x =  0.5; mesh.verts[21].y = -0.5; mesh.verts[21].z = -0.5;
    mesh.verts[21].u =  1.0; mesh.verts[21].v =  0.0;

    mesh.verts[22].x =  0.5; mesh.verts[22].y = -0.5; mesh.verts[22].z =  0.5;
    mesh.verts[22].u =  1.0; mesh.verts[22].v =  1.0;

    mesh.verts[23].x = -0.5; mesh.verts[23].y = -0.5; mesh.verts[23].z =  0.5;
    mesh.verts[23].u =  0.0; mesh.verts[23].v =  1.0;

    // ── Triangle indices (CCW winding when viewed from outside) ──────────────
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
// PROCEDURAL TEXTURE
//
// Brushed-metal look: a 64×64 tile with two interleaved materials:
//   Dark squares  - charcoal steel  (0.18, 0.18, 0.20)
//   Light squares - polished silver (0.75, 0.78, 0.85)
// A subtle horizontal scratch pattern is added to both to simulate
// directional brushing.  All values stored as u64 AAARRRRGGGGBBBB.
// ============================================================================

def make_metal_texture(RCTexturePalette* pal) -> void
{
    const int TEX_W = 64,
              TEX_H = 64;

    size_t bytes;
    u64*   pixels;
    int    x, y, check, scratch_y;
    double r, g, b, noise, scratch;

    bytes  = (size_t)(TEX_W * TEX_H * 8);   // 8 bytes per u64 pixel
    pixels = (u64*)fmalloc(bytes);

    y = 0;
    while (y < TEX_H)
    {
        x = 0;
        while (x < TEX_W)
        {
            // 4×4 checkerboard
            check = ((x / 4) + (y / 4)) % 2;

            // Horizontal scratch bands every ~3 rows, very thin
            scratch_y = y % 7;
            scratch = (scratch_y == 0 | scratch_y == 1) ? 0.06 : 0.0;

            // Subtle pseudo-noise from position to break up flatness
            noise = (double)((x * 13 + y * 7 + x * y * 3) % 17) / 17.0 * 0.04;

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
// MAIN
// ============================================================================

const int VK_LEFT  = 0x25,
          VK_RIGHT = 0x27,
          VK_UP    = 0x26,
          VK_DOWN  = 0x28,
          VK_W     = 0x57,
          VK_S     = 0x53,
          VK_R     = 0x52;

def main() -> int
{
    // ── Window + GL context ───────────────────────────────────────────────────
    Window    win("Cube Demo - Arrow: orbit  W/S: zoom  R: reset\0",
                  100, 100, WIN_W, WIN_H);
    GLContext gl(win.device_context);
    gl.load_extensions();

    // Fixed-function setup: no depth test (handled by raycasting engine itself),
    // texture-mapped fullscreen quad pattern identical to the Mandelbrot demo.
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

    // ── Pixel + depth buffers ─────────────────────────────────────────────────
    size_t px_bytes, z_bytes;
    px_bytes = WIN_W * WIN_H * 8;
    z_bytes  = WIN_W * WIN_H * 8;

    u64*    pixels = (u64*)fmalloc(px_bytes);
    double* zbuf   = (double*)fmalloc(z_bytes);

    // ── Texture palette ───────────────────────────────────────────────────────
    RCTexturePalette palette;
    rc_palette_init(@palette, 4);
    make_metal_texture(@palette);

    // ── Cube mesh + instance ──────────────────────────────────────────────────
    R3DMesh     cube_mesh;
    R3DMeshInst cube_inst;
    build_cube_mesh(@cube_mesh);
    r3d_inst_init(@cube_inst, @cube_mesh);
    cube_inst.shade_model = R3D_SHADE_GOURAUD;

    // Array of instance pointers for r3d_scene
    R3DMeshInst*[1] inst_ptrs;
    inst_ptrs[0] = @cube_inst;

    // ── Lights ────────────────────────────────────────────────────────────────
    //  Three-point lighting rig:
    //    lights[0] - key  : warm directional (upper-left, strong)
    //    lights[1] - fill : cool point       (right side, soft)
    //    lights[2] - rim  : silver directional (back-right, medium)

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

    // ── Sky ───────────────────────────────────────────────────────────────────
    RCSky sky;
    sky.color_top     = color64_pack(0.04d, 0.07d, 0.18d);   // deep midnight blue
    sky.color_horizon = color64_pack(0.01d, 0.02d, 0.06d);   // near-black at horizon

    // ── Camera + player ───────────────────────────────────────────────────────
    R3DCamera cam;
    R3DPlayer player;

    r3d_camera_init(@cam, 70.0d, WIN_W, WIN_H, 0.05d, 100.0d);
    r3d_player_init(@player, 0.0d, 0.8d, 3.0d);   // start: slightly above, 3 units out

    // Default pitch: look slightly down at the cube
    player.yaw   = 0.0d;
    player.pitch = -0.22d;

    // ── Scene ─────────────────────────────────────────────────────────────────
    R3DScene scene;
    r3d_scene_init(@scene, @cam, @player, @palette, @sky);
    r3d_scene_set_insts(@scene, @inst_ptrs[0], 1);
    r3d_scene_set_lights(@scene, @lights[0], 3);
    // Moderate ambient: enough to see unlit faces without washing out the lighting
    r3d_scene_set_ambient(@scene, 0.06d, 0.07d, 0.10d);
    scene.passes = R3D_PASS_ALL;

    // ── State variables ───────────────────────────────────────────────────────
    double cam_dist,               // camera orbit radius
           orbit_yaw, orbit_pitch, // camera orbit angles (driven by keys)
           cy, sy, cp, sp;
    DWORD  t_start, t_last, t_now;
    double dt, elapsed;
    WORD   left_st, right_st, up_st, dn_st, w_st, s_st, r_st;
    RECT   cr;

    cam_dist    = 3.0d;
    orbit_yaw   = 0.0d;
    orbit_pitch = -0.22d;

    t_start = GetTickCount();
    t_last  = t_start;

    while (win.process_messages())
    {
        // ── Delta time ───────────────────────────────────────────────────────
        t_now = GetTickCount();
        dt    = (double)(t_now - t_last) / 1000.0d;
        t_last = t_now;
        if (dt > 0.1d) { dt = 0.1d; };

        // ── Input ────────────────────────────────────────────────────────────
        left_st  = GetAsyncKeyState(VK_LEFT);
        right_st = GetAsyncKeyState(VK_RIGHT);
        up_st    = GetAsyncKeyState(VK_UP);
        dn_st    = GetAsyncKeyState(VK_DOWN);
        w_st     = GetAsyncKeyState(VK_W);
        s_st     = GetAsyncKeyState(VK_S);
        r_st     = GetAsyncKeyState(VK_R);

        // Orbit camera yaw
        if ((left_st  `& 0x8000) != 0) { orbit_yaw   -= dt * 1.2d; };
        if ((right_st `& 0x8000) != 0) { orbit_yaw   += dt * 1.2d; };

        // Orbit camera pitch (clamped)
        if ((up_st    `& 0x8000) != 0) { orbit_pitch += dt * 1.0d; };
        if ((dn_st    `& 0x8000) != 0) { orbit_pitch -= dt * 1.0d; };
        if (orbit_pitch >  1.40d) { orbit_pitch =  1.40d; };
        if (orbit_pitch < -1.40d) { orbit_pitch = -1.40d; };

        // Dolly in / out
        if ((w_st `& 0x8000) != 0) { cam_dist -= dt * 2.0d; };
        if ((s_st `& 0x8000) != 0) { cam_dist += dt * 2.0d; };
        if (cam_dist < 0.8d)  { cam_dist = 0.8d;  };
        if (cam_dist > 12.0d) { cam_dist = 12.0d; };

        // Reset
        if ((r_st `& 0x8000) != 0)
        {
            orbit_yaw   = 0.0d;
            orbit_pitch = -0.22d;
            cam_dist    = 3.0d;
        };

        // ── Update camera orbit position ─────────────────────────────────────
        // Spherical coordinates around origin:
        //   x = dist * sin(yaw)  * cos(pitch)
        //   y = dist * sin(pitch)
        //   z = dist * cos(yaw)  * cos(pitch)   (positive Z is toward camera)
        cy = cos(orbit_yaw);
        sy = sin(orbit_yaw);
        cp = cos(orbit_pitch);
        sp = sin(orbit_pitch);

        player.pos_x = cam_dist * sy * cp;
        player.pos_y = cam_dist * sp;
        player.pos_z = cam_dist * cy * cp;

        // Player always looks toward origin - derive yaw/pitch from position
        // yaw: atan2(x, z) for the look-from direction
        player.yaw   = orbit_yaw;         // face origin
        player.pitch = -orbit_pitch;

        // ── Auto-rotate cube ─────────────────────────────────────────────────
        // Compute angles directly from total elapsed time - no accumulation drift
        elapsed = (double)(t_now - t_start) / 1000.0d;
        cube_inst.rot_y = elapsed * 0.55d;
        cube_inst.rot_x = elapsed * 0.22d;

        // ── Resize check ─────────────────────────────────────────────────────
        GetClientRect(win.handle, @cr);
        {
            i32 cur_w, cur_h;
            cur_w = cr.right  - cr.left;
            cur_h = cr.bottom - cr.top;
            if (cur_w < 1) { cur_w = 1; };
            if (cur_h < 1) { cur_h = 1; };
            glViewport(0, 0, cur_w, cur_h);
        };

        // ── Sync camera matrices ─────────────────────────────────────────────
        r3d_camera_sync(@cam, @player);

        // ── Render 3D scene ──────────────────────────────────────────────────
        r3d_render(@scene, pixels, zbuf);

        // ── Upload texture and draw fullscreen quad (Mandelbrot pattern) ─────
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        glBindTexture(GL_TEXTURE_2D, tex_id);

        // The pixel buffer is u64 (AAARRRRGGGGBBBB 16bpc); upload as RGBA 16-bit.
        // GL_UNSIGNED_SHORT maps 16-bit channels correctly.
        // Internal format GL_RGBA, external format GL_RGBA, type GL_UNSIGNED_SHORT.
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

    // ── Cleanup ───────────────────────────────────────────────────────────────
    r3d_mesh_free(@cube_mesh);
    rc_palette_free(@palette);
    ffree((u64)pixels);
    ffree((u64)zbuf);

    glDeleteTextures(1, @tex_id);
    gl.__exit();
    win.__exit();

    return 0;
};
