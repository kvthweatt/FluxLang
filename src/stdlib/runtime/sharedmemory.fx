// redsharedmem.fx - Shared Memory Library
// Provides named shared memory regions visible across processes.
//
// Windows : CreateFileMappingA / OpenFileMappingA / MapViewOfFile
// Linux   : shm_open / ftruncate / mmap / shm_unlink  (POSIX)
// macOS   : shm_open / ftruncate / mmap / shm_unlink  (POSIX)
//
// Usage pattern:
//   Process A (creator):
//     SharedMem shm;
//     shm_create(@shm, "my_region\0", 4096);
//     byte* ptr = shm_map(@shm, SHM_READ | SHM_WRITE);
//     // ... write data ...
//     shm_unmap(@shm);
//     shm_close(@shm);          // keeps the region alive for other processes
//
//   Process B (consumer):
//     SharedMem shm;
//     shm_open_existing(@shm, "my_region\0", 4096);
//     byte* ptr = shm_map(@shm, SHM_READ);
//     // ... read data ...
//     shm_unmap(@shm);
//     shm_close(@shm);
//
//   Creator cleanup (when all consumers are done):
//     shm_destroy(@shm, "my_region\0");

#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_SHAREDMEM
#def FLUX_STANDARD_SHAREDMEM 1;

// ============================================================
//  Platform FFI
// ============================================================

#ifdef __WINDOWS__
extern
{
    def !!
        CreateFileMappingA(void*, void*, u32, u32, u32, byte*) -> void*,
        OpenFileMappingA(u32, int, byte*)                      -> void*,
        MapViewOfFile(void*, u32, u32, u32, size_t)            -> void*,
        UnmapViewOfFile(void*)                                 -> int,
        FlushViewOfFile(void*, size_t)                         -> int,
        CloseHandle(void*)                                     -> int;
};
#endif;

#ifdef __LINUX__
extern
{
    def !!
        shm_open(byte*, int, u32)               -> int,
        shm_unlink(byte*)                       -> int,
        ftruncate(int, i64)                     -> int,
        mmap(void*, size_t, int, int, int, i64) -> void*,
        munmap(void*, size_t)                   -> int,
        msync(void*, size_t, int)               -> int,
        close(int)                              -> int;
};
#endif;

#ifdef __MACOS__
extern
{
    def !!
        shm_open(byte*, int, u32)               -> int,
        shm_unlink(byte*)                       -> int,
        ftruncate(int, i64)                     -> int,
        mmap(void*, size_t, int, int, int, i64) -> void*,
        munmap(void*, size_t)                   -> int,
        msync(void*, size_t, int)               -> int,
        close(int)                              -> int;
};
#endif;

// ============================================================
//  Access flags (combine with |)
// ============================================================

const u32 SHM_READ  = 0x01,
          SHM_WRITE = 0x02;

// ============================================================
//  Result codes
// ============================================================

const int SHM_OK    =  0,
          SHM_ERROR = -1;

// ============================================================
//  Windows page-protection / access constants
// ============================================================

#ifdef __WINDOWS__
const u32 WIN_PAGE_READWRITE = 0x04,
          WIN_PAGE_READONLY  = 0x02,
          WIN_FILE_MAP_WRITE = 0x0002,
          WIN_FILE_MAP_READ  = 0x0004;
#endif;

// ============================================================
//  POSIX constants
// ============================================================

#ifdef __LINUX__
const int POSIX_O_RDONLY   = 0,
          POSIX_O_RDWR     = 2,
          POSIX_O_CREAT    = 64,
          POSIX_O_TRUNC    = 512,
          POSIX_PROT_READ  = 1,
          POSIX_PROT_WRITE = 2,
          POSIX_MAP_SHARED = 1,
          POSIX_MS_SYNC    = 4;

const u32 POSIX_MODE_RW = 0x1B6;
#endif;

#ifdef __MACOS__
const int POSIX_O_RDONLY   = 0,
          POSIX_O_RDWR     = 2,
          POSIX_O_CREAT    = 512,
          POSIX_O_TRUNC    = 1024,
          POSIX_PROT_READ  = 1,
          POSIX_PROT_WRITE = 2,
          POSIX_MAP_SHARED = 1,
          POSIX_MS_SYNC    = 0;

const u32 POSIX_MODE_RW = 0x1B6;
#endif;

// ============================================================
//  SharedMem struct
//
//  handle  - Win32 HANDLE or POSIX fd, stored as u64
//  view    - mapped virtual address (null if not yet mapped)
//  size    - length of the region in bytes
//  owner   - 1 if this process created the region
// ============================================================

struct SharedMem
{
    u64    handle;
    void*  view;
    size_t size;
    i32    owner,
           _pad;
};

// ============================================================
//  Namespace
// ============================================================

namespace standard
{
    namespace sharedmemory
    {
        // ====================================================
        //  Create a new named shared memory region.
        //  Returns SHM_OK or SHM_ERROR.
        // ====================================================
        def shm_create(SharedMem* out, byte* name, size_t size) -> int
        {
            out.view  = (void*)0;
            out.size  = size;
            out.owner = 1;

            #ifdef __WINDOWS__
            u32 hi = (u32)((u64)size >> 32);
            u32 lo = (u32)size;
            void* h = CreateFileMappingA(
                (void*)(i64)-1,     // INVALID_HANDLE_VALUE - pagefile-backed
                (void*)0,           // default security
                WIN_PAGE_READWRITE,
                hi,
                lo,
                name
            );
            if ((u64)h == (u64)0)
            {
                return SHM_ERROR;
            };
            out.handle = (u64)h;
            return SHM_OK;
            #endif;

            #ifdef __LINUX__
            int fd = shm_open(name, POSIX_O_RDWR | POSIX_O_CREAT | POSIX_O_TRUNC, POSIX_MODE_RW);
            if (fd < 0)
            {
                return SHM_ERROR;
            };
            if (ftruncate(fd, (i64)size) < 0)
            {
                close(fd);
                shm_unlink(name);
                return SHM_ERROR;
            };
            out.handle = (u64)fd;
            return SHM_OK;
            #endif;

            #ifdef __MACOS__
            int fd = shm_open(name, POSIX_O_RDWR | POSIX_O_CREAT | POSIX_O_TRUNC, POSIX_MODE_RW);
            if (fd < 0)
            {
                return SHM_ERROR;
            };
            if (ftruncate(fd, (i64)size) < 0)
            {
                close(fd);
                shm_unlink(name);
                return SHM_ERROR;
            };
            out.handle = (u64)fd;
            return SHM_OK;
            #endif;
        };

        // ====================================================
        //  Open an existing named shared memory region.
        //  Returns SHM_OK or SHM_ERROR.
        // ====================================================
        def shm_open_existing(SharedMem* out, byte* name, size_t size) -> int
        {
            out.view  = (void*)0;
            out.size  = size;
            out.owner = 0;

            #ifdef __WINDOWS__
            void* h = OpenFileMappingA(
                WIN_FILE_MAP_READ | WIN_FILE_MAP_WRITE,
                0,
                name
            );
            if ((u64)h == (u64)0)
            {
                return SHM_ERROR;
            };
            out.handle = (u64)h;
            return SHM_OK;
            #endif;

            #ifdef __LINUX__
            int fd = shm_open(name, POSIX_O_RDWR, POSIX_MODE_RW);
            if (fd < 0)
            {
                return SHM_ERROR;
            };
            out.handle = (u64)fd;
            return SHM_OK;
            #endif;

            #ifdef __MACOS__
            int fd = shm_open(name, POSIX_O_RDWR, POSIX_MODE_RW);
            if (fd < 0)
            {
                return SHM_ERROR;
            };
            out.handle = (u64)fd;
            return SHM_OK;
            #endif;
        };

        // ====================================================
        //  Map the region into the calling process's address space.
        //  access is SHM_READ, SHM_WRITE, or both.
        //  Returns the mapped pointer, or null on failure.
        // ====================================================
        def shm_map(SharedMem* shm, u32 access) -> void*
        {
            #ifdef __WINDOWS__
            u32 win_access = (access `& SHM_WRITE) != (u32)0
                             ? WIN_FILE_MAP_WRITE
                             : WIN_FILE_MAP_READ;
            void* view = MapViewOfFile(
                (void*)shm.handle,
                win_access,
                (u32)0, (u32)0,
                shm.size
            );
            if ((u64)view == (u64)0)
            {
                return (void*)0;
            };
            shm.view = view;
            return view;
            #endif;

            #ifdef __LINUX__
            int prot = POSIX_PROT_READ;
            if ((access `& SHM_WRITE) != (u32)0)
            {
                prot = prot | POSIX_PROT_WRITE;
            };
            void* view = mmap(
                (void*)0,
                shm.size,
                prot,
                POSIX_MAP_SHARED,
                (int)shm.handle,
                (i64)0
            );
            if ((u64)view == (u64)(void*)(i64)-1)
            {
                return (void*)0;
            };
            shm.view = view;
            return view;
            #endif;

            #ifdef __MACOS__
            int prot = POSIX_PROT_READ;
            if ((access `& SHM_WRITE) != (u32)0)
            {
                prot = prot | POSIX_PROT_WRITE;
            };
            void* view = mmap(
                (void*)0,
                shm.size,
                prot,
                POSIX_MAP_SHARED,
                (int)shm.handle,
                (i64)0
            );
            if ((u64)view == (u64)(void*)(i64)-1)
            {
                return (void*)0;
            };
            shm.view = view;
            return view;
            #endif;
        };

        // ====================================================
        //  Flush dirty pages back to the backing store.
        // ====================================================
        def shm_flush(SharedMem* shm) -> int
        {
            if ((u64)shm.view == (u64)0)
            {
                return SHM_ERROR;
            };

            #ifdef __WINDOWS__
            int ok = FlushViewOfFile(shm.view, shm.size);
            return ok != 0 ? SHM_OK : SHM_ERROR;
            #endif;

            #ifdef __LINUX__
            int rc = msync(shm.view, shm.size, POSIX_MS_SYNC);
            return rc == 0 ? SHM_OK : SHM_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = msync(shm.view, shm.size, POSIX_MS_SYNC);
            return rc == 0 ? SHM_OK : SHM_ERROR;
            #endif;
        };

        // ====================================================
        //  Unmap the region from this process's address space.
        //  Does not destroy the region; other processes keep their mappings.
        // ====================================================
        def shm_unmap(SharedMem* shm) -> int
        {
            if ((u64)shm.view == (u64)0)
            {
                return SHM_OK;
            };

            #ifdef __WINDOWS__
            int ok = UnmapViewOfFile(shm.view);
            shm.view = (void*)0;
            return ok != 0 ? SHM_OK : SHM_ERROR;
            #endif;

            #ifdef __LINUX__
            int rc = munmap(shm.view, shm.size);
            shm.view = (void*)0;
            return rc == 0 ? SHM_OK : SHM_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = munmap(shm.view, shm.size);
            shm.view = (void*)0;
            return rc == 0 ? SHM_OK : SHM_ERROR;
            #endif;
        };

        // ====================================================
        //  Close this process's handle to the region.
        //  Unmaps first if still mapped.
        //  The region remains accessible to other processes until
        //  shm_destroy is called.
        // ====================================================
        def shm_close(SharedMem* shm) -> int
        {
            shm_unmap(shm);

            #ifdef __WINDOWS__
            int ok = CloseHandle((void*)shm.handle);
            shm.handle = (u64)0;
            return ok != 0 ? SHM_OK : SHM_ERROR;
            #endif;

            #ifdef __LINUX__
            int rc = close((int)shm.handle);
            shm.handle = (u64)0;
            return rc == 0 ? SHM_OK : SHM_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = close((int)shm.handle);
            shm.handle = (u64)0;
            return rc == 0 ? SHM_OK : SHM_ERROR;
            #endif;
        };

        // ====================================================
        //  Destroy (unlink) the named region.
        //  Call this from the creator after all processes have
        //  called shm_close.
        //
        //  Windows: the kernel destroys the mapping automatically
        //  once the last handle is closed; shm_close is sufficient.
        //
        //  POSIX: shm_unlink removes the name from /dev/shm so no
        //  new processes can open it. Existing mappings stay valid
        //  until every process calls munmap.
        // ====================================================
        def shm_destroy(SharedMem* shm, byte* name) -> int
        {
            shm_close(shm);

            #ifdef __WINDOWS__
            return SHM_OK;
            #endif;

            #ifdef __LINUX__
            int rc = shm_unlink(name);
            return rc == 0 ? SHM_OK : SHM_ERROR;
            #endif;

            #ifdef __MACOS__
            int rc = shm_unlink(name);
            return rc == 0 ? SHM_OK : SHM_ERROR;
            #endif;
        };
    };
};

#endif;
