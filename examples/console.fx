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

#import "standard.fx";
#import "redconsole.fx";

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

    // ------------------------------------------------------------------
    // 1. Basic setup: hide cursor, clear screen
    // ------------------------------------------------------------------
    con.cursor_visible(false);
    con.clear_screen();

    // ------------------------------------------------------------------
    // 2. Title bar -- white on dark blue
    // BG_DARK_BLUE | FG_WHITE = 0x0010 | 0x000F = 0x001F
    // ------------------------------------------------------------------
    i16 w = con.get_width();
    i16 h = con.get_height();

    con.clear_line_attr((i16)0, (i16)0x001F);
    con.write_at_colored((i16)2, (i16)0, (i16)0x001F,
                         "  redconsole.fx  --  Feature Demo\0");

    // ------------------------------------------------------------------
    // 3. Foreground color palette
    // ------------------------------------------------------------------
    con.write_at_colored((i16)2, (i16)2, (i16)0x000E,
                         "[ Foreground Colors ]\0");

    i16 col = (i16)2;
    con.write_at_colored(col, (i16)3, (i16)0x0008, "DARK_GRAY   \0"); col = (i16)(col + (i16)13);
    con.write_at_colored(col, (i16)3, (i16)0x0009, "BLUE        \0"); col = (i16)(col + (i16)13);
    con.write_at_colored(col, (i16)3, (i16)0x000A, "GREEN       \0"); col = (i16)(col + (i16)13);
    con.write_at_colored(col, (i16)3, (i16)0x000B, "CYAN        \0");

    col = (i16)2;
    con.write_at_colored(col, (i16)4, (i16)0x000C, "RED         \0"); col = (i16)(col + (i16)13);
    con.write_at_colored(col, (i16)4, (i16)0x000D, "MAGENTA     \0"); col = (i16)(col + (i16)13);
    con.write_at_colored(col, (i16)4, (i16)0x000E, "YELLOW      \0"); col = (i16)(col + (i16)13);
    con.write_at_colored(col, (i16)4, (i16)0x000F, "WHITE       \0");

    // ------------------------------------------------------------------
    // 4. Background color palette
    // ------------------------------------------------------------------
    con.write_at_colored((i16)2, (i16)6, (i16)0x000E,
                         "[ Background Colors ]\0");

    col = (i16)2;
    con.write_at_colored(col, (i16)7, (i16)0x001F, " DARK_BLUE   \0"); col = (i16)(col + (i16)14);
    con.write_at_colored(col, (i16)7, (i16)0x002F, " DARK_GREEN  \0"); col = (i16)(col + (i16)14);
    con.write_at_colored(col, (i16)7, (i16)0x004F, " DARK_RED    \0"); col = (i16)(col + (i16)14);
    con.write_at_colored(col, (i16)7, (i16)0x005F, " DARK_MAG    \0");

    col = (i16)2;
    con.write_at_colored(col, (i16)8, (i16)0x0030, " DARK_CYAN   \0"); col = (i16)(col + (i16)14);
    con.write_at_colored(col, (i16)8, (i16)0x0060, " DARK_YELLOW \0"); col = (i16)(col + (i16)14);
    con.write_at_colored(col, (i16)8, (i16)0x0070, " GRAY        \0"); col = (i16)(col + (i16)14);
    con.write_at_colored(col, (i16)8, (i16)0x00F0, " WHITE       \0");

    // ------------------------------------------------------------------
    // 5. Console dimensions
    // ------------------------------------------------------------------
    con.write_at_colored((i16)2, (i16)10, (i16)0x000E,
                         "[ Console Info ]\0");

    con.write_at_colored((i16)2, (i16)11, (i16)0x000B, "Width:  \0");
    byte[16] numbuf;
    i16 ww = w;
    numbuf[0] = (byte)('0' + (int)(ww / (i16)10));
    numbuf[1] = (byte)('0' + (int)(ww % (i16)10));
    numbuf[2] = (byte)0;
    con.write_at_colored((i16)10, (i16)11, (i16)0x000F, @numbuf[0]);

    con.write_at_colored((i16)2, (i16)12, (i16)0x000B, "Height: \0");
    i16 hh = h;
    numbuf[0] = (byte)('0' + (int)(hh / (i16)10));
    numbuf[1] = (byte)('0' + (int)(hh % (i16)10));
    numbuf[2] = (byte)0;
    con.write_at_colored((i16)10, (i16)12, (i16)0x000F, @numbuf[0]);

    // ------------------------------------------------------------------
    // 6. clear_region demo
    // ------------------------------------------------------------------
    con.write_at_colored((i16)2, (i16)14, (i16)0x000E,
                         "[ clear_region demo ]\0");

    con.write_at_colored((i16)2, (i16)15, (i16)0x000C, "XXXXXXXXXXXXXXXXXX\0");
    con.write_at_colored((i16)2, (i16)16, (i16)0x000C, "XXXXXXXXXXXXXXXXXX\0");
    con.write_at_colored((i16)2, (i16)17, (i16)0x000C, "XXXXXXXXXXXXXXXXXX\0");

    Sleep(600);

    con.clear_region((i16)6, (i16)15, (i16)10, (i16)3);

    con.write_at_colored((i16)2, (i16)17, (i16)0x0008,
                         "  (cols 6-15 cleared)\0");

    // ------------------------------------------------------------------
    // 7. Progress bar animation
    // ------------------------------------------------------------------
    con.write_at_colored((i16)2, (i16)19, (i16)0x000E,
                         "[ Progress Bar ]\0");

    i32 step = (i32)0;
    while (step <= (i32)20)
    {
        con.progress_bar((i16)20, "Loading\0", step, (i32)20);
        Sleep(80);
        step = step + (i32)1;
    };
    // progress_bar uses CON_FG_GREEN|CON_BG_BLACK internally which resolves
    // to 0 (black on black) due to zero-init globals. Repaint the finished
    // bar with a visible color.
    con.write_at_colored((i16)0, (i16)20, (i16)0x000A,
                         "Loading [####################] 100%           \0");

    // ------------------------------------------------------------------
    // 8. Spinner animation
    // ------------------------------------------------------------------
    con.write_at_colored((i16)2, (i16)22, (i16)0x000E,
                         "[ Spinner ] Working...\0");

    i32 tick = (i32)0;
    while (tick < (i32)24)
    {
        con.spinner((i16)12, (i16)22, tick);
        Sleep(100);
        tick = tick + (i32)1;
    };
    con.write_at_colored((i16)12, (i16)22, (i16)0x000A, "Done!           \0");

    // ------------------------------------------------------------------
    // 9. cursor_save / cursor_restore demo
    // ------------------------------------------------------------------
    con.write_at_colored((i16)2, (i16)24, (i16)0x000E,
                         "[ Cursor Save/Restore ]\0");

    con.cursor_set((i16)2, (i16)25);
    con.set_attr((i16)0x000B);
    con.cursor_save();

    con.write_at_colored((i16)2, (i16)26, (i16)0x0008,
                         "(cursor jumped away and came back)\0");

    con.cursor_set((i16)30, (i16)0);
    Sleep(500);
    con.cursor_restore();

    con.write_at_colored((i16)2, (i16)25, (i16)0x000B,
                         "Saved here -> Restored here!\0");
    con.set_attr((i16)0x0007);

    // ------------------------------------------------------------------
    // 10. Status bar at the bottom
    // BG_DARK_GREEN | FG_BLACK = 0x0020
    // ------------------------------------------------------------------
    i16 last_row = (i16)(h - (i16)1);
    con.clear_line_attr(last_row, (i16)0x0020);
    con.write_at_colored((i16)2, last_row, (i16)0x0020,
                         "  redconsole.fx demo complete. Press Enter to exit.  \0");

    // ------------------------------------------------------------------
    // Done -- restore state and wait
    // ------------------------------------------------------------------
    con.cursor_set((i16)0, last_row);
    con.cursor_visible(true);
    con.set_attr((i16)0x0007);

    Sleep(100);
    system("pause\0");

    return 0;
};
