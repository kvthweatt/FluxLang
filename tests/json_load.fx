// Author: Karac V. Thweatt
// json_load.fx - Load a .json file, parse it, close it, and time each phase.

#import "standard.fx";
#import "allocators.fx";
#import "ffifio.fx";
#import "json.fx";
#import "timing.fx";

using standard::io::console,
      standard::io::file,
      standard::strings,
      standard::time,
      standard::memory::allocators::stdarena,
      json;

def print_ms(i64 ns) -> void
{
    i64      ms, us;
    byte[64] buf;
    ms = ns_to_ms(ns);
    us = ns_to_us(ns) % 1000;
    i64str(ms, @buf[0]);
    print(@buf[0]);
    print(".\0");
    if (us < 100) { print("0\0"); };
    if (us < 10)  { print("0\0"); };
    i64str(us, @buf[0]);
    print(@buf[0]);
    print(" ms\0");
    return;
};

def print_mbs(i64 bytes, i64 ns) -> void
{
    i64      us, kb_per_s, mbs, mbs_frac;
    byte[64] buf;
    if (ns <= 0) { print("N/A\0"); return; };
    us = ns / 1000;
    if (us <= 0) { us = 1; };
    kb_per_s = (bytes * 1000) / us;
    mbs      = kb_per_s / 1024;
    mbs_frac = (kb_per_s % 1024) * 10 / 1024;
    i64str(mbs, @buf[0]);
    print(@buf[0]);
    print(".\0");
    i64str(mbs_frac, @buf[0]);
    print(@buf[0]);
    print(" MB/s\0");
    return;
};

def parse_and_report(byte* buf, int buf_len) -> int
{
    JSONNode       root();
    Arena          arena;
    JSONParserFast p(buf, buf_len, @arena);
    byte[64]       num_buf;
    size_t         node_cap;

    // Single arena covers nodes and strings.
    // node_cap: worst case ~1 node per 3 bytes of source, 2x headroom, plus string data.
    node_cap = (size_t)((buf_len / 3 + 1) * (sizeof(JSONNode) / sizeof(byte)) * 2)
             + (size_t)buf_len + 1;
    arena_init_sized(@arena, node_cap);

    p.parse(@root);

    if (!p.ok())
    {
        print("ERROR: JSON parse failed\n\0");
        arena_destroy(@arena);
        return 1;
    };

    print("Root type: \0");
    if      (root.is_null())   { print("null\n\0");   }
    elif    (root.is_bool())   { print("bool\n\0");   }
    elif    (root.is_int())    { print("int\n\0");    }
    elif    (root.is_float())  { print("float\n\0");  }
    elif    (root.is_string()) { print("string\n\0"); }
    elif    (root.is_array())
    {
        print("array, length: \0");
        i32str((int)root.array_len(), @num_buf[0]);
        print(@num_buf[0]);
        print("\n\0");
    }
    elif    (root.is_object())
    {
        print("object, keys: \0");
        i32str((int)root.object_len(), @num_buf[0]);
        print(@num_buf[0]);
        print("\n\0");
    };

    arena_destroy(@arena);
    return 0;
};

def main() -> int
{
    void*    fh;
    int      file_size, bytes_read, result;
    byte*    buf;
    byte[64] num_buf;
    i64      t_start, t_after_load, t_after_parse, load_ns, parse_ns, total_ns;

    t_start = time_now();

    print("Opening test.json...\n\0");

    fh = fopen("test.json\0", "rb\0");
    if ((u64)fh == 0)
    {
        print("ERROR: Could not open test.json\n\0");
        return 1;
    };

    fseek(fh, 0, SEEK_END);
    file_size = ftell(fh);
    fseek(fh, 0, SEEK_SET);

    print("File size: \0");
    i32str(file_size, @num_buf[0]);
    print(@num_buf[0]);
    print(" bytes\n\0");

    buf = (byte*)fmalloc((u64)file_size + 1);
    if ((u64)buf == 0)
    {
        print("ERROR: Out of memory\n\0");
        fclose(fh);
        return 1;
    };

    bytes_read = fread(buf, 1, file_size, fh);
    fclose(fh);
    buf[bytes_read] = (byte)0;

    t_after_load = time_now();

    // Pass bytes_read directly -- no strlen in the parser.
    result = parse_and_report(buf, bytes_read);

    t_after_parse = time_now();

    ffree((u64)buf);

    load_ns  = t_after_load  - t_start;
    parse_ns = t_after_parse - t_after_load;
    total_ns = t_after_parse - t_start;

    print("\n\0");
    print("Load:  \0"); print_ms(load_ns);  print(" | \0"); print_mbs((i64)bytes_read, load_ns);  print("\n\0");
    print("Parse: \0"); print_ms(parse_ns); print(" | \0"); print_mbs((i64)bytes_read, parse_ns); print("\n\0");
    print("Total: \0"); print_ms(total_ns); print(" | \0"); print_mbs((i64)bytes_read, total_ns); print("\n\0");

    return result;
};
