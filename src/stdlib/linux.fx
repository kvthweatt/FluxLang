// Author: Karac V. Thweatt

// redlinux.fx - Flux Linux System Primitives
// Linux-specific syscall wrappers, file I/O, signals, epoll, process control.
// No X11. GUI is in redwayland.fx.

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef __LINUX_INTERFACE__
#def __LINUX_INTERFACE__ 1;

// ============================================================================
// LINUX EXTERN DECLARATIONS
// ============================================================================

#ifdef __LINUX__
extern
{
    def !!
    // Process
        getpid()                                    -> int,
        getppid()                                   -> int,
        getuid()                                    -> u32,
        getgid()                                    -> u32,
        fork()                                      -> int,
        execve(byte*, byte**, byte**)               -> int,
        waitpid(int, int*, int)                     -> int,
        exit(int)                                   -> void,
        abort()                                     -> void,

    // File I/O
        open(byte*, int, u32)                       -> int,
        close(int)                                  -> int,
        read(int, void*, size_t)                    -> i64,
        write(int, void*, size_t)                   -> i64,
        lseek(int, i64, int)                        -> i64,
        ftruncate(int, i64)                         -> int,
        memfd_create(byte*, u32)                    -> int,
        unlink(byte*)                               -> int,
        rename(byte*, byte*)                        -> int,
        stat(byte*, void*)                          -> int,
        fstat(int, void*)                           -> int,
        dup(int)                                    -> int,
        dup2(int, int)                              -> int,
        pipe(int*)                                  -> int,
        fcntl(int, int, int)                        -> int,
        ioctl(int, u64, void*)                      -> int,

    // Memory
        mmap(u64, size_t, int, int, int, i64)       -> u64,
        munmap(u64, size_t)                         -> int,
        mprotect(u64, size_t, int)                  -> int,
        madvise(u64, size_t, int)                   -> int,
        msync(u64, size_t, int)                     -> int,
        brk(u64)                                    -> u64,

    // Sockets
        socket(int, int, int)                       -> int,
        bind(int, void*, u32)                       -> int,
        connect(int, void*, u32)                    -> int,
        listen(int, int)                            -> int,
        accept(int, void*, u32*)                    -> int,
        send(int, void*, size_t, int)               -> i64,
        recv(int, void*, size_t, int)               -> i64,
        sendmsg(int, void*, int)                    -> i64,
        recvmsg(int, void*, int)                    -> i64,
        setsockopt(int, int, int, void*, u32)       -> int,
        getsockopt(int, int, int, void*, u32*)      -> int,
        shutdown(int, int)                          -> int,

    // Epoll
        epoll_create1(int)                          -> int,
        epoll_ctl(int, int, int, void*)             -> int,
        epoll_wait(int, void*, int, int)            -> int,

    // Signals
        kill(int, int)                              -> int,
        signal(int, void*)                          -> void*,
        sigaction(int, void*, void*)                -> int,
        raise(int)                                  -> int,

    // Time
        nanosleep(void*, void*)                     -> int,
        clock_gettime(int, void*)                   -> int,
        gettimeofday(void*, void*)                  -> int,

    // Environment
        getenv(byte*)                               -> byte*,
        setenv(byte*, byte*, int)                   -> int,
        unsetenv(byte*)                             -> int,

    // String / misc
        strerror(int)                               -> byte*,
        poll(void*, u32, int)                       -> int,

    // Directory
        mkdir(byte*, u32)                           -> int,
        rmdir(byte*)                                -> int,
        getcwd(byte*, size_t)                       -> byte*,
        chdir(byte*)                                -> int;
};
#endif;

// ============================================================================
// CONSTANTS AND STRUCTURES
// ============================================================================

namespace standard
{
    namespace system
    {
        namespace linux
        {
            // open() flags
            enum OpenFlags
            {
                O_RDONLY   = 0x000,
                O_WRONLY   = 0x001,
                O_RDWR     = 0x002,
                O_CREAT    = 0x040,
                O_EXCL     = 0x080,
                O_TRUNC    = 0x200,
                O_APPEND   = 0x400,
                O_NONBLOCK = 0x800,
                O_CLOEXEC  = 0x80000
            };

            // lseek() whence
            enum SeekWhence
            {
                SEEK_SET = 0,
                SEEK_CUR = 1,
                SEEK_END = 2
            };

            // mmap() prot flags
            enum MmapProt
            {
                PROT_NONE  = 0x0,
                PROT_READ  = 0x1,
                PROT_WRITE = 0x2,
                PROT_EXEC  = 0x4
            };

            // mmap() map flags
            enum MmapFlags
            {
                MAP_SHARED    = 0x01,
                MAP_PRIVATE   = 0x02,
                MAP_ANONYMOUS = 0x20,
                MAP_FIXED     = 0x10
            };

            // socket() domain
            enum SockDomain
            {
                AF_UNIX  = 1,
                AF_INET  = 2,
                AF_INET6 = 10
            };

            // socket() type
            enum SockType
            {
                SOCK_STREAM   = 1,
                SOCK_DGRAM    = 2,
                SOCK_NONBLOCK = 0x800,
                SOCK_CLOEXEC  = 0x80000
            };

            // epoll_ctl() op
            enum EpollOp
            {
                EPOLL_CTL_ADD = 1,
                EPOLL_CTL_DEL = 2,
                EPOLL_CTL_MOD = 3
            };

            // epoll event flags
            enum EpollEvents
            {
                EPOLLIN  = 0x001,
                EPOLLOUT = 0x004,
                EPOLLERR = 0x008,
                EPOLLHUP = 0x010,
                EPOLLET  = 0x80000000
            };

            // signal numbers
            enum Signal
            {
                SIGHUP  = 1,
                SIGINT  = 2,
                SIGQUIT = 3,
                SIGILL  = 4,
                SIGABRT = 6,
                SIGFPE  = 8,
                SIGKILL = 9,
                SIGSEGV = 11,
                SIGPIPE = 13,
                SIGALRM = 14,
                SIGTERM = 15,
                SIGUSR1 = 10,
                SIGUSR2 = 12
            };

            // clock_gettime() clock ids
            enum ClockId
            {
                CLOCK_REALTIME  = 0,
                CLOCK_MONOTONIC = 1,
                CLOCK_PROCESS   = 2,
                CLOCK_THREAD    = 3
            };

            // fcntl() commands
            enum FcntlCmd
            {
                F_GETFD  = 1,
                F_SETFD  = 2,
                F_GETFL  = 3,
                F_SETFL  = 4,
                F_GETLK  = 5,
                F_SETLK  = 6,
                F_SETLKW = 7
            };

            // ================================================================
            // STRUCTURES
            // ================================================================

            struct timespec
            {
                i64 tv_sec;
                i64 tv_nsec;
            };

            struct timeval
            {
                i64 tv_sec;
                i64 tv_usec;
            };

            struct epoll_event
            {
                u32 events;
                u64 evt_data;
            };

            struct sockaddr_un
            {
                u16       family;
                byte[108] path;
            };

            struct sockaddr_in
            {
                u16    family;
                u16    port;
                u32    addr;
                byte[8] pad;
            };

            struct msghdr
            {
                void*  msg_name;
                u32    msg_namelen;
                void*  msg_iov;
                size_t msg_iovlen;
                void*  msg_control;
                size_t msg_controllen;
                int    msg_flags;
            };

            struct iovec
            {
                void*  iov_base;
                size_t iov_len;
            };

            struct cmsghdr
            {
                size_t cmsg_len;
                int    cmsg_level;
                int    cmsg_type;
            };

            struct stat_t
            {
                u64 st_dev;
                u64 st_ino;
                u32 st_mode;
                u32 st_nlink;
                u32 st_uid;
                u32 st_gid;
                u64 st_rdev;
                i64 st_size;
                i64 st_blksize;
                i64 st_blocks;
            };

            // ================================================================
            // HELPERS
            // ================================================================

            // Sleep for milliseconds
            def sleep_ms(int ms) -> void
            {
                timespec ts;
                ts.tv_sec  = (i64)(ms / 1000);
                ts.tv_nsec = (i64)((ms % 1000) * 1000000);
                nanosleep((void*)@ts, (void*)0);
                return;
            };

            // Sleep for microseconds
            def sleep_us(int us) -> void
            {
                timespec ts;
                ts.tv_sec  = (i64)(us / 1000000);
                ts.tv_nsec = (i64)((us % 1000000) * 1000);
                nanosleep((void*)@ts, (void*)0);
                return;
            };

            // Get monotonic time in milliseconds
            def time_ms() -> i64
            {
                timespec ts;
                clock_gettime((int)ClockId.CLOCK_MONOTONIC, (void*)@ts);
                return ts.tv_sec * (i64)1000 + ts.tv_nsec / (i64)1000000;
            };

            // Get monotonic time in microseconds
            def time_us() -> i64
            {
                timespec ts;
                clock_gettime((int)ClockId.CLOCK_MONOTONIC, (void*)@ts);
                return ts.tv_sec * (i64)1000000 + ts.tv_nsec / (i64)1000;
            };

            // Send a file descriptor over a Unix socket via SCM_RIGHTS
            def send_fd(int sock, int fd_to_send) -> bool
            {
                byte[1] dummy;
                dummy[0] = (byte)0;

                iovec iov;
                iov.iov_base = (void*)@dummy;
                iov.iov_len  = (size_t)1;

                byte[24] cmsg_buf;
                memset((void*)@cmsg_buf, 0, (size_t)24);
                cmsghdr* cm   = (cmsghdr*)@cmsg_buf;
                cm.cmsg_len   = (size_t)20;
                cm.cmsg_level = 1;   // SOL_SOCKET
                cm.cmsg_type  = 1;   // SCM_RIGHTS
                int* fd_ptr   = (int*)(@cmsg_buf + sizeof(cmsghdr));
                fd_ptr[0]     = fd_to_send;

                msghdr msg;
                msg.msg_name       = (void*)0;
                msg.msg_namelen    = (u32)0;
                msg.msg_iov        = (void*)@iov;
                msg.msg_iovlen     = (size_t)1;
                msg.msg_control    = (void*)@cmsg_buf;
                msg.msg_controllen = (size_t)24;
                msg.msg_flags      = 0;

                i64 r = sendmsg(sock, (void*)@msg, 0);
                return r >= (i64)0;
            };
        };
    };
};

#endif;
