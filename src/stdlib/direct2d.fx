// Flux Direct2D Library
// Provides Direct2D context setup and rendering helpers via COM vtable dispatch
#ifndef __WIN32_INTERFACE__
#import "redwindows.fx";
#endif

#ifndef __REDD2D__
#def __REDD2D__ 1;

// ============================================================================
// DIRECT2D / COM TYPES
// ============================================================================

// COM HRESULT (signed 32-bit return code)
signed   data{32} as HRESULT;
// IUnknown-derived interface pointers are all opaque void* at the ABI level
void* as ID2D1Factory,
        ID2D1HwndRenderTarget,
        ID2D1RenderTarget,
        ID2D1SolidColorBrush,
        ID2D1LinearGradientBrush,
        ID2D1RadialGradientBrush,
        ID2D1BitmapRenderTarget,
        ID2D1Bitmap,
        ID2D1StrokeStyle,
        ID2D1Layer,
        ID2D1Geometry,
        ID2D1PathGeometry,
        ID2D1GeometrySink,
        ID2D1EllipseGeometry,
        ID2D1RectangleGeometry,
        ID2D1RoundedRectangleGeometry,
        ID2D1TransformedGeometry,
        ID2D1GeometryGroup,
        IDWriteFactory,
        IDWriteTextFormat,
        IDWriteTextLayout,
        IWICImagingFactory,
        IWICBitmapDecoder,
        IWICBitmapFrameDecode,
        IWICFormatConverter;

// ============================================================================
// DIRECT2D STRUCTURES
// ============================================================================

// D2D1_COLOR_F - floating-point RGBA colour (0.0 - 1.0 per channel)
struct D2D1_COLOR_F
{
    float r, g, b, a;
};

// D2D1_POINT_2F - 2D floating-point point
struct D2D1_POINT_2F
{
    float x, y;
};

// D2D1_SIZE_F - floating-point size
struct D2D1_SIZE_F
{
    float width, height;
};

// D2D1_SIZE_U - unsigned integer size
struct D2D1_SIZE_U
{
    DWORD width, height;
};

// D2D1_RECT_F - floating-point rectangle
struct D2D1_RECT_F
{
    float left, top, right, bottom;
};

// D2D1_RECT_U - unsigned integer rectangle
struct D2D1_RECT_U
{
    DWORD left, top, right, bottom;
};

// D2D1_ROUNDED_RECT - rectangle with corner radii
struct D2D1_ROUNDED_RECT
{
    D2D1_RECT_F rect;
    float radiusX, radiusY;
};

// D2D1_ELLIPSE - centre point and radii
struct D2D1_ELLIPSE
{
    D2D1_POINT_2F point;
    float radiusX, radiusY;
};

// D2D1_MATRIX_3X2_F - affine 3x2 transformation matrix (row-major)
struct D2D1_MATRIX_3X2_F
{
    float _11, _12,
          _21, _22,
          _31, _32;
};

// D2D1_GRADIENT_STOP - colour stop for gradient brushes
struct D2D1_GRADIENT_STOP
{
    float        position; // 0.0 - 1.0
    D2D1_COLOR_F color;
};

// D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES
struct D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES
{
    D2D1_POINT_2F startPoint;
    D2D1_POINT_2F endPoint;
};

// D2D1_RADIAL_GRADIENT_BRUSH_PROPERTIES
struct D2D1_RADIAL_GRADIENT_BRUSH_PROPERTIES
{
    D2D1_POINT_2F center;
    D2D1_POINT_2F gradientOriginOffset;
    float         radiusX, radiusY;
};

// D2D1_RENDER_TARGET_PROPERTIES - creation properties for render targets
struct D2D1_RENDER_TARGET_PROPERTIES
{
    DWORD type;        // D2D1_RENDER_TARGET_TYPE
    DWORD pixelFormat; // DXGI_FORMAT
    DWORD alphaMode;   // D2D1_ALPHA_MODE
    float dpiX, dpiY;
    DWORD usage;       // D2D1_RENDER_TARGET_USAGE
    DWORD minLevel;    // D2D1_FEATURE_LEVEL
};

// D2D1_HWND_RENDER_TARGET_PROPERTIES
struct D2D1_HWND_RENDER_TARGET_PROPERTIES
{
    HWND        hwnd;
    D2D1_SIZE_U pixelSize;
    DWORD       presentOptions; // D2D1_PRESENT_OPTIONS
};

// D2D1_STROKE_STYLE_PROPERTIES
struct D2D1_STROKE_STYLE_PROPERTIES
{
    DWORD startCap;   // D2D1_CAP_STYLE
    DWORD endCap;
    DWORD dashCap;
    DWORD lineJoin;   // D2D1_LINE_JOIN
    float miterLimit;
    DWORD dashStyle;  // D2D1_DASH_STYLE
    float dashOffset;
};

// D2D1_BEZIER_SEGMENT
struct D2D1_BEZIER_SEGMENT
{
    D2D1_POINT_2F point1, point2, point3;
};

// D2D1_QUADRATIC_BEZIER_SEGMENT
struct D2D1_QUADRATIC_BEZIER_SEGMENT
{
    D2D1_POINT_2F point1, point2;
};

// D2D1_ARC_SEGMENT
struct D2D1_ARC_SEGMENT
{
    D2D1_POINT_2F point;
    D2D1_SIZE_F   size;
    float         rotationAngle;
    DWORD         sweepDirection; // D2D1_SWEEP_DIRECTION
    DWORD         arcSize;        // D2D1_ARC_SIZE
};

// D2D1_BITMAP_PROPERTIES
struct D2D1_BITMAP_PROPERTIES
{
    DWORD pixelFormat; // DXGI_FORMAT
    DWORD alphaMode;
    float dpiX, dpiY;
};

// ============================================================================
// DIRECT2D CONSTANTS
// ============================================================================

// HRESULT
global HRESULT D2D_S_OK                          =  0x00000000,
               D2D_E_NOTIMPL                     =  0x80004001,
               D2D_E_NOINTERFACE                 =  0x80004002,
               D2D_E_POINTER                     =  0x80004003,
               D2D_E_ABORT                       =  0x80004004,
               D2D_E_FAIL                        =  0x80004005,
               D2D_E_OUTOFMEMORY                 =  0x8007000E,
               D2D_E_INVALIDARG                  =  0x80070057,
               D2DERR_WRONG_STATE                =  0x88990001,
               D2DERR_NOT_INITIALIZED            =  0x88990002,
               D2DERR_UNSUPPORTED_OPERATION      =  0x88990003,
               D2DERR_SCANNER_FAILED             =  0x88990004,
               D2DERR_SCREENACCESSDENIED         =  0x88990005,
               D2DERR_DISPLAY_STATE_INVALID      =  0x88990006,
               D2DERR_ZERO_VECTOR                =  0x88990007,
               D2DERR_INTERNAL_ERROR             =  0x88990008,
               D2DERR_DISPLAY_FORMAT_NOT_SUPPORTED = 0x88990009,
               D2DERR_INVALID_CALL               =  0x8899000A,
               D2DERR_NO_HARDWARE_DEVICE         =  0x8899000B,
               D2DERR_RECREATE_TARGET            =  0x8899000C,
               D2DERR_BAD_NUMBER                 =  0x88990011,
               D2DERR_WRONG_FACTORY              =  0x88990012,
               D2DERR_WIN32_ERROR                =  0x88990019;

// D2D1_FACTORY_TYPE
global int D2D1_FACTORY_TYPE_SINGLE_THREADED = 0,
           D2D1_FACTORY_TYPE_MULTI_THREADED  = 1;

// D2D1_RENDER_TARGET_TYPE
global int D2D1_RENDER_TARGET_TYPE_DEFAULT  = 0,
           D2D1_RENDER_TARGET_TYPE_SOFTWARE = 1,
           D2D1_RENDER_TARGET_TYPE_HARDWARE = 2;

// DXGI_FORMAT (common subset used by D2D)
global int DXGI_FORMAT_UNKNOWN        = 0,
           DXGI_FORMAT_R8G8B8A8_UNORM = 28,
           DXGI_FORMAT_B8G8R8A8_UNORM = 87,
           DXGI_FORMAT_B8G8R8X8_UNORM = 88,
           DXGI_FORMAT_A8_UNORM       = 65;

// D2D1_ALPHA_MODE
global int D2D1_ALPHA_MODE_UNKNOWN       = 0,
           D2D1_ALPHA_MODE_PREMULTIPLIED = 1,
           D2D1_ALPHA_MODE_STRAIGHT      = 2,
           D2D1_ALPHA_MODE_IGNORE        = 3;

// D2D1_PRESENT_OPTIONS
global int D2D1_PRESENT_OPTIONS_NONE            = 0x00000000,
           D2D1_PRESENT_OPTIONS_RETAIN_CONTENTS = 0x00000001,
           D2D1_PRESENT_OPTIONS_IMMEDIATELY     = 0x00000002;

// D2D1_RENDER_TARGET_USAGE
global int D2D1_RENDER_TARGET_USAGE_NONE                  = 0x00000000,
           D2D1_RENDER_TARGET_USAGE_FORCE_BITMAP_REMOTING = 0x00000001,
           D2D1_RENDER_TARGET_USAGE_GDI_COMPATIBLE        = 0x00000002;

// D2D1_FEATURE_LEVEL
global int D2D1_FEATURE_LEVEL_DEFAULT = 0,
           D2D1_FEATURE_LEVEL_9       = 0x9100,
           D2D1_FEATURE_LEVEL_10      = 0xA000;

// D2D1_ANTIALIAS_MODE
global int D2D1_ANTIALIAS_MODE_PER_PRIMITIVE = 0,
           D2D1_ANTIALIAS_MODE_ALIASED       = 1;

// D2D1_TEXT_ANTIALIAS_MODE
global int D2D1_TEXT_ANTIALIAS_MODE_DEFAULT   = 0,
           D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE = 1,
           D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE = 2,
           D2D1_TEXT_ANTIALIAS_MODE_ALIASED   = 3;

// D2D1_CAP_STYLE
global int D2D1_CAP_STYLE_FLAT     = 0,
           D2D1_CAP_STYLE_SQUARE   = 1,
           D2D1_CAP_STYLE_ROUND    = 2,
           D2D1_CAP_STYLE_TRIANGLE = 3;

// D2D1_LINE_JOIN
global int D2D1_LINE_JOIN_MITER          = 0,
           D2D1_LINE_JOIN_BEVEL          = 1,
           D2D1_LINE_JOIN_ROUND          = 2,
           D2D1_LINE_JOIN_MITER_OR_BEVEL = 3;

// D2D1_DASH_STYLE
global int D2D1_DASH_STYLE_SOLID        = 0,
           D2D1_DASH_STYLE_DASH         = 1,
           D2D1_DASH_STYLE_DOT          = 2,
           D2D1_DASH_STYLE_DASH_DOT     = 3,
           D2D1_DASH_STYLE_DASH_DOT_DOT = 4,
           D2D1_DASH_STYLE_CUSTOM       = 5;

// D2D1_SWEEP_DIRECTION
global int D2D1_SWEEP_DIRECTION_COUNTER_CLOCKWISE = 0,
           D2D1_SWEEP_DIRECTION_CLOCKWISE         = 1;

// D2D1_ARC_SIZE
global int D2D1_ARC_SIZE_SMALL = 0,
           D2D1_ARC_SIZE_LARGE = 1;

// D2D1_FILL_MODE
global int D2D1_FILL_MODE_ALTERNATE = 0,
           D2D1_FILL_MODE_WINDING   = 1;

// D2D1_FIGURE_BEGIN
global int D2D1_FIGURE_BEGIN_FILLED = 0,
           D2D1_FIGURE_BEGIN_HOLLOW = 1;

// D2D1_FIGURE_END
global int D2D1_FIGURE_END_OPEN   = 0,
           D2D1_FIGURE_END_CLOSED = 1;

// D2D1_PATH_SEGMENT
global int D2D1_PATH_SEGMENT_NONE                   = 0x00000000,
           D2D1_PATH_SEGMENT_FORCE_UNSTROKED         = 0x00000001,
           D2D1_PATH_SEGMENT_FORCE_ROUND_LINE_JOIN   = 0x00000002;

// D2D1_COMBINE_MODE
global int D2D1_COMBINE_MODE_UNION     = 0,
           D2D1_COMBINE_MODE_INTERSECT = 1,
           D2D1_COMBINE_MODE_XOR       = 2,
           D2D1_COMBINE_MODE_EXCLUDE   = 3;

// D2D1_LAYER_OPTIONS
global int D2D1_LAYER_OPTIONS_NONE                     = 0x00000000,
           D2D1_LAYER_OPTIONS_INITIALIZE_FOR_CLEARTYPE = 0x00000001;

// D2D1_BITMAP_INTERPOLATION_MODE
global int D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR = 0,
           D2D1_BITMAP_INTERPOLATION_MODE_LINEAR            = 1;

// D2D1_DRAW_TEXT_OPTIONS
global int D2D1_DRAW_TEXT_OPTIONS_NONE              = 0x00000000,
           D2D1_DRAW_TEXT_OPTIONS_NO_SNAP           = 0x00000001,
           D2D1_DRAW_TEXT_OPTIONS_CLIP              = 0x00000002,
           D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT = 0x00000004;

// D2D1_EXTEND_MODE (for gradients)
global int D2D1_EXTEND_MODE_CLAMP  = 0,
           D2D1_EXTEND_MODE_WRAP   = 1,
           D2D1_EXTEND_MODE_MIRROR = 2;

// D2D1_GAMMA
global int D2D1_GAMMA_2_2 = 0,
           D2D1_GAMMA_1_0 = 1;

// DWRITE_FONT_WEIGHT
global int DWRITE_FONT_WEIGHT_THIN        = 100,
           DWRITE_FONT_WEIGHT_EXTRA_LIGHT = 200,
           DWRITE_FONT_WEIGHT_LIGHT       = 300,
           DWRITE_FONT_WEIGHT_NORMAL      = 400,
           DWRITE_FONT_WEIGHT_MEDIUM      = 500,
           DWRITE_FONT_WEIGHT_SEMI_BOLD   = 600,
           DWRITE_FONT_WEIGHT_BOLD        = 700,
           DWRITE_FONT_WEIGHT_EXTRA_BOLD  = 800,
           DWRITE_FONT_WEIGHT_BLACK       = 900;

// DWRITE_FONT_STYLE
global int DWRITE_FONT_STYLE_NORMAL  = 0,
           DWRITE_FONT_STYLE_OBLIQUE = 1,
           DWRITE_FONT_STYLE_ITALIC  = 2;

// DWRITE_FONT_STRETCH
global int DWRITE_FONT_STRETCH_UNDEFINED       = 0,
           DWRITE_FONT_STRETCH_ULTRA_CONDENSED = 1,
           DWRITE_FONT_STRETCH_EXTRA_CONDENSED = 2,
           DWRITE_FONT_STRETCH_CONDENSED       = 3,
           DWRITE_FONT_STRETCH_SEMI_CONDENSED  = 4,
           DWRITE_FONT_STRETCH_NORMAL          = 5,
           DWRITE_FONT_STRETCH_SEMI_EXPANDED   = 6,
           DWRITE_FONT_STRETCH_EXPANDED        = 7,
           DWRITE_FONT_STRETCH_EXTRA_EXPANDED  = 8,
           DWRITE_FONT_STRETCH_ULTRA_EXPANDED  = 9;

// DWRITE_TEXT_ALIGNMENT
global int DWRITE_TEXT_ALIGNMENT_LEADING   = 0,
           DWRITE_TEXT_ALIGNMENT_TRAILING  = 1,
           DWRITE_TEXT_ALIGNMENT_CENTER    = 2,
           DWRITE_TEXT_ALIGNMENT_JUSTIFIED = 3;

// DWRITE_PARAGRAPH_ALIGNMENT
global int DWRITE_PARAGRAPH_ALIGNMENT_NEAR   = 0,
           DWRITE_PARAGRAPH_ALIGNMENT_FAR    = 1,
           DWRITE_PARAGRAPH_ALIGNMENT_CENTER = 2;

// DWRITE_WORD_WRAPPING
global int DWRITE_WORD_WRAPPING_WRAP            = 0,
           DWRITE_WORD_WRAPPING_NO_WRAP         = 1,
           DWRITE_WORD_WRAPPING_EMERGENCY_BREAK = 2,
           DWRITE_WORD_WRAPPING_WHOLE_WORD      = 3,
           DWRITE_WORD_WRAPPING_CHARACTER       = 4;

// DWRITE_FACTORY_TYPE
global int DWRITE_FACTORY_TYPE_SHARED    = 0,
           DWRITE_FACTORY_TYPE_ISOLATED  = 1;

// DWRITE_MEASURING_MODE
global int DWRITE_MEASURING_MODE_NATURAL     = 0,
           DWRITE_MEASURING_MODE_GDI_CLASSIC = 1,
           DWRITE_MEASURING_MODE_GDI_NATURAL = 2;

// ============================================================================
// DIRECT2D / DWRITE EXTERN FUNCTION DECLARATIONS
// Flat DLL exports - no COM vtable needed for factory creation.
// ============================================================================

extern
{
    def !!
        D2D1CreateFactory(int, void*, void*, void**) -> HRESULT,
        DWriteCreateFactory(int, void*, void**) -> HRESULT;
};

// ============================================================================
// GLOBAL FUNCTION POINTER VARIABLES
// Initialized to null; populated at runtime by d2d_init_vtable_ptrs()
// from the live COM vtables.
// ============================================================================

def{}* gfn_release(void*) -> void                                                      = (void*)0;
def{}* gfn_create_hwnd_rt(void*, void*, void*, void**) -> HRESULT                     = (void*)0;
def{}* gfn_create_path(void*, void**) -> HRESULT                                      = (void*)0;
def{}* gfn_open_path(void*, void**) -> HRESULT                                        = (void*)0;
def{}* gfn_resize(void*, void*) -> void                                                = (void*)0;
def{}* gfn_clear(void*, void*) -> void                                                 = (void*)0;
def{}* gfn_set_transform(void*, void*) -> void                                         = (void*)0;
def{}* gfn_begin_draw(void*) -> void                                                   = (void*)0;
def{}* gfn_pop_clip(void*) -> void                                                     = (void*)0;
def{}* gfn_end_draw(void*, void*, void*) -> HRESULT                                   = (void*)0;
def{}* gfn_create_brush(void*, void*, void*, void**) -> HRESULT                       = (void*)0;
def{}* gfn_draw_line(void*, void*, void*, void*, float, void*) -> void                = (void*)0;
def{}* gfn_draw_rect(void*, void*, void*, float, void*) -> void                       = (void*)0;
def{}* gfn_fill_rect(void*, void*, void*) -> void                                     = (void*)0;
def{}* gfn_draw_rounded_rect(void*, void*, void*, float, void*) -> void               = (void*)0;
def{}* gfn_fill_rounded_rect(void*, void*, void*) -> void                             = (void*)0;
def{}* gfn_draw_ellipse(void*, void*, void*, float, void*) -> void                    = (void*)0;
def{}* gfn_fill_ellipse(void*, void*, void*) -> void                                  = (void*)0;
def{}* gfn_draw_geometry(void*, void*, void*, float, void*) -> void                   = (void*)0;
def{}* gfn_fill_geometry(void*, void*, void*, void*) -> void                          = (void*)0;
def{}* gfn_draw_text(void*, void*, DWORD, void*, void*, void*, int, int) -> void      = (void*)0;
def{}* gfn_push_clip(void*, void*, int) -> void                                        = (void*)0;
def{}* gfn_create_text_format(void*, void*, void*, int, int, int, float, void*, void**) -> HRESULT = (void*)0;
def{}* gfn_close_sink(void*) -> HRESULT                                               = (void*)0;
def{}* gfn_set_text_alignment(void*, int) -> HRESULT                                  = (void*)0;
def{}* gfn_set_paragraph_alignment(void*, int) -> HRESULT                             = (void*)0;
def{}* gfn_begin_figure(void*, void*, int) -> void                                    = (void*)0;
def{}* gfn_end_figure(void*, int) -> void                                             = (void*)0;
def{}* gfn_add_line(void*, void*) -> void                                             = (void*)0;
def{}* gfn_add_bezier(void*, void*) -> void                                           = (void*)0;
def{}* gfn_add_arc(void*, void*) -> void                                              = (void*)0;

namespace standard
{
    namespace system
    {
        namespace windows
        {
            // ============================================================================
            // COM VTABLE DISPATCH
            // A COM object's first field is void** (pointer to array of function pointers).
            // Read one slot by zero-based method index and call it directly.
            // ============================================================================

            // Read one vtable slot from a COM object by zero-based method index
            def d2d_vtable_slot(void* obj, int index) -> void*
            {
                void** vtbl = *(void**)obj;
                return vtbl[index];
            };

            // ============================================================================
            // D2D FACTORY HELPERS
            // ============================================================================

            // Create a single-threaded ID2D1Factory.
            // Returns (ID2D1Factory)0 on failure.
            def d2d_create_factory() -> ID2D1Factory
            {
                // IID_ID2D1Factory GUID: {06152247-6F50-465A-9245-118BFD3B6007}
                DWORD[4] iid_d;
                iid_d[0] = (u64*)0x06152247;
                iid_d[1] = (u64*)0x465A6F50;
                iid_d[2] = (u64*)0x3BFD1892;
                iid_d[3] = (u64*)0x07603B6B;
                ID2D1Factory factory = (ID2D1Factory)0;
                HRESULT hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                                               (void*)@iid_d[0],
                                               (void*)0,
                                               (void**)@factory);
                if (hr != D2D_S_OK) { return (ID2D1Factory)0; };
                return factory;
            };

            // Create a multi-threaded ID2D1Factory.
            def d2d_create_factory_mt() -> ID2D1Factory
            {
                DWORD[4] iid_d;
                iid_d[0] = (u64*)0x06152247;
                iid_d[1] = (u64*)0x465A6F50;
                iid_d[2] = (u64*)0x3BFD1892;
                iid_d[3] = (u64*)0x07603B6B;
                ID2D1Factory factory = (ID2D1Factory)0;
                HRESULT hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_MULTI_THREADED,
                                               (void*)@iid_d[0],
                                               (void*)0,
                                               (void**)@factory);
                if (hr != D2D_S_OK) { return (ID2D1Factory)0; };
                return factory;
            };

            // Create a shared IDWriteFactory.
            def d2d_create_dwrite_factory() -> IDWriteFactory
            {
                // IID_IDWriteFactory: {B859EE5A-D838-4B5B-A2E8-1ADC7D93DB48}
                DWORD[4] iid_d;
                iid_d[0] = (u64*)0xB859EE5A;
                iid_d[1] = (u64*)0x4B5BD838;
                iid_d[2] = (u64*)0xDC1AE8A2;
                iid_d[3] = (u64*)0x48DB93D7;
                IDWriteFactory dw = (IDWriteFactory)0;
                HRESULT hr = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
                                                 (void*)@iid_d[0],
                                                 (void**)@dw);
                if (hr != D2D_S_OK) { return (IDWriteFactory)0; };
                return dw;
            };

            // Create an ID2D1HwndRenderTarget attached to the given window.
            // factory must have been initialised via d2d_create_factory().
            // Returns (ID2D1HwndRenderTarget)0 on failure.
            //
            // ID2D1Factory vtable layout:
            //   IUnknown:     0=QueryInterface, 1=AddRef, 2=Release
            //   ID2D1Factory: 3=ReloadSystemMetrics, 4=GetDesktopDpi,
            //                 5=CreateRectangleGeometry, 6=CreateRoundedRectangleGeometry,
            //                 7=CreateEllipseGeometry, 8=CreateGeometryGroup,
            //                 9=CreateTransformedGeometry, 10=CreatePathGeometry,
            //                 11=CreateStrokeStyle, 12=CreateDrawingStateBlock,
            //                 13=CreateWicBitmapRenderTarget, 14=CreateHwndRenderTarget
            def d2d_create_hwnd_render_target(ID2D1Factory factory, HWND hwnd, int width, int height) -> ID2D1HwndRenderTarget
            {
                D2D1_RENDER_TARGET_PROPERTIES rtp;
                rtp.type        = D2D1_RENDER_TARGET_TYPE_DEFAULT;
                rtp.pixelFormat = DXGI_FORMAT_B8G8R8A8_UNORM;
                rtp.alphaMode   = D2D1_ALPHA_MODE_PREMULTIPLIED;
                rtp.dpiX        = 0.0;
                rtp.dpiY        = 0.0;
                rtp.usage       = D2D1_RENDER_TARGET_USAGE_NONE;
                rtp.minLevel    = D2D1_FEATURE_LEVEL_DEFAULT;
                D2D1_HWND_RENDER_TARGET_PROPERTIES hwnd_rtp;
                hwnd_rtp.hwnd                 = hwnd;
                hwnd_rtp.pixelSize.width      = (DWORD)width;
                hwnd_rtp.pixelSize.height     = (DWORD)height;
                hwnd_rtp.presentOptions       = D2D1_PRESENT_OPTIONS_NONE;
                ID2D1HwndRenderTarget rt = (ID2D1HwndRenderTarget)0;
                gfn_create_hwnd_rt = d2d_vtable_slot(factory, 14);
                HRESULT hr = gfn_create_hwnd_rt(factory, (void*)@rtp, (void*)@hwnd_rtp, (void**)@rt);
                if (hr != D2D_S_OK) { return (ID2D1HwndRenderTarget)0; };
                return rt;
            };

            // ============================================================================
            // VTABLE POINTER INITIALISATION
            // Call once after factory and render_target are created.
            // Re-points all global function pointers at the live vtable slots.
            // ============================================================================

            def d2d_init_vtable_ptrs(ID2D1Factory factory, IDWriteFactory dwrite,
                                     ID2D1HwndRenderTarget rt) -> void
            {
                gfn_release            = d2d_vtable_slot(rt, 2);
                gfn_create_path        = d2d_vtable_slot(factory, 10);
                gfn_resize             = d2d_vtable_slot(rt, 58);
                gfn_create_brush       = d2d_vtable_slot(rt, 8);
                gfn_draw_line          = d2d_vtable_slot(rt, 15);
                gfn_draw_rect          = d2d_vtable_slot(rt, 16);
                gfn_fill_rect          = d2d_vtable_slot(rt, 17);
                gfn_draw_rounded_rect  = d2d_vtable_slot(rt, 18);
                gfn_fill_rounded_rect  = d2d_vtable_slot(rt, 19);
                gfn_draw_ellipse       = d2d_vtable_slot(rt, 20);
                gfn_fill_ellipse       = d2d_vtable_slot(rt, 21);
                gfn_draw_geometry      = d2d_vtable_slot(rt, 22);
                gfn_fill_geometry      = d2d_vtable_slot(rt, 23);
                gfn_draw_text          = d2d_vtable_slot(rt, 27);
                gfn_set_transform      = d2d_vtable_slot(rt, 30);
                gfn_push_clip          = d2d_vtable_slot(rt, 45);
                gfn_pop_clip           = d2d_vtable_slot(rt, 46);
                gfn_clear              = d2d_vtable_slot(rt, 47);
                gfn_begin_draw         = d2d_vtable_slot(rt, 48);
                gfn_end_draw           = d2d_vtable_slot(rt, 49);
                gfn_create_text_format = d2d_vtable_slot(dwrite, 15);
                return;
            };

            // Sink pointers are re-pointed per geometry after open_path.
            def d2d_init_sink_ptrs(ID2D1GeometrySink sink) -> void
            {
                gfn_close_sink   = d2d_vtable_slot(sink, 9);
                gfn_begin_figure = d2d_vtable_slot(sink, 5);
                gfn_end_figure   = d2d_vtable_slot(sink, 8);
                gfn_add_line     = d2d_vtable_slot(sink, 10);
                gfn_add_bezier   = d2d_vtable_slot(sink, 11);
                gfn_add_arc      = d2d_vtable_slot(sink, 14);
                return;
            };

            // ============================================================================
            // MATRIX HELPERS
            // ============================================================================

            // Load identity into a D2D1_MATRIX_3X2_F
            def d2d_matrix_identity(D2D1_MATRIX_3X2_F* out) -> void
            {
                out._11 = 1.0; out._12 = 0.0;
                out._21 = 0.0; out._22 = 1.0;
                out._31 = 0.0; out._32 = 0.0;
                return;
            };

            // Build a translation matrix
            def d2d_matrix_translate(float tx, float ty, D2D1_MATRIX_3X2_F* out) -> void
            {
                out._11 = 1.0; out._12 = 0.0;
                out._21 = 0.0; out._22 = 1.0;
                out._31 = tx;  out._32 = ty;
                return;
            };

            // Build a scale matrix (pivot at origin)
            def d2d_matrix_scale(float sx, float sy, D2D1_MATRIX_3X2_F* out) -> void
            {
                out._11 = sx;  out._12 = 0.0;
                out._21 = 0.0; out._22 = sy;
                out._31 = 0.0; out._32 = 0.0;
                return;
            };

            // Build a rotation matrix (angle in radians, pivot at origin)
            def d2d_matrix_rotate(float angle_rad, D2D1_MATRIX_3X2_F* out) -> void
            {
                float c = cos(angle_rad);
                float s = sin(angle_rad);
                out._11 =  c;        out._12 = s;
                out._21 = (0.0 - s); out._22 = c;
                out._31 = 0.0;       out._32 = 0.0;
                return;
            };

            // Multiply two 3x2 matrices: out = a * b
            def d2d_matrix_mul(D2D1_MATRIX_3X2_F* a, D2D1_MATRIX_3X2_F* b, D2D1_MATRIX_3X2_F* out) -> void
            {
                out._11 = a._11 * b._11 + a._12 * b._21;
                out._12 = a._11 * b._12 + a._12 * b._22;
                out._21 = a._21 * b._11 + a._22 * b._21;
                out._22 = a._21 * b._12 + a._22 * b._22;
                out._31 = a._31 * b._11 + a._32 * b._21 + b._31;
                out._32 = a._31 * b._12 + a._32 * b._22 + b._32;
                return;
            };

            // ============================================================================
            // D2D1_COLOR_F CONVENIENCE HELPERS
            // ============================================================================

            // Build a D2D1_COLOR_F from normalised float components
            def d2d_color(float r, float g, float b, float a, D2D1_COLOR_F* out) -> void
            {
                out.r = r;
                out.g = g;
                out.b = b;
                out.a = a;
                return;
            };

            // Build a D2D1_COLOR_F from 0-255 byte components
            def d2d_color_rgba(int r, int g, int b, int a, D2D1_COLOR_F* out) -> void
            {
                out.r = (float)r / 255.0;
                out.g = (float)g / 255.0;
                out.b = (float)b / 255.0;
                out.a = (float)a / 255.0;
                return;
            };

            // ============================================================================
            // D2DCONTEXT OBJECT - Wraps the D2D1 / DWrite lifecycle for a window
            // All COM dispatch is done via the global function pointer variables above.
            //
            // ID2D1RenderTarget vtable layout:
            //   IUnknown:              0=QueryInterface, 1=AddRef, 2=Release
            //   ID2D1Resource:         3=GetFactory
            //   ID2D1RenderTarget:     4=CreateBitmap, 5=CreateBitmapFromWicBitmap,
            //                          6=CreateSharedBitmap, 7=CreateBitmapBrush,
            //                          8=CreateSolidColorBrush,
            //                          9=CreateGradientStopCollection,
            //                          10=CreateLinearGradientBrush,
            //                          11=CreateRadialGradientBrush,
            //                          12=CreateCompatibleRenderTarget, 13=CreateLayer,
            //                          14=CreateMesh,
            //                          15=DrawLine, 16=DrawRectangle, 17=FillRectangle,
            //                          18=DrawRoundedRectangle, 19=FillRoundedRectangle,
            //                          20=DrawEllipse, 21=FillEllipse,
            //                          22=DrawGeometry, 23=FillGeometry, 24=FillMesh,
            //                          25=FillOpacityMask, 26=DrawBitmap,
            //                          27=DrawText, 28=DrawTextLayout, 29=DrawGlyphRun,
            //                          30=SetTransform, 31=GetTransform,
            //                          32=SetAntialiasMode, 33=GetAntialiasMode,
            //                          34=SetTextAntialiasMode, 35=GetTextAntialiasMode,
            //                          36=SetTextRenderingParams, 37=GetTextRenderingParams,
            //                          38=SetTags, 39=GetTags,
            //                          40=PushLayer, 41=PopLayer,
            //                          42=Flush, 43=SaveDrawingState, 44=RestoreDrawingState,
            //                          45=PushAxisAlignedClip, 46=PopAxisAlignedClip,
            //                          47=Clear, 48=BeginDraw, 49=EndDraw,
            //                          50=GetPixelFormat, 51=SetDpi, 52=GetDpi,
            //                          53=GetSize, 54=GetPixelSize,
            //                          55=GetMaximumBitmapSize, 56=IsSupported
            //   ID2D1HwndRenderTarget: 57=CheckWindowState, 58=Resize, 59=GetHwnd
            //
            // ID2D1SolidColorBrush vtable layout:
            //   IUnknown:              0=QueryInterface, 1=AddRef, 2=Release
            //   ID2D1Resource:         3=GetFactory
            //   ID2D1Brush:            4=SetOpacity, 5=GetOpacity, 6=SetTransform, 7=GetTransform
            //   ID2D1SolidColorBrush:  8=SetColor, 9=GetColor
            //
            // IDWriteFactory vtable layout:
            //   IUnknown:       0=QueryInterface, 1=AddRef, 2=Release
            //   IDWriteFactory: ...15=CreateTextFormat, ...18=CreateTextLayout
            //
            // IDWriteTextFormat vtable layout:
            //   IDWriteTextFormat: 3=SetTextAlignment, 4=SetParagraphAlignment,
            //                      5=SetWordWrapping
            //
            // ID2D1PathGeometry vtable layout:
            //   ID2D1PathGeometry: 7=Open
            //
            // ID2D1GeometrySink vtable layout:
            //   ID2D1SimplifiedGeometrySink: 3=SetFillMode, 4=SetSegmentFlags,
            //                                5=BeginFigure, 6=AddLines, 7=AddBeziers,
            //                                8=EndFigure, 9=Close
            //   ID2D1GeometrySink:           10=AddLine, 11=AddBezier,
            //                                12=AddQuadraticBezier, 14=AddArc
            // ============================================================================

            object D2DContext
            {
                ID2D1Factory          factory;
                IDWriteFactory        dwrite;
                ID2D1HwndRenderTarget render_target;

                // Create D2D and DWrite factories and an HwndRenderTarget for hwnd
                def __init(HWND hwnd, int width, int height) -> this
                {
                    this.factory       = d2d_create_factory();
                    this.dwrite        = d2d_create_dwrite_factory();
                    this.render_target = d2d_create_hwnd_render_target(this.factory, hwnd, width, height);
                    d2d_init_vtable_ptrs(this.factory, this.dwrite, this.render_target);
                    return this;
                };

                // Release all resources
                def __exit() -> void
                {
                    if (this.render_target != (ID2D1HwndRenderTarget)0)
                    {
                        gfn_release = d2d_vtable_slot(this.render_target, 2);
                        gfn_release(this.render_target);
                    };
                    if (this.dwrite != (IDWriteFactory)0)
                    {
                        gfn_release = d2d_vtable_slot(this.dwrite, 2);
                        gfn_release(this.dwrite);
                    };
                    if (this.factory != (ID2D1Factory)0)
                    {
                        gfn_release = d2d_vtable_slot(this.factory, 2);
                        gfn_release(this.factory);
                    };
                    return;
                };

                // Resize the render target pixel buffer (call on WM_SIZE)
                def resize(int width, int height) -> void
                {
                    D2D1_SIZE_U new_size;
                    new_size.width  = (DWORD)width;
                    new_size.height = (DWORD)height;
                    gfn_resize(this.render_target, (void*)@new_size);
                    return;
                };

                // Begin a draw frame
                def begin_draw() -> void
                {
                    gfn_begin_draw(this.render_target);
                    return;
                };

                // End a draw frame; returns HRESULT
                def end_draw() -> HRESULT
                {
                    return gfn_end_draw(this.render_target, (void*)0, (void*)0);
                };

                // Clear the render target to a solid colour
                def clear(float r, float g, float b, float a) -> void
                {
                    D2D1_COLOR_F color;
                    d2d_color(r, g, b, a, @color);
                    gfn_clear(this.render_target, (void*)@color);
                    return;
                };

                // Set the world transform
                def set_transform(D2D1_MATRIX_3X2_F* matrix) -> void
                {
                    gfn_set_transform(this.render_target, (void*)matrix);
                    return;
                };

                // Reset the world transform to identity
                def reset_transform() -> void
                {
                    D2D1_MATRIX_3X2_F identity;
                    d2d_matrix_identity(@identity);
                    gfn_set_transform(this.render_target, (void*)@identity);
                    return;
                };

                // Create a solid colour brush (caller must release via release_brush)
                def create_brush(float r, float g, float b, float a) -> ID2D1SolidColorBrush
                {
                    D2D1_COLOR_F color;
                    d2d_color(r, g, b, a, @color);
                    ID2D1SolidColorBrush brush = (ID2D1SolidColorBrush)0;
                    gfn_create_brush(this.render_target, (void*)@color, (void*)0, (void**)@brush);
                    return brush;
                };

                // Release a brush
                def release_brush(ID2D1SolidColorBrush brush) -> void
                {
                    gfn_release = d2d_vtable_slot(brush, 2);
                    gfn_release(brush);
                    return;
                };

                // Draw a line
                def draw_line(float x0, float y0, float x1, float y1,
                              ID2D1SolidColorBrush brush, float stroke_width) -> void
                {
                    D2D1_POINT_2F p0;
                    D2D1_POINT_2F p1;
                    p0.x = x0; p0.y = y0;
                    p1.x = x1; p1.y = y1;
                    gfn_draw_line(this.render_target, (void*)@p0, (void*)@p1, brush, stroke_width, (ID2D1StrokeStyle)0);
                    return;
                };

                // Draw a rectangle outline
                def draw_rect(float left, float top, float right, float bottom,
                              ID2D1SolidColorBrush brush, float stroke_width) -> void
                {
                    D2D1_RECT_F rect;
                    rect.left = left; rect.top = top; rect.right = right; rect.bottom = bottom;
                    gfn_draw_rect(this.render_target, (void*)@rect, brush, stroke_width, (ID2D1StrokeStyle)0);
                    return;
                };

                // Fill a rectangle
                def fill_rect(float left, float top, float right, float bottom,
                              ID2D1SolidColorBrush brush) -> void
                {
                    D2D1_RECT_F rect;
                    rect.left = left; rect.top = top; rect.right = right; rect.bottom = bottom;
                    gfn_fill_rect(this.render_target, (void*)@rect, brush);
                    return;
                };

                // Draw a rounded rectangle outline
                def draw_rounded_rect(float left, float top, float right, float bottom,
                                      float rx, float ry,
                                      ID2D1SolidColorBrush brush, float stroke_width) -> void
                {
                    D2D1_ROUNDED_RECT rrect;
                    rrect.rect.left = left; rrect.rect.top = top;
                    rrect.rect.right = right; rrect.rect.bottom = bottom;
                    rrect.radiusX = rx; rrect.radiusY = ry;
                    gfn_draw_rounded_rect(this.render_target, (void*)@rrect, brush, stroke_width, (ID2D1StrokeStyle)0);
                    return;
                };

                // Fill a rounded rectangle
                def fill_rounded_rect(float left, float top, float right, float bottom,
                                      float rx, float ry,
                                      ID2D1SolidColorBrush brush) -> void
                {
                    D2D1_ROUNDED_RECT rrect;
                    rrect.rect.left = left; rrect.rect.top = top;
                    rrect.rect.right = right; rrect.rect.bottom = bottom;
                    rrect.radiusX = rx; rrect.radiusY = ry;
                    gfn_fill_rounded_rect(this.render_target, (void*)@rrect, brush);
                    return;
                };

                // Draw an ellipse outline
                def draw_ellipse(float cx, float cy, float rx, float ry,
                                 ID2D1SolidColorBrush brush, float stroke_width) -> void
                {
                    D2D1_ELLIPSE ellipse;
                    ellipse.point.x = cx; ellipse.point.y = cy;
                    ellipse.radiusX = rx; ellipse.radiusY = ry;
                    gfn_draw_ellipse(this.render_target, (void*)@ellipse, brush, stroke_width, (ID2D1StrokeStyle)0);
                    return;
                };

                // Fill an ellipse
                def fill_ellipse(float cx, float cy, float rx, float ry,
                                 ID2D1SolidColorBrush brush) -> void
                {
                    D2D1_ELLIPSE ellipse;
                    ellipse.point.x = cx; ellipse.point.y = cy;
                    ellipse.radiusX = rx; ellipse.radiusY = ry;
                    gfn_fill_ellipse(this.render_target, (void*)@ellipse, brush);
                    return;
                };

                // Draw a circle outline (uniform radii)
                def draw_circle(float cx, float cy, float r,
                                ID2D1SolidColorBrush brush, float stroke_width) -> void
                {
                    D2D1_ELLIPSE ellipse;
                    ellipse.point.x = cx; ellipse.point.y = cy;
                    ellipse.radiusX = r; ellipse.radiusY = r;
                    gfn_draw_ellipse(this.render_target, (void*)@ellipse, brush, stroke_width, (ID2D1StrokeStyle)0);
                    return;
                };

                // Fill a circle (uniform radii)
                def fill_circle(float cx, float cy, float r,
                                ID2D1SolidColorBrush brush) -> void
                {
                    D2D1_ELLIPSE ellipse;
                    ellipse.point.x = cx; ellipse.point.y = cy;
                    ellipse.radiusX = r; ellipse.radiusY = r;
                    gfn_fill_ellipse(this.render_target, (void*)@ellipse, brush);
                    return;
                };

                // Draw geometry outline
                def draw_path(ID2D1PathGeometry path,
                              ID2D1SolidColorBrush brush, float stroke_width) -> void
                {
                    gfn_draw_geometry(this.render_target, (ID2D1Geometry)path, brush, stroke_width, (ID2D1StrokeStyle)0);
                    return;
                };

                // Fill geometry
                def fill_path(ID2D1PathGeometry path, ID2D1SolidColorBrush brush) -> void
                {
                    gfn_fill_geometry(this.render_target, (ID2D1Geometry)path, brush, (ID2D1SolidColorBrush)0);
                    return;
                };

                // Draw text in a layout rectangle using a text format
                def draw_text(LPCSTR text, DWORD text_len,
                              IDWriteTextFormat fmt,
                              float left, float top, float right, float bottom,
                              ID2D1SolidColorBrush brush) -> void
                {
                    D2D1_RECT_F rect;
                    rect.left = left; rect.top = top; rect.right = right; rect.bottom = bottom;
                    gfn_draw_text(this.render_target, text, text_len, fmt, (void*)@rect, brush,
                                  D2D1_DRAW_TEXT_OPTIONS_NONE, DWRITE_MEASURING_MODE_NATURAL);
                    return;
                };

                // Push an axis-aligned clip
                def push_clip(float left, float top, float right, float bottom) -> void
                {
                    D2D1_RECT_F rect;
                    rect.left = left; rect.top = top; rect.right = right; rect.bottom = bottom;
                    gfn_push_clip(this.render_target, (void*)@rect, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
                    return;
                };

                // Pop the last axis-aligned clip
                def pop_clip() -> void
                {
                    gfn_pop_clip(this.render_target);
                    return;
                };

                // Create a text format (caller must release via release_text_format)
                def create_text_format(LPCSTR font_family, float font_size) -> IDWriteTextFormat
                {
                    IDWriteTextFormat fmt = (IDWriteTextFormat)0;
                    gfn_create_text_format(this.dwrite, font_family, (void*)0,
                                           DWRITE_FONT_WEIGHT_NORMAL,
                                           DWRITE_FONT_STYLE_NORMAL,
                                           DWRITE_FONT_STRETCH_NORMAL,
                                           font_size, "en-us\0", (void**)@fmt);
                    return fmt;
                };

                // Release a text format
                def release_text_format(IDWriteTextFormat fmt) -> void
                {
                    gfn_release = d2d_vtable_slot(fmt, 2);
                    gfn_release(fmt);
                    return;
                };

                // Set text alignment on a text format (IDWriteTextFormat slot 3)
                def set_text_alignment(IDWriteTextFormat fmt, int alignment) -> void
                {
                    gfn_set_text_alignment = d2d_vtable_slot(fmt, 3);
                    gfn_set_text_alignment(fmt, alignment);
                    return;
                };

                // Set paragraph alignment on a text format (IDWriteTextFormat slot 4)
                def set_paragraph_alignment(IDWriteTextFormat fmt, int alignment) -> void
                {
                    gfn_set_paragraph_alignment = d2d_vtable_slot(fmt, 4);
                    gfn_set_paragraph_alignment(fmt, alignment);
                    return;
                };

                // Create a path geometry (caller must release via release_path)
                def create_path() -> ID2D1PathGeometry
                {
                    ID2D1PathGeometry geom = (ID2D1PathGeometry)0;
                    gfn_create_path(this.factory, (void**)@geom);
                    return geom;
                };

                // Release a path geometry
                def release_path(ID2D1PathGeometry geom) -> void
                {
                    gfn_release = d2d_vtable_slot(geom, 2);
                    gfn_release(geom);
                    return;
                };

                // Open a geometry sink on a path geometry
                def open_path(ID2D1PathGeometry geom) -> ID2D1GeometrySink
                {
                    ID2D1GeometrySink sink = (ID2D1GeometrySink)0;
                    gfn_open_path = d2d_vtable_slot(geom, 7);
                    gfn_open_path(geom, (void**)@sink);
                    d2d_init_sink_ptrs(sink);
                    return sink;
                };

                // Close and release a geometry sink
                def close_path(ID2D1GeometrySink sink) -> void
                {
                    gfn_close_sink(sink);
                    gfn_release = d2d_vtable_slot(sink, 2);
                    gfn_release(sink);
                    return;
                };

                // Begin a figure in a geometry sink
                def begin_figure(ID2D1GeometrySink sink, float x, float y, int begin_type) -> void
                {
                    D2D1_POINT_2F pt;
                    pt.x = x; pt.y = y;
                    gfn_begin_figure(sink, (void*)@pt, begin_type);
                    return;
                };

                // End a figure in a geometry sink
                def end_figure(ID2D1GeometrySink sink, int end_type) -> void
                {
                    gfn_end_figure(sink, end_type);
                    return;
                };

                // Add a line to a geometry sink
                def add_line(ID2D1GeometrySink sink, float x, float y) -> void
                {
                    D2D1_POINT_2F pt;
                    pt.x = x; pt.y = y;
                    gfn_add_line(sink, (void*)@pt);
                    return;
                };

                // Add a cubic bezier to a geometry sink
                def add_bezier(ID2D1GeometrySink sink,
                               float x1, float y1,
                               float x2, float y2,
                               float x3, float y3) -> void
                {
                    D2D1_BEZIER_SEGMENT seg;
                    seg.point1.x = x1; seg.point1.y = y1;
                    seg.point2.x = x2; seg.point2.y = y2;
                    seg.point3.x = x3; seg.point3.y = y3;
                    gfn_add_bezier(sink, (void*)@seg);
                    return;
                };

                // Add an arc to a geometry sink
                def add_arc(ID2D1GeometrySink sink,
                            float x, float y,
                            float w, float h,
                            float rotation,
                            int sweep_dir, int arc_size) -> void
                {
                    D2D1_ARC_SEGMENT seg;
                    seg.point.x        = x;
                    seg.point.y        = y;
                    seg.size.width     = w;
                    seg.size.height    = h;
                    seg.rotationAngle  = rotation;
                    seg.sweepDirection = sweep_dir;
                    seg.arcSize        = arc_size;
                    gfn_add_arc(sink, (void*)@seg);
                    return;
                };
            };
        };
    };
};

#endif;
