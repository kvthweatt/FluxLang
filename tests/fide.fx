// fide.fx - Flux IDE

#import <standard.fx>, <windows.fx>;
#import "editor_core.fx";
#import "guide_data.fx";

using standard::io::console,
      standard::math,
      standard::strings,
      standard::system::windows,
      FluxIDE;

// ============================================================================
// SUBLIME TEXT THEME COLORS  (COLORREF = 0x00BBGGRR)
// ============================================================================

#def CLR_BG        0x00222827;
#def CLR_FG        0x00F2F8F8;
#def CLR_WIN_BG    0x00222827;
#def CLR_CARET     0x00F8F8F2;
#def CLR_SEL       0x00574E49;
#def CLR_LINENO_BG 0x00272920;
#def CLR_LINENO_FG 0x00807C75;

UINT CF_TEXT            = 1;
UINT GMEM_MOVEABLE      = 0x0002;
UINT WM_MOUSEWHEEL      = 0x020A;
UINT WM_PAINT           = 0x000F;
DWORD DWMWA_DARK        = 20;
int   FW_NORMAL         = 400;
DWORD ANSI_CHARSET        = 0,
      OUT_DEFAULT_PRECIS  = 0,
      CLIP_DEFAULT_PRECIS = 0,
      DEFAULT_QUALITY     = 0,
      FIXED_PITCH         = 1,
      FF_MODERN           = 0x30;
int   SB_VERT        = 1,
      SB_HORZ        = 0,
      SB_THUMBTRACK  = 5,
      SB_LINEDOWN    = 1,
      SB_LINEUP      = 0,
      SB_PAGEDOWN    = 3,
      SB_PAGEUP      = 2,
      SB_LINERIGHT   = 1,
      SB_LINELEFT    = 0,
      SB_PAGERIGHT   = 3,
      SB_PAGELEFT    = 2;
UINT  SIF_RANGE     = 0x0001,
      SIF_PAGE      = 0x0002,
      SIF_POS       = 0x0004,
      SIF_TRACKPOS  = 0x0010,
      SIF_ALL       = 0x0017;
UINT  ETO_OPAQUE    = 0x0002;
DWORD SRCCOPY       = 0x00CC0020;
int   TRANSPARENT_MODE = 1,
      OPAQUE_MODE      = 2;

// IDE-specific menu IDs
int IDM_LANG_GUIDE = 3002;

// Custom message: lParam = byte* pointing to example code to load
UINT WM_APP_LOAD_EXAMPLE = 0x8001;

// Link color for clickable example entries (COLORREF 0x00BBGGRR)
#def CLR_LINK 0x00E6B87A;
#def CLR_CODE_BG     0x002D3330;   // slightly lighter than CLR_BG for code blocks
#def CLR_CODE_BORDER 0x00807C75;   // same muted tone as line number fg

// Global editor window handle -- used by the guide window to send examples back
HWND g_editor_hwnd;

// ============================================================================
// GUIDE WINDOW STATE
// ============================================================================

// Guide window state: -1 = home page, >= 0 = detail page for that example index
int  g_guide_page;      // set to -1 in do_lang_guide
HWND g_guide_hwnd;
int  g_guide_scroll;    // home page: pixel scroll offset (scrolled down by this many px)

// Runtime nav link Y positions on the detail page (set during WM_PAINT,
// read during WM_LBUTTONDOWN)
int g_detail_home_y;
int g_detail_paste_y;
int g_guide_min_h;      // minimum window height to show full code box, set during WM_PAINT

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
// EDITOR STATE
// ============================================================================

GapBuf    g_gb;
LineIndex g_li;

HFONT     g_font;
HBRUSH    g_brush_bg,
          g_brush_lineno,
          g_brush_sel;

int       g_char_w;
int       g_char_h;
int       g_scroll_line;
int       g_scroll_col;
int       g_cursor;
int       g_sel_anchor;
int       g_caret_on;
int       g_mouse_selecting;

byte[260] g_filename;
bool      g_modified;
int       g_font_size;

// ============================================================================
// TITLE / SAVE / OPEN / NEW
// ============================================================================

def update_title(HWND hwnd) -> void
{
    byte[300] title;
    noopstr base     = "Flux IDE - ",
            untitled = "Untitled",
            star     = " *";
    strcpy(title, base);
    strcat(title, (g_filename[0] != (byte)0) ? g_filename : untitled);
    if (g_modified) { strcat(title, star); };
    SetWindowTextA(hwnd, (LPCSTR)title);
    return;
};

def ask_save(HWND hwnd) -> int
{
    noopstr msg = "Do you want to save changes?",
            cap = "Flux IDE";
    return MessageBoxA(hwnd, (LPCSTR)msg, (LPCSTR)cap, MB_YESNOCANCEL | MB_ICONQUESTION);
};

def do_save(HWND hwnd, bool save_as) -> bool
{
    byte[260]     path;
    OPENFILENAMEA ofn;
    DWORD         written;
    noopstr filter = "Flux Files*.fxAll Files*.*",
            defext = "fx",
            cap    = "Save As";

    if (g_filename[0] == (byte)0 | save_as)
    {
        path[0] = (byte)0;
        if (g_filename[0] != (byte)0) { strcpy(path, g_filename); };
        memset((void*)@ofn, 0, sizeof(OPENFILENAMEA) / 8);
        ofn.lStructSize = (DWORD)(sizeof(OPENFILENAMEA) / 8);
        ofn.hwndOwner   = hwnd;
        ofn.lpstrFilter = (LPCSTR)filter;
        ofn.lpstrFile   = (LPSTR)path;
        ofn.nMaxFile    = 260;
        ofn.lpstrDefExt = (LPCSTR)defext;
        ofn.lpstrTitle  = (LPCSTR)cap;
        ofn.Flags       = OFN_OVERWRITEPROMPT | OFN_HIDEREADONLY;
        if (!GetSaveFileNameA((void*)@ofn)) { return false; };
        strcpy(g_filename, path);
    };

    int   len = gb_len(@g_gb);
    void* buf = (void*)fmalloc((size_t)(len + 1));
    if (buf == STDLIB_GVP) { return false; };
    gb_flatten(@g_gb, (byte*)buf);

    HWND hf = CreateFileA((LPCSTR)g_filename, GENERIC_WRITE, 0,
                           STDLIB_GVP, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, (HWND)0);
    if (hf == (HWND)0xFFFFFFFFFFFFFFFFu) { ffree(long(buf)); return false; };
    WriteFile(hf, buf, (DWORD)len, @written, STDLIB_GVP);
    CloseHandle(hf);
    ffree(long(buf));
    g_modified = false;
    update_title(hwnd);
    return true;
};

def do_open(HWND hwnd) -> void
{
    byte[260]     path;
    OPENFILENAMEA ofn;
    DWORD         bread;
    i64           fsize;
    noopstr filter = "Flux Files*.fxAll Files*.*",
            cap    = "Open";

    path[0] = (byte)0;
    memset((void*)@ofn, 0, sizeof(OPENFILENAMEA) / 8);
    ofn.lStructSize = (DWORD)(sizeof(OPENFILENAMEA) / 8);
    ofn.hwndOwner   = hwnd;
    ofn.lpstrFilter = (LPCSTR)filter;
    ofn.lpstrFile   = (LPSTR)path;
    ofn.nMaxFile    = 260;
    ofn.lpstrTitle  = (LPCSTR)cap;
    ofn.Flags       = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY;
    if (!GetOpenFileNameA((void*)@ofn)) { return; };

    HWND hf = CreateFileA((LPCSTR)path, GENERIC_READ, FILE_SHARE_READ,
                           STDLIB_GVP, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, (HWND)0);
    if (hf == (HWND)0xFFFFFFFFFFFFFFFFu) { return; };

    GetFileSizeEx(hf, @fsize);
    void* buf = (void*)fmalloc((size_t)(fsize + 1));
    if (buf == STDLIB_GVP) { CloseHandle(hf); return; };
    ReadFile(hf, buf, (DWORD)fsize, @bread, STDLIB_GVP);
    CloseHandle(hf);

    gb_free(@g_gb);
    gb_init(@g_gb);
    int fi;
    while (fi < (int)fsize)
    {
        gb_insert(@g_gb, fi, ((byte*)buf)[fi]);
        fi++;
    };
    ffree(long(buf));

    g_cursor      = 0;
    g_scroll_line = 0;
    g_scroll_col  = 0;
    li_rebuild(@g_li, @g_gb);
    strcpy(g_filename, path);
    g_modified = false;
    update_title(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

def do_new(HWND hwnd) -> void
{
    int r;
    if (g_modified)
    {
        r = ask_save(hwnd);
        if (r == IDCANCEL) { return; };
        if (r == IDYES)    { do_save(hwnd, false); };
    };
    gb_free(@g_gb);
    gb_init(@g_gb);
    li_rebuild(@g_li, @g_gb);
    g_cursor      = 0;
    g_scroll_line = 0;
    g_scroll_col  = 0;
    g_filename[0] = (byte)0;
    g_modified    = false;
    update_title(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

// ============================================================================
// SCROLL HELPERS
// ============================================================================

def update_vscroll(HWND hwnd) -> void
{
    SCROLLINFO si;
    RECT rc;
    if (g_char_h == 0) { return; };
    GetClientRect(hwnd, @rc);
    si.cbSize = (UINT)(sizeof(SCROLLINFO) / 8);
    si.fMask  = SIF_RANGE | SIF_PAGE | SIF_POS;
    si.nMin   = 0;
    si.nMax   = g_li.count - 1;
    si.nPage  = (UINT)((rc.bottom - rc.top) / g_char_h);
    si.nPos   = g_scroll_line;
    SetScrollInfo(hwnd, SB_VERT, (void*)@si, true);
    return;
};

def clamp_scroll(HWND hwnd) -> void
{
    if (g_scroll_line > g_li.count - 1) { g_scroll_line = g_li.count - 1; };
    if (g_scroll_line < 0)              { g_scroll_line = 0; };
    if (g_scroll_col  < 0)              { g_scroll_col  = 0; };
    return;
};

def recreate_font(HWND hwnd) -> void
{
    noopstr font_face = "Consolas";
    HDC hdc_tmp;
    TEXTMETRIC tm;

    DeleteObject((HDC)g_font);
    g_font = CreateFontA
    (
        g_font_size, 0, 0, 0,
        FW_NORMAL,   0, 0, 0,
        ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        DEFAULT_QUALITY,
        FIXED_PITCH | FF_MODERN,
        (LPCSTR)font_face
    );

    hdc_tmp = GetDC(hwnd);
    SelectObject(hdc_tmp, g_font);
    GetTextMetricsA(hdc_tmp, (void*)@tm);
    g_char_w = (int)tm.tmAveCharWidth;
    g_char_h = (int)tm.tmHeight;
    ReleaseDC(hwnd, hdc_tmp);

    clamp_scroll(hwnd);
    update_vscroll(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

def scroll_to_cursor(HWND hwnd) -> void
{
    RECT rc;
    int  cur_line, vis_lines, cur_col, vis_cols;

    if (g_char_h == 0 | g_char_w == 0) { return; };
    GetClientRect(hwnd, @rc);
    
    vis_lines = (rc.bottom - rc.top) / g_char_h;
    cur_line  = li_line_of(@g_li, g_cursor);
    if (cur_line < g_scroll_line) g_scroll_line = cur_line;
    if (cur_line >= g_scroll_line + vis_lines) g_scroll_line = cur_line - vis_lines + 1;
    
    cur_col  = li_col_of(@g_li, g_cursor);
    vis_cols = (rc.right - rc.left - LINENO_WIDTH) / g_char_w;
    if (cur_col < g_scroll_col) g_scroll_col = cur_col;
    if (cur_col >= g_scroll_col + vis_cols) g_scroll_col = cur_col - vis_cols + 1;
    
    clamp_scroll(hwnd);
    update_vscroll(hwnd);
    return;
};

// ============================================================================
// SELECTION HELPERS
// ============================================================================

def sel_has() -> bool
{
    return g_cursor != g_sel_anchor;
};

def sel_min() -> int
{
    if (g_cursor < g_sel_anchor) { return g_cursor; };
    return g_sel_anchor;
};

def sel_max() -> int
{
    if (g_cursor > g_sel_anchor) { return g_cursor; };
    return g_sel_anchor;
};

// Delete selected region, leave cursor at sel_min
def sel_delete(HWND hwnd) -> void
{
    int lo, hi, count, i;
    if (!sel_has()) { return; };
    lo    = sel_min();
    hi    = sel_max();
    count = hi - lo;
    i     = 0;
    while (i < count)
    {
        gb_delete(@g_gb, lo);
        i++;
    };
    g_cursor     = lo;
    g_sel_anchor = lo;
    li_rebuild(@g_li, @g_gb);
    g_modified = true;
    update_title(hwnd);
    return;
};

// ============================================================================
// CLIPBOARD
// ============================================================================

def clipboard_copy(HWND hwnd) -> void
{
    int   lo, hi, len;
    HWND  hmem;
    void* ptr;
    int   i;
    if (!sel_has()) { return; };
    lo  = sel_min();
    hi  = sel_max();
    len = hi - lo;
    hmem = GlobalAlloc(GMEM_MOVEABLE, (size_t)(len + 1));
    if (hmem == (HWND)0) { return; };
    ptr = GlobalLock(hmem);
    if (ptr == STDLIB_GVP) { return; };
    i = 0;
    while (i < len)
    {
        ((byte*)ptr)[i] = gb_get(@g_gb, lo + i);
        i++;
    };
    ((byte*)ptr)[len] = (byte)0;
    GlobalUnlock(hmem);
    if (OpenClipboard(hwnd))
    {
        EmptyClipboard();
        SetClipboardData((UINT)CF_TEXT, hmem);
        CloseClipboard();
    };
    return;
};

def clipboard_paste(HWND hwnd) -> void
{
    HWND  hmem;
    void* ptr;
    size_t sz;
    int    i;
    byte   ch;
    if (!OpenClipboard(hwnd)) { return; };
    hmem = GetClipboardData((UINT)CF_TEXT);
    if (hmem == (HWND)0) { CloseClipboard(); return; };
    ptr = GlobalLock(hmem);
    if (ptr == STDLIB_GVP) { CloseClipboard(); return; };
    sz = GlobalSize(hmem);
    // Delete selection first if any
    if (sel_has())
    {
        sel_delete(hwnd);
        update_vscroll(hwnd);
    };
    i = 0;
    while (i < (int)sz)
    {
        ch = ((byte*)ptr)[i];
        if (ch == (byte)0) { break; };
        // Normalize CR/CRLF to LF
        if (ch == (byte)13)
        {
            i++;
            gb_insert(@g_gb, g_cursor, (byte)10);
            g_cursor++;
        }
        else
        {
            gb_insert(@g_gb, g_cursor, ch);
            g_cursor++;
        };
        i++;
    };
    g_sel_anchor = g_cursor;
    GlobalUnlock(hmem);
    CloseClipboard();
    li_rebuild(@g_li, @g_gb);
    g_modified = true;
    update_title(hwnd);
    scroll_to_cursor(hwnd);
    update_vscroll(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

// ============================================================================
// PAINT
// ============================================================================

def editor_paint(HWND hwnd) -> void
{
    PAINTSTRUCT ps;
    HDC hdc, back_dc, back_bmp;
    RECT rc, cell;
    int  w, h, vis_lines, vis_cols;
    int  ln, y, line_start, line_len;
    int  draw_start, draw_len, si;
    byte[32] lnbuf;
    int  lnlen, lnx;
    void* seg_buf;
    int  cur_line, cur_col, caret_x;
    HBRUSH caret_brush;
    int  sel_lo, sel_hi, line_end, sc_lo, sc_hi, sx, sw;
    RECT sel_cell;
    HBRUSH sel_fill;

    hdc = BeginPaint(hwnd, (void*)@ps);
    if (g_char_h == 0)
    {
        EndPaint(hwnd, (void*)@ps);
        return;
    };
    GetClientRect(hwnd, @rc);
    w = rc.right  - rc.left;
    h = rc.bottom - rc.top;

    back_dc  = CreateCompatibleDC(hdc);
    back_bmp = CreateCompatibleBitmap(hdc, w, h);
    SelectObject(back_dc, (HFONT)back_bmp);
    SelectObject(back_dc, g_font);
    SetBkMode(back_dc, OPAQUE_MODE);

    // Fill entire back buffer
    FillRect(back_dc, @rc, g_brush_bg);

    // Line number gutter
    cell.left   = 0;
    cell.top    = 0;
    cell.right  = LINENO_WIDTH;
    cell.bottom = h;
    FillRect(back_dc, @cell, g_brush_lineno);

    vis_lines = (h / g_char_h) + 2;
    vis_cols  = (w - LINENO_WIDTH) / g_char_w + 2;

    cur_line = li_line_of(@g_li, g_cursor);
    cur_col  = li_col_of(@g_li, g_cursor);

    ln = g_scroll_line;
    y  = 0;
    while (ln < g_li.count & y < h + g_char_h)
    {
        // Line number
        snprintf(lnbuf, (size_t)31, "%d", ln + 1);
        lnlen = strlen(lnbuf);
        lnx   = LINENO_WIDTH - (lnlen * g_char_w) - 6;
        cell.left   = 0;
        cell.top    = y;
        cell.right  = LINENO_WIDTH;
        cell.bottom = y + g_char_h;
        SetBkColor(back_dc, (DWORD)CLR_LINENO_BG);
        SetTextColor(back_dc, (DWORD)CLR_LINENO_FG);
        ExtTextOutA(back_dc, lnx, y, ETO_OPAQUE, @cell, (LPCSTR)lnbuf, (UINT)lnlen, (void*)0);

        // Text
        line_start = g_li.starts[ln];
        line_len   = li_line_len(@g_li, @g_gb, ln);

        if (g_scroll_col >= line_len)
        {
            draw_start = line_start + line_len;
            draw_len   = 0;
        }
        else
        {
            draw_start = line_start + g_scroll_col;
            draw_len   = line_len - g_scroll_col;
            if (draw_len > vis_cols) { draw_len = vis_cols; };
        };

        // Paint base line background opaque
        cell.left   = LINENO_WIDTH;
        cell.top    = y;
        cell.right  = w;
        cell.bottom = y + g_char_h;
        SetBkColor(back_dc, (DWORD)CLR_BG);
        SetTextColor(back_dc, (DWORD)CLR_FG);
        ExtTextOutA(back_dc, LINENO_WIDTH, y, ETO_OPAQUE, @cell, (LPCSTR)"", 0, (void*)0);

        // Draw selection highlight for this line
        if (sel_has())
        {
            sel_lo   = sel_min();
            sel_hi   = sel_max();
            line_end = line_start + line_len;
            if (sel_lo < line_end + 1 & sel_hi > line_start)
            {
                sc_lo = sel_lo - line_start;
                if (sc_lo < 0) { sc_lo = 0; };
                sc_hi = sel_hi - line_start;
                if (sc_hi > line_len) { sc_hi = line_len; };
                if (sel_hi > line_end) { sc_hi = line_len + 1; };
                sx = LINENO_WIDTH + (sc_lo - g_scroll_col) * g_char_w;
                sw = (sc_hi - sc_lo) * g_char_w;
                if (sx < LINENO_WIDTH) { sw -= (LINENO_WIDTH - sx); sx = LINENO_WIDTH; };
                if (sw > 0)
                {
                    sel_cell.left   = sx;
                    sel_cell.top    = y;
                    sel_cell.right  = sx + sw;
                    sel_cell.bottom = y + g_char_h;
                    sel_fill = CreateSolidBrush((DWORD)CLR_SEL);
                    FillRect(back_dc, @sel_cell, sel_fill);
                    DeleteObject((HDC)sel_fill);
                };
            };
        };

        // Draw text transparently over the (possibly highlighted) background
        if (draw_len > 0)
        {
            seg_buf = (void*)fmalloc((size_t)(draw_len + 1));
            if (seg_buf != STDLIB_GVP)
            {
                si = 0;
                while (si < draw_len)
                {
                    ((byte*)seg_buf)[si] = gb_get(@g_gb, draw_start + si);
                    si++;
                };
                ((byte*)seg_buf)[draw_len] = (byte)0;
                SetBkMode(back_dc, TRANSPARENT_MODE);
                ExtTextOutA(back_dc, LINENO_WIDTH, y, 0, @cell,
                            (LPCSTR)seg_buf, (UINT)draw_len, (void*)0);
                SetBkMode(back_dc, OPAQUE_MODE);
                ffree(long(seg_buf));
            };
        };

        // Caret
        if (g_caret_on & cur_line == ln)
        {
            caret_x = LINENO_WIDTH + (cur_col - g_scroll_col) * g_char_w;
            if (caret_x >= LINENO_WIDTH)
            {
                cell.left   = caret_x;
                cell.top    = y;
                cell.right  = caret_x + 2;
                cell.bottom = y + g_char_h;
                caret_brush = CreateSolidBrush((DWORD)CLR_CARET);
                FillRect(back_dc, @cell, caret_brush);
                DeleteObject((HDC)caret_brush);
            };
        };

        y  += g_char_h;
        ln++;
    };

    BitBlt(hdc, 0, 0, w, h, back_dc, 0, 0, SRCCOPY);
    DeleteObject((HDC)back_bmp);
    DeleteDC(back_dc);
    EndPaint(hwnd, (void*)@ps);
    return;
};

// ============================================================================
// CURSOR MOVEMENT
// ============================================================================

// shift=true: extend selection; shift=false: collapse anchor to cursor first
def cursor_move_left(HWND hwnd, bool shift) -> void
{
    if (!shift & sel_has()) { g_cursor = sel_min(); g_sel_anchor = g_cursor; scroll_to_cursor(hwnd); return; };
    if (!shift) { g_sel_anchor = g_cursor; };
    if (g_cursor > 0) { g_cursor--; };
    if (!shift) { g_sel_anchor = g_cursor; };
    scroll_to_cursor(hwnd);
    return;
};

def cursor_move_right(HWND hwnd, bool shift) -> void
{
    if (!shift & sel_has()) { g_cursor = sel_max(); g_sel_anchor = g_cursor; scroll_to_cursor(hwnd); return; };
    if (!shift) { g_sel_anchor = g_cursor; };
    if (g_cursor < gb_len(@g_gb)) { g_cursor++; };
    if (!shift) { g_sel_anchor = g_cursor; };
    scroll_to_cursor(hwnd);
    return;
};

def cursor_move_up(HWND hwnd, bool shift) -> void
{
    int ln, col, new_line_len;
    if (!shift) { g_sel_anchor = g_cursor; };
    ln  = li_line_of(@g_li, g_cursor);
    col = li_col_of(@g_li, g_cursor);
    if (ln == 0) { g_cursor = 0; if (!shift) { g_sel_anchor = g_cursor; }; scroll_to_cursor(hwnd); return; };
    ln--;
    new_line_len = li_line_len(@g_li, @g_gb, ln);
    if (col > new_line_len) { col = new_line_len; };
    g_cursor = g_li.starts[ln] + col;
    if (!shift) { g_sel_anchor = g_cursor; };
    scroll_to_cursor(hwnd);
    return;
};

def cursor_move_down(HWND hwnd, bool shift) -> void
{
    int ln, col, new_line_len;
    if (!shift) { g_sel_anchor = g_cursor; };
    ln  = li_line_of(@g_li, g_cursor);
    col = li_col_of(@g_li, g_cursor);
    if (ln >= g_li.count - 1) { g_cursor = gb_len(@g_gb); if (!shift) { g_sel_anchor = g_cursor; }; scroll_to_cursor(hwnd); return; };
    ln++;
    new_line_len = li_line_len(@g_li, @g_gb, ln);
    if (col > new_line_len) { col = new_line_len; };
    g_cursor = g_li.starts[ln] + col;
    if (!shift) { g_sel_anchor = g_cursor; };
    scroll_to_cursor(hwnd);
    return;
};

def cursor_home(HWND hwnd, bool shift) -> void
{
    int ln;
    if (!shift) { g_sel_anchor = g_cursor; };
    ln = li_line_of(@g_li, g_cursor);
    g_cursor = g_li.starts[ln];
    if (!shift) { g_sel_anchor = g_cursor; };
    scroll_to_cursor(hwnd);
    return;
};

def cursor_end(HWND hwnd, bool shift) -> void
{
    int ln;
    if (!shift) { g_sel_anchor = g_cursor; };
    ln = li_line_of(@g_li, g_cursor);
    g_cursor = g_li.starts[ln] + li_line_len(@g_li, @g_gb, ln);
    if (!shift) { g_sel_anchor = g_cursor; };
    scroll_to_cursor(hwnd);
    return;
};

def cursor_page_up(HWND hwnd) -> void
{
    RECT rc;
    int  vis_lines, ln, col, new_line_len;
    if (g_char_h == 0) { return; };
    GetClientRect(hwnd, @rc);
    vis_lines     = (rc.bottom - rc.top) / g_char_h;
    g_scroll_line -= vis_lines;
    ln  = li_line_of(@g_li, g_cursor) - vis_lines;
    col = li_col_of(@g_li, g_cursor);
    if (ln < 0) { ln = 0; };
    new_line_len = li_line_len(@g_li, @g_gb, ln);
    if (col > new_line_len) { col = new_line_len; };
    g_cursor = g_li.starts[ln] + col;
    clamp_scroll(hwnd);
    update_vscroll(hwnd);
    return;
};

def cursor_page_down(HWND hwnd) -> void
{
    RECT rc;
    int  vis_lines, ln, col, new_line_len;
    if (g_char_h == 0) { return; };
    GetClientRect(hwnd, @rc);
    vis_lines     = (rc.bottom - rc.top) / g_char_h;
    g_scroll_line += vis_lines;
    ln  = li_line_of(@g_li, g_cursor) + vis_lines;
    col = li_col_of(@g_li, g_cursor);
    if (ln >= g_li.count) { ln = g_li.count - 1; };
    new_line_len = li_line_len(@g_li, @g_gb, ln);
    if (col > new_line_len) { col = new_line_len; };
    g_cursor = g_li.starts[ln] + col;
    clamp_scroll(hwnd);
    update_vscroll(hwnd);
    return;
};

// ============================================================================
// EDIT OPERATIONS
// ============================================================================

def editor_insert(HWND hwnd, byte ch) -> void
{
    int  ln, line_start, line_len, ei, ns_count, spaces, di;
    byte ec, ns_prev, ns_cur;

    if (sel_has()) { sel_delete(hwnd); };
    gb_insert(@g_gb, g_cursor, ch);
    g_cursor++;
    g_sel_anchor = g_cursor;
    li_rebuild(@g_li, @g_gb);

    // After inserting ';': if the line is solely "};" dedent it by 4.
    if (ch == (byte)59)
    {
        ln         = li_line_of(@g_li, g_cursor - 1);
        line_start = g_li.starts[ln];
        line_len   = li_line_len(@g_li, @g_gb, ln);
        ei = 0;
        while (ei < line_len)
        {
            ec = gb_get(@g_gb, line_start + ei);
            if (ec != (byte)32 & ec != (byte)9 & ec != (byte)13)
            {
                ns_prev = ns_cur;
                ns_cur  = ec;
                ns_count++;
            }
            else
            {
                if (ns_count == 0) { spaces++; };
            };
            ei++;
        };
        if (ns_count == 2 & ns_prev == (byte)125 & ns_cur == (byte)59)
        {
            while (di < 4 & spaces > 0)
            {
                gb_delete(@g_gb, line_start);
                g_cursor--;
                spaces--;
                di++;
            };
            g_sel_anchor = g_cursor;
            li_rebuild(@g_li, @g_gb);
        };
    };

    g_modified = true;
    update_title(hwnd);
    scroll_to_cursor(hwnd);
    update_vscroll(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

// Auto-indenting newline: carries forward indentation, and adds 4 spaces after '{'.
def editor_newline(HWND hwnd) -> void
{
    int  ln, line_start, line_len, spaces, i, last_nonspace, ins;
    byte ch;

    if (sel_has()) { sel_delete(hwnd); };

    ln         = li_line_of(@g_li, g_cursor);
    line_start = g_li.starts[ln];
    line_len   = li_line_len(@g_li, @g_gb, ln);

    // Count leading spaces
    while (i < line_len)
    {
        if (gb_get(@g_gb, line_start + i) != (byte)32) { break; };
        spaces++;
        i++;
    };

    // Find last non-space char before cursor
    last_nonspace = -1;
    i = 0;
    while (i < line_len & (line_start + i) < g_cursor)
    {
        ch = gb_get(@g_gb, line_start + i);
        if (ch != (byte)32) { last_nonspace = i; };
        i++;
    };

    gb_insert(@g_gb, g_cursor, (byte)10);
    g_cursor++;

    // Carry forward indentation
    ins = 0;
    while (ins < spaces)
    {
        gb_insert(@g_gb, g_cursor, (byte)32);
        g_cursor++;
        ins++;
    };

    // Extra 4 spaces after '{'
    if (last_nonspace >= 0)
    {
        if (gb_get(@g_gb, line_start + last_nonspace) == (byte)123)
        {
            ins = 0;
            while (ins < 4)
            {
                gb_insert(@g_gb, g_cursor, (byte)32);
                g_cursor++;
                ins++;
            };
        };
    };

    g_sel_anchor = g_cursor;
    li_rebuild(@g_li, @g_gb);
    g_modified = true;
    update_title(hwnd);
    scroll_to_cursor(hwnd);
    update_vscroll(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

def editor_backspace(HWND hwnd) -> void
{
    if (sel_has())
    {
        sel_delete(hwnd);
        update_vscroll(hwnd);
        InvalidateRect(hwnd, (RECT*)0, false);
        return;
    };
    if (g_cursor == 0) { return; };
    g_cursor--;
    gb_delete(@g_gb, g_cursor);
    g_sel_anchor = g_cursor;
    li_rebuild(@g_li, @g_gb);
    g_modified = true;
    update_title(hwnd);
    scroll_to_cursor(hwnd);
    update_vscroll(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

def editor_delete(HWND hwnd) -> void
{
    if (sel_has())
    {
        sel_delete(hwnd);
        update_vscroll(hwnd);
        InvalidateRect(hwnd, (RECT*)0, false);
        return;
    };
    if (g_cursor >= gb_len(@g_gb)) { return; };
    gb_delete(@g_gb, g_cursor);
    g_sel_anchor = g_cursor;
    li_rebuild(@g_li, @g_gb);
    g_modified = true;
    update_title(hwnd);
    update_vscroll(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

def editor_delete_word(HWND hwnd) -> void
{
    int  i, word_start;
    byte ch;
    if (sel_has()) { sel_delete(hwnd); update_vscroll(hwnd); InvalidateRect(hwnd, (RECT*)0, false); return; };
    if (g_cursor == 0) { return; };
    i = g_cursor - 1;
    while (i >= 0)
    {
        ch = gb_get(@g_gb, i);
        if (ch != (byte)32 & ch != (byte)9 & ch != (byte)13 & ch != (byte)10) { break; };
        i--;
    };
    while (i >= 0)
    {
        ch = gb_get(@g_gb, i);
        if (ch == (byte)32 | ch == (byte)9 | ch == (byte)13 | ch == (byte)10) { break; };
        i--;
    };
    word_start = i + 1;
    while (g_cursor > word_start)
    {
        g_cursor--;
        gb_delete(@g_gb, g_cursor);
    };
    g_sel_anchor = g_cursor;
    li_rebuild(@g_li, @g_gb);
    g_modified = true;
    update_title(hwnd);
    scroll_to_cursor(hwnd);
    update_vscroll(hwnd);
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

// ============================================================================
// CLICK TO POSITION
// ============================================================================

// extend=false: new click, reset anchor; extend=true: drag, keep anchor
def is_word_char(byte c) -> bool
{
    if (c >= 'a' & c <= 'z') { return true; };
    if (c >= 'A' & c <= 'Z') { return true; };
    if (c >= '0' & c <= '9') { return true; };
    if (c == '_')             { return true; };
    return false;
};

def select_word_at(HWND hwnd, int pos) -> void
{
    int len, lo, hi;
    len = gb_len(@g_gb);
    if (len == 0) { return; };
    if (pos >= len) { pos = len - 1; };

    // If not on a word character, select just that character
    if (!is_word_char(gb_get(@g_gb, pos)))
    {
        g_sel_anchor = pos;
        g_cursor     = pos + 1;
        InvalidateRect(hwnd, (RECT*)0, false);
        return;
    };

    // Walk left to find word start
    lo = pos;
    while (lo > 0 & is_word_char(gb_get(@g_gb, lo - 1))) { lo--; };

    // Walk right to find word end
    hi = pos;
    while (hi < len & is_word_char(gb_get(@g_gb, hi))) { hi++; };

    g_sel_anchor = lo;
    g_cursor     = hi;
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

def editor_click(HWND hwnd, int mx, int my, bool extend) -> void
{
    int clicked_line, clicked_col, line_len;
    if (g_char_h == 0 | g_char_w == 0) { return; };
    clicked_line = g_scroll_line + (my / g_char_h);
    if (clicked_line >= g_li.count) { clicked_line = g_li.count - 1; };
    if (clicked_line < 0)           { clicked_line = 0; };
    clicked_col = g_scroll_col + ((mx - LINENO_WIDTH) / g_char_w);
    if (clicked_col < 0) { clicked_col = 0; };
    line_len = li_line_len(@g_li, @g_gb, clicked_line);
    if (clicked_col > line_len) { clicked_col = line_len; };
    g_cursor = g_li.starts[clicked_line] + clicked_col;
    if (!extend) { g_sel_anchor = g_cursor; };
    InvalidateRect(hwnd, (RECT*)0, false);
    return;
};

// ============================================================================
// LANGUAGE GUIDE WINDOW
// ============================================================================

// Layout constants shared by WM_PAINT and WM_LBUTTONDOWN -- must stay in sync.
#def GUIDE_LINK_HEIGHT    22;   // row height for all links
#def GUIDE_LINK_X         20;   // left margin for all text

def LangGuideWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) -> LRESULT
{
    switch (msg)
    {
        case (WM_PAINT)
        {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, (void*)@ps);

            RECT rc,
                 sub_rc,
                 ltr_rc,
                 link_rc,
                 head_rc,
                 desc_rc,
                 box_rc,
                 home_rc,
                 code_rc,
                 paste_rc,
                 meas_rc;
            int box_left, box_right, text_min_h, box_top, box_avail, box_h;
            GetClientRect(hwnd, @rc);

            // Background
            HBRUSH bg = CreateSolidBrush((DWORD)CLR_BG),
                   code_border = CreateSolidBrush((DWORD)CLR_CODE_BORDER),
                   code_bg = CreateSolidBrush((DWORD)CLR_CODE_BG);
            FillRect(hdc, @rc, bg);
            DeleteObject((HDC)bg);

            SetBkMode(hdc, TRANSPARENT_MODE);

            HFONT hfont_head = CreateFontA(
                28, 0, 0, 0, 700, 0, 0, 0,
                ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, FIXED_PITCH | FF_MODERN,
                (LPCSTR)"Consolas");

            HFONT hfont_body = CreateFontA(
                16, 0, 0, 0, FW_NORMAL, 0, 0, 0,
                ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, FIXED_PITCH | FF_MODERN,
                (LPCSTR)"Consolas");

            HFONT hfont_mono = CreateFontA(
                15, 0, 0, 0, FW_NORMAL, 0, 0, 0,
                ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, FIXED_PITCH | FF_MODERN,
                (LPCSTR)"Consolas");

            noopstr heading = "Language Guide";
            noopstr sub = "Click a keyword to view its description and example.";
            noopstr home_lbl = "Main Help";
            noopstr paste_lbl = "Paste into IDE";


            if (g_guide_page < 0)
            {
                // ---- HOME PAGE ----

                HFONT hfont_letter = CreateFontA(
                    18, 0, 0, 0, 700, 0, 0, 0,
                    ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                    DEFAULT_QUALITY, FIXED_PITCH | FF_MODERN,
                    (LPCSTR)"Consolas");

                // Fixed heading (not scrolled)
                SelectObject(hdc, (HDC)hfont_head);
                SetTextColor(hdc, (DWORD)CLR_FG);
                head_rc.left = GUIDE_LINK_X; head_rc.top = 20;
                head_rc.right = rc.right - 20; head_rc.bottom = 56;
                DrawTextA(hdc, (LPCSTR)heading, 14, @head_rc,
                          DT_LEFT | DT_TOP | DT_SINGLELINE);

                SelectObject(hdc, (HDC)hfont_body);
                SetTextColor(hdc, (DWORD)CLR_FG);

                sub_rc.left = GUIDE_LINK_X; sub_rc.top = 58;
                sub_rc.right = rc.right - 20; sub_rc.bottom = 80;
                DrawTextA(hdc, (LPCSTR)sub, 51, @sub_rc,
                          DT_LEFT | DT_TOP | DT_SINGLELINE);

                // Scrollable list: virtual_y is the unscrolled pixel position.
                // screen_y = virtual_y - g_guide_scroll.
                // Letter headers take GUIDE_LINK_HEIGHT + 4 px each.
                int virtual_y = 90;
                byte prev_letter, first;
                byte* name,
                      ex_name,
                      ex_desc,
                      ex_code;
                byte[2] lbuf;

                int i, idx,
                    nlen,
                    ex_name_len,
                    ex_desc_len,
                    ex_code_len,
                    screen_y, nav_paste_y, nav_home_y;

                while (i < sizeof(g_examples) / sizeof(FluxExample))
                {
                    name = g_examples[i].name;
                    first = name[0];

                    if (first != prev_letter)
                    {
                        screen_y = virtual_y - g_guide_scroll;
                        if (screen_y >= 80 & screen_y < rc.bottom)
                        {
                            SelectObject(hdc, (HDC)hfont_letter);
                            SetTextColor(hdc, (DWORD)CLR_FG);
                            lbuf[0] = first;
                            lbuf[1] = (byte)0;
                            ltr_rc.left = GUIDE_LINK_X; ltr_rc.top = screen_y;
                            ltr_rc.right = rc.right - 20; ltr_rc.bottom = screen_y + GUIDE_LINK_HEIGHT + 4;
                            DrawTextA(hdc, (LPCSTR)lbuf, 1, @ltr_rc,
                                      DT_LEFT | DT_TOP | DT_SINGLELINE);
                            SelectObject(hdc, (HDC)hfont_body);
                        };
                        prev_letter = first;
                        virtual_y = virtual_y + GUIDE_LINK_HEIGHT + 4;
                    };

                    screen_y = virtual_y - g_guide_scroll;
                    if (screen_y >= 80 & screen_y < rc.bottom)
                    {
                        nlen = strlen(name);
                        SetTextColor(hdc, (DWORD)CLR_LINK);
                        link_rc.left = GUIDE_LINK_X + 12; link_rc.top = screen_y;
                        link_rc.right = rc.right - 20; link_rc.bottom = screen_y + GUIDE_LINK_HEIGHT;
                        DrawTextA(hdc, (LPCSTR)name, nlen, @link_rc,
                                  DT_LEFT | DT_TOP | DT_SINGLELINE);
                    };

                    virtual_y = virtual_y + GUIDE_LINK_HEIGHT;
                    i++;
                };

                DeleteObject((HDC)hfont_letter);
            }
            else
            {
                // ---- DETAIL PAGE ----
                idx = g_guide_page;

                // Nav link Y positions are computed after the box height is known (see below)

                // Heading: example name
                ex_name = g_examples[idx].name;
                ex_name_len = strlen(ex_name);
                SelectObject(hdc, (HDC)hfont_head);
                SetTextColor(hdc, (DWORD)CLR_FG);
                head_rc.left = GUIDE_LINK_X; head_rc.top = 20;
                head_rc.right = rc.right - 20; head_rc.bottom = 68;
                DrawTextA(hdc, (LPCSTR)ex_name, ex_name_len, @head_rc,
                          DT_LEFT | DT_TOP | DT_SINGLELINE);

                // Description text (word-wrapped)
                ex_desc = g_examples[idx].desc;
                ex_desc_len = strlen(ex_desc);
                SelectObject(hdc, (HDC)hfont_body);
                SetTextColor(hdc, (DWORD)CLR_FG);
                desc_rc.left = GUIDE_LINK_X; desc_rc.top = 72;
                desc_rc.right = rc.right - 20; desc_rc.bottom = 72 + 48;
                DrawTextA(hdc, (LPCSTR)ex_desc, ex_desc_len, @desc_rc,
                          DT_LEFT | DT_TOP | DT_WORDBREAK);

                // Code block (monospace, word-wrap on newlines via DT_WORDBREAK)
                ex_code = g_examples[idx].code;
                ex_code_len = strlen(ex_code);

                // Clamp width: max 600px, anchored left
                box_left  = GUIDE_LINK_X;
                box_right = rc.right - 20;
                if (box_right - box_left > 600) { box_right = box_left + 600; };

                box_top = 132;

                // Select mono font before measuring so DT_CALCRECT uses the right metrics
                SelectObject(hdc, (HDC)hfont_mono);

                // Measure the text height at the clamped width (padding 8px each side)
                meas_rc.left = box_left + 8; meas_rc.top = 0;
                meas_rc.right = box_right - 8; meas_rc.bottom = 0;
                DrawTextA(hdc, (LPCSTR)ex_code, ex_code_len, @meas_rc,
                          DT_LEFT | DT_TOP | DT_WORDBREAK | DT_CALCRECT);

                // text height + top/bottom padding (6px each) = required box height
                text_min_h = (meas_rc.bottom - meas_rc.top) + 12;

                // Store minimum window height: fixed top + box + gap + nav + bottom margin + title bar
                g_guide_min_h = box_top + text_min_h + 8 + (2 * GUIDE_LINK_HEIGHT) + 20 + 30;

                // Box height: fit to text, capped at 600px
                box_h = text_min_h;
                if (box_h > 600) { box_h = 600; };

                box_rc.left = box_left; box_rc.top = box_top;
                box_rc.right = box_right; box_rc.bottom = box_top + box_h;

                // Nav links sit below the box with a fixed gap
                nav_home_y  = box_rc.bottom + 8;
                nav_paste_y = nav_home_y + GUIDE_LINK_HEIGHT + 4;

                // Fill background
                FillRect(hdc, @box_rc, code_bg);
                DeleteObject((HDC)code_bg);

                // Draw border
                FrameRect(hdc, @box_rc, code_border);
                DeleteObject((HDC)code_border);

                // Text inset by padding inside the box
                code_rc.left = box_rc.left + 8; code_rc.top = box_rc.top + 6;
                code_rc.right = box_rc.right - 8; code_rc.bottom = box_rc.bottom - 6;

                SetBkMode(hdc, TRANSPARENT_MODE);
                SetTextColor(hdc, (DWORD)CLR_FG);

                // Clip drawing strictly to code_rc so text never bleeds outside the box
                IntersectClipRect(hdc, code_rc.left, code_rc.top,
                                  code_rc.right, code_rc.bottom);
                DrawTextA(hdc, (LPCSTR)ex_code, ex_code_len, @code_rc,
                          DT_LEFT | DT_TOP | DT_WORDBREAK);
                SelectClipRgn(hdc, (HRGN)0);

                DeleteObject((HDC)hfont_mono);

                // "Main Help" back link
                SelectObject(hdc, (HDC)hfont_body);
                SetTextColor(hdc, (DWORD)CLR_LINK);
                home_rc.left = GUIDE_LINK_X; home_rc.top = nav_home_y;
                home_rc.right = rc.right - 20; home_rc.bottom = nav_home_y + GUIDE_LINK_HEIGHT;
                DrawTextA(hdc, (LPCSTR)home_lbl, 9, @home_rc,
                          DT_LEFT | DT_TOP | DT_SINGLELINE);

                // "Paste into IDE" link
                SetTextColor(hdc, (DWORD)CLR_LINK);
                paste_rc.left = GUIDE_LINK_X; paste_rc.top = nav_paste_y;
                paste_rc.right = rc.right - 20; paste_rc.bottom = nav_paste_y + GUIDE_LINK_HEIGHT;
                DrawTextA(hdc, (LPCSTR)paste_lbl, 14, @paste_rc,
                          DT_LEFT | DT_TOP | DT_SINGLELINE);

                // Store nav Y positions for WM_LBUTTONDOWN hit-testing
                g_detail_home_y  = nav_home_y;
                g_detail_paste_y = nav_paste_y;
            };

            DeleteObject((HDC)hfont_head);
            DeleteObject((HDC)hfont_body);
            EndPaint(hwnd, (void*)@ps);
            return 0;
        }
        case (WM_LBUTTONDOWN)
        {
            int my = (int)(lParam >> 16) & 0xFFFF;
            if (my & 0x8000) { my = my | (int)0xFFFF0000; };

            if (g_guide_page < 0)
            {
                // Home page: reconstruct same virtual_y layout as WM_PAINT to hit-test
                int virtual_y = 90;
                byte prev_letter, first;
                byte* name;
                int i, screen_y;
                while (i < sizeof(g_examples) / sizeof(FluxExample))
                {
                    name = g_examples[i].name;
                    first = name[0];

                    if (first != prev_letter)
                    {
                        prev_letter = first;
                        virtual_y = virtual_y + GUIDE_LINK_HEIGHT + 4;
                    };

                    screen_y = virtual_y - g_guide_scroll;
                    if (my >= screen_y & my < screen_y + GUIDE_LINK_HEIGHT)
                    {
                        g_guide_page = i;
                        g_guide_scroll = 0;
                        InvalidateRect(hwnd, (RECT*)0, false);
                        return 0;
                    };

                    virtual_y = virtual_y + GUIDE_LINK_HEIGHT;
                    i++;
                };
            }
            else
            {
                // Detail page: check "Main Help" back link first
                if (my >= g_detail_home_y & my < g_detail_home_y + GUIDE_LINK_HEIGHT)
                {
                    g_guide_page = -1;
                    InvalidateRect(hwnd, (RECT*)0, false);
                    return 0;
                };

                // Detail page: check "Paste into IDE" link
                if (my >= g_detail_paste_y & my < g_detail_paste_y + GUIDE_LINK_HEIGHT)
                {
                    SendMessageA(g_editor_hwnd, (UINT)WM_APP_LOAD_EXAMPLE,
                                 0, (LPARAM)g_examples[g_guide_page].code);
                };
            };
            return 0;
        }
        case (WM_MOUSEWHEEL)
        {
            // Only scroll on the home page
            if (g_guide_page < 0)
            {
                int delta = (int)((wParam >> 16) & 0xFFFF);
                if (delta & 0x8000) { delta = delta | (int)0xFFFF0000; };
                if (delta > 0) { g_guide_scroll -= 3 * GUIDE_LINK_HEIGHT; }
                else           { g_guide_scroll += 3 * GUIDE_LINK_HEIGHT; };
                if (g_guide_scroll < 0) { g_guide_scroll = 0; };
                InvalidateRect(hwnd, (RECT*)0, false);
            };
            return 0;
        }
        case (WM_GETMINMAXINFO)
        {
            MINMAXINFO* mmi = (MINMAXINFO*)lParam;
            mmi.ptMinTrackSize.x = 300;
            int min_h = g_guide_min_h;
            if (min_h < 200) { min_h = 200; };
            mmi.ptMinTrackSize.y = min_h;
            return 0;
        }
        case (WM_CLOSE)
        {
            DestroyWindow(hwnd);
            return 0;
        }
        case (WM_DESTROY)
        {
            return 0;
        }
        default
        {
            return DefWindowProcA(hwnd, msg, wParam, lParam);
        };
    };

    return DefWindowProcA(hwnd, msg, wParam, lParam);
};

def do_lang_guide(HWND parent) -> void
{
    g_editor_hwnd  = parent;
    g_guide_page   = -1;
    g_guide_scroll = 0;
    HINSTANCE hinstance = GetModuleHandleA((LPCSTR)0);
    noopstr cls = "FluxLangGuide",
            ttl = "Language Guide";

    WNDCLASSEXA wc;
    wc.cbSize        = (UINT)(sizeof(WNDCLASSEXA) / 8);
    wc.style         = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc   = (WNDPROC)@LangGuideWndProc;
    wc.cbClsExtra    = 0;
    wc.cbWndExtra    = 0;
    wc.hInstance     = hinstance;
    wc.hIcon         = LoadIconA((HINSTANCE)0, (LPCSTR)32512);
    wc.hCursor       = LoadCursorA((HINSTANCE)0, (LPCSTR)32512);
    wc.hbrBackground = (HBRUSH)0;
    wc.lpszMenuName  = (LPCSTR)0;
    wc.lpszClassName = (LPCSTR)cls;
    wc.hIconSm       = (HICON)0;
    RegisterClassExA(@wc);

    HWND hwnd_guide = CreateWindowExA(
        0, (LPCSTR)cls, (LPCSTR)ttl,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, 600, 400,
        parent, (HMENU)0, hinstance, STDLIB_GVP);

    g_guide_hwnd = hwnd_guide;

    DWORD dark = 1;
    DwmSetWindowAttribute(hwnd_guide, DWMWA_DARK, (void*)@dark, (DWORD)(sizeof(DWORD) / 8));

    ShowWindow(hwnd_guide, SW_SHOW);
    UpdateWindow(hwnd_guide);
    return;
};

// ============================================================================
// WINDOW PROCEDURE
// ============================================================================

def EditorWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) -> LRESULT
{
    RECT rc;
    int  r, lo, vk, action;
    bool ctrl, shift;
    int  mx, my, delta;
    int  ch;
    SCROLLINFO si;

    switch (msg)
    {
        case (WM_CREATE)
        {
            HMENU hmenu = CreateMenu(),
                  hfile = CreatePopupMenu(),
                  hedit = CreatePopupMenu(),
                  hhelp = CreatePopupMenu();

            noopstr sNew    = "&New\tCtrl+N",   sOpen   = "&Open...\tCtrl+O",
                    sSave   = "&Save\tCtrl+S",  sSaveAs = "Save &As...",
                    sExit   = "E&xit",           sUndo   = "&Undo\tCtrl+Z",
                    sCut    = "Cu&t\tCtrl+X",   sCopy   = "&Copy\tCtrl+C",
                    sPaste  = "&Paste\tCtrl+V", sSel    = "Select &All\tCtrl+A",
                    sAbout      = "&About",
                    sLangGuide  = "&Language Guide",
                    mFile   = "&File",           mEdit   = "&Edit",
                    mHelp   = "&Help";

            AppendMenuA(hfile, MF_STRING,    (UINT_PTR)IDM_NEW,       (LPCSTR)sNew);
            AppendMenuA(hfile, MF_STRING,    (UINT_PTR)IDM_OPEN,      (LPCSTR)sOpen);
            AppendMenuA(hfile, MF_STRING,    (UINT_PTR)IDM_SAVE,      (LPCSTR)sSave);
            AppendMenuA(hfile, MF_STRING,    (UINT_PTR)IDM_SAVEAS,    (LPCSTR)sSaveAs);
            AppendMenuA(hfile, MF_SEPARATOR, 0,                        (LPCSTR)STDLIB_GVP);
            AppendMenuA(hfile, MF_STRING,    (UINT_PTR)IDM_EXIT,      (LPCSTR)sExit);
            AppendMenuA(hedit, MF_STRING,    (UINT_PTR)IDM_UNDO,      (LPCSTR)sUndo);
            AppendMenuA(hedit, MF_SEPARATOR, 0,                        (LPCSTR)STDLIB_GVP);
            AppendMenuA(hedit, MF_STRING,    (UINT_PTR)IDM_CUT,       (LPCSTR)sCut);
            AppendMenuA(hedit, MF_STRING,    (UINT_PTR)IDM_COPY,      (LPCSTR)sCopy);
            AppendMenuA(hedit, MF_STRING,    (UINT_PTR)IDM_PASTE,     (LPCSTR)sPaste);
            AppendMenuA(hedit, MF_SEPARATOR, 0,                        (LPCSTR)STDLIB_GVP);
            AppendMenuA(hedit, MF_STRING,    (UINT_PTR)IDM_SELECTALL, (LPCSTR)sSel);
            AppendMenuA(hhelp, MF_STRING,    (UINT_PTR)IDM_LANG_GUIDE, (LPCSTR)sLangGuide);
            AppendMenuA(hhelp, MF_STRING,    (UINT_PTR)IDM_ABOUT,      (LPCSTR)sAbout);
            AppendMenuA(hmenu, MF_POPUP, (UINT_PTR)hfile, (LPCSTR)mFile);
            AppendMenuA(hmenu, MF_POPUP, (UINT_PTR)hedit, (LPCSTR)mEdit);
            AppendMenuA(hmenu, MF_POPUP, (UINT_PTR)hhelp, (LPCSTR)mHelp);
            SetMenu(hwnd, hmenu);

            DWORD dark = 1;
            DwmSetWindowAttribute(hwnd, DWMWA_DARK, (void*)@dark, (DWORD)(sizeof(DWORD) / 8));

            g_font_size = 19;
            noopstr font_face = "Consolas";
            g_font = CreateFontA(
                g_font_size, 0, 0, 0, FW_NORMAL, 0, 0, 0,
                ANSI_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, FIXED_PITCH | FF_MODERN, (LPCSTR)font_face);

            HDC hdc_tmp = GetDC(hwnd);
            SelectObject(hdc_tmp, g_font);
            TEXTMETRIC tm;
            GetTextMetricsA(hdc_tmp, (void*)@tm);
            g_char_w = (int)tm.tmAveCharWidth;
            g_char_h = (int)tm.tmHeight;
            ReleaseDC(hwnd, hdc_tmp);

            g_brush_bg     = CreateSolidBrush((DWORD)CLR_BG);
            g_brush_lineno = CreateSolidBrush((DWORD)CLR_LINENO_BG);
            g_brush_sel    = CreateSolidBrush((DWORD)CLR_SEL);

            gb_init(@g_gb);
            li_rebuild(@g_li, @g_gb);

            g_cursor          = 0;
            g_sel_anchor      = 0;
            g_scroll_line     = 0;
            g_scroll_col      = 0;
            g_caret_on        = 1;
            g_mouse_selecting = 0;

            update_vscroll(hwnd);
            return 0;
        }
        case (WM_ERASEBKGND)
        {
            return 1;
        }
        case (WM_PAINT)
        {
            editor_paint(hwnd);
            return 0;
        }
        case (WM_SIZE)
        {
            clamp_scroll(hwnd);
            update_vscroll(hwnd);
            InvalidateRect(hwnd, (RECT*)0, false);
            return 0;
        }
        case (WM_SETFOCUS)
        {
            g_caret_on = 1;
            InvalidateRect(hwnd, (RECT*)0, false);
            return 0;
        }
        case (WM_KILLFOCUS)
        {
            g_caret_on = 0;
            InvalidateRect(hwnd, (RECT*)0, false);
            return 0;
        }
        case (WM_LBUTTONDOWN)
        {
            mx = (int)(lParam & 0xFFFF);
            my = (int)((lParam >> 16) & 0xFFFF);
            SetFocus(hwnd);
            editor_click(hwnd, mx, my, false);
            g_mouse_selecting = 1;
            SetCapture(hwnd);
            return 0;
        }
        case (WM_LBUTTONDBLCLK)
        {
            mx = (int)(lParam & 0xFFFF);
            my = (int)((lParam >> 16) & 0xFFFF);
            // Position cursor at click first, then expand to word bounds
            editor_click(hwnd, mx, my, false);
            select_word_at(hwnd, g_cursor);
            g_mouse_selecting = 0;
            return 0;
        }
        case (WM_LBUTTONUP)
        {
            g_mouse_selecting = 0;
            ReleaseCapture();
            return 0;
        }
        case (WM_MOUSEMOVE)
        {
            if (g_mouse_selecting)
            {
                mx = (int)(lParam & 0xFFFF);
                my = (int)((lParam >> 16) & 0xFFFF);
                editor_click(hwnd, mx, my, true);
            };
            return 0;
        }
        case (WM_MOUSEWHEEL)
        {
            delta = (int)((short)((wParam >> 16) & 0xFFFF));
            ctrl  = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
            if (ctrl)
            {
                if (delta > 0) { g_font_size += 1; }
                else           { g_font_size -= 1; };
                if (g_font_size < 6)  { g_font_size = 6; };
                if (g_font_size > 72) { g_font_size = 72; };
                recreate_font(hwnd);
            }
            else
            {
                if (delta > 0) { g_scroll_line -= 3; }
                else           { g_scroll_line += 3; };
                clamp_scroll(hwnd);
                update_vscroll(hwnd);
                InvalidateRect(hwnd, (RECT*)0, false);
            };
            return 0;
        }
        case (WM_VSCROLL)
        {
            action = (int)(wParam & 0xFFFF);
            switch (action)
            {
                case (SB_LINEUP)    { g_scroll_line--; }
                case (SB_LINEDOWN)  { g_scroll_line++; }
                case (SB_PAGEUP)    { g_scroll_line -= 10; }
                case (SB_PAGEDOWN)  { g_scroll_line += 10; }
                case (SB_THUMBTRACK)
                {
                    si.cbSize = (UINT)(sizeof(SCROLLINFO) / 8);
                    si.fMask  = SIF_TRACKPOS;
                    GetScrollInfo(hwnd, SB_VERT, (void*)@si);
                    g_scroll_line = si.nTrackPos;
                }
                default {};
            };
            clamp_scroll(hwnd);
            update_vscroll(hwnd);
            InvalidateRect(hwnd, (RECT*)0, false);
            return 0;
        }
        case (WM_HSCROLL)
        {
            action = (int)(wParam & 0xFFFF);
            switch (action)
            {
                case (SB_LINELEFT)   { g_scroll_col--; }
                case (SB_LINERIGHT)  { g_scroll_col++; }
                case (SB_PAGELEFT)   { g_scroll_col -= 10; }
                case (SB_PAGERIGHT)  { g_scroll_col += 10; }
                case (SB_THUMBTRACK)
                {
                    si.cbSize = (UINT)(sizeof(SCROLLINFO) / 8);
                    si.fMask  = SIF_TRACKPOS;
                    GetScrollInfo(hwnd, SB_HORZ, (void*)@si);
                    g_scroll_col = si.nTrackPos;
                }
                default {};
            };
            clamp_scroll(hwnd);
            InvalidateRect(hwnd, (RECT*)0, false);
            return 0;
        }
        case (WM_KEYDOWN)
        {
            vk    = (int)wParam;
            ctrl  = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
            shift = (GetAsyncKeyState(VK_SHIFT)   & 0x8000) != 0;

            switch (vk)
            {
                case (VK_TAB)
                {
                    if (sel_has()) { sel_delete(hwnd); };
                    editor_insert(hwnd, (byte)32);
                    editor_insert(hwnd, (byte)32);
                    editor_insert(hwnd, (byte)32);
                    editor_insert(hwnd, (byte)32);
                }
                case (VK_LEFT)  { cursor_move_left(hwnd, shift);  InvalidateRect(hwnd, (RECT*)0, false); }
                case (VK_RIGHT) { cursor_move_right(hwnd, shift); InvalidateRect(hwnd, (RECT*)0, false); }
                case (VK_UP)    { cursor_move_up(hwnd, shift);    InvalidateRect(hwnd, (RECT*)0, false); }
                case (VK_DOWN)  { cursor_move_down(hwnd, shift);  InvalidateRect(hwnd, (RECT*)0, false); }
                case (VK_HOME)  { cursor_home(hwnd, shift);       InvalidateRect(hwnd, (RECT*)0, false); }
                case (VK_END)   { cursor_end(hwnd, shift);        InvalidateRect(hwnd, (RECT*)0, false); }
                case (VK_PRIOR) { cursor_page_up(hwnd);           InvalidateRect(hwnd, (RECT*)0, false); }
                case (VK_NEXT)  { cursor_page_down(hwnd);         InvalidateRect(hwnd, (RECT*)0, false); }
                case (VK_BACK)
                {
                    if (ctrl) { editor_delete_word(hwnd); }
                    else      { editor_backspace(hwnd); };
                }
                case (VK_DELETE) { editor_delete(hwnd); }
                case (VK_RETURN) { editor_newline(hwnd); }
                default
                {
                    if (ctrl)
                    {
                        switch (vk)
                        {
                            case (0x41)
                            {
                                // Ctrl+A: select all
                                g_sel_anchor = 0;
                                g_cursor     = gb_len(@g_gb);
                                InvalidateRect(hwnd, (RECT*)0, false);
                            }
                            case (0x43) { clipboard_copy(hwnd); InvalidateRect(hwnd, (RECT*)0, false); }
                            case (0x58)
                            {
                                // Ctrl+X: copy then delete selection
                                clipboard_copy(hwnd);
                                if (sel_has()) { sel_delete(hwnd); update_vscroll(hwnd); InvalidateRect(hwnd, (RECT*)0, false); };
                            }
                            case (0x56) { clipboard_paste(hwnd); }
                            case (0x53) { do_save(hwnd, false); }
                            case (0x4F) { do_open(hwnd); }
                            case (0x4E) { do_new(hwnd); }
                            default {};
                        };
                    };
                };
            };
            return 0;
        }
        case (WM_CHAR)
        {
            ch = (int)wParam;
            if (ch >= 32 & ch != 127)
            {
                editor_insert(hwnd, (byte)ch);
            };
            return 0;
        }
        case (WM_APP_LOAD_EXAMPLE)
        {
            // lParam is a byte* to null-terminated example source code.
            // Clear the buffer and load the snippet -- same as do_new then insert.
            byte* src = (byte*)lParam;
            if (src == (byte*)0) { return 0; };
            gb_free(@g_gb);
            gb_init(@g_gb);
            int ei = 0;
            while (src[ei] != (byte)0)
            {
                gb_insert(@g_gb, ei, src[ei]);
                ei++;
            };
            g_cursor      = 0;
            g_sel_anchor  = 0;
            g_scroll_line = 0;
            g_scroll_col  = 0;
            g_filename[0] = (byte)0;
            g_modified    = true;
            li_rebuild(@g_li, @g_gb);
            update_title(hwnd);
            update_vscroll(hwnd);
            InvalidateRect(hwnd, (RECT*)0, false);
            return 0;
        }
        case (WM_COMMAND)
        {
            lo = (int)(wParam & 0xFFFF);
            switch (lo)
            {
                case (IDM_NEW)    { do_new(hwnd); }
                case (IDM_SAVE)   { do_save(hwnd, false); }
                case (IDM_SAVEAS) { do_save(hwnd, true); }
                case (IDM_CUT)
                {
                    clipboard_copy(hwnd);
                    if (sel_has()) { sel_delete(hwnd); update_vscroll(hwnd); InvalidateRect(hwnd, (RECT*)0, false); };
                }
                case (IDM_COPY)      { clipboard_copy(hwnd); InvalidateRect(hwnd, (RECT*)0, false); }
                case (IDM_PASTE)     { clipboard_paste(hwnd); }
                case (IDM_SELECTALL)
                {
                    g_sel_anchor = 0;
                    g_cursor     = gb_len(@g_gb);
                    InvalidateRect(hwnd, (RECT*)0, false);
                }
                case (IDM_OPEN)
                {
                    if (g_modified)
                    {
                        r = ask_save(hwnd);
                        if (r == IDCANCEL) { return 0; };
                        if (r == IDYES)    { do_save(hwnd, false); };
                    };
                    do_open(hwnd);
                }
                case (IDM_LANG_GUIDE)
                {
                    do_lang_guide(hwnd);
                }
                case (IDM_ABOUT)
                {
                    noopstr amsg = "Flux IDE\nWritten in Flux.\nAuthor: Karac V. Thweatt",
                            acap = "About";
                    MessageBoxA(hwnd, (LPCSTR)amsg, (LPCSTR)acap, 0);
                }
                case (IDM_EXIT)
                {
                    if (g_modified)
                    {
                        r = ask_save(hwnd);
                        if (r == IDCANCEL) { return 0; };
                        if (r == IDYES)    { do_save(hwnd, false); };
                    };
                    DestroyWindow(hwnd);
                    PostQuitMessage(0);
                }
                default {};
            };
            return 0;
        }
        case (WM_CLOSE)
        {
            if (g_modified)
            {
                r = ask_save(hwnd);
                if (r == IDCANCEL) { return 0; };
                if (r == IDYES)    { do_save(hwnd, false); };
            };
            DestroyWindow(hwnd);
            PostQuitMessage(0);
            return 0;
        }
        case (WM_DESTROY)
        {
            gb_free(@g_gb);
            li_free(@g_li);
            DeleteObject((HDC)g_font);
            DeleteObject((HDC)g_brush_bg);
            DeleteObject((HDC)g_brush_lineno);
            DeleteObject((HDC)g_brush_sel);
            PostQuitMessage(0);
            return 0;
        }
        default
        {
            return DefWindowProcA(hwnd, msg, wParam, lParam);
        };
    };

    return DefWindowProcA(hwnd, msg, wParam, lParam);
};


// ============================================================================
// ENTRY POINT
// ============================================================================

def main() -> int
{
    FreeConsole();
    HINSTANCE hinstance = GetModuleHandleA((LPCSTR)0);
    noopstr cls = "FluxIDE",
            ttl = "Flux IDE - Untitled";

    WNDCLASSEXA wc;
    wc.cbSize        = (UINT)(sizeof(WNDCLASSEXA) / 8);
    wc.style         = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    wc.lpfnWndProc   = (WNDPROC)@EditorWndProc;
    wc.cbClsExtra    = 0;
    wc.cbWndExtra    = 0;
    wc.hInstance     = hinstance;
    wc.hIcon         = LoadIconA((HINSTANCE)0, (LPCSTR)32512);
    wc.hCursor       = LoadCursorA((HINSTANCE)0, (LPCSTR)32512);
    wc.hbrBackground = (HBRUSH)0;
    wc.lpszMenuName  = (LPCSTR)0;
    wc.lpszClassName = (LPCSTR)cls;
    wc.hIconSm       = (HICON)0;
    RegisterClassExA(@wc);

    HWND hwnd = CreateWindowExA(
        0, (LPCSTR)cls, (LPCSTR)ttl,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE | WS_VSCROLL | WS_HSCROLL,
        CW_USEDEFAULT, CW_USEDEFAULT, 1024, 768,
        (HWND)0, (HMENU)0, hinstance, STDLIB_GVP);

    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageA(@msg, (HWND)0, 0, 0))
    {
        if (msg.message == WM_CHAR & msg.wParam == 0x7F)
        {
            // Swallow DEL char that Ctrl+Backspace produces
        }
        else
        {
            TranslateMessage(@msg);
            DispatchMessageA(@msg);
        };
    };

    return int(msg.wParam);
};
