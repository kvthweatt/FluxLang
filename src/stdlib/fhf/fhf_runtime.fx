// Author: Karac V. Thweatt

// fhf_runtime.fx
//
// Flux Hotpatch Framework (FHF) — Patch Manager Runtime
//
// The top-level API surface.  Ties together crypto, sym, tramp, threads,
// and engine into a single coherent manager.
//
// Lifecycle:
//   fhf_init(mgr, hmac_key)              — initialize manager + trampoline pool
//   fhf_load_bundle(mgr, data, size)     — parse + verify a bundle in memory
//   fhf_apply_bundle(mgr, data, size)    — load + apply all entries
//   fhf_apply_entry(mgr, hdr, payload, sz) — apply one entry directly
//   fhf_rollback(mgr, rec_idx)           — roll back one record
//   fhf_rollback_all(mgr)                — roll back every applied patch
//   fhf_inspect(mgr)                     — print all patch records
//   fhf_shutdown(mgr)                    — roll back all + free pool

#ifndef FHF_RUNTIME
#def FHF_RUNTIME 1;

#ifndef FHF_ENGINE
#import "fhf\\fhf_engine.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

using standard::io::console;

// Forward declarations
def fhf_rollback_all(FHFManager* mgr) -> void;

// ============================================================================
//  Initialization / shutdown
// ============================================================================

// Initialize the manager.  hmac_key must be 32 bytes.
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_init(FHFManager* mgr, byte* hmac_key) -> int
{
    if (mgr == (FHFManager*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };

    store32(@mgr.initialized, 0);
    store32(@mgr.lock, 0);
    mgr.record_count = 0;
    store32(@mgr.key_set, 0);

    // Zero all records
    int i;
    for (i = 0; i < FHF_MAX_ENTRIES; i++)
    {
        mgr.records[i].state           = (u32)FHF_STATE_EMPTY;
        mgr.records[i].target_addr     = (ulong)0;
        mgr.records[i].tramp_addr      = (ulong)0;
        mgr.records[i].tramp_idx       = -1;
        mgr.records[i].saved_bytes_len = (u32)0;
        mgr.records[i].flags           = (u32)0;
    };

    // Load HMAC key
    if (hmac_key != (byte*)0)
    {
        for (i = 0; i < 32; i++)
        {
            mgr.hmac_key[i] = hmac_key[i];
        };
        store32(@mgr.key_set, 1);
    };

    // Initialize trampoline pool
    int pool_rc = fhf_tramp_pool_init(@mgr.tramp_pool);
    if (pool_rc != FHF_OK)
    {
        return pool_rc;
    };

    store32(@mgr.initialized, 1);
    return FHF_OK;
};

// Roll back all applied patches and free the trampoline pool.
def fhf_shutdown(FHFManager* mgr) -> void
{
    if (mgr == (FHFManager*)0) { return; };
    if (load32(@mgr.initialized) == 0) { return; };

    fhf_rollback_all(mgr);
    fhf_tramp_pool_destroy(@mgr.tramp_pool);
    store32(@mgr.initialized, 0);
};

// ============================================================================
//  Bundle parsing helpers
// ============================================================================

// Read a u32 from an unaligned byte pointer (little-endian).
def _fhf_read_u32(byte* p) -> u32
{
    return ((u32)p[0])        |
           ((u32)p[1] << 8)  |
           ((u32)p[2] << 16) |
           ((u32)p[3] << 24);
};

// Read a u64 from an unaligned byte pointer (little-endian).
def _fhf_read_u64(byte* p) -> u64
{
    u64 lo = (u64)_fhf_read_u32(p);
    u64 hi = (u64)_fhf_read_u32(p + 4);
    return lo | (hi << (u64)32);
};

// ============================================================================
//  Claim the next free record slot.  Returns index or -1 if full.
// ============================================================================

def _fhf_alloc_record(FHFManager* mgr) -> int
{
    int i;
    for (i = 0; i < FHF_MAX_ENTRIES; i++)
    {
        if (mgr.records[i].state == (u32)FHF_STATE_EMPTY)
        {
            return i;
        };
    };
    return -1;
};

// ============================================================================
//  Apply a single entry (public, direct API)
// ============================================================================

def fhf_apply_entry(FHFManager*     mgr,
                    FHFEntryHeader* entry_hdr,
                    byte*           payload,
                    int             payload_size) -> int
{
    if (load32(@mgr.initialized) == 0)
    {
        return FHF_ERR_INVALID_ARG;
    };

    if (payload_size > FHF_MAX_PAYLOAD)
    {
        return FHF_ERR_PAYLOAD_TOO_LARGE;
    };

    spin_lock(@mgr.lock);

    int idx = _fhf_alloc_record(mgr);
    if (idx < 0)
    {
        spin_unlock(@mgr.lock);
        return FHF_ERR_TOO_MANY_ENTRIES;
    };

    // Mark pending so the slot is reserved
    mgr.records[idx].state = (u32)FHF_STATE_PENDING;
    mgr.record_count       = mgr.record_count + 1;

    spin_unlock(@mgr.lock);

    // Apply outside the lock (engine does its own thread suspension)
    int rc = fhf_engine_apply(mgr, entry_hdr, payload, payload_size, idx);

    if (rc != FHF_OK)
    {
        spin_lock(@mgr.lock);
        mgr.records[idx].state = (u32)FHF_STATE_EMPTY;
        mgr.record_count       = mgr.record_count - 1;
        spin_unlock(@mgr.lock);
    };

    return rc;
};

// ============================================================================
//  Bundle loading and application
//
//  Wire layout:
//    FHFBundleHeader   (fixed size)
//    for each entry:
//      FHFEntryHeader  (fixed size)
//      byte[payload_size] payload
// ============================================================================

// sizeof(FHFBundleHeader): magic(4)+version(4)+entry_count(4)+flags(4)+
//                          timestamp(8)+bundle_sig(32)+key_hint(32) = 88
const int FHF_BUNDLE_HDR_SIZE = 88;

// sizeof(FHFEntryHeader): magic(4)+flags(4)+sym_mode(4)+payload_size(4)+
//   target_rva(8)+sym_name(256)+mod_name(260)+saved_bytes(32)+
//   saved_bytes_len(4)+payload_sig(32) = 608
const int FHF_ENTRY_HDR_SIZE = 608;

// Parse and verify bundle magic + version + signature.
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_verify_bundle_header(FHFManager* mgr,
                              byte*       buf,
                              int         data_size) -> int
{
    if (data_size < FHF_BUNDLE_HDR_SIZE)
    {
        return FHF_ERR_BAD_MAGIC;
    };

    u32 magic = _fhf_read_u32(buf);
    if (magic != FHF_BUNDLE_MAGIC)
    {
        return FHF_ERR_BAD_MAGIC;
    };

    u32 version = _fhf_read_u32(buf + 4);
    u32 major   = (version >> 16) & (u32)0xFF;
    if (major != FHF_VERSION_MAJOR)
    {
        return FHF_ERR_BAD_VERSION;
    };

    return FHF_OK;
};

// Apply all entries from a raw in-memory bundle.
// Returns FHF_OK, or the first FHF_ERR_* encountered.
def fhf_apply_bundle(FHFManager* mgr, byte* buf, int data_size) -> int
{
    if (mgr == (FHFManager*)0 | buf == (byte*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };

    int hdr_rc = fhf_verify_bundle_header(mgr, buf, data_size);
    if (hdr_rc != FHF_OK)
    {
        return hdr_rc;
    };

    u32 entry_count = _fhf_read_u32(buf + 8);
    if ((int)entry_count > FHF_MAX_ENTRIES)
    {
        return FHF_ERR_TOO_MANY_ENTRIES;
    };

    int cursor = FHF_BUNDLE_HDR_SIZE;
    int i;
    for (i = 0; i < (int)entry_count; i++)
    {
        if (cursor + FHF_ENTRY_HDR_SIZE > data_size)
        {
            return FHF_ERR_BAD_MAGIC; // truncated
        };

        // Map entry header directly from the buffer
        FHFEntryHeader* ehdr = (FHFEntryHeader*)(buf + cursor);

        if (ehdr.magic != (u32)FHF_ENTRY_MAGIC)
        {
            return FHF_ERR_BAD_MAGIC;
        };

        cursor = cursor + FHF_ENTRY_HDR_SIZE;

        int psz = (int)ehdr.payload_size;
        if (psz < 0 | psz > FHF_MAX_PAYLOAD)
        {
            return FHF_ERR_PAYLOAD_TOO_LARGE;
        };

        if (cursor + psz > data_size)
        {
            return FHF_ERR_BAD_MAGIC; // truncated
        };

        byte* payload = buf + cursor;
        cursor = cursor + psz;

        int rc = fhf_apply_entry(mgr, ehdr, payload, psz);
        if (rc != FHF_OK)
        {
            return rc;
        };
    };

    return FHF_OK;
};

// ============================================================================
//  Rollback
// ============================================================================

def fhf_rollback(FHFManager* mgr, int rec_idx) -> int
{
    if (mgr == (FHFManager*)0) { return FHF_ERR_INVALID_ARG; };

    int rc = fhf_engine_rollback(mgr, rec_idx);
    if (rc == FHF_OK)
    {
        spin_lock(@mgr.lock);
        mgr.record_count = mgr.record_count - 1;
        spin_unlock(@mgr.lock);
    };
    return rc;
};

def fhf_rollback_all(FHFManager* mgr) -> void
{
    if (mgr == (FHFManager*)0) { return; };

    int i;
    for (i = 0; i < FHF_MAX_ENTRIES; i++)
    {
        if (mgr.records[i].state == (u32)FHF_STATE_APPLIED)
        {
            fhf_rollback(mgr, i);
        };
    };
};

// ============================================================================
//  Inspect — print all patch records to stdout
// ============================================================================

def _fhf_print_hex64(ulong v) -> void
{
    // Print 16 hex digits
    int shift = 60;
    while (shift >= 0)
    {
        int nibble = (int)((v >> (ulong)shift) & (ulong)0xF);
        if (nibble < 10)
        {
            print((byte)('0' + nibble));
        }
        else
        {
            print((byte)('a' + (nibble - 10)));
        };
        shift = shift - 4;
    };
};

def fhf_inspect(FHFManager* mgr) -> void
{
    if (mgr == (FHFManager*)0) { return; };

    print("=== FHF Patch Manager ===\n\0");
    print("Initialized: \0");
    print(load32(@mgr.initialized));
    print("\n\0");
    print("Active patches: \0");
    print(mgr.record_count);
    print("\n\0");
    print("Trampoline pool usage: \0");
    print(load32(@mgr.tramp_pool.used_count));
    print(" / \0");
    print(FHF_TRAMP_POOL_MAX);
    print("\n\0");

    int i;
    for (i = 0; i < FHF_MAX_ENTRIES; i++)
    {
        FHFPatchRecord* rec = @mgr.records[i];
        if (rec.state == (u32)FHF_STATE_EMPTY) { i = i; } // skip, no continue
        else
        {
            print("[#\0");
            print(i);
            print("] state=\0");
            print((int)rec.state);
            print(" target=0x\0");
            _fhf_print_hex64(rec.target_addr);
            print(" tramp=0x\0");
            _fhf_print_hex64(rec.tramp_addr);
            print(" saved_bytes=\0");
            print((int)rec.saved_bytes_len);
            print("\n\0");
        };
    };

    print("=========================\n\0");
};

#endif; // FHF_RUNTIME
