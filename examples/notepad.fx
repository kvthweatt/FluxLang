#import "standard.fx";
#import "redwindows.fx";
#import "redtypes.fx";
#import "ffifio.fx";

using standard::strings,
      standard::file,
      standard::io::console,
      standard::system::windows;

// ============================================================================
// Notepad Clone for Windows
// ============================================================================

// Menu command IDs
const int IDM_FILE_NEW     = 1001,
          IDM_FILE_OPEN    = 1002,
          IDM_FILE_SAVE    = 1003,
          IDM_FILE_SAVE_AS = 1004,
          IDM_FILE_EXIT    = 1005,
          IDM_EDIT_UNDO    = 2001,
          IDM_EDIT_CUT     = 2002,
          IDM_EDIT_COPY    = 2003,
          IDM_EDIT_PASTE   = 2004,
          IDM_EDIT_DELETE  = 2005,
          IDM_EDIT_SELECT_ALL = 2006,
          IDM_HELP_ABOUT   = 3001;

// Maximum file size (1MB)
const int MAX_FILE_SIZE = 1048576;

// Buffer size for text
const int TEXT_BUFFER_SIZE = 65536;

// Global variables
heap byte* g_text_buffer = (byte*)0;
heap byte* g_file_path = (byte*)0;
bool g_modified = false;
HWND g_hEdit = (HWND)0;

// ============================================================================
// Forward declarations
// ============================================================================

def update_window_title(HWND hwnd) -> void;
def load_file(HWND hwnd, byte* path) -> bool;
def save_file(HWND hwnd, byte* path) -> bool;
def show_open_dialog(HWND hwnd) -> bool;
def show_save_dialog(HWND hwnd) -> bool;
def show_about_dialog(HWND hwnd) -> void;

// ============================================================================
// File operations
// ============================================================================

def load_file(HWND hwnd, byte* path) -> bool
{
    i64 handle;
    i32 bytes_read;
    u32 file_size;
    
    // Open file for reading
    handle = open_read(path);
    if (handle == (i64)INVALID_HANDLE_VALUE)
    {
        return false;
    };
    
    // Get file size
    file_size = (u32)standard::strings::strlen(path); // Placeholder - need actual file size
    // For simplicity, read up to buffer size
    bytes_read = win_read(handle, g_text_buffer, TEXT_BUFFER_SIZE - 1);
    win_close(handle);
    
    if (bytes_read > 0)
    {
        g_text_buffer[bytes_read] = '\0';
        SetWindowTextA(g_hEdit, (LPCSTR)g_text_buffer);
        
        // Save path
        standard::strings::strcpy(g_file_path, path);
        
        g_modified = false;
        update_window_title(hwnd);
        return true;
    };
    
    return false;
};

def save_file(HWND hwnd, byte* path) -> bool
{
    i64 handle;
    i32 bytes_written;
    i32 text_len;
    
    // Get text from edit control
    text_len = GetWindowTextA(g_hEdit, (LPSTR)g_text_buffer, TEXT_BUFFER_SIZE);
    
    // Open file for writing
    handle = open_write(path);
    if (handle == (i64)INVALID_HANDLE_VALUE)
    {
        return false;
    };
    
    bytes_written = win_write(handle, g_text_buffer, (u32)text_len);
    win_close(handle);
    
    if (bytes_written == text_len)
    {
        // Save path
        standard::strings::strcpy(g_file_path, path);
        
        g_modified = false;
        update_window_title(hwnd);
        return true;
    };
    
    return false;
};

def show_open_dialog(HWND hwnd) -> bool
{
    // For simplicity, return false
    // Full implementation would use GetOpenFileName
    return false;
};

def show_save_dialog(HWND hwnd) -> bool
{
    // For simplicity, return false
    // Full implementation would use GetSaveFileName
    return false;
};

def show_about_dialog(HWND hwnd) -> void
{
    // Simple message box placeholder
    // MessageBoxA would be called here
    print("Flux Notepad\nVersion 1.0\nA simple text editor\n");
    return;
};

def update_window_title(HWND hwnd) -> void
{
    byte[512] title;
    byte[256] filename;
    
    if (g_file_path != (byte*)0 & g_file_path[0] != '\0')
    {
        // Extract filename from path
        int i, start;
        i = 0;
        start = 0;
        while (g_file_path[i] != '\0')
        {
            if (g_file_path[i] == '\\' | g_file_path[i] == '/')
            {
                start = i + 1;
            };
            i++;
        };
        
        standard::strings::strcpy(filename, @g_file_path[start]);
        
        if (g_modified)
        {
            standard::strings::sprintf(title, "*%s - Flux Notepad\0", filename);
        }
        else
        {
            standard::strings::sprintf(title, "%s - Flux Notepad\0", filename);
        };
    }
    else
    {
        if (g_modified)
        {
            standard::strings::strcpy(title, "*Untitled - Flux Notepad\0");
        }
        else
        {
            standard::strings::strcpy(title, "Untitled - Flux Notepad\0");
        };
    };
    
    SetWindowTextA(hwnd, (LPCSTR)title);
    return;
};

// ============================================================================
// Window Procedure
// ============================================================================

def NotepadWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) -> LRESULT
{
    switch (msg)
    {
        case (WM_CREATE)
        {
            // Create edit control
            g_hEdit = CreateWindowExA(WS_EX_CLIENTEDGE,
                                       (LPCSTR)"EDIT\0",
                                       (LPCSTR)"\0",
                                       WS_CHILD | WS_VISIBLE | WS_VSCROLL | 
                                       ES_LEFT | ES_MULTILINE | ES_AUTOVSCROLL,
                                       0, 0, 0, 0,
                                       hwnd,
                                       (HMENU)0,
                                       GetModuleHandleA((LPCSTR)0),
                                       (void*)0);
            
            // Allocate buffers
            g_text_buffer = (byte*)fmalloc((size_t)TEXT_BUFFER_SIZE);
            g_file_path = (byte*)fmalloc((size_t)512);
            
            if (g_text_buffer == (byte*)0 | g_file_path == (byte*)0)
            {
                return -1;
            };
            
            g_text_buffer[0] = '\0';
            g_file_path[0] = '\0';
            
            return 0;
        }
        
        case (WM_SIZE)
        {
            // Resize edit control to fill window
            int width = (int)LOWORD(lParam);
            int height = (int)HIWORD(lParam);
            SetWindowPos(g_hEdit, (HWND)0, 0, 0, width, height, SWP_NOZORDER);
            return 0;
        }
        
        case (WM_COMMAND)
        {
            int id = (int)LOWORD(wParam);
            
            switch (id)
            {
                case (IDM_FILE_NEW)
                {
                    if (g_modified)
                    {
                        // Prompt to save changes
                        // For simplicity, just clear
                    };
                    
                    SetWindowTextA(g_hEdit, (LPCSTR)"\0");
                    g_file_path[0] = '\0';
                    g_modified = false;
                    update_window_title(hwnd);
                    return 0;
                }
                
                case (IDM_FILE_OPEN)
                {
                    if (show_open_dialog(hwnd))
                    {
                        // File loaded
                    };
                    return 0;
                }
                
                case (IDM_FILE_SAVE)
                {
                    if (g_file_path[0] != '\0')
                    {
                        save_file(hwnd, g_file_path);
                    }
                    else
                    {
                        show_save_dialog(hwnd);
                    };
                    return 0;
                }
                
                case (IDM_FILE_SAVE_AS)
                {
                    show_save_dialog(hwnd);
                    return 0;
                }
                
                case (IDM_FILE_EXIT)
                {
                    if (g_modified)
                    {
                        // Prompt to save changes
                    };
                    PostQuitMessage(0);
                    return 0;
                }
                
                case (IDM_EDIT_UNDO)
                {
                    SendMessageA(g_hEdit, (UINT)0x00C7, 0, 0); // EM_UNDO
                    return 0;
                }
                
                case (IDM_EDIT_CUT)
                {
                    SendMessageA(g_hEdit, (UINT)0x0300, 0, 0); // WM_CUT
                    g_modified = true;
                    update_window_title(hwnd);
                    return 0;
                }
                
                case (IDM_EDIT_COPY)
                {
                    SendMessageA(g_hEdit, (UINT)0x0301, 0, 0); // WM_COPY
                    return 0;
                }
                
                case (IDM_EDIT_PASTE)
                {
                    SendMessageA(g_hEdit, (UINT)0x0302, 0, 0); // WM_PASTE
                    g_modified = true;
                    update_window_title(hwnd);
                    return 0;
                }
                
                case (IDM_EDIT_DELETE)
                {
                    SendMessageA(g_hEdit, (UINT)0x0304, 0, 0); // WM_CLEAR
                    g_modified = true;
                    update_window_title(hwnd);
                    return 0;
                }
                
                case (IDM_EDIT_SELECT_ALL)
                {
                    SendMessageA(g_hEdit, (UINT)0x00B1, 0, -1); // EM_SETSEL
                    return 0;
                }
                
                case (IDM_HELP_ABOUT)
                {
                    show_about_dialog(hwnd);
                    return 0;
                }
            };
            return 0;
        }
        
        case (WM_CLOSE)
        {
            if (g_modified)
            {
                // Prompt to save changes
            };
            DestroyWindow(hwnd);
            return 0;
        }
        
        case (WM_DESTROY)
        {
            if (g_text_buffer != (byte*)0)
            {
                ffree((u64)g_text_buffer);
            };
            if (g_file_path != (byte*)0)
            {
                ffree((u64)g_file_path);
            };
            PostQuitMessage(0);
            return 0;
        }
    };
    
    return DefWindowProcA(hwnd, msg, wParam, lParam);
};

// ============================================================================
// Create Menu
// ============================================================================

def create_menu() -> HMENU
{
    HMENU hMenu = CreateMenu();
    HMENU hFileMenu = CreatePopupMenu();
    HMENU hEditMenu = CreatePopupMenu();
    HMENU hHelpMenu = CreatePopupMenu();
    
    // File menu
    AppendMenuA(hFileMenu, MF_STRING, IDM_FILE_NEW, "&New\tCtrl+N");
    AppendMenuA(hFileMenu, MF_STRING, IDM_FILE_OPEN, "&Open...\tCtrl+O");
    AppendMenuA(hFileMenu, MF_STRING, IDM_FILE_SAVE, "&Save\tCtrl+S");
    AppendMenuA(hFileMenu, MF_STRING, IDM_FILE_SAVE_AS, "Save &As...");
    AppendMenuA(hFileMenu, MF_SEPARATOR, 0, (LPCSTR)0);
    AppendMenuA(hFileMenu, MF_STRING, IDM_FILE_EXIT, "E&xit");
    
    // Edit menu
    AppendMenuA(hEditMenu, MF_STRING, IDM_EDIT_UNDO, "&Undo\tCtrl+Z");
    AppendMenuA(hEditMenu, MF_SEPARATOR, 0, (LPCSTR)0);
    AppendMenuA(hEditMenu, MF_STRING, IDM_EDIT_CUT, "Cu&t\tCtrl+X");
    AppendMenuA(hEditMenu, MF_STRING, IDM_EDIT_COPY, "&Copy\tCtrl+C");
    AppendMenuA(hEditMenu, MF_STRING, IDM_EDIT_PASTE, "&Paste\tCtrl+V");
    AppendMenuA(hEditMenu, MF_STRING, IDM_EDIT_DELETE, "&Delete\tDel");
    AppendMenuA(hEditMenu, MF_SEPARATOR, 0, (LPCSTR)0);
    AppendMenuA(hEditMenu, MF_STRING, IDM_EDIT_SELECT_ALL, "Select &All\tCtrl+A");
    
    // Help menu
    AppendMenuA(hHelpMenu, MF_STRING, IDM_HELP_ABOUT, "&About");
    
    // Attach menus to main menu
    AppendMenuA(hMenu, MF_POPUP, (UINT)hFileMenu, "&File");
    AppendMenuA(hMenu, MF_POPUP, (UINT)hEditMenu, "&Edit");
    AppendMenuA(hMenu, MF_POPUP, (UINT)hHelpMenu, "&Help");
    
    return hMenu;
};

// ============================================================================
// Main entry point
// ============================================================================

def main() -> int
{
    HINSTANCE hInstance = GetModuleHandleA((LPCSTR)0);
    HMENU hMenu;
    HWND hwnd;
    MSG msg;
    
    // Set up window class
    WNDCLASSEXA wc;
    wc.cbSize = (UINT)(sizeof(WNDCLASSEXA) / 8);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = (WNDPROC)@NotepadWndProc;
    wc.cbClsExtra = 0;
    wc.cbWndExtra = 0;
    wc.hInstance = hInstance;
    wc.hIcon = LoadIconA((HINSTANCE)0, (LPCSTR)32512);
    wc.hCursor = LoadCursorA((HINSTANCE)0, (LPCSTR)32512);
    wc.hbrBackground = GetStockObject(WHITE_BRUSH);
    wc.lpszMenuName = (LPCSTR)0;
    wc.lpszClassName = (LPCSTR)"NotepadClass\0";
    wc.hIconSm = (HICON)0;
    
    // Register window class
    RegisterClassExA(@wc);
    
    // Create menu
    hMenu = create_menu();
    
    // Create window
    hwnd = CreateWindowExA(WS_EX_APPWINDOW,
                           (LPCSTR)"NotepadClass\0",
                           (LPCSTR)"Untitled - Flux Notepad\0",
                           WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                           CW_USEDEFAULT, CW_USEDEFAULT,
                           800, 600,
                           (HWND)0,
                           hMenu,
                           hInstance,
                           (void*)0);
    
    if (hwnd == (HWND)0)
    {
        return -1;
    };
    
    // Message loop
    while (GetMessageA(@msg, (HWND)0, 0, 0))
    {
        TranslateMessage(@msg);
        DispatchMessageA(@msg);
    };
    
    return 0;
};