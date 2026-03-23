// demo_console.fx - Demo for the redconsole.fx library
//
// Demonstrates:
//   - Console setup and size querying
//   - Cursor movement and visibility
//   - Color and attribute control
//   - write / write_at / write_at_colored
//   - clear_line / clear_region / clear_screen
//   - progress_bar helper
//   - spinner helper
//   - Screen save/restore (like old DOS programs)

#import "standard.fx";
#import "console.fx";

using standard::io::console;

def main() -> int
{
    Console con;
    con.__init();

    // Console.__init() calls GetStdHandle(CON_STDOUT) but CON_STDOUT is a
    // zero-initialized global (compiler does not emit initializers), so it
    // calls GetStdHandle(0) and gets an invalid handle.
    // WIN_STDOUT_HANDLE is set correctly at runtime startup with the literal
    // -11, so we overwrite the first field (out_handle, i64) of the struct.
    i64* handle_ptr = (i64*)@con;
    handle_ptr[0] = WIN_STDOUT_HANDLE;

    // Also refresh size now that we have a valid handle
    con.refresh_size();

    // ====================================================================
    // Save the current screen contents before we start
    // ====================================================================
    i16 w = con.get_width(),
        h = con.get_height();
    
    // Calculate total cells
    i32 total_cells = w * h;
    
    // Allocate buffers for screen capture
    // We need to store both characters and attributes
    byte* saved_chars = (byte*)fmalloc((u64)total_cells);
    i16* saved_attrs = (i16*)fmalloc((u64)total_cells * (u64)2); // i16 = 2 bytes
    
    // Read the entire screen buffer
    i32 written = 0,
        start_coord = make_coord(0, 0);
    
    // Read characters
    ReadConsoleOutputCharacterA(
        con.out_handle,
        saved_chars,
        total_cells,
        start_coord,
        @written
    );
    
    // Read attributes
    ReadConsoleOutputAttribute(
        con.out_handle,
        saved_attrs,
        total_cells,
        start_coord,
        @written
    );
    
    // Save cursor position and attributes
    i32 saved_cursor = con.cursor_get();
    con.save_attr();

    // ------------------------------------------------------------------
    // 1. Basic setup: hide cursor, clear screen
    // ------------------------------------------------------------------
    con.cursor_visible(false);
    con.clear_screen();

    // ------------------------------------------------------------------
    // 2. Title bar -- white on dark blue
    // BG_DARK_BLUE | FG_WHITE = 0x0010 | 0x000F = 0x001F
    // ------------------------------------------------------------------
    con.clear_line_attr(0, 0x001F);
    con.write_at_colored(
    2, 0, 0x001F,
    "  redconsole.fx  --  Feature Demo\0"
    );

    // ------------------------------------------------------------------
    // 3. Foreground color palette
    // ------------------------------------------------------------------
    con.write_at_colored(2, 2, 0x000E,
                         "[ Foreground Colors ]\0");

    i16 col = 2;
    con.write_at_colored(col, 3, 0x0008, "DARK_GRAY   \0"); col = (col + 13);
    con.write_at_colored(col, 3, 0x0009, "BLUE        \0"); col = (col + 13);
    con.write_at_colored(col, 3, 0x000A, "GREEN       \0"); col = (col + 13);
    con.write_at_colored(col, 3, 0x000B, "CYAN        \0");

    col = 2;
    con.write_at_colored(col, 4, 0x000C, "RED         \0"); col = (col + 13);
    con.write_at_colored(col, 4, 0x000D, "MAGENTA     \0"); col = (col + 13);
    con.write_at_colored(col, 4, 0x000E, "YELLOW      \0"); col = (col + 13);
    con.write_at_colored(col, 4, 0x000F, "WHITE       \0");

    // ------------------------------------------------------------------
    // 4. Background color palette
    // ------------------------------------------------------------------
    con.write_at_colored(2, 6, 0x000E,
                         "[ Background Colors ]\0");

    col = 2;
    con.write_at_colored(col, 7, 0x001F, " DARK_BLUE   \0"); col = (col + 14);
    con.write_at_colored(col, 7, 0x002F, " DARK_GREEN  \0"); col = (col + 14);
    con.write_at_colored(col, 7, 0x004F, " DARK_RED    \0"); col = (col + 14);
    con.write_at_colored(col, 7, 0x005F, " DARK_MAG    \0");

    col = 2;
    con.write_at_colored(col, 8, 0x0030, " DARK_CYAN   \0"); col = (col + 14);
    con.write_at_colored(col, 8, 0x0060, " DARK_YELLOW \0"); col = (col + 14);
    con.write_at_colored(col, 8, 0x0070, " GRAY        \0"); col = (col + 14);
    con.write_at_colored(col, 8, 0x00F0, " WHITE       \0");

    // ------------------------------------------------------------------
    // 5. Console dimensions
    // ------------------------------------------------------------------
    con.write_at_colored(2, 10, 0x000E,
                         "[ Console Info ]\0");

    con.write_at_colored(2, 11, 0x000B, "Width:  \0");
    byte[16] numbuf;
    i16 ww = w;
    numbuf[0] = (byte)('0' + (int)(ww / 10));
    numbuf[1] = (byte)('0' + (int)(ww % 10));
    numbuf[2] = (byte)0;
    con.write_at_colored(10, 11, 0x000F, @numbuf[0]);

    con.write_at_colored(2, 12, 0x000B, "Height: \0");
    i16 hh = h;
    numbuf[0] = (byte)('0' + (int)(hh / 10));
    numbuf[1] = (byte)('0' + (int)(hh % 10));
    numbuf[2] = (byte)0;
    con.write_at_colored(10, 12, 0x000F, @numbuf[0]);

    // ------------------------------------------------------------------
    // 6. clear_region demo
    // ------------------------------------------------------------------
    con.write_at_colored(2, 14, 0x000E,
                         "[ clear_region demo ]\0");

    con.write_at_colored(2, 15, 0x000C, "XXXXXXXXXXXXXXXXXX\0");
    con.write_at_colored(2, 16, 0x000C, "XXXXXXXXXXXXXXXXXX\0");
    con.write_at_colored(2, 17, 0x000C, "XXXXXXXXXXXXXXXXXX\0");

    Sleep(600);

    con.clear_region(6, 15, 10, 3);

    con.write_at_colored(2, 17, 0x0008,
                         "  (cols 6-15 cleared)\0");

    // ------------------------------------------------------------------
    // 7. Progress bar animation
    // ------------------------------------------------------------------
    con.write_at_colored(2, 19, 0x000E,
                         "[ Progress Bar ]\0");

    i32 step = 0;
    while (step <= 20)
    {
        con.progress_bar(20, "Loading\0", step, 20);
        Sleep(80);
        step = step + 1;
    };
    // progress_bar uses CON_FG_GREEN|CON_BG_BLACK internally which resolves
    // to 0 (black on black) due to zero-init globals. Repaint the finished
    // bar with a visible color.
    con.write_at_colored(0, 20, 0x000A,
                         "Loading [####################] 100%           \0");

    // ------------------------------------------------------------------
    // 8. Spinner animation
    // ------------------------------------------------------------------
    con.write_at_colored(2, 22, 0x000E,
                         "[ Spinner ] Working...\0");

    i32 tick = 0;
    while (tick < 24)
    {
        con.spinner(12, 22, tick);
        Sleep(100);
        tick = tick + 1;
    };
    con.write_at_colored(12, 22, 0x000A, "Done!           \0");

    // ------------------------------------------------------------------
    // 9. cursor_save / cursor_restore demo
    // ------------------------------------------------------------------
    con.write_at_colored(2, 24, 0x000E,
                         "[ Cursor Save/Restore ]\0");

    con.cursor_set(2, 25);
    con.set_attr(0x000B);
    con.cursor_save();

    con.write_at_colored(2, 26, 0x0008,
                         "(cursor jumped away and came back)\0");

    con.cursor_set(30, 0);
    Sleep(500);
    con.cursor_restore();

    con.write_at_colored(2, 25, 0x000B,
                         "Saved here -> Restored here!\0");
    con.set_attr(0x0007);

    // ------------------------------------------------------------------
    // 10. Status bar at the bottom
    // BG_DARK_GREEN | FG_BLACK = 0x0020
    // ------------------------------------------------------------------
    i16 last_row = (h - 1);
    con.clear_line_attr(last_row, 0x0020);
    con.write_at_colored(2, last_row, 0x0020,
                         "  redconsole.fx demo complete. Press Enter to exit.  \0");

    // ------------------------------------------------------------------
    // Wait for user input
    // ------------------------------------------------------------------
    con.cursor_set(0, last_row);
    con.cursor_visible(true);
    con.set_attr(0x0007);

    Sleep(100);
    system("pause\0");

    // ====================================================================
    // Restore the original screen contents
    // ====================================================================
    // Hide cursor during restoration
    con.cursor_visible(false);
    
    // Restore characters and attributes
    for (i16 y = 0; y < h; y = y + 1)
    {
        i32 line_coord = make_coord(0, y);
        i32 line_start = y * w;
        
        // Write characters for this line
        WriteConsoleOutputCharacterA(
            con.out_handle,
            @saved_chars[line_start],
            w,
            line_coord,
            @written
        );
        
        // Write attributes for this line
        WriteConsoleOutputAttribute(
            con.out_handle,
            @saved_attrs[line_start],
            w,
            line_coord,
            @written
        );
    };
    
    // Restore cursor position and attributes
    SetConsoleCursorPosition(con.out_handle, saved_cursor);
    con.restore_attr();
    con.cursor_visible(true);
    
    // Free the saved buffers
    ffree((u64)saved_chars);
    ffree((u64)saved_attrs);

    return 0;
};