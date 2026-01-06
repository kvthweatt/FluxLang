namespace standard
{
    namespace io
    {
        // File I/O
        namespace file
        {
            // File handle type (Windows HANDLE is a pointer)
            unsigned data{64} as FileHandle;
            
            // File access modes
            const unsigned data{32} GENERIC_READ = 0x80000000;
            const unsigned data{32} GENERIC_WRITE = 0x40000000;
            const unsigned data{32} GENERIC_ALL = 0x10000000;
            
            // File share modes
            const unsigned data{32} FILE_SHARE_READ = 0x00000001;
            const unsigned data{32} FILE_SHARE_WRITE = 0x00000002;
            const unsigned data{32} FILE_SHARE_DELETE = 0x00000004;
            
            // File creation disposition
            const unsigned data{32} CREATE_NEW = 1;
            const unsigned data{32} CREATE_ALWAYS = 2;
            const unsigned data{32} OPEN_EXISTING = 3;
            const unsigned data{32} OPEN_ALWAYS = 4;
            const unsigned data{32} TRUNCATE_EXISTING = 5;
            
            // File attributes
            const unsigned data{32} FILE_ATTRIBUTE_NORMAL = 0x00000080;
            
            // Special values
            const FileHandle INVALID_HANDLE_VALUE = 0xFFFFFFFFFFFFFFFF;
            const FileHandle NULL_HANDLE = 0x0000000000000000;
            
            // Seek origins
            const unsigned data{32} FILE_BEGIN = 0;
            const unsigned data{32} FILE_CURRENT = 1;
            const unsigned data{32} FILE_END = 2;
            
            // FORWARD DECLARATIONS
            def win_open(byte* path, unsigned data{32} access, unsigned data{32} share, 
                        unsigned data{32} disposition, unsigned data{32} flags) -> FileHandle;
            def win_close(FileHandle handle) -> bool;
            def win_read(FileHandle handle, byte* buffer, unsigned data{32} bytes_to_read, 
                        unsigned data{32}* bytes_read) -> bool;
            def win_write(FileHandle handle, byte* buffer, unsigned data{32} bytes_to_write, 
                         unsigned data{32}* bytes_written) -> bool;
            def win_seek(FileHandle handle, signed data{64} distance, unsigned data{32} method) -> signed data{64};
            def win_get_size(FileHandle handle) -> signed data{64};
            def win_flush(FileHandle handle) -> bool;
            
            // DEFINITIONS
            
            def win_open(byte* path, unsigned data{32} access, unsigned data{32} share, 
                        unsigned data{32} disposition, unsigned data{32} flags) -> FileHandle
            {
                FileHandle result;
                
                volatile asm
                {
                    // HANDLE CreateFileA(
                    //   LPCSTR                lpFileName,        // RCX
                    //   DWORD                 dwDesiredAccess,   // RDX (32-bit)
                    //   DWORD                 dwShareMode,       // R8D (32-bit)
                    //   LPSECURITY_ATTRIBUTES lpSecurityAttr,   // R9 = NULL
                    //   DWORD                 dwCreationDisp,    // stack+32
                    //   DWORD                 dwFlagsAndAttr,    // stack+40
                    //   HANDLE                hTemplateFile      // stack+48 = NULL
                    // )
                    
                    movq $0, %rcx           // lpFileName = path
                    movl $1, %edx           // dwDesiredAccess (32-bit)
                    movl $2, %r8d           // dwShareMode (32-bit)
                    xorq %r9, %r9           // lpSecurityAttributes = NULL
                    
                    subq $$56, %rsp         // 32 shadow + 24 for params 5-7
                    movl $3, 32(%rsp)       // dwCreationDisposition
                    movl $4, 40(%rsp)       // dwFlagsAndAttributes
                    movq %r9, 48(%rsp)      // hTemplateFile = NULL
                    
                    call CreateFileA
                    
                    addq $$56, %rsp
                    movq %rax, $5           // Store result
                } : "=r"(result) : "r"(path), "r"(access), "r"(share), "r"(disposition), "r"(flags) 
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result;
            };
            
            def win_close(FileHandle handle) -> bool
            {
                unsigned data{32} result;
                
                volatile asm
                {
                    // BOOL CloseHandle(HANDLE hObject)
                    movq $0, %rcx           // hObject = handle
                    subq $$32, %rsp
                    call CloseHandle
                    addq $$32, %rsp
                    movl %eax, $1           // Store result (BOOL is 32-bit)
                } : "=r"(result) : "r"(handle) 
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result != 0;
            };
            
            def win_read(FileHandle handle, byte* buffer, unsigned data{32} bytes_to_read, 
                        unsigned data{32}* bytes_read) -> bool
            {
                unsigned data{32} result;
                
                volatile asm
                {
                    // BOOL ReadFile(
                    //   HANDLE       hFile,                // RCX
                    //   LPVOID       lpBuffer,             // RDX
                    //   DWORD        nNumberOfBytesToRead, // R8D
                    //   LPDWORD      lpNumberOfBytesRead,  // R9
                    //   LPOVERLAPPED lpOverlapped          // stack+32 = NULL
                    // )
                    
                    movq $0, %rcx           // hFile = handle
                    movq $1, %rdx           // lpBuffer = buffer
                    movl $2, %r8d           // nNumberOfBytesToRead (32-bit)
                    movq $3, %r9            // lpNumberOfBytesRead = bytes_read
                    
                    subq $$40, %rsp         // 32 shadow + 8 for param 5
                    movq $$0, 32(%rsp)      // lpOverlapped = NULL
                    
                    call ReadFile
                    
                    addq $$40, %rsp
                    movl %eax, $4           // Store result
                } : "=r"(result) : "r"(handle), "r"(buffer), "r"(bytes_to_read), "r"(bytes_read)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result != 0;
            };
            
            def win_write(FileHandle handle, byte* buffer, unsigned data{32} bytes_to_write, 
                         unsigned data{32}* bytes_written) -> bool
            {
                unsigned data{32} result;
                
                volatile asm
                {
                    // BOOL WriteFile(
                    //   HANDLE       hFile,                  // RCX
                    //   LPCVOID      lpBuffer,               // RDX
                    //   DWORD        nNumberOfBytesToWrite,  // R8D
                    //   LPDWORD      lpNumberOfBytesWritten, // R9
                    //   LPOVERLAPPED lpOverlapped            // stack+32 = NULL
                    // )
                    
                    movq $0, %rcx           // hFile = handle
                    movq $1, %rdx           // lpBuffer = buffer
                    movl $2, %r8d           // nNumberOfBytesToWrite (32-bit)
                    movq $3, %r9            // lpNumberOfBytesWritten = bytes_written
                    
                    subq $$40, %rsp         // 32 shadow + 8 for param 5
                    movq $$0, 32(%rsp)      // lpOverlapped = NULL
                    
                    call WriteFile
                    
                    addq $$40, %rsp
                    movl %eax, $4           // Store result
                } : "=r"(result) : "r"(handle), "r"(buffer), "r"(bytes_to_write), "r"(bytes_written)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result != 0;
            };
            
            def win_seek(FileHandle handle, signed data{64} distance, unsigned data{32} method) -> signed data{64}
            {
                signed data{64} result;
                unsigned data{32} low_part;
                signed data{32} high_part;
                
                // Split 64-bit distance into low and high 32-bit parts
                low_part = (unsigned data{32})(distance & 0xFFFFFFFF);
                high_part = (signed data{32})((distance >> 32) & 0xFFFFFFFF);
                
                volatile asm
                {
                    // DWORD SetFilePointer(
                    //   HANDLE hFile,                    // RCX
                    //   LONG   lDistanceToMove,          // EDX (32-bit signed)
                    //   PLONG  lpDistanceToMoveHigh,     // R8
                    //   DWORD  dwMoveMethod              // R9D (32-bit)
                    // )
                    
                    movq $0, %rcx           // hFile = handle
                    movl $1, %edx           // lDistanceToMove = low_part (32-bit)
                    leaq $2, %r8            // lpDistanceToMoveHigh = &high_part
                    movl $3, %r9d           // dwMoveMethod (32-bit)
                    
                    subq $$32, %rsp
                    call SetFilePointer
                    addq $$32, %rsp
                    
                    // Combine low (EAX) and high parts into 64-bit result
                    movl %eax, %eax         // Zero-extend EAX to RAX
                    movl $2, %edx           // Load high_part into EDX
                    shlq $$32, %rdx         // Shift high part left 32 bits
                    orq %rdx, %rax          // Combine: result = high_part << 32 | low_part
                    movq %rax, $4           // Store result
                } : "=r"(result), "+r"(high_part) : "r"(handle), "r"(low_part), "r"(method)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result;
            };
            
            def win_get_size(FileHandle handle) -> signed data{64}
            {
                signed data{64} result;
                
                volatile asm
                {
                    // BOOL GetFileSizeEx(
                    //   HANDLE         hFile,      // RCX
                    //   PLARGE_INTEGER lpFileSize  // RDX
                    // )
                    
                    movq $0, %rcx           // hFile = handle
                    leaq $1, %rdx           // lpFileSize = &result
                    
                    subq $$32, %rsp
                    call GetFileSizeEx
                    addq $$32, %rsp
                    
                    // Result is already in the memory location pointed to by RDX
                } : "+r"(result) : "r"(handle)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result;
            };
            
            def win_flush(FileHandle handle) -> bool
            {
                unsigned data{32} result;
                
                volatile asm
                {
                    // BOOL FlushFileBuffers(HANDLE hFile)
                    movq $0, %rcx           // hFile = handle
                    subq $$32, %rsp
                    call FlushFileBuffers
                    addq $$32, %rsp
                    movl %eax, $1           // Store result
                } : "=r"(result) : "r"(handle)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return result != 0;
            };
            
            // HIGH-LEVEL HELPER FUNCTIONS
            
            def open_read(noopstr path) -> FileHandle
            {
                return win_open(@path, GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL);
            };
            
            def open_write(noopstr path) -> FileHandle
            {
                return win_open(@path, GENERIC_WRITE, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL);
            };
            
            def open_append(noopstr path) -> FileHandle
            {
                FileHandle handle = win_open(@path, GENERIC_WRITE, 0, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL);
                if (handle != INVALID_HANDLE_VALUE)
                {
                    win_seek(handle, 0, FILE_END);
                };
                return handle;
            };
            
            def is_valid(FileHandle handle) -> bool
            {
                return handle != INVALID_HANDLE_VALUE and handle != NULL_HANDLE;
            };
        };