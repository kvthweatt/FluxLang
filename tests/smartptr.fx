// smart_ptr.fx - OOP Smart Pointer for Flux

#import "standard.fx";

using standard::io::console;

object smartptr
{
    void* raw;
    size_t ref_count;

    // Templated constructor — accepts any pointer type T*
    def __init<T>(T* val) -> this
    {
        this.raw       = (void*)val;
        this.ref_count = (size_t)1;
        return this;
    };

    def __exit() -> void
    {
        this.release();
        return;
    };

    // Increment the reference count and return this smart pointer
    def retain() -> this
    {
        this.ref_count++;
        return this;
    };

    // Decrement the reference count; free when it reaches zero
    def release() -> void
    {
        if (this.ref_count > (size_t)0)
        {
            this.ref_count--;
        };
        if (this.ref_count == (size_t)0 & this.raw != STDLIB_GVP)
        {
            free(this.raw);
            this.raw = STDLIB_GVP;
        };
        return;
    };

    // Return the raw void* held by this smart pointer
    def get() -> void*
    {
        return this.raw;
    };

    // Return true if the pointer is non-null
    def valid() -> bool
    {
        return this.raw != STDLIB_GVP;
    };

    // Return the current reference count
    def count() -> size_t
    {
        return this.ref_count;
    };

    // Swap contents with another smartptr
    def swap(smartptr* other) -> void
    {
        void*  tmp_raw   = this.raw;
        size_t tmp_count = this.ref_count;

        this.raw       = other.raw;
        this.ref_count = other.ref_count;

        other.raw       = tmp_raw;
        other.ref_count = tmp_count;
        return;
    };

    // Detach the raw pointer without freeing (transfer ownership elsewhere)
    def detach() -> void*
    {
        void* out      = this.raw;
        this.raw       = STDLIB_GVP;
        this.ref_count = (size_t)0;
        return out;
    };
};

def main() -> int
{
    // Allocate an int on the heap and wrap it in a smartptr
    int* val = (int*)malloc((size_t)sizeof(int));
    *val = 42;

    // Templated __init instantiated with int*
    smartptr sp = smartptr.__init<int>(val);

    print("valid: \0");
    if (sp.valid()) { print("true\n\0"); } else { print("false\n\0"); };

    print("ref_count: \0");
    size_t rc = sp.count();
    byte digit = (byte)((int)rc + 48);
    byte[2] buf;
    buf[0] = digit;
    buf[1] = (byte)0;
    print(buf);
    print("\n\0");

    sp.release();

    print("valid after release: \0");
    if (sp.valid()) { print("true\n\0"); } else { print("false\n\0"); };

    return 0;
};
