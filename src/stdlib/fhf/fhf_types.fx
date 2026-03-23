// Author: Karac V. Thweatt

// fhf_types.fx
//
// Flux Hotpatch Framework (FHF) — Core Types, Error Codes, and Constants
//
// Every other FHF module imports this file.  Nothing here has any
// dependency beyond the standard type system.

#ifndef FHF_TYPES
#def FHF_TYPES 1;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

// ============================================================================
//  Version
// ============================================================================

const u32 FHF_VERSION_MAJOR = 1,
          FHF_VERSION_MINOR = 0,
          FHF_VERSION_PATCH = 0;

// Bundle magic bytes: "FHFB" (Flux HotPatch Bundle)
const u32 FHF_BUNDLE_MAGIC   = 0x46484642;

// Entry magic bytes: "FHFE" (Flux HotPatch Frame Entry)
const u32 FHF_ENTRY_MAGIC    = 0x46484645;

// Trampoline pool tag for identification
const u32 FHF_TRAMP_MAGIC    = 0x46484654;

// Maximum number of patch entries per bundle
const int FHF_MAX_ENTRIES    = 64;

// Maximum raw payload bytes per entry (16 pages)
const int FHF_MAX_PAYLOAD    = 65536;

// Maximum symbol name length (including null terminator)
const int FHF_SYM_NAME_MAX   = 256;

// Maximum module name length
const int FHF_MOD_NAME_MAX   = 260;

// Trampoline size: 14 bytes for absolute indirect JMP (FF 25 00000000 + 8-byte addr)
const int FHF_TRAMP_SIZE     = 14;

// Number of trampolines in the shared pool
const int FHF_TRAMP_POOL_MAX = 256;

// HMAC-SHA256 signature size
const int FHF_SIG_SIZE       = 32;

// Saved bytes buffer — enough to hold the overwritten preamble before patching
const int FHF_SAVED_BYTES_MAX = 32;

// ============================================================================
//  Error Codes
// ============================================================================

const int FHF_OK                =  0;   // Success
const int FHF_ERR_BAD_MAGIC     = -1;   // Bundle or entry magic mismatch
const int FHF_ERR_BAD_SIG       = -2;   // HMAC-SHA256 signature invalid
const int FHF_ERR_BAD_VERSION   = -3;   // Incompatible bundle version
const int FHF_ERR_ALLOC         = -4;   // Memory / page allocation failed
const int FHF_ERR_PROTECT       = -5;   // VirtualProtect failed
const int FHF_ERR_FLUSH         = -6;   // FlushInstructionCache failed
const int FHF_ERR_SYM_NOT_FOUND = -7;   // Symbol resolution failed
const int FHF_ERR_ALREADY_PATCHED = -8; // Target already has a patch installed
const int FHF_ERR_NOT_PATCHED   = -9;   // Rollback called on unpatched site
const int FHF_ERR_THREAD_SUSPEND = -10; // Failed to suspend all threads safely
const int FHF_ERR_PAYLOAD_TOO_LARGE = -11; // Payload exceeds FHF_MAX_PAYLOAD
const int FHF_ERR_TOO_MANY_ENTRIES = -12;  // More entries than FHF_MAX_ENTRIES
const int FHF_ERR_NETWORK       = -13;  // Network send/recv failure
const int FHF_ERR_IO            = -14;  // File I/O failure
const int FHF_ERR_TRAMP_POOL_FULL = -15; // No free trampolines available
const int FHF_ERR_INVALID_ARG   = -16;  // Null pointer or bad parameter

// ============================================================================
//  Patch Entry Flags
// ============================================================================

const u32 FHF_FLAG_NONE         = 0x00000000;
const u32 FHF_FLAG_REPLACE      = 0x00000001;  // Full function replacement
const u32 FHF_FLAG_PREPEND      = 0x00000002;  // Insert hook before original
const u32 FHF_FLAG_APPEND       = 0x00000004;  // Insert hook after original
const u32 FHF_FLAG_NOP_FILL     = 0x00000008;  // Fill displaced bytes with NOPs
const u32 FHF_FLAG_SIGNED       = 0x00000010;  // Entry carries HMAC-SHA256 sig
const u32 FHF_FLAG_ROLLBACK_OK  = 0x00000020;  // Saved bytes included for rollback

// ============================================================================
//  Symbol Resolution Mode
// ============================================================================

const u32 FHF_SYM_BY_RVA        = 0;   // Use target_rva directly
const u32 FHF_SYM_BY_NAME       = 1;   // Look up exported name in module
const u32 FHF_SYM_BY_PATTERN    = 2;   // Byte-pattern scan in module text
const u32 FHF_SYM_BY_ABSADDR    = 3;   // Absolute virtual address (same process)

// ============================================================================
//  Patch State
// ============================================================================

const u32 FHF_STATE_EMPTY       = 0;   // Slot not in use
const u32 FHF_STATE_PENDING     = 1;   // Loaded, not yet applied
const u32 FHF_STATE_APPLIED     = 2;   // Currently live
const u32 FHF_STATE_ROLLED_BACK = 3;   // Was applied, now reverted

// ============================================================================
//  Core Data Structures
// ============================================================================

// On-disk / on-wire bundle header.
// All multi-byte integers are little-endian.
struct FHFBundleHeader
{
    u32 magic;              // FHF_BUNDLE_MAGIC
    u32 version;            // Packed: (major<<16)|(minor<<8)|patch
    u32 entry_count;        // Number of FHFEntryHeader records following
    u32 flags;              // Bundle-level flags (reserved, set to 0)
    u64 timestamp;          // Unix time of bundle creation
    byte[32] bundle_sig;    // HMAC-SHA256 over all entry headers + payloads
    byte[32] key_hint;      // First 32 bytes of SHA256(signing_key) for key lookup
};

// Per-entry header that precedes the raw payload bytes.
struct FHFEntryHeader
{
    u32 magic;              // FHF_ENTRY_MAGIC
    u32 flags;              // FHF_FLAG_* bitmask
    u32 sym_mode;           // FHF_SYM_BY_* constant
    u32 payload_size;       // Byte length of the payload that follows
    u64 target_rva;         // RVA or absolute address (depending on sym_mode)
    byte[FHF_SYM_NAME_MAX] sym_name;   // Symbol name (null-padded)
    byte[FHF_MOD_NAME_MAX] mod_name;   // Module name (null-padded)
    byte[FHF_SAVED_BYTES_MAX] saved_bytes; // Original bytes for rollback
    u32 saved_bytes_len;    // How many saved_bytes are valid
    byte[32] payload_sig;   // HMAC-SHA256 over payload bytes (if FHF_FLAG_SIGNED)
};

// Runtime record tracking one applied patch.
struct FHFPatchRecord
{
    u32 state;              // FHF_STATE_*
    ulong target_addr;      // Resolved virtual address of the patch site
    ulong tramp_addr;       // Address of the allocated trampoline page
    int   tramp_idx;        // Index into the trampoline pool (-1 = own page)
    byte[FHF_SAVED_BYTES_MAX] saved_bytes; // Original bytes at target_addr
    u32   saved_bytes_len;  // How many bytes were saved
    u32   flags;            // Copied from FHFEntryHeader.flags
};

// One slot in the trampoline pool.
struct FHFTrampolineSlot
{
    u32   magic;            // FHF_TRAMP_MAGIC when in use, 0 when free
    i32   in_use;           // Atomic: 0 = free, 1 = taken
    ulong code_addr;        // Address of the 14-byte trampoline in the pool page
    ulong target_addr;      // The patch site this trampoline serves
};

// The trampoline pool — a single RWX page divided into FHF_TRAMP_POOL_MAX slots.
struct FHFTrampolinePool
{
    ulong  page_addr;                          // Base of the RWX allocation
    i32    lock;                               // Spinlock (0=free, 1=held)
    i32    used_count;                         // Number of slots in use
    FHFTrampolineSlot[FHF_TRAMP_POOL_MAX] slots;
};

// Top-level patch manager state.  One instance per process.
struct FHFManager
{
    i32  initialized;       // 1 after fhf_init(), 0 otherwise
    i32  lock;              // Spinlock protecting records[]
    FHFPatchRecord[FHF_MAX_ENTRIES] records;
    int  record_count;
    FHFTrampolinePool tramp_pool;
    byte[32] hmac_key;      // Active signing/verification key
    i32  key_set;           // 1 if hmac_key has been loaded
};

#endif; // FHF_TYPES
