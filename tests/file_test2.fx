#import "standard.fx";

//string test("testing!");

object file
{
    void* handle;
    bool is_open;
    bool has_error;

    // Initialize with filename and mode
    def __init(byte* filename, byte* mode) -> this
    {
        this.handle = fopen(filename, mode);
        this.is_open = (this.handle != 0);
        this.has_error = (bool)0;
        return this;
    };

    // Cleanup on destruction
    def __exit() -> void
    {
        if (this.is_open)
        {
            fclose(this.handle);
            this.is_open = (bool)0;
        };
        return;
    };
};


def main() -> int
{
    print("Opening test...\n\0");
    file test("test.txt\0", "rb\0");
    bool x = test.opened();
    
    ///if (x)
    {
        print("Success!\n\0");
    };///

    test.close();
    test.__exit();
	return 0;
};