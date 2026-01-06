// io.fx - Full Windows I/O Library for Flux
// Implements console and file I/O with AT&T syntax inline assembly
// Compatible with LLVM (requires proper clobber lists)

import "types.fx";

using standard::types;

namespace windows
{
    //-------------------------------------------------------------------------
    // WINDOWS API FUNCTION DECLARATIONS
    //-------------------------------------------------------------------------
    
    // These are declared here for the inline assembly to call
    def GetStdHandle(i32 nStdHandle) -> i64;
    def WriteFile(i64 hFile, void* lpBuffer, u32 nNumberOfBytesToWrite,
                 u32* lpNumberOfBytesWritten, void* lpOverlapped) -> bool;
    def ReadFile(i64 hFile, void* lpBuffer, u32 nNumberOfBytesToRead,
                u32* lpNumberOfBytesRead, void* lpOverlapped) -> bool;
    def SetConsoleMode(i64 hConsoleHandle, u32 dwMode) -> bool;
    def GetConsoleMode(i64 hConsoleHandle, u32* lpMode) -> bool;
    def SetConsoleTextAttribute(i64 hConsoleOutput, ui16 wAttributes) -> bool;
    def CreateFileA(byte* lpFileName, u32 dwDesiredAccess, u32 dwShareMode,
                   void* lpSecurityAttributes, u32 dwCreationDisposition,
                   u32 dwFlagsAndAttributes, i64 hTemplateFile) -> i64;
    def CloseHandle(i64 hObject) -> bool;
    def GetFileSize(i64 hFile, u32* lpFileSizeHigh) -> u32;
    def SetFilePointer(i64 hFile, i32 lDistanceToMove, i32* lpDistanceToMoveHigh,
                      u32 dwMoveMethod) -> u32;
    def FlushFileBuffers(i64 hFile) -> bool;
    def DeleteFileA(byte* lpFileName) -> bool;
    def GetFileAttributesA(byte* lpFileName) -> u32;
    def GetProcessHeap() -> i64;
    def HeapAlloc(i64 hHeap, u32 dwFlags, ui64 dwBytes) -> void*;
    def HeapFree(i64 hHeap, u32 dwFlags, void* lpMem) -> bool;
    def HeapReAlloc(i64 hHeap, u32 dwFlags, void* lpMem, ui64 dwBytes) -> void*;
    
    namespace io
    {
        // Console Constants
        global def STD_INPUT_HANDLE  -10;
        global def STD_OUTPUT_HANDLE -11;
        global def STD_ERROR_HANDLE  -12;
        
        // File Access Modes
        global def GENERIC_READ      0x80000000;
        global def GENERIC_WRITE     0x40000000;
        global def GENERIC_EXECUTE   0x20000000;
        global def GENERIC_ALL       0x10000000;
        
        // File Creation Flags
        global def CREATE_NEW        1;
        global def CREATE_ALWAYS     2;
        global def OPEN_EXISTING     3;
        global def OPEN_ALWAYS       4;
        global def TRUNCATE_EXISTING 5;
        
        // File Share Modes
        global def FILE_SHARE_READ   0x00000001;
        global def FILE_SHARE_WRITE  0x00000002;
        global def FILE_SHARE_DELETE 0x00000004;
        
        // File Attributes
        global def FILE_ATTRIBUTE_NORMAL     0x00000080;
        global def FILE_ATTRIBUTE_HIDDEN     0x00000002;
        global def FILE_ATTRIBUTE_READONLY   0x00000001;
        global def FILE_ATTRIBUTE_DIRECTORY  0x00000010;
        
        //-------------------------------------------------------------------------
        // CONSOLE I/O
        //-------------------------------------------------------------------------
        
        namespace console
        {
            // Get standard handle
            def getStdHandle(int nStdHandle) -> i64
            {
                i64 handle;
                volatile asm
                {
                    // HANDLE GetStdHandle(DWORD nStdHandle)
                    movl $0, %ecx           // nStdHandle (parameter 0)
                    subq $$32, %rsp         // Shadow space
                    call GetStdHandle
                    addq $$32, %rsp
                    movq %rax, handle
                } : : "r"(nStdHandle) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return handle;
            };
            
            // Write to console
            def write(i64 handle, byte* buffer, u32 bytesToWrite) -> bool
            {
                u32 bytesWritten = 0;
                bool success = false;
                u32* pBytesWritten = @bytesWritten;
                
                volatile asm
                {
                    // BOOL WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite,
                    //                LPDWORD lpNumberOfBytesWritten, LPOVERLAPPED lpOverlapped)
                    movq $0, %rcx           // hFile = handle
                    movq $1, %rdx           // lpBuffer = buffer
                    movl $2, %r8d           // nNumberOfBytesToWrite = bytesToWrite (32-bit)
                    movq $3, %r9           // lpNumberOfBytesWritten = pBytesWritten
                    
                    // Setup 5th argument (NULL for lpOverlapped)
                    subq $$40, %rsp         // 32 bytes shadow + 8 for 5th arg
                    xorq %rax, %rax         // NULL
                    movq %rax, 32(%rsp)     // lpOverlapped = NULL
                    
                    call WriteFile
                    addq $$40, %rsp
                    
                    // Set return value (RAX contains BOOL result)
                    movl %eax, success      // success = (BOOL)result
                } : : "r"(handle), "r"(buffer), "r"(bytesToWrite), "r"(pBytesWritten) 
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return success;
            };
            
            // Read from console
            def read(i64 handle, byte* buffer, u32 bytesToRead) -> u32
            {
                u32 bytesRead = 0;
                u32* pBytesRead = @bytesRead;
                
                volatile asm
                {
                    // BOOL ReadFile(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead,
                    //               LPDWORD lpNumberOfBytesRead, LPOVERLAPPED lpOverlapped)
                    movq $0, %rcx           // hFile = handle
                    movq $1, %rdx           // lpBuffer = buffer
                    movl $2, %r8d           // nNumberOfBytesToRead = bytesToRead
                    movq $3, %r9           // lpNumberOfBytesRead = pBytesRead
                    
                    // Setup 5th argument (NULL for lpOverlapped)
                    subq $$40, %rsp
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     // lpOverlapped = NULL
                    
                    call ReadFile
                    addq $$40, %rsp
                    
                    // If ReadFile failed, set bytesRead to 0
                    testl %eax, %eax
                    jnz read_success
                    movq $3, %rax
                    movl $$0, (%rax)        // *pBytesRead = 0
                    
                    read_success:
                } : : "r"(handle), "r"(buffer), "r"(bytesToRead), "r"(pBytesRead)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return bytesRead;
            };
            
            // Set console mode
            def setConsoleMode(i64 handle, u32 mode) -> bool
            {
                bool success;
                volatile asm
                {
                    // BOOL SetConsoleMode(HANDLE hConsoleHandle, DWORD dwMode)
                    movq $0, %rcx           // hConsoleHandle = handle
                    movl $1, %edx           // dwMode = mode
                    subq $$32, %rsp
                    call SetConsoleMode
                    addq $$32, %rsp
                    movl %eax, success      // success = result
                } : : "r"(handle), "r"(mode) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return success;
            };
            
            // Get console mode
            def getConsoleMode(i64 handle) -> u32
            {
                u32 mode;
                volatile asm
                {
                    // BOOL GetConsoleMode(HANDLE hConsoleHandle, LPDWORD lpMode)
                    movq $0, %rcx           // hConsoleHandle = handle
                    leaq mode, %rdx         // lpMode = &mode
                    subq $$32, %rsp
                    call GetConsoleMode
                    addq $$32, %rsp
                    // mode already set via pointer
                } : : "r"(handle), "r"(@mode) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return mode;
            };
            
            //-------------------------------------------------------------------------
            // HIGH-LEVEL CONSOLE FUNCTIONS
            //-------------------------------------------------------------------------
            
            // Print string to stdout
            def print(byte* str, u32 length) -> void
            {
                i64 stdout = getStdHandle(STD_OUTPUT_HANDLE);
                if (stdout != 0)
                {
                    write(stdout, str, length);
                };
                return void;
            };
            
            // Print string with newline
            def println(byte* str, u32 length) -> void
            {
                print(str, length);
                print(@"\r\n", 2);
                return void;
            };
            
            // Print character
            def putchar(char c) -> void
            {
                byte ch = (byte)c;
                print(@ch, 1);
                return void;
            };
            
            // Get character from stdin
            def getchar() -> char
            {
                byte ch;
                i64 stdin = getStdHandle(STD_INPUT_HANDLE);
                if (stdin != 0)
                {
                    if (read(stdin, @ch, 1) == 1)
                    {
                        return (char)ch;
                    };
                };
                return (char)0;
            };
            
            // Read line from stdin
            def readLine(byte* buffer, u32 maxLength) -> u32
            {
                i64 stdin = getStdHandle(STD_INPUT_HANDLE);
                u32 totalRead = 0;
                byte ch;
                
                if (stdin == 0 || maxLength == 0)
                {
                    return 0;
                };
                
                while (totalRead < maxLength - 1)
                {
                    if (read(stdin, @ch, 1) != 1)
                    {
                        break;
                    };
                    
                    if (ch == '\r' || ch == '\n')
                    {
                        // Consume remaining newline characters
                        if (ch == '\r')
                        {
                            // Peek for '\n'
                            byte nextCh;
                            if (read(stdin, @nextCh, 1) == 1 && nextCh != '\n')
                            {
                                // Put it back (can't actually put back, so store it)
                                // For simplicity, we'll just discard for now
                            };
                        };
                        break;
                    };
                    
                    buffer[totalRead] = ch;
                    totalRead++;
                };
                
                buffer[totalRead] = 0; // Null terminate
                return totalRead;
            };
            
            // Clear console
            def clear() -> void
            {
                i64 stdout = getStdHandle(STD_OUTPUT_HANDLE);
                if (stdout != 0)
                {
                    // Windows-specific clear screen command
                    print(@"\x1B[2J\x1B[H", 7);
                };
                return void;
            };
            
            // Set console text color
            def setColor(u32 color) -> void
            {
                i64 stdout = getStdHandle(STD_OUTPUT_HANDLE);
                if (stdout != 0)
                {
                    // Windows console attribute
                    u32* attributes = @color;
                    volatile asm
                    {
                        // BOOL SetConsoleTextAttribute(HANDLE hConsoleOutput, WORD wAttributes)
                        movq $0, %rcx           // hConsoleOutput = stdout
                        movzwl (%rdx), %edx     // wAttributes = color (16-bit)
                        subq $$32, %rsp
                        call SetConsoleTextAttribute
                        addq $$32, %rsp
                    } : : "r"(stdout), "r"(attributes) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                };
                return void;
            };
        };
        
        //-------------------------------------------------------------------------
        // FILE I/O
        //-------------------------------------------------------------------------
        
        namespace file
        {
            // File handle type
            struct FileHandle
            {
                i64 handle;
                bool valid;
            };
            
            // Open file
            def open(byte* filename, u32 access, u32 share, u32 creation, u32 attributes) -> FileHandle
            {
                FileHandle fh;
                fh.valid = false;
                fh.handle = 0;
                
                i64 result;
                volatile asm
                {
                    // HANDLE CreateFileA(LPCSTR lpFileName, DWORD dwDesiredAccess,
                    //                    DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes,
                    //                    DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes,
                    //                    HANDLE hTemplateFile)
                    
                    // Parameters
                    movq $0, %rcx           // lpFileName = filename
                    movl $1, %edx           // dwDesiredAccess = access
                    movl $2, %r8d           // dwShareMode = share
                    xorq %r9, %r9           // lpSecurityAttributes = NULL
                    
                    // Stack arguments (5th, 6th, 7th)
                    subq $$56, %rsp         // 32 shadow + 24 for 3 args
                    
                    movl $3, %eax           // dwCreationDisposition = creation
                    movl %eax, 32(%rsp)
                    
                    movl $4, %eax           // dwFlagsAndAttributes = attributes
                    movl %eax, 40(%rsp)
                    
                    xorq %rax, %rax         // hTemplateFile = NULL
                    movq %rax, 48(%rsp)
                    
                    call CreateFileA
                    addq $$56, %rsp
                    
                    movq %rax, result       // result = handle
                } : : "r"(filename), "r"(access), "r"(share), "r"(creation), "r"(attributes)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                if (result != -1)  // INVALID_HANDLE_VALUE = -1
                {
                    fh.handle = result;
                    fh.valid = true;
                };
                
                return fh;
            };
            
            // Close file
            def close(FileHandle fh) -> bool
            {
                if (!fh.valid)
                {
                    return false;
                };
                
                bool success;
                volatile asm
                {
                    // BOOL CloseHandle(HANDLE hObject)
                    movq $0, %rcx           // hObject = fh.handle
                    subq $$32, %rsp
                    call CloseHandle
                    addq $$32, %rsp
                    movl %eax, success      // success = result
                } : : "r"(fh.handle) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return success;
            };
            
            // Read from file
            def read(FileHandle fh, byte* buffer, u32 bytesToRead) -> u32
            {
                if (!fh.valid)
                {
                    return 0;
                };
                
                u32 bytesRead = 0;
                u32* pBytesRead = @bytesRead;
                
                volatile asm
                {
                    // BOOL ReadFile(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead,
                    //               LPDWORD lpNumberOfBytesRead, LPOVERLAPPED lpOverlapped)
                    movq $0, %rcx           // hFile = fh.handle
                    movq $1, %rdx           // lpBuffer = buffer
                    movl $2, %r8d           // nNumberOfBytesToRead = bytesToRead
                    movq $3, %r9           // lpNumberOfBytesRead = pBytesRead
                    
                    // Setup 5th argument (NULL for lpOverlapped)
                    subq $$40, %rsp
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)
                    
                    call ReadFile
                    addq $$40, %rsp
                    
                    // If ReadFile failed, set bytesRead to 0
                    testl %eax, %eax
                    jnz read_success
                    movq $3, %rax
                    movl $$0, (%rax)
                    
                    read_success:
                } : : "r"(fh.handle), "r"(buffer), "r"(bytesToRead), "r"(pBytesRead)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return bytesRead;
            };
            
            // Write to file
            def write(FileHandle fh, byte* buffer, u32 bytesToWrite) -> u32
            {
                if (!fh.valid)
                {
                    return 0;
                };
                
                u32 bytesWritten = 0;
                u32* pBytesWritten = @bytesWritten;
                
                volatile asm
                {
                    // BOOL WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite,
                    //                LPDWORD lpNumberOfBytesWritten, LPOVERLAPPED lpOverlapped)
                    movq $0, %rcx           // hFile = fh.handle
                    movq $1, %rdx           // lpBuffer = buffer
                    movl $2, %r8d           // nNumberOfBytesToWrite = bytesToWrite
                    movq $3, %r9           // lpNumberOfBytesWritten = pBytesWritten
                    
                    // Setup 5th argument (NULL for lpOverlapped)
                    subq $$40, %rsp
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)
                    
                    call WriteFile
                    addq $$40, %rsp
                    
                    // If WriteFile failed, set bytesWritten to 0
                    testl %eax, %eax
                    jnz write_success
                    movq $3, %rax
                    movl $$0, (%rax)
                    
                    write_success:
                } : : "r"(fh.handle), "r"(buffer), "r"(bytesToWrite), "r"(pBytesWritten)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return bytesWritten;
            };
            
            // Get file size
            def getSize(FileHandle fh) -> i64
            {
                if (!fh.valid)
                {
                    return 0;
                };
                
                i64 size;
                volatile asm
                {
                    // DWORD GetFileSize(HANDLE hFile, LPDWORD lpFileSizeHigh)
                    movq $0, %rcx           // hFile = fh.handle
                    xorq %rdx, %rdx         // lpFileSizeHigh = NULL
                    subq $$32, %rsp
                    call GetFileSize
                    addq $$32, %rsp
                    
                    // RAX contains low DWORD, high DWORD is 0 since we passed NULL
                    movq %rax, size
                } : : "r"(fh.handle) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return size;
            };
            
            // Set file pointer
            def seek(FileHandle fh, i64 distance, u32 moveMethod) -> i64
            {
                if (!fh.valid)
                {
                    return -1;
                };
                
                i64 newPosition;
                i64* pNewPosition = @newPosition;
                i32 distanceLow = (i32)(distance & 0xFFFFFFFF);
                i32 distanceHigh = (i32)(distance >> 32);
                
                volatile asm
                {
                    // DWORD SetFilePointer(HANDLE hFile, LONG lDistanceToMove,
                    //                     PLONG lpDistanceToMoveHigh, DWORD dwMoveMethod)
                    movq $0, %rcx           // hFile = fh.handle
                    movl $1, %edx           // lDistanceToMove = distanceLow
                    leaq $2, %r8           // lpDistanceToMoveHigh = &distanceHigh
                    movl $3, %r9d           // dwMoveMethod = moveMethod
                    subq $$32, %rsp
                    call SetFilePointer
                    addq $$32, %rsp
                    
                    // Combine low and high parts
                    movl %eax, %eax         // Zero extend low DWORD
                    shlq $$32, %rdx        // Shift high DWORD
                    orq %rdx, %rax         // Combine
                    movq %rax, (pNewPosition)
                } : : "r"(fh.handle), "r"(distanceLow), "r"(@distanceHigh), "r"(moveMethod)
                  : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return newPosition;
            };
            
            // Flush file buffers
            def flush(FileHandle fh) -> bool
            {
                if (!fh.valid)
                {
                    return false;
                };
                
                bool success;
                volatile asm
                {
                    // BOOL FlushFileBuffers(HANDLE hFile)
                    movq $0, %rcx           // hFile = fh.handle
                    subq $$32, %rsp
                    call FlushFileBuffers
                    addq $$32, %rsp
                    movl %eax, success
                } : : "r"(fh.handle) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return success;
            };
            
            //-------------------------------------------------------------------------
            // HIGH-LEVEL FILE FUNCTIONS
            //-------------------------------------------------------------------------
            
            // Open file for reading
            def openRead(byte* filename) -> FileHandle
            {
                return open(filename, GENERIC_READ, FILE_SHARE_READ, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL);
            };
            
            // Open file for writing (creates if doesn't exist, truncates if exists)
            def openWrite(byte* filename) -> FileHandle
            {
                return open(filename, GENERIC_WRITE, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL);
            };
            
            // Open file for appending
            def openAppend(byte* filename) -> FileHandle
            {
                FileHandle fh = open(filename, GENERIC_WRITE, 0, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL);
                if (fh.valid)
                {
                    seek(fh, 0, 2); // Seek to end (FILE_END = 2)
                };
                return fh;
            };
            
            // Read entire file into buffer
            def readAll(byte* filename, byte** buffer, ui64* size) -> bool
            {
                FileHandle fh = openRead(filename);
                if (!fh.valid)
                {
                    return false;
                };
                
                i64 fileSize = getSize(fh);
                if (fileSize <= 0)
                {
                    close(fh);
                    return false;
                };
                
                // Allocate buffer
                *size = (ui64)fileSize;
                *buffer = malloc(*size);
                if (*buffer == void)
                {
                    close(fh);
                    return false;
                };
                
                // Read file
                u32 totalRead = 0;
                u32 bytesRead;
                while (totalRead < *size)
                {
                    bytesRead = read(fh, *buffer + totalRead, (u32)(*size - totalRead));
                    if (bytesRead == 0)
                    {
                        break;
                    };
                    totalRead += bytesRead;
                };
                
                close(fh);
                return (totalRead == *size);
            };
            
            // Write buffer to file
            def writeAll(byte* filename, byte* buffer, ui64 size) -> bool
            {
                FileHandle fh = openWrite(filename);
                if (!fh.valid)
                {
                    return false;
                };
                
                u32 totalWritten = 0;
                u32 bytesWritten;
                while (totalWritten < size)
                {
                    u32 toWrite = (u32)(size - totalWritten);
                    if (toWrite > 0xFFFFFFFF)
                    {
                        toWrite = 0xFFFFFFFF;
                    };
                    
                    bytesWritten = write(fh, buffer + totalWritten, toWrite);
                    if (bytesWritten == 0)
                    {
                        break;
                    };
                    totalWritten += bytesWritten;
                };
                
                flush(fh);
                close(fh);
                return (totalWritten == size);
            };
            
            // Copy file
            def copy(byte* source, byte* destination) -> bool
            {
                byte* buffer;
                ui64 size;
                
                if (!readAll(source, @buffer, @size))
                {
                    return false;
                };
                
                bool success = writeAll(destination, buffer, size);
                free(buffer);
                return success;
            };
            
            // Delete file
            def delete(byte* filename) -> bool
            {
                bool success;
                volatile asm
                {
                    // BOOL DeleteFileA(LPCSTR lpFileName)
                    movq $0, %rcx           // lpFileName = filename
                    subq $$32, %rsp
                    call DeleteFileA
                    addq $$32, %rsp
                    movl %eax, success
                } : : "r"(filename) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return success;
            };
            
            // Check if file exists
            def exists(byte* filename) -> bool
            {
                u32 attributes;
                volatile asm
                {
                    // DWORD GetFileAttributesA(LPCSTR lpFileName)
                    movq $0, %rcx           // lpFileName = filename
                    subq $$32, %rsp
                    call GetFileAttributesA
                    addq $$32, %rsp
                    movl %eax, attributes
                } : : "r"(filename) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return (attributes != 0xFFFFFFFF);
            };
        };
        
        //-------------------------------------------------------------------------
        // MEMORY ALLOCATION (for file buffers)
        //-------------------------------------------------------------------------
        
        namespace mem
        {
            // Allocate memory
            def malloc(ui64 size) -> void*
            {
                void* ptr;
                volatile asm
                {
                    // LPVOID HeapAlloc(HANDLE hHeap, DWORD dwFlags, SIZE_T dwBytes)
                    movq GetProcessHeap(), %rcx  // hHeap = GetProcessHeap()
                    xorq %rdx, %rdx              // dwFlags = 0
                    movq $0, %r8                // dwBytes = size
                    subq $$32, %rsp
                    call HeapAlloc
                    addq $$32, %rsp
                    movq %rax, ptr
                } : : "r"(size) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return ptr;
            };
            
            // Free memory
            def free(void* ptr) -> void
            {
                if (ptr == void)
                {
                    return void;
                };
                
                volatile asm
                {
                    // BOOL HeapFree(HANDLE hHeap, DWORD dwFlags, LPVOID lpMem)
                    movq GetProcessHeap(), %rcx  // hHeap = GetProcessHeap()
                    xorq %rdx, %rdx              // dwFlags = 0
                    movq $0, %r8                // lpMem = ptr
                    subq $$32, %rsp
                    call HeapFree
                    addq $$32, %rsp
                } : : "r"(ptr) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                return void;
            };
            
            // Reallocate memory
            def realloc(void* ptr, ui64 newSize) -> void*
            {
                if (ptr == void)
                {
                    return malloc(newSize);
                };
                
                void* newPtr;
                volatile asm
                {
                    // LPVOID HeapReAlloc(HANDLE hHeap, DWORD dwFlags, LPVOID lpMem, SIZE_T dwBytes)
                    movq GetProcessHeap(), %rcx  // hHeap = GetProcessHeap()
                    xorq %rdx, %rdx              // dwFlags = 0
                    movq $0, %r8                // lpMem = ptr
                    movq $1, %r9                // dwBytes = newSize
                    subq $$32, %rsp
                    call HeapReAlloc
                    addq $$32, %rsp
                    movq %rax, newPtr
                } : : "r"(ptr), "r"(newSize) : "rax","rcx","rdx","r8","r9","r10","r11","memory";
                
                return newPtr;
            };
        };
        
        //-------------------------------------------------------------------------
        // UTILITY FUNCTIONS
        //-------------------------------------------------------------------------
        
        namespace util
        {
            // Get string length (null-terminated)
            def strlen(byte* str) -> u32
            {
                u32 len = 0;
                while (str[len] != 0)
                {
                    len++;
                };
                return len;
            };
            
            // Copy string
            def strcpy(byte* dest, byte* src) -> void
            {
                u32 i = 0;
                while (src[i] != 0)
                {
                    dest[i] = src[i];
                    i++;
                };
                dest[i] = 0;
                return void;
            };
            
            // Compare strings
            def strcmp(byte* a, byte* b) -> i32
            {
                u32 i = 0;
                while (a[i] != 0 && b[i] != 0)
                {
                    if (a[i] != b[i])
                    {
                        return (i32)a[i] - (i32)b[i];
                    };
                    i++;
                };
                return (i32)a[i] - (i32)b[i];
            };
            
            // Convert integer to string
            def itoa(i32 value, byte* buffer, u32 base) -> byte*
            {
                if (base < 2 || base > 36)
                {
                    buffer[0] = '0';
                    buffer[1] = 0;
                    return buffer;
                };
                
                u32 i = 0;
                bool negative = false;
                
                if (value == 0)
                {
                    buffer[i++] = '0';
                    buffer[i] = 0;
                    return buffer;
                };
                
                if (value < 0 && base == 10)
                {
                    negative = true;
                    value = -value;
                };
                
                while (value != 0)
                {
                    i32 remainder = value % base;
                    buffer[i++] = (remainder > 9) ? (byte)(remainder - 10 + 'A') : (byte)(remainder + '0');
                    value = value / base;
                };
                
                if (negative)
                {
                    buffer[i++] = '-';
                };
                
                buffer[i] = 0;
                
                // Reverse the string
                u32 start = 0;
                u32 end = i - 1;
                while (start < end)
                {
                    byte temp = buffer[start];
                    buffer[start] = buffer[end];
                    buffer[end] = temp;
                    start++;
                    end--;
                };
                
                return buffer;
            };
            
            // Convert string to integer
            def atoi(byte* str) -> i32
            {
                i32 result = 0;
                i32 sign = 1;
                u32 i = 0;
                
                // Skip whitespace
                while (str[i] == ' ' || str[i] == '\t' || str[i] == '\n' || str[i] == '\r')
                {
                    i++;
                };
                
                // Check sign
                if (str[i] == '-')
                {
                    sign = -1;
                    i++;
                }
                elif (str[i] == '+')
                {
                    i++;
                };
                
                // Convert digits
                while (str[i] >= '0' && str[i] <= '9')
                {
                    result = result * 10 + (str[i] - '0');
                    i++;
                };
                
                return result * sign;
            };
        };
    };
};