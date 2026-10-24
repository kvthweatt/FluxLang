#import <standard.fx>;
#import <streams.fx>;
using standard::io::console;
using standard::streams;

def main() -> int
{
    byte* text = "line one\r\nline two\nlast";
    MemReader mr(text, 23);
    i64 n;
    byte* all = mr.read_all(@n);
    println(f"{n} {all}");
    ffree(all);

    MemReader m2(text, 23);
    byte[64] line;
    int k = m2.read_line(@line[0], 64);
    while (k >= 0)
    {
        println(f"[{k}] {@line[0]}");
        k = m2.read_line(@line[0], 64);
    };

    MemWriter mw();
    mw.write_str("hello ");
    mw.write_str("world");
    println(f"{mw.len()} {mw.bytes()}");

    MemReader m3(text, 23);
    MemWriter mw2();
    i64 c = m3.copy_to_mem(@mw2);
    println(f"copied {c} {mw2.len()}");

    FileWriter fw("/tmp/spec/lib/st1.out", false);
    fw.write_str("file data\n");
    fw.flush();
    fw.__exit();
    FileReader fr("/tmp/spec/lib/st1.out");
    i64 fn;
    byte* fd = fr.read_all(@fn);
    println(f"{fn} {fd}");
    ffree(fd);

    FileReader fr2("/tmp/spec/lib/st1.out");
    FileWriter fw2("/tmp/spec/lib/st1b.out", false);
    println(f"{fr2.copy_to_file(@fw2)}");

    FileWriter so();
    so.attach(1);
    so.write_str("to stdout\n");
    so.flush();
    return 0;
};
