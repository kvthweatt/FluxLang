// fhf_crypto.fx
//
// Flux Hotpatch Framework (FHF) — Cryptographic Signing Layer
//
// Provides HMAC-SHA256 signing and verification for both individual
// patch entries and whole bundles.  Built on top of redcrypto.fx.
//
// API:
//   fhf_hmac(key, msg, msg_len, out[32])
//   fhf_sign_entry(mgr, entry_hdr, payload, payload_size)
//   fhf_verify_entry(mgr, entry_hdr, payload, payload_size) -> bool
//   fhf_sign_bundle(mgr, bundle_hdr, entry_hdrs, payloads[], sizes[])
//   fhf_verify_bundle(mgr, bundle_hdr, entry_hdrs, payloads[], sizes[]) -> bool
//   fhf_sig_equal(a, b) -> bool

#ifndef FHF_CRYPTO
#def FHF_CRYPTO 1;

#ifndef FHF_TYPES
#import "fhf\\fhf_types.fx";
#endif;

#ifndef FLUX_STANDARD_CRYPTO
#import "redcrypto.fx";
#endif;

using standard::crypto::hashing::SHA256;

// ============================================================================
//  HMAC-SHA256
// ============================================================================

// Compute HMAC-SHA256(key[key_len], msg[msg_len]) into out[32].
// RFC 2104 construction with 64-byte block size.
def fhf_hmac(byte* key, int key_len,
             byte* msg, int msg_len,
             byte* out) -> void
{
    byte[64] ipad;
    byte[64] opad;
    int i;

    for (i = 0; i < 64; i++)
    {
        byte k = (i < key_len) ? key[i] : (byte)0;
        ipad[i] = k ^^ (byte)0x36;
        opad[i] = k ^^ (byte)0x5C;
    };

    // inner = SHA256(ipad || msg)
    byte[32] inner;
    SHA256_CTX ictx;
    sha256_init(@ictx);
    sha256_update(@ictx, @ipad[0], (u64)64);
    sha256_update(@ictx, msg,      (u64)msg_len);
    sha256_final(@ictx, @inner[0]);

    // out = SHA256(opad || inner)
    SHA256_CTX octx;
    sha256_init(@octx);
    sha256_update(@octx, @opad[0],  (u64)64);
    sha256_update(@octx, @inner[0], (u64)32);
    sha256_final(@octx, out);
};

// ============================================================================
//  Constant-time 32-byte comparison
// ============================================================================

// Returns true iff a[0..31] == b[0..31].
// The loop never short-circuits so timing is independent of content.
def fhf_sig_equal(byte* a, byte* b) -> bool
{
    byte acc = (byte)0;
    int i;
    for (i = 0; i < 32; i++)
    {
        acc = acc | (a[i] ^^ b[i]);
    };
    return acc == (byte)0;
};

// ============================================================================
//  Entry signing / verification
// ============================================================================

// Write HMAC-SHA256(mgr.hmac_key, payload) into entry_hdr.payload_sig.
// Sets FHF_FLAG_SIGNED in entry_hdr.flags.
def fhf_sign_entry(FHFManager* mgr,
                   FHFEntryHeader* entry_hdr,
                   byte* payload,
                   int payload_size) -> void
{
    fhf_hmac(@mgr.hmac_key[0], 32, payload, payload_size,
             @entry_hdr.payload_sig[0]);
    entry_hdr.flags = entry_hdr.flags | FHF_FLAG_SIGNED;
};

// Verify the payload signature on a single entry.
// Returns false if the entry is not marked FHF_FLAG_SIGNED, or if the
// computed MAC does not match entry_hdr.payload_sig.
def fhf_verify_entry(FHFManager* mgr,
                     FHFEntryHeader* entry_hdr,
                     byte* payload,
                     int payload_size) -> bool
{
    if ((entry_hdr.flags & FHF_FLAG_SIGNED) == (u32)0)
    {
        return false;
    };

    byte[32] expected;
    fhf_hmac(@mgr.hmac_key[0], 32, payload, payload_size, @expected[0]);
    return fhf_sig_equal(@expected[0], @entry_hdr.payload_sig[0]);
};

// ============================================================================
//  Bundle signing / verification
//
//  The bundle MAC covers:
//    for each entry i: entry_headers[i] (as raw bytes) || payloads[i]
//  concatenated in order.  The resulting digest is written to
//  bundle_hdr.bundle_sig.
//
//  Callers pass parallel arrays: entry_hdrs[count], payloads[count],
//  payload_sizes[count].
// ============================================================================

def fhf_sign_bundle(FHFManager*      mgr,
                    FHFBundleHeader*  bundle_hdr,
                    FHFEntryHeader*   entry_hdrs,
                    byte**            payloads,
                    int*              payload_sizes,
                    int               count) -> void
{
    // Build the MAC incrementally by running one SHA256 pass over the
    // concatenated (entry_header || payload) stream, then wrapping with HMAC.
    //
    // Because fhf_hmac expects a contiguous buffer we use the two-phase
    // HMAC construction directly here rather than calling fhf_hmac.

    byte[64] ipad;
    byte[64] opad;
    int i;

    for (i = 0; i < 64; i++)
    {
        byte k = mgr.hmac_key[i];
        ipad[i] = k ^^ (byte)0x36;
        opad[i] = k ^^ (byte)0x5C;
    };

    // inner = SHA256(ipad || all_entry_headers || all_payloads)
    byte[32] inner;
    SHA256_CTX ictx;
    sha256_init(@ictx);
    sha256_update(@ictx, @ipad[0], (u64)64);

    int entry_hdr_size = 552; // sizeof(FHFEntryHeader) — fixed layout
    for (i = 0; i < count; i++)
    {
        // Feed entry header bytes
        byte* hdr_bytes = (byte*)(@entry_hdrs + i);
        sha256_update(@ictx, hdr_bytes, (u64)entry_hdr_size);
        // Feed payload bytes
        sha256_update(@ictx, payloads[i], (u64)payload_sizes[i]);
    };
    sha256_final(@ictx, @inner[0]);

    // out = SHA256(opad || inner)
    SHA256_CTX octx;
    sha256_init(@octx);
    sha256_update(@octx, @opad[0],  (u64)64);
    sha256_update(@octx, @inner[0], (u64)32);
    sha256_final(@octx, @bundle_hdr.bundle_sig[0]);
};

def fhf_verify_bundle(FHFManager*      mgr,
                      FHFBundleHeader*  bundle_hdr,
                      FHFEntryHeader*   entry_hdrs,
                      byte**            payloads,
                      int*              payload_sizes,
                      int               count) -> bool
{
    byte[64] ipad;
    byte[64] opad;
    int i;

    for (i = 0; i < 64; i++)
    {
        byte k = mgr.hmac_key[i];
        ipad[i] = k ^^ (byte)0x36;
        opad[i] = k ^^ (byte)0x5C;
    };

    byte[32] inner;
    SHA256_CTX ictx;
    sha256_init(@ictx);
    sha256_update(@ictx, @ipad[0], (u64)64);

    int entry_hdr_size = 552;
    for (i = 0; i < count; i++)
    {
        byte* hdr_bytes = (byte*)(@entry_hdrs + i);
        sha256_update(@ictx, hdr_bytes, (u64)entry_hdr_size);
        sha256_update(@ictx, payloads[i], (u64)payload_sizes[i]);
    };
    sha256_final(@ictx, @inner[0]);

    byte[32] computed;
    SHA256_CTX octx;
    sha256_init(@octx);
    sha256_update(@octx, @opad[0],  (u64)64);
    sha256_update(@octx, @inner[0], (u64)32);
    sha256_final(@octx, @computed[0]);

    return fhf_sig_equal(@computed[0], @bundle_hdr.bundle_sig[0]);
};

#endif; // FHF_CRYPTO
