// graph_3D_3_dx.fx - 16 Panel 3D Graph Demo (DirectX 11)
//
// Identical scene to graph_3D_3_gl.fx, rewritten for D3D11.
//
// Rendering approach:
//   - One dynamic vertex buffer (DX_VB_CAP float3 vertices) mapped each frame.
//   - CPU fills vertices for all 16 panels sequentially; per-panel draw calls
//     are flushed by setting the scissor rect and viewport before each panel,
//     then issuing dx_draw() for the accumulated geometry.
//   - Minimal VS+PS compiled at startup via D3DCompile from embedded HLSL.
//     VS applies a per-draw MVP constant buffer; PS outputs a flat color.
//   - Line topology (D3D11_PRIMITIVE_TOPOLOGY_LINELIST) for box/grid/axes/
//     surface/bars; point topology (POINTLIST) for scatter.
//
// Build:
//   fxc graph_3D_3_dx.fx -o graph_3D_3_dx.exe
// ============================================================================

#import <standard.fx>, <math.fx>, <vectors.fx>, <matrices.fx>, <windows.fx>, <directx.fx>;

using standard::io::console,
      standard::system::windows,
      standard::math,
      standard::vectors,
      DirectX;

// ============================================================================
// LAYOUT  (identical to GL version)
// ============================================================================

const int COLS     = 4;
const int ROWS     = 4;
const int CELL     = 200;
const int GAP      = 30;
const int WIN_SIZE = COLS * CELL + (COLS + 1) * GAP;   // 950

const int CURVE_N  = 80;
const int SURF_N   = 12;
const int BAR_N    = 5;

// Maximum vertices the dynamic VB can hold per flush
const int DX_VB_CAP = 65536;

// ============================================================================
// GRAPH3D  (minimal struct - mirrors the fields used from redgraphing)
// ============================================================================

struct Graph3D
{
    float cx, cy,
          fov, cam_z,
          rot_x, rot_y, rot_z,
          x_min, x_max,
          y_min, y_max,
          z_min, z_max,
          scale;
};

// ============================================================================
// VERTEX  - float3 position only (color goes in cbuffer)
// ============================================================================

struct DXVert
{
    float x, y, z;
};

// ============================================================================
// CONSTANT BUFFER (slot b0)
// MVP matrix + flat RGBA color.
// Must be 16-byte aligned; pad to 128 bytes (4x4 float matrix = 64 + float4 = 16).
// ============================================================================

struct DXCBuffer
{
    float mvp00, mvp01, mvp02, mvp03,
          mvp10, mvp11, mvp12, mvp13,
          mvp20, mvp21, mvp22, mvp23,
          mvp30, mvp31, mvp32, mvp33,
          col_r, col_g, col_b, col_a;
};

// ============================================================================
// HLSL SOURCE (embedded as byte strings)
// ============================================================================

// Vertex shader: transforms position by MVP, passes through
byte* VS_SRC =
    "cbuffer CB : register(b0)
{
    float4x4 gMVP;
    float4   gColor;
};
float4 main(float3 pos : POSITION) : SV_Position
{
    return mul(gMVP, float4(pos, 1.0));
};
\0";

// Pixel shader: outputs flat color from cbuffer
byte* PS_SRC =
    "cbuffer CB : register(b0)
{
    float4x4 gMVP;
    float4   gColor;
};
float4 main() : SV_Target
{
    return gColor;
};
\0";

// ============================================================================
// MATH HELPERS
// ============================================================================

const float PIF = 3.14159265358979323846f;

// Normalize a data value to [-0.5, 0.5] * scale (same as GL version)
def gnorm(float val, float lo, float hi, float sc) -> float
{
    float range = hi - lo;
    if (range == 0.0) { return 0.0; };
    return ((val - lo) / range - 0.5) * sc;
};

def dword_to_r(DWORD c) -> float { return (float)((c)        & 0xFF) / 255.0; };
def dword_to_g(DWORD c) -> float { return (float)(((c) >> 8)  & 0xFF) / 255.0; };
def dword_to_b(DWORD c) -> float { return (float)(((c) >> 16) & 0xFF) / 255.0; };

// ============================================================================
// CPU-SIDE 4x4 FLOAT MATRIX HELPERS
// Row-major, matching HLSL float4x4 layout (row-major multiply).
// ============================================================================

struct FMat4
{
    float m00, m01, m02, m03,
          m10, m11, m12, m13,
          m20, m21, m22, m23,
          m30, m31, m32, m33;
};

def fmat4_identity(FMat4* m) -> void
{
    m.m00 = 1.0; m.m01 = 0.0; m.m02 = 0.0; m.m03 = 0.0;
    m.m10 = 0.0; m.m11 = 1.0; m.m12 = 0.0; m.m13 = 0.0;
    m.m20 = 0.0; m.m21 = 0.0; m.m22 = 1.0; m.m23 = 0.0;
    m.m30 = 0.0; m.m31 = 0.0; m.m32 = 0.0; m.m33 = 1.0;
    return;
};

def fmat4_mul(FMat4* a, FMat4* b, FMat4* out) -> void
{
    out.m00 = a.m00*b.m00 + a.m01*b.m10 + a.m02*b.m20 + a.m03*b.m30;
    out.m01 = a.m00*b.m01 + a.m01*b.m11 + a.m02*b.m21 + a.m03*b.m31;
    out.m02 = a.m00*b.m02 + a.m01*b.m12 + a.m02*b.m22 + a.m03*b.m32;
    out.m03 = a.m00*b.m03 + a.m01*b.m13 + a.m02*b.m23 + a.m03*b.m33;

    out.m10 = a.m10*b.m00 + a.m11*b.m10 + a.m12*b.m20 + a.m13*b.m30;
    out.m11 = a.m10*b.m01 + a.m11*b.m11 + a.m12*b.m21 + a.m13*b.m31;
    out.m12 = a.m10*b.m02 + a.m11*b.m12 + a.m12*b.m22 + a.m13*b.m32;
    out.m13 = a.m10*b.m03 + a.m11*b.m13 + a.m12*b.m23 + a.m13*b.m33;

    out.m20 = a.m20*b.m00 + a.m21*b.m10 + a.m22*b.m20 + a.m23*b.m30;
    out.m21 = a.m20*b.m01 + a.m21*b.m11 + a.m22*b.m21 + a.m23*b.m31;
    out.m22 = a.m20*b.m02 + a.m21*b.m12 + a.m22*b.m22 + a.m23*b.m32;
    out.m23 = a.m20*b.m03 + a.m21*b.m13 + a.m22*b.m23 + a.m23*b.m33;

    out.m30 = a.m30*b.m00 + a.m31*b.m10 + a.m32*b.m20 + a.m33*b.m30;
    out.m31 = a.m30*b.m01 + a.m31*b.m11 + a.m32*b.m21 + a.m33*b.m31;
    out.m32 = a.m30*b.m02 + a.m31*b.m12 + a.m32*b.m22 + a.m33*b.m32;
    out.m33 = a.m30*b.m03 + a.m31*b.m13 + a.m32*b.m23 + a.m33*b.m33;
    return;
};

// Perspective projection (row-major, right-handed, maps Z to [0,1] for D3D)
def fmat4_perspective(float fov_y, float aspect, float near_z, float far_z, FMat4* out) -> void
{
    float f = 1.0 / tan(fov_y * 0.5);
    fmat4_identity(out);
    out.m00 = f / aspect;
    out.m11 = f;
    out.m22 = far_z / (near_z - far_z);
    out.m23 = -1.0;
    out.m32 = (near_z * far_z) / (near_z - far_z);
    out.m33 = 0.0;
    return;
};

// Look-at view matrix (row-major)
def fmat4_lookat(float ex, float ey, float ez,
                 float tx, float ty, float tz,
                 FMat4* out) -> void
{
    float fx, fy, fz, ux, uy, uz, rx, ry, rz, len;

    fx = tx - ex; fy = ty - ey; fz = tz - ez;
    len = sqrt(fx*fx + fy*fy + fz*fz);
    if (len > 0.0) { fx /= len; fy /= len; fz /= len; };

    // world up = (0,1,0)
    rx = fy*0.0 - fz*1.0;   // cross(f, up).x  -- but up=(0,1,0)
    ry = fz*0.0 - fx*0.0;
    rz = fx*1.0 - fy*0.0;
    // cross(f, up) = (fy*0 - fz*1, fz*0 - fx*0, fx*1 - fy*0) = (-fz, 0, fx)
    rx = -fz; ry = 0.0; rz = fx;
    len = sqrt(rx*rx + ry*ry + rz*rz);
    if (len > 0.0) { rx /= len; ry /= len; rz /= len; };

    ux = ry*fz - rz*fy;
    uy = rz*fx - rx*fz;
    uz = rx*fy - ry*fx;

    out.m00 = rx;           out.m01 = ux;           out.m02 = -fx;          out.m03 = 0.0;
    out.m10 = ry;           out.m11 = uy;           out.m12 = -fy;          out.m13 = 0.0;
    out.m20 = rz;           out.m21 = uz;           out.m22 = -fz;          out.m23 = 0.0;
    out.m30 = -(rx*ex + ry*ey + rz*ez);
    out.m31 = -(ux*ex + uy*ey + uz*ez);
    out.m32 =   fx*ex + fy*ey + fz*ez;
    out.m33 = 1.0;
    return;
};

// Rotation around Y axis
def fmat4_rot_y(float angle, FMat4* out) -> void
{
    float c = cos(angle), s = sin(angle);
    fmat4_identity(out);
    out.m00 =  c; out.m02 = s;
    out.m20 = -s; out.m22 = c;
    return;
};

// Rotation around X axis
def fmat4_rot_x(float angle, FMat4* out) -> void
{
    float c = cos(angle), s = sin(angle);
    fmat4_identity(out);
    out.m11 = c; out.m12 = -s;
    out.m21 = s; out.m22 =  c;
    return;
};

// Rotation around Z axis
def fmat4_rot_z(float angle, FMat4* out) -> void
{
    float c = cos(angle), s = sin(angle);
    fmat4_identity(out);
    out.m00 =  c; out.m01 = -s;
    out.m10 =  s; out.m11 =  c;
    return;
};

// ============================================================================
// VERTEX BUFFER STATE  (global write cursor, filled by emit_* helpers)
// ============================================================================

global DXVert* g_vb_cpu  = (DXVert*)0;   // mapped write pointer
global int     g_vb_count = 0;            // vertices written so far this flush

def emit_vertex(float x, float y, float z) -> void
{
    if (g_vb_count >= DX_VB_CAP) { return; };
    g_vb_cpu[g_vb_count].x = x;
    g_vb_cpu[g_vb_count].y = y;
    g_vb_cpu[g_vb_count].z = z;
    g_vb_count = g_vb_count + 1;
    return;
};

// ============================================================================
// PANEL SETUP (identical logic to GL version)
// ============================================================================

def setup_panel(Graph3D* g, int col, int row) -> void
{
    g.cx    = (float)(GAP + col * (CELL + GAP) + CELL / 2);
    g.cy    = (float)(GAP + row * (CELL + GAP) + CELL / 2);
    g.fov   = 220.0;
    g.cam_z = 9.0;
    g.rot_z = 0.0;
    g.x_min = 0.0; g.x_max = 1.0;
    g.y_min = 0.0; g.y_max = 1.0;
    g.z_min = 0.0; g.z_max = 1.0;
    g.scale = 3.75;
    return;
};

// ============================================================================
// SET UP PER-PANEL MVP + VIEWPORT + SCISSOR
// Returns the composed MVP matrix (to be uploaded to cbuffer before draw).
// D3D viewport Y origin is top-left (same as window), no flip needed.
// ============================================================================

def setup_panel_dx(Graph3D* g,
                   ID3D11DeviceContext ctx,
                   FMat4* out_mvp) -> void
{
    // Viewport for this panel
    int px = (int)g.cx - CELL / 2;
    int py = (int)g.cy - CELL / 2;

    D3D11_VIEWPORT vp;
    vp.TopLeftX = (float)px;
    vp.TopLeftY = (float)py;
    vp.Width    = (float)CELL;
    vp.Height   = (float)CELL;
    vp.MinDepth = 0.0;
    vp.MaxDepth = 1.0;
    dx_rs_set_viewports(ctx, 1, @vp);

    // Scissor rect
    D3D11_RECT sr;
    sr.left   = (LONG)px;
    sr.top    = (LONG)py;
    sr.right  = (LONG)(px + CELL);
    sr.bottom = (LONG)(py + CELL);
    {
        dx_rs_set_scissorrects(ctx, 1, @sr);
    };

    // Perspective projection
    FMat4 proj;
    fmat4_perspective(0.872665, 1.0, 0.1, 100.0, @proj);

    // View: camera at (0, 0, cam_z) looking at origin
    FMat4 view;
    fmat4_lookat(0.0, 0.0, g.cam_z, 0.0, 0.0, 0.0, @view);

    // Model: rot_x then rot_y then rot_z
    FMat4 rx, ry, rz, rxy, model;
    fmat4_rot_x(g.rot_x, @rx);
    fmat4_rot_y(g.rot_y, @ry);
    fmat4_rot_z(g.rot_z, @rz);
    fmat4_mul(@rx, @ry, @rxy);
    fmat4_mul(@rxy, @rz, @model);

    // MVP = proj * view * model  (row-major: right-to-left application)
    FMat4 vm, pvm;
    fmat4_mul(@view, @model, @vm);
    fmat4_mul(@proj, @vm, out_mvp);

    return;
};

// ============================================================================
// UPLOAD CBUFFER + FLUSH DRAW
// Maps the cbuffer, writes MVP and color, then issues a draw call.
// ============================================================================

def flush_draw(ID3D11DeviceContext ctx,
               ID3D11Buffer cbuf,
               ID3D11Buffer vbuf,
               FMat4* mvp,
               float r, float g, float b,
               D3D_PRIMITIVE_TOPOLOGY topo,
               int vert_count) -> void
{
    if (vert_count == 0) { return; };

    // Update cbuffer
    DXCBuffer cb;
    cb.mvp00 = mvp.m00; cb.mvp01 = mvp.m01; cb.mvp02 = mvp.m02; cb.mvp03 = mvp.m03;
    cb.mvp10 = mvp.m10; cb.mvp11 = mvp.m11; cb.mvp12 = mvp.m12; cb.mvp13 = mvp.m13;
    cb.mvp20 = mvp.m20; cb.mvp21 = mvp.m21; cb.mvp22 = mvp.m22; cb.mvp23 = mvp.m23;
    cb.mvp30 = mvp.m30; cb.mvp31 = mvp.m31; cb.mvp32 = mvp.m32; cb.mvp33 = mvp.m33;
    cb.col_r = r; cb.col_g = g; cb.col_b = b; cb.col_a = 1.0;

    D3D11_MAPPED_SUBRESOURCE ms;
    dx_map(ctx, (ID3D11Resource)cbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
    if (ms.pData != (void*)0)
    {
        DXCBuffer* dst = (DXCBuffer*)ms.pData;
        *dst = cb;
    };
    dx_unmap(ctx, (ID3D11Resource)cbuf, 0);

    // Set topology and draw
    dx_ia_set_topology(ctx, topo);
    dx_draw(ctx, (uint)vert_count, 0);

    return;
};

// ============================================================================
// GEOMETRY EMITTERS  (fill g_vb_cpu, matching gl_draw_* semantics)
// All return vertex count written.
// ============================================================================

def emit_box(Graph3D* g) -> int
{
    float x0, x1, y0, y1, z0, z1;
    int start = g_vb_count;

    x0 = gnorm(g.x_min, g.x_min, g.x_max, g.scale);
    x1 = gnorm(g.x_max, g.x_min, g.x_max, g.scale);
    y0 = gnorm(g.y_min, g.y_min, g.y_max, g.scale);
    y1 = gnorm(g.y_max, g.y_min, g.y_max, g.scale);
    z0 = gnorm(g.z_min, g.z_min, g.z_max, g.scale);
    z1 = gnorm(g.z_max, g.z_min, g.z_max, g.scale);

    // Bottom face
    emit_vertex(x0,y0,z0); emit_vertex(x1,y0,z0);
    emit_vertex(x1,y0,z0); emit_vertex(x1,y0,z1);
    emit_vertex(x1,y0,z1); emit_vertex(x0,y0,z1);
    emit_vertex(x0,y0,z1); emit_vertex(x0,y0,z0);
    // Top face
    emit_vertex(x0,y1,z0); emit_vertex(x1,y1,z0);
    emit_vertex(x1,y1,z0); emit_vertex(x1,y1,z1);
    emit_vertex(x1,y1,z1); emit_vertex(x0,y1,z1);
    emit_vertex(x0,y1,z1); emit_vertex(x0,y1,z0);
    // Verticals
    emit_vertex(x0,y0,z0); emit_vertex(x0,y1,z0);
    emit_vertex(x1,y0,z0); emit_vertex(x1,y1,z0);
    emit_vertex(x1,y0,z1); emit_vertex(x1,y1,z1);
    emit_vertex(x0,y0,z1); emit_vertex(x0,y1,z1);

    return g_vb_count - start;
};

def emit_grid(Graph3D* g, int x_divs, int z_divs) -> int
{
    float y0, nx0, nx1, nz0, nz1, fx, nx, fz, nz;
    int i, start = g_vb_count;

    y0  = gnorm(g.y_min, g.y_min, g.y_max, g.scale);
    nz0 = gnorm(g.z_min, g.z_min, g.z_max, g.scale);
    nz1 = gnorm(g.z_max, g.z_min, g.z_max, g.scale);
    nx0 = gnorm(g.x_min, g.x_min, g.x_max, g.scale);
    nx1 = gnorm(g.x_max, g.x_min, g.x_max, g.scale);

    i = 0;
    while (i <= x_divs)
    {
        fx = g.x_min + (g.x_max - g.x_min) * (float)i / (float)x_divs;
        nx = gnorm(fx, g.x_min, g.x_max, g.scale);
        emit_vertex(nx, y0, nz0);
        emit_vertex(nx, y0, nz1);
        i = i + 1;
    };

    i = 0;
    while (i <= z_divs)
    {
        fz = g.z_min + (g.z_max - g.z_min) * (float)i / (float)z_divs;
        nz = gnorm(fz, g.z_min, g.z_max, g.scale);
        emit_vertex(nx0, y0, nz);
        emit_vertex(nx1, y0, nz);
        i = i + 1;
    };

    return g_vb_count - start;
};

def emit_axes(Graph3D* g) -> int
{
    float x0, x1, y0, y1, z0, z1;
    int start = g_vb_count;

    x0 = gnorm(g.x_min, g.x_min, g.x_max, g.scale);
    x1 = gnorm(g.x_max, g.x_min, g.x_max, g.scale);
    y0 = gnorm(g.y_min, g.y_min, g.y_max, g.scale);
    y1 = gnorm(g.y_max, g.y_min, g.y_max, g.scale);
    z0 = gnorm(g.z_min, g.z_min, g.z_max, g.scale);
    z1 = gnorm(g.z_max, g.z_min, g.z_max, g.scale);

    emit_vertex(x0,y0,z0); emit_vertex(x1,y0,z0);
    emit_vertex(x0,y0,z0); emit_vertex(x0,y1,z0);
    emit_vertex(x0,y0,z0); emit_vertex(x0,y0,z1);

    return g_vb_count - start;
};

def emit_line(Graph3D* g, float* xs, float* ys, float* zs, int count) -> int
{
    int i, start = g_vb_count;
    i = 0;
    while (i < count - 1)
    {
        emit_vertex(gnorm(xs[i],   g.x_min, g.x_max, g.scale),
                    gnorm(ys[i],   g.y_min, g.y_max, g.scale),
                    gnorm(zs[i],   g.z_min, g.z_max, g.scale));
        emit_vertex(gnorm(xs[i+1], g.x_min, g.x_max, g.scale),
                    gnorm(ys[i+1], g.y_min, g.y_max, g.scale),
                    gnorm(zs[i+1], g.z_min, g.z_max, g.scale));
        i = i + 1;
    };
    return g_vb_count - start;
};

def emit_scatter(Graph3D* g, float* xs, float* ys, float* zs, int count) -> int
{
    int i, start = g_vb_count;
    i = 0;
    while (i < count)
    {
        emit_vertex(gnorm(xs[i], g.x_min, g.x_max, g.scale),
                    gnorm(ys[i], g.y_min, g.y_max, g.scale),
                    gnorm(zs[i], g.z_min, g.z_max, g.scale));
        i = i + 1;
    };
    return g_vb_count - start;
};

def emit_surface(Graph3D* g, float* xs, float* ys, float* zs, int x_count, int y_count) -> int
{
    int row, col_i, start = g_vb_count;
    float z00, z01, z10;

    row = 0;
    while (row < y_count)
    {
        col_i = 0;
        while (col_i < x_count)
        {
            z00 = zs[row * x_count + col_i];

            if (col_i < x_count - 1)
            {
                z01 = zs[row * x_count + col_i + 1];
                emit_vertex(gnorm(xs[col_i],     g.x_min, g.x_max, g.scale),
                            gnorm(ys[row],        g.y_min, g.y_max, g.scale),
                            gnorm(z00,            g.z_min, g.z_max, g.scale));
                emit_vertex(gnorm(xs[col_i + 1], g.x_min, g.x_max, g.scale),
                            gnorm(ys[row],        g.y_min, g.y_max, g.scale),
                            gnorm(z01,            g.z_min, g.z_max, g.scale));
            };

            if (row < y_count - 1)
            {
                z10 = zs[(row + 1) * x_count + col_i];
                emit_vertex(gnorm(xs[col_i], g.x_min, g.x_max, g.scale),
                            gnorm(ys[row],    g.y_min, g.y_max, g.scale),
                            gnorm(z00,        g.z_min, g.z_max, g.scale));
                emit_vertex(gnorm(xs[col_i], g.x_min, g.x_max, g.scale),
                            gnorm(ys[row+1],  g.y_min, g.y_max, g.scale),
                            gnorm(z10,        g.z_min, g.z_max, g.scale));
            };

            col_i = col_i + 1;
        };
        row = row + 1;
    };
    return g_vb_count - start;
};

def emit_bars(Graph3D* g, float* xs, float* ys, float* zs, int count) -> int
{
    float y_base, nx, ny, nz;
    float cap = 0.06;
    int i, start = g_vb_count;

    y_base = gnorm(g.y_min, g.y_min, g.y_max, g.scale);

    i = 0;
    while (i < count)
    {
        nx = gnorm(xs[i], g.x_min, g.x_max, g.scale);
        ny = gnorm(ys[i], g.y_min, g.y_max, g.scale);
        nz = gnorm(zs[i], g.z_min, g.z_max, g.scale);

        emit_vertex(nx, y_base, nz); emit_vertex(nx, ny, nz);
        emit_vertex(nx - cap, ny, nz); emit_vertex(nx + cap, ny, nz);
        emit_vertex(nx, ny, nz - cap); emit_vertex(nx, ny, nz + cap);

        i = i + 1;
    };
    return g_vb_count - start;
};

// ============================================================================
// PANEL DRAW HELPER
// Maps VB, emits geometry, unmaps, then calls flush_draw.
// ============================================================================

def panel_draw_lines(Graph3D* g,
                     ID3D11DeviceContext ctx,
                     ID3D11Buffer cbuf,
                     ID3D11Buffer vbuf,
                     FMat4* mvp,
                     float r, float gv, float b,
                     int emit_result) -> void
{
    // VB was already mapped before emit calls; just flush
    flush_draw(ctx, cbuf, vbuf, mvp, r, gv, b,
               D3D11_PRIMITIVE_TOPOLOGY_LINELIST, emit_result);
    return;
};

def panel_draw_points(Graph3D* g,
                      ID3D11DeviceContext ctx,
                      ID3D11Buffer cbuf,
                      ID3D11Buffer vbuf,
                      FMat4* mvp,
                      float r, float gv, float b,
                      int emit_result) -> void
{
    flush_draw(ctx, cbuf, vbuf, mvp, r, gv, b,
               D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, emit_result);
    return;
};

// ============================================================================
// DATA GENERATORS  (identical math to GL version)
// ============================================================================

def auto_range_z(Graph3D* g, float* zs, int count, float pad) -> void
{
    float lo, hi, range;
    int i;
    lo = zs[0]; hi = zs[0];
    i = 1;
    while (i < count)
    {
        if (zs[i] < lo) { lo = zs[i]; };
        if (zs[i] > hi) { hi = zs[i]; };
        i = i + 1;
    };
    range = hi - lo;
    g.z_min = lo - range * pad;
    g.z_max = hi + range * pad;
    return;
};

def auto_range3d(Graph3D* g, float* xs, float* ys, float* zs, int count, float pad) -> void
{
    float lx, hx, ly, hy, lz, hz, rx, ry, rz;
    int i;
    lx = xs[0]; hx = xs[0];
    ly = ys[0]; hy = ys[0];
    lz = zs[0]; hz = zs[0];
    i = 1;
    while (i < count)
    {
        if (xs[i] < lx) { lx = xs[i]; };
        if (xs[i] > hx) { hx = xs[i]; };
        if (ys[i] < ly) { ly = ys[i]; };
        if (ys[i] > hy) { hy = ys[i]; };
        if (zs[i] < lz) { lz = zs[i]; };
        if (zs[i] > hz) { hz = zs[i]; };
        i = i + 1;
    };
    rx = hx - lx; ry = hy - ly; rz = hz - lz;
    g.x_min = lx - rx*pad; g.x_max = hx + rx*pad;
    g.y_min = ly - ry*pad; g.y_max = hy + ry*pad;
    g.z_min = lz - rz*pad; g.z_max = hz + rz*pad;
    return;
};

def gen_ripple(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i, j;
    float fx, fz, r, t;
    i = 0;
    while (i < n)
    {
        j = 0;
        while (j < n)
        {
            fx = (float)i / (float)(n - 1);
            fz = (float)j / (float)(n - 1);
            xs[i] = fx;
            ys[j] = fz;
            r = sqrt((fx - 0.5) * (fx - 0.5) + (fz - 0.5) * (fz - 0.5));
            t = r * 18.0 - phase * 4.0;
            zs[i * n + j] = 0.5 + 0.45 * sin(t) * (1.0 - r);
            j = j + 1;
        };
        i = i + 1;
    };
    return;
};

def gen_saddle(float* xs, float* ys, float* zs, int n) -> void
{
    int i, j;
    float fx, fz;
    i = 0;
    while (i < n)
    {
        j = 0;
        while (j < n)
        {
            fx = (float)i / (float)(n - 1);
            fz = (float)j / (float)(n - 1);
            xs[i] = fx;
            ys[j] = fz;
            zs[i * n + j] = 0.5 + 2.0 * ((fx - 0.5) * (fx - 0.5) - (fz - 0.5) * (fz - 0.5));
            j = j + 1;
        };
        i = i + 1;
    };
    return;
};

def gen_peaks(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i, j;
    float fx, fz, x, z;
    i = 0;
    while (i < n)
    {
        j = 0;
        while (j < n)
        {
            fx = (float)i / (float)(n - 1);
            fz = (float)j / (float)(n - 1);
            xs[i] = fx;
            ys[j] = fz;
            x = (fx - 0.5) * 6.0;
            z = (fz - 0.5) * 6.0;
            zs[i * n + j] = 0.5 + 0.2 * (3.0*(1.0-x)*(1.0-x)*exp(-(x*x)-(z+1.0)*(z+1.0))
                           - 10.0*(x/5.0 - x*x*x - z*z*z*z*z)*exp(-x*x-z*z)
                           - (1.0/3.0)*exp(-(x+1.0)*(x+1.0)-z*z)) * cos(phase * 0.3);
            j = j + 1;
        };
        i = i + 1;
    };
    return;
};

def gen_torus_surf(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i, j;
    float u, v, R, r2, x, y, z;
    R = 0.35; r2 = 0.15;
    i = 0;
    while (i < n)
    {
        j = 0;
        while (j < n)
        {
            u = (float)i / (float)(n - 1) * 2.0 * PIF + phase;
            v = (float)j / (float)(n - 1) * 2.0 * PIF;
            x = (R + r2 * cos(v)) * cos(u);
            y = (R + r2 * cos(v)) * sin(u);
            z = r2 * sin(v);
            xs[i] = x + 0.5;
            ys[j] = y + 0.5;
            zs[i * n + j] = z + 0.5;
            j = j + 1;
        };
        i = i + 1;
    };
    return;
};

def gen_interference(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i, j;
    float fx, fz, d1, d2;
    i = 0;
    while (i < n)
    {
        j = 0;
        while (j < n)
        {
            fx = (float)i / (float)(n - 1);
            fz = (float)j / (float)(n - 1);
            xs[i] = fx;
            ys[j] = fz;
            d1 = sqrt((fx - 0.3) * (fx - 0.3) + (fz - 0.3) * (fz - 0.3));
            d2 = sqrt((fx - 0.7) * (fx - 0.7) + (fz - 0.7) * (fz - 0.7));
            zs[i * n + j] = 0.5 + 0.25 * (sin(d1 * 20.0 - phase * 3.0) + sin(d2 * 20.0 - phase * 2.5));
            j = j + 1;
        };
        i = i + 1;
    };
    return;
};

def gen_helix(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float t;
    i = 0;
    while (i < n)
    {
        t = (float)i / (float)(n - 1) * 4.0 * PIF + phase;
        xs[i] = 0.5 + 0.45 * cos(t);
        ys[i] = (float)i / (float)(n - 1);
        zs[i] = 0.5 + 0.45 * sin(t);
        i = i + 1;
    };
    return;
};

def gen_double_helix(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i, half;
    float t;
    half = n / 2;
    i = 0;
    while (i < half)
    {
        t = (float)i / (float)(half - 1) * 4.0 * PIF + phase;
        xs[i] = 0.5 + 0.4 * cos(t);
        ys[i] = (float)i / (float)(half - 1);
        zs[i] = 0.5 + 0.4 * sin(t);
        i = i + 1;
    };
    i = 0;
    while (i < half)
    {
        t = (float)i / (float)(half - 1) * 4.0 * PIF + phase + PIF;
        xs[half + i] = 0.5 + 0.4 * cos(t);
        ys[half + i] = (float)i / (float)(half - 1);
        zs[half + i] = 0.5 + 0.4 * sin(t);
        i = i + 1;
    };
    return;
};

def gen_knot_23(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float t;
    i = 0;
    while (i < n)
    {
        t = (float)i / (float)(n - 1) * 2.0 * PIF + phase;
        xs[i] = 0.5 + 0.4 * (cos(2.0*t) * (3.0 + cos(3.0*t))) / 6.0;
        ys[i] = 0.5 + 0.4 * (sin(2.0*t) * (3.0 + cos(3.0*t))) / 6.0;
        zs[i] = 0.5 + 0.4 * sin(3.0*t) / 3.0;
        i = i + 1;
    };
    return;
};

def gen_fig8(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float t;
    i = 0;
    while (i < n)
    {
        t = (float)i / (float)(n - 1) * 2.0 * PIF + phase;
        xs[i] = 0.5 + 0.4 * cos(t) / (1.0 + sin(t)*sin(t));
        ys[i] = 0.5 + 0.4 * sin(t) * cos(t) / (1.0 + sin(t)*sin(t));
        zs[i] = 0.5 + 0.4 * sin(t);
        i = i + 1;
    };
    return;
};

def gen_lissajous(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float t;
    i = 0;
    while (i < n)
    {
        t = (float)i / (float)(n - 1) * 2.0 * PIF;
        xs[i] = 0.5 + 0.45 * sin(3.0 * t + phase);
        ys[i] = 0.5 + 0.45 * sin(2.0 * t);
        zs[i] = 0.5 + 0.45 * sin(t + phase * 0.5);
        i = i + 1;
    };
    return;
};

def gen_sphere(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float u, v;
    i = 0;
    while (i < n)
    {
        u = (float)i / (float)(n - 1) * PIF;
        v = (float)i / (float)(n - 1) * 2.0 * PIF + phase;
        xs[i] = 0.5 + 0.45 * sin(u) * cos(v);
        ys[i] = 0.5 + 0.45 * cos(u);
        zs[i] = 0.5 + 0.45 * sin(u) * sin(v);
        i = i + 1;
    };
    return;
};

def gen_cone(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float t, h;
    i = 0;
    while (i < n)
    {
        t = (float)i / (float)(n - 1) * 4.0 * PIF + phase;
        h = (float)i / (float)(n - 1);
        xs[i] = 0.5 + h * 0.45 * cos(t);
        ys[i] = h;
        zs[i] = 0.5 + h * 0.45 * sin(t);
        i = i + 1;
    };
    return;
};

def gen_spiral_coil(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float t;
    i = 0;
    while (i < n)
    {
        t = (float)i / (float)(n - 1) * 6.0 * PIF + phase;
        xs[i] = 0.5 + (0.1 + 0.35 * (float)i / (float)(n-1)) * cos(t);
        ys[i] = (float)i / (float)(n - 1);
        zs[i] = 0.5 + (0.1 + 0.35 * (float)i / (float)(n-1)) * sin(t);
        i = i + 1;
    };
    return;
};

def gen_viviani(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float t;
    i = 0;
    while (i < n)
    {
        t = (float)i / (float)(n - 1) * 4.0 * PIF + phase;
        xs[i] = 0.5 + 0.45 * (1.0 + cos(t)) * 0.5;
        ys[i] = 0.5 + 0.45 * sin(t);
        zs[i] = 0.5 + 0.45 * sin(t * 0.5) * cos(t * 0.5);
        i = i + 1;
    };
    return;
};

def gen_cluster(float* xs, float* ys, float* zs, int n, float phase) -> void
{
    int i;
    float t, r2;
    i = 0;
    while (i < n)
    {
        t = (float)i * 0.37 + phase;
        r2 = 0.08 + 0.12 * (float)(i % 5) / 4.0;
        xs[i] = 0.5 + r2 * cos(t * 2.9);
        ys[i] = 0.5 + r2 * sin(t * 3.7);
        zs[i] = 0.5 + r2 * cos(t * 1.3) * sin(t);
        i = i + 1;
    };
    return;
};

def gen_bars(float* xs, float* ys, float* zs, int count, int dim, float phase) -> void
{
    int i, j, idx;
    float fx, fz;
    i = 0;
    while (i < dim)
    {
        j = 0;
        while (j < dim)
        {
            idx = i * dim + j;
            fx = (float)i / (float)(dim - 1);
            fz = (float)j / (float)(dim - 1);
            xs[idx] = fx;
            ys[idx] = 0.1 + 0.85 * (0.5 + 0.5 * sin(fx * 6.0 + phase) * cos(fz * 6.0 + phase * 0.7));
            zs[idx] = fz;
            j = j + 1;
        };
        i = i + 1;
    };
    return;
};

// ============================================================================
// MAIN
// ============================================================================

def main() -> int
{
    Window win("graph_3D_3_dx.fx - 16 Panel 3D Demo (DirectX 11)\0",
               WIN_SIZE, WIN_SIZE, CW_USEDEFAULT, CW_USEDEFAULT);
    SetForegroundWindow(win.handle);

    // ── D3D11 device + swap chain ─────────────────────────────────────────────
    DXContext dx(win.handle, WIN_SIZE, WIN_SIZE);

    // ── Compile shaders ───────────────────────────────────────────────────────
    ID3DBlob vs_blob = (ID3DBlob)0,
             ps_blob = (ID3DBlob)0,
             err_blob = (ID3DBlob)0;

    D3DCompile((void*)VS_SRC, (size_t)strlen((byte*)VS_SRC),
               (LPCSTR)0, (void*)0, (void*)0,
               "main\0", "vs_5_0\0", 0, 0, @vs_blob, @err_blob);
    if (err_blob != (ID3DBlob)0) { dx_release(err_blob); err_blob = (ID3DBlob)0; };

    D3DCompile((void*)PS_SRC, (size_t)strlen((byte*)PS_SRC),
               (LPCSTR)0, (void*)0, (void*)0,
               "main\0", "ps_5_0\0", 0, 0, @ps_blob, @err_blob);
    if (err_blob != (ID3DBlob)0) { dx_release(err_blob); err_blob = (ID3DBlob)0; };

    ID3D11VertexShader vs = (ID3D11VertexShader)0;
    ID3D11PixelShader  ps = (ID3D11PixelShader)0;

    dx_create_vs(dx.device, dx_blob_ptr(vs_blob), dx_blob_size(vs_blob), @vs);
    dx_create_ps(dx.device, dx_blob_ptr(ps_blob), dx_blob_size(ps_blob), @ps);

    // ── Input layout: float3 POSITION ────────────────────────────────────────
    D3D11_INPUT_ELEMENT_DESC ied;
    ied.SemanticName         = "POSITION\0";
    ied.SemanticIndex        = 0;
    ied.Format               = DXGI_FORMAT_R32G32B32_FLOAT;
    ied.InputSlot            = 0;
    ied.AlignedByteOffset    = 0;
    ied.InputSlotClass       = D3D11_INPUT_PER_VERTEX_DATA;
    ied.InstanceDataStepRate = 0;

    ID3D11InputLayout il = (ID3D11InputLayout)0;
    dx_create_inputlayout(dx.device, @ied, 1,
                          dx_blob_ptr(vs_blob), dx_blob_size(vs_blob), @il);

    dx_release(vs_blob);
    dx_release(ps_blob);

    // ── Dynamic vertex buffer ─────────────────────────────────────────────────
    D3D11_BUFFER_DESC vbd;
    vbd.ByteWidth           = (uint)(DX_VB_CAP * 12);  // float3 = 12 bytes
    vbd.StructureByteStride = 0;
    vbd.Usage               = D3D11_USAGE_DYNAMIC;
    vbd.BindFlags           = D3D11_BIND_VERTEX_BUFFER;
    vbd.CPUAccessFlags      = D3D11_CPU_ACCESS_WRITE;
    vbd.MiscFlags           = 0;

    ID3D11Buffer vbuf = (ID3D11Buffer)0;
    dx_create_buffer(dx.device, @vbd, (D3D11_SUBRESOURCE_DATA*)0, @vbuf);

    // ── Constant buffer ───────────────────────────────────────────────────────
    D3D11_BUFFER_DESC cbd;
    cbd.ByteWidth           = 128;   // DXCBuffer padded to 128 bytes (multiple of 16)
    cbd.StructureByteStride = 0;
    cbd.Usage               = D3D11_USAGE_DYNAMIC;
    cbd.BindFlags           = D3D11_BIND_CONSTANT_BUFFER;
    cbd.CPUAccessFlags      = D3D11_CPU_ACCESS_WRITE;
    cbd.MiscFlags           = 0;

    ID3D11Buffer cbuf = (ID3D11Buffer)0;
    dx_create_buffer(dx.device, @cbd, (D3D11_SUBRESOURCE_DATA*)0, @cbuf);

    // ── Rasterizer state: scissor enabled, no culling ─────────────────────────
    D3D11_RASTERIZER_DESC rsd;
    rsd.FillMode              = D3D11_FILL_SOLID;
    rsd.CullMode              = D3D11_CULL_NONE;
    rsd.FrontCounterClockwise = 0;
    rsd.DepthBias             = 0;
    rsd.DepthBiasClamp        = 0.0;
    rsd.SlopeScaledDepthBias  = 0.0;
    rsd.DepthClipEnable       = 1;
    rsd.ScissorEnable         = 1;
    rsd.MultisampleEnable     = 0;
    rsd.AntialiasedLineEnable = 1;

    ID3D11RasterizerState rs = (ID3D11RasterizerState)0;
    dx_create_rasterizer(dx.device, @rsd, @rs);

    // ── Bind pipeline state that doesn't change frame-to-frame ────────────────
    dx_vs_set_shader(dx.ctx, vs);
    dx_ps_set_shader(dx.ctx, ps);
    dx_ia_set_inputlayout(dx.ctx, il);
    dx_rs_set_state(dx.ctx, rs);
    dx_vs_set_cbuffers(dx.ctx, 0, 1, @cbuf);
    dx_ps_set_samplers(dx.ctx, 0, 0, (ID3D11SamplerState*)0);

    {
        uint stride = 12, offset = 0;
        dx_ia_set_vertexbuffers(dx.ctx, 0, 1, @vbuf, @stride, @offset);
    };

    // ── Data arrays ───────────────────────────────────────────────────────────
    int surf_cells = SURF_N * SURF_N,
        bar_cells  = BAR_N * BAR_N;

    float* sx = (float*)fmalloc((u64)SURF_N     * 4),
           sy = (float*)fmalloc((u64)SURF_N     * 4),
           sz = (float*)fmalloc((u64)surf_cells  * 4),
           ax = (float*)fmalloc((u64)CURVE_N    * 4),
           ay = (float*)fmalloc((u64)CURVE_N    * 4),
           az = (float*)fmalloc((u64)CURVE_N    * 4),
           bx = (float*)fmalloc((u64)bar_cells  * 4),
           by = (float*)fmalloc((u64)bar_cells  * 4),
           bz = (float*)fmalloc((u64)bar_cells  * 4);

    gen_saddle(sx, sy, sz, SURF_N);

    // ── Graph3D panels ────────────────────────────────────────────────────────
    Graph3D[16] g;
    int pi, col, row;

    pi = 0;
    while (pi < 16)
    {
        col = pi % COLS;
        row = pi / COLS;
        setup_panel(@g[pi], col, row);
        pi = pi + 1;
    };

    g[0].rot_x  = 0.50;  g[0].rot_y  = 0.30;
    g[1].rot_x  = 0.50;  g[1].rot_y  = 0.50;
    g[2].rot_x  = 0.45;  g[2].rot_y  = 0.40;
    g[3].rot_x  = 0.55;  g[3].rot_y  = 0.60;
    g[4].rot_x  = 0.40;  g[4].rot_y  = 0.30;
    g[5].rot_x  = 0.50;  g[5].rot_y  = 0.20;
    g[6].rot_x  = 0.45;  g[6].rot_y  = 0.70;
    g[7].rot_x  = 0.40;  g[7].rot_y  = 0.50;
    g[8].rot_x  = 0.55;  g[8].rot_y  = 0.40;
    g[9].rot_x  = 0.35;  g[9].rot_y  = 0.60;
    g[10].rot_x = 0.50;  g[10].rot_y = 0.30;
    g[11].rot_x = 0.45;  g[11].rot_y = 0.50;
    g[12].rot_x = 0.55;  g[12].rot_y = 0.40;
    g[13].rot_x = 0.40;  g[13].rot_y = 0.30;
    g[14].rot_x = 0.50;  g[14].rot_y = 0.60;
    g[15].rot_x = 0.45;  g[15].rot_y = 0.50;

    // ── Colors ────────────────────────────────────────────────────────────────
    DWORD col_bg   = RGB( 14,  14,  20);
    DWORD col_grid = RGB( 35,  35,  50);
    DWORD col_axis = RGB( 90,  90, 110);
    DWORD col_box  = RGB( 55,  55,  75);

    DWORD[16] colors;
    colors[0]  = RGB( 60, 180, 255);
    colors[1]  = RGB(255, 180,  40);
    colors[2]  = RGB(100, 255, 120);
    colors[3]  = RGB(220,  80, 255);
    colors[4]  = RGB(255,  80, 100);
    colors[5]  = RGB( 80, 220, 200);
    colors[6]  = RGB(255, 160,  60);
    colors[7]  = RGB(160, 100, 255);
    colors[8]  = RGB( 60, 255, 180);
    colors[9]  = RGB(255, 220,  60);
    colors[10] = RGB(255, 100, 180);
    colors[11] = RGB( 80, 160, 255);
    colors[12] = RGB(200, 255,  80);
    colors[13] = RGB(255, 140,  80);
    colors[14] = RGB(120, 255, 255);
    colors[15] = RGB(220, 180, 255);

    float phase = 0.0;

    // ── Helper macro: map VB, reset cursor ───────────────────────────────────
    // Used inline at the start of each panel's geometry block.

    while (win.process_messages())
    {
        // Rotate panels
        g[0].rot_y  += 0.009;
        g[1].rot_y  += 0.007;
        g[2].rot_y  += 0.008;
        g[3].rot_y  += 0.010;
        g[4].rot_y  += 0.011;
        g[5].rot_y  += 0.009;
        g[6].rot_y  += 0.008;
        g[7].rot_y  += 0.010;
        g[8].rot_y  += 0.007;
        g[9].rot_y  += 0.009;
        g[10].rot_y += 0.011;
        g[11].rot_y += 0.008;
        g[12].rot_y += 0.009;
        g[13].rot_y += 0.010;
        g[14].rot_y += 0.007;
        g[15].rot_y += 0.008;

        // Clear full window
        dx.bind_backbuffer();
        dx.clear(dword_to_r(col_bg), dword_to_g(col_bg), dword_to_b(col_bg), 1.0);

        FMat4 mvp;
        D3D11_MAPPED_SUBRESOURCE ms;
        int n_verts;

        // ── PANEL DRAW HELPER (inline) ────────────────────────────────────────
        // For each panel:
        //   1. setup_panel_dx → sets viewport+scissor, builds mvp
        //   2. Map VB, emit geometry, unmap, flush_draw
        //   3. Repeat for each geometry type in the panel

        // ---- 0: Sine ripple surface ----
        gen_ripple(sx, sy, sz, SURF_N, phase);
        setup_panel_dx(@g[0], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[0]); emit_grid(@g[0], 3, 3); n_verts = emit_axes(@g[0]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_surface(@g[0], sx, sy, sz, SURF_N, SURF_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[0]), dword_to_g(colors[0]), dword_to_b(colors[0]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);

        // ---- 1: Saddle surface ----
        gen_saddle(sx, sy, sz, SURF_N);
        setup_panel_dx(@g[1], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[1]); emit_grid(@g[1], 3, 3); emit_axes(@g[1]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_surface(@g[1], sx, sy, sz, SURF_N, SURF_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[1]), dword_to_g(colors[1]), dword_to_b(colors[1]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);

        // ---- 2: Peaks surface ----
        gen_peaks(sx, sy, sz, SURF_N, phase);
        auto_range_z(@g[2], sz, surf_cells, 0.05);
        setup_panel_dx(@g[2], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[2]); emit_grid(@g[2], 3, 3); emit_axes(@g[2]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_surface(@g[2], sx, sy, sz, SURF_N, SURF_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[2]), dword_to_g(colors[2]), dword_to_b(colors[2]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);

        // ---- 3: Torus surface ----
        gen_torus_surf(sx, sy, sz, SURF_N, phase);
        setup_panel_dx(@g[3], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[3]); emit_grid(@g[3], 3, 3); emit_axes(@g[3]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_surface(@g[3], sx, sy, sz, SURF_N, SURF_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[3]), dword_to_g(colors[3]), dword_to_b(colors[3]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);

        // ---- 4: Helix - line ----
        gen_helix(ax, ay, az, CURVE_N, phase);
        setup_panel_dx(@g[4], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[4]); emit_grid(@g[4], 3, 3); emit_axes(@g[4]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_line(@g[4], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[4]), dword_to_g(colors[4]), dword_to_b(colors[4]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);

        // ---- 5: Torus knot (2,3) - line + scatter ----
        gen_knot_23(ax, ay, az, CURVE_N, phase);
        auto_range3d(@g[5], ax, ay, az, CURVE_N, 0.05);
        setup_panel_dx(@g[5], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[5]); emit_grid(@g[5], 3, 3); emit_axes(@g[5]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_line(@g[5], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[5]), dword_to_g(colors[5]), dword_to_b(colors[5]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_scatter(@g[5], ax, ay, az, CURVE_N / 5);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[5]), dword_to_g(colors[5]), dword_to_b(colors[5]), D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, n_verts);

        // ---- 6: Figure-8 knot - line + scatter ----
        gen_fig8(ax, ay, az, CURVE_N, phase);
        auto_range3d(@g[6], ax, ay, az, CURVE_N, 0.05);
        setup_panel_dx(@g[6], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[6]); emit_grid(@g[6], 3, 3); emit_axes(@g[6]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_line(@g[6], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[6]), dword_to_g(colors[6]), dword_to_b(colors[6]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_scatter(@g[6], ax, ay, az, CURVE_N / 4);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[6]), dword_to_g(colors[6]), dword_to_b(colors[6]), D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, n_verts);

        // ---- 7: Lissajous - line + scatter ----
        gen_lissajous(ax, ay, az, CURVE_N, phase);
        setup_panel_dx(@g[7], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[7]); emit_grid(@g[7], 3, 3); emit_axes(@g[7]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_line(@g[7], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[7]), dword_to_g(colors[7]), dword_to_b(colors[7]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_scatter(@g[7], ax, ay, az, CURVE_N / 3);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[7]), dword_to_g(colors[7]), dword_to_b(colors[7]), D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, n_verts);

        // ---- 8: Sphere scatter ----
        gen_sphere(ax, ay, az, CURVE_N, phase);
        setup_panel_dx(@g[8], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[8]); emit_grid(@g[8], 3, 3); emit_axes(@g[8]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_scatter(@g[8], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[8]), dword_to_g(colors[8]), dword_to_b(colors[8]), D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, n_verts);

        // ---- 9: Cone scatter ----
        gen_cone(ax, ay, az, CURVE_N, phase);
        setup_panel_dx(@g[9], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[9]); emit_grid(@g[9], 3, 3); emit_axes(@g[9]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_scatter(@g[9], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[9]), dword_to_g(colors[9]), dword_to_b(colors[9]), D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, n_verts);

        // ---- 10: Double helix - line ----
        gen_double_helix(ax, ay, az, CURVE_N, phase);
        setup_panel_dx(@g[10], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[10]); emit_grid(@g[10], 3, 3); emit_axes(@g[10]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_line(@g[10], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[10]), dword_to_g(colors[10]), dword_to_b(colors[10]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);

        // ---- 11: Spiral coil - line + scatter ----
        gen_spiral_coil(ax, ay, az, CURVE_N, phase);
        setup_panel_dx(@g[11], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[11]); emit_grid(@g[11], 3, 3); emit_axes(@g[11]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_line(@g[11], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[11]), dword_to_g(colors[11]), dword_to_b(colors[11]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_scatter(@g[11], ax, ay, az, CURVE_N / 4);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[11]), dword_to_g(colors[11]), dword_to_b(colors[11]), D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, n_verts);

        // ---- 12: 3D bars ----
        gen_bars(bx, by, bz, bar_cells, BAR_N, phase);
        setup_panel_dx(@g[12], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[12]); emit_grid(@g[12], 3, 3); emit_axes(@g[12]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_bars(@g[12], bx, by, bz, bar_cells);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[12]), dword_to_g(colors[12]), dword_to_b(colors[12]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);

        // ---- 13: Viviani curve - line + scatter ----
        gen_viviani(ax, ay, az, CURVE_N, phase);
        setup_panel_dx(@g[13], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[13]); emit_grid(@g[13], 3, 3); emit_axes(@g[13]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_line(@g[13], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[13]), dword_to_g(colors[13]), dword_to_b(colors[13]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_scatter(@g[13], ax, ay, az, CURVE_N / 5);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[13]), dword_to_g(colors[13]), dword_to_b(colors[13]), D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, n_verts);

        // ---- 14: Cluster scatter ----
        gen_cluster(ax, ay, az, CURVE_N, phase);
        setup_panel_dx(@g[14], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[14]); emit_grid(@g[14], 3, 3); emit_axes(@g[14]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_scatter(@g[14], ax, ay, az, CURVE_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[14]), dword_to_g(colors[14]), dword_to_b(colors[14]), D3D11_PRIMITIVE_TOPOLOGY_POINTLIST, n_verts);

        // ---- 15: Wave interference surface ----
        gen_interference(sx, sy, sz, SURF_N, phase);
        setup_panel_dx(@g[15], dx.ctx, @mvp);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        emit_box(@g[15]); emit_grid(@g[15], 3, 3); emit_axes(@g[15]);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(col_box), dword_to_g(col_box), dword_to_b(col_box), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, g_vb_count);
        dx_map(dx.ctx, (ID3D11Resource)vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, @ms);
        g_vb_cpu = (DXVert*)ms.pData; g_vb_count = 0;
        n_verts = emit_surface(@g[15], sx, sy, sz, SURF_N, SURF_N);
        dx_unmap(dx.ctx, (ID3D11Resource)vbuf, 0);
        flush_draw(dx.ctx, cbuf, vbuf, @mvp, dword_to_r(colors[15]), dword_to_g(colors[15]), dword_to_b(colors[15]), D3D11_PRIMITIVE_TOPOLOGY_LINELIST, n_verts);

        phase += 0.025;
        if (phase > 2.0 * PIF) { phase -= 2.0 * PIF; };

        dx.present(1);
        Sleep(16);
    };

    // ── Cleanup ───────────────────────────────────────────────────────────────
    dx_release(rs);
    dx_release(cbuf);
    dx_release(vbuf);
    dx_release(il);
    dx_release(vs);
    dx_release(ps);
    dx.__exit();
    win.__exit();

    ffree((u64)sx); ffree((u64)sy); ffree((u64)sz);
    ffree((u64)ax); ffree((u64)ay); ffree((u64)az);
    ffree((u64)bx); ffree((u64)by); ffree((u64)bz);

    return 0;
};
