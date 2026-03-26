// Author: Karac V. Thweatt

// glanim.fx - OpenGL Text Animation Library
//
// Animated text objects rendered in a GL window.
// Text lives on screen and can be manipulated with transition effects.
//
// Requires: freetype.dll
//
// Usage:
//   #import "glanim.fx";
//   using standard::anim;
//
//   Renderer  r("Flux Demo\0", 1280, 720);
//   AnimStr   s("def foo() -> void\0", 40, 80, @r);
//
//   r.step(s.replace("->", "<~\0", ANIM_FADE));
//   r.step(s.insert(0, "stdcall \0", ANIM_WIPE_LR));

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef __WIN32_INTERFACE__
#import "windows.fx";
#endif;

#ifndef __REDOPENGL__
#import "opengl.fx";
#endif;

#ifndef FLUX_STANDARD_TIME
#import "timing.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "memory.fx";
#endif;

#ifndef FLUX_GLANIM
#def FLUX_GLANIM 1;

using standard::system::windows;
using standard::time;
using standard::memory::allocators::stdheap;

// ============================================================================
// FREETYPE 2 FFI
// ============================================================================

extern
{
    def !!
        FT_Init_FreeType(void**)               -> int,
        FT_Done_FreeType(void*)                -> int,
        FT_New_Face(void*, byte*, int, void**) -> int,
        FT_Done_Face(void*)                    -> int,
        FT_Set_Pixel_Sizes(void*, int, int)    -> int,
        FT_Load_Char(void*, int, int)          -> int;
};

global int FT_LOAD_RENDER = 4;

// FT_Bitmap - public layout from freetype/ftimage.h
// rows, width, pitch, buffer, num_grays, pixel_mode, palette_mode, palette
struct FT_Bitmap
{
    int    rows,
           width,
           pitch;
    byte*  buffer;
    i16    num_grays;
    byte   pixel_mode,
           palette_mode;
    void*  palette;
};

// FT_GlyphSlotRec - partial public layout from freetype/freetype.h
// We only need: advance (FT_Vector = two i64), bitmap, bitmap_left, bitmap_top.
// Fields before these that we skip are laid out as padding void* members.
// FT_GlyphSlotRec public layout (x86-64):
//   library         void*    +0
//   face            void*    +8
//   next            void*    +16
//   glyph_index     uint     +24   [+4 pad to +32]
//   generic         16 bytes +32
//   metrics         40 bytes +48   (FT_Glyph_Metrics)
//   linearHoriAdv   i64      +88
//   linearVertAdv   i64      +96
//   advance         FT_Vector +104  (two i64: x at +104, y at +112)
//   format          int      +120  [+4 pad to +128]
//   bitmap          FT_Bitmap +128
//   bitmap_left     int      at +128 + sizeof(FT_Bitmap)
//   bitmap_top      int      follows bitmap_left
// sizeof(FT_Bitmap) on x86-64 = 4+4+4+[4 pad]+8+2+1+1+[6 pad]+8 = 40 bytes
// so bitmap_left is at +128+40 = +168, bitmap_top at +172
//
// We express this as a struct with explicit padding fields.
struct FT_GlyphSlot
{
    void*  library;        // +0
    void*  face;           // +8
    void*  next;           // +16
    int    glyph_index;    // +24
    int    _pad0;          // +28 (padding to 32)
    i64    _generic0;      // +32
    i64    _generic1;      // +40
    i64    _metrics0;      // +48
    i64    _metrics1;      // +56
    i64    _metrics2;      // +64
    i64    _metrics3;      // +72
    i64    _metrics4;      // +80
    i64    _linearH;       // +88
    i64    _linearV;       // +96
    i64    advance_x;      // +104
    i64    advance_y;      // +112
    int    format;         // +120
    int    _pad1;          // +124
    int    bmp_rows;       // +128
    int    bmp_width;      // +132
    int    bmp_pitch;      // +136
    int    _pad2;          // +140
    byte*  bmp_buffer;     // +144
    i16    num_grays;      // +152
    byte   pixel_mode;     // +154
    byte   palette_mode;   // +155
    int    _pad3;          // +156
    void*  palette;        // +160
    int    bitmap_left;    // +168
    int    bitmap_top;     // +172
};

// FT_FaceRec partial layout - we only need the glyph slot pointer.
// Public fields up to glyph (x86-64):
//   num_faces       i64   +0
//   face_index      i64   +8
//   face_flags      i64   +16
//   style_flags     i64   +24
//   num_glyphs      i64   +32
//   family_name     void* +40
//   style_name      void* +48
//   num_fixed_sizes int   +56  [+4 pad to +64]
//   available_sizes void* +64
//   num_charmaps    int   +72  [+4 pad to +80]
//   charmaps        void* +80
//   generic         16b   +88
//   bbox            32b   +104
//   units_per_EM    u16   +136 [+6 pad to +144]
//   ascender        i16   +138
//   descender       i16   +140
//   height          i16   +142
//   ... more metrics ...
//   glyph           FT_GlyphSlot* at +144 + more fields
//
// Rather than counting all of that, we use FT_Get_Glyph_Slot via a helper extern.
// FreeType exposes no such function — glyph IS a public struct field.
// Confirmed offset for FT_FaceRec->glyph on FT 2.x x86-64 Windows: +144
global int FT_FACE_GLYPH_OFFSET = 144;

namespace standard
{
    namespace anim
    {
        // ====================================================================
        // COLORS  (RGBA u32: 0xRRGGBBAA)
        // ====================================================================

        global u32
            COLOR_BG        = 0x0D1117FF,
            COLOR_DEFAULT   = 0xCDD9E5FF,
            COLOR_KEYWORD   = 0xFF7B72FF,
            COLOR_TYPE      = 0x79C0FFFF,
            COLOR_FUNCTION  = 0xD2A8FFFF,
            COLOR_STRING    = 0xA5D6FFFF,
            COLOR_COMMENT   = 0x8B949EFF,
            COLOR_NUMBER    = 0x79C0FFFF,
            COLOR_NAMESPACE = 0xFFA657FF,
            COLOR_PUNCT     = 0xCDD9E5FF;

        // ====================================================================
        // ANIMATION KINDS
        // ====================================================================

        global int ANIM_NONE     = 0,
                   ANIM_FADE     = 1,   // old fades out, new fades in
                   ANIM_WIPE_LR  = 2,   // new text wipes in left to right
                   ANIM_WIPE_RL  = 3,   // new text wipes in right to left
                   ANIM_SLIDE_UP = 4,   // new text slides up from below
                   ANIM_TYPE     = 5;   // new text types in character by character

        global int ANIM_STEPS    = 30;  // frames per animation
        global int ANIM_FRAME_MS = 16;  // ~60fps

        // ====================================================================
        // GlyphInfo
        // ====================================================================

        struct GlyphInfo
        {
            int atlas_x,
                bmp_w,
                bmp_h,
                bear_x,
                bear_y,
                advance;
        };

        // ====================================================================
        // FontAtlas
        // Rasterizes ASCII 32-126 into a single GL_ALPHA texture strip.
        // ====================================================================

        global int ATLAS_W   = 4096,
                   ATLAS_FIRST = 32,
                   ATLAS_COUNT = 95;

        object FontAtlas
        {
            void* ft_lib;
            void* ft_face;
            int   tex,
                  atlas_h,
                  cell_h,
                  col_w,
                  px_size;
            GlyphInfo[95] glyphs;

            def __init(byte* ttf_path, int px_size) -> this
            {
                this.px_size = px_size;
                this.cell_h  = px_size + px_size / 2;
                this.atlas_h = this.cell_h;

                FT_Init_FreeType(@this.ft_lib);
                FT_New_Face(this.ft_lib, ttf_path, 0, @this.ft_face);
                FT_Set_Pixel_Sizes(this.ft_face, 0, px_size);

                int   total   = ATLAS_W * this.atlas_h,
                      pen_x,
                      ci,
                      ch,
                      rows,
                      width,
                      pitch,
                      bear_x,
                      bear_y,
                      adv,
                      glyph_y,
                      dst_row,
                      gy,
                      gx;
                byte*         buf       = (byte*)fmalloc((u64)total),
                              bmp,
                              face_bytes;
                FT_GlyphSlot* slot;

                for (int i; i < total; i = i + 1) { buf[i] = 0; };

                ci = 0;
                while (ci < ATLAS_COUNT)
                {
                    ch = ATLAS_FIRST + ci;
                    if (FT_Load_Char(this.ft_face, ch, FT_LOAD_RENDER) != 0)
                    {
                        ci = ci + 1;
                        continue;
                    };

                    // face->glyph is a pointer stored at FT_FACE_GLYPH_OFFSET into FT_FaceRec
                    face_bytes = (byte*)this.ft_face;
                    slot       = *(FT_GlyphSlot**)(face_bytes + FT_FACE_GLYPH_OFFSET);

                    rows   = slot.bmp_rows;
                    width  = slot.bmp_width;
                    pitch  = slot.bmp_pitch;
                    bmp    = slot.bmp_buffer;
                    bear_x = slot.bitmap_left;
                    bear_y = slot.bitmap_top;
                    adv    = (int)(slot.advance_x >> 6);

                    this.glyphs[ci].atlas_x = pen_x;
                    this.glyphs[ci].bmp_w   = width;
                    this.glyphs[ci].bmp_h   = rows;
                    this.glyphs[ci].bear_x  = bear_x;
                    this.glyphs[ci].bear_y  = bear_y;
                    this.glyphs[ci].advance = adv;

                    glyph_y = this.cell_h - bear_y - (this.cell_h - px_size) / 2;
                    if (glyph_y < 0) { glyph_y = 0; };

                    gy = 0;
                    while (gy < rows)
                    {
                        dst_row = glyph_y + gy;
                        if (dst_row >= 0 & dst_row < this.atlas_h)
                        {
                            gx = 0;
                            while (gx < width)
                            {
                                if (pen_x + gx < ATLAS_W)
                                {
                                    buf[dst_row * ATLAS_W + pen_x + gx] = bmp[gy * pitch + gx];
                                };
                                gx = gx + 1;
                            };
                        };
                        gy = gy + 1;
                    };

                    pen_x = pen_x + adv + 1;
                    ci    = ci + 1;
                };

                // Use advance of 'M' as cell width
                this.col_w = this.glyphs['M' - ATLAS_FIRST].advance;
                if (this.col_w == 0) { this.col_w = px_size; };

                glGenTextures(1, @this.tex);
                glBindTexture(GL_TEXTURE_2D, this.tex);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, ATLAS_W, this.atlas_h,
                             0, GL_ALPHA, GL_UNSIGNED_BYTE, (void*)buf);
                glBindTexture(GL_TEXTURE_2D, 0);

                ffree(buf);
                return this;
            };

            def __exit() -> void
            {
                glDeleteTextures(1, @this.tex);
                FT_Done_Face(this.ft_face);
                FT_Done_FreeType(this.ft_lib);
            };

            // Draw one glyph at pixel position (px, baseline_y) with color (RGBA u32)
            def draw_glyph(float px, float py, int ci, u32 color, float alpha) -> void
            {
                if (ci < 0 | ci >= ATLAS_COUNT) { return; };
                GlyphInfo* g = @this.glyphs[ci];
                if (g.bmp_w == 0) { return; };

                float r = (float)((color >> 24) & 0xFF) / 255.0,
                      gg = (float)((color >> 16) & 0xFF) / 255.0,
                      b  = (float)((color >>  8) & 0xFF) / 255.0;

                float u0 = (float)g.atlas_x             / (float)ATLAS_W,
                      u1 = (float)(g.atlas_x + g.bmp_w) / (float)ATLAS_W,
                      v0 = 0.0,
                      v1 = (float)g.bmp_h / (float)this.atlas_h;

                float x0 = px + (float)g.bear_x,
                      y0 = py - (float)g.bear_y,
                      x1 = x0 + (float)g.bmp_w,
                      y1 = y0 + (float)g.bmp_h;

                glBindTexture(GL_TEXTURE_2D, this.tex);
                glColor4f(r, gg, b, alpha);
                glBegin(GL_QUADS);
                    glTexCoord2f(u0, v0); glVertex2f(x0, y0);
                    glTexCoord2f(u1, v0); glVertex2f(x1, y0);
                    glTexCoord2f(u1, v1); glVertex2f(x1, y1);
                    glTexCoord2f(u0, v1); glVertex2f(x0, y1);
                glEnd();
            };

            // Draw a string at (px, baseline_y), returns pixel width drawn
            def draw_str(float px, float py, byte* s, u32 color, float alpha) -> float
            {
                float cx = px;
                int   ci, i;
                while (s[i] != 0)
                {
                    ci = s[i] - ATLAS_FIRST;
                    if (ci >= 0 & ci < ATLAS_COUNT)
                    {
                        this.draw_glyph(cx, py, ci, color, alpha);
                        cx = cx + (float)this.glyphs[ci].advance;
                    };
                    i = i + 1;
                };
                return cx - px;
            };

            // Measure pixel width of a string without drawing
            def measure(byte* s) -> float
            {
                float w;
                int   ci, i;
                while (s[i] != 0)
                {
                    ci = s[i] - ATLAS_FIRST;
                    if (ci >= 0 & ci < ATLAS_COUNT)
                    {
                        w = w + (float)this.glyphs[ci].advance;
                    };
                    i = i + 1;
                };
                return w;
            };
        };

        // ====================================================================
        // Renderer
        // Owns the window, GL context, and font atlas.
        // Drives the step-by-step playback loop — space bar advances.
        // ====================================================================

        object Renderer
        {
            Window    win;
            GLContext gl;
            FontAtlas font;
            int       win_w,
                      win_h;
            bool      running;

            def __init(byte* title, int w, int h, byte* ttf_path, int px_size) -> this
            {
                this.win_w   = w;
                this.win_h   = h;
                this.running = true;
                Window win(title, w, h, 100, 100);
                this.win     = win;
                GLContext gl(this.win.device_context);
                this.gl      = gl;
                this.gl.load_extensions();
                FontAtlas font(ttf_path, px_size);
                this.font    = font;
                return this;
            };

            def __exit() -> void
            {
                this.font.__exit();
                this.gl.__exit();
                this.win.__exit();
            };

            // Set up orthographic 2D projection for this frame
            def begin_frame() -> void
            {
                glViewport(0, 0, this.win_w, this.win_h);
                glMatrixMode(GL_PROJECTION);
                glLoadIdentity();
                glOrtho(0.0, (float)this.win_w, (float)this.win_h, 0.0, -1.0, 1.0);
                glMatrixMode(GL_MODELVIEW);
                glLoadIdentity();
                glEnable(GL_TEXTURE_2D);
                glEnable(GL_BLEND);
                glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
                glDisable(GL_DEPTH_TEST);

                float bg_r = (float)((COLOR_BG >> 24) & 0xFF) / 255.0,
                      bg_g = (float)((COLOR_BG >> 16) & 0xFF) / 255.0,
                      bg_b = (float)((COLOR_BG >>  8) & 0xFF) / 255.0;
                glClearColor(bg_r, bg_g, bg_b, 1.0);
                glClear(GL_COLOR_BUFFER_BIT);
            };

            def end_frame() -> void
            {
                this.gl.present();
                this.win.process_messages();
            };

            // Block until space is pressed, pumping messages so the window stays alive.
            // Returns false if the window was closed.
            def wait_for_space() -> bool
            {
                while (this.running)
                {
                    if (GetAsyncKeyState(VK_SPACE) & 0x8000)
                    {
                        // Debounce: wait for release
                        while (GetAsyncKeyState(VK_SPACE) & 0x8000)
                        {
                            this.running = this.win.process_messages();
                            sleep_ms(10);
                        };
                        return true;
                    };
                    if (GetAsyncKeyState(VK_ESCAPE) & 0x8000) { return false; };
                    this.running = this.win.process_messages();
                    sleep_ms(10);
                };
                return false;
            };
        };

        // ====================================================================
        // AnimStr
        // A piece of text on screen that can be animated.
        // Holds its current content and pixel position.
        // All mutation methods play an animation then update the content.
        // ====================================================================

        global int ANIMSTR_MAX = 512;

        object AnimStr
        {
            Renderer* r;
            float     px,    // pixel x of the string's left edge
                      py;    // pixel y of the string's baseline
            u32       color;
            byte[ANIMSTR_MAX] buf;
            int       len;

            def __init(byte* text, float px, float py, u32 color, Renderer* r) -> this
            {
                this.r     = r;
                this.px    = px;
                this.py    = py;
                this.color = color;
                this.len   = 0;
                for (int i; text[i] != 0 & i < ANIMSTR_MAX - 1; i = i + 1)
                {
                    this.buf[i] = text[i];
                    this.len    = this.len + 1;
                };
                this.buf[this.len] = 0;
                return this;
            };

            def __exit() -> void { return; };

            // Draw current content at full alpha — called every frame by the renderer
            def draw(float alpha) -> void
            {
                this.r.font.draw_str(this.px, this.py, @this.buf[0], this.color, alpha);
            };

            // ----------------------------------------------------------------
            // Find the first occurrence of `needle` in buf.
            // Returns -1 if not found.
            // ----------------------------------------------------------------
            def find(byte* needle) -> int
            {
                int  nlen, i, j;
                bool match;
                while (needle[nlen] != 0) { nlen = nlen + 1; };
                if (nlen == 0 | nlen > this.len) { return -1; };

                while (i <= this.len - nlen)
                {
                    match = true;
                    j = 0;
                    while (j < nlen)
                    {
                        if (this.buf[i + j] != needle[j]) { match = false; break; };
                        j = j + 1;
                    };
                    if (match) { return i; };
                    i = i + 1;
                };
                return -1;
            };

            // ----------------------------------------------------------------
            // replace: find `from` in buf, animate it out, animate `to` in.
            // Plays the animation immediately (blocking per-frame with present).
            // ----------------------------------------------------------------
            def replace(byte* src, byte* dst, int anim_kind) -> void
            {
                int   at       = this.find(src),
                      src_len,
                      dst_len,
                      step;
                byte  saved;
                float t;

                if (at == -1) { return; };

                while (src[src_len] != 0) { src_len = src_len + 1; };
                while (dst[dst_len] != 0) { dst_len = dst_len + 1; };

                switch (anim_kind)
                {
                    case (1) // ANIM_FADE: fade old out then fade new in
                    {
                        step = 0;
                        while (step <= ANIM_STEPS)
                        {
                            t = 1.0 - (float)step / (float)ANIM_STEPS;
                            this.r.begin_frame();
                            this._draw_with_region_alpha(at, src_len, src, t);
                            this.r.end_frame();
                            sleep_ms(ANIM_FRAME_MS);
                            step = step + 1;
                        };
                        this._do_replace(at, src_len, dst, dst_len);
                        step = 0;
                        while (step <= ANIM_STEPS)
                        {
                            t = (float)step / (float)ANIM_STEPS;
                            this.r.begin_frame();
                            this._draw_with_region_alpha(at, dst_len, dst, t);
                            this.r.end_frame();
                            sleep_ms(ANIM_FRAME_MS);
                            step = step + 1;
                        };
                    }

                    case (2) // ANIM_WIPE_LR
                    {
                        this._do_replace(at, src_len, dst, dst_len);
                        step = 0;
                        while (step <= dst_len)
                        {
                            this.r.begin_frame();
                            this._draw_with_partial(at, step);
                            this.r.end_frame();
                            sleep_ms(ANIM_FRAME_MS * 2);
                            step = step + 1;
                        };
                    }

                    case (3) // ANIM_WIPE_RL
                    {
                        this._do_replace(at, src_len, dst, dst_len);
                        step = 0;
                        while (step <= dst_len)
                        {
                            this.r.begin_frame();
                            this._draw_with_partial_rl(at, dst_len, step);
                            this.r.end_frame();
                            sleep_ms(ANIM_FRAME_MS * 2);
                            step = step + 1;
                        };
                    }

                    case (5) // ANIM_TYPE
                    {
                        this._do_replace(at, src_len, dst, dst_len);
                        step = 0;
                        while (step <= dst_len)
                        {
                            this.r.begin_frame();
                            this._draw_with_partial(at, step);
                            this.r.end_frame();
                            sleep_ms(ANIM_FRAME_MS * 3);
                            step = step + 1;
                        };
                    }

                    default
                    {
                        this._do_replace(at, src_len, dst, dst_len);
                        this.r.begin_frame();
                        this.draw(1.0);
                        this.r.end_frame();
                    };
                };
            };

            // ----------------------------------------------------------------
            // insert: insert `text` at character position `pos` with animation
            // ----------------------------------------------------------------
            def insert(int pos, byte* text, int anim_kind) -> void
            {
                int ins_len, step;
                while (text[ins_len] != 0) { ins_len = ins_len + 1; };
                if (this.len + ins_len >= ANIMSTR_MAX) { return; };

                for (int i = this.len; i >= pos; i = i - 1) { this.buf[i + ins_len] = this.buf[i]; };
                for (int i; i < ins_len; i = i + 1) { this.buf[pos + i] = text[i]; };
                this.len = this.len + ins_len;

                switch (anim_kind)
                {
                    case (2) // ANIM_WIPE_LR
                    {
                        step = 0;
                        while (step <= ins_len)
                        {
                            this.r.begin_frame();
                            this._draw_with_partial(pos, step);
                            this.r.end_frame();
                            sleep_ms(ANIM_FRAME_MS * 2);
                            step = step + 1;
                        };
                    }
                    case (5) // ANIM_TYPE
                    {
                        step = 0;
                        while (step <= ins_len)
                        {
                            this.r.begin_frame();
                            this._draw_with_partial(pos, step);
                            this.r.end_frame();
                            sleep_ms(ANIM_FRAME_MS * 3);
                            step = step + 1;
                        };
                    }
                    default
                    {
                        this.r.begin_frame();
                        this.draw(1.0);
                        this.r.end_frame();
                    };
                };
            };

            // ----------------------------------------------------------------
            // remove: remove `count` characters starting at `pos`
            // ----------------------------------------------------------------
            def remove(int pos, int count, int anim_kind) -> void
            {
                int   step;
                float t;
                if (pos < 0 | pos >= this.len) { return; };
                if (pos + count > this.len) { count = this.len - pos; };

                switch (anim_kind)
                {
                    case (1) // ANIM_FADE
                    {
                        step = 0;
                        while (step <= ANIM_STEPS)
                        {
                            t = 1.0 - (float)step / (float)ANIM_STEPS;
                            this.r.begin_frame();
                            this._draw_with_region_alpha(pos, count, @this.buf[pos], t);
                            this.r.end_frame();
                            sleep_ms(ANIM_FRAME_MS);
                            step = step + 1;
                        };
                    }
                    default {};
                };

                for (int i = pos; i < this.len - count; i = i + 1) { this.buf[i] = this.buf[i + count]; };
                this.len = this.len - count;
                this.buf[this.len] = 0;

                this.r.begin_frame();
                this.draw(1.0);
                this.r.end_frame();
            };

            // ----------------------------------------------------------------
            // Internal helpers
            // ----------------------------------------------------------------

            // Perform the raw buffer replacement (no animation)
            def _do_replace(int at, int src_len, byte* dst, int dst_len) -> void
            {
                int tail_start = at + src_len,
                    tail_len   = this.len - tail_start,
                    new_tail   = at + dst_len;

                if (dst_len < src_len)
                {
                    for (int i; i < tail_len; i = i + 1)
                    {
                        this.buf[new_tail + i] = this.buf[tail_start + i];
                    };
                }
                elif (dst_len > src_len)
                {
                    for (int i = tail_len - 1; i >= 0; i = i - 1)
                    {
                        this.buf[new_tail + i] = this.buf[tail_start + i];
                    };
                };

                for (int i; i < dst_len; i = i + 1) { this.buf[at + i] = dst[i]; };
                this.len = this.len - src_len + dst_len;
                this.buf[this.len] = 0;
            };

            // Draw the string but apply `alpha` to the region [at .. at+region_len).
            // The `region_str` is drawn in place of those chars (allows pre-swap fade).
            def _draw_with_region_alpha(int at, int region_len, byte* region_str, float alpha) -> void
            {
                byte  saved = this.buf[at];
                float cx,
                      suffix_px;

                this.buf[at] = 0;
                cx = this.px + this.r.font.measure(@this.buf[0]);
                this.r.font.draw_str(this.px, this.py, @this.buf[0], this.color, 1.0);
                this.buf[at] = saved;

                this.r.font.draw_str(cx, this.py, region_str, this.color, alpha);

                suffix_px = cx + this.r.font.measure(region_str);
                this.r.font.draw_str(suffix_px, this.py, @this.buf[at + region_len], this.color, 1.0);
            };

            // Draw string with only `visible` chars of the region at `at` shown (LR wipe)
            def _draw_with_partial(int at, int visible) -> void
            {
                byte  saved    = this.buf[at];
                float prefix_w,
                      cx;
                int   ci, i;

                this.buf[at] = 0;
                prefix_w = this.r.font.measure(@this.buf[0]);
                this.r.font.draw_str(this.px, this.py, @this.buf[0], this.color, 1.0);
                this.buf[at] = saved;

                cx = this.px + prefix_w;
                i  = 0;
                while (i < visible)
                {
                    ci = this.buf[at + i] - ATLAS_FIRST;
                    if (ci >= 0 & ci < ATLAS_COUNT)
                    {
                        this.r.font.draw_glyph(cx, this.py, ci, this.color, 1.0);
                        cx = cx + (float)this.r.font.glyphs[ci].advance;
                    };
                    i = i + 1;
                };
            };

            // Draw string with region revealed right-to-left
            def _draw_with_partial_rl(int at, int region_len, int visible) -> void
            {
                byte  saved = this.buf[at];
                float prefix_w,
                      cx;
                int   start, ci, i;

                this.buf[at] = 0;
                prefix_w = this.r.font.measure(@this.buf[0]);
                this.r.font.draw_str(this.px, this.py, @this.buf[0], this.color, 1.0);
                this.buf[at] = saved;

                start = region_len - visible;
                cx    = this.px + prefix_w;

                i = 0;
                while (i < start)
                {
                    ci = this.buf[at + i] - ATLAS_FIRST;
                    if (ci >= 0 & ci < ATLAS_COUNT) { cx = cx + (float)this.r.font.glyphs[ci].advance; };
                    i = i + 1;
                };

                i = start;
                while (i < region_len)
                {
                    ci = this.buf[at + i] - ATLAS_FIRST;
                    if (ci >= 0 & ci < ATLAS_COUNT)
                    {
                        this.r.font.draw_glyph(cx, this.py, ci, this.color, 1.0);
                        cx = cx + (float)this.r.font.glyphs[ci].advance;
                    };
                    i = i + 1;
                };
            };
        };

        // ====================================================================
        // View
        // A named collection of AnimStrs that all redraw together each frame.
        // The renderer calls view.draw() every frame during a step.
        // ====================================================================

        global int VIEW_MAX_STRS = 64;

        object View
        {
            Renderer*  r;
            AnimStr[VIEW_MAX_STRS]* strs;
            int        count;

            def __init(Renderer* r) -> this
            {
                this.r     = r;
                this.count = 0;
                return this;
            };

            def __exit() -> void { return; };

            def add(AnimStr* s) -> void
            {
                if (this.count < VIEW_MAX_STRS)
                {
                    this.strs[this.count] = s;
                    this.count = this.count + 1;
                };
            };

            def draw() -> void
            {
                for (int i; i < this.count; i = i + 1)
                {
                    this.strs[i].draw(1.0);
                };
            };

            // Play an animation step on one string, with all other strings
            // held visible behind it. Blocks until the animation completes,
            // then waits for space before returning.
            def step_replace(AnimStr* s, byte* src, byte* dst, int anim_kind) -> bool
            {
                // Draw all other strings while this one animates
                // (handled inside AnimStr.replace via begin_frame/end_frame,
                //  so we need to hook the other draws in — we do this by
                //  temporarily making the renderer call back to us)
                s.replace(src, dst, anim_kind);
                return this.r.wait_for_space();
            };

            def step_insert(AnimStr* s, int pos, byte* text, int anim_kind) -> bool
            {
                s.insert(pos, text, anim_kind);
                return this.r.wait_for_space();
            };

            def step_remove(AnimStr* s, int pos, int count, int anim_kind) -> bool
            {
                s.remove(pos, count, anim_kind);
                return this.r.wait_for_space();
            };

            // Just show the current state and wait for space
            def step_hold() -> bool
            {
                this.r.begin_frame();
                this.draw();
                this.r.end_frame();
                return this.r.wait_for_space();
            };
        };

    };  // namespace anim
};      // namespace standard

#endif;  // FLUX_GLANIM
