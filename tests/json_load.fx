// Author: Karac V. Thweatt
// json_load.fx - Load a .json file, parse it, and close it.

#import "standard.fx";
#import "ffifio.fx";
#import "json.fx";

using standard::io::console,
      standard::strings,
      standard::io::file,
      json;

def parse_and_report(byte* buf) -> int
{
    JSONNode   root();
    JSONParser p(buf);
    byte[64]   num_buf;

    p.parse(@root);

    if (!p.ok())
    {
        print("ERROR: JSON parse failed\n\0");
        root.__exit();
        return 1;
    };

    print("Parse OK. Root type: \0");
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

    root.__exit();
    return 0;
};

def main() -> int
{
    void*    fh;
    int      file_size, bytes_read, result;
    byte*    buf;
    byte[64] num_buf;

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

    print("Read \0");
    i32str(bytes_read, @num_buf[0]);
    print(@num_buf[0]);
    print(" bytes. Parsing...\n\0");

    result = parse_and_report(buf);
    ffree((u64)buf);

    print("Done.\n\0");
    return result;
};
