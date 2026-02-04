#import "standard.fx";

object file
{
    void* handle;
    int size;

    def is_open()->bool,
        size()->int;

    def __init(byte* path, byte* mode) -> this
    {
        this.handle = fopen(path, mode);
        //this.size = this.size();
        return this;
    };

    def is_open() -> bool
    {
        return this.handle != 0;
    };

    def close() -> bool
    {
        if (this.handle == (void*)0)
        {
            return false;
        };

        fclose(this.handle);
        this.handle = (void*)0;
        return true;
    };

    def __exit() -> void
    {
        this.close();
        return;
    };

    // Returns file size without changing current position
    def size() -> int
    {
        if (this.handle == 0)
        {
            return -1;
        };

        int cur = ftell(this.handle);
        fseek(this.handle, 0, SEEK_END);
        int s = ftell(this.handle);
        fseek(this.handle, cur, SEEK_SET);
        return s;
    };

    // Read entire file into a heap-backed string that this string owns.
    // Caller should call result.__exit() (or rely on normal object cleanup rules if you add them later).
    def read_all() -> string
    {
        // If you want it to always start from beginning:
        // rewind(this.handle);

        int s = this.size();
        if (s <= 0)
        {
            string empty("\0");
            return empty;
        };

        byte* buf = malloc((u64)s + 1);
        if (buf == 0)
        {
            string empty2("\0");
            return empty2;
        };

        int bytes_read = fread(buf, 1, s, this.handle);
        if (bytes_read < 0)
        {
            free(buf);
            string empty3("\0");
            return empty3;
        };

        buf[bytes_read] = (byte)0;

        // IMPORTANT: string.__exit() frees this.value, so buf MUST be heap memory.
        string out(buf);
        return out;
    };

    // Write a null-terminated byte* (writes strlen bytes)
    def write(byte* xdata) -> int
    {
        if (this.handle == 0)
        {
            return -1;
        };

        int n = (int)strlen(xdata);
        return fwrite(xdata, 1, n, this.handle);
    };

    // Write a raw buffer with explicit length
    def write_bytes(byte* xdata, int n) -> int
    {
        if (this.handle == 0)
        {
            return -1;
        };

        return fwrite(xdata, 1, n, this.handle);
    };

    def seek(int offset, int whence) -> bool
    {
        if (this.handle == 0)
        {
            return false;
        };
        return fseek(this.handle, offset, whence) == 0;
    };

    def tell() -> int
    {
        if (this.handle == 0)
        {
            return -1;
        };
        return ftell(this.handle);
    };

    def rewind() -> void
    {
        if (this.handle != 0)
        {
            rewind(this.handle);
        };
        return;
    };
};


def main() -> int
{
    //file f();
    //s.__exit();
	return 0;
};