// fhf_engine.fx
//
// Flux Hotpatch Framework (FHF) — Patch Engine
//
// Applies and rolls back patches atomically under thread suspension.
//
// Apply sequence for one entry:
//   1. Resolve target address via fhf_sym
//   2. Verify payload signature (if FHF_FLAG_SIGNED)
//   3. Allocate trampoline slot; write new code into it
//   4. Suspend all threads
//   5. VirtualProtect(target, RWX)
//   6. Save original bytes (for rollback)
//   7. Write 14-byte JMP detour at target
//   8. Optionally NOP-fill bytes 14..saved_len
//   9. VirtualProtect(target, restore original protection)
//  10. FlushInstructionCache
//  11. Resume all threads
//  12. Record patch state
//
// Rollback restores the original bytes in the same way.
//
// API:
//   fhf_engine_apply(mgr, entry_hdr, payload, payload_size, rec_idx) -> int
//   fhf_engine_rollback(mgr, rec_idx)                                  -> int

#ifndef FHF_ENGINE
#def FHF_ENGINE 1;

#ifndef FHF_TYPES
#import "fhf\\fhf_types.fx";
#endif;
#ifndef FHF_SYM
#import "fhf\\fhf_sym.fx";
#endif;
#ifndef FHF_TRAMP
#import "fhf\\fhf_tramp.fx";
#endif;
#ifndef FHF_THREADS
#import "fhf\\fhf_threads.fx";
#endif;
#ifndef FHF_CRYPTO
#import "fhf\\fhf_crypto.fx";
#endif;
#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

// ============================================================================
//  Internal helpers
// ============================================================================

// Write one byte, no protection override (caller must have made the page RWX).
def _fhf_write_byte(ulong addr, byte val) -> void
{
    byte* p = (byte*)addr;
    *p = val;
};

// Write the 14-byte detour JMP at target_addr, pointing to trampoline.
def _fhf_write_detour(ulong target_addr, ulong tramp_addr) -> void
{
    byte* p = (byte*)target_addr;
    p[0] = (byte)0xFF;
    p[1] = (byte)0x25;
    p[2] = (byte)0x00;
    p[3] = (byte)0x00;
    p[4] = (byte)0x00;
    p[5] = (byte)0x00;
    p[6]  = (byte)(tramp_addr        & (ulong)0xFF);
    p[7]  = (byte)((tramp_addr >> 8)  & (ulong)0xFF);
    p[8]  = (byte)((tramp_addr >> 16) & (ulong)0xFF);
    p[9]  = (byte)((tramp_addr >> 24) & (ulong)0xFF);
    p[10] = (byte)((tramp_addr >> 32) & (ulong)0xFF);
    p[11] = (byte)((tramp_addr >> 40) & (ulong)0xFF);
    p[12] = (byte)((tramp_addr >> 48) & (ulong)0xFF);
    p[13] = (byte)((tramp_addr >> 56) & (ulong)0xFF);
};

// NOP-fill bytes [target+14 .. target+saved_len).
def _fhf_nop_fill(ulong target_addr, int saved_len) -> void
{
    int i;
    byte* p = (byte*)target_addr;
    for (i = FHF_TRAMP_SIZE; i < saved_len; i++)
    {
        p[i] = (byte)0x90; // NOP
    };
};

// ============================================================================
//  Apply
// ============================================================================

// Apply one patch entry.  The resolved patch record is written into
// mgr.records[rec_idx].
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_engine_apply(FHFManager*     mgr,
                     FHFEntryHeader* entry_hdr,
                     byte*           payload,
                     int             payload_size,
                     int             rec_idx) -> int
{
    if (mgr == (FHFManager*)0 | entry_hdr == (FHFEntryHeader*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };
    if (rec_idx < 0 | rec_idx >= FHF_MAX_ENTRIES)
    {
        return FHF_ERR_INVALID_ARG;
    };

    FHFPatchRecord* rec = @mgr.records[rec_idx];

    if (rec.state == (u32)FHF_STATE_APPLIED)
    {
        return FHF_ERR_ALREADY_PATCHED;
    };

    // --- 1. Verify signature ---
    if ((entry_hdr.flags & FHF_FLAG_SIGNED) != (u32)0)
    {
        if (!fhf_verify_entry(mgr, entry_hdr, payload, payload_size))
        {
            return FHF_ERR_BAD_SIG;
        };
    };

    // --- 2. Resolve target ---
    ulong target_addr = (ulong)0;
    int sym_rc = fhf_resolve(entry_hdr, @target_addr);
    if (sym_rc != FHF_OK)
    {
        return sym_rc;
    };

    // --- 3. Allocate trampoline and write new code into it ---
    int tramp_idx = fhf_tramp_alloc(@mgr.tramp_pool, target_addr);
    if (tramp_idx < 0)
    {
        return tramp_idx; // propagate FHF_ERR_TRAMP_POOL_FULL
    };

    // Write payload into trampoline slot's code location
    ulong tramp_code = fhf_tramp_addr(@mgr.tramp_pool, tramp_idx);
    byte* tdst = (byte*)tramp_code;
    int i;
    for (i = 0; i < payload_size; i++)
    {
        tdst[i] = payload[i];
    };

    #ifdef __WINDOWS__
    FlushInstructionCache((ulong)0xFFFFFFFFFFFFFFFF, tramp_code,
                          (size_t)payload_size);
    #endif;

    // --- 4. Suspend all threads ---
    int susp_rc = fhf_suspend_all();
    if (susp_rc != FHF_OK)
    {
        fhf_tramp_free(@mgr.tramp_pool, tramp_idx);
        return susp_rc;
    };

    // --- 5. Make target page RWX ---
    #ifdef __WINDOWS__
    u32 old_protect = (u32)0;
    VirtualProtect(target_addr, (size_t)FHF_TRAMP_SIZE, (u32)0x40, @old_protect);
    #endif;

    // --- 6. Save original bytes ---
    int save_len = FHF_TRAMP_SIZE;
    if (save_len > FHF_SAVED_BYTES_MAX) { save_len = FHF_SAVED_BYTES_MAX; };
    byte* target_bytes = (byte*)target_addr;
    for (i = 0; i < save_len; i++)
    {
        rec.saved_bytes[i] = target_bytes[i];
    };
    rec.saved_bytes_len = (u32)save_len;

    // Also copy into entry_hdr for bundle serialization
    for (i = 0; i < save_len; i++)
    {
        entry_hdr.saved_bytes[i] = target_bytes[i];
    };
    entry_hdr.saved_bytes_len = (u32)save_len;

    // --- 7. Write detour JMP at target ---
    _fhf_write_detour(target_addr, tramp_code);

    // --- 8. NOP-fill if requested ---
    if ((entry_hdr.flags & FHF_FLAG_NOP_FILL) != (u32)0)
    {
        _fhf_nop_fill(target_addr, save_len);
    };

    // --- 9. Restore protection ---
    #ifdef __WINDOWS__
    u32 dummy = (u32)0;
    VirtualProtect(target_addr, (size_t)FHF_TRAMP_SIZE, old_protect, @dummy);

    // --- 10. Flush instruction cache ---
    FlushInstructionCache((ulong)0xFFFFFFFFFFFFFFFF, target_addr,
                          (size_t)FHF_TRAMP_SIZE);
    #endif;

    // --- 11. Resume threads ---
    fhf_resume_all();

    // --- 12. Record state ---
    rec.state        = (u32)FHF_STATE_APPLIED;
    rec.target_addr  = target_addr;
    rec.tramp_addr   = tramp_code;
    rec.tramp_idx    = tramp_idx;
    rec.flags        = entry_hdr.flags;

    return FHF_OK;
};

// ============================================================================
//  Rollback
// ============================================================================

// Restore the original bytes at the patch site.
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_engine_rollback(FHFManager* mgr, int rec_idx) -> int
{
    if (mgr == (FHFManager*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };
    if (rec_idx < 0 | rec_idx >= FHF_MAX_ENTRIES)
    {
        return FHF_ERR_INVALID_ARG;
    };

    FHFPatchRecord* rec = @mgr.records[rec_idx];

    if (rec.state != (u32)FHF_STATE_APPLIED)
    {
        return FHF_ERR_NOT_PATCHED;
    };

    if ((rec.flags & FHF_FLAG_ROLLBACK_OK) == (u32)0)
    {
        // Entry was not created with rollback support
        return FHF_ERR_NOT_PATCHED;
    };

    ulong target_addr = rec.target_addr;
    int restore_len   = (int)rec.saved_bytes_len;

    // Suspend
    int susp_rc = fhf_suspend_all();
    if (susp_rc != FHF_OK)
    {
        return susp_rc;
    };

    #ifdef __WINDOWS__
    u32 old_protect = (u32)0;
    VirtualProtect(target_addr, (size_t)restore_len, (u32)0x40, @old_protect);
    #endif;

    // Restore original bytes
    byte* p = (byte*)target_addr;
    int i;
    for (i = 0; i < restore_len; i++)
    {
        p[i] = rec.saved_bytes[i];
    };

    #ifdef __WINDOWS__
    u32 dummy = (u32)0;
    VirtualProtect(target_addr, (size_t)restore_len, old_protect, @dummy);
    FlushInstructionCache((ulong)0xFFFFFFFFFFFFFFFF, target_addr,
                          (size_t)restore_len);
    #endif;

    fhf_resume_all();

    // Free trampoline slot
    if (rec.tramp_idx >= 0)
    {
        fhf_tramp_free(@mgr.tramp_pool, rec.tramp_idx);
    };

    rec.state = (u32)FHF_STATE_ROLLED_BACK;
    return FHF_OK;
};

#endif; // FHF_ENGINE
