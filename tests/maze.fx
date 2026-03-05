#import "standard.fx", "redmath.fx", "redwindows.fx", "redopengl.fx", "redio.fx";

using standard::system::windows;
using standard::math;
using standard::io::file;

// ============================================================================
// GDI+ structs and externs for PNG loading
// ============================================================================

struct GdiplusStartupInput
{
    int GdiplusVersion;
    u64 DebugEventCallback;
    int SuppressBackgroundThread;
    int SuppressExternalCodecs;
};

struct BitmapData
{
    int Width;
    int Height;
    int Stride;
    int PixelFormat;
    u64 Scan0;
    u64 Reserved;
};

struct GpRectI
{
    int X;
    int Y;
    int Width;
    int Height;
};

extern
{
    def !!
        GdiplusStartup(void*, void*, void*) -> int,
        GdipLoadImageFromFile(void*, void*) -> int,
        GdipGetImageWidth(void*, int*) -> int,
        GdipGetImageHeight(void*, int*) -> int,
        GdipBitmapLockBits(void*, void*, int, int, void*) -> int,
        GdipBitmapUnlockBits(void*, void*) -> int,
        GdipDisposeImage(void*) -> int,
        GdiplusShutdown(void*) -> void,
        GetModuleFileNameA(void*, byte*, int) -> int;
};

// ImageLockModeRead = 1, PixelFormat32bppARGB = 0x26200A
const int ImageLockModeRead  = 1;
const int PixelFormat32bppARGB = 0x26200A;

// ============================================================================
// Load a PNG file into an OpenGL texture, return texture ID.
// Expects the file to be adjacent to the executable.
// ============================================================================

def load_png_texture(byte* filename) -> int
{
    // Start GDI+
    GdiplusStartupInput input;
    input.GdiplusVersion = 1;
    input.DebugEventCallback = (u64)0;
    input.SuppressBackgroundThread = 0;
    input.SuppressExternalCodecs = 0;
    u64 token = 0;
    GdiplusStartup((void*)@token, (void*)@input, (void*)0);

    // Get the full path of the exe, then replace the filename part with brick.png
    byte[512] exe_path;
    GetModuleFileNameA((void*)0, @exe_path[0], 512);

    // Find the last backslash to get the directory
    int last_slash = 0;
    int k = 0;
    while (exe_path[k] != 0)
    {
        if (exe_path[k] == 92) { last_slash = k; }; // 92 = '\'
        k = k + 1;
    };

    // Build full path: exe_dir + \ + filename into a byte buffer, then widen it
    byte[512] full_path;
    int j = 0;
    while (j <= last_slash)
    {
        full_path[j] = exe_path[j];
        j = j + 1;
    };
    int fi = 0;
    while (filename[fi] != 0)
    {
        full_path[j] = filename[fi];
        j = j + 1;
        fi = fi + 1;
    };
    full_path[j] = '\0';

    // Wide-char path: wchar_t is 16-bit on Windows.
    unsigned data{16} as wchar;
    wchar[512] wpath_buf;
    int i = 0;
    while (full_path[i] != 0)
    {
        wpath_buf[i] = (wchar)full_path[i];
        i = i + 1;
    };
    wpath_buf[i] = (wchar)0;

    u64 bitmap = 0;
    GdipLoadImageFromFile((void*)@wpath_buf[0], (void*)@bitmap);

    int img_w = 0;
    int img_h = 0;
    GdipGetImageWidth((void*)bitmap, @img_w);
    GdipGetImageHeight((void*)bitmap, @img_h);

    GpRectI rect;
    rect.X = 0;
    rect.Y = 0;
    rect.Width  = img_w;
    rect.Height = img_h;

    BitmapData bd;
    GdipBitmapLockBits((void*)bitmap, (void*)@rect, ImageLockModeRead, PixelFormat32bppARGB, (void*)@bd);

    // GDI+ gives BGRA; convert to RGBA in-place using a temp row buffer
    // We'll pass the raw BGRA as GL_BGRA (0x80E1) which OpenGL supports
    int tex_id = 0;
    glGenTextures(1, @tex_id);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

    // GL_BGRA = 0x80E1, GL_UNSIGNED_BYTE = 0x1401
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, img_w, img_h, 0, 0x80E1, GL_UNSIGNED_BYTE, (void*)bd.Scan0);

    GdipBitmapUnlockBits((void*)bitmap, (void*)@bd);
    GdipDisposeImage((void*)bitmap);

    return tex_id;
};

// ============================================================================
// Window
// ============================================================================

const int WIN_W = 900;
const int WIN_H = 600;

// ============================================================================
// Maze dimensions
// Each cell is CELL_SIZE x CELL_SIZE world units.
// Wall geometry is drawn as 4 vertical lines per wall edge (a thin quad frame).
// ============================================================================

const int  MAZE_W     = 15;    // cells wide
const int  MAZE_H     = 15;    // cells tall
const int  MAZE_CELLS = 225;   // MAZE_W * MAZE_H
const float CELL_SIZE = 3.0;
const float WALL_H    = 2.5;   // wall height
const float EYE_H     = 1.2;   // camera eye height

// Wall bitflags stored per cell: bit 0 = North wall, bit 1 = East wall
// South wall of cell (r,c) == North wall of (r+1,c)
// West  wall of cell (r,c) == East  wall of (r,c-1)
// Border walls are always present (implicit).

const int WALL_N = 1;
const int WALL_E = 2;

// ============================================================================
// Maze data  (MAZE_CELLS entries, each is WALL_N | WALL_E bitmask)
// Generated offline with recursive backtracker seeded at (0,0).
// Each value encodes which walls this cell OWNS (N and/or E).
// ============================================================================

// 15x15 maze wall data, row-major (row 0 = top).
// Bit 0 (1) = North wall present, Bit 1 (2) = East wall present.
int[225] MAZE_WALLS;

def init_maze_walls() -> void
{
    // Row 0
    MAZE_WALLS[0]   = 3; MAZE_WALLS[1]   = 1; MAZE_WALLS[2]   = 3;
    MAZE_WALLS[3]   = 1; MAZE_WALLS[4]   = 3; MAZE_WALLS[5]   = 1;
    MAZE_WALLS[6]   = 3; MAZE_WALLS[7]   = 1; MAZE_WALLS[8]   = 1;
    MAZE_WALLS[9]   = 3; MAZE_WALLS[10]  = 1; MAZE_WALLS[11]  = 3;
    MAZE_WALLS[12]  = 1; MAZE_WALLS[13]  = 1; MAZE_WALLS[14]  = 3;
    // Row 1
    MAZE_WALLS[15]  = 2; MAZE_WALLS[16]  = 3; MAZE_WALLS[17]  = 2;
    MAZE_WALLS[18]  = 3; MAZE_WALLS[19]  = 0; MAZE_WALLS[20]  = 2;
    MAZE_WALLS[21]  = 1; MAZE_WALLS[22]  = 2; MAZE_WALLS[23]  = 3;
    MAZE_WALLS[24]  = 2; MAZE_WALLS[25]  = 3; MAZE_WALLS[26]  = 2;
    MAZE_WALLS[27]  = 3; MAZE_WALLS[28]  = 2; MAZE_WALLS[29]  = 2;
    // Row 2
    MAZE_WALLS[30]  = 3; MAZE_WALLS[31]  = 0; MAZE_WALLS[32]  = 3;
    MAZE_WALLS[33]  = 0; MAZE_WALLS[34]  = 3; MAZE_WALLS[35]  = 0;
    MAZE_WALLS[36]  = 2; MAZE_WALLS[37]  = 3; MAZE_WALLS[38]  = 2;
    MAZE_WALLS[39]  = 3; MAZE_WALLS[40]  = 0; MAZE_WALLS[41]  = 3;
    MAZE_WALLS[42]  = 2; MAZE_WALLS[43]  = 3; MAZE_WALLS[44]  = 0;
    // Row 3
    MAZE_WALLS[45]  = 0; MAZE_WALLS[46]  = 3; MAZE_WALLS[47]  = 0;
    MAZE_WALLS[48]  = 3; MAZE_WALLS[49]  = 0; MAZE_WALLS[50]  = 3;
    MAZE_WALLS[51]  = 3; MAZE_WALLS[52]  = 0; MAZE_WALLS[53]  = 3;
    MAZE_WALLS[54]  = 0; MAZE_WALLS[55]  = 3; MAZE_WALLS[56]  = 0;
    MAZE_WALLS[57]  = 3; MAZE_WALLS[58]  = 0; MAZE_WALLS[59]  = 3;
    // Row 4
    MAZE_WALLS[60]  = 3; MAZE_WALLS[61]  = 2; MAZE_WALLS[62]  = 3;
    MAZE_WALLS[63]  = 2; MAZE_WALLS[64]  = 3; MAZE_WALLS[65]  = 2;
    MAZE_WALLS[66]  = 0; MAZE_WALLS[67]  = 3; MAZE_WALLS[68]  = 2;
    MAZE_WALLS[69]  = 3; MAZE_WALLS[70]  = 2; MAZE_WALLS[71]  = 3;
    MAZE_WALLS[72]  = 2; MAZE_WALLS[73]  = 3; MAZE_WALLS[74]  = 2;
    // Row 5
    MAZE_WALLS[75]  = 0; MAZE_WALLS[76]  = 3; MAZE_WALLS[77]  = 0;
    MAZE_WALLS[78]  = 3; MAZE_WALLS[79]  = 0; MAZE_WALLS[80]  = 3;
    MAZE_WALLS[81]  = 3; MAZE_WALLS[82]  = 0; MAZE_WALLS[83]  = 3;
    MAZE_WALLS[84]  = 0; MAZE_WALLS[85]  = 3; MAZE_WALLS[86]  = 0;
    MAZE_WALLS[87]  = 3; MAZE_WALLS[88]  = 0; MAZE_WALLS[89]  = 3;
    // Row 6
    MAZE_WALLS[90]  = 3; MAZE_WALLS[91]  = 2; MAZE_WALLS[92]  = 3;
    MAZE_WALLS[93]  = 0; MAZE_WALLS[94]  = 3; MAZE_WALLS[95]  = 2;
    MAZE_WALLS[96]  = 2; MAZE_WALLS[97]  = 3; MAZE_WALLS[98]  = 0;
    MAZE_WALLS[99]  = 3; MAZE_WALLS[100] = 2; MAZE_WALLS[101] = 1;
    MAZE_WALLS[102] = 3; MAZE_WALLS[103] = 2; MAZE_WALLS[104] = 3;
    // Row 7
    MAZE_WALLS[105] = 2; MAZE_WALLS[106] = 3; MAZE_WALLS[107] = 2;
    MAZE_WALLS[108] = 3; MAZE_WALLS[109] = 2; MAZE_WALLS[110] = 3;
    MAZE_WALLS[111] = 3; MAZE_WALLS[112] = 2; MAZE_WALLS[113] = 3;
    MAZE_WALLS[114] = 2; MAZE_WALLS[115] = 3; MAZE_WALLS[116] = 2;
    MAZE_WALLS[117] = 1; MAZE_WALLS[118] = 3; MAZE_WALLS[119] = 2;
    // Row 8
    MAZE_WALLS[120] = 3; MAZE_WALLS[121] = 0; MAZE_WALLS[122] = 3;
    MAZE_WALLS[123] = 2; MAZE_WALLS[124] = 3; MAZE_WALLS[125] = 0;
    MAZE_WALLS[126] = 0; MAZE_WALLS[127] = 3; MAZE_WALLS[128] = 2;
    MAZE_WALLS[129] = 3; MAZE_WALLS[130] = 0; MAZE_WALLS[131] = 3;
    MAZE_WALLS[132] = 0; MAZE_WALLS[133] = 1; MAZE_WALLS[134] = 3;
    // Row 9
    MAZE_WALLS[135] = 0; MAZE_WALLS[136] = 3; MAZE_WALLS[137] = 2;
    MAZE_WALLS[138] = 3; MAZE_WALLS[139] = 2; MAZE_WALLS[140] = 3;
    MAZE_WALLS[141] = 3; MAZE_WALLS[142] = 0; MAZE_WALLS[143] = 3;
    MAZE_WALLS[144] = 0; MAZE_WALLS[145] = 3; MAZE_WALLS[146] = 2;
    MAZE_WALLS[147] = 3; MAZE_WALLS[148] = 2; MAZE_WALLS[149] = 0;
    // Row 10
    MAZE_WALLS[150] = 3; MAZE_WALLS[151] = 2; MAZE_WALLS[152] = 3;
    MAZE_WALLS[153] = 0; MAZE_WALLS[154] = 3; MAZE_WALLS[155] = 2;
    MAZE_WALLS[156] = 0; MAZE_WALLS[157] = 3; MAZE_WALLS[158] = 2;
    MAZE_WALLS[159] = 3; MAZE_WALLS[160] = 2; MAZE_WALLS[161] = 3;
    MAZE_WALLS[162] = 2; MAZE_WALLS[163] = 3; MAZE_WALLS[164] = 2;
    // Row 11
    MAZE_WALLS[165] = 0; MAZE_WALLS[166] = 3; MAZE_WALLS[167] = 0;
    MAZE_WALLS[168] = 3; MAZE_WALLS[169] = 0; MAZE_WALLS[170] = 3;
    MAZE_WALLS[171] = 3; MAZE_WALLS[172] = 0; MAZE_WALLS[173] = 3;
    MAZE_WALLS[174] = 0; MAZE_WALLS[175] = 3; MAZE_WALLS[176] = 0;
    MAZE_WALLS[177] = 3; MAZE_WALLS[178] = 0; MAZE_WALLS[179] = 3;
    // Row 12
    MAZE_WALLS[180] = 3; MAZE_WALLS[181] = 0; MAZE_WALLS[182] = 3;
    MAZE_WALLS[183] = 2; MAZE_WALLS[184] = 3; MAZE_WALLS[185] = 0;
    MAZE_WALLS[186] = 2; MAZE_WALLS[187] = 3; MAZE_WALLS[188] = 0;
    MAZE_WALLS[189] = 3; MAZE_WALLS[190] = 0; MAZE_WALLS[191] = 3;
    MAZE_WALLS[192] = 0; MAZE_WALLS[193] = 3; MAZE_WALLS[194] = 0;
    // Row 13
    MAZE_WALLS[195] = 2; MAZE_WALLS[196] = 3; MAZE_WALLS[197] = 2;
    MAZE_WALLS[198] = 3; MAZE_WALLS[199] = 2; MAZE_WALLS[200] = 3;
    MAZE_WALLS[201] = 3; MAZE_WALLS[202] = 2; MAZE_WALLS[203] = 3;
    MAZE_WALLS[204] = 2; MAZE_WALLS[205] = 3; MAZE_WALLS[206] = 2;
    MAZE_WALLS[207] = 1; MAZE_WALLS[208] = 3; MAZE_WALLS[209] = 2;
    // Row 14
    MAZE_WALLS[210] = 3; MAZE_WALLS[211] = 1; MAZE_WALLS[212] = 3;
    MAZE_WALLS[213] = 1; MAZE_WALLS[214] = 3; MAZE_WALLS[215] = 1;
    MAZE_WALLS[216] = 1; MAZE_WALLS[217] = 3; MAZE_WALLS[218] = 1;
    MAZE_WALLS[219] = 3; MAZE_WALLS[220] = 1; MAZE_WALLS[221] = 3;
    MAZE_WALLS[222] = 1; MAZE_WALLS[223] = 1; MAZE_WALLS[224] = 3;
    return;
};

// ============================================================================
// Wall query helpers
// ============================================================================

def has_north(int r, int c) -> bool
{
    if (r < 0 | r >= MAZE_H | c < 0 | c >= MAZE_W) { return true; };
    return (MAZE_WALLS[r * MAZE_W + c] & WALL_N) != 0;
};

def has_east(int r, int c) -> bool
{
    if (r < 0 | r >= MAZE_H | c < 0 | c >= MAZE_W) { return true; };
    return (MAZE_WALLS[r * MAZE_W + c] & WALL_E) != 0;
};

def has_south(int r, int c) -> bool
{
    // South wall of (r,c) is north wall of (r+1,c)
    return has_north(r + 1, c);
};

def has_west(int r, int c) -> bool
{
    // West wall of (r,c) is east wall of (r,c-1)
    return has_east(r, c - 1);
};

// ============================================================================
// Cell center in world space.
// Row 0 is at Z = 0, increases downward (+Z).
// Col 0 is at X = 0, increases rightward (+X).
// ============================================================================

def cell_cx(int c) -> float { return (float)c * CELL_SIZE + CELL_SIZE * 0.5; };
def cell_cz(int r) -> float { return (float)r * CELL_SIZE + CELL_SIZE * 0.5; };

// ============================================================================
// Draw a single solid wall segment.
// (x0,z0) -> (x1,z1) is the base line of the wall.
// Two quads are emitted (front and back) so the wall is solid from both sides.
// ============================================================================

def draw_wall_seg(float x0, float z0, float x1, float z1) -> void
{
    float len = sqrt((x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0));
    float u1 = len / CELL_SIZE;
    float v1 = WALL_H / CELL_SIZE;
    // Front face (winding: bottom-left, bottom-right, top-right, top-left)
    glTexCoord2f(0.0, 0.0);  glVertex3f(x0, 0.0,    z0);
    glTexCoord2f(u1,  0.0);  glVertex3f(x1, 0.0,    z1);
    glTexCoord2f(u1,  v1);   glVertex3f(x1, WALL_H, z1);
    glTexCoord2f(0.0, v1);   glVertex3f(x0, WALL_H, z0);
    // Back face (reversed winding)
    glTexCoord2f(0.0, v1);   glVertex3f(x0, WALL_H, z0);
    glTexCoord2f(u1,  v1);   glVertex3f(x1, WALL_H, z1);
    glTexCoord2f(u1,  0.0);  glVertex3f(x1, 0.0,    z1);
    glTexCoord2f(0.0, 0.0);  glVertex3f(x0, 0.0,    z0);
    return;
};

// ============================================================================
// Draw entire maze as wireframe walls
// ============================================================================

def draw_maze(int wall_tex) -> void
{
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, wall_tex);
    glColor3f(1.0, 1.0, 1.0);
    glBegin(GL_QUADS);

    int r, c;
    float x0, x1, z0, z1;
    r = 0;
    while (r < MAZE_H)
    {
        c = 0;
        while (c < MAZE_W)
        {
            x0 = (float)c       * CELL_SIZE;
            x1 = (float)(c + 1) * CELL_SIZE;
            z0 = (float)r       * CELL_SIZE;
            z1 = (float)(r + 1) * CELL_SIZE;

            if (has_north(r, c)) { draw_wall_seg(x0, z0, x1, z0); };
            if (has_east(r, c))  { draw_wall_seg(x1, z0, x1, z1); };
            // South and West are drawn by neighbour cells to avoid duplicates,
            // except on the border row/col.
            if (r == MAZE_H - 1) { if (has_south(r, c)) { draw_wall_seg(x0, z1, x1, z1); }; };
            if (c == 0)          { if (has_west(r, c))  { draw_wall_seg(x0, z0, x0, z1); }; };

            c = c + 1;
        };
        r = r + 1;
    };

    glEnd();
    glDisable(GL_TEXTURE_2D);
    return;
};

// ============================================================================
// Draw the ground plane across the whole maze
// ============================================================================

def draw_floor() -> void
{
    float total = (float)MAZE_W * CELL_SIZE;
    glColor3f(0.15, 0.15, 0.15);
    glBegin(GL_QUADS);
        glVertex3f(0.0,   0.0, 0.0);
        glVertex3f(total, 0.0, 0.0);
        glVertex3f(total, 0.0, total);
        glVertex3f(0.0,   0.0, total);
    glEnd();
    return;
};


// ============================================================================
// Check if moving one cell in a direction is blocked by a wall.
// dir: 0=North, 1=East, 2=South, 3=West
// ============================================================================

def wall_ahead(int r, int c, int dir) -> bool
{
    if (dir == 0) { return has_north(r, c); };
    if (dir == 1) { return has_east(r, c);  };
    if (dir == 2) { return has_south(r, c); };
    return has_west(r, c);
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("Maze Demo - ESC to quit\0", WIN_W, WIN_H, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    GLContext gl(win.device_context);
    gl.load_extensions();

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);

    int wall_tex = load_png_texture("brick.png\0");

    init_maze_walls();

    // ---- Camera state ----
    // Position is always moving toward the center of the next cell.
    // dir: 0=North(-Z), 1=East(+X), 2=South(+Z), 3=West(-X)
    float cam_x = cell_cx(5);
    float cam_z = cell_cz(1);
    int   cam_dir = 0;           // start facing North
    int   cam_cell_r = 1;
    int   cam_cell_c = 5;

    // Target cell the camera is currently moving toward
    int   tgt_r = 0;
    int   tgt_c = 5;

    float move_speed = 0.05;

    // Smooth turn state
    // is_turning: 1 while rotating, 0 while moving forward
    int   is_turning = 0;
    float turn_yaw_start = 0.0;   // yaw at turn begin (dir=0 North)
    float turn_yaw_end   = 0.0;   // yaw to rotate toward
    float turn_progress  = 0.0;   // 0.0 .. 1.0
    float turn_speed     = 0.04;  // fraction of 90-deg turn per frame

    // Hoisted loop vars
    float cam_yaw, fwd_x, fwd_z, tgt_x, tgt_z, dx, dz, dist, step, aspect;
    float dir_yaw;
    int   cur_w, cur_h, turn, try_dir, next_tgt_r, next_tgt_c;
    RECT  client_rect;
    Matrix4 proj;
    Matrix4 view;
    GLVec3 eye;
    GLVec3 lookat;
    GLVec3 up;
    up.x = 0.0;
    up.y = 1.0;
    up.z = 0.0;

    while (win.process_messages())
    {
        if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0) { PostQuitMessage(0); };

        // ---- Movement / Turning ----
        // Always recompute vector to current target
        tgt_x = cell_cx(tgt_c);
        tgt_z = cell_cz(tgt_r);
        dx = tgt_x - cam_x;
        dz = tgt_z - cam_z;
        dist = sqrt(dx * dx + dz * dz);

        if (is_turning == 1)
        {
            // Smoothly rotate toward turn_yaw_end
            turn_progress = turn_progress + turn_speed;
            if (turn_progress >= 1.0)
            {
                turn_progress = 1.0;
                is_turning = 0;
                // Turn finished - now commit the next target so movement begins
                tgt_r = next_tgt_r;
                tgt_c = next_tgt_c;
            };
            cam_yaw = turn_yaw_start + (turn_yaw_end - turn_yaw_start) * turn_progress;
            fwd_x = sin(cam_yaw);
            fwd_z = (0.0 - cos(cam_yaw));
        }
        else
        {
            // Arrived at target cell center
            if (dist <= move_speed)
            {
                cam_cell_r = tgt_r;
                cam_cell_c = tgt_c;

                // Find next open direction (prefer straight, then right, then left, then back)
                // try order: straight (0), right (+1), left (+3 mod 4), back (+2)
                try_dir = cam_dir;
                if (wall_ahead(cam_cell_r, cam_cell_c, try_dir) == true)
                {
                    // Try right
                    try_dir = (cam_dir + 1) % 4;
                    if (wall_ahead(cam_cell_r, cam_cell_c, try_dir) == true)
                    {
                        // Try left
                        try_dir = (cam_dir + 3) % 4;
                        if (wall_ahead(cam_cell_r, cam_cell_c, try_dir) == true)
                        {
                            // Only option is back
                            try_dir = (cam_dir + 2) % 4;
                        };
                    };
                };

                // Compute the yaw angles for smooth turn
                turn_yaw_start = turn_yaw_end;

                dir_yaw = 0.0;
                if (try_dir == 1) { dir_yaw =  PIF * 0.5; };
                if (try_dir == 2) { dir_yaw =  PIF; };
                if (try_dir == 3) { dir_yaw = (0.0 - PIF) * 0.5; };
                turn_yaw_end = dir_yaw;

                cam_dir = try_dir;

                // Stage next target cell - only committed once turn finishes
                next_tgt_r = cam_cell_r;
                next_tgt_c = cam_cell_c;
                if (cam_dir == 0) { next_tgt_r = cam_cell_r - 1; next_tgt_c = cam_cell_c; };
                if (cam_dir == 1) { next_tgt_r = cam_cell_r;     next_tgt_c = cam_cell_c + 1; };
                if (cam_dir == 2) { next_tgt_r = cam_cell_r + 1; next_tgt_c = cam_cell_c; };
                if (cam_dir == 3) { next_tgt_r = cam_cell_r;     next_tgt_c = cam_cell_c - 1; };

                // Begin turn if direction changed, otherwise commit target immediately
                if (turn_yaw_start != turn_yaw_end)
                {
                    is_turning = 1;
                    turn_progress = 0.0;
                }
                else
                {
                    tgt_r = next_tgt_r;
                    tgt_c = next_tgt_c;
                };
            }
            else
            {
                // Still moving toward target - step forward
                step = move_speed;
                if (step > dist) { step = dist; };
                cam_x = cam_x + (dx / dist) * step;
                cam_z = cam_z + (dz / dist) * step;
            };

            // Lookat always points directly at the target while moving
            fwd_x = dx / dist;
            fwd_z = dz / dist;
        };

        // ---- Dynamic viewport ----
        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_h == 0) { cur_h = 1; };
        aspect = (float)cur_w / (float)cur_h;

        glViewport(0, 0, cur_w, cur_h);
        gl.set_clear_color(0.0, 0.0, 0.0, 1.0);
        gl.clear();

        // ---- Projection ----
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        mat4_perspective(1.1, aspect, 0.05, 300.0, @proj);
        glLoadMatrixf(@proj.m[0]);

        // ---- View ----
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();

        eye.x = cam_x;
        eye.y = EYE_H;
        eye.z = cam_z;

        lookat.x = cam_x + fwd_x;
        lookat.y = EYE_H;
        lookat.z = cam_z + fwd_z;

        mat4_lookat(@eye, @lookat, @up, @view);
        glLoadMatrixf(@view.m[0]);

        // ---- Draw scene ----
        draw_floor();
        draw_maze(wall_tex);

        gl.present();
        Sleep(16);
    };

    gl.__exit();
    win.__exit();

    return 0;
};

