// fhf_bundle.fx
//
// Flux Hotpatch Framework (FHF) — Bundle Builder
//
// Programmatic API for constructing FHF patch bundles in memory.
// The builder accumulates entries into a flat byte buffer that can be
// written to disk, sent over the network, or applied directly.
//
// Usage:
//   FHFBundleBuilder b;
//   fhf_builder_init(@b)
//   fhf_builder_add_entry(@b, sym_mode, sym_name, mod_name,
//                          target_rva, flags, payload, payload_size)
//   fhf_builder_finalize(@b, mgr)   — signs and writes the header
//   fhf_builder_data(@b)            — pointer to completed buffer
//   fhf_builder_size(@b)            — total byte count
//   fhf_builder_free(@b)            — release buffer

#ifndef FHF_BUNDLE
#def FHF_BUNDLE 1;

#ifndef FHF_CRYPTO
#import "fhf\\fhf_crypto.fx";
#endif;
#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

// ============================================================================
//  Builder state
// ============================================================================

// Initial buffer allocation: 64 KiB, grows as needed
const int FHF_BUILDER_INIT_CAP = 65536;

struct FHFBundleBuilder
{
    byte* buf;          // heap-allocated output buffer
    int   capacity;     // allocated bytes
    int   used;         // bytes written so far
    int   entry_count;  // number of entries added
    int   hdr_reserved; // byte offset where the bundle header lives (always 0)
};

// ============================================================================
//  Internal helpers
// ============================================================================

// Ensure the buffer has at least `needed` additional bytes.
def _fhf_builder_grow(FHFBundleBuilder* b, int needed) -> bool
{
    if (b.used + needed <= b.capacity) { return true; };

    int new_cap = b.capacity * 2;
    while (new_cap < b.used + needed) { new_cap = new_cap * 2; };

    byte* new_buf = (byte*)realloc((void*)b.buf, (size_t)new_cap);
    if (new_buf == (byte*)0) { return false; };

    b.buf      = new_buf;
    b.capacity = new_cap;
    return true;
};

// Append `count` bytes from `src` to the builder buffer.
def _fhf_builder_append(FHFBundleBuilder* b, byte* src, int count) -> bool
{
    if (!_fhf_builder_grow(b, count)) { return false; };
    int i;
    for (i = 0; i < count; i++)
    {
        b.buf[b.used + i] = src[i];
    };
    b.used = b.used + count;
    return true;
};

// Append `count` zero bytes.
def _fhf_builder_append_zeros(FHFBundleBuilder* b, int count) -> bool
{
    if (!_fhf_builder_grow(b, count)) { return false; };
    int i;
    for (i = 0; i < count; i++)
    {
        b.buf[b.used + i] = (byte)0;
    };
    b.used = b.used + count;
    return true;
};

def _fhf_write_u32_at(byte* p, u32 v) -> void
{
    p[0] = (byte)(v         & (u32)0xFF);
    p[1] = (byte)((v >>  8) & (u32)0xFF);
    p[2] = (byte)((v >> 16) & (u32)0xFF);
    p[3] = (byte)((v >> 24) & (u32)0xFF);
};

def _fhf_write_u64_at(byte* p, u64 v) -> void
{
    p[0] = (byte)(v         & (u64)0xFF);
    p[1] = (byte)((v >>  8) & (u64)0xFF);
    p[2] = (byte)((v >> 16) & (u64)0xFF);
    p[3] = (byte)((v >> 24) & (u64)0xFF);
    p[4] = (byte)((v >> 32) & (u64)0xFF);
    p[5] = (byte)((v >> 40) & (u64)0xFF);
    p[6] = (byte)((v >> 48) & (u64)0xFF);
    p[7] = (byte)((v >> 56) & (u64)0xFF);
};

// Copy a null-terminated string into a fixed-size field, zero-padding.
def _fhf_copy_name(byte* dst, byte* src, int field_size) -> void
{
    int i = 0;
    while (i < field_size - 1 & src[i] != (byte)0)
    {
        dst[i] = src[i];
        i++;
    };
    while (i < field_size)
    {
        dst[i] = (byte)0;
        i++;
    };
};

// ============================================================================
//  Public API
// ============================================================================

// Initialize a new bundle builder.
// Returns FHF_OK or FHF_ERR_ALLOC.
def fhf_builder_init(FHFBundleBuilder* b) -> int
{
    if (b == (FHFBundleBuilder*)0) { return FHF_ERR_INVALID_ARG; };

    b.buf = (byte*)malloc((size_t)FHF_BUILDER_INIT_CAP);
    if (b.buf == (byte*)0) { return FHF_ERR_ALLOC; };

    b.capacity    = FHF_BUILDER_INIT_CAP;
    b.used        = 0;
    b.entry_count = 0;
    b.hdr_reserved = 0;

    // Reserve space for the bundle header (filled in by fhf_builder_finalize)
    if (!_fhf_builder_append_zeros(b, FHF_BUNDLE_HDR_SIZE))
    {
        free((void*)b.buf);
        b.buf = (byte*)0;
        return FHF_ERR_ALLOC;
    };

    return FHF_OK;
};

// Add one patch entry to the bundle.
// sym_name and mod_name are null-terminated strings.
// payload[0..payload_size) is the replacement machine code.
// The entry is individually signed if mgr != NULL && mgr.key_set.
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_builder_add_entry(FHFBundleBuilder* b,
                           FHFManager*       mgr,
                           u32               sym_mode,
                           byte*             sym_name,
                           byte*             mod_name,
                           u64               target_rva,
                           u32               flags,
                           byte*             payload,
                           int               payload_size) -> int
{
    if (b == (FHFBundleBuilder*)0 | payload == (byte*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };
    if (payload_size <= 0 | payload_size > FHF_MAX_PAYLOAD)
    {
        return FHF_ERR_PAYLOAD_TOO_LARGE;
    };
    if (b.entry_count >= FHF_MAX_ENTRIES)
    {
        return FHF_ERR_TOO_MANY_ENTRIES;
    };

    // Build entry header on stack as a zero-initialised byte array
    // FHF_ENTRY_HDR_SIZE = 608 bytes
    byte[608] ehdr_buf;
    int i;
    for (i = 0; i < 608; i++) { ehdr_buf[i] = (byte)0; };

    FHFEntryHeader* ehdr = (FHFEntryHeader*)@ehdr_buf[0];

    ehdr.magic        = (u32)FHF_ENTRY_MAGIC;
    ehdr.flags        = flags | FHF_FLAG_ROLLBACK_OK;
    ehdr.sym_mode     = sym_mode;
    ehdr.payload_size = (u32)payload_size;
    ehdr.target_rva   = target_rva;

    _fhf_copy_name((byte*)@ehdr.sym_name[0], sym_name, FHF_SYM_NAME_MAX);
    _fhf_copy_name((byte*)@ehdr.mod_name[0], mod_name, FHF_MOD_NAME_MAX);

    // Sign the entry payload if we have a key
    if (mgr != (FHFManager*)0 & load32(@mgr.key_set) != 0)
    {
        fhf_sign_entry(mgr, ehdr, payload, payload_size);
    };

    // Append entry header + payload to buffer
    if (!_fhf_builder_append(b, @ehdr_buf[0], FHF_ENTRY_HDR_SIZE))
    {
        return FHF_ERR_ALLOC;
    };
    if (!_fhf_builder_append(b, payload, payload_size))
    {
        return FHF_ERR_ALLOC;
    };

    b.entry_count = b.entry_count + 1;
    return FHF_OK;
};

// Finalise the bundle: fill in the bundle header and sign it.
// After this call, fhf_builder_data/size return the complete buffer.
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_builder_finalize(FHFBundleBuilder* b, FHFManager* mgr) -> int
{
    if (b == (FHFBundleBuilder*)0) { return FHF_ERR_INVALID_ARG; };

    // Write bundle header at offset 0
    byte* hdr = b.buf;

    // magic
    _fhf_write_u32_at(hdr + 0,  FHF_BUNDLE_MAGIC);
    // version: (major<<16)|(minor<<8)|patch
    u32 ver = ((u32)FHF_VERSION_MAJOR << 16) |
              ((u32)FHF_VERSION_MINOR << 8)  |
              (u32)FHF_VERSION_PATCH;
    _fhf_write_u32_at(hdr + 4,  ver);
    // entry_count
    _fhf_write_u32_at(hdr + 8,  (u32)b.entry_count);
    // flags (reserved)
    _fhf_write_u32_at(hdr + 12, (u32)0);
    // timestamp (0 for now — no time API yet)
    _fhf_write_u64_at(hdr + 16, (u64)0);
    // bundle_sig and key_hint will be filled below (zero for now)
    // bytes 24..87 are already zero from _fhf_builder_append_zeros

    // Compute bundle-level HMAC over everything after the header
    if (mgr != (FHFManager*)0 & load32(@mgr.key_set) != 0)
    {
        byte* body     = b.buf + FHF_BUNDLE_HDR_SIZE;
        int   body_len = b.used - FHF_BUNDLE_HDR_SIZE;

        // bundle_sig lives at offset 24 in the header
        fhf_hmac(@mgr.hmac_key[0], 32, body, body_len, hdr + 24);

        // key_hint = SHA256(hmac_key) truncated to 32 bytes, offset 56
        SHA256_CTX kctx;
        sha256_init(@kctx);
        sha256_update(@kctx, @mgr.hmac_key[0], (u64)32);
        sha256_final(@kctx, hdr + 56);
    };

    return FHF_OK;
};

// Return pointer to the completed bundle buffer.
def fhf_builder_data(FHFBundleBuilder* b) -> byte*
{
    if (b == (FHFBundleBuilder*)0) { return (byte*)0; };
    return b.buf;
};

// Return the size of the completed bundle buffer in bytes.
def fhf_builder_size(FHFBundleBuilder* b) -> int
{
    if (b == (FHFBundleBuilder*)0) { return 0; };
    return b.used;
};

// Free the builder's internal buffer.
def fhf_builder_free(FHFBundleBuilder* b) -> void
{
    if (b == (FHFBundleBuilder*)0) { return; };
    if (b.buf != (byte*)0)
    {
        free((void*)b.buf);
        b.buf = (byte*)0;
    };
    b.used        = 0;
    b.capacity    = 0;
    b.entry_count = 0;
};

#endif; // FHF_BUNDLE
