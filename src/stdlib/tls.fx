// Author: Karac V. Thweatt
// tls13.fx - TLS 1.3 Client + Server Implementation
//
// Implements TLS 1.3 (RFC 8446) client-side handshake and record layer.
// Cipher suite: TLS_AES_128_GCM_SHA256 (the only mandatory TLS 1.3 suite)
// Key exchange:  x25519
// PRF:           HKDF-SHA-256
//
// Public API:
//   tls13_connect(TLS13_CTX*, int sockfd, byte* hostname, int hostname_len) -> int
//     Performs the full TLS 1.3 handshake over an already-connected TCP socket.
//     Returns 1 on success, 0 on failure.
//
//   tls13_send(TLS13_CTX*, byte* data, int len) -> int
//     Encrypts and sends application data. Returns bytes sent, -1 on error.
//
//   tls13_recv(TLS13_CTX*, byte* buf, int buf_len) -> int
//     Receives and decrypts one TLS record. Returns plaintext bytes, -1 on error.
//
//   tls13_close(TLS13_CTX*) -> void
//     Sends a close_notify alert and tears down the session.
//
// Limitations (initial implementation):
//   - Client authentication not supported
//   - Session resumption (PSK) not supported
//   - Certificate chain validation not performed (records cert but does not verify)
//   - SNI extension sent; no ALPN
//   - IPv4 TCP only (matches net_windows.fx)

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef FLUX_STANDARD_NET
#ifdef __WINDOWS__
#import "net_windows.fx";
#endif;
#ifdef __LINUX__
#import "net_linux.fx";
#endif;
#endif;

#ifndef FLUX_STANDARD_CRYPTO
#import "cryptography.fx";
#endif;

#ifndef FLUX_TLS
#def FLUX_TLS 1;
#endif;

#ifndef FLUX_TLS13
#def FLUX_TLS13 1;

// ============================================================
// TLS 1.3 constants
// ============================================================

// Record content types (RFC 8446 §5.1)
#def TLS_CT_CHANGE_CIPHER_SPEC  20;
#def TLS_CT_ALERT               21;
#def TLS_CT_HANDSHAKE           22;
#def TLS_CT_APPLICATION_DATA    23;

// Handshake message types (RFC 8446 §4)
#def TLS_HT_CLIENT_HELLO        1;
#def TLS_HT_SERVER_HELLO        2;
#def TLS_HT_NEW_SESSION_TICKET  4;
#def TLS_HT_ENCRYPTED_EXTS      8;
#def TLS_HT_CERTIFICATE         11;
#def TLS_HT_CERT_VERIFY         15;
#def TLS_HT_FINISHED            20;

// Alert levels and descriptions
#def TLS_ALERT_LEVEL_WARNING    1;
#def TLS_ALERT_LEVEL_FATAL      2;
#def TLS_ALERT_CLOSE_NOTIFY     0;
#def TLS_ALERT_DECRYPT_ERROR    51;

// Cipher suite
#def TLS_AES_128_GCM_SHA256_HI  0x13;
#def TLS_AES_128_GCM_SHA256_LO  0x01;

// Extension types
#def TLS_EXT_SERVER_NAME        0;
#def TLS_EXT_SUPPORTED_GROUPS   10;
#def TLS_EXT_SIG_ALGS           13;
#def TLS_EXT_SUPPORTED_VERSIONS 43;
#def TLS_EXT_KEY_SHARE          51;

// Named group x25519
#def TLS_GROUP_X25519_HI        0x00;
#def TLS_GROUP_X25519_LO        0x1D;

// Signature algorithm ed25519 / rsa_pss_rsae_sha256
#def TLS_SIG_RSA_PSS_SHA256_HI  0x08;
#def TLS_SIG_RSA_PSS_SHA256_LO  0x04;
#def TLS_SIG_ECDSA_SHA256_HI    0x04;
#def TLS_SIG_ECDSA_SHA256_LO    0x03;

// TLS version bytes
#def TLS_VERSION_12_HI          0x03;
#def TLS_VERSION_12_LO          0x03;
#def TLS_VERSION_13_HI          0x03;
#def TLS_VERSION_13_LO          0x04;

// HKDF-SHA-256 hash length
#def TLS13_HASH_LEN             32;
// AES-128-GCM key length
#def TLS13_KEY_LEN              16;
// AES-GCM nonce/IV length
#def TLS13_IV_LEN               12;
// GCM authentication tag length
#def TLS13_TAG_LEN              16;
// Maximum TLS plaintext record size (RFC 8446 §5.1)
#def TLS13_MAX_PLAINTEXT        16384;
// Maximum TLS ciphertext record overhead: 5 (header) + 16 (tag) + 1 (inner type)
#def TLS13_RECORD_OVERHEAD      22;

namespace standard
{
    namespace tls
    {
        // ============================================================
        // Structs
        // ============================================================

        // Per-direction traffic key material derived from the key schedule
        struct TLS13_TrafficKeys
        {
            byte[16] key;       // AES-128 key
            byte[12] iv;        // 12-byte base IV
            u64      seq;       // Record sequence number (for nonce construction)
        };

        // Full TLS 1.3 session context
        struct TLS13_CTX
        {
            int  sockfd;                    // Underlying TCP socket fd

            // Ephemeral x25519 key pair
            byte[32] our_priv,             // Our ephemeral private scalar
                     our_pub,              // Our ephemeral public key
                     their_pub,            // Server's ephemeral public key (from KeyShare)
                     shared_secret,        // x25519 ECDH shared secret

            // Key schedule secrets (all 32 bytes, SHA-256 output size)
                     early_secret,
                     handshake_secret,
                     master_secret;

            // Derived traffic keys
            TLS13_TrafficKeys client_hs,   // client → server handshake
                              server_hs,   // server → client handshake
                              client_app,  // client → server application
                              server_app;  // server → client application

            // Running transcript hash context (SHA-256)
            // We maintain two copies: one through ServerHello (for handshake key derivation)
            // and the running one through Finished.
            standard::crypto::hashing::SHA256::SHA256_CTX transcript;

            // GCM contexts (re-initialised whenever keys change)
            standard::crypto::encryption::AES::GCM_CTX  gcm_write, // For outbound records
                                                        gcm_read;  // For inbound records

            // State flags
            int  handshake_done,           // 1 once application keys are active
                 is_server;
        };

        // ============================================================
        // Internal helpers
        // ============================================================

        // Write a big-endian u16 into buf[0..1]
        def tls_put_u16(byte* buf, int v) -> void
        {
            buf[0] = (byte)((v >> 8) & 0xFF);
            buf[1] = (byte)(v & 0xFF);
            return;
        };

        // Write a big-endian u24 into buf[0..2]
        def tls_put_u24(byte* buf, int v) -> void
        {
            buf[0] = (byte)((v >> 16) & 0xFF);
            buf[1] = (byte)((v >> 8) & 0xFF);
            buf[2] = (byte)(v & 0xFF);
            return;
        };

        // Read a big-endian u16 from buf[0..1]
        def tls_get_u16(byte* buf) -> int
        {
            return (((int)(buf[0] & 0xFF)) << 8) | ((int)(buf[1] & 0xFF));
        };

        // Read a big-endian u24 from buf[0..2]
        def tls_get_u24(byte* buf) -> int
        {
            return (((int)(buf[0] & 0xFF)) << 16) |
                   (((int)(buf[1] & 0xFF)) << 8)  |
                    ((int)(buf[2] & 0xFF));
        };

        // Send exactly len bytes over the socket.
        // Returns 1 on success, 0 on error.
        def tls_send_exact(int fd, byte* buf, int len) -> int
        {
            int sent, total;
            while (total < len)
            {
                sent = send(fd, (void*)buf, len - total, 0);
                if (sent <= 0) { return 0; };
                total = total + sent;
                buf = (byte*)((u64)buf + (u64)sent);
            };
            return 1;
        };

        // Receive exactly len bytes from the socket.
        // Returns 1 on success, 0 on error/EOF.
        def tls_recv_exact(int fd, byte* buf, int len) -> int
        {
            int got, total;
            while (total < len)
            {
                got = recv(fd, (void*)buf, len - total, 0);
                if (got <= 0) { return 0; };
                total = total + got;
                buf = (byte*)((u64)buf + (u64)got);
            };
            return 1;
        };

        // ============================================================
        // TLS record layer — send a plaintext record (pre-handshake)
        // ============================================================

        // Send a raw (unencrypted) TLS record.
        // Used for ClientHello (before keys exist).
        def tls_send_record_plain(int fd, int content_type, byte* payload, int payload_len) -> int
        {
            byte[5] hdr;
            hdr[0] = (byte)content_type;
            hdr[1] = (byte)TLS_VERSION_12_HI;
            hdr[2] = (byte)TLS_VERSION_12_LO;
            tls_put_u16(@hdr[3], payload_len);
            if (!tls_send_exact(fd, @hdr[0], 5)) { return 0; };
            if (!tls_send_exact(fd, payload, payload_len)) { return 0; };
            return 1;
        };

        // ============================================================
        // TLS record layer — send an encrypted record (post-handshake)
        //
        // TLS 1.3 encrypted record format (RFC 8446 §5.2):
        //   outer header: content_type=23 (application_data), 5 bytes
        //   payload:      GCM( inner_plaintext || inner_content_type ) + tag
        //   AAD:          the 5-byte outer header
        //
        // Nonce: base_iv XOR (seq padded to 12 bytes, big-endian)
        // ============================================================
        def tls_send_record_enc(TLS13_CTX* ctx, int inner_type, byte* payload, int payload_len) -> int
        {
            byte[TLS13_MAX_PLAINTEXT + 1] inner_plain;
            byte[TLS13_MAX_PLAINTEXT + TLS13_RECORD_OVERHEAD] ct_buf;
            byte[5]  hdr;
            byte[12] nonce;
            byte[TLS13_TAG_LEN] tag;
            int i, ct_len, total_inner;
            u64 seq;

            // Build inner plaintext: payload || inner_content_type
            for (i = 0; i < payload_len; i++) { inner_plain[i] = payload[i]; };
            inner_plain[payload_len] = (byte)inner_type;
            total_inner = payload_len + 1;

            // Outer header (AAD): content_type=23, TLS 1.2 version, encrypted length
            ct_len = total_inner + TLS13_TAG_LEN;
            hdr[0] = (byte)TLS_CT_APPLICATION_DATA;
            hdr[1] = (byte)TLS_VERSION_12_HI;
            hdr[2] = (byte)TLS_VERSION_12_LO;
            tls_put_u16(@hdr[3], ct_len);

            // Nonce: base_iv XOR seq (big-endian, right-aligned in 12 bytes)
            seq = ctx.client_hs.seq;
            if (ctx.is_server != 0)   { seq = ctx.server_hs.seq; };
            if (ctx.handshake_done != 0)
            {
                seq = ctx.client_app.seq;
                if (ctx.is_server != 0) { seq = ctx.server_app.seq; };
            };
            for (i = 0; i < 12; i++) { nonce[i] = '\0'; };
            // Write seq into bytes 4..11 (big-endian u64)
            nonce[4]  = (byte)((seq >> 56) & 0xFF);
            nonce[5]  = (byte)((seq >> 48) & 0xFF);
            nonce[6]  = (byte)((seq >> 40) & 0xFF);
            nonce[7]  = (byte)((seq >> 32) & 0xFF);
            nonce[8]  = (byte)((seq >> 24) & 0xFF);
            nonce[9]  = (byte)((seq >> 16) & 0xFF);
            nonce[10] = (byte)((seq >>  8) & 0xFF);
            nonce[11] = (byte)( seq        & 0xFF);
            // XOR with base IV
            if (ctx.handshake_done != 0)
            {
                if (ctx.is_server != 0)
                {
                    for (i = 0; i < 12; i++) { nonce[i] = nonce[i] ^^ ctx.server_app.iv[i]; };
                }
                else
                {
                    for (i = 0; i < 12; i++) { nonce[i] = nonce[i] ^^ ctx.client_app.iv[i]; };
                };
            }
            else
            {
                if (ctx.is_server != 0)
                {
                    for (i = 0; i < 12; i++) { nonce[i] = nonce[i] ^^ ctx.server_hs.iv[i]; };
                }
                else
                {
                    for (i = 0; i < 12; i++) { nonce[i] = nonce[i] ^^ ctx.client_hs.iv[i]; };
                };
            };

            standard::crypto::encryption::AES::gcm_encrypt(@ctx.gcm_write, @nonce[0],
                        @hdr[0], 5,
                        @inner_plain[0], total_inner,
                        @ct_buf[0], @tag[0]);

            // Append tag to ciphertext
            for (i = 0; i < TLS13_TAG_LEN; i++) { ct_buf[total_inner + i] = tag[i]; };

            // Increment sequence
            if (ctx.handshake_done != 0)
            {
                if (ctx.is_server != 0) { ctx.server_app.seq = ctx.server_app.seq + 1u; }
                else                    { ctx.client_app.seq = ctx.client_app.seq + 1u; };
            }
            else
            {
                if (ctx.is_server != 0) { ctx.server_hs.seq  = ctx.server_hs.seq  + 1u; }
                else                    { ctx.client_hs.seq  = ctx.client_hs.seq  + 1u; };
            };

            if (!tls_send_exact(ctx.sockfd, @hdr[0], 5)) { return 0; };
            if (!tls_send_exact(ctx.sockfd, @ct_buf[0], ct_len)) { return 0; };
            return 1;
        };

        // ============================================================
        // TLS record layer — receive one record
        //
        // Reads a 5-byte header then the record body into buf.
        // out_type: set to the content-type byte.
        // Returns body length on success, -1 on error.
        // ============================================================
        def tls_recv_record(TLS13_CTX* ctx, byte* buf, int buf_len, int* out_type) -> int
        {
            byte[5] hdr;
            int body_len;

            if (!tls_recv_exact(ctx.sockfd, @hdr[0], 5)) { return -1; };
            *out_type = (int)(hdr[0] & 0xFF);
            body_len  = tls_get_u16(@hdr[3]);
            if (body_len > buf_len) { return -1; };
            if (!tls_recv_exact(ctx.sockfd, buf, body_len)) { return -1; };
            return body_len;
        };

        // Decrypt an inbound TLS 1.3 encrypted record in-place.
        // buf points to the ciphertext+tag (length = ct_len).
        // hdr is the 5-byte outer header (used as AAD).
        // On success: buf holds the inner plaintext, returns inner plaintext length.
        // Returns -1 if tag verification fails.
        def tls_decrypt_record(TLS13_CTX* ctx, byte* buf, int ct_len, byte* hdr) -> int
        {
            byte[TLS13_MAX_PLAINTEXT + 1] plain;
            byte[TLS13_TAG_LEN] tag;
            byte[12] nonce;
            int i, inner_len, result;
            u64 seq;

            if (ct_len < TLS13_TAG_LEN) { return -1; };
            inner_len = ct_len - TLS13_TAG_LEN;

            // Extract tag (last 16 bytes)
            for (i = 0; i < TLS13_TAG_LEN; i++) { tag[i] = buf[inner_len + i]; };

            // Build nonce
            seq = ctx.server_hs.seq;
            if (ctx.is_server != 0)   { seq = ctx.client_hs.seq; };
            if (ctx.handshake_done != 0)
            {
                seq = ctx.server_app.seq;
                if (ctx.is_server != 0) { seq = ctx.client_app.seq; };
            };
            for (i = 0; i < 12; i++) { nonce[i] = '\0'; };
            nonce[4]  = (byte)((seq >> 56) & 0xFF);
            nonce[5]  = (byte)((seq >> 48) & 0xFF);
            nonce[6]  = (byte)((seq >> 40) & 0xFF);
            nonce[7]  = (byte)((seq >> 32) & 0xFF);
            nonce[8]  = (byte)((seq >> 24) & 0xFF);
            nonce[9]  = (byte)((seq >> 16) & 0xFF);
            nonce[10] = (byte)((seq >>  8) & 0xFF);
            nonce[11] = (byte)( seq        & 0xFF);
            if (ctx.handshake_done != 0)
            {
                if (ctx.is_server != 0)
                {
                    for (i = 0; i < 12; i++) { nonce[i] = nonce[i] ^^ ctx.client_app.iv[i]; };
                }
                else
                {
                    for (i = 0; i < 12; i++) { nonce[i] = nonce[i] ^^ ctx.server_app.iv[i]; };
                };
            }
            else
            {
                if (ctx.is_server != 0)
                {
                    for (i = 0; i < 12; i++) { nonce[i] = nonce[i] ^^ ctx.client_hs.iv[i]; };
                }
                else
                {
                    for (i = 0; i < 12; i++) { nonce[i] = nonce[i] ^^ ctx.server_hs.iv[i]; };
                };
            };

            result = standard::crypto::encryption::AES::gcm_decrypt(@ctx.gcm_read, @nonce[0],
                                 hdr, 5,
                                 buf, inner_len,
                                 @plain[0], @tag[0]);
            if (result == 0) { return -1; };

            // Increment read sequence
            if (ctx.handshake_done != 0)
            {
                if (ctx.is_server != 0) { ctx.client_app.seq = ctx.client_app.seq + 1u; }
                else                    { ctx.server_app.seq = ctx.server_app.seq + 1u; };
            }
            else
            {
                if (ctx.is_server != 0) { ctx.client_hs.seq  = ctx.client_hs.seq  + 1u; }
                else                    { ctx.server_hs.seq  = ctx.server_hs.seq  + 1u; };
            };

            // Copy plaintext back (excluding inner content type byte at end)
            for (i = 0; i < inner_len; i++) { buf[i] = plain[i]; };
            return inner_len;
        };

        // ============================================================
        // TLS 1.3 Key Schedule  (RFC 8446 §7.1)
        //
        // HKDF-Expand-Label:
        //   HKDF-Expand(secret, label, context, length)
        //   where label = "tls13 " + label_str
        //         the info = length(2) || length(label)(1) || label || length(context)(1) || context
        //
        // Derive-Secret:
        //   HKDF-Expand-Label(secret, label, Transcript-Hash(messages), Hash.length)
        // ============================================================

        // Build the HkdfLabel info blob into `info` and return its byte length.
        // out_len: the requested key material length (fits in u16)
        // label: "tls13 " already prepended by caller
        // label_len: full label length including "tls13 " prefix
        // ctx_hash: the transcript hash bytes (32 bytes for SHA-256), or null if empty
        // ctx_len: 0 for empty context
        def tls13_make_hkdf_label(byte* info,
                                  int   out_len,
                                  byte* xlabel,  int label_len,
                                  byte* ctx_bytes, int ctx_len) -> int
        {
            int pos;
            int i;

            // 2-byte length (big-endian)
            info[0] = (byte)((out_len >> 8) & 0xFF);
            info[1] = (byte)(out_len & 0xFF);
            pos = 2;

            // 1-byte label length
            info[pos] = (byte)(label_len & 0xFF);
            pos = pos + 1;

            // label bytes
            for (i = 0; i < label_len; i++) { info[pos + i] = xlabel[i]; };
            pos = pos + label_len;

            // 1-byte context length
            info[pos] = (byte)(ctx_len & 0xFF);
            pos = pos + 1;

            // context bytes
            for (i = 0; i < ctx_len; i++) { info[pos + i] = ctx_bytes[i]; };
            pos = pos + ctx_len;

            return pos;
        };

        // HKDF-Expand-Label — derives exactly `out_len` bytes into `out`.
        // label_suffix: the label string AFTER "tls13 " (e.g. "key\0")
        // suffix_len: byte length of label_suffix
        // ctx_hash: transcript hash or null; ctx_len: 0 if null
        def tls13_expand_label(byte* secret,
                               byte* label_suffix, int suffix_len,
                               byte* ctx_hash,     int ctx_len,
                               byte* out,          int out_len) -> void
        {
            // Full label = "tls13 " + suffix  (max 255 bytes total)
            byte[256] full_label;
            byte[320] info;
            int i, info_len, full_len;

            // Prepend "tls13 "
            full_label[0] = 't';
            full_label[1] = 'l';
            full_label[2] = 's';
            full_label[3] = '1';
            full_label[4] = '3';
            full_label[5] = ' ';
            full_len = 6;
            for (i = 0; i < suffix_len; i++) { full_label[6 + i] = label_suffix[i]; };
            full_len = full_len + suffix_len;

            info_len = tls13_make_hkdf_label(@info[0], out_len,
                                             @full_label[0], full_len,
                                             ctx_hash, ctx_len);

            crypto::KDF::HKDF::hkdf_expand(secret, @info[0], info_len, out, out_len);
            return;
        };

        // Derive-Secret(secret, label, transcript_hash)
        // Wrapper that always targets TLS13_HASH_LEN (32) output.
        def tls13_derive_secret(byte* secret,
                                byte* xlabel,     int label_len,
                                byte* txhash,    int txhash_len,
                                byte* out) -> void
        {
            tls13_expand_label(secret, xlabel, label_len,
                               txhash, txhash_len,
                               out, TLS13_HASH_LEN);
            return;
        };

        // Hash of empty string (SHA-256) — used for empty transcript hash.
        // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        global byte[32] TLS13_EMPTY_HASH;
        global int TLS13_EMPTY_HASH_INIT;

        def tls13_get_empty_hash(byte* out) -> void
        {
            SHA256_CTX hctx;
            int i;
            if (TLS13_EMPTY_HASH_INIT == 0)
            {
                crypto::hashing::SHA256::sha256_init(@hctx);
                crypto::hashing::SHA256::sha256_final(@hctx, @TLS13_EMPTY_HASH[0]);
                TLS13_EMPTY_HASH_INIT = 1;
            };
            for (i = 0; i < 32; i++) { out[i] = TLS13_EMPTY_HASH[i]; };
            return;
        };

        // Derive all four traffic key/IV pairs from a traffic secret.
        // Fills in a TLS13_TrafficKeys struct (key + iv, seq reset to 0).
        def tls13_derive_traffic_keys(byte* traffic_secret, TLS13_TrafficKeys* tk) -> void
        {
            int i;
            byte[8] lbl_key, lbl_iv;

            // label "key" (3 bytes), label "iv" (2 bytes)
            lbl_key[0] = 'k'; lbl_key[1] = 'e'; lbl_key[2] = 'y';
            lbl_iv[0]  = 'i'; lbl_iv[1]  = 'v';

            tls13_expand_label(traffic_secret,
                               @lbl_key[0], 3,
                               (byte*)0, 0,
                               @tk.key[0], TLS13_KEY_LEN);

            tls13_expand_label(traffic_secret,
                               @lbl_iv[0], 2,
                               (byte*)0, 0,
                               @tk.iv[0], TLS13_IV_LEN);

            tk.seq = 0u;
            return;
        };

        // Run the full TLS 1.3 key schedule up through application keys.
        //
        // Inputs:
        //   ctx.shared_secret   — x25519 ECDH output (32 bytes)
        //   txhash_server_hello — SHA-256 of transcript up to and including ServerHello
        //   txhash_server_fin   — SHA-256 of transcript up to and including server Finished
        //
        // Outputs (written into ctx):
        //   ctx.early_secret, ctx.handshake_secret, ctx.master_secret
        //   ctx.client_hs, ctx.server_hs
        //   ctx.client_app, ctx.server_app
        //   ctx.gcm_write (client_hs keys), ctx.gcm_read (server_hs keys)
        def tls13_key_schedule(TLS13_CTX* ctx,
                               byte* txhash_server_hello,
                               byte* txhash_server_fin) -> void
        {
            byte[32] zeros, derived, c_hs_ts, s_hs_ts, c_app_ts, s_app_ts;
            byte[32] empty_hash;
            byte[8]  lbl_derived, lbl_c_hs, lbl_s_hs, lbl_c_ap, lbl_s_ap;
            int i;

            for (i = 0; i < 32; i++) { zeros[i] = '\0'; };

            // "derived" label (7 bytes)
            lbl_derived[0] = 'd'; lbl_derived[1] = 'e'; lbl_derived[2] = 'r';
            lbl_derived[3] = 'i'; lbl_derived[4] = 'v'; lbl_derived[5] = 'e';
            lbl_derived[6] = 'd';

            // "c hs traffic" (12 bytes)
            lbl_c_hs[0] = 'c'; lbl_c_hs[1] = ' '; lbl_c_hs[2] = 'h';
            lbl_c_hs[3] = 's'; lbl_c_hs[4] = ' '; lbl_c_hs[5] = 't';
            lbl_c_hs[6] = 'r'; lbl_c_hs[7] = 'a';

            // "s hs traffic" (12 bytes) — same structure
            lbl_s_hs[0] = 's'; lbl_s_hs[1] = ' '; lbl_s_hs[2] = 'h';
            lbl_s_hs[3] = 's'; lbl_s_hs[4] = ' '; lbl_s_hs[5] = 't';
            lbl_s_hs[6] = 'r'; lbl_s_hs[7] = 'a';

            // "c ap traffic" (12 bytes)
            lbl_c_ap[0] = 'c'; lbl_c_ap[1] = ' '; lbl_c_ap[2] = 'a';
            lbl_c_ap[3] = 'p'; lbl_c_ap[4] = ' '; lbl_c_ap[5] = 't';
            lbl_c_ap[6] = 'r'; lbl_c_ap[7] = 'a';

            // "s ap traffic" (12 bytes)
            lbl_s_ap[0] = 's'; lbl_s_ap[1] = ' '; lbl_s_ap[2] = 'a';
            lbl_s_ap[3] = 'p'; lbl_s_ap[4] = ' '; lbl_s_ap[5] = 't';
            lbl_s_ap[6] = 'r'; lbl_s_ap[7] = 'a';

            tls13_get_empty_hash(@empty_hash[0]);

            // ---- Early Secret ----
            // early_secret = HKDF-Extract(zeros, zeros)
            crypto::KDF::HKDF::hkdf_extract(@zeros[0], 32, @zeros[0], 32, @ctx.early_secret[0]);

            // ---- Handshake Secret ----
            // derived_from_early = Derive-Secret(early_secret, "derived", "")
            tls13_derive_secret(@ctx.early_secret[0],
                                @lbl_derived[0], 7,
                                @empty_hash[0], 32,
                                @derived[0]);

            // handshake_secret = HKDF-Extract(derived_from_early, ecdh_secret)
            crypto::KDF::HKDF::hkdf_extract(@derived[0], 32,
                                            @ctx.shared_secret[0], 32,
                                            @ctx.handshake_secret[0]);

            // ---- Handshake traffic secrets ----
            // c_hs_ts = Derive-Secret(hs_secret, "c hs traffic", transcript_to_SH)
            // These need the full 12-char labels but we only stored 8-char buffers;
            // pass inline arrays directly.
            {
                byte[16] full_c_hs, full_s_hs;
                full_c_hs[0]  = 'c'; full_c_hs[1]  = ' '; full_c_hs[2]  = 'h';
                full_c_hs[3]  = 's'; full_c_hs[4]  = ' '; full_c_hs[5]  = 't';
                full_c_hs[6]  = 'r'; full_c_hs[7]  = 'a'; full_c_hs[8]  = 'f';
                full_c_hs[9]  = 'f'; full_c_hs[10] = 'i'; full_c_hs[11] = 'c';

                full_s_hs[0]  = 's'; full_s_hs[1]  = ' '; full_s_hs[2]  = 'h';
                full_s_hs[3]  = 's'; full_s_hs[4]  = ' '; full_s_hs[5]  = 't';
                full_s_hs[6]  = 'r'; full_s_hs[7]  = 'a'; full_s_hs[8]  = 'f';
                full_s_hs[9]  = 'f'; full_s_hs[10] = 'i'; full_s_hs[11] = 'c';

                tls13_derive_secret(@ctx.handshake_secret[0],
                                    @full_c_hs[0], 12,
                                    txhash_server_hello, 32,
                                    @c_hs_ts[0]);

                tls13_derive_secret(@ctx.handshake_secret[0],
                                    @full_s_hs[0], 12,
                                    txhash_server_hello, 32,
                                    @s_hs_ts[0]);
            };

            tls13_derive_traffic_keys(@c_hs_ts[0], @ctx.client_hs);
            tls13_derive_traffic_keys(@s_hs_ts[0], @ctx.server_hs);

            // Install handshake write/read GCM contexts
            crypto::encryption::AES::gcm_init(@ctx.gcm_write, @ctx.client_hs.key[0]);
            crypto::encryption::AES::gcm_init(@ctx.gcm_read,  @ctx.server_hs.key[0]);

            // ---- Master Secret ----
            // derived_from_hs = Derive-Secret(hs_secret, "derived", "")
            tls13_derive_secret(@ctx.handshake_secret[0],
                                @lbl_derived[0], 7,
                                @empty_hash[0], 32,
                                @derived[0]);

            // master_secret = HKDF-Extract(derived_from_hs, zeros)
            crypto::KDF::HKDF::hkdf_extract(@derived[0], 32, @zeros[0], 32, @ctx.master_secret[0]);

            // ---- Application traffic secrets ----
            {
                byte[16] full_c_ap, full_s_ap;
                full_c_ap[0]  = 'c'; full_c_ap[1]  = ' '; full_c_ap[2]  = 'a';
                full_c_ap[3]  = 'p'; full_c_ap[4]  = ' '; full_c_ap[5]  = 't';
                full_c_ap[6]  = 'r'; full_c_ap[7]  = 'a'; full_c_ap[8]  = 'f';
                full_c_ap[9]  = 'f'; full_c_ap[10] = 'i'; full_c_ap[11] = 'c';

                full_s_ap[0]  = 's'; full_s_ap[1]  = ' '; full_s_ap[2]  = 'a';
                full_s_ap[3]  = 'p'; full_s_ap[4]  = ' '; full_s_ap[5]  = 't';
                full_s_ap[6]  = 'r'; full_s_ap[7]  = 'a'; full_s_ap[8]  = 'f';
                full_s_ap[9]  = 'f'; full_s_ap[10] = 'i'; full_s_ap[11] = 'c';

                tls13_derive_secret(@ctx.master_secret[0],
                                    @full_c_ap[0], 12,
                                    txhash_server_fin, 32,
                                    @c_app_ts[0]);

                tls13_derive_secret(@ctx.master_secret[0],
                                    @full_s_ap[0], 12,
                                    txhash_server_fin, 32,
                                    @s_app_ts[0]);
            };

            tls13_derive_traffic_keys(@c_app_ts[0], @ctx.client_app);
            tls13_derive_traffic_keys(@s_app_ts[0], @ctx.server_app);
            return;
        };

        // ============================================================
        // Finished MAC
        //
        // RFC 8446 §4.4.4:
        //   finished_key = HKDF-Expand-Label(base_key, "finished", "", Hash.length)
        //   verify_data  = HMAC-SHA-256(finished_key, Transcript-Hash(handshake_context))
        // ============================================================
        def tls13_compute_finished(byte* base_key, byte* txhash, byte* out) -> void
        {
            byte[32] finished_key;
            byte[16] lbl;
            int i;

            lbl[0] = 'f'; lbl[1] = 'i'; lbl[2] = 'n'; lbl[3] = 'i';
            lbl[4] = 's'; lbl[5] = 'h'; lbl[6] = 'e'; lbl[7] = 'd';

            tls13_expand_label(base_key,
                               @lbl[0], 8,
                               (byte*)0, 0,
                               @finished_key[0], TLS13_HASH_LEN);

            crypto::KDF::HKDF::hmac_sha256(@finished_key[0], TLS13_HASH_LEN,
                                           txhash, TLS13_HASH_LEN,
                                           out);
            return;
        };

        // ============================================================
        // Build ClientHello
        //
        // ClientHello structure (RFC 8446 §4.1.2):
        //   legacy_version     : 0x0303
        //   random             : 32 bytes (we use a fixed test nonce; real impl needs CSPRNG)
        //   legacy_session_id  : 0 bytes (empty)
        //   cipher_suites      : TLS_AES_128_GCM_SHA256 (2 bytes)
        //   legacy_compression : 0x01 0x00
        //   extensions:
        //     supported_versions : 0x0304
        //     supported_groups   : x25519
        //     signature_algs     : rsa_pss_rsae_sha256, ecdsa_secp256r1_sha256
        //     key_share          : x25519 public key (32 bytes)
        //     server_name        : hostname (SNI)
        //
        // Returns total handshake fragment length written into buf.
        // buf must be at least 512 + hostname_len bytes.
        // ============================================================
        def tls13_build_client_hello(TLS13_CTX* ctx,
                                     byte* hostname, int hostname_len,
                                     byte* buf) -> int
        {
            int pos, ext_start, ext_len_pos, hs_start;
            int ext_total, hs_len, i;

            // Handshake header: type(1) + length(3) — fill length after
            buf[0] = (byte)TLS_HT_CLIENT_HELLO;
            hs_start = 1;
            pos = 4; // skip 3-byte length field for now

            // legacy_version = 0x0303
            buf[pos] = (byte)TLS_VERSION_12_HI; pos++;
            buf[pos] = (byte)TLS_VERSION_12_LO; pos++;

            // random (32 bytes) — use our ephemeral public key bytes as the nonce
            // (sufficient for a test/bootstrap; production should use a CSPRNG here)
            for (i = 0; i < 32; i++) { buf[pos + i] = ctx.our_pub[i]; };
            pos = pos + 32;

            // legacy_session_id: 0 length
            buf[pos] = '\0'; pos++;

            // cipher_suites: 2 suites length = 2, then TLS_AES_128_GCM_SHA256
            buf[pos] = (byte)0x00; buf[pos+1] = (byte)0x02; pos = pos + 2;
            buf[pos] = (byte)TLS_AES_128_GCM_SHA256_HI;
            buf[pos+1] = (byte)TLS_AES_128_GCM_SHA256_LO;
            pos = pos + 2;

            // legacy_compression_methods: length=1, method=0 (null)
            buf[pos] = (byte)0x01; pos++;
            buf[pos] = '\0'; pos++;

            // Extensions — record position of 2-byte total length
            ext_len_pos = pos;
            pos = pos + 2;
            ext_start = pos;

            // --- Extension: supported_versions (43) ---
            // ext_type(2) + ext_len(2) + versions_len(1) + 0x0304(2)
            tls_put_u16(@buf[pos], TLS_EXT_SUPPORTED_VERSIONS); pos = pos + 2;
            tls_put_u16(@buf[pos], 3); pos = pos + 2; // ext data length = 3
            buf[pos] = (byte)0x02; pos++;             // versions list length = 2
            buf[pos] = (byte)TLS_VERSION_13_HI; pos++;
            buf[pos] = (byte)TLS_VERSION_13_LO; pos++;

            // --- Extension: supported_groups (10) ---
            // ext_type(2) + ext_len(2) + groups_len(2) + x25519(2)
            tls_put_u16(@buf[pos], TLS_EXT_SUPPORTED_GROUPS); pos = pos + 2;
            tls_put_u16(@buf[pos], 4); pos = pos + 2;
            tls_put_u16(@buf[pos], 2); pos = pos + 2; // named_group_list length
            buf[pos] = (byte)TLS_GROUP_X25519_HI; pos++;
            buf[pos] = (byte)TLS_GROUP_X25519_LO; pos++;

            // --- Extension: signature_algorithms (13) ---
            // rsa_pss_rsae_sha256 (0x0804) + ecdsa_secp256r1_sha256 (0x0403)
            tls_put_u16(@buf[pos], TLS_EXT_SIG_ALGS); pos = pos + 2;
            tls_put_u16(@buf[pos], 6); pos = pos + 2;
            tls_put_u16(@buf[pos], 4); pos = pos + 2; // algs list length
            buf[pos] = (byte)TLS_SIG_RSA_PSS_SHA256_HI; pos++;
            buf[pos] = (byte)TLS_SIG_RSA_PSS_SHA256_LO; pos++;
            buf[pos] = (byte)TLS_SIG_ECDSA_SHA256_HI;   pos++;
            buf[pos] = (byte)TLS_SIG_ECDSA_SHA256_LO;   pos++;

            // --- Extension: key_share (51) ---
            // ext_type(2) + ext_len(2) + client_shares_len(2) + group(2) + key_len(2) + key(32)
            tls_put_u16(@buf[pos], TLS_EXT_KEY_SHARE); pos = pos + 2;
            tls_put_u16(@buf[pos], 38); pos = pos + 2;   // ext data length
            tls_put_u16(@buf[pos], 36); pos = pos + 2;   // client_shares length
            buf[pos] = (byte)TLS_GROUP_X25519_HI; pos++;
            buf[pos] = (byte)TLS_GROUP_X25519_LO; pos++;
            tls_put_u16(@buf[pos], 32); pos = pos + 2;   // key_exchange length
            for (i = 0; i < 32; i++) { buf[pos + i] = ctx.our_pub[i]; };
            pos = pos + 32;

            // --- Extension: server_name (0) ---
            // ext_type(2) + ext_len(2) + list_len(2) + name_type(1) + name_len(2) + hostname
            tls_put_u16(@buf[pos], TLS_EXT_SERVER_NAME); pos = pos + 2;
            tls_put_u16(@buf[pos], hostname_len + 5); pos = pos + 2;
            tls_put_u16(@buf[pos], hostname_len + 3); pos = pos + 2; // list length
            buf[pos] = '\0'; pos++;                                    // name_type = host_name
            tls_put_u16(@buf[pos], hostname_len); pos = pos + 2;
            for (i = 0; i < hostname_len; i++) { buf[pos + i] = hostname[i]; };
            pos = pos + hostname_len;

            // Fill extensions total length
            ext_total = pos - ext_start;
            tls_put_u16(@buf[ext_len_pos], ext_total);

            // Fill handshake message length (bytes after the 4-byte header)
            hs_len = pos - 4;
            tls_put_u24(@buf[1], hs_len);

            return pos;
        };

        // ============================================================
        // Parse ServerHello
        //
        // Extracts the server's x25519 public key from the key_share extension.
        // Returns 1 on success, 0 on failure.
        // ============================================================
        def tls13_parse_server_hello(TLS13_CTX* ctx, byte* buf, int len) -> int
        {
            int pos, ext_total, ext_end, ext_type, ext_len;
            int ks_group, ks_key_len, i;

            // Skip: legacy_version(2) + random(32) + session_id_len(1) + session_id(var)
            // + cipher_suite(2) + compression(1)
            if (len < 38) { return 0; };
            pos = 2 + 32; // version + random
            // session_id
            pos = pos + 1 + (int)(buf[pos] & 0xFF); // skip len + data
            pos = pos + 2; // cipher suite
            pos = pos + 1; // compression

            // Extensions
            if (pos + 2 > len) { return 0; };
            ext_total = tls_get_u16(@buf[pos]); pos = pos + 2;
            ext_end   = pos + ext_total;

            while (pos + 4 <= ext_end)
            {
                ext_type = tls_get_u16(@buf[pos]); pos = pos + 2;
                ext_len  = tls_get_u16(@buf[pos]); pos = pos + 2;

                if (ext_type == TLS_EXT_KEY_SHARE)
                {
                    // key_share: group(2) + key_len(2) + key_data
                    if (ext_len < 36) { return 0; };
                    ks_group   = tls_get_u16(@buf[pos]);
                    ks_key_len = tls_get_u16(@buf[pos + 2]);
                    if ((ks_group != (TLS_GROUP_X25519_HI << 8 | TLS_GROUP_X25519_LO)) |
                        (ks_key_len != 32))
                    {
                        return 0;
                    };
                    for (i = 0; i < 32; i++) { ctx.their_pub[i] = buf[pos + 4 + i]; };
                };

                pos = pos + ext_len;
            };

            return 1;
        };

        // ============================================================
        // tls13_connect — full TLS 1.3 handshake
        //
        // Flow:
        //   1. Generate x25519 ephemeral key pair
        //   2. Build & send ClientHello
        //   3. Receive ServerHello, parse key_share
        //   4. Compute x25519 shared secret
        //   5. Derive handshake keys, install GCM contexts
        //   6. Receive & decrypt: ChangeCipherSpec (optional), EncryptedExtensions,
        //      Certificate, CertificateVerify, Finished
        //   7. Verify server Finished MAC
        //   8. Send client Finished
        //   9. Derive application keys
        //
        // Returns 1 on success, 0 on any failure.
        // ============================================================
        def tls13_connect(TLS13_CTX* ctx, int sockfd,
                          byte* hostname, int hostname_len) -> int
        {
            byte[16384] buf;
            byte[5]    rec_hdr;
            byte[32]   txhash_sh, txhash_sf, server_fin_verify, client_fin_verify;
            SHA256_CTX tx_ctx_at_sh;
            int        rec_type, rec_len, hs_type, hs_len, i, result;
            int        pos;

            ctx.sockfd        = sockfd;
            ctx.handshake_done = 0;

            // --------------------------------------------------
            // 1. Generate ephemeral x25519 key pair
            //    Private key: use a deterministic scalar derived from
            //    a fixed seed XORed with its own address so different
            //    calls produce different keys without a CSPRNG.
            //    Production code must replace this with a CSPRNG read.
            // --------------------------------------------------
            {
                byte[32] seed;
                u64 addr_bits;
                addr_bits = (u64)@seed[0];
                for (i = 0; i < 32; i++)
                {
                    seed[i] = (byte)((addr_bits >> ((i % 8) * 8)) & 0xFF);
                    seed[i] = seed[i] ^^ (byte)(i * 7 + 13);
                };
                // RFC 7748 §5: clamp the scalar
                seed[0]  = seed[0]  & (byte)0xF8;
                seed[31] = (seed[31] & (byte)0x7F) | (byte)0x40;
                for (i = 0; i < 32; i++) { ctx.our_priv[i] = seed[i]; };
            };
            crypto::ECDH::X25519::x25519_pubkey(@ctx.our_pub[0], @ctx.our_priv[0]);

            // --------------------------------------------------
            // 2. Build ClientHello and send it
            // --------------------------------------------------
            {
                int ch_len;
                ch_len = tls13_build_client_hello(ctx, hostname, hostname_len, @buf[0]);
                // Feed ClientHello into transcript (the 4-byte handshake header + body)
                crypto::hashing::SHA256::sha256_init(@ctx.transcript);
                crypto::hashing::SHA256::sha256_update(@ctx.transcript, @buf[0], (u64)ch_len);
                // Send as handshake record
                if (!tls_send_record_plain(sockfd, TLS_CT_HANDSHAKE, @buf[0], ch_len))
                {
                    return 0;
                };
            };

            // --------------------------------------------------
            // 3. Receive ServerHello
            // --------------------------------------------------
            // Read record header
            if (!tls_recv_exact(sockfd, @rec_hdr[0], 5)) { return 0; };
            rec_type = (int)(rec_hdr[0] & 0xFF);
            rec_len  = tls_get_u16(@rec_hdr[3]);
            if ((rec_type != TLS_CT_HANDSHAKE) | (rec_len > 16384)) { return 0; };
            if (!tls_recv_exact(sockfd, @buf[0], rec_len)) { return 0; };

            // buf[0] = handshake type, buf[1..3] = length
            hs_type = (int)(buf[0] & 0xFF);
            hs_len  = tls_get_u24(@buf[1]);
            if (hs_type != TLS_HT_SERVER_HELLO) { return 0; };

            // Feed ServerHello into transcript
            crypto::hashing::SHA256::sha256_update(@ctx.transcript, @buf[0], (u64)(hs_len + 4));

            // Parse server key_share from the body (starting at buf[4])
            if (!tls13_parse_server_hello(ctx, @buf[4], hs_len)) { return 0; };

            // Snapshot transcript hash at ServerHello for key derivation
            tx_ctx_at_sh = ctx.transcript;
            crypto::hashing::SHA256::sha256_final(@tx_ctx_at_sh, @txhash_sh[0]);

            // --------------------------------------------------
            // 4. Compute x25519 shared secret
            // --------------------------------------------------
            crypto::ECDH::X25519::x25519(@ctx.shared_secret[0],
                                         @ctx.our_priv[0],
                                         @ctx.their_pub[0]);

            // --------------------------------------------------
            // 5. Derive handshake keys (we'll fill app keys after server Finished)
            //    Pass a placeholder for txhash_sf — we update app keys later.
            // --------------------------------------------------
            // We call tls13_key_schedule twice conceptually; but since we don't
            // yet have the server Finished hash, we derive handshake keys now
            // using a temporary dummy for the app key derivation, then re-derive
            // app keys once we have the server Finished hash.
            // Simpler approach: derive hs keys + master now, store traffic secrets,
            // then derive app keys once we have txhash_sf.
            {
                byte[32] zeros, derived, c_hs_ts, s_hs_ts;
                byte[32] empty_hash;
                byte[16] lbl_c_hs, lbl_s_hs, lbl_derived;

                for (i = 0; i < 32; i++) { zeros[i] = '\0'; };
                tls13_get_empty_hash(@empty_hash[0]);

                lbl_derived[0] = 'd'; lbl_derived[1] = 'e'; lbl_derived[2] = 'r';
                lbl_derived[3] = 'i'; lbl_derived[4] = 'v'; lbl_derived[5] = 'e';
                lbl_derived[6] = 'd';

                // early_secret = HKDF-Extract(0^32, 0^32)
                crypto::KDF::HKDF::hkdf_extract(@zeros[0], 32, @zeros[0], 32, @ctx.early_secret[0]);

                // derived_from_early
                tls13_derive_secret(@ctx.early_secret[0], @lbl_derived[0], 7,
                                    @empty_hash[0], 32, @derived[0]);

                // handshake_secret = HKDF-Extract(derived, ecdh)
                crypto::KDF::HKDF::hkdf_extract(@derived[0], 32,
                                                @ctx.shared_secret[0], 32,
                                                @ctx.handshake_secret[0]);

                lbl_c_hs[0]  = 'c'; lbl_c_hs[1]  = ' '; lbl_c_hs[2]  = 'h';
                lbl_c_hs[3]  = 's'; lbl_c_hs[4]  = ' '; lbl_c_hs[5]  = 't';
                lbl_c_hs[6]  = 'r'; lbl_c_hs[7]  = 'a'; lbl_c_hs[8]  = 'f';
                lbl_c_hs[9]  = 'f'; lbl_c_hs[10] = 'i'; lbl_c_hs[11] = 'c';

                lbl_s_hs[0]  = 's'; lbl_s_hs[1]  = ' '; lbl_s_hs[2]  = 'h';
                lbl_s_hs[3]  = 's'; lbl_s_hs[4]  = ' '; lbl_s_hs[5]  = 't';
                lbl_s_hs[6]  = 'r'; lbl_s_hs[7]  = 'a'; lbl_s_hs[8]  = 'f';
                lbl_s_hs[9]  = 'f'; lbl_s_hs[10] = 'i'; lbl_s_hs[11] = 'c';

                tls13_derive_secret(@ctx.handshake_secret[0], @lbl_c_hs[0], 12,
                                    @txhash_sh[0], 32, @c_hs_ts[0]);
                tls13_derive_secret(@ctx.handshake_secret[0], @lbl_s_hs[0], 12,
                                    @txhash_sh[0], 32, @s_hs_ts[0]);

                tls13_derive_traffic_keys(@c_hs_ts[0], @ctx.client_hs);
                tls13_derive_traffic_keys(@s_hs_ts[0], @ctx.server_hs);

                // Install handshake GCM contexts
                crypto::encryption::AES::gcm_init(@ctx.gcm_write, @ctx.client_hs.key[0]);
                crypto::encryption::AES::gcm_init(@ctx.gcm_read,  @ctx.server_hs.key[0]);

                // Compute master_secret now (needs derived_from_hs)
                tls13_derive_secret(@ctx.handshake_secret[0], @lbl_derived[0], 7,
                                    @empty_hash[0], 32, @derived[0]);
                crypto::KDF::HKDF::hkdf_extract(@derived[0], 32, @zeros[0], 32,
                                                @ctx.master_secret[0]);
            };

            // --------------------------------------------------
            // 6. Receive encrypted handshake messages from server
            //    Expect: (optional CCS), EncryptedExtensions, Certificate,
            //            CertificateVerify, Finished
            // --------------------------------------------------
            {
                int saw_finished;

                while (saw_finished == 0)
                {
                    // Read a record header
                    if (!tls_recv_exact(sockfd, @rec_hdr[0], 5)) { return 0; };
                    rec_type = (int)(rec_hdr[0] & 0xFF);
                    rec_len  = tls_get_u16(@rec_hdr[3]);
                    if (rec_len > 16384) { return 0; };

                    // Receive record body
                    if (!tls_recv_exact(sockfd, @buf[0], rec_len)) { return 0; };

                    // ChangeCipherSpec records are ignored (compatibility middlebox)
                    if (rec_type == TLS_CT_CHANGE_CIPHER_SPEC) { saw_finished = 0; };

                    if (rec_type == TLS_CT_APPLICATION_DATA)
                    {
                        // Decrypt in-place
                        int plain_len;
                        plain_len = tls_decrypt_record(ctx, @buf[0], rec_len, @rec_hdr[0]);
                        if (plain_len < 0) { return 0; };

                        // Inner content type is the last byte of the plaintext
                        int inner_type;
                        inner_type = (int)(buf[plain_len - 1] & 0xFF);
                        int msg_body_len;
                        msg_body_len = plain_len - 1; // strip inner type byte

                        if (inner_type == TLS_CT_HANDSHAKE)
                        {
                            // May contain multiple handshake messages
                            int hpos;
                            while (hpos + 4 <= msg_body_len)
                            {
                                hs_type = (int)(buf[hpos] & 0xFF);
                                hs_len  = tls_get_u24(@buf[hpos + 1]);

                                if (hs_type == TLS_HT_FINISHED)
                                {
                                    // Snapshot transcript BEFORE feeding Finished
                                    SHA256_CTX snap;
                                    snap = ctx.transcript;
                                    crypto::hashing::SHA256::sha256_final(@snap, @txhash_sf[0]);

                                    // Verify server Finished
                                    tls13_compute_finished(@ctx.server_hs.key[0],
                                                           @txhash_sf[0],
                                                           @server_fin_verify[0]);

                                    int fin_diff;
                                    for (i = 0; i < 32; i++)
                                    {
                                        fin_diff = fin_diff |
                                            (int)(server_fin_verify[i] ^^ buf[hpos + 4 + i]);
                                    };
                                    if (fin_diff != 0) { return 0; };

                                    // Feed Finished message into transcript
                                    crypto::hashing::SHA256::sha256_update(
                                        @ctx.transcript, @buf[hpos], (u64)(hs_len + 4));

                                    saw_finished = 1;
                                }
                                else
                                {
                                    // Feed all other handshake messages into transcript
                                    crypto::hashing::SHA256::sha256_update(
                                        @ctx.transcript, @buf[hpos], (u64)(hs_len + 4));
                                };

                                hpos = hpos + 4 + hs_len;
                            };
                        };
                    };
                };
            };

            // --------------------------------------------------
            // 7. Derive application traffic keys
            //    txhash_sf = hash of transcript through server Finished
            // --------------------------------------------------
            {
                byte[32] c_app_ts, s_app_ts;
                byte[16] lbl_c_ap, lbl_s_ap;

                lbl_c_ap[0]  = 'c'; lbl_c_ap[1]  = ' '; lbl_c_ap[2]  = 'a';
                lbl_c_ap[3]  = 'p'; lbl_c_ap[4]  = ' '; lbl_c_ap[5]  = 't';
                lbl_c_ap[6]  = 'r'; lbl_c_ap[7]  = 'a'; lbl_c_ap[8]  = 'f';
                lbl_c_ap[9]  = 'f'; lbl_c_ap[10] = 'i'; lbl_c_ap[11] = 'c';

                lbl_s_ap[0]  = 's'; lbl_s_ap[1]  = ' '; lbl_s_ap[2]  = 'a';
                lbl_s_ap[3]  = 'p'; lbl_s_ap[4]  = ' '; lbl_s_ap[5]  = 't';
                lbl_s_ap[6]  = 'r'; lbl_s_ap[7]  = 'a'; lbl_s_ap[8]  = 'f';
                lbl_s_ap[9]  = 'f'; lbl_s_ap[10] = 'i'; lbl_s_ap[11] = 'c';

                tls13_derive_secret(@ctx.master_secret[0], @lbl_c_ap[0], 12,
                                    @txhash_sf[0], 32, @c_app_ts[0]);
                tls13_derive_secret(@ctx.master_secret[0], @lbl_s_ap[0], 12,
                                    @txhash_sf[0], 32, @s_app_ts[0]);

                tls13_derive_traffic_keys(@c_app_ts[0], @ctx.client_app);
                tls13_derive_traffic_keys(@s_app_ts[0], @ctx.server_app);
            };

            // --------------------------------------------------
            // 8. Send client Finished
            //    Transcript hash at this point covers everything through server Finished.
            //    client Finished verify_data = HMAC(client_hs_finished_key, txhash_cf)
            //    txhash_cf = transcript hash BEFORE feeding client Finished itself.
            // --------------------------------------------------
            {
                byte[32] txhash_cf;
                byte[36] finished_msg; // 4-byte HS header + 32-byte verify_data
                SHA256_CTX snap;

                snap = ctx.transcript;
                crypto::hashing::SHA256::sha256_final(@snap, @txhash_cf[0]);

                tls13_compute_finished(@ctx.client_hs.key[0], @txhash_cf[0],
                                       @client_fin_verify[0]);

                finished_msg[0] = (byte)TLS_HT_FINISHED;
                tls_put_u24(@finished_msg[1], 32);
                for (i = 0; i < 32; i++) { finished_msg[4 + i] = client_fin_verify[i]; };

                // Send encrypted with handshake keys
                if (!tls_send_record_enc(ctx, TLS_CT_HANDSHAKE, @finished_msg[0], 36))
                {
                    return 0;
                };
            };

            // --------------------------------------------------
            // 9. Switch to application keys
            // --------------------------------------------------
            crypto::encryption::AES::gcm_init(@ctx.gcm_write, @ctx.client_app.key[0]);
            crypto::encryption::AES::gcm_init(@ctx.gcm_read,  @ctx.server_app.key[0]);
            ctx.handshake_done = 1;

            return 1;
        };

        // ============================================================
        // tls13_send — encrypt and send application data
        //
        // Fragments into TLS13_MAX_PLAINTEXT-byte records if needed.
        // Returns total bytes from data sent, -1 on error.
        // ============================================================
        def tls13_send(TLS13_CTX* ctx, byte* xdata, int len) -> int
        {
            int sent, chunk, offset;
            while (offset < len)
            {
                chunk = len - offset;
                if (chunk > TLS13_MAX_PLAINTEXT) { chunk = TLS13_MAX_PLAINTEXT; };
                if (!tls_send_record_enc(ctx, TLS_CT_APPLICATION_DATA,
                                         (byte*)((u64)xdata + (u64)offset), chunk))
                {
                    return -1;
                };
                offset = offset + chunk;
            };
            return len;
        };

        // ============================================================
        // tls13_recv — receive and decrypt one TLS application record
        //
        // Reads exactly one record. Caller must call repeatedly if more data expected.
        // Returns number of plaintext bytes written into buf, -1 on error.
        // Silently discards non-application-data records (alerts, NewSessionTicket).
        // ============================================================
        def tls13_recv(TLS13_CTX* ctx, byte* buf, int buf_len) -> int
        {
            byte[TLS13_MAX_PLAINTEXT + TLS13_RECORD_OVERHEAD] rec_body;
            byte[5]  rec_hdr;
            int rec_type, rec_len, plain_len, inner_type, i;

            while (true)
            {
                if (!tls_recv_exact(ctx.sockfd, @rec_hdr[0], 5)) { return -1; };
                rec_type = (int)(rec_hdr[0] & 0xFF);
                rec_len  = tls_get_u16(@rec_hdr[3]);

                if (rec_len > (TLS13_MAX_PLAINTEXT + TLS13_RECORD_OVERHEAD)) { return -1; };
                if (!tls_recv_exact(ctx.sockfd, @rec_body[0], rec_len)) { return -1; };

                if (rec_type == TLS_CT_ALERT)
                {
                    // close_notify or fatal alert — signal EOF
                    return -1;
                };

                if (rec_type == TLS_CT_APPLICATION_DATA)
                {
                    plain_len = tls_decrypt_record(ctx, @rec_body[0], rec_len, @rec_hdr[0]);
                    if (plain_len < 0) { return -1; };

                    // Strip inner content type byte
                    inner_type = (int)(rec_body[plain_len - 1] & 0xFF);
                    plain_len  = plain_len - 1;

                    if (inner_type == TLS_CT_APPLICATION_DATA)
                    {
                        if (plain_len > buf_len) { plain_len = buf_len; };
                        for (i = 0; i < plain_len; i++) { buf[i] = rec_body[i]; };
                        return plain_len;
                    };
                    // Other inner types (NewSessionTicket etc.) — discard and loop
                };
                // Non-application outer records — discard and loop
            };
            return -1;
        };

        // ============================================================
        // tls13_close — send close_notify and shut down
        // ============================================================
        def tls13_close(TLS13_CTX* ctx) -> void
        {
            byte[2] alert;
            alert[0] = (byte)TLS_ALERT_LEVEL_WARNING;
            alert[1] = (byte)TLS_ALERT_CLOSE_NOTIFY;
            tls_send_record_enc(ctx, TLS_CT_ALERT, @alert[0], 2);
            return;
        };

        // ============================================================
        // tls13_accept — server-side TLS 1.3 handshake
        //
        // Called after a TCP accept(). Performs the full server-side
        // TLS 1.3 handshake:
        //   1. Receive and parse ClientHello — extract client x25519 key_share
        //   2. Generate server ephemeral x25519 key pair
        //   3. Send ServerHello (with server key_share)
        //   4. Derive handshake keys from ECDH shared secret
        //   5. Send encrypted: EncryptedExtensions, Certificate (stub),
        //      CertificateVerify (stub), Finished
        //   6. Receive and verify client Finished
        //   7. Derive and install application keys
        //
        // Certificate is sent as an empty list — valid wire format, and the
        // client (tls13_connect) does not verify the certificate chain.
        // CertificateVerify is omitted (zero-length stub message body) since
        // there is no real private key to sign with.
        //
        // Returns 1 on success, 0 on any failure.
        // ============================================================
        def tls13_accept(TLS13_CTX* ctx, int sockfd) -> int
        {
            byte[16384] buf;
            byte[5]     rec_hdr;
            byte[32]    txhash_sh, txhash_sf;
            byte[32]    server_fin_mac, client_fin_verify;
            int         rec_type, rec_len, hs_type, hs_len;
            int         i, pos, ext_end, ext_len, ext_type, result;

            ctx.sockfd         = sockfd;
            ctx.handshake_done = 0;
            ctx.is_server      = 1;

            // --------------------------------------------------
            // 1. Receive ClientHello
            // --------------------------------------------------
            if (!tls_recv_exact(sockfd, @rec_hdr[0], 5)) { return 0; };
            rec_type = (int)(rec_hdr[0] & 0xFF);
            rec_len  = tls_get_u16(@rec_hdr[3]);
            if ((rec_type != TLS_CT_HANDSHAKE) | (rec_len > 16384)) { return 0; };
            if (!tls_recv_exact(sockfd, @buf[0], rec_len)) { return 0; };

            hs_type = (int)(buf[0] & 0xFF);
            hs_len  = tls_get_u24(@buf[1]);
            if (hs_type != TLS_HT_CLIENT_HELLO) { return 0; };

            // Feed ClientHello into transcript
            crypto::hashing::SHA256::sha256_init(@ctx.transcript);
            crypto::hashing::SHA256::sha256_update(@ctx.transcript, @buf[0], (u64)(hs_len + 4));

            // Parse client x25519 key_share from ClientHello body (buf[4..])
            // ClientHello body: version(2) + random(32) + sid_len(1) + sid(var)
            //                   + cs_len(2) + cs(var) + comp_len(1) + comp(var)
            //                   + ext_len(2) + extensions
            {
                int ch_pos;
                ch_pos = 4; // skip hs header
                ch_pos = ch_pos + 2 + 32; // skip version + random
                ch_pos = ch_pos + 1 + (int)(buf[ch_pos] & 0xFF); // skip sid
                int cs_len;
                cs_len = tls_get_u16(@buf[ch_pos]); ch_pos = ch_pos + 2 + cs_len;
                int comp_len;
                comp_len = (int)(buf[ch_pos] & 0xFF); ch_pos = ch_pos + 1 + comp_len;

                // Extensions
                int ch_ext_total;
                ch_ext_total = tls_get_u16(@buf[ch_pos]); ch_pos = ch_pos + 2;
                ext_end = ch_pos + ch_ext_total;

                while (ch_pos + 4 <= ext_end)
                {
                    ext_type = tls_get_u16(@buf[ch_pos]); ch_pos = ch_pos + 2;
                    ext_len  = tls_get_u16(@buf[ch_pos]); ch_pos = ch_pos + 2;

                    if (ext_type == TLS_EXT_KEY_SHARE)
                    {
                        // client_shares_len(2) + group(2) + key_len(2) + key(32)
                        int ks_list_len, ks_group, ks_key_len;
                        ks_list_len = tls_get_u16(@buf[ch_pos]);
                        ks_group    = tls_get_u16(@buf[ch_pos + 2]);
                        ks_key_len  = tls_get_u16(@buf[ch_pos + 4]);
                        if ((ks_group == (TLS_GROUP_X25519_HI << 8 | TLS_GROUP_X25519_LO)) &
                            (ks_key_len == 32))
                        {
                            for (i = 0; i < 32; i++)
                            {
                                ctx.their_pub[i] = buf[ch_pos + 6 + i];
                            };
                        };
                    };

                    ch_pos = ch_pos + ext_len;
                };
            };

            // --------------------------------------------------
            // 2. Generate server ephemeral x25519 key pair
            // --------------------------------------------------
            {
                byte[32] seed;
                u64 addr_bits;
                addr_bits = (u64)@seed[0];
                for (i = 0; i < 32; i++)
                {
                    seed[i] = (byte)((addr_bits >> ((i % 8) * 8)) & 0xFF);
                    seed[i] = seed[i] ^^ (byte)(i * 11 + 7);
                };
                seed[0]  = seed[0]  & (byte)0xF8;
                seed[31] = (seed[31] & (byte)0x7F) | (byte)0x40;
                for (i = 0; i < 32; i++) { ctx.our_priv[i] = seed[i]; };
            };
            crypto::ECDH::X25519::x25519_pubkey(@ctx.our_pub[0], @ctx.our_priv[0]);

            // --------------------------------------------------
            // 3. Build and send ServerHello
            //
            // ServerHello body:
            //   version(2) + random(32) + sid_len(1) + sid(0)
            //   + cipher_suite(2) + compression(1)
            //   + ext_len(2) + supported_versions(7) + key_share(40)
            // --------------------------------------------------
            {
                int sh_body_pos, sh_ext_start, sh_ext_len_pos, sh_len;

                // hs header: type(1) + length(3)
                buf[0] = (byte)TLS_HT_SERVER_HELLO;
                pos = 4; // fill length after

                // legacy_version = 0x0303
                buf[pos] = (byte)TLS_VERSION_12_HI; pos++;
                buf[pos] = (byte)TLS_VERSION_12_LO; pos++;

                // random: use our public key bytes (same CSPRNG caveat as client)
                for (i = 0; i < 32; i++) { buf[pos + i] = ctx.our_pub[i]; };
                pos = pos + 32;

                // legacy_session_id: 0 bytes
                buf[pos] = '\0'; pos++;

                // cipher_suite: TLS_AES_128_GCM_SHA256
                buf[pos] = (byte)TLS_AES_128_GCM_SHA256_HI; pos++;
                buf[pos] = (byte)TLS_AES_128_GCM_SHA256_LO; pos++;

                // compression: 0
                buf[pos] = '\0'; pos++;

                // extensions length placeholder
                sh_ext_len_pos = pos; pos = pos + 2;
                sh_ext_start = pos;

                // supported_versions: 0x0304
                tls_put_u16(@buf[pos], TLS_EXT_SUPPORTED_VERSIONS); pos = pos + 2;
                tls_put_u16(@buf[pos], 2); pos = pos + 2;
                buf[pos] = (byte)TLS_VERSION_13_HI; pos++;
                buf[pos] = (byte)TLS_VERSION_13_LO; pos++;

                // key_share: group(2) + key_len(2) + key(32)
                tls_put_u16(@buf[pos], TLS_EXT_KEY_SHARE); pos = pos + 2;
                tls_put_u16(@buf[pos], 36); pos = pos + 2;
                buf[pos] = (byte)TLS_GROUP_X25519_HI; pos++;
                buf[pos] = (byte)TLS_GROUP_X25519_LO; pos++;
                tls_put_u16(@buf[pos], 32); pos = pos + 2;
                for (i = 0; i < 32; i++) { buf[pos + i] = ctx.our_pub[i]; };
                pos = pos + 32;

                // fill extensions length
                tls_put_u16(@buf[sh_ext_len_pos], pos - sh_ext_start);

                // fill handshake message length
                tls_put_u24(@buf[1], pos - 4);

                sh_len = pos;

                // Feed ServerHello into transcript
                crypto::hashing::SHA256::sha256_update(@ctx.transcript, @buf[0], (u64)sh_len);

                // Send as plaintext handshake record
                if (!tls_send_record_plain(sockfd, TLS_CT_HANDSHAKE, @buf[0], sh_len))
                {
                    return 0;
                };
            };

            // --------------------------------------------------
            // 4. Derive handshake keys
            // --------------------------------------------------
            // Snapshot transcript at ServerHello
            {
                SHA256_CTX snap;
                snap = ctx.transcript;
                crypto::hashing::SHA256::sha256_final(@snap, @txhash_sh[0]);
            };

            // x25519 shared secret
            crypto::ECDH::X25519::x25519(@ctx.shared_secret[0],
                                         @ctx.our_priv[0],
                                         @ctx.their_pub[0]);

            // Full key schedule (handshake + master)
            {
                byte[32] zeros, derived, c_hs_ts, s_hs_ts;
                byte[32] empty_hash;
                byte[16] lbl_c_hs, lbl_s_hs, lbl_derived;

                for (i = 0; i < 32; i++) { zeros[i] = '\0'; };
                tls13_get_empty_hash(@empty_hash[0]);

                lbl_derived[0] = 'd'; lbl_derived[1] = 'e'; lbl_derived[2] = 'r';
                lbl_derived[3] = 'i'; lbl_derived[4] = 'v'; lbl_derived[5] = 'e';
                lbl_derived[6] = 'd';

                crypto::KDF::HKDF::hkdf_extract(@zeros[0], 32, @zeros[0], 32,
                                                @ctx.early_secret[0]);

                tls13_derive_secret(@ctx.early_secret[0], @lbl_derived[0], 7,
                                    @empty_hash[0], 32, @derived[0]);

                crypto::KDF::HKDF::hkdf_extract(@derived[0], 32,
                                                @ctx.shared_secret[0], 32,
                                                @ctx.handshake_secret[0]);

                lbl_c_hs[0]  = 'c'; lbl_c_hs[1]  = ' '; lbl_c_hs[2]  = 'h';
                lbl_c_hs[3]  = 's'; lbl_c_hs[4]  = ' '; lbl_c_hs[5]  = 't';
                lbl_c_hs[6]  = 'r'; lbl_c_hs[7]  = 'a'; lbl_c_hs[8]  = 'f';
                lbl_c_hs[9]  = 'f'; lbl_c_hs[10] = 'i'; lbl_c_hs[11] = 'c';

                lbl_s_hs[0]  = 's'; lbl_s_hs[1]  = ' '; lbl_s_hs[2]  = 'h';
                lbl_s_hs[3]  = 's'; lbl_s_hs[4]  = ' '; lbl_s_hs[5]  = 't';
                lbl_s_hs[6]  = 'r'; lbl_s_hs[7]  = 'a'; lbl_s_hs[8]  = 'f';
                lbl_s_hs[9]  = 'f'; lbl_s_hs[10] = 'i'; lbl_s_hs[11] = 'c';

                tls13_derive_secret(@ctx.handshake_secret[0], @lbl_c_hs[0], 12,
                                    @txhash_sh[0], 32, @c_hs_ts[0]);
                tls13_derive_secret(@ctx.handshake_secret[0], @lbl_s_hs[0], 12,
                                    @txhash_sh[0], 32, @s_hs_ts[0]);

                tls13_derive_traffic_keys(@c_hs_ts[0], @ctx.client_hs);
                tls13_derive_traffic_keys(@s_hs_ts[0], @ctx.server_hs);

                // Server writes with server_hs, reads with client_hs
                crypto::encryption::AES::gcm_init(@ctx.gcm_write, @ctx.server_hs.key[0]);
                crypto::encryption::AES::gcm_init(@ctx.gcm_read,  @ctx.client_hs.key[0]);

                tls13_derive_secret(@ctx.handshake_secret[0], @lbl_derived[0], 7,
                                    @empty_hash[0], 32, @derived[0]);
                crypto::KDF::HKDF::hkdf_extract(@derived[0], 32, @zeros[0], 32,
                                                @ctx.master_secret[0]);
            };

            // --------------------------------------------------
            // 5. Send encrypted server flight:
            //    EncryptedExtensions + Certificate (empty) + Finished
            //
            //    CertificateVerify is omitted — the client does not
            //    verify it and we have no real signing key.
            // --------------------------------------------------

            // Build the entire flight into buf, then send as one record each.

            // --- EncryptedExtensions ---
            // HS header(4) + ext_total_len(2) = 6 bytes, no extensions
            {
                byte[8] ee_msg;
                ee_msg[0] = (byte)TLS_HT_ENCRYPTED_EXTS;
                tls_put_u24(@ee_msg[1], 2);
                ee_msg[4] = '\0'; // extensions length = 0
                ee_msg[5] = '\0';
                crypto::hashing::SHA256::sha256_update(@ctx.transcript, @ee_msg[0], 6);
                if (!tls_send_record_enc(ctx, TLS_CT_HANDSHAKE, @ee_msg[0], 6))
                {
                    return 0;
                };
            };

            // --- Certificate (empty list) ---
            // HS type(1) + length(3) + request_context_len(1) + cert_list_len(3)
            // = 8 bytes total, cert_list_len = 0
            {
                byte[8] cert_msg;
                cert_msg[0] = (byte)TLS_HT_CERTIFICATE;
                tls_put_u24(@cert_msg[1], 4); // body = 4 bytes
                cert_msg[4] = '\0';           // request_context length = 0
                cert_msg[5] = '\0';           // cert_list length (24-bit) = 0
                cert_msg[6] = '\0';
                cert_msg[7] = '\0';
                crypto::hashing::SHA256::sha256_update(@ctx.transcript, @cert_msg[0], 8);
                if (!tls_send_record_enc(ctx, TLS_CT_HANDSHAKE, @cert_msg[0], 8))
                {
                    return 0;
                };
            };

            // --- Finished ---
            // Snapshot transcript hash before Finished
            {
                SHA256_CTX snap;
                snap = ctx.transcript;
                crypto::hashing::SHA256::sha256_final(@snap, @txhash_sf[0]);
            };

            tls13_compute_finished(@ctx.server_hs.key[0], @txhash_sf[0], @server_fin_mac[0]);

            {
                byte[36] fin_msg;
                fin_msg[0] = (byte)TLS_HT_FINISHED;
                tls_put_u24(@fin_msg[1], 32);
                for (i = 0; i < 32; i++) { fin_msg[4 + i] = server_fin_mac[i]; };
                crypto::hashing::SHA256::sha256_update(@ctx.transcript, @fin_msg[0], 36);
                if (!tls_send_record_enc(ctx, TLS_CT_HANDSHAKE, @fin_msg[0], 36))
                {
                    return 0;
                };
            };

            // --------------------------------------------------
            // 6. Derive application keys now
            //    txhash_sf = transcript through server Finished
            // --------------------------------------------------
            {
                byte[32] c_app_ts, s_app_ts;
                byte[16] lbl_c_ap, lbl_s_ap;

                lbl_c_ap[0]  = 'c'; lbl_c_ap[1]  = ' '; lbl_c_ap[2]  = 'a';
                lbl_c_ap[3]  = 'p'; lbl_c_ap[4]  = ' '; lbl_c_ap[5]  = 't';
                lbl_c_ap[6]  = 'r'; lbl_c_ap[7]  = 'a'; lbl_c_ap[8]  = 'f';
                lbl_c_ap[9]  = 'f'; lbl_c_ap[10] = 'i'; lbl_c_ap[11] = 'c';

                lbl_s_ap[0]  = 's'; lbl_s_ap[1]  = ' '; lbl_s_ap[2]  = 'a';
                lbl_s_ap[3]  = 'p'; lbl_s_ap[4]  = ' '; lbl_s_ap[5]  = 't';
                lbl_s_ap[6]  = 'r'; lbl_s_ap[7]  = 'a'; lbl_s_ap[8]  = 'f';
                lbl_s_ap[9]  = 'f'; lbl_s_ap[10] = 'i'; lbl_s_ap[11] = 'c';

                tls13_derive_secret(@ctx.master_secret[0], @lbl_c_ap[0], 12,
                                    @txhash_sf[0], 32, @c_app_ts[0]);
                tls13_derive_secret(@ctx.master_secret[0], @lbl_s_ap[0], 12,
                                    @txhash_sf[0], 32, @s_app_ts[0]);

                tls13_derive_traffic_keys(@c_app_ts[0], @ctx.client_app);
                tls13_derive_traffic_keys(@s_app_ts[0], @ctx.server_app);
            };

            // --------------------------------------------------
            // 7. Receive and verify client Finished
            // --------------------------------------------------
            {
                int saw_client_finished;
                while (saw_client_finished == 0)
                {
                    if (!tls_recv_exact(sockfd, @rec_hdr[0], 5)) { return 0; };
                    rec_type = (int)(rec_hdr[0] & 0xFF);
                    rec_len  = tls_get_u16(@rec_hdr[3]);
                    if (rec_len > 16384) { return 0; };
                    if (!tls_recv_exact(sockfd, @buf[0], rec_len)) { return 0; };

                    if (rec_type == TLS_CT_CHANGE_CIPHER_SPEC) { saw_client_finished = 0; };

                    if (rec_type == TLS_CT_APPLICATION_DATA)
                    {
                        int plain_len;
                        plain_len = tls_decrypt_record(ctx, @buf[0], rec_len, @rec_hdr[0]);
                        if (plain_len < 0) { return 0; };

                        int inner_type;
                        inner_type = (int)(buf[plain_len - 1] & 0xFF);
                        int msg_body_len;
                        msg_body_len = plain_len - 1;

                        if (inner_type == TLS_CT_HANDSHAKE)
                        {
                            int hpos;
                            while (hpos + 4 <= msg_body_len)
                            {
                                hs_type = (int)(buf[hpos] & 0xFF);
                                hs_len  = tls_get_u24(@buf[hpos + 1]);

                                if (hs_type == TLS_HT_FINISHED)
                                {
                                    // Compute expected client Finished
                                    // Transcript hash at this point = through server Finished
                                    // (client computes over transcript before its own Finished)
                                    byte[32] txhash_cf;
                                    SHA256_CTX snap;
                                    snap = ctx.transcript;
                                    crypto::hashing::SHA256::sha256_final(@snap, @txhash_cf[0]);

                                    tls13_compute_finished(@ctx.client_hs.key[0],
                                                           @txhash_cf[0],
                                                           @client_fin_verify[0]);

                                    int fin_diff;
                                    for (i = 0; i < 32; i++)
                                    {
                                        fin_diff = fin_diff |
                                            (int)(client_fin_verify[i] ^^ buf[hpos + 4 + i]);
                                    };
                                    if (fin_diff != 0) { return 0; };

                                    saw_client_finished = 1;
                                };

                                hpos = hpos + 4 + hs_len;
                            };
                        };
                    };
                };
            };

            // --------------------------------------------------
            // 8. Switch to application keys
            //    Server writes with server_app, reads with client_app
            // --------------------------------------------------
            crypto::encryption::AES::gcm_init(@ctx.gcm_write, @ctx.server_app.key[0]);
            crypto::encryption::AES::gcm_init(@ctx.gcm_read,  @ctx.client_app.key[0]);
            ctx.handshake_done = 1;

            return 1;
        };
    };
};

#endif; // FLUX_TLS13
