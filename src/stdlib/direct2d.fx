// Author: Karac V. Thweatt
//
// direct2d.fx  -  Flux Direct2D Rendering Library
//
// Provides a hardware-accelerated D2DCanvas object whose drawing interface
// mirrors the GDI Canvas in windows.fx, so all standard graphing functions
// (plot_line, draw_grid, draw_axes, etc.) work without modification via the
// D2DCanvas* overloads in d2d_graphing.fx.
//
// Also exposes a D2DWindow object that wraps Win32 window creation and
// drives a Direct2D HwndRenderTarget.
//
// COM vtable dispatch:
//   Every COM interface pointer's first field is a pointer to the vtable.
//   We load the vtable pointer, index the desired slot, assign it to a
//   typed def{}* function pointer, and call it with the interface pointer
//   as the first argument.
//
// Usage:
//   #import "standard.fx";
//   #import "direct2d.fx";
//   using standard::system::windows;
//   using standard::d2d;
//
//   def main() -> int
//   {
//       D2DWindow win("My Window\0", 800, 600, CW_USEDEFAULT, CW_USEDEFAULT);
//       D2DCanvas c(win.handle, 800, 600);
//
//       while (win.process_messages())
//       {
//           c.begin();
//           c.clear(RGB(20, 20, 30));
//           c.set_pen(RGB(0, 200, 255), 2);
//           c.line(10, 10, 200, 200);
//           c.end();
//       };
//
//       c.__exit();
//       win.__exit();
//       return 0;
//   };

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef __WIN32_INTERFACE__
#import "windows.fx";
#endif;

#ifndef FLUX_STANDARD_MATH
#import "math.fx";
#endif;

#ifndef FLUX_STANDARD_DIRECT2D
#def FLUX_STANDARD_DIRECT2D 1;

using standard::system::windows;
using standard::types;
using standard::math;

// ============================================================================
// Direct2D / DWrite DLL entry points
// ============================================================================

extern
{
    def !!
        D2D1CreateFactory(u32, u64*, u64*, u64*) -> i32,
        DWriteCreateFactory(u32, u64*, u64*)     -> i32,
        CoInitializeEx(u64*, u32)                -> i32;
};

namespace standard
{
    namespace d2d
    {
        // ====================================================================
        // Constants
        // ====================================================================

        global u32 D2D1_FACTORY_TYPE_SINGLE_THREADED = 0;

        global u32 D2D1_RENDER_TARGET_TYPE_DEFAULT   = 0;

        global u32 DXGI_FORMAT_UNKNOWN               = 0;

        global u32 D2D1_ALPHA_MODE_IGNORE            = 3;

        global u32 D2D1_PRESENT_OPTIONS_NONE         = 0;

        global u32 D2D1_FEATURE_LEVEL_DEFAULT        = 0;

        global u32 D2D1_ANTIALIAS_MODE_ALIASED       = 1;

        global u32 D2D1_CAP_STYLE_FLAT               = 0;

        global u32 D2D1_LINE_JOIN_MITER              = 0;

        global u32 D2D1_DASH_STYLE_SOLID             = 0;

        global u32 DWRITE_FACTORY_TYPE_SHARED        = 0;

        global u32 DWRITE_FONT_WEIGHT_NORMAL         = 400,
                   DWRITE_FONT_STYLE_NORMAL          = 0,
                   DWRITE_FONT_STRETCH_NORMAL        = 5;

        global u32 DWRITE_TEXT_ALIGNMENT_LEADING     = 0,
                   DWRITE_PARAGRAPH_ALIGNMENT_NEAR   = 0;

        global u32 COINIT_APARTMENTTHREADED          = 2;

        // ====================================================================
        // Packed structs used by Direct2D API calls
        // ====================================================================

        struct D2D1_COLOR_F
        {
            float r, g, b, a;
        };

        struct D2D1_RECT_F
        {
            float left, top, right, bottom;
        };

        struct D2D1_ELLIPSE
        {
            float cx, cy, rx, ry;
        };

        struct D2D1_SIZE_U
        {
            u32 width, height;
        };

        struct D2D1_PIXEL_FORMAT
        {
            u32 format,
                alphaMode;
        };

        struct D2D1_RENDER_TARGET_PROPERTIES
        {
            u32               renderTargetType;
            D2D1_PIXEL_FORMAT pixelFormat;
            float             dpiX, dpiY;
            u32               usage,
                              minLevel;
        };

        struct D2D1_HWND_RENDER_TARGET_PROPERTIES
        {
            HWND        hwnd;
            D2D1_SIZE_U pixelSize;
            u32         presentOptions;
        };

        struct D2D1_STROKE_STYLE_PROPERTIES
        {
            u32   startCap,
                  endCap,
                  dashCap,
                  lineJoin;
            float miterLimit;
            u32   dashStyle;
            float dashOffset;
        };

        // ====================================================================
        // Helper: DWORD (0x00BBGGRR) -> D2D1_COLOR_F
        // ====================================================================
        def dword_to_colorf(DWORD color, D2D1_COLOR_F* out) -> void
        {
            float inv = 1.0 / 255.0;
            out.r = (float)( color        & 0xFF) * inv;
            out.g = (float)((color >> 8)  & 0xFF) * inv;
            out.b = (float)((color >> 16) & 0xFF) * inv;
            out.a = 1.0;
            return;
        };

        // ====================================================================
        // Helper: encode ASCII string as UTF-16LE into a u16 buffer.
        // Returns number of code units written (not counting null terminator).
        // ====================================================================
        def ascii_to_utf16(byte* src, u16* dst, int max_chars) -> int
        {
            int i;
            while (i < max_chars)
            {
                byte ch = src[i];
                if (ch == 0) { break; };
                dst[i] = (u16)ch;
                i = i + 1;
            };
            if (i < max_chars) { dst[i] = 0; };
            return i;
        };

        // ====================================================================
        // COM vtable dispatch
        //
        // A COM object's first field is a pointer to its vtable.
        // The vtable is an array of u64 (function pointer) slots.
        //
        // To call method N on interface ptr iface:
        //   u64* tb = *(u64**)iface;
        //   def{}* fn(...) -> T = (u64*)tb[N];
        //   fn(iface, ...);
        // ====================================================================

        // ----------------------------------------------------------------
        // IUnknown::Release  (vtable slot 2)
        // ----------------------------------------------------------------
        def com_release(u64 iface) -> void
        {
            if (iface == 0) { return; };
            u64* tb = *(u64**)iface;
            def{}* fn(u64) -> u32 = (u64*)tb[2];
            fn(iface);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1Factory::CreateHwndRenderTarget  (vtable slot 15)
        // ----------------------------------------------------------------
        def d2d_factory_create_hwnd_rt(
            u64 factory,
            D2D1_RENDER_TARGET_PROPERTIES*      rtp,
            D2D1_HWND_RENDER_TARGET_PROPERTIES* hrtp,
            u64*                                out_rt) -> i32
        {
            u64* tb = *(u64**)factory;
            def{}* fn(u64, D2D1_RENDER_TARGET_PROPERTIES*, D2D1_HWND_RENDER_TARGET_PROPERTIES*, u64*) -> i32 = (u64*)tb[15];
            return fn(factory, rtp, hrtp, out_rt);
        };

        // ----------------------------------------------------------------
        // ID2D1Factory::CreateStrokeStyle  (vtable slot 11)
        // ----------------------------------------------------------------
        def d2d_factory_create_stroke_style(
            u64 factory,
            D2D1_STROKE_STYLE_PROPERTIES* props,
            float*                         dashes,
            u32                            dash_count,
            u64*                           out_ss) -> i32
        {
            u64* tb = *(u64**)factory;
            def{}* fn(u64, D2D1_STROKE_STYLE_PROPERTIES*, float*, u32, u64*) -> i32 = (u64*)tb[11];
            return fn(factory, props, dashes, dash_count, out_ss);
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::BeginDraw  (vtable slot 48)
        // ----------------------------------------------------------------
        def d2d_rt_begin_draw(u64 rt) -> void
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64) -> void = (u64*)tb[48];
            fn(rt);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::EndDraw  (vtable slot 49)
        // ----------------------------------------------------------------
        def d2d_rt_end_draw(u64 rt, u64* tag1, u64* tag2) -> i32
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, u64*, u64*) -> i32 = (u64*)tb[49];
            return fn(rt, tag1, tag2);
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::Clear  (vtable slot 47)
        // ----------------------------------------------------------------
        def d2d_rt_clear(u64 rt, D2D1_COLOR_F* color) -> void
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, D2D1_COLOR_F*) -> void = (u64*)tb[47];
            fn(rt, color);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::CreateSolidColorBrush  (vtable slot 8)
        // ----------------------------------------------------------------
        def d2d_rt_create_brush(u64 rt, D2D1_COLOR_F* color, u64 props, u64* out_brush) -> i32
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, D2D1_COLOR_F*, u64, u64*) -> i32 = (u64*)tb[8];
            return fn(rt, color, props, out_brush);
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::DrawLine  (vtable slot 15)
        //
        // Direct2D passes D2D1_POINT_2F by value as two floats on x64.
        // x0,y0 and x1,y1 are passed as four individual floats.
        // ----------------------------------------------------------------
        def d2d_rt_draw_line(u64 rt, float x0, float y0, float x1, float y1, u64 brush, float stroke_width, u64 stroke_style) -> void
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, float, float, float, float, u64, float, u64) -> void = (u64*)tb[15];
            fn(rt, x0, y0, x1, y1, brush, stroke_width, stroke_style);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::DrawRectangle  (vtable slot 16)
        // ----------------------------------------------------------------
        def d2d_rt_draw_rect(u64 rt, D2D1_RECT_F* rect, u64 brush, float stroke_width, u64 stroke_style) -> void
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, D2D1_RECT_F*, u64, float, u64) -> void = (u64*)tb[16];
            fn(rt, rect, brush, stroke_width, stroke_style);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::FillRectangle  (vtable slot 17)
        // ----------------------------------------------------------------
        def d2d_rt_fill_rect(u64 rt, D2D1_RECT_F* rect, u64 brush) -> void
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, D2D1_RECT_F*, u64) -> void = (u64*)tb[17];
            fn(rt, rect, brush);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::DrawEllipse  (vtable slot 20)
        // ----------------------------------------------------------------
        def d2d_rt_draw_ellipse(u64 rt, D2D1_ELLIPSE* el, u64 brush, float stroke_width, u64 stroke_style) -> void
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, D2D1_ELLIPSE*, u64, float, u64) -> void = (u64*)tb[20];
            fn(rt, el, brush, stroke_width, stroke_style);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::SetAntialiasMode  (vtable slot 32)
        // ----------------------------------------------------------------
        def d2d_rt_set_antialias_mode(u64 rt, u32 mode) -> void
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, u32) -> void = (u64*)tb[32];
            fn(rt, mode);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1HwndRenderTarget::Resize  (vtable slot 58)
        // ----------------------------------------------------------------
        def d2d_rt_resize(u64 rt, D2D1_SIZE_U* new_size) -> i32
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, D2D1_SIZE_U*) -> i32 = (u64*)tb[58];
            return fn(rt, new_size);
        };

        // ----------------------------------------------------------------
        // ID2D1RenderTarget::DrawText  (vtable slot 27)
        // ----------------------------------------------------------------
        def d2d_rt_draw_text(u64 rt, u16* str, u32 len, u64 text_format, D2D1_RECT_F* layout_rect, u64 brush, u32 options, u32 measuring_mode) -> void
        {
            u64* tb = *(u64**)rt;
            def{}* fn(u64, u16*, u32, u64, D2D1_RECT_F*, u64, u32, u32) -> void = (u64*)tb[27];
            fn(rt, str, len, text_format, layout_rect, brush, options, measuring_mode);
            return;
        };

        // ----------------------------------------------------------------
        // ID2D1SolidColorBrush::SetColor  (vtable slot 8)
        // ----------------------------------------------------------------
        def d2d_brush_set_color(u64 brush, D2D1_COLOR_F* color) -> void
        {
            u64* tb = *(u64**)brush;
            def{}* fn(u64, D2D1_COLOR_F*) -> void = (u64*)tb[8];
            fn(brush, color);
            return;
        };

        // ----------------------------------------------------------------
        // IDWriteFactory::CreateTextFormat  (vtable slot 15)
        // ----------------------------------------------------------------
        def dwrite_create_text_format(
            u64   factory,
            u16*  font_family,
            u64   font_collection,
            u32   font_weight,
            u32   font_style,
            u32   font_stretch,
            float font_size,
            u16*  locale_name,
            u64*  out_format) -> i32
        {
            u64* tb = *(u64**)factory;
            def{}* fn(u64, u16*, u64, u32, u32, u32, float, u16*, u64*) -> i32 = (u64*)tb[15];
            return fn(factory, font_family, font_collection, font_weight, font_style, font_stretch, font_size, locale_name, out_format);
        };

        // ----------------------------------------------------------------
        // IDWriteTextFormat::SetTextAlignment  (vtable slot 3)
        // ----------------------------------------------------------------
        def dwrite_set_text_alignment(u64 fmt, u32 alignment) -> i32
        {
            u64* tb = *(u64**)fmt;
            def{}* fn(u64, u32) -> i32 = (u64*)tb[3];
            return fn(fmt, alignment);
        };

        // ====================================================================
        // D2DCanvas object
        //
        // Drawing interface mirrors GDI Canvas from windows.fx:
        //   clear(DWORD)
        //   set_pen(DWORD color, int width)
        //   line(int x1, int y1, int x2, int y2)
        //   rect(int x1, int y1, int x2, int y2)
        //   fill_rect(int x1, int y1, int x2, int y2)
        //   circle(int cx, int cy, int r)
        //   ellipse(int x1, int y1, int x2, int y2)
        //   pixel(int x, int y, DWORD color)
        //   width() -> int
        //   height() -> int
        //
        // Additional D2D-specific:
        //   begin()   - call before drawing each frame
        //   end()     - call after drawing each frame (presents)
        //   resize(u32 w, u32 h)
        //   draw_text_utf8(byte* text, int x, int y, int w, int h, DWORD color, float font_size)
        // ====================================================================

        object D2DCanvas
        {
            u64 factory,
                render_target,
                brush,
                stroke_style,
                dwrite_factory,
                text_format;

            DWORD pen_color;
            float pen_width;

            u32 canvas_w, canvas_h;

            // UTF-16 scratch buffer for text rendering (max 255 chars)
            u16[256] wstr_buf;

            def __init(HWND hwnd, u32 w, u32 h) -> this
            {
                this.canvas_w  = w;
                this.canvas_h  = h;
                this.pen_color = 0xFFFFFF;
                this.pen_width = 1.0;

                CoInitializeEx((u64*)void, COINIT_APARTMENTTHREADED);

                // Create ID2D1Factory
                D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, (u64*)void, (u64*)void, @this.factory);

                // Build render target properties
                D2D1_RENDER_TARGET_PROPERTIES rtp;
                rtp.renderTargetType      = D2D1_RENDER_TARGET_TYPE_DEFAULT;
                rtp.pixelFormat.format    = DXGI_FORMAT_UNKNOWN;
                rtp.pixelFormat.alphaMode = D2D1_ALPHA_MODE_IGNORE;
                rtp.dpiX                  = 0.0;
                rtp.dpiY                  = 0.0;
                rtp.usage                 = 0;
                rtp.minLevel              = D2D1_FEATURE_LEVEL_DEFAULT;

                // Build hwnd render target properties
                D2D1_HWND_RENDER_TARGET_PROPERTIES hrtp;
                hrtp.hwnd             = hwnd;
                hrtp.pixelSize.width  = w;
                hrtp.pixelSize.height = h;
                hrtp.presentOptions   = D2D1_PRESENT_OPTIONS_NONE;

                d2d_factory_create_hwnd_rt(this.factory, @rtp, @hrtp, @this.render_target);

                // Aliased rendering for crisp graph lines
                d2d_rt_set_antialias_mode(this.render_target, D2D1_ANTIALIAS_MODE_ALIASED);

                // Create initial solid color brush (white)
                D2D1_COLOR_F white;
                white.r = 1.0;
                white.g = 1.0;
                white.b = 1.0;
                white.a = 1.0;
                d2d_rt_create_brush(this.render_target, @white, 0, @this.brush);

                // Create IDWriteFactory
                DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, (u64*)void, @this.dwrite_factory);

                // "Segoe UI" as UTF-16LE
                u16[32] font_name;
                font_name[0] = 83;   // S
                font_name[1] = 101;  // e
                font_name[2] = 103;  // g
                font_name[3] = 111;  // o
                font_name[4] = 101;  // e
                font_name[5] = 32;   // (space)
                font_name[6] = 85;   // U
                font_name[7] = 73;   // I
                font_name[8] = 0;

                // Empty locale string (system default)
                u16[4] locale;
                locale[0] = 0;

                dwrite_create_text_format(
                    this.dwrite_factory,
                    @font_name[0],
                    0,
                    DWRITE_FONT_WEIGHT_NORMAL,
                    DWRITE_FONT_STYLE_NORMAL,
                    DWRITE_FONT_STRETCH_NORMAL,
                    11.0,
                    @locale[0],
                    @this.text_format);

                dwrite_set_text_alignment(this.text_format, DWRITE_TEXT_ALIGNMENT_LEADING);

                return this;
            };

            def __exit() -> void
            {
                com_release(this.text_format);
                com_release(this.dwrite_factory);
                com_release(this.stroke_style);
                com_release(this.brush);
                com_release(this.render_target);
                com_release(this.factory);
                return;
            };

            // ----------------------------------------------------------------
            // begin / end — must bracket every frame
            // ----------------------------------------------------------------

            def begin() -> void
            {
                d2d_rt_begin_draw(this.render_target);
                return;
            };

            def end() -> i32
            {
                u64 tag1, tag2;
                return d2d_rt_end_draw(this.render_target, @tag1, @tag2);
            };

            // ----------------------------------------------------------------
            // clear
            // ----------------------------------------------------------------
            def clear(DWORD color) -> void
            {
                D2D1_COLOR_F cf;
                dword_to_colorf(color, @cf);
                d2d_rt_clear(this.render_target, @cf);
                return;
            };

            // ----------------------------------------------------------------
            // set_pen
            // ----------------------------------------------------------------
            def set_pen(DWORD color, int width) -> void
            {
                this.pen_color = color;
                this.pen_width = (float)width;

                D2D1_COLOR_F cf;
                dword_to_colorf(color, @cf);
                d2d_brush_set_color(this.brush, @cf);

                // Rebuild stroke style for new width
                com_release(this.stroke_style);
                this.stroke_style = 0;

                D2D1_STROKE_STYLE_PROPERTIES ssp;
                ssp.startCap   = D2D1_CAP_STYLE_FLAT;
                ssp.endCap     = D2D1_CAP_STYLE_FLAT;
                ssp.dashCap    = D2D1_CAP_STYLE_FLAT;
                ssp.lineJoin   = D2D1_LINE_JOIN_MITER;
                ssp.miterLimit = 10.0;
                ssp.dashStyle  = D2D1_DASH_STYLE_SOLID;
                ssp.dashOffset = 0.0;

                d2d_factory_create_stroke_style(this.factory, @ssp, (float*)void, 0, @this.stroke_style);
                return;
            };

            // ----------------------------------------------------------------
            // line
            // ----------------------------------------------------------------
            def line(int x1, int y1, int x2, int y2) -> void
            {
                d2d_rt_draw_line(
                    this.render_target,
                    (float)x1 + 0.5, (float)y1 + 0.5,
                    (float)x2 + 0.5, (float)y2 + 0.5,
                    this.brush,
                    this.pen_width,
                    this.stroke_style);
                return;
            };

            // ----------------------------------------------------------------
            // rect  (outlined rectangle)
            // ----------------------------------------------------------------
            def rect(int x1, int y1, int x2, int y2) -> void
            {
                D2D1_RECT_F r;
                r.left   = (float)x1 + 0.5;
                r.top    = (float)y1 + 0.5;
                r.right  = (float)x2 + 0.5;
                r.bottom = (float)y2 + 0.5;
                d2d_rt_draw_rect(this.render_target, @r, this.brush, this.pen_width, this.stroke_style);
                return;
            };

            // ----------------------------------------------------------------
            // fill_rect  (filled rectangle, no outline)
            // ----------------------------------------------------------------
            def fill_rect(int x1, int y1, int x2, int y2) -> void
            {
                D2D1_RECT_F r;
                r.left   = (float)x1;
                r.top    = (float)y1;
                r.right  = (float)x2;
                r.bottom = (float)y2;
                d2d_rt_fill_rect(this.render_target, @r, this.brush);
                return;
            };

            // ----------------------------------------------------------------
            // circle
            // ----------------------------------------------------------------
            def circle(int cx, int cy, int r) -> void
            {
                D2D1_ELLIPSE el;
                el.cx = (float)cx + 0.5;
                el.cy = (float)cy + 0.5;
                el.rx = (float)r;
                el.ry = (float)r;
                d2d_rt_draw_ellipse(this.render_target, @el, this.brush, this.pen_width, this.stroke_style);
                return;
            };

            // ----------------------------------------------------------------
            // ellipse  (bounding-box form matching GDI Ellipse)
            // ----------------------------------------------------------------
            def ellipse(int x1, int y1, int x2, int y2) -> void
            {
                D2D1_ELLIPSE el;
                el.cx = (float)(x1 + x2) * 0.5 + 0.5;
                el.cy = (float)(y1 + y2) * 0.5 + 0.5;
                el.rx = (float)(x2 - x1) * 0.5;
                el.ry = (float)(y2 - y1) * 0.5;
                d2d_rt_draw_ellipse(this.render_target, @el, this.brush, this.pen_width, this.stroke_style);
                return;
            };

            // ----------------------------------------------------------------
            // pixel  (1x1 filled rectangle)
            // ----------------------------------------------------------------
            def pixel(int x, int y, DWORD color) -> void
            {
                D2D1_COLOR_F cf;
                dword_to_colorf(color, @cf);
                d2d_brush_set_color(this.brush, @cf);

                D2D1_RECT_F r;
                r.left   = (float)x;
                r.top    = (float)y;
                r.right  = (float)x + 1.0;
                r.bottom = (float)y + 1.0;
                d2d_rt_fill_rect(this.render_target, @r, this.brush);

                // Restore pen color
                D2D1_COLOR_F pen_cf;
                dword_to_colorf(this.pen_color, @pen_cf);
                d2d_brush_set_color(this.brush, @pen_cf);
                return;
            };

            // ----------------------------------------------------------------
            // draw_text_utf8
            // Renders a null-terminated ASCII string at pixel position (x, y)
            // within a bounding box of size (w x h).
            // ----------------------------------------------------------------
            def draw_text_utf8(byte* text, int x, int y, int w, int h, DWORD color, float font_size) -> void
            {
                int len = ascii_to_utf16(text, @this.wstr_buf[0], 255);
                if (len == 0) { return; };

                D2D1_COLOR_F cf;
                dword_to_colorf(color, @cf);
                d2d_brush_set_color(this.brush, @cf);

                D2D1_RECT_F layout;
                layout.left   = (float)x;
                layout.top    = (float)y;
                layout.right  = (float)(x + w);
                layout.bottom = (float)(y + h);

                d2d_rt_draw_text(
                    this.render_target,
                    @this.wstr_buf[0],
                    (u32)len,
                    this.text_format,
                    @layout,
                    this.brush,
                    0, 0);

                // Restore pen color
                D2D1_COLOR_F pen_cf;
                dword_to_colorf(this.pen_color, @pen_cf);
                d2d_brush_set_color(this.brush, @pen_cf);
                return;
            };

            // ----------------------------------------------------------------
            // width / height
            // ----------------------------------------------------------------
            def width()  -> int { return (int)this.canvas_w; };
            def height() -> int { return (int)this.canvas_h; };

            // ----------------------------------------------------------------
            // resize — call on WM_SIZE
            // ----------------------------------------------------------------
            def resize(u32 w, u32 h) -> void
            {
                this.canvas_w = w;
                this.canvas_h = h;
                D2D1_SIZE_U sz;
                sz.width  = w;
                sz.height = h;
                d2d_rt_resize(this.render_target, @sz);
                return;
            };

        };  // object D2DCanvas

        // ====================================================================
        // D2DWindow
        // Same interface as Window from windows.fx.
        // ====================================================================

        object D2DWindow
        {
            HWND      handle;
            HDC       device_context;
            HINSTANCE instance;
            bool      is_visible;
            byte[64]  class_name;

            def __init(byte* title, int w, int h, int x, int y) -> this
            {
                this.instance = GetModuleHandleA((LPCSTR)void);

                // Class name: "FluxD2DWnd\0"
                this.class_name  = "Flux2DWind\0";
                WNDCLASSEXA wc;
                wc.cbSize        = 72u;
                wc.style         = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
                wc.lpfnWndProc   = (WNDPROC)@DefWindowProcA;
                wc.cbClsExtra    = 0;
                wc.cbWndExtra    = 0;
                wc.hInstance     = this.instance;
                wc.hIcon         = (HICON)0;
                wc.hCursor       = LoadCursorA((HINSTANCE)0, (LPCSTR)32512);
                wc.hbrBackground = (HBRUSH)(NULL_BRUSH + 1);
                wc.lpszMenuName  = (LPCSTR)void;
                wc.lpszClassName = (LPCSTR)this.class_name;
                wc.hIconSm       = (HICON)0;

                RegisterClassExA(@wc);

                this.handle = CreateWindowExA(
                    WS_EX_APPWINDOW,
                    (LPCSTR)this.class_name,
                    (LPCSTR)title,
                    WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                    x, y, w, h,
                    (HWND)0,
                    (HMENU)0,
                    this.instance,
                    STDLIB_GVP);

                this.device_context = GetDC(this.handle);
                ShowWindow(this.handle, SW_SHOW);
                UpdateWindow(this.handle);
                this.is_visible = true;
                return this;
            };

            def __exit() -> void
            {
                if (this.device_context != 0)
                {
                    ReleaseDC(this.handle, this.device_context);
                };
                UnregisterClassA((LPCSTR)this.class_name, this.instance);
                return;
            };

            def show() -> void
            {
                ShowWindow(this.handle, SW_SHOW);
                this.is_visible = true;
                return;
            };

            def hide() -> void
            {
                ShowWindow(this.handle, SW_HIDE);
                this.is_visible = false;
                return;
            };

            def set_title(byte* title) -> void
            {
                SetWindowTextA(this.handle, (LPCSTR)title);
                return;
            };

            def process_messages() -> bool
            {
                MSG msg;
                while (PeekMessageA(@msg, (HWND)0, 0, 0, PM_REMOVE))
                {
                    if (msg.message == WM_QUIT)
                    {
                        return false;
                    };
                    TranslateMessage(@msg);
                    DispatchMessageA(@msg);
                };
                return true;
            };

        };  // object D2DWindow

    };  // namespace d2d
};      // namespace standard

#endif;
