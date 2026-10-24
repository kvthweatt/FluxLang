// Author: Karac V. Thweatt

// filesystem.fx - Paths, files, directories and child processes for Flux.
//
//   Paths       pure string functions, no allocation, work on both '/' and '\' separators
//   Files       exists, size, create/remove/rename, whole-file read/write, copy
//   Directories mkdir, mkdir_all, rmdir, cwd, chdir, temp dir, DirIter
//   Processes   spawn / wait / run, with optional output capture
//   Environment env_get / env_set
//
// Conventions
//   * Every function taking `out, cap` writes a null-terminated result and returns
//     its length, or -1 when `cap` is too small (nothing useful is written).
//   * Boolean-returning functions report failure with false; no exceptions are used.
//   * Functions that allocate (fs_read_all, proc_capture) -> memory from
//     fmalloc; release it with ffree.
//
// Platforms: Linux (libc) and Windows (kernel32). The Windows branch has not been
// exercised by the test suite; the Linux branch has.
//
// Dependencies: standard::types, standard::memory

#ifnFLUX_STANDARD_TYPES
#import <types.fx>;
#endif;

#ifnFLUX_STANDARD_MEMORY
#import <memory.fx>;
#endif;

#ifnFLUX_STANDARD_FILESYSTEM
#FLUX_STANDARD_FILESYSTEM 1;

#if__LINUX__
extern
{
    !!
        stat(byte*, void*)              -> int,
        mkdir(byte*, u32)               -> int,
        rmdir(byte*)                    -> int,
        unlink(byte*)                   -> int,
        rename(byte*, byte*)            -> int,
        getcwd(byte*, size_t)           -> byte*,
        chdir(byte*)                    -> int,
        opendir(byte*)                  -> void*,
        readdir(void*)                  -> void*,
        closedir(void*)                 -> int,
        getenv(byte*)                   -> byte*,
        setenv(byte*, byte*, int)       -> int,
        unsetenv(byte*)                 -> int,
        fork()                          -> int,
        execvp(byte*, byte**)           -> int,
        waitpid(int, int*, int)         -> int,
        pipe(int*)                      -> int,
        dup2(int, int)                  -> int,
        read(int, void*, size_t)        -> i64,
        close(int)                      -> int,
        _exit(int)                      -> void,
        fopen(byte*, byte*)             -> void*,
        fclose(void*)                   -> int,
        fread(void*, ulong, ulong, void*) -> ulong,
        fwrite(void*, ulong, ulong, void*) -> ulong,
        fseek(void*, long, int)         -> int,
        ftell(void*)                    -> long;
};
#endif;

#if__WINDOWS__
extern
{
    !!
        GetFileAttributesA(byte*)                   -> u32,
        CreateDirectoryA(byte*, void*)              -> i32,
        RemoveDirectoryA(byte*)                     -> i32,
        DeleteFileA(byte*)                          -> i32,
        MoveFileExA(byte*, byte*, u32)              -> i32,
        GetCurrentDirectoryA(u32, byte*)            -> u32,
        SetCurrentDirectoryA(byte*)                 -> i32,
        GetTempPathA(u32, byte*)                    -> u32,
        FindFirstFileA(byte*, void*)                -> i64,
        FindNextFileA(i64, void*)                   -> i32,
        FindClose(i64)                              -> i32,
        GetEnvironmentVariableA(byte*, byte*, u32)  -> u32,
        SetEnvironmentVariableA(byte*, byte*)       -> i32,
        CreateProcessA(byte*, byte*, void*, void*, i32, u32, void*, byte*, void*, void*) -> i32,
        WaitForSingleObject(i64, u32)               -> u32,
        GetExitCodeProcess(i64, u32*)               -> i32,
        CloseHandle(i64)                            -> i32,
        CreatePipe(i64*, i64*, void*, u32)          -> i32,
        SetHandleInformation(i64, u32, u32)         -> i32,
        ReadFile(i64, void*, u32, u32*, void*)      -> i32,
        GetStdHandle(u32)                           -> i64,
        fopen(byte*, byte*)                         -> void*,
        fclose(void*)                               -> int,
        fread(void*, ulong, ulong, void*)           -> ulong,
        fwrite(void*, ulong, ulong, void*)          -> ulong,
        fseek(void*, long, int)                     -> int,
        ftell(void*)                                -> long;
};
#endif;

namespace standard
{
    namespace fs
    {
        // ====================================================================
        // Paths
        // ====================================================================

        path_is_sep(byte c) -> bool
        {
            -> c == (byte)'/' | c == (byte)'\\';
        };

        _cstrlen(byte* s) -> int
        {
            int n;
            while (s[n] != (byte)0) { n++; };
            -> n;
        };

        // True for "/x", "\x", and "C:\x" / "C:/x".
        path_is_absolute(byte* p) -> bool
        {
            if (p[0] == (byte)0) { -> false; };
            if (path_is_sep(p[0])) { -> true; };
            if (p[1] == (byte)':' & path_is_sep(p[2])) { -> true; };
            -> false;
        };

        // Joins a and b with a single '/'. An absolute b replaces a.
        path_join(byte* a, byte* b, byte* out, int cap) -> int
        {
            int la = _cstrlen(a), lb = _cstrlen(b);
            int n, i;
            if (la == 0 | path_is_absolute(b))
            {
                if (lb + 1 > cap) { -> -1; };
                while (i < lb) { out[i] = b[i]; i++; };
                out[lb] = (byte)0;
                -> lb;
            };
            if (lb == 0)
            {
                if (la + 1 > cap) { -> -1; };
                while (i < la) { out[i] = a[i]; i++; };
                out[la] = (byte)0;
                -> la;
            };
            bool need_sep = !path_is_sep(a[la - 1]);
            n = la + lb + (need_sep ? 1 : 0);
            if (n + 1 > cap) { -> -1; };
            while (i < la) { out[i] = a[i]; i++; };
            int o = la;
            if (need_sep) { out[o] = (byte)'/'; o++; };
            i = 0;
            while (i < lb) { out[o + i] = b[i]; i++; };
            out[n] = (byte)0;
            -> n;
        };

        // Index just past the last separator (start of the final component).
        _last_component(byte* p, int len) -> int
        {
            int i = len;
            // Ignore trailing separators
            while (i > 0 & path_is_sep(p[i - 1])) { i--; };
            while (i > 0 & !path_is_sep(p[i - 1])) { i--; };
            -> i;
        };

        // Final component: "a/b/c.txt" -> "c.txt". Trailing separators are ignored.
        path_basename(byte* p, byte* out, int cap) -> int
        {
            int len = _cstrlen(p);
            int start = _last_component(p, len);
            int end = len;
            while (end > start & path_is_sep(p[end - 1])) { end--; };
            int n = end - start;
            if (n + 1 > cap) { -> -1; };
            int i;
            while (i < n) { out[i] = p[start + i]; i++; };
            out[n] = (byte)0;
            -> n;
        };

        // Everything before the final component, without its trailing separator.
        // "a/b/c" -> "a/b", "c" -> ".", "/c" -> "/".
        path_dirname(byte* p, byte* out, int cap) -> int
        {
            int len = _cstrlen(p);
            int start = _last_component(p, len);
            int end = start;
            int i;
            while (end > 1 & path_is_sep(p[end - 1])) { end--; };
            if (end == 0)
            {
                if (2 > cap) { -> -1; };
                out[0] = (byte)'.';
                out[1] = (byte)0;
                -> 1;
            };
            if (end + 1 > cap) { -> -1; };
            while (i < end) { out[i] = p[i]; i++; };
            out[end] = (byte)0;
            -> end;
        };

        // Pointer to the '.' of the extension of the final component, or null.
        // "a/b.tar.gz" -> ".gz"; ".bashrc" and "noext" have none.
        path_ext(byte* p) -> byte*
        {
            int len = _cstrlen(p);
            int start = _last_component(p, len);
            int i = len;
            while (i > start + 1)
            {
                if (p[i - 1] == (byte)'.') { -> p + (i - 1); };
                i--;
            };
            -> (byte*)STDLIB_GVP;
        };

        // Collapses repeated separators and resolves "." and ".." components.
        // Output separators are '/'. A leading root ("/", "C:/") is kept.
        path_normalize(byte* p, byte* out, int cap) -> int
        {
            int len = _cstrlen(p);
            int i, o, root;
            bool abs = path_is_absolute(p);
            if (len + 2 > cap) { -> -1; };
            if (p[1] == (byte)':' & len >= 2)
            {
                out[0] = p[0];
                out[1] = (byte)':';
                o = 2;
                i = 2;
            };
            if (abs)
            {
                out[o] = (byte)'/';
                o++;
                while (i < len & path_is_sep(p[i])) { i++; };
            };
            root = o;
            int comp_start, comp_len, k;
            while (i < len)
            {
                comp_start = i;
                while (i < len & !path_is_sep(p[i])) { i++; };
                comp_len = i - comp_start;
                while (i < len & path_is_sep(p[i])) { i++; };
                if (comp_len == 0) { continue; };
                if (comp_len == 1 & p[comp_start] == (byte)'.') { continue; };
                if (comp_len == 2 & p[comp_start] == (byte)'.' & p[comp_start + 1] == (byte)'.')
                {
                    // Pop the previous component unless it is ".." or we are at the root
                    int q = o;
                    if (q > root)
                    {
                        if (out[q - 1] == (byte)'/') { q--; };
                        while (q > root & out[q - 1] != (byte)'/') { q--; };
                        bool prev_dotdot = (o - q >= 2) & out[q] == (byte)'.' & out[q + 1] == (byte)'.' &
                                           (q + 2 == o | out[q + 2] == (byte)'/');
                        if (!prev_dotdot) { o = q; continue; };
                    };
                    if (abs) { continue; };
                };
                if (o > root & out[o - 1] != (byte)'/') { out[o] = (byte)'/'; o++; };
                k = 0;
                while (k < comp_len) { out[o + k] = p[comp_start + k]; k++; };
                o = o + comp_len;
            };
            if (o > root & out[o - 1] == (byte)'/') { o--; };
            if (o == 0) { out[0] = (byte)'.'; o = 1; };
            out[o] = (byte)0;
            -> o;
        };

        // ====================================================================
        // File metadata
        // ====================================================================

#if__LINUX__
        // struct stat field offsets (glibc, 64-bit)
#if__ARCH_ARM64__
        #FS_ST_MODE_OFF 16;
#endif;
#ifn__ARCH_ARM64__
        #FS_ST_MODE_OFF 24;
#endif;
        #FS_ST_SIZE_OFF 48;
        #FS_ST_BUF 256;

        // Fills buf (FS_ST_BUF bytes). False when the path does not exist.
        _stat(byte* p, byte* buf) -> bool
        {
            -> stat(p, (void*)buf) == 0;
        };

        _mode(byte* buf) -> u32
        {
            -> *(u32*)(buf + FS_ST_MODE_OFF);
        };

        fs_exists(byte* p) -> bool
        {
            byte[FS_ST_BUF] st;
            -> _stat(p, @st[0]);
        };

        fs_is_dir(byte* p) -> bool
        {
            byte[FS_ST_BUF] st;
            if (!_stat(p, @st[0])) { -> false; };
            -> (_mode(@st[0]) `& (u32)0xF000) == (u32)0x4000;
        };

        fs_is_file(byte* p) -> bool
        {
            byte[FS_ST_BUF] st;
            if (!_stat(p, @st[0])) { -> false; };
            -> (_mode(@st[0]) `& (u32)0xF000) == (u32)0x8000;
        };

        // Size in bytes, or -1 when the path does not exist.
        fs_size(byte* p) -> i64
        {
            byte[FS_ST_BUF] st;
            if (!_stat(p, @st[0])) { -> (i64)-1; };
            -> *(i64*)(@st[0] + FS_ST_SIZE_OFF);
        };

        fs_mkdir(byte* p) -> bool
        {
            -> mkdir(p, (u32)0x1FD) == 0;
        };

        fs_rmdir(byte* p) -> bool
        {
            -> rmdir(p) == 0;
        };

        fs_remove(byte* p) -> bool
        {
            -> unlink(p) == 0;
        };

        fs_rename(byte* src, byte* dst) -> bool
        {
            -> rename(src, dst) == 0;
        };

        fs_getcwd(byte* out, int cap) -> int
        {
            if (getcwd(out, (size_t)cap) == (byte*)STDLIB_GVP) { -> -1; };
            -> _cstrlen(out);
        };

        fs_chdir(byte* p) -> bool
        {
            -> chdir(p) == 0;
        };

        fs_temp_dir(byte* out, int cap) -> int
        {
            byte* t = getenv("TMPDIR\0");
            if (t == (byte*)STDLIB_GVP) { t = "/tmp\0"; };
            int n = _cstrlen(t);
            if (n + 1 > cap) { -> -1; };
            int i;
            while (i <= n) { out[i] = t[i]; i++; };
            -> n;
        };

        env_get(byte* name) -> byte*
        {
            -> getenv(name);
        };

        env_set(byte* name, byte* value) -> bool
        {
            -> setenv(name, value, 1) == 0;
        };

        env_unset(byte* name) -> bool
        {
            -> unsetenv(name) == 0;
        };
#endif;

#if__WINDOWS__
        #FS_INVALID_ATTR 0xFFFFFFFF;

        fs_exists(byte* p) -> bool
        {
            -> GetFileAttributesA(p) != (u32)FS_INVALID_ATTR;
        };

        fs_is_dir(byte* p) -> bool
        {
            u32 a = GetFileAttributesA(p);
            if (a == (u32)FS_INVALID_ATTR) { -> false; };
            -> (a `& (u32)0x10) != (u32)0;
        };

        fs_is_file(byte* p) -> bool
        {
            u32 a = GetFileAttributesA(p);
            if (a == (u32)FS_INVALID_ATTR) { -> false; };
            -> (a `& (u32)0x10) == (u32)0;
        };

        fs_size(byte* p) -> i64
        {
            byte[320] fd;
            i64 h = FindFirstFileA(p, (void*)@fd[0]);
            if (h == (i64)-1) { -> (i64)-1; };
            FindClose(h);
            u32 hi = *(u32*)(@fd[0] + 28);
            u32 lo = *(u32*)(@fd[0] + 32);
            -> ((i64)hi << 32) | (i64)lo;
        };

        fs_mkdir(byte* p) -> bool
        {
            -> CreateDirectoryA(p, (void*)STDLIB_GVP) != 0;
        };

        fs_rmdir(byte* p) -> bool
        {
            -> RemoveDirectoryA(p) != 0;
        };

        fs_remove(byte* p) -> bool
        {
            -> DeleteFileA(p) != 0;
        };

        fs_rename(byte* src, byte* dst) -> bool
        {
            // MOVEFILE_REPLACE_EXISTING, matching rename(2)
            -> MoveFileExA(src, dst, (u32)1) != 0;
        };

        fs_getcwd(byte* out, int cap) -> int
        {
            u32 n = GetCurrentDirectoryA((u32)cap, out);
            if (n == (u32)0 | (int)n >= cap) { -> -1; };
            -> (int)n;
        };

        fs_chdir(byte* p) -> bool
        {
            -> SetCurrentDirectoryA(p) != 0;
        };

        fs_temp_dir(byte* out, int cap) -> int
        {
            u32 n = GetTempPathA((u32)cap, out);
            if (n == (u32)0 | (int)n >= cap) { -> -1; };
            -> (int)n;
        };

        // Windows has no pointer-returning getenv in kernel32; the value is copied
        // into a process-lifetime buffer (4096 bytes, overwritten by the next call).
        env_get(byte* name) -> byte*
        {
            local byte[4096] buf;
            u32 n = GetEnvironmentVariableA(name, @buf[0], (u32)4096);
            if (n == (u32)0 | n >= (u32)4096) { -> (byte*)STDLIB_GVP; };
            -> @buf[0];
        };

        env_set(byte* name, byte* value) -> bool
        {
            -> SetEnvironmentVariableA(name, value) != 0;
        };

        env_unset(byte* name) -> bool
        {
            -> SetEnvironmentVariableA(name, (byte*)STDLIB_GVP) != 0;
        };
#endif;

        // Creates p and any missing parents. True when p exists as a directory afterwards.
        fs_mkdir_all(byte* p) -> bool
        {
            int len = _cstrlen(p);
            if (len + 1 > 1024) { -> false; };
            byte[1024] tmp;
            int i;
            while (i < len) { tmp[i] = p[i]; i++; };
            tmp[len] = (byte)0;
            i = 1;
            while (i < len)
            {
                if (path_is_sep(tmp[i]))
                {
                    byte saved = tmp[i];
                    tmp[i] = (byte)0;
                    if (!fs_is_dir(@tmp[0])) { fs_mkdir(@tmp[0]); };
                    tmp[i] = saved;
                };
                i++;
            };
            if (!fs_is_dir(@tmp[0])) { fs_mkdir(@tmp[0]); };
            -> fs_is_dir(@tmp[0]);
        };

        // ====================================================================
        // Whole-file helpers
        // ====================================================================

        // Reads the entire file into a new buffer (null terminated, so text is safe to
        // print). *out_len receives the byte count. Returns null on failure; free with ffree.
        fs_read_all(byte* p, i64* out_len) -> byte*
        {
            void* f = fopen(p, "rb\0");
            if (f == (void*)STDLIB_GVP) { -> (byte*)STDLIB_GVP; };
            fseek(f, (long)0, 2);
            long sz = ftell(f);
            fseek(f, (long)0, 0);
            if (sz < (long)0) { fclose(f); -> (byte*)STDLIB_GVP; };
            byte* buf = (byte*)fmalloc((size_t)sz + 1);
            if (buf == (byte*)STDLIB_GVP) { fclose(f); -> (byte*)STDLIB_GVP; };
            ulong got = fread((void*)buf, (ulong)1, (ulong)sz, f);
            fclose(f);
            buf[(size_t)got] = (byte)0;
            *out_len = (i64)got;
            -> buf;
        };

        fs_write_all(byte* p, byte* buf_in, i64 len) -> bool
        {
            void* f = fopen(p, "wb\0");
            if (f == (void*)STDLIB_GVP) { -> false; };
            ulong put = fwrite((void*)buf_in, (ulong)1, (ulong)len, f);
            fclose(f);
            -> (i64)put == len;
        };

        fs_append(byte* p, byte* buf_in, i64 len) -> bool
        {
            void* f = fopen(p, "ab\0");
            if (f == (void*)STDLIB_GVP) { -> false; };
            ulong put = fwrite((void*)buf_in, (ulong)1, (ulong)len, f);
            fclose(f);
            -> (i64)put == len;
        };

        fs_copy(byte* src, byte* dst) -> bool
        {
            i64 n;
            byte* buf = fs_read_all(src, @n);
            if (buf == (byte*)STDLIB_GVP) { -> false; };
            bool ok = fs_write_all(dst, buf, n);
            ffree(buf);
            -> ok;
        };

        // ====================================================================
        // Directory iteration
        // ====================================================================

        // Usage:
        //   DirIter it("some/dir\0");
        //   byte[256] name; bool is_dir;
        //   while (it.next(@name[0], 256, @is_dir)) { ... }
        // "." and ".." are skipped. Entry order is the OS order.
        trait BaseDirIterTraits
        {
            valid() -> bool;
        };

        BaseDirIterTraits
        object DirIter
        {
            void* handle;
            bool  first;
            byte[320] find;

            __init(byte* path) -> this
            {
                this.handle = (void*)STDLIB_GVP;
                this.first  = true;
#if__LINUX__
                this.handle = opendir(path);
#endif;
#if__WINDOWS__
                byte[1024] pat;
                int n = _cstrlen(path);
                if (n + 3 <= 1024)
                {
                    int i;
                    while (i < n) { pat[i] = path[i]; i++; };
                    if (n > 0 & !path_is_sep(path[n - 1])) { pat[n] = (byte)'\\'; n++; };
                    pat[n] = (byte)'*';
                    pat[n + 1] = (byte)0;
                    i64 h = FindFirstFileA(@pat[0], (void*)@this.find[0]);
                    if (h != (i64)-1) { this.handle = (void*)h; };
                };
#endif;
                -> this;
            };

            __exit() -> void
            {
                if (this.handle != (void*)STDLIB_GVP)
                {
#if__LINUX__
                    closedir(this.handle);
#endif;
#if__WINDOWS__
                    FindClose((i64)this.handle);
#endif;
                    this.handle = (void*)STDLIB_GVP;
                };
                ->;
            };

            __expr() -> DirIter*
            {
                -> this;
            };

            valid() -> bool
            {
                -> this.handle != (void*)STDLIB_GVP;
            };

            // Next entry name into out (null terminated). False when finished or on error.
            next(byte* out, int cap, bool* is_dir) -> bool
            {
                if (this.handle == (void*)STDLIB_GVP) { -> false; };
                byte* name;
                while (true)
                {
#if__LINUX__
                    void* ent = readdir(this.handle);
                    if (ent == (void*)STDLIB_GVP) { -> false; };
                    name = (byte*)ent + 19;
                    *is_dir = *((byte*)ent + 18) == (byte)4;
#endif;
#if__WINDOWS__
                    if (!this.first)
                    {
                        if (FindNextFileA((i64)this.handle, (void*)@this.find[0]) == 0) { -> false; };
                    };
                    this.first = false;
                    name = @this.find[0] + 44;
                    *is_dir = (*(u32*)@this.find[0] `& (u32)0x10) != (u32)0;
#endif;
                    if (name[0] == (byte)'.' & (name[1] == (byte)0 | (name[1] == (byte)'.' & name[2] == (byte)0)))
                    {
                        continue;
                    };
                    break;
                };
                int n = _cstrlen(name);
                if (n + 1 > cap) { -> false; };
                int i;
                while (i <= n) { out[i] = name[i]; i++; };
                -> true;
            };
        };

        // Recursively removes a directory tree. True on success.
        fs_remove_all(byte* p) -> bool
        {
            if (!fs_is_dir(p)) { -> fs_remove(p); };
            DirIter it(p);
            byte[512] name;
            byte[1024] child;
            bool is_dir, ok = true;
            while (it.next(@name[0], 512, @is_dir))
            {
                if (path_join(p, @name[0], @child[0], 1024) < 0) { ok = false; continue; };
                if (is_dir) { if (!fs_remove_all(@child[0])) { ok = false; }; }
                else { if (!fs_remove(@child[0])) { ok = false; }; };
            };
            -> fs_rmdir(p) & ok;
        };

        // ====================================================================
        // Processes
        // ====================================================================

        // argv is a null-terminated array of strings; argv[0] is the program (searched on PATH).

#if__LINUX__
        // Starts a child. Returns its pid, or -1.
        proc_spawn(byte** argv) -> i64
        {
            int pid = fork();
            if (pid < 0) { -> (i64)-1; };
            if (pid == 0)
            {
                execvp(argv[0], argv);
                _exit(127);
            };
            -> (i64)pid;
        };

        // Waits for the child and returns its exit code (128 + signal when it was killed), or -1.
        proc_wait(i64 pid) -> int
        {
            int status;
            if (waitpid((int)pid, @status, 0) < 0) { -> -1; };
            int sig = status `& 0x7F;
            if (sig == 0) { -> (status >> 8) `& 0xFF; };
            -> 128 + sig;
        };

        // Runs argv, waits, and returns the exit code (-1 if it could not be started).
        proc_run(byte** argv) -> int
        {
            i64 pid = proc_spawn(argv);
            if (pid < (i64)0) { -> -1; };
            -> proc_wait(pid);
        };

        // Runs argv with stdout redirected into a new buffer (null terminated).
        // *out_len receives the byte count and *exit_code the exit status.
        // Returns null when the process could not be started; free the buffer with ffree.
        proc_capture(byte** argv, i64* out_len, int* exit_code) -> byte*
        {
            int[2] fds;
            if (pipe(@fds[0]) != 0) { -> (byte*)STDLIB_GVP; };
            int pid = fork();
            if (pid < 0)
            {
                close(fds[0]);
                close(fds[1]);
                -> (byte*)STDLIB_GVP;
            };
            if (pid == 0)
            {
                close(fds[0]);
                dup2(fds[1], 1);
                close(fds[1]);
                execvp(argv[0], argv);
                _exit(127);
            };
            close(fds[1]);
            i64 cap = (i64)4096, len = (i64)0, got;
            byte* buf = (byte*)fmalloc((size_t)cap);
            while (true)
            {
                if (len + (i64)1024 + (i64)1 > cap)
                {
                    cap = cap * (i64)2;
                    byte* nb = (byte*)fmalloc((size_t)cap);
                    i64 k;
                    while (k < len) { nb[(size_t)k] = buf[(size_t)k]; k++; };
                    ffree(buf);
                    buf = nb;
                };
                got = read(fds[0], (void*)(buf + (size_t)len), (size_t)1024);
                if (got <= (i64)0) { break; };
                len = len + got;
            };
            close(fds[0]);
            buf[(size_t)len] = (byte)0;
            *out_len = len;
            *exit_code = proc_wait((i64)pid);
            -> buf;
        };
#endif;

#if__WINDOWS__
        // Builds a command line from argv, quoting arguments that contain spaces or quotes.
        _build_cmdline(byte** argv, byte* out, int cap) -> int
        {
            int o, a, i;
            bool quote;
            while (argv[a] != (byte*)STDLIB_GVP)
            {
                byte* s = argv[a];
                quote = s[0] == (byte)0;
                i = 0;
                while (s[i] != (byte)0)
                {
                    if (s[i] == (byte)' ' | s[i] == (byte)'\t' | s[i] == (byte)'"') { quote = true; };
                    i++;
                };
                if (o + _cstrlen(s) * 2 + 4 > cap) { -> -1; };
                if (a > 0) { out[o++] = (byte)' '; };
                if (quote) { out[o++] = (byte)'"'; };
                i = 0;
                while (s[i] != (byte)0)
                {
                    if (s[i] == (byte)'"') { out[o++] = (byte)'\\'; };
                    out[o] = s[i];
                    o++;
                    i++;
                };
                if (quote) { out[o] = (byte)'"'; o++; };
                a++;
            };
            out[o] = (byte)0;
            -> o;
        };

        // Starts a child. Returns its process handle, or -1. Pass the handle to proc_wait.
        proc_spawn(byte** argv) -> i64
        {
            byte[8192] cmd;
            byte[104] si;
            byte[24] pi;
            if (_build_cmdline(argv, @cmd[0], 8192) < 0) { -> (i64)-1; };
            int i;
            while (i < 104) { si[i] = (byte)0; i++; };
            *(u32*)@si[0] = (u32)104;
            if (CreateProcessA((byte*)STDLIB_GVP, @cmd[0], (void*)STDLIB_GVP, (void*)STDLIB_GVP, 0, (u32)0,
                               (void*)STDLIB_GVP, (byte*)STDLIB_GVP, (void*)@si[0], (void*)@pi[0]) == 0)
            {
                -> (i64)-1;
            };
            CloseHandle(*(i64*)(@pi[0] + 8));
            -> *(i64*)@pi[0];
        };

        proc_wait(i64 handle) -> int
        {
            u32 code;
            WaitForSingleObject(handle, (u32)0xFFFFFFFF);
            if (GetExitCodeProcess(handle, @code) == 0) { CloseHandle(handle); -> -1; };
            CloseHandle(handle);
            -> (int)code;
        };

        proc_run(byte** argv) -> int
        {
            i64 h = proc_spawn(argv);
            if (h < (i64)0) { -> -1; };
            -> proc_wait(h);
        };
        // Runs argv with stdout redirected into a new buffer (null terminated).
        // *out_len receives the byte count and *exit_code the exit status.
        // Returns null when the process could not be started; free the buffer with ffree.
        proc_capture(byte** argv, i64* out_len, int* exit_code) -> byte*
        {
            byte[8192] cmd;
            byte[104] si;
            byte[24] pi, sa;
            i64 rd, wr;
            int i;
            if (_build_cmdline(argv, @cmd[0], 8192) < 0) { -> (byte*)STDLIB_GVP; };
            while (i < 24) { sa[i] = (byte)0; i++; };
            *(u32*)@sa[0] = (u32)24;
            *(i32*)(@sa[0] + 16) = 1;
            if (CreatePipe(@rd, @wr, (void*)@sa[0], (u32)0) == 0) { -> (byte*)STDLIB_GVP; };
            SetHandleInformation(rd, (u32)1, (u32)0);
            i = 0;
            while (i < 104) { si[i] = (byte)0; i++; };
            *(u32*)@si[0] = (u32)104;
            *(u32*)(@si[0] + 60) = (u32)0x100;
            *(i64*)(@si[0] + 80) = GetStdHandle((u32)0xFFFFFFF6);
            *(i64*)(@si[0] + 88) = wr;
            *(i64*)(@si[0] + 96) = GetStdHandle((u32)0xFFFFFFF4);
            if (CreateProcessA((byte*)STDLIB_GVP, @cmd[0], (void*)STDLIB_GVP, (void*)STDLIB_GVP, 1, (u32)0,
                               (void*)STDLIB_GVP, (byte*)STDLIB_GVP, (void*)@si[0], (void*)@pi[0]) == 0)
            {
                CloseHandle(rd);
                CloseHandle(wr);
                -> (byte*)STDLIB_GVP;
            };
            CloseHandle(*(i64*)(@pi[0] + 8));
            CloseHandle(wr);
            i64 cap = (i64)4096, len = (i64)0;
            u32 got;
            byte* buf = (byte*)fmalloc((size_t)cap);
            while (true)
            {
                if (len + (i64)1024 + (i64)1 > cap)
                {
                    cap = cap * (i64)2;
                    byte* nb = (byte*)fmalloc((size_t)cap);
                    i64 k;
                    while (k < len) { nb[(size_t)k] = buf[(size_t)k]; k++; };
                    ffree(buf);
                    buf = nb;
                };
                if (ReadFile(rd, (void*)(buf + (size_t)len), (u32)1024, @got, (void*)STDLIB_GVP) == 0) { break; };
                if (got == (u32)0) { break; };
                len = len + (i64)got;
            };
            CloseHandle(rd);
            buf[(size_t)len] = (byte)0;
            *out_len = len;
            *exit_code = proc_wait(*(i64*)@pi[0]);
            -> buf;
        };
#endif;
    };
};

#endif;
