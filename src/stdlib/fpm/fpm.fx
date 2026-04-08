// fpm.fx - Flux Package Manager
// Author: Karac V. Thweatt
//
// Usage:
//   fpm install <package>
//   fpm install --stdlib
//   fpm install --all
//   fpm remove <package>
//   fpm update [package]
//   fpm update --all
//   fpm list
//   fpm list --available
//   fpm info <package>
//   fpm addsource <url>
//   fpm removesource <url>
//   fpm sources

#import "standard.fx", "socket_object_raw.fx", "net_windows.fx", "json.fx";

using standard::io::console,
      standard::io::file,
      standard::strings,
      standard::sockets,
      standard::net,
      standard::memory::allocators::stdarena,
      json;

// ─── Constants ────────────────────────────────────────────────────────────────

#def FPM_MAX_PATH      512;
#def FPM_MAX_URL       1024;
#def FPM_MAX_NAME      128;
#def FPM_MAX_VERSION   32;
#def FPM_HTTP_BUF      65536;
#def FPM_MAX_PACKAGES  256;

noopstr STDLIB_BASE_URL = "https://raw.githubusercontent.com/kvthweatt/Flux/main/src/stdlib\0";
noopstr FPM_HOST        = "raw.githubusercontent.com\0";

// ─── Path helpers ─────────────────────────────────────────────────────────────

// Build a path from home directory + suffix.
// home() reads USERPROFILE on Windows, HOME on Linux.
def get_home(byte* out, int out_size) -> void
{
    byte* h;
    h = getenv("USERPROFILE\0");
    if ((u64)h == 0)
    {
        h = getenv("HOME\0");
    };
    if ((u64)h == 0)
    {
        out[0] = (byte)'.';
        out[1] = (byte)0;
        return;
    };
    strncpy(out, h, out_size - 1);
    out[out_size - 1] = (byte)0;
    return;
};

def path_join(byte* out, int out_size, byte* a, byte* b) -> void
{
    int la, lb;
    la = strlen(a);
    lb = strlen(b);
    strncpy(out, a, out_size - 1);
    if (la > 0 & (char)a[la - 1] != '/' & (char)a[la - 1] != '\\')
    {
        if (la < out_size - 1)
        {
            out[la] = (byte)'\\';
            la = la + 1;
        };
    };
    strncpy(@out[la], b, out_size - la - 1);
    out[out_size - 1] = (byte)0;
    return;
};

// Check whether a file exists
def file_exists_path(byte* path) -> bool
{
    void* f;
    f = fopen(path, "rb\0");
    if ((u64)f == 0) { return false; };
    fclose(f);
    return true;
};

// Read entire file into a heap buffer. Returns byte count, -1 on error.
// Caller must ffree the buffer.
def read_file_alloc(byte* path, byte** out_buf) -> int
{
    void* f;
    int   sz, nread;
    byte* buf;

    f = fopen(path, "rb\0");
    if ((u64)f == 0) { return -1; };

    fseek(f, 0, 2);
    sz = ftell(f);
    rewind(f);

    buf = (byte*)fmalloc((u64)sz + 1);
    if ((u64)buf == 0) { fclose(f); return -1; };

    nread = fread(buf, 1, sz, f);
    buf[nread] = (byte)0;
    fclose(f);

    *out_buf = buf;
    return nread;
};

// Write buffer to file. Returns bytes written, -1 on error.
def write_file_path(byte* path, byte* buf, int len) -> int
{
    void* f;
    int   written;
    f = fopen(path, "wb\0");
    if ((u64)f == 0) { return -1; };
    written = fwrite(buf, 1, len, f);
    fclose(f);
    return written;
};

// ─── Extern declarations ───────────────────────────────────────────────────────

extern
{
    def !!
        getenv(byte*) -> byte*,
        _mkdir(byte*) -> int,
        mkdir(byte*, int) -> int,
        strncpy(byte*, byte*, size_t) -> byte*,
        strncmp(byte*, byte*, size_t) -> int,
        strcat(byte*, byte*) -> byte*,
        sprintf(byte*, byte*, ...) -> int,
        snprintf(byte*, size_t, byte*, ...) -> int,
        atoi(byte*) -> int,
        rewind(void*) -> void,
        fseek(void*, int, int) -> int,
        ftell(void*) -> int,
        fread(void*, int, int, void*) -> int,
        fwrite(void*, int, int, void*) -> int,
        fopen(byte*, byte*) -> void*,
        fclose(void*) -> int;
};

// ─── WinINet (HTTPS support) ──────────────────────────────────────────────────

#def INTERNET_OPEN_TYPE_DIRECT        1;
#def INTERNET_FLAG_SECURE             0x00800000;
#def INTERNET_FLAG_RELOAD             0x80000000;
#def INTERNET_FLAG_NO_CACHE_WRITE     0x04000000;
#def INTERNET_QUERY_CONTENT_LENGTH    5;
#def HTTP_QUERY_STATUS_CODE           19;
#def HTTP_QUERY_FLAG_NUMBER           0x20000000;

extern
{
    def !!
        InternetOpenA(byte*, u32, byte*, byte*, u32) -> void*,
        InternetConnectA(void*, byte*, u16, byte*, byte*, u32, u32, u64) -> void*,
        HttpOpenRequestA(void*, byte*, byte*, byte*, byte*, byte**, u32, u64) -> void*,
        HttpSendRequestA(void*, byte*, u32, void*, u32) -> bool,
        HttpQueryInfoA(void*, u32, void*, u32*, u32*) -> bool,
        InternetReadFile(void*, void*, u32, u32*) -> bool,
        InternetCloseHandle(void*) -> bool;
};

// ─── mkdir cross-platform ─────────────────────────────────────────────────────

def make_dir(byte* path) -> void
{
    _mkdir(path);
    return;
};

def ensure_dirs() -> void
{
    byte[FPM_MAX_PATH] home, fpm, packages, src, stdlib;

    get_home(@home[0], FPM_MAX_PATH);
    path_join(@fpm[0],      FPM_MAX_PATH, @home[0],    ".fpm\0");
    path_join(@packages[0], FPM_MAX_PATH, @fpm[0],     "packages\0");

    make_dir(@fpm[0]);
    make_dir(@packages[0]);
    return;
};

// ─── Version comparison ───────────────────────────────────────────────────────

// Parse "1.2.3" into major, minor, patch
def parse_version(byte* v, int* major, int* minor, int* patch) -> void
{
    int i, start;
    byte[FPM_MAX_VERSION] part;

    // major
    i = 0;
    while (v[i] != (byte)'.' & v[i] != (byte)0) { i = i + 1; };
    strncpy(@part[0], v, i);
    part[i] = (byte)0;
    *major = atoi(@part[0]);
    if (v[i] == (byte)0) { *minor = 0; *patch = 0; return; };
    i = i + 1;
    start = i;

    // minor
    while (v[i] != (byte)'.' & v[i] != (byte)0) { i = i + 1; };
    strncpy(@part[0], @v[start], i - start);
    part[i - start] = (byte)0;
    *minor = atoi(@part[0]);
    if (v[i] == (byte)0) { *patch = 0; return; };
    i = i + 1;

    // patch
    *patch = atoi(@v[i]);
    return;
};

// Returns: -1 if a < b, 0 if equal, 1 if a > b
def cmp_version(byte* a, byte* b) -> int
{
    int ma, mi_a, pa, mb, mi_b, pb;
    parse_version(a, @ma, @mi_a, @pa);
    parse_version(b, @mb, @mi_b, @pb);
    if (ma != mb) { return ma > mb ? 1 : -1; };
    if (mi_a != mi_b) { return mi_a > mi_b ? 1 : -1; };
    if (pa != pb) { return pa > pb ? 1 : -1; };
    return 0;
};

// Check constraint like ">=1.0.0", "<2.0.0", "1.0.0"
def check_constraint(byte* installed_v, byte* constraint) -> bool
{
    byte[FPM_MAX_VERSION] ver;
    int i, cmp_result;

    if (strncmp(constraint, ">=\0", 2) == 0)
    {
        strncpy(@ver[0], @constraint[2], FPM_MAX_VERSION - 1);
        cmp_result = cmp_version(installed_v, @ver[0]);
        return cmp_result >= 0;
    };
    if (strncmp(constraint, "<=\0", 2) == 0)
    {
        strncpy(@ver[0], @constraint[2], FPM_MAX_VERSION - 1);
        cmp_result = cmp_version(installed_v, @ver[0]);
        return cmp_result <= 0;
    };
    if (constraint[0] == (byte)'>')
    {
        strncpy(@ver[0], @constraint[1], FPM_MAX_VERSION - 1);
        cmp_result = cmp_version(installed_v, @ver[0]);
        return cmp_result > 0;
    };
    if (constraint[0] == (byte)'<')
    {
        strncpy(@ver[0], @constraint[1], FPM_MAX_VERSION - 1);
        cmp_result = cmp_version(installed_v, @ver[0]);
        return cmp_result < 0;
    };
    // Exact
    return strcmp(installed_v, constraint) == 0;
};

// ─── HTTP GET ─────────────────────────────────────────────────────────────────

// HTTPS GET via WinINet. Downloads url path from host into out_buf (heap alloc).
// Returns content length, -1 on error. Caller must ffree out_buf.
def http_get(byte* host, byte* path, byte** out_buf) -> int
{
    void* hsession, hconnect, hrequest;
    u32   bytes_read, total, cap;
    bool  ok;
    byte* buf;
    byte* newbuf;
    byte[FPM_HTTP_BUF] chunk;
    u32   status, status_size;

    hsession = InternetOpenA("fpm/1.0\0", INTERNET_OPEN_TYPE_DIRECT,
                             (byte*)0, (byte*)0, 0);
    if ((u64)hsession == 0)
    {
        print("  ERROR: InternetOpenA failed\n\0");
        return -1;
    };

    hconnect = InternetConnectA(hsession, host, (u16)443,
                                (byte*)0, (byte*)0,
                                3,  // INTERNET_SERVICE_HTTP
                                0, 0);
    if ((u64)hconnect == 0)
    {
        print("  ERROR: Could not connect to \0"); print(host); print("\n\0");
        InternetCloseHandle(hsession);
        return -1;
    };

    hrequest = HttpOpenRequestA(hconnect, "GET\0", path,
                                (byte*)0, (byte*)0, (byte**)0,
                                INTERNET_FLAG_SECURE |
                                INTERNET_FLAG_RELOAD |
                                INTERNET_FLAG_NO_CACHE_WRITE,
                                0);
    if ((u64)hrequest == 0)
    {
        print("  ERROR: HttpOpenRequestA failed\n\0");
        InternetCloseHandle(hconnect);
        InternetCloseHandle(hsession);
        return -1;
    };

    ok = HttpSendRequestA(hrequest, (byte*)0, 0, (void*)0, 0);
    if (!ok)
    {
        print("  ERROR: HttpSendRequestA failed\n\0");
        InternetCloseHandle(hrequest);
        InternetCloseHandle(hconnect);
        InternetCloseHandle(hsession);
        return -1;
    };

    // Check HTTP status code
    status      = 0;
    status_size = 4;
    HttpQueryInfoA(hrequest,
                   HTTP_QUERY_STATUS_CODE | HTTP_QUERY_FLAG_NUMBER,
                   @status, @status_size, (u32*)0);
    if (status != 0 & status != 200)
    {
        print("  ERROR: HTTP status \0");
        InternetCloseHandle(hrequest);
        InternetCloseHandle(hconnect);
        InternetCloseHandle(hsession);
        return -1;
    };

    // Read response body into growable heap buffer
    cap   = FPM_HTTP_BUF;
    buf   = (byte*)fmalloc((u64)cap);
    total = 0;

    bytes_read = 0;
    ok = InternetReadFile(hrequest, @chunk[0], FPM_HTTP_BUF - 1, @bytes_read);
    while (ok & bytes_read > 0)
    {
        if (total + bytes_read >= (u32)cap)
        {
            cap    = cap * 2;
            newbuf = (byte*)fmalloc((u64)cap);
            memcpy(newbuf, buf, total);
            ffree((u64)buf);
            buf = newbuf;
        };
        memcpy(@buf[total], @chunk[0], bytes_read);
        total = total + bytes_read;
        bytes_read = 0;
        ok = InternetReadFile(hrequest, @chunk[0], FPM_HTTP_BUF - 1, @bytes_read);
    };
    buf[total] = (byte)0;

    InternetCloseHandle(hrequest);
    InternetCloseHandle(hconnect);
    InternetCloseHandle(hsession);

    *out_buf = buf;
    return (int)total;
};

// Download a file from STDLIB_BASE_URL/sub_path/entry to dest path
def download_file(byte* sub_path, byte* entry, byte* dest) -> bool
{
    byte[FPM_MAX_URL] url_path;
    byte* content;
    int   content_len, written;

    if (strlen(sub_path) > 0)
    {
        snprintf(@url_path[0], FPM_MAX_URL, "/%s/%s/%s\0",
                 "kvthweatt/FluxLang/main/src/stdlib",
                 sub_path, entry);
    }
    else
    {
        snprintf(@url_path[0], FPM_MAX_URL, "/%s/%s\0",
                 "kvthweatt/FluxLang/main/src/stdlib",
                 entry);
    };

    content_len = http_get(FPM_HOST, @url_path[0], @content);
    if (content_len < 0) { return false; };

    written = write_file_path(dest, content, content_len);
    ffree((u64)content);

    return written > 0;
};

// ─── JSON file helpers ────────────────────────────────────────────────────────

// Read and parse a JSON file. Returns root JSONNode* (arena-owned) or null.
// Arena must be initialized by caller.
def parse_json_file(byte* path, Arena* arena) -> JSONNode*
{
    byte*     buf;
    int       n;
    JSONNode* root;

    n = read_file_alloc(path, @buf);
    if (n < 0) { return (JSONNode*)0; };

    // Allocate root node from arena so it outlives this function
    root = (JSONNode*)standard::memory::allocators::stdarena::alloc(arena, sizeof(JSONNode) / sizeof(byte));
    if ((u64)root == 0) { ffree((u64)buf); return (JSONNode*)0; };

    JSONParser parser(buf, n, arena);
    parser.parse(root);
    ffree((u64)buf);

    if (!parser.ok()) { return (JSONNode*)0; };
    return root;
};

// Fetch and parse a remote JSON file. Returns root JSONNode* (arena-owned) or null.
def fetch_json_url(byte* host, byte* url_path, Arena* arena) -> JSONNode*
{
    byte*     buf;
    int       n;
    JSONNode* root;

    n = http_get(host, url_path, @buf);
    if (n < 0) { return (JSONNode*)0; };

    // Allocate root node from arena so it outlives this function
    root = (JSONNode*)standard::memory::allocators::stdarena::alloc(arena, sizeof(JSONNode) / sizeof(byte));
    if ((u64)root == 0) { ffree((u64)buf); return (JSONNode*)0; };

    JSONParser parser(buf, n, arena);
    parser.parse(root);
    ffree((u64)buf);

    if (!parser.ok()) { return (JSONNode*)0; };
    return root;
};

// ─── installed.json helpers ───────────────────────────────────────────────────

// Get a string field from a JSON object node, copy into out.
def json_get_str(JSONNode* obj, byte* key, byte* out, int out_size) -> bool
{
    JSONNode* val;
    val = (JSONNode*)obj.object_get(key);
    if ((u64)val == 0) { out[0] = (byte)0; return false; };
    if (val.type != JSON_STRING) { out[0] = (byte)0; return false; };
    strncpy(out, val.s, out_size - 1);
    out[out_size - 1] = (byte)0;
    return true;
};

// Check if a package name exists as a key in installed JSON object
def installed_has(JSONNode* installed_root, byte* name) -> bool
{
    JSONNode* pkg;
    if ((u64)installed_root == 0) { return false; };
    pkg = (JSONNode*)installed_root.object_get(name);
    return (u64)pkg != 0;
};

// Get version of installed package, returns false if not found
def installed_get_version(JSONNode* installed_root, byte* name, byte* out, int out_size) -> bool
{
    JSONNode* pkg;
    if ((u64)installed_root == 0) { return false; };
    pkg = (JSONNode*)installed_root.object_get(name);
    if ((u64)pkg == 0) { return false; };
    return json_get_str(pkg, "version\0", out, out_size);
};

// ─── Path builders ────────────────────────────────────────────────────────────

def get_fpm_dir(byte* out) -> void
{
    byte[FPM_MAX_PATH] home;
    get_home(@home[0], FPM_MAX_PATH);
    path_join(out, FPM_MAX_PATH, @home[0], ".fpm\0");
    return;
};

def get_packages_dir(byte* out) -> void
{
    byte[FPM_MAX_PATH] fpm;
    get_fpm_dir(@fpm[0]);
    path_join(out, FPM_MAX_PATH, @fpm[0], "packages\0");
    return;
};

def get_stdlib_dir(byte* out) -> void
{
    byte[FPM_MAX_PATH] home;
    int l;
    get_home(@home[0], FPM_MAX_PATH);
    path_join(out, FPM_MAX_PATH, @home[0], "src\0");
    // Append \stdlib
    l = strlen(out);
    out[l]     = (byte)'\\';
    out[l + 1] = (byte)'s';
    out[l + 2] = (byte)'t';
    out[l + 3] = (byte)'d';
    out[l + 4] = (byte)'l';
    out[l + 5] = (byte)'i';
    out[l + 6] = (byte)'b';
    out[l + 7] = (byte)0;
    return;
};

def get_installed_path(byte* out) -> void
{
    byte[FPM_MAX_PATH] fpm;
    get_fpm_dir(@fpm[0]);
    path_join(out, FPM_MAX_PATH, @fpm[0], "installed.json\0");
    return;
};

def get_sources_path(byte* out) -> void
{
    byte[FPM_MAX_PATH] fpm;
    get_fpm_dir(@fpm[0]);
    path_join(out, FPM_MAX_PATH, @fpm[0], "sources.json\0");
    return;
};

def get_stdlib_json_path(byte* out) -> void
{
    byte[FPM_MAX_PATH] sdir;
    get_stdlib_dir(@sdir[0]);
    path_join(out, FPM_MAX_PATH, @sdir[0], "package.json\0");
    return;
};

// ─── Package node helpers ─────────────────────────────────────────────────────

// Given a packages JSONNode* (object), get the package sub-object by name
def get_package_node(JSONNode* packages, byte* name) -> JSONNode*
{
    if ((u64)packages == 0) { return (JSONNode*)0; };
    return (JSONNode*)packages.object_get(name);
};

// Check if package name is in stdlib packages object
def is_stdlib_package(JSONNode* stdlib_packages, byte* name) -> bool
{
    return (u64)get_package_node(stdlib_packages, name) != 0;
};

// ─── Print helpers ────────────────────────────────────────────────────────────

def print_padded(byte* s, int width) -> void
{
    int l, i;
    print(s);
    l = strlen(s);
    i = l;
    while (i < width) { print(" \0"); i = i + 1; };
    return;
};

// ─── Commands ─────────────────────────────────────────────────────────────────

def cmd_install(byte** argv, int argc, int arg_start,
                JSONNode* stdlib_pkgs, JSONNode* all_pkgs,
                JSONNode* installed_root, byte* installed_path,
                Arena* arena) -> void
{
    bool      do_stdlib, do_all;
    int       i, success, failed;
    size_t    k;
    byte*     pname;
    JSONNode* pkgs;
    JSONNode* pkg;
    byte[FPM_MAX_NAME]    name;
    byte[FPM_MAX_PATH]    dest, packages_dir, stdlib_dir;
    byte[FPM_MAX_PATH]    pkg_dir, sub_dir;
    byte[FPM_MAX_VERSION] version;
    byte[FPM_MAX_PATH]    sub_path_buf, entry_buf;
    byte[32]              sbuf, fbuf;

    do_stdlib = false;
    do_all    = false;
    success   = 0;
    failed    = 0;

    get_packages_dir(@packages_dir[0]);
    get_stdlib_dir(@stdlib_dir[0]);

    // Check flags
    i = arg_start;
    while (i < argc)
    {
        if (strcmp(argv[i], "--stdlib\0") == 0) { do_stdlib = true; };
        if (strcmp(argv[i], "--all\0")    == 0) { do_all    = true; };
        i = i + 1;
    };

    if (do_stdlib | do_all)
    {
        if (do_stdlib) { print("Installing full Flux standard library...\n\0"); }
        else           { print("Installing all available packages...\n\0"); };

        pkgs = do_stdlib ? stdlib_pkgs : all_pkgs;
        if ((u64)pkgs == 0) { print("  ERROR: No packages found.\n\0"); return; };

        k = 0;
        while (k < pkgs.object_len())
        {
            pname = pkgs.object_key_at(k);
            pkg   = (JSONNode*)pkgs.object_val_at(k);

            if (is_stdlib_package(stdlib_pkgs, pname))
            {
                print("  Stdlib:   \0"); print(pname);
                print(" (always available)\n\0");
                success = success + 1;
                k = k + 1;
                continue;
            };

            if (installed_has(installed_root, pname))
            {
                print("  Installed: \0"); print(pname);
                print(" (already installed)\n\0");
                success = success + 1;
                k = k + 1;
                continue;
            };

            json_get_str(pkg, "version\0", @version[0],      FPM_MAX_VERSION);
            json_get_str(pkg, "entry\0",   @entry_buf[0],    FPM_MAX_PATH);
            json_get_str(pkg, "path\0",    @sub_path_buf[0], FPM_MAX_PATH);

            path_join(@pkg_dir[0], FPM_MAX_PATH, @packages_dir[0], pname);
            make_dir(@pkg_dir[0]);

            if (strlen(@sub_path_buf[0]) > 0)
            {
                path_join(@sub_dir[0], FPM_MAX_PATH, @pkg_dir[0], @sub_path_buf[0]);
                make_dir(@sub_dir[0]);
                path_join(@dest[0], FPM_MAX_PATH, @sub_dir[0], @entry_buf[0]);
            }
            else
            {
                path_join(@dest[0], FPM_MAX_PATH, @pkg_dir[0], @entry_buf[0]);
            };

            print("  Downloading \0"); print(pname);
            print(" v\0"); print(@version[0]); print("...\n\0");

            if (download_file(@sub_path_buf[0], @entry_buf[0], @dest[0]))
            {
                print("  Installed:  \0"); print(pname);
                print(" -> \0"); print(@dest[0]); print("\n\0");
                success = success + 1;
            }
            else
            {
                print("  FAILED:     \0"); print(pname); print("\n\0");
                failed = failed + 1;
            };

            k = k + 1;
        };
    }
    else
    {
        i = arg_start;
        while (i < argc)
        {
            strncpy(@name[0], argv[i], FPM_MAX_NAME - 1);
            name[FPM_MAX_NAME - 1] = (byte)0;

            if (name[0] == (byte)'-') { i = i + 1; continue; };

            pkg = get_package_node(all_pkgs, @name[0]);
            if ((u64)pkg == 0)
            {
                print("  ERROR: '\0"); print(@name[0]);
                print("' not found in registry.\n\0");
                failed = failed + 1;
                i = i + 1;
                continue;
            };

            if (is_stdlib_package(stdlib_pkgs, @name[0]))
            {
                print("  Stdlib:   \0"); print(@name[0]);
                print(" (always available)\n\0");
                success = success + 1;
                i = i + 1;
                continue;
            };

            if (installed_has(installed_root, @name[0]))
            {
                print("  Already installed: \0"); print(@name[0]); print("\n\0");
                success = success + 1;
                i = i + 1;
                continue;
            };

            json_get_str(pkg, "version\0", @version[0],      FPM_MAX_VERSION);
            json_get_str(pkg, "entry\0",   @entry_buf[0],    FPM_MAX_PATH);
            json_get_str(pkg, "path\0",    @sub_path_buf[0], FPM_MAX_PATH);

            path_join(@pkg_dir[0], FPM_MAX_PATH, @packages_dir[0], @name[0]);
            make_dir(@pkg_dir[0]);

            if (strlen(@sub_path_buf[0]) > 0)
            {
                path_join(@sub_dir[0], FPM_MAX_PATH, @pkg_dir[0], @sub_path_buf[0]);
                make_dir(@sub_dir[0]);
                path_join(@dest[0], FPM_MAX_PATH, @sub_dir[0], @entry_buf[0]);
            }
            else
            {
                path_join(@dest[0], FPM_MAX_PATH, @pkg_dir[0], @entry_buf[0]);
            };

            print("  Downloading \0"); print(@name[0]);
            print(" v\0"); print(@version[0]); print("...\n\0");

            if (download_file(@sub_path_buf[0], @entry_buf[0], @dest[0]))
            {
                print("  Installed:  \0"); print(@name[0]);
                print(" -> \0"); print(@dest[0]); print("\n\0");
                success = success + 1;
            }
            else
            {
                print("  FAILED:     \0"); print(@name[0]); print("\n\0");
                failed = failed + 1;
            };

            i = i + 1;
        };
    };

    strings::i32str(success, @sbuf[0]);
    strings::i32str(failed,  @fbuf[0]);
    print("\nDone. \0"); print(@sbuf[0]);
    print(" installed, \0"); print(@fbuf[0]); print(" failed.\n\0");
    return;
};


def cmd_remove(byte** argv, int argc, int arg_start,
               JSONNode* stdlib_pkgs,
               byte* installed_path) -> void
{
    int i;
    byte[FPM_MAX_NAME] name;
    byte[FPM_MAX_PATH] packages_dir, pkg_dir;

    get_packages_dir(@packages_dir[0]);

    i = arg_start;
    while (i < argc)
    {
        strncpy(@name[0], argv[i], FPM_MAX_NAME - 1);
        name[FPM_MAX_NAME - 1] = (byte)0;

        if (is_stdlib_package(stdlib_pkgs, @name[0]))
        {
            print("  Protected: \0"); print(@name[0]);
            print(" is part of the Flux standard library.\n\0");
            i = i + 1;
            continue;
        };

        path_join(@pkg_dir[0], FPM_MAX_PATH, @packages_dir[0], @name[0]);

        // We can't rmdir recursively in pure Flux easily, so just print guidance
        print("  Removed:   \0"); print(@name[0]);
        print(" (delete \0"); print(@pkg_dir[0]); print(" manually if needed)\n\0");

        i = i + 1;
    };
    return;
};


def cmd_update(byte** argv, int argc, int arg_start,
               JSONNode* stdlib_pkgs, JSONNode* remote_stdlib,
               JSONNode* installed_root, byte* installed_path,
               Arena* arena) -> void
{
    int       i, success, failed;
    bool      do_all, do_specific, matched;
    size_t    k;
    byte*     pname;
    JSONNode* local_pkg;
    JSONNode* remote_pkg;
    byte[FPM_MAX_NAME]    name;
    byte[FPM_MAX_VERSION] local_ver, remote_ver;
    byte[FPM_MAX_PATH]    stdlib_dir, entry_buf, sub_path_buf, dest, sub_dir;
    byte[32]              sbuf, fbuf;

    success     = 0;
    failed      = 0;
    do_all      = true;
    do_specific = false;

    get_stdlib_dir(@stdlib_dir[0]);

    i = arg_start;
    while (i < argc)
    {
        if (argv[i][0] != (byte)'-') { do_all = false; do_specific = true; };
        i = i + 1;
    };

    if ((u64)remote_stdlib == 0)
    {
        print("  WARNING: Could not fetch remote stdlib package.json.\n\0");
    };

    if ((u64)stdlib_pkgs != 0)
    {
        k = 0;
        while (k < stdlib_pkgs.object_len())
        {
            pname = stdlib_pkgs.object_key_at(k);

            if (do_specific)
            {
                matched = false;
                i = arg_start;
                while (i < argc)
                {
                    if (strcmp(argv[i], pname) == 0) { matched = true; break; };
                    i = i + 1;
                };
                if (!matched) { k = k + 1; continue; };
            };

            local_pkg = (JSONNode*)stdlib_pkgs.object_val_at(k);
            json_get_str(local_pkg, "version\0", @local_ver[0], FPM_MAX_VERSION);

            if ((u64)remote_stdlib == 0)
            {
                print("  Skipping \0"); print(pname);
                print(" (no remote info)\n\0");
                k = k + 1;
                continue;
            };

            remote_pkg = get_package_node(remote_stdlib, pname);
            if ((u64)remote_pkg == 0)
            {
                print("  Not found in remote: \0"); print(pname); print("\n\0");
                k = k + 1;
                continue;
            };

            json_get_str(remote_pkg, "version\0", @remote_ver[0], FPM_MAX_VERSION);

            if (cmp_version(@remote_ver[0], @local_ver[0]) <= 0)
            {
                print("  Up to date: \0"); print(pname);
                print(" v\0"); print(@local_ver[0]); print("\n\0");
                success = success + 1;
                k = k + 1;
                continue;
            };

            print("  Updating \0"); print(pname);
            print(": v\0"); print(@local_ver[0]);
            print(" -> v\0"); print(@remote_ver[0]); print("\n\0");

            json_get_str(remote_pkg, "entry\0", @entry_buf[0],    FPM_MAX_PATH);
            json_get_str(remote_pkg, "path\0",  @sub_path_buf[0], FPM_MAX_PATH);

            if (strlen(@sub_path_buf[0]) > 0)
            {
                path_join(@sub_dir[0], FPM_MAX_PATH, @stdlib_dir[0], @sub_path_buf[0]);
                path_join(@dest[0],    FPM_MAX_PATH, @sub_dir[0],    @entry_buf[0]);
            }
            else
            {
                path_join(@dest[0], FPM_MAX_PATH, @stdlib_dir[0], @entry_buf[0]);
            };

            if (download_file(@sub_path_buf[0], @entry_buf[0], @dest[0]))
            {
                print("  Updated:    \0"); print(pname);
                print(" v\0"); print(@remote_ver[0]);
                print(" -> \0"); print(@dest[0]); print("\n\0");
                success = success + 1;
            }
            else
            {
                print("  FAILED:     \0"); print(pname); print("\n\0");
                failed = failed + 1;
            };

            k = k + 1;
        };
    };

    strings::i32str(success, @sbuf[0]);
    strings::i32str(failed,  @fbuf[0]);
    print("\nUpdate complete. \0"); print(@sbuf[0]);
    print(" updated, \0"); print(@fbuf[0]); print(" failed.\n\0");
    return;
};


def cmd_list(bool show_available, JSONNode* all_pkgs, JSONNode* installed_root,
             JSONNode* stdlib_pkgs) -> void
{
    size_t    k;
    byte*     pname;
    JSONNode* pkg;
    bool      inst;
    byte[FPM_MAX_VERSION] ver;
    byte[256]             desc;
    byte[32]              nbuf;

    if (show_available)
    {
        if ((u64)all_pkgs == 0) { print("No packages available.\n\0"); return; };

        strings::i32str((i32)all_pkgs.object_len(), @nbuf[0]);
        print("Available packages (\0"); print(@nbuf[0]); print("):\n\n\0");

        k = 0;
        while (k < all_pkgs.object_len())
        {
            pname = all_pkgs.object_key_at(k);
            pkg   = (JSONNode*)all_pkgs.object_val_at(k);
            json_get_str(pkg, "version\0",     @ver[0],  FPM_MAX_VERSION);
            json_get_str(pkg, "description\0", @desc[0], 256);
            inst = installed_has(installed_root, pname) | is_stdlib_package(stdlib_pkgs, pname);

            print("  \0");
            print_padded(pname, 32);
            print(" v\0"); print_padded(@ver[0], 10);
            print(@desc[0]);
            if (inst) { print(" [installed]\0"); };
            print("\n\0");

            k = k + 1;
        };
    }
    else
    {
        print("Installed packages:\n\n\0");

        if ((u64)stdlib_pkgs != 0)
        {
            k = 0;
            while (k < stdlib_pkgs.object_len())
            {
                pname = stdlib_pkgs.object_key_at(k);
                pkg   = (JSONNode*)stdlib_pkgs.object_val_at(k);
                json_get_str(pkg, "version\0", @ver[0], FPM_MAX_VERSION);
                print("  \0");
                print_padded(pname, 32);
                print(" v\0"); print_padded(@ver[0], 10);
                print("[stdlib]\n\0");
                k = k + 1;
            };
        };

        if ((u64)installed_root != 0)
        {
            k = 0;
            while (k < installed_root.object_len())
            {
                pname = installed_root.object_key_at(k);
                pkg   = (JSONNode*)installed_root.object_val_at(k);
                json_get_str(pkg, "version\0", @ver[0], FPM_MAX_VERSION);
                print("  \0");
                print_padded(pname, 32);
                print(" v\0"); print_padded(@ver[0], 10);
                print("[remote]\n\0");
                k = k + 1;
            };
        };
    };
    return;
};


def cmd_info(byte** argv, int argc, int arg_start,
             JSONNode* all_pkgs, JSONNode* installed_root,
             JSONNode* stdlib_pkgs) -> void
{
    int       i;
    size_t    k;
    JSONNode* pkg;
    JSONNode* deps;
    JSONNode* dver;
    byte*     dname;
    byte[FPM_MAX_NAME]    name;
    byte[FPM_MAX_VERSION] ver;
    byte[256]             desc;
    byte[FPM_MAX_PATH]    entry, sub_path;

    i = arg_start;
    while (i < argc)
    {
        strncpy(@name[0], argv[i], FPM_MAX_NAME - 1);
        name[FPM_MAX_NAME - 1] = (byte)0;

        pkg = get_package_node(all_pkgs, @name[0]);
        if ((u64)pkg == 0)
        {
            print("  '\0"); print(@name[0]); print("' not found in registry.\n\0");
            i = i + 1;
            continue;
        };

        json_get_str(pkg, "version\0",     @ver[0],      FPM_MAX_VERSION);
        json_get_str(pkg, "description\0", @desc[0],     256);
        json_get_str(pkg, "entry\0",       @entry[0],    FPM_MAX_PATH);
        json_get_str(pkg, "path\0",        @sub_path[0], FPM_MAX_PATH);

        print("\n  Package:      \0"); print(@name[0]);
        print("\n  Version:      \0"); print(@ver[0]);
        print("\n  Description:  \0"); print(@desc[0]);
        print("\n  Entry:        \0"); print(@entry[0]);
        if (strlen(@sub_path[0]) > 0)
        {
            print("\n  Subdirectory: \0"); print(@sub_path[0]);
        };

        deps = (JSONNode*)pkg.object_get("dependencies\0");
        if ((u64)deps != 0 & deps.type == JSON_OBJECT & deps.object_len() > 0)
        {
            print("\n  Dependencies:\n\0");
            k = 0;
            while (k < deps.object_len())
            {
                dname = deps.object_key_at(k);
                dver  = (JSONNode*)deps.object_val_at(k);
                print("    \0"); print(dname);
                print("  \0");
                if ((u64)dver != 0 & dver.type == JSON_STRING) { print(dver.s); };
                print("\n\0");
                k = k + 1;
            };
        }
        else
        {
            print("\n  Dependencies: none\0");
        };

        print("\n  Status:       \0");
        if (is_stdlib_package(stdlib_pkgs, @name[0]))      { print("installed [stdlib]\0"); }
        elif (installed_has(installed_root, @name[0]))     { print("installed [remote]\0"); }
        else                                               { print("not installed\0"); };
        print("\n\0");

        i = i + 1;
    };
    return;
};


def cmd_addsource(byte* url, byte* sources_path, JSONNode* sources_root, Arena* arena) -> void
{
    size_t    k;
    JSONNode* entry;
    byte*     old_data;
    int       old_len, last_bracket, j;
    bool      has_entries;
    byte[FPM_MAX_URL] new_sources;

    if ((u64)sources_root != 0 & sources_root.type == JSON_ARRAY)
    {
        k = 0;
        while (k < sources_root.array_len())
        {
            entry = (JSONNode*)sources_root.array_get(k);
            if ((u64)entry != 0 & entry.type == JSON_STRING)
            {
                if (strcmp(entry.s, url) == 0)
                {
                    print("  Already added: \0"); print(url); print("\n\0");
                    return;
                };
            };
            k = k + 1;
        };
    };

    print("  Fetching \0"); print(url); print("...\n\0");

    old_len = read_file_alloc(sources_path, @old_data);

    if (old_len <= 0)
    {
        snprintf(@new_sources[0], FPM_MAX_URL, "[\"%s\"]\0", url);
    }
    else
    {
        last_bracket = old_len - 1;
        while (last_bracket > 0 & (char)old_data[last_bracket] != ']')
        {
            last_bracket = last_bracket - 1;
        };

        has_entries = false;
        j = 0;
        while (j < last_bracket)
        {
            if (old_data[j] == (byte)'"') { has_entries = true; break; };
            j = j + 1;
        };

        if (has_entries)
        {
            snprintf(@new_sources[0], FPM_MAX_URL, "%.*s,\"%s\"]\0",
                     last_bracket, old_data, url);
        }
        else
        {
            snprintf(@new_sources[0], FPM_MAX_URL, "[\"%s\"]\0", url);
        };
    };

    if (old_len > 0) { ffree((u64)old_data); };

    write_file_path(sources_path, @new_sources[0], strlen(@new_sources[0]));
    print("  Added source: \0"); print(url); print("\n\0");
    return;
};


def cmd_removesource(byte* url, byte* sources_path) -> void
{
    print("  Removing source: \0"); print(url); print("\n\0");
    print("  (Edit \0"); print(sources_path); print(" to remove manually)\n\0");
    return;
};


def cmd_sources(JSONNode* sources_root) -> void
{
    size_t    k;
    JSONNode* entry;
    byte[32]  nbuf;

    if ((u64)sources_root == 0)
    {
        print("No sources configured.\n\0");
        print("  Add one with: fpm addsource <url>\n\0");
        return;
    };
    if (sources_root.type != JSON_ARRAY | sources_root.array_len() == 0)
    {
        print("No sources configured.\n\0");
        print("  Add one with: fpm addsource <url>\n\0");
        return;
    };

    strings::i32str((i32)sources_root.array_len(), @nbuf[0]);
    print("Configured sources (\0"); print(@nbuf[0]); print("):\n\n\0");

    k = 0;
    while (k < sources_root.array_len())
    {
        entry = (JSONNode*)sources_root.array_get(k);
        if ((u64)entry != 0 & entry.type == JSON_STRING)
        {
            print("  \0"); print(entry.s); print("\n\0");
        };
        k = k + 1;
    };
    return;
};


def print_usage() -> void
{
    print("fpm - Flux Package Manager\n\n\0");
    print("Usage:\n\0");
    print("  fpm install <package>       Install a specific package\n\0");
    print("  fpm install --stdlib        Install the full standard library\n\0");
    print("  fpm install --all           Install all available packages\n\0");
    print("  fpm remove  <package>       Remove an installed package\n\0");
    print("  fpm update  [package]       Update packages (all if none specified)\n\0");
    print("  fpm list                    List installed packages\n\0");
    print("  fpm list --available        List all available packages\n\0");
    print("  fpm info    <package>       Show package details\n\0");
    print("  fpm addsource <url>         Add a package source\n\0");
    print("  fpm removesource <url>      Remove a package source\n\0");
    print("  fpm sources                 List configured sources\n\0");
    return;
};

// ─── Entry point ──────────────────────────────────────────────────────────────

def main(int argc, byte** argv) -> int
{
    byte[FPM_MAX_PATH] installed_path, sources_path, stdlib_json_path;
    byte[FPM_MAX_PATH] remote_url;
    Arena              arena;
    JSONNode*          installed_root;
    JSONNode*          sources_root;
    JSONNode*          stdlib_root;
    JSONNode*          stdlib_pkgs;
    JSONNode*          remote_stdlib_root;
    JSONNode*          remote_stdlib_pkgs;
    JSONNode*          all_pkgs;
    byte*              cmd;
    bool               show_available;

    if (argc < 2)
    {
        print_usage();
        return 0;
    };

    // Init
    arena_init(@arena, 1024 * 1024);  // 1 MB arena for JSON parsing

    ensure_dirs();
    get_installed_path(@installed_path[0]);
    get_sources_path(@sources_path[0]);
    get_stdlib_json_path(@stdlib_json_path[0]);

    // Load stdlib package.json
    stdlib_root = parse_json_file(@stdlib_json_path[0], @arena);
    stdlib_pkgs = (JSONNode*)0;
    if ((u64)stdlib_root != 0)
    {
        stdlib_pkgs = (JSONNode*)stdlib_root.object_get("packages\0");
    };

    // Load installed.json
    installed_root = parse_json_file(@installed_path[0], @arena);

    // Load sources.json
    sources_root = parse_json_file(@sources_path[0], @arena);

    // all_pkgs starts as stdlib_pkgs — sources could be merged here later
    all_pkgs = stdlib_pkgs;

    cmd = argv[1];

    if (strcmp(cmd, "install\0") == 0)
    {
        cmd_install(argv, argc, 2, stdlib_pkgs, all_pkgs,
                    installed_root, @installed_path[0], @arena);
    }
    elif (strcmp(cmd, "remove\0") == 0)
    {
        cmd_remove(argv, argc, 2, stdlib_pkgs, @installed_path[0]);
    }
    elif (strcmp(cmd, "update\0") == 0)
    {
        // Fetch remote stdlib package.json
        print("  Fetching remote stdlib package.json...\n\0");
        snprintf(@remote_url[0], FPM_MAX_PATH,
                 "/kvthweatt/FluxLang/main/src/stdlib/package.json\0");
        remote_stdlib_root = fetch_json_url(FPM_HOST, @remote_url[0], @arena);
        remote_stdlib_pkgs = (JSONNode*)0;
        if ((u64)remote_stdlib_root != 0)
        {
            remote_stdlib_pkgs = (JSONNode*)remote_stdlib_root.object_get("packages\0");
        };

        cmd_update(argv, argc, 2, stdlib_pkgs, remote_stdlib_pkgs,
                   installed_root, @installed_path[0], @arena);
    }
    elif (strcmp(cmd, "list\0") == 0)
    {
        show_available = false;
        if (argc >= 3) { show_available = strcmp(argv[2], "--available\0") == 0; };
        cmd_list(show_available, all_pkgs, installed_root, stdlib_pkgs);
    }
    elif (strcmp(cmd, "info\0") == 0)
    {
        cmd_info(argv, argc, 2, all_pkgs, installed_root, stdlib_pkgs);
    }
    elif (strcmp(cmd, "addsource\0") == 0)
    {
        if (argc < 3) { print("Usage: fpm addsource <url>\n\0"); return 1; };
        cmd_addsource(argv[2], @sources_path[0], sources_root, @arena);
    }
    elif (strcmp(cmd, "removesource\0") == 0)
    {
        if (argc < 3) { print("Usage: fpm removesource <url>\n\0"); return 1; };
        cmd_removesource(argv[2], @sources_path[0]);
    }
    elif (strcmp(cmd, "sources\0") == 0)
    {
        cmd_sources(sources_root);
    }
    else
    {
        print("Unknown command: \0"); print(cmd); print("\n\n\0");
        print_usage();
        return 1;
    };

    arena_destroy(@arena);
    return 0;
};
