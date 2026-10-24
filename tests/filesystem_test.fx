#import <standard.fx>;
#import <filesystem.fx>;
using standard::io::console;
using standard::fs;

def main() -> int
{
    byte[512] a, b;
    int n;
    n = path_join("usr/local\0", "bin\0", @a[0], 512);
    println(f"join {n} {a}");
    n = path_join("usr/\0", "/etc\0", @a[0], 512);
    println(f"join abs {n} {a}");
    path_basename("a/b/c.txt\0", @a[0], 512);
    path_dirname("a/b/c.txt\0", @b[0], 512);
    println(f"base {a} dir {b}");
    path_dirname("c\0", @b[0], 512);
    path_basename("dir/sub/\0", @a[0], 512);
    println(f"dir-of-c {b} base-of-trailing {a}");
    byte* e = path_ext("x/y.tar.gz\0");
    println(f"ext {e}");
    path_normalize("/a/./b//c/../d/\0", @a[0], 512);
    println(f"norm {a}");
    path_normalize("../x/../../y\0", @a[0], 512);
    println(f"norm2 {a}");
    path_normalize("a/..\0", @a[0], 512);
    println(f"norm3 {a}");

    byte* root = "/tmp/fx_fs_test\0";
    fs_remove_all(root);
    bool ok1 = fs_mkdir_all("/tmp/fx_fs_test/x/y/z\0");
    bool d1 = fs_is_dir("/tmp/fx_fs_test/x/y\0");
    byte[6] hello = "hello";
    bool w = fs_write_all("/tmp/fx_fs_test/x/f.txt\0", @hello[0], 5);
    fs_append("/tmp/fx_fs_test/x/f.txt\0", @hello[0], 5);
    i64 sz = fs_size("/tmp/fx_fs_test/x/f.txt\0");
    i64 len;
    byte* got = fs_read_all("/tmp/fx_fs_test/x/f.txt\0", @len);
    println(f"mkdir_all {ok1} {d1} write {w} size {sz} read {len} {got}");
    ffree(got);
    bool c = fs_copy("/tmp/fx_fs_test/x/f.txt\0", "/tmp/fx_fs_test/g.txt\0");
    bool r = fs_rename("/tmp/fx_fs_test/g.txt\0", "/tmp/fx_fs_test/h.txt\0");
    bool e1 = fs_exists("/tmp/fx_fs_test/h.txt\0");
    bool e2 = fs_exists("/tmp/fx_fs_test/g.txt\0");
    bool isf = fs_is_file("/tmp/fx_fs_test/h.txt\0");
    println(f"copy {c} rename {r} {e1} {e2} isfile {isf}");

    DirIter it(root);
    byte[256] name;
    bool isd;
    int count, dirs;
    while (it.next(@name[0], 256, @isd)) { count++; if (isd) { dirs++; }; };
    println(f"entries {count} dirs {dirs}");

    fs_getcwd(@a[0], 512);
    fs_chdir(root);
    fs_getcwd(@b[0], 512);
    println(f"cwd {b}");
    fs_chdir(@a[0]);

    byte*[3] argv;
    argv[0] = "echo\0";
    argv[1] = "from-child\0";
    argv[2] = (byte*)STDLIB_GVP;
    i64 olen;
    int code;
    byte* outp = proc_capture(@argv[0], @olen, @code);
    println(f"capture {olen} code {code} {outp}");
    ffree(outp);
    byte*[2] bad;
    bad[0] = "false\0";
    bad[1] = (byte*)STDLIB_GVP;
    int rc = proc_run(@bad[0]);
    println(f"run false -> {rc}");

    env_set("FX_TEST_VAR\0", "abc\0");
    byte* ev = env_get("FX_TEST_VAR\0");
    println(f"env {ev}");

    bool rm = fs_remove_all(root);
    bool gone = !fs_exists(root);
    println(f"cleanup {rm} {gone}");
    return 0;
};
