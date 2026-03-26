// notepad.fx - Notepad clone in Flux

#import "standard.fx", "windows.fx";

using standard::io::console,
      standard::strings,
      standard::system::windows;

HWND      g_hwnd_edit;
byte[260] g_filename;
bool      g_modified;

// ============================================================================
// HELPERS
// ============================================================================

def update_title(HWND hwnd) -> void
{
    byte[300] title;
    noopstr base = "Notepad - \0",
            untitled = "Untitled\0",
            star = " *\0";

    strcpy(title, base);
    strcat(title, (g_filename[0] != (byte)0) ? g_filename : untitled);
    if (g_modified) { strcat(title, star); };
    SetWindowTextA(hwnd, (LPCSTR)title);
    return;
};

def ask_save(HWND hwnd) -> int
{
    noopstr msg = "Do you want to save changes?\0",
            cap = "Notepad\0";
    return MessageBoxA(hwnd, (LPCSTR)msg, (LPCSTR)cap, MB_YESNOCANCEL | MB_ICONQUESTION);
};

def do_save(HWND hwnd, bool save_as) -> bool
{
    byte[260]     path;
    OPENFILENAMEA ofn;
    DWORD         written;
    noopstr filter = "Text Files\0*.txt\0All Files\0*.*\0\0",
            defext = "txt\0",
            cap    = "Save As\0";

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

    int   len = GetWindowTextLengthA(g_hwnd_edit) + 1;
    void* buf = malloc((size_t)len);
    if (buf == STDLIB_GVP) { return false; };

    GetWindowTextA(g_hwnd_edit, (LPSTR)buf, len);

    HWND hf = CreateFileA((LPCSTR)g_filename, GENERIC_WRITE, 0,
                           STDLIB_GVP, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, (HWND)0);
    if (hf == (HWND)0xFFFFFFFFFFFFFFFFu) { free(buf); return false; };

    WriteFile(hf, buf, (DWORD)(len - 1), @written, STDLIB_GVP);
    CloseHandle(hf);
    free(buf);
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
    noopstr filter = "Text Files\0*.txt\0All Files\0*.*\0\0",
            cap    = "Open\0";

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
    void* buf = malloc((size_t)(fsize + 1));
    if (buf == STDLIB_GVP) { CloseHandle(hf); return; };

    ReadFile(hf, buf, (DWORD)fsize, @bread, STDLIB_GVP);
    CloseHandle(hf);
    ((byte*)buf)[fsize] = (byte)0;

    SetWindowTextA(g_hwnd_edit, (LPCSTR)buf);
    free(buf);
    strcpy(g_filename, path);
    g_modified = false;
    update_title(hwnd);
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
    SetWindowTextA(g_hwnd_edit, (LPCSTR)"\0");
    g_filename[0] = (byte)0;
    g_modified    = false;
    update_title(hwnd);
    return;
};

// ============================================================================
// WINDOW PROCEDURE
// ============================================================================

def NotepadWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) -> LRESULT
{
    RECT rc;
    int  r, lo;

    if (msg == WM_CREATE)
    {
        HMENU hmenu = CreateMenu(),
              hfile = CreatePopupMenu(),
              hedit = CreatePopupMenu(),
              hhelp = CreatePopupMenu();

        noopstr sNew = "&New\tCtrl+N\0",     sOpen   = "&Open...\tCtrl+O\0",
                sSave = "&Save\tCtrl+S\0",   sSaveAs = "Save &As...\0",
                sExit = "E&xit\0",           sUndo   = "&Undo\tCtrl+Z\0",
                sCut  = "Cu&t\tCtrl+X\0",    sCopy   = "&Copy\tCtrl+C\0",
                sPaste = "&Paste\tCtrl+V\0", sSel    = "Select &All\tCtrl+A\0",
                sAbout = "&About\0",
                mFile = "&File\0", mEdit = "&Edit\0", mHelp = "&Help\0";

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
        AppendMenuA(hhelp, MF_STRING,    (UINT_PTR)IDM_ABOUT,     (LPCSTR)sAbout);
        AppendMenuA(hmenu, MF_POPUP, (UINT_PTR)hfile, (LPCSTR)mFile);
        AppendMenuA(hmenu, MF_POPUP, (UINT_PTR)hedit, (LPCSTR)mEdit);
        AppendMenuA(hmenu, MF_POPUP, (UINT_PTR)hhelp, (LPCSTR)mHelp);
        SetMenu(hwnd, hmenu);

        noopstr edit_cls = "EDIT\0";
        GetClientRect(hwnd, @rc);
        g_hwnd_edit = CreateWindowExA(
            0, (LPCSTR)edit_cls, (LPCSTR)"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_HSCROLL |
            ES_MULTILINE | ES_AUTOVSCROLL | ES_AUTOHSCROLL | ES_NOHIDESEL | ES_WANTRETURN,
            0, 0, rc.right - rc.left, rc.bottom - rc.top,
            hwnd, (HMENU)IDM_EDIT_CTRL, GetModuleHandleA((LPCSTR)0), STDLIB_GVP);

        SetFocus(g_hwnd_edit);
        return 0;
    };

    if (msg == WM_SIZE)
    {
        GetClientRect(hwnd, @rc);
        MoveWindow(g_hwnd_edit, 0, 0, rc.right - rc.left, rc.bottom - rc.top, true);
        return 0;
    };

    if (msg == WM_COMMAND)
    {
        lo = (int)(wParam & 0xFFFF);
        if (lo == IDM_EDIT_CTRL & (int)((wParam >> 16) & 0xFFFF) == (int)EN_CHANGE)
        {
            g_modified = true;
            update_title(hwnd);
            return 0;
        };
        if (lo == IDM_NEW)       { do_new(hwnd);                                     return 0; };
        if (lo == IDM_SAVE)      { do_save(hwnd, false);                             return 0; };
        if (lo == IDM_SAVEAS)    { do_save(hwnd, true);                              return 0; };
        if (lo == IDM_UNDO)      { SendMessageA(g_hwnd_edit, WM_UNDO,  0, 0);        return 0; };
        if (lo == IDM_CUT)       { SendMessageA(g_hwnd_edit, WM_CUT,   0, 0);        return 0; };
        if (lo == IDM_COPY)      { SendMessageA(g_hwnd_edit, WM_COPY,  0, 0);        return 0; };
        if (lo == IDM_PASTE)     { SendMessageA(g_hwnd_edit, WM_PASTE, 0, 0);        return 0; };
        if (lo == IDM_SELECTALL) { SendMessageA(g_hwnd_edit, EM_SETSEL, 0, -1);      return 0; };
        if (lo == IDM_ABOUT)
        {
            noopstr amsg = "Notepad\nWritten in Flux.\nAuthor: Karac V. Thweatt\n\nModeled after Microslop Bloatpad.\0", acap = "About\0";
            MessageBoxA(hwnd, (LPCSTR)amsg, (LPCSTR)acap, 0);
            return 0;
        };
        if (lo == IDM_OPEN)
        {
            if (g_modified)
            {
                r = ask_save(hwnd);
                if (r == IDCANCEL) { return 0; };
                if (r == IDYES)    { do_save(hwnd, false); };
            };
            do_open(hwnd);
            return 0;
        };
        if (lo == IDM_EXIT)
        {
            if (g_modified)
            {
                r = ask_save(hwnd);
                if (r == IDCANCEL) { return 0; };
                if (r == IDYES)    { do_save(hwnd, false); };
            };
            DestroyWindow(hwnd);
            return 0;
        };
    };

    if (msg == WM_CLOSE)
    {
        if (g_modified)
        {
            r = ask_save(hwnd);
            if (r == IDCANCEL) { return 0; };
            if (r == IDYES)    { do_save(hwnd, false); };
        };
        DestroyWindow(hwnd);
        return 0;
    };

    if (msg == WM_DESTROY) { PostQuitMessage(0); return 0; };

    return DefWindowProcA(hwnd, msg, wParam, lParam);
};

// ============================================================================
// ENTRY POINT
// ============================================================================

def main() -> int
{
    FreeConsole();
    HINSTANCE hinstance = GetModuleHandleA((LPCSTR)0);
    noopstr cls = "FluxNotepad\0",
            ttl = "Notepad - Untitled\0";

    WNDCLASSEXA wc;
    wc.cbSize        = (UINT)(sizeof(WNDCLASSEXA) / 8);
    wc.style         = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc   = (WNDPROC)@NotepadWndProc;
    wc.cbClsExtra    = 0;
    wc.cbWndExtra    = 0;
    wc.hInstance     = hinstance;
    wc.hIcon         = LoadIconA((HINSTANCE)0, (LPCSTR)32512);
    wc.hCursor       = LoadCursorA((HINSTANCE)0, (LPCSTR)32512);
    wc.hbrBackground = GetStockObject(WHITE_BRUSH);
    wc.lpszMenuName  = (LPCSTR)0;
    wc.lpszClassName = (LPCSTR)cls;
    wc.hIconSm       = (HICON)0;
    RegisterClassExA(@wc);

    HWND hwnd = CreateWindowExA(
        0, (LPCSTR)cls, (LPCSTR)ttl,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
        (HWND)0, (HMENU)0, hinstance, STDLIB_GVP);

    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageA(@msg, (HWND)0, 0, 0))
    {
        if (msg.message == WM_KEYDOWN & msg.wParam == 0x41 &
            (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0)
        {
            SendMessageA(g_hwnd_edit, EM_SETSEL, 0, -1);
        }
        else
        {
            TranslateMessage(@msg);
            DispatchMessageA(@msg);
        };
    };

    return (int)msg.wParam;
};
