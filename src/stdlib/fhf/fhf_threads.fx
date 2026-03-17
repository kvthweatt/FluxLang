// fhf_threads.fx
//
// Flux Hotpatch Framework (FHF) — Thread Suspension Layer
//
// Before any bytes at a patch site are modified, every thread other than
// the patching thread must be guaranteed not to be executing inside the
// region being written.  This module provides:
//
//   fhf_suspend_all()   — suspend every thread except the caller
//   fhf_resume_all()    — resume every previously suspended thread
//
// Implementation uses the Win32 Toolhelp snapshot API (Windows) or
// SIGSTOP/SIGCONT via /proc/self/task (Linux).  The caller must ensure
// fhf_resume_all() is always called after fhf_suspend_all(), even on error
// (use a cleanup flag).
//
// Thread list capacity is capped at FHF_MAX_THREADS.  If a process has
// more threads than this the call returns FHF_ERR_THREAD_SUSPEND.

#ifndef FHF_THREADS
#def FHF_THREADS 1;

#ifndef FHF_TYPES
#import "fhf\\fhf_types.fx";
#endif;

// Forward declarations
def _fhf_get_pid() -> u32,
    fhf_resume_all() -> void;

const int FHF_MAX_THREADS = 512;

// ============================================================================
//  Windows implementation via Toolhelp32
// ============================================================================

#ifdef __WINDOWS__

extern
{
    def !!
        CreateToolhelp32Snapshot(u32, u32)  -> ulong,  // returns HANDLE
        Thread32First(ulong, void*)          -> int,
        Thread32Next(ulong, void*)           -> int,
        OpenThread(u32, int, u32)            -> ulong,
        SuspendThread(ulong)                 -> u32,
        ResumeThread(ulong)                  -> u32,
        GetCurrentThreadId()                 -> u32,
        CloseHandle(ulong)                   -> int;
};

// TH32CS_SNAPTHREAD = 0x00000004
const u32 TH32CS_SNAPTHREAD = 0x00000004;

// THREAD_SUSPEND_RESUME = 0x0002
const u32 THREAD_SUSPEND_RESUME_ACCESS = 0x0002;

// THREADENTRY32 layout (simplified to what we need):
//   DWORD dwSize        (4)
//   DWORD cntUsage      (4)
//   DWORD th32ThreadID  (4)
//   DWORD th32OwnerProcessID (4)
//   ... (more fields, 28 bytes total)
const int THREADENTRY32_SIZE = 28;

// Suspended thread handle list (module-level state, protected by the
// caller ensuring single-threaded use of fhf_suspend_all/resume_all).
// Allocated as a heap block of FHF_MAX_THREADS * 8 bytes on first use.
global ulong* _fhf_suspended_handles = (ulong*)0;
global int _fhf_suspended_count = 0;

// Ensure the handle buffer is allocated.  Returns false on alloc failure.
def _fhf_ensure_handle_buf() -> bool
{
    if (_fhf_suspended_handles != (ulong*)0) { return true; };
    _fhf_suspended_handles = (ulong*)malloc((size_t)(FHF_MAX_THREADS * 8));
    return _fhf_suspended_handles != (ulong*)0;
};

// Suspend all threads in this process except the calling thread.
// Returns FHF_OK or FHF_ERR_THREAD_SUSPEND.
def fhf_suspend_all() -> int
{
    _fhf_suspended_count = 0;

    if (!_fhf_ensure_handle_buf())
    {
        return FHF_ERR_THREAD_SUSPEND;
    };

    u32 self_id = GetCurrentThreadId();

    // Take a snapshot of all threads in the system for this process
    ulong snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, (u32)0);
    if (snap == (ulong)0xFFFFFFFFFFFFFFFF) // INVALID_HANDLE_VALUE
    {
        return FHF_ERR_THREAD_SUSPEND;
    };

    // THREADENTRY32 on stack — 28 bytes, zero-init
    byte[28] entry_buf;
    int i;
    for (i = 0; i < 28; i++) { entry_buf[i] = (byte)0; };
    // Set dwSize field
    entry_buf[0] = (byte)28;

    if (!Thread32First(snap, (void*)@entry_buf[0]))
    {
        CloseHandle(snap);
        return FHF_ERR_THREAD_SUSPEND;
    };

    // We need the current process ID to filter by owner
    // GetCurrentProcessId is declared inline below
    u32 self_pid = _fhf_get_pid();

    int ok = 1;
    do
    {
        // th32OwnerProcessID at byte offset 12
        u32 owner_pid = ((u32)entry_buf[12])        |
                        ((u32)entry_buf[13] << 8)   |
                        ((u32)entry_buf[14] << 16)  |
                        ((u32)entry_buf[15] << 24);

        // th32ThreadID at byte offset 8
        u32 tid = ((u32)entry_buf[8])       |
                  ((u32)entry_buf[9]  << 8) |
                  ((u32)entry_buf[10] << 16)|
                  ((u32)entry_buf[11] << 24);

        if (owner_pid == self_pid & tid != self_id)
        {
            if (_fhf_suspended_count >= FHF_MAX_THREADS)
            {
                ok = 0;
            }
            else
            {
                ulong th = OpenThread(THREAD_SUSPEND_RESUME_ACCESS, 0, tid);
                if (th != (ulong)0)
                {
                    SuspendThread(th);
                    ulong* slot = _fhf_suspended_handles + _fhf_suspended_count;
                    *slot = th;
                    _fhf_suspended_count = _fhf_suspended_count + 1;
                };
            };
        };

        // Zero the size field then re-set it for next call
        entry_buf[0] = (byte)28;
    }
    while (Thread32Next(snap, (void*)@entry_buf[0]) & ok != 0);

    CloseHandle(snap);

    if (ok == 0)
    {
        // Too many threads — resume what we suspended and fail
        fhf_resume_all();
        return FHF_ERR_THREAD_SUSPEND;
    };

    return FHF_OK;
};

// Resume all threads suspended by the last fhf_suspend_all() call.
def fhf_resume_all() -> void
{
    if (_fhf_suspended_handles == (ulong*)0) { return; };
    int i;
    for (i = 0; i < _fhf_suspended_count; i++)
    {
        ulong* slot = _fhf_suspended_handles + i;
        ulong th = *slot;
        if (th != (ulong)0)
        {
            ResumeThread(th);
            CloseHandle(th);
            *slot = (ulong)0;
        };
    };
    _fhf_suspended_count = 0;
};

extern { def !! GetCurrentProcessId() -> u32; };

def _fhf_get_pid() -> u32
{
    return GetCurrentProcessId();
};

#endif; // __WINDOWS__

// ============================================================================
//  Linux / macOS stub
//  Full implementation would use tgkill(SIGSTOP) via /proc/self/task.
//  Provided as a safe no-op for cross-platform compilation.
// ============================================================================

#ifdef __LINUX__
global int _fhf_suspended_count = 0;

def fhf_suspend_all() -> int
{
    // TODO: enumerate /proc/self/task, send SIGSTOP to each tid != gettid()
    return FHF_OK;
};

def fhf_resume_all() -> void
{
    // TODO: send SIGCONT to all previously stopped tids
};
#endif;

#ifdef __MACOS__
global int _fhf_suspended_count = 0;

def fhf_suspend_all() -> int
{
    return FHF_OK;
};

def fhf_resume_all() -> void
{
};
#endif;

#endif; // FHF_THREADS
