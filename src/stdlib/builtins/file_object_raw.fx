// File Object Primitive
// Provides object-oriented interface to C stdio file operations

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_FFI_FIO
#import "ffifio.fx";
#endif;


#ifdef FLUX_STANDARD_FFI_FIO

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

    // Close file
    def close() -> bool
    {
        if ((bool)!this.is_open)
        {
            return (bool)0;
        };

        int result = fclose(this.handle);
        this.is_open = (bool)0;
        this.handle = (void*)0;
        
        return (result == 0);
    };

    // Open file with specified mode
    def open(byte* filename, byte* mode) -> bool
    {
        if (this.is_open)
        {
            this.close();
        };

        this.handle = fopen(filename, mode);
        this.is_open = (this.handle != 0);
        this.has_error = (bool)0;
        
        return this.is_open;
    };

    // Read data from file
    def read(byte[] buffer, int size, int count) -> int
    {
        if (!this.is_open)
        {
            this.has_error = (bool)1;
            return -1;
        };

        int bytes_read = fread(buffer, size, count, this.handle);
        
        if (ferror(this.handle) != 0)
        {
            this.has_error = (bool)1;
        };

        return bytes_read;
    };

    // Write data to file
    def write(byte[] dx, int size, int count) -> int
    {
        if (!this.is_open)
        {
            this.has_error = (bool)1;
            return -1;
        };

        int bytes_written = fwrite(dx, size, count, this.handle);
        
        if (ferror(this.handle) != 0)
        {
            this.has_error = (bool)1;
        };

        return bytes_written;
    };

    // Seek to position in file
    def seek(int offset, int whence) -> bool
    {
        if (!this.is_open)
        {
            this.has_error = (bool)1;
            return (bool)0;
        };

        int result = fseek(this.handle, offset, whence);
        
        if (result != 0)
        {
            this.has_error = (bool)1;
            return (bool)0;
        };

        return (bool)1;
    };

    // Get current position in file
    def tell() -> int
    {
        if (!this.is_open)
        {
            this.has_error = (bool)1;
            return -1;
        };

        return ftell(this.handle);
    };

    // Check if at end of file
    def eof() -> bool
    {
        if (!this.is_open)
        {
            return (bool)1;
        };

        return (feof(this.handle) != 0);
    };

    // Get file size
    def size() -> int
    {
        if (!this.is_open)
        {
            this.has_error = (bool)1;
            return -1;
        };

        int current_pos = ftell(this.handle);
        fseek(this.handle, 0, 2);
        int file_size = ftell(this.handle);
        fseek(this.handle, current_pos, 0);

        return file_size;
    };

    // Check if file is currently open
    def opened() -> bool
    {
        return this.is_open;
    };

    // Get raw file handle
    def get_handle() -> void*
    {
        return this.handle;
    };
};

#endif;