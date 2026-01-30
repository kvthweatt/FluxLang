// File I/O Library using C FFI
// Simple wrapper around C's stdio.h functions

#ifndef FLUX_FILE_IO
#def FLUX_FILE_IO 1;

extern
{
    // FILE* fopen(const char* filename, const char* mode)
    def !!fopen(byte* filename, byte* mode) -> void*;
    
    // int fclose(FILE* stream)
    def !!fclose(void* stream) -> int;
    
    // size_t fread(void* ptr, size_t size, size_t count, FILE* stream)
    def !!fread(void* ptr, int size, int count, void* stream) -> int;
    
    // size_t fwrite(const void* ptr, size_t size, size_t count, FILE* stream)
    def !!fwrite(void* ptr, int size, int count, void* stream) -> int;
    
    // int fseek(FILE* stream, long offset, int whence)
    def !!fseek(void* stream, int offset, int whence) -> int;
    
    // long ftell(FILE* stream)
    def !!ftell(void* stream) -> int;
    
    // void rewind(FILE* stream)
    def !!rewind(void* stream) -> void;
    
    // int feof(FILE* stream)
    def !!feof(void* stream) -> int;
    
    // int ferror(FILE* stream)
    def !!ferror(void* stream) -> int;
};

namespace standard
{
    namespace io
    {
        namespace file
        {
            // C stdio.h FFI declarations
            
            // Mode constants (as string literals you'll use)
            // "r"  - read
            // "w"  - write (truncate)
            // "a"  - append
            // "r+" - read/write
            // "w+" - read/write (truncate)
            // "rb" - read binary
            // "wb" - write binary
            // "ab" - append binary
            
            // SEEK constants for fseek
            int SEEK_SET = 0;  // Beginning of file
            int SEEK_CUR = 1;  // Current position
            int SEEK_END = 2;  // End of file
            
            
            // ===== HIGH-LEVEL HELPER FUNCTIONS =====
            
            // Read entire file into buffer
            // Returns number of bytes read, or -1 on error
            def read_file(byte* filename, byte[] buffer, int buffer_size) -> int
            {
                void* file = fopen(filename, "rb\0");
                if (file == 0)
                {
                    return -1;
                };
                
                // Get file size
                fseek(file, 0, 2);
                int file_size = ftell(file);
                rewind(file);
                
                // Read into buffer
                int bytes_to_read = file_size;
                if (bytes_to_read > buffer_size)
                {
                    bytes_to_read = buffer_size;
                };
                
                int bytes_read = fread(buffer, 1, bytes_to_read, file);
                fclose(file);
                
                return bytes_read;
            };
            
            // Write entire buffer to file
            // Returns number of bytes written, or -1 on error
            def write_file(byte* filename, byte[] xd, int data_size) -> int
            {
                void* file = fopen(filename, "wb\0");
                if (file == 0)
                {
                    return -1;
                };
                
                int bytes_written = fwrite(xd, 1, data_size, file);
                fclose(file);
                
                return bytes_written;
            };
            
            // Append data to file
            // Returns number of bytes written, or -1 on error
            def append_file(byte* filename, byte[] xd, int data_size) -> int
            {
                void* file = fopen(filename, "ab\0");
                if (file == 0)
                {
                    return -1;
                };
                
                int bytes_written = fwrite(xd, 1, data_size, file);
                fclose(file);
                
                return bytes_written;
            };
            
            // Get file size in bytes
            // Returns file size, or -1 on error
            def get_file_size(byte* filename) -> int
            {
                void* file = fopen(filename, "rb\0");
                if (file == 0)
                {
                    return -1;
                };
                
                fseek(file, 0, 2);
                int size = ftell(file);
                fclose(file);
                
                return size;
            };
            
            // Check if file exists
            // Returns 1 if exists, 0 if not
            def file_exists(byte* filename) -> bool
            {
                void* file = fopen(filename, "rb\0");
                if (file == 0)
                {
                    return 0;
                };
                
                fclose(file);
                return 1;
            };
        };
    };
};

using standard::io::file;

#endif;