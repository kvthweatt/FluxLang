// editor_core.fx - Gap buffer, line index, font metrics for fide

// ============================================================================
// GAP BUFFER
// ============================================================================


#def GAP_INITIAL   4096;
#def GAP_GROW      4096;

namespace FluxIDE
{
    struct GapBuf
    {
        byte* buf;
        int   buf_size;
        int   gap_start;
        int   gap_end;
    };

    def gb_len(GapBuf* g) -> int
    {
        return g.buf_size - (g.gap_end - g.gap_start);
    };

    def gb_phys(GapBuf* g, int idx) -> int
    {
        if (idx < g.gap_start) { return idx; };
        return idx + (g.gap_end - g.gap_start);
    };

    def gb_get(GapBuf* g, int idx) -> byte
    {
        return g.buf[gb_phys(g, idx)];
    };

    def gb_move_gap(GapBuf* g, int pos) -> void
    {
        int gap_len, i, dst;
        gap_len = g.gap_end - g.gap_start;
        if (pos == g.gap_start) { return; };
        if (pos < g.gap_start)
        {
            i = g.gap_start - 1;
            while (i >= pos)
            {
                dst = g.gap_end - 1 - (g.gap_start - 1 - i);
                g.buf[dst] = g.buf[i];
                i--;
            };
            g.gap_end   = g.gap_end - (g.gap_start - pos);
            g.gap_start = pos;
        }
        else
        {
            i = g.gap_end;
            while (i < pos + gap_len)
            {
                g.buf[g.gap_start + (i - g.gap_end)] = g.buf[i];
                i++;
            };
            g.gap_start = pos;
            g.gap_end   = pos + gap_len;
        };
        return;
    };

    def gb_ensure_gap(GapBuf* g, int need) -> bool
    {
        int   gap_len, new_size, old_gap_end;
        void* new_buf;
        gap_len = g.gap_end - g.gap_start;
        if (gap_len >= need) { return true; };
        new_size    = g.buf_size + GAP_GROW;
        new_buf     = (void*)frealloc(long(g.buf), (size_t)new_size);
        if (new_buf == STDLIB_GVP) { return false; };
        g.buf        = (byte*)new_buf;
        old_gap_end  = g.gap_end;
        memmove((void*)(g.buf + old_gap_end + GAP_GROW),
                (void*)(g.buf + old_gap_end),
                (size_t)(g.buf_size - old_gap_end));
        g.gap_end    = old_gap_end + GAP_GROW;
        g.buf_size   = new_size;
        return true;
    };

    def gb_insert(GapBuf* g, int pos, byte ch) -> bool
    {
        if (!gb_ensure_gap(g, 1)) { return false; };
        gb_move_gap(g, pos);
        g.buf[g.gap_start] = ch;
        g.gap_start++;
        return true;
    };

    def gb_delete(GapBuf* g, int pos) -> void
    {
        int len;
        len = gb_len(g);
        if (pos < 0 | pos >= len) { return; };
        gb_move_gap(g, pos);
        g.gap_end++;
        return;
    };

    def gb_init(GapBuf* g) -> bool
    {
        g.buf = (byte*)fmalloc((size_t)GAP_INITIAL);
        if (g.buf == STDLIB_GVP) { return false; };
        g.buf_size  = GAP_INITIAL;
        g.gap_start = 0;
        g.gap_end   = GAP_INITIAL;
        return true;
    };

    def gb_free(GapBuf* g) -> void
    {
        if (g.buf != STDLIB_GVP) { ffree(long(g.buf)); };
        g.buf      = (byte*)STDLIB_GVP;
        g.buf_size = 0;
        g.gap_start = 0;
        g.gap_end   = 0;
        return;
    };

    def gb_flatten(GapBuf* g, byte* out) -> void
    {
        int len, i;
        len = gb_len(g);
        i   = 0;
        while (i < len)
        {
            out[i] = gb_get(g, i);
            i++;
        };
        out[len] = (byte)0;
        return;
    };

    // ============================================================================
    // LINE INDEX
    // ============================================================================

    #def LINE_INITIAL 1024;

    struct LineIndex
    {
        int* starts;
        int  count;
        int  cap;
    };

    def li_init(LineIndex* li) -> bool
    {
        li.starts = (int*)fmalloc((size_t)(LINE_INITIAL * (sizeof(int) / 8)));
        if (li.starts == STDLIB_GVP) { return false; };
        li.cap   = LINE_INITIAL;
        li.count = 0;
        return true;
    };

    def li_free(LineIndex* li) -> void
    {
        if (li.starts != STDLIB_GVP) { ffree(long(li.starts)); };
        li.starts = (int*)STDLIB_GVP;
        li.count  = 0;
        li.cap    = 0;
        return;
    };

    def li_rebuild(LineIndex* li, GapBuf* g) -> bool
    {
        int   len, i, new_cap;
        void* new_buf;
        byte  ch;

        len      = gb_len(g);
        li.count = 0;

        if (li.cap < 1)
        {
            new_buf = (void*)frealloc(long(li.starts), (size_t)(LINE_INITIAL * (sizeof(int) / 8)));
            if (new_buf == STDLIB_GVP) { return false; };
            li.starts = (int*)new_buf;
            li.cap    = LINE_INITIAL;
        };

        li.starts[0] = 0;
        li.count     = 1;

        i = 0;
        while (i < len)
        {
            ch = gb_get(g, i);
            if (ch == (byte)10)
            {
                if (li.count >= li.cap)
                {
                    new_cap = li.cap * 2;
                    new_buf = (void*)frealloc(long(li.starts), (size_t)(new_cap * (sizeof(int) / 8)));
                    if (new_buf == STDLIB_GVP) { return false; };
                    li.starts = (int*)new_buf;
                    li.cap    = new_cap;
                };
                li.starts[li.count] = i + 1;
                li.count++;
            };
            i++;
        };
        return true;
    };

    // Binary search: which line does offset fall on?
    def li_line_of(LineIndex* li, int offset) -> int
    {
        int lo, hi, mid;
        lo = 0;
        hi = li.count - 1;
        while (lo < hi)
        {
            mid = (lo + hi + 1) / 2;
            if (li.starts[mid] <= offset)
            {
                lo = mid;
            }
            else
            {
                hi = mid - 1;
            };
        };
        return lo;
    };

    def li_col_of(LineIndex* li, int offset) -> int
    {
        int ln;
        ln = li_line_of(li, offset);
        return offset - li.starts[ln];
    };

    // Length of line ln (not including the newline)
    def li_line_len(LineIndex* li, GapBuf* g, int ln) -> int
    {
        int line_start, line_end, total_len;
        total_len  = gb_len(g);
        line_start = li.starts[ln];
        if (ln + 1 < li.count)
        {
            line_end = li.starts[ln + 1] - 1;
        }
        else
        {
            line_end = total_len;
        };
        return line_end - line_start;
    };

    // ============================================================================
    // SCROLLINFO / TEXTMETRIC
    // ============================================================================

    struct SCROLLINFO
    {
        UINT cbSize, fMask;
        int  nMin, nMax, nPage, nPos, nTrackPos;
    };

    struct TEXTMETRIC
    {
        LONG tmHeight, tmAscent, tmDescent, tmInternalLeading, tmExternalLeading,
             tmAveCharWidth, tmMaxCharWidth, tmWeight, tmOverhang,
             tmDigitizedAspectX, tmDigitizedAspectY;
        byte tmFirstChar, tmLastChar, tmDefaultChar, tmBreakChar,
             tmItalic, tmUnderlined, tmStruckOut, tmPitchAndFamily, tmCharSet;
    };

    // ============================================================================
    // TAB STATE
    // ============================================================================

    #def MAX_TABS 16;

    struct EditorTab
    {
        GapBuf    gb;
        LineIndex li;
        int       cursor;
        int       sel_anchor;
        int       scroll_line;
        int       scroll_col;
        byte[260] filename;
        bool      modified;
    };

    def tab_init(EditorTab* t) -> bool
    {
        if (!gb_init(@t.gb))   { return false; };
        li_rebuild(@t.li, @t.gb);
        t.cursor      = 0;
        t.sel_anchor  = 0;
        t.scroll_line = 0;
        t.scroll_col  = 0;
        t.filename[0] = (byte)0;
        t.modified    = false;
        return true;
    };

    def tab_free(EditorTab* t) -> void
    {
        gb_free(@t.gb);
        li_free(@t.li);
        return;
    };

    // ============================================================================
    // PANE STATE
    // ============================================================================

    #def MAX_PANES   4;
    #def SPLIT_BAR_W 4;
    #def TAB_HEIGHT  26;
    #def TAB_MIN_W   80;
    #def TAB_MAX_W   180;
    #def LINENO_WIDTH 52;

    struct EditorPane
    {
        EditorTab[MAX_TABS] tabs;
        int                 tab_count;
        int                 active_tab;
        int                 caret_on;
        int                 mouse_selecting;
        // Layout (set by layout manager each WM_SIZE / WM_PAINT pass)
        int                 x;          // left edge (client coords)
        int                 y;          // top edge (always 0 for now)
        int                 w;          // pixel width
        int                 h;          // pixel height
    };

    // ============================================================================
    // GLOBAL LAYOUT / FONT STATE
    // ============================================================================

    EditorPane[MAX_PANES] g_panes;
    global int  g_pane_count,
                g_focused_pane;

    // Split divider drag state
    global bool g_drag_split;
    global int  g_drag_pane,      // index of left pane being resized
                g_drag_start_x,   // mouse x when drag began
                g_drag_orig_w;    // original width of left pane when drag began

    global HFONT  g_font;
    global HBRUSH g_brush_bg,
                  g_brush_lineno,
                  g_brush_sel;

    global int g_char_w,
               g_char_h,
               g_font_size;

    // ============================================================================
    // PANE / TAB ACCESSOR HELPERS
    // ============================================================================

    def active_tab(EditorPane* p) -> EditorTab*
    {
        return @p.tabs[p.active_tab];
    };

    def focused_pane() -> EditorPane*
    {
        return @g_panes[g_focused_pane];
    };

    // ============================================================================
    // TAB MANAGEMENT
    // ============================================================================

    def pane_new_tab(EditorPane* p) -> int
    {
        if (p.tab_count >= MAX_TABS) { return -1; };
        int idx = p.tab_count;
        tab_init(@p.tabs[idx]);
        p.tab_count++;
        p.active_tab = idx;
        return idx;
    };

    def pane_close_tab(EditorPane* p, int idx) -> void
    {
        if (p.tab_count <= 1) { return; };  // keep at least one tab
        tab_free(@p.tabs[idx]);
        // Shift remaining tabs down
        int i = idx;
        while (i < p.tab_count - 1)
        {
            p.tabs[i] = p.tabs[i + 1];
            i++;
        };
        p.tab_count--;
        if (p.active_tab >= p.tab_count) { p.active_tab = p.tab_count - 1; };
        return;
    };

    def pane_init(EditorPane* p) -> void
    {
        p.tab_count      = 0;
        p.active_tab     = 0;
        p.caret_on       = 1;
        p.mouse_selecting = 0;
        pane_new_tab(p);
        return;
    };

    def pane_free(EditorPane* p) -> void
    {
        int i = 0;
        while (i < p.tab_count)
        {
            tab_free(@p.tabs[i]);
            i++;
        };
        p.tab_count = 0;
        return;
    };

    // ============================================================================
    // SELECTION HELPERS
    // ============================================================================

    def tab_sel_has(EditorTab* t) -> bool
    {
        return t.cursor != t.sel_anchor;
    };

    def tab_sel_min(EditorTab* t) -> int
    {
        if (t.cursor < t.sel_anchor) { return t.cursor; };
        return t.sel_anchor;
    };

    def tab_sel_max(EditorTab* t) -> int
    {
        if (t.cursor > t.sel_anchor) { return t.cursor; };
        return t.sel_anchor;
    };

    // ============================================================================
    // SCROLL HELPERS (pure math, no Win32)
    // ============================================================================

    def pane_tab_rect(EditorPane* p, RECT* out) -> void
    {
        out.left   = p.x;
        out.top    = TAB_HEIGHT;
        out.right  = p.x + p.w;
        out.bottom = p.h;
        return;
    };

    def clamp_scroll_tab(EditorTab* t) -> void
    {
        if (t.scroll_line > t.li.count - 1) { t.scroll_line = t.li.count - 1; };
        if (t.scroll_line < 0)              { t.scroll_line = 0; };
        if (t.scroll_col  < 0)              { t.scroll_col  = 0; };
        return;
    };

    // ============================================================================
    // LAYOUT: distribute pane widths given total client width
    // ============================================================================

    def layout_panes(HWND hwnd) -> void
    {
        RECT rc;
        GetClientRect(hwnd, @rc);
        int total_w = rc.right  - rc.left;
        int total_h = rc.bottom - rc.top;

        if (g_pane_count <= 0) { return; };

        int dividers  = g_pane_count - 1;
        int available = total_w - dividers * SPLIT_BAR_W;

        // Normalise: ensure stored widths sum to available
        int sum = 0;
        int i = 0;
        while (i < g_pane_count)
        {
            sum += g_panes[i].w;
            i++;
        };
        // If widths are 0 or badly out of sync, reset evenly
        if (sum <= 0)
        {
            i = 0;
            while (i < g_pane_count)
            {
                g_panes[i].w = available / g_pane_count;
                i++;
            };
            sum = available;
        };

        // Scale stored widths to available
        int x_cursor = 0;
        i = 0;
        while (i < g_pane_count)
        {
            int pw = (g_panes[i].w * available) / sum;
            if (i == g_pane_count - 1) { pw = total_w - x_cursor; };  // absorb rounding
            g_panes[i].x = x_cursor;
            g_panes[i].y = 0;
            g_panes[i].w = pw;
            g_panes[i].h = total_h;
            x_cursor += pw + SPLIT_BAR_W;
            i++;
        };
        return;
    };

    // Add a new pane (split the focused pane in half)
    def add_pane(HWND hwnd) -> void
    {
        if (g_pane_count >= MAX_PANES) { return; };

        // Insert new pane after the focused pane
        int ins = g_focused_pane + 1;

        // Shift panes right
        int i = g_pane_count;
        while (i > ins)
        {
            g_panes[i] = g_panes[i - 1];
            i--;
        };
        g_pane_count++;

        // Steal half the focused pane's width
        int half = g_panes[g_focused_pane].w / 2;
        g_panes[g_focused_pane].w -= half;

        pane_init(@g_panes[ins]);
        g_panes[ins].w = half;

        g_focused_pane = ins;
        layout_panes(hwnd);
        return;
    };

    def remove_pane(HWND hwnd, int idx) -> void
    {
        if (g_pane_count <= 1) { return; };

        pane_free(@g_panes[idx]);

        // Give the width back to the left neighbour if possible, else right
        int give_to = idx - 1;
        if (give_to < 0) { give_to = 1; };
        g_panes[give_to].w += g_panes[idx].w + SPLIT_BAR_W;

        // Shift panes left
        int i = idx;
        while (i < g_pane_count - 1)
        {
            g_panes[i] = g_panes[i + 1];
            i++;
        };
        g_pane_count--;

        if (g_focused_pane >= g_pane_count) { g_focused_pane = g_pane_count - 1; };
        layout_panes(hwnd);
        return;
    };

    // ============================================================================
    // HIT TEST: which pane / tab was clicked?
    // mx, my are client coords.
    // Returns pane index, -1 if on split bar.
    // Sets *tab_out = tab index clicked, or -1 if body clicked.
    // ============================================================================

    def hit_test_pane(int mx, int my, int* tab_out) -> int
    {
        int i = 0;
        while (i < g_pane_count)
        {
            EditorPane* p = @g_panes[i];
            if (mx >= p.x & mx < p.x + p.w)
            {
                // Check tab bar (top TAB_HEIGHT pixels)
                if (my < TAB_HEIGHT)
                {
                    // Which tab?
                    int tab_w = p.w / p.tab_count;
                    if (tab_w > TAB_MAX_W) { tab_w = TAB_MAX_W; };
                    if (tab_w < TAB_MIN_W) { tab_w = TAB_MIN_W; };
                    int tx = p.x;
                    int ti = 0;
                    while (ti < p.tab_count)
                    {
                        if (mx >= tx & mx < tx + tab_w)
                        {
                            *tab_out = ti;
                            return i;
                        };
                        tx += tab_w;
                        ti++;
                    };
                    *tab_out = -1;
                    return i;
                };
                *tab_out = -1;
                return i;
            };
            // Check split bar to the right of pane i
            if (i < g_pane_count - 1)
            {
                int bar_x = p.x + p.w;
                if (mx >= bar_x & mx < bar_x + SPLIT_BAR_W)
                {
                    *tab_out = -1;
                    return -1;  // on split bar
                };
            };
            i++;
        };
        *tab_out = -1;
        return 0;
    };

    // Which split bar index is at mx? Returns pane-left index or -1.
    def hit_test_split_bar(int mx) -> int
    {
        int i = 0;
        while (i < g_pane_count - 1)
        {
            int bar_x = g_panes[i].x + g_panes[i].w;
            if (mx >= bar_x & mx < bar_x + SPLIT_BAR_W) { return i; };
            i++;
        };
        return -1;
    };

    // ============================================================================
    // WORD CLASSIFICATION
    // ============================================================================

    def is_word_char(byte c) -> bool
    {
        if (c >= 'a' & c <= 'z') { return true; };
        if (c >= 'A' & c <= 'Z') { return true; };
        if (c >= '0' & c <= '9') { return true; };
        if (c == '_')            { return true; };
        return false;
    };
};