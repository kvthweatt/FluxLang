// redconsole.fx - Flux Console Control Library
//
//
// Provides cursor positioning, color control, and region management
// for building TUI applications without clearing the whole screen.
//
// Windows: Built on top of Win32 Console API (kernel32).
//
// Usage:
//   #import "redconsole.fx";
//   using standard::io::console;
//
//   Console con;
//   con.cursor_set(0, 23);
//   con.set_color(CON_FG_GREEN | CON_BG_BLACK);
//   con.write("Progress: [####      ] 40%\0");
//   con.reset_color();

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_CONSOLE
#def FLUX_STANDARD_CONSOLE 1;

#ifdef __WINDOWS__

extern
{
    def !!
        GetStdHandle(i32)                                              -> i64,
        GetConsoleScreenBufferInfo(i64, void*)                         -> bool,
        SetConsoleCursorPosition(i64, i32)                             -> bool,
        SetConsoleTextAttribute(i64, i16)                              -> bool,
        GetConsoleCursorInfo(i64, void*)                               -> bool,
        SetConsoleCursorInfo(i64, void*)                               -> bool,
        FillConsoleOutputCharacterA(i64, byte, i32, i32, i32*)         -> bool,
        FillConsoleOutputAttribute(i64, i16, i32, i32, i32*)           -> bool,
        WriteConsoleOutputCharacterA(i64, byte*, i32, i32, i32*)       -> bool,
        WriteConsoleOutputAttribute(i64, i16*, i32, i32, i32*)         -> bool,
        ReadConsoleOutputCharacterA(i64, byte*, i32, i32, i32*)        -> bool,
        ReadConsoleOutputAttribute(i64, i16*, i32, i32, i32*)          -> bool,
        ScrollConsoleScreenBufferA(i64, void*, void*, i32, void*)      -> bool,
        SetConsoleWindowInfo(i64, bool, void*)                         -> bool,
        SetConsoleScreenBufferSize(i64, i32)                           -> bool;
};

#endif;

namespace standard
{
    namespace io
    {
        namespace console
        {
            // ============================================================================
            // CONSTANTS
            // ============================================================================

            // Foreground colors
            global i16 CON_FG_BLACK        = (i16)0x0000,
                       CON_FG_DARK_BLUE    = (i16)0x0001,
                       CON_FG_DARK_GREEN   = (i16)0x0002,
                       CON_FG_DARK_CYAN    = (i16)0x0003,
                       CON_FG_DARK_RED     = (i16)0x0004,
                       CON_FG_DARK_MAGENTA = (i16)0x0005,
                       CON_FG_DARK_YELLOW  = (i16)0x0006,
                       CON_FG_GRAY         = (i16)0x0007,
                       CON_FG_DARK_GRAY    = (i16)0x0008,
                       CON_FG_BLUE         = (i16)0x0009,
                       CON_FG_GREEN        = (i16)0x000A,
                       CON_FG_CYAN         = (i16)0x000B,
                       CON_FG_RED          = (i16)0x000C,
                       CON_FG_MAGENTA      = (i16)0x000D,
                       CON_FG_YELLOW       = (i16)0x000E,
                       CON_FG_WHITE        = (i16)0x000F;

            // Background colors
            global i16 CON_BG_BLACK        = (i16)0x0000,
                       CON_BG_DARK_BLUE    = (i16)0x0010,
                       CON_BG_DARK_GREEN   = (i16)0x0020,
                       CON_BG_DARK_CYAN    = (i16)0x0030,
                       CON_BG_DARK_RED     = (i16)0x0040,
                       CON_BG_DARK_MAGENTA = (i16)0x0050,
                       CON_BG_DARK_YELLOW  = (i16)0x0060,
                       CON_BG_GRAY         = (i16)0x0070,
                       CON_BG_DARK_GRAY    = (i16)0x0080,
                       CON_BG_BLUE         = (i16)0x0090,
                       CON_BG_GREEN        = (i16)0x00A0,
                       CON_BG_CYAN         = (i16)0x00B0,
                       CON_BG_RED          = (i16)0x00C0,
                       CON_BG_MAGENTA      = (i16)0x00D0,
                       CON_BG_YELLOW       = (i16)0x00E0,
                       CON_BG_WHITE        = (i16)0x00F0;

            // Attribute flags
            global i16 CON_ATTR_BOLD       = (i16)0x0008,  // Bright/intense foreground
                       CON_ATTR_UNDERLINE  = (i16)0x8000;  // Leading bit - underline on some terminals

            // STD handle IDs
            global i32 CON_STDIN  = (i32)-10,
                       CON_STDOUT = (i32)-11,
                       CON_STDERR = (i32)-12;

            // Default attribute: gray on black (the classic)
            global i16 CON_DEFAULT_ATTR = (i16)0x0007;

            // ============================================================================
            // COORD / SMALL_RECT helpers
            //
            // Win32 COORD   = two packed i16s in one i32  (X in low word, Y in high word)
            // Win32 SMALL_RECT = four packed i16s in two i32s
            //   stored as: { Left, Top, Right, Bottom } each i16
            //   packed as two i32s: (Top<<16|Left), (Bottom<<16|Right)
            // ============================================================================

            def make_coord(i16 x, i16 y) -> i32
            {
                return (i32)x | ((i32)y << 16);
            };

            def coord_x(i32 coord) -> i16
            {
                return (i16)(coord & (i32)0xFFFF);
            };

            def coord_y(i32 coord) -> i16
            {
                return (i16)((coord >> 16) & (i32)0xFFFF);
            };

            // ============================================================================
            // CONSOLE SCREEN BUFFER INFO
            //
            // CONSOLE_SCREEN_BUFFER_INFO layout (22 bytes, but we store as padded struct):
            //   COORD      dwSize              (i32)  offset 0
            //   COORD      dwCursorPosition    (i32)  offset 4
            //   WORD       wAttributes         (i16)  offset 8
            //   SMALL_RECT srWindow            (8 b)  offset 10
            //   COORD      dwMaximumWindowSize (i32)  offset 18
            // We store as byte[22] and extract manually.
            // ============================================================================

            // ============================================================================
            // CONSOLE_CURSOR_INFO layout (8 bytes):
            //   DWORD  dwSize     (i32) offset 0  — cursor height as % of cell (1-100)
            //   BOOL   bVisible   (i32) offset 4
            // ============================================================================

            // ============================================================================
            // Console object
            // ============================================================================

            object Console
            {
                i64  out_handle;
                i64  in_handle;
                i16  saved_attr;
                i32  saved_cursor;   // packed COORD
                i16  width;
                i16  height;

                // Constructor — grabs handles and reads initial buffer size
                def __init() -> this
                {
                    this.out_handle  = GetStdHandle(CON_STDOUT);
                    this.in_handle   = GetStdHandle(CON_STDIN);
                    this.saved_attr  = CON_DEFAULT_ATTR;
                    this.saved_cursor = make_coord((i16)0, (i16)0);
                    this.width       = (i16)80;
                    this.height      = (i16)24;
                    this.refresh_size();
                    return this;
                };

                // ====================================================================
                // Size
                // ====================================================================

                // Refresh cached width/height from the OS buffer info.
                // Call this after a resize event if you care about live dimensions.
                def refresh_size() -> void
                {
                    byte[22] info;
                    bool ok = GetConsoleScreenBufferInfo(this.out_handle, (void*)@info[0]);
                    switch (ok)
                    {
                        case (1)
                        {
                            // dwSize is at offset 0: X=low i16, Y=high i16
                            i16* p = (i16*)@info[0];
                            this.width  = p[0];
                            this.height = p[1];
                        }
                        default {};
                    };
                };

                def get_width() -> i16
                {
                    return this.width;
                };

                def get_height() -> i16
                {
                    return this.height;
                };

                // ====================================================================
                // Cursor
                // ====================================================================

                // Move the cursor to (x, y). Zero-based.
                def cursor_set(i16 x, i16 y) -> void
                {
                    i32 coord = make_coord(x, y);
                    SetConsoleCursorPosition(this.out_handle, coord);
                };

                // Read current cursor position. Returns packed COORD.
                def cursor_get() -> i32
                {
                    byte[22] info;
                    bool ok = GetConsoleScreenBufferInfo(this.out_handle, (void*)@info[0]);
                    switch (ok)
                    {
                        case (1)
                        {
                            // dwCursorPosition is at offset 4
                            i16* p = (i16*)@info[4];
                            return make_coord(p[0], p[1]);
                        }
                        default {};
                    };
                    return make_coord((i16)0, (i16)0);
                };

                // Save current cursor position into this.saved_cursor.
                def cursor_save() -> void
                {
                    this.saved_cursor = this.cursor_get();
                };

                // Restore cursor to previously saved position.
                def cursor_restore() -> void
                {
                    SetConsoleCursorPosition(this.out_handle, this.saved_cursor);
                };

                // Show or hide the cursor. visible=1 shows, visible=0 hides.
                def cursor_visible(bool visible) -> void
                {
                    // CONSOLE_CURSOR_INFO: dwSize (i32) + bVisible (i32)
                    i32[2] ci;
                    GetConsoleCursorInfo(this.out_handle, (void*)@ci[0]);
                    ci[1] = (i32)visible;
                    SetConsoleCursorInfo(this.out_handle, (void*)@ci[0]);
                };

                // ====================================================================
                // Color / Attributes
                // ====================================================================

                // Set text attribute directly (combine CON_FG_* | CON_BG_* constants).
                def set_attr(i16 attr) -> void
                {
                    SetConsoleTextAttribute(this.out_handle, attr);
                };

                // Save the current attribute into this.saved_attr.
                def save_attr() -> void
                {
                    byte[22] info;
                    bool ok = GetConsoleScreenBufferInfo(this.out_handle, (void*)@info[0]);
                    switch (ok)
                    {
                        case (1)
                        {
                            // wAttributes is at offset 8
                            i16* p = (i16*)@info[8];
                            this.saved_attr = p[0];
                        }
                        default {};
                    };
                };

                // Restore saved attribute.
                def restore_attr() -> void
                {
                    SetConsoleTextAttribute(this.out_handle, this.saved_attr);
                };

                // Reset to the default gray-on-black attribute.
                def reset_attr() -> void
                {
                    SetConsoleTextAttribute(this.out_handle, CON_DEFAULT_ATTR);
                };

                // ====================================================================
                // Writing
                // ====================================================================

                // Write a null-terminated string at the current cursor position.
                // Uses the existing print mechanism so formatting stays consistent.
                def write(byte* msg) -> void
                {
                    int len = 0;
                    while (msg[len] != (byte)0) { len = len + 1; };
                    i32 written = 0;
                    WriteConsoleOutputCharacterA(this.out_handle, @msg[0], (i32)len,
                                                 this.cursor_get(), @written);
                    // Advance cursor manually by written columns (same row)
                    i32 cur   = this.cursor_get();
                    i16 nx    = (i16)(coord_x(cur) + (i16)written);
                    i16 ny    = coord_y(cur);
                    this.cursor_set(nx, ny);
                };

                // Write a null-terminated string at an explicit (x, y) without
                // disturbing the logical cursor position.
                def write_at(i16 x, i16 y, byte* msg) -> void
                {
                    i32 saved = this.cursor_get();
                    int len   = 0;
                    while (msg[len] != (byte)0) { len = len + 1; };
                    i32 coord  = make_coord(x, y);
                    i32 written = 0;
                    WriteConsoleOutputCharacterA(this.out_handle, @msg[0], (i32)len,
                                                 coord, @written);
                    SetConsoleCursorPosition(this.out_handle, saved);
                };

                // Write a null-terminated string at (x, y) with a specific attribute,
                // then restore the original attribute and cursor. Good for status lines.
                def write_at_colored(i16 x, i16 y, i16 attr, byte* msg) -> void
                {
                    i32 saved_pos  = this.cursor_get();
                    this.save_attr();
                    int len = 0;
                    while (msg[len] != (byte)0) { len = len + 1; };
                    i32 coord   = make_coord(x, y);
                    i32 written = 0;
                    // Paint attributes first
                    FillConsoleOutputAttribute(this.out_handle, attr, (i32)len, coord, @written);
                    // Then write characters
                    WriteConsoleOutputCharacterA(this.out_handle, @msg[0], (i32)len,
                                                 coord, @written);
                    this.restore_attr();
                    SetConsoleCursorPosition(this.out_handle, saved_pos);
                };

                // ====================================================================
                // Clearing
                // ====================================================================

                // Clear a single line at row y, filling it with spaces.
                // Does not move the logical cursor.
                def clear_line(i16 y) -> void
                {
                    i32 coord   = make_coord((i16)0, y);
                    i32 written = 0;
                    FillConsoleOutputCharacterA(this.out_handle, (byte)' ',
                                                (i32)this.width, coord, @written);
                    FillConsoleOutputAttribute(this.out_handle, CON_DEFAULT_ATTR,
                                               (i32)this.width, coord, @written);
                };

                // Clear a single line at row y with a specific attribute.
                def clear_line_attr(i16 y, i16 attr) -> void
                {
                    i32 coord   = make_coord((i16)0, y);
                    i32 written = 0;
                    FillConsoleOutputCharacterA(this.out_handle, (byte)' ',
                                                (i32)this.width, coord, @written);
                    FillConsoleOutputAttribute(this.out_handle, attr,
                                               (i32)this.width, coord, @written);
                };

                // Clear a rectangular region. All coordinates zero-based.
                def clear_region(i16 x, i16 y, i16 w, i16 h) -> void
                {
                    i16 row = y;
                    while (row < (i16)(y + h))
                    {
                        i32 coord   = make_coord(x, row);
                        i32 written = 0;
                        FillConsoleOutputCharacterA(this.out_handle, (byte)' ',
                                                    (i32)w, coord, @written);
                        FillConsoleOutputAttribute(this.out_handle, CON_DEFAULT_ATTR,
                                                   (i32)w, coord, @written);
                        row = row + (i16)1;
                    };
                };

                // Clear the entire screen and home the cursor.
                def clear_screen() -> void
                {
                    i32 coord   = make_coord((i16)0, (i16)0);
                    i32 cells   = (i32)this.width * (i32)this.height;
                    i32 written = 0;
                    FillConsoleOutputCharacterA(this.out_handle, (byte)' ',
                                                cells, coord, @written);
                    FillConsoleOutputAttribute(this.out_handle, CON_DEFAULT_ATTR,
                                               cells, coord, @written);
                    SetConsoleCursorPosition(this.out_handle, coord);
                };

                // ====================================================================
                // Scrolling
                // ====================================================================

                // Scroll a band of rows [top_row .. bottom_row] up by `lines` rows.
                // Rows that scroll off the top are lost; vacated rows at the bottom
                // are filled with spaces at CON_DEFAULT_ATTR.
                // The status line below bottom_row is untouched.
                def scroll_up(i16 top_row, i16 bottom_row, i16 lines) -> void
                {
                    // SMALL_RECT srScrollRect: Left, Top, Right, Bottom (each i16)
                    // Packed as two i32s for the FFI.
                    // Layout: word0 = (Top<<16 | Left), word1 = (Bottom<<16 | Right)
                    i32[2] scroll_rect;
                    scroll_rect[0] = (i32)0 | ((i32)top_row << 16);
                    scroll_rect[1] = ((i32)(this.width - (i16)1)) | ((i32)bottom_row << 16);

                    // dwDestinationOrigin COORD: scroll up = new top starts at top_row - lines
                    i32 dest = make_coord((i16)0, (i16)(top_row - lines));

                    // CHAR_INFO fill: character + attribute (4 bytes: i16 char, i16 attr)
                    i32 fill = (i32)' ' | ((i32)CON_DEFAULT_ATTR << 16);

                    ScrollConsoleScreenBufferA(this.out_handle,
                                               (void*)@scroll_rect[0],
                                               (void*)0,
                                               dest,
                                               (void*)@fill);
                };

                // ====================================================================
                // Progress bar helper
                //
                // Draws a progress bar pinned to `row`, spanning the full console width.
                // `done` and `total` are arbitrary units; bar fills proportionally.
                // `label` is a short null-terminated prefix shown before the bar.
                //
                // Example output (width=60, label="Build"):
                //   Build [####################          ] 50%
                // ====================================================================

                def progress_bar(i16 row, byte* label, i32 done, i32 total) -> void
                {
                    // Clamp
                    switch (total <= (i32)0) { case (1) { total = (i32)1; } default {}; };
                    switch (done > total)    { case (1) { done  = total;  } default {}; };
                    switch (done < (i32)0)   { case (1) { done  = (i32)0; } default {}; };

                    // Measure label length
                    int llen = 0;
                    while (label[llen] != (byte)0) { llen = llen + 1; };

                    // Bar area: " [" + bar + "] NNN%" = width - llen - 8 min
                    int bar_width = (int)this.width - llen - 8;
                    switch (bar_width < (int)4) { case (1) { bar_width = (int)4; } default {}; };

                    int filled = (done * bar_width) / total;

                    // Build into a stack buffer (max 512 chars)
                    byte[512] buf;
                    int bi = 0;

                    // Copy label
                    int li = 0;
                    while (li < llen & bi < 510)
                    {
                        buf[bi] = label[li];
                        bi = bi + 1;
                        li = li + 1;
                    };

                    buf[bi] = (byte)' '; bi = bi + 1;
                    buf[bi] = (byte)'['; bi = bi + 1;

                    int fi = 0;
                    while (fi < filled & bi < 510)
                    {
                        buf[bi] = (byte)'#';
                        bi = bi + 1;
                        fi = fi + 1;
                    };
                    while (fi < bar_width & bi < 510)
                    {
                        buf[bi] = (byte)' ';
                        bi = bi + 1;
                        fi = fi + 1;
                    };

                    buf[bi] = (byte)']'; bi = bi + 1;
                    buf[bi] = (byte)' '; bi = bi + 1;

                    // Percentage digits (0-100)
                    int pct = (done * 100) / total;
                    int hundreds = pct / 100;
                    int tens     = (pct / 10) % 10;
                    int ones     = pct % 10;

                    switch (hundreds > 0)
                    {
                        case (1)
                        {
                            buf[bi] = (byte)('0' + hundreds); bi = bi + 1;
                            buf[bi] = (byte)('0' + tens);     bi = bi + 1;
                        }
                        default
                        {
                            switch (tens > 0)
                            {
                                case (1) { buf[bi] = (byte)('0' + tens); bi = bi + 1; }
                                default  {};
                            };
                        };
                    };
                    buf[bi] = (byte)('0' + ones); bi = bi + 1;
                    buf[bi] = (byte)'%';           bi = bi + 1;

                    // Pad remainder with spaces so we overwrite any leftover chars
                    while (bi < (int)this.width & bi < 511)
                    {
                        buf[bi] = (byte)' ';
                        bi = bi + 1;
                    };
                    buf[bi] = (byte)0;

                    // Write at the pinned row without disturbing cursor
                    this.write_at_colored(
                        (i16)0, row,
                        (i16)(CON_FG_GREEN | CON_BG_BLACK),
                        @buf[0]
                    );
                };

                // ====================================================================
                // Spinner helper
                //
                // Draws a single spinning character at (x, y).
                // Call repeatedly, incrementing `tick` each time.
                // ====================================================================

                def spinner(i16 x, i16 y, i32 tick) -> void
                {
                    byte[5] frames;
                    frames[0] = (byte)'-';
                    frames[1] = (byte)'\\';
                    frames[2] = (byte)'|';
                    frames[3] = (byte)'/';
                    frames[4] = (byte)0;
                    byte ch = frames[tick & (i32)3];
                    byte[2] buf;
                    buf[0] = ch;
                    buf[1] = (byte)0;
                    this.write_at(x, y, @buf[0]);
                };
            };
        };
    };
};

#endif;
