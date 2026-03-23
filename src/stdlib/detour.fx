// detour.fx
//
// Detour / inline hook library for Flux (x86-64, Windows).
//
// What a detour is:
//   A detour overwrites the first bytes of an existing function with an
//   unconditional JMP to your hook function.  Before writing those bytes,
//   it saves them — along with a JMP back to the instruction after the
//   patch site — into a small executable "trampoline" page.  Calling
//   through that trampoline therefore runs the original function's stolen
//   bytes and then falls through to the rest of the original, giving the
//   hook the ability to call the original cleanly.
//
// Memory layout after install():
//
//   [target function]
//   +0:  FF 25 00 00 00 00   JMP QWORD PTR [RIP+0]    <- absolute indirect JMP (6 bytes)
//   +6:  <hook addr 8 bytes>                           <- address of hook function
//   ...  (original bytes now unreachable directly)
//
//   [trampoline page]        (PAGE_EXECUTE_READWRITE, VirtualAlloc'd)
//   +0:  <stolen bytes>      STOLEN_BYTES (14 bytes, enough to cover the patch)
//   +14: FF 25 00 00 00 00   JMP QWORD PTR [RIP+0]    <- back to target+6
//   +20: <target+6 addr>     8-byte continuation address
//
// Patch size:
//   We always overwrite exactly PATCH_SIZE = 14 bytes at the target so that
//   the stolen-bytes region is guaranteed to hold at least one complete
//   instruction even on the widest x86-64 encodings.  A 6-byte RIP-relative
//   indirect JMP is written at offset 0; bytes 6-13 hold the 8-byte absolute
//   destination address.
//
// Calling convention:
//   The hook and the original must share the same signature.  The library is
//   generic over (ulong)->ulong for demonstration; adapt the function pointer
//   types for your target's actual signature.
//
// Usage:
//   Detour d;
//   d.install(@target_fn, @hook_fn);
//   ...
//   d.call_original((ulong)arg);   // calls original through trampoline
//   ...
//   d.uninstall();                 // restores the original bytes

#ifndef __FLUX_STANDARD_TYPES__
#import "types.fx", "datautils.fx";
#endif;

// ============================================================================
// Constants
// ============================================================================

// Size of the patch we stamp on the target function.
// 6-byte RIP-relative indirect JMP + 8-byte absolute address = 14 bytes.
int PATCH_SIZE = 14,

// Size of the trampoline page we allocate.
// stolen bytes (14) + 6-byte JMP + 8-byte addr = 28 bytes.  A full page is
// allocated; we only use the first 28 bytes.
    TRAMPOLINE_SIZE = 28;

// ============================================================================
// Detour object
//
// One Detour instance manages one hook.  install()/uninstall() are the
// public surface; call_original() lets the hook invoke the real function.
// ============================================================================

object Detour
{
    // Address of the function being hooked
    ulong target_addr,

    // Address of the hook function
          hook_addr,

    // Executable page holding the trampoline
          trampoline_page;

    // Saved copy of the PATCH_SIZE bytes we overwrote at target_addr.
    byte[14] saved;

    // True once install() has been called successfully
    bool installed;

    def __init() -> this
    {
        this.target_addr     = (ulong)0;
        this.hook_addr       = (ulong)0;
        this.trampoline_page = (ulong)0;
        this.installed       = false;
        return this;
    };

    def __exit() -> void
    {
        if (this.installed)
        {
            this.uninstall();
        };
        if (this.trampoline_page != (ulong)0)
        {
            VirtualFree(this.trampoline_page, (size_t)0, (u32)0x8000);
            this.trampoline_page = (ulong)0;
        };
        return;
    };

    // ------------------------------------------------------------------
    // install(target_addr, hook_addr)
    //
    // 1. Allocate a trampoline page (RWX).
    // 2. Copy the first PATCH_SIZE bytes of the target into the trampoline.
    // 3. Append a JMP back to target+PATCH_SIZE in the trampoline.
    // 4. Make the target page writable.
    // 5. Stamp the 6-byte indirect JMP + 8-byte hook address over the target.
    // 6. Flush the instruction cache.
    // ------------------------------------------------------------------
    def install(ulong target, ulong hook) -> bool
    {
        if (this.installed)
        {
            print("  [detour] already installed\n\0");
            return false;
        };

        this.target_addr = target;
        this.hook_addr   = hook;

        // --- Step 1: allocate trampoline page ---
        this.trampoline_page = VirtualAlloc((ulong)0, (size_t)4096, (u32)0x3000, (u32)0x40);

        if (this.trampoline_page == (ulong)0)
        {
            print("  [detour] VirtualAlloc failed\n\0");
            return false;
        };

        // --- Step 2: save stolen bytes ---
        byte* tgt = (byte*)target;
        for (int i = 0; i < PATCH_SIZE; i++)
        {
            this.saved[i] = tgt[i];
        };

        // --- Step 3: build trampoline ---
        // [+0 .. +13]  stolen bytes
        copy_bytes(this.trampoline_page, target, PATCH_SIZE);

        // [+14 .. +19]  JMP QWORD PTR [RIP+0]
        write_jmp_indirect(this.trampoline_page + (ulong)PATCH_SIZE);

        // [+20 .. +27]  absolute address of target+PATCH_SIZE (continuation)
        ulong continuation = target + (ulong)PATCH_SIZE;
        write_addr64(this.trampoline_page + (ulong)PATCH_SIZE + (ulong)6, continuation);

        // --- Step 4: make target page writable ---
        u32 old_protect = (u32)0;
        VirtualProtect(target, (size_t)PATCH_SIZE, (u32)0x40, @old_protect);

        // --- Step 5: stamp JMP + hook address onto target ---
        write_jmp_indirect(target);
        write_addr64(target + (ulong)6, hook);

        // --- Step 6: flush instruction cache ---
        FlushInstructionCache((ulong)0xFFFFFFFFFFFFFFFF, target, (size_t)PATCH_SIZE);

        this.installed = true;
        return true;
    };

    // ------------------------------------------------------------------
    // uninstall()
    //
    // Restore the original bytes to the target function.
    // ------------------------------------------------------------------
    def uninstall() -> bool
    {
        if (!this.installed)
        {
            print("  [detour] not installed\n\0");
            return false;
        };

        u32 old_protect = (u32)0;
        VirtualProtect(this.target_addr, (size_t)PATCH_SIZE, (u32)0x40, @old_protect);

        byte* tgt = (byte*)this.target_addr;
        for (int i = 0; i < PATCH_SIZE; i++)
        {
            tgt[i] = this.saved[i];
        };

        FlushInstructionCache((ulong)0xFFFFFFFFFFFFFFFF, this.target_addr, (size_t)PATCH_SIZE);

        this.installed = false;
        return true;
    };

    // ------------------------------------------------------------------
    // call_original(arg) -> ulong
    //
    // Call the original function through the trampoline.
    // The trampoline runs the stolen bytes then JMPs to target+PATCH_SIZE,
    // so the original executes as if it were never hooked.
    // ------------------------------------------------------------------
    def call_original(ulong arg) -> ulong
    {
        def{}* original(ulong) -> ulong = (byte*)this.trampoline_page;
        return original(arg);
    };
};