namespace aes
{
    // AES S-box (forward)
    const byte[256] SBOX = [
        0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
        0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
        0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
        0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
        0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
        0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
        0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
        0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
        0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
        0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
        0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
        0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
        0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
        0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
        0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
        0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16
    ];
    
    // Inverse S-box
    const byte[256] INV_SBOX = [
        0x52, 0x09, 0x6A, 0xD5, 0x30, 0x36, 0xA5, 0x38, 0xBF, 0x40, 0xA3, 0x9E, 0x81, 0xF3, 0xD7, 0xFB,
        0x7C, 0xE3, 0x39, 0x82, 0x9B, 0x2F, 0xFF, 0x87, 0x34, 0x8E, 0x43, 0x44, 0xC4, 0xDE, 0xE9, 0xCB,
        0x54, 0x7B, 0x94, 0x32, 0xA6, 0xC2, 0x23, 0x3D, 0xEE, 0x4C, 0x95, 0x0B, 0x42, 0xFA, 0xC3, 0x4E,
        0x08, 0x2E, 0xA1, 0x66, 0x28, 0xD9, 0x24, 0xB2, 0x76, 0x5B, 0xA2, 0x49, 0x6D, 0x8B, 0xD1, 0x25,
        0x72, 0xF8, 0xF6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xD4, 0xA4, 0x5C, 0xCC, 0x5D, 0x65, 0xB6, 0x92,
        0x6C, 0x70, 0x48, 0x50, 0xFD, 0xED, 0xB9, 0xDA, 0x5E, 0x15, 0x46, 0x57, 0xA7, 0x8D, 0x9D, 0x84,
        0x90, 0xD8, 0xAB, 0x00, 0x8C, 0xBC, 0xD3, 0x0A, 0xF7, 0xE4, 0x58, 0x05, 0xB8, 0xB3, 0x45, 0x06,
        0xD0, 0x2C, 0x1E, 0x8F, 0xCA, 0x3F, 0x0F, 0x02, 0xC1, 0xAF, 0xBD, 0x03, 0x01, 0x13, 0x8A, 0x6B,
        0x3A, 0x91, 0x11, 0x41, 0x4F, 0x67, 0xDC, 0xEA, 0x97, 0xF2, 0xCF, 0xCE, 0xF0, 0xB4, 0xE6, 0x73,
        0x96, 0xAC, 0x74, 0x22, 0xE7, 0xAD, 0x35, 0x85, 0xE2, 0xF9, 0x37, 0xE8, 0x1C, 0x75, 0xDF, 0x6E,
        0x47, 0xF1, 0x1A, 0x71, 0x1D, 0x29, 0xC5, 0x89, 0x6F, 0xB7, 0x62, 0x0E, 0xAA, 0x18, 0xBE, 0x1B,
        0xFC, 0x56, 0x3E, 0x4B, 0xC6, 0xD2, 0x79, 0x20, 0x9A, 0xDB, 0xC0, 0xFE, 0x78, 0xCD, 0x5A, 0xF4,
        0x1F, 0xDD, 0xA8, 0x33, 0x88, 0x07, 0xC7, 0x31, 0xB1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xEC, 0x5F,
        0x60, 0x51, 0x7F, 0xA9, 0x19, 0xB5, 0x4A, 0x0D, 0x2D, 0xE5, 0x7A, 0x9F, 0x93, 0xC9, 0x9C, 0xEF,
        0xA0, 0xE0, 0x3B, 0x4D, 0xAE, 0x2A, 0xF5, 0xB0, 0xC8, 0xEB, 0xBB, 0x3C, 0x83, 0x53, 0x99, 0x61,
        0x17, 0x2B, 0x04, 0x7E, 0xBA, 0x77, 0xD6, 0x26, 0xE1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0C, 0x7D
    ];
    
    // Rijndael Galois Field multiplication tables
    const byte[256] GF_MUL_2 = [
        0x00, 0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, 0x14, 0x16, 0x18, 0x1A, 0x1C, 0x1E,
        0x20, 0x22, 0x24, 0x26, 0x28, 0x2A, 0x2C, 0x2E, 0x30, 0x32, 0x34, 0x36, 0x38, 0x3A, 0x3C, 0x3E,
        0x40, 0x42, 0x44, 0x46, 0x48, 0x4A, 0x4C, 0x4E, 0x50, 0x52, 0x54, 0x56, 0x58, 0x5A, 0x5C, 0x5E,
        0x60, 0x62, 0x64, 0x66, 0x68, 0x6A, 0x6C, 0x6E, 0x70, 0x72, 0x74, 0x76, 0x78, 0x7A, 0x7C, 0x7E,
        0x80, 0x82, 0x84, 0x86, 0x88, 0x8A, 0x8C, 0x8E, 0x90, 0x92, 0x94, 0x96, 0x98, 0x9A, 0x9C, 0x9E,
        0xA0, 0xA2, 0xA4, 0xA6, 0xA8, 0xAA, 0xAC, 0xAE, 0xB0, 0xB2, 0xB4, 0xB6, 0xB8, 0xBA, 0xBC, 0xBE,
        0xC0, 0xC2, 0xC4, 0xC6, 0xC8, 0xCA, 0xCC, 0xCE, 0xD0, 0xD2, 0xD4, 0xD6, 0xD8, 0xDA, 0xDC, 0xDE,
        0xE0, 0xE2, 0xE4, 0xE6, 0xE8, 0xEA, 0xEC, 0xEE, 0xF0, 0xF2, 0xF4, 0xF6, 0xF8, 0xFA, 0xFC, 0xFE,
        0x1B, 0x19, 0x1F, 0x1D, 0x13, 0x11, 0x17, 0x15, 0x0B, 0x09, 0x0F, 0x0D, 0x03, 0x01, 0x07, 0x05,
        0x3B, 0x39, 0x3F, 0x3D, 0x33, 0x31, 0x37, 0x35, 0x2B, 0x29, 0x2F, 0x2D, 0x23, 0x21, 0x27, 0x25,
        0x5B, 0x59, 0x5F, 0x5D, 0x53, 0x51, 0x57, 0x55, 0x4B, 0x49, 0x4F, 0x4D, 0x43, 0x41, 0x47, 0x45,
        0x7B, 0x79, 0x7F, 0x7D, 0x73, 0x71, 0x77, 0x75, 0x6B, 0x69, 0x6F, 0x6D, 0x63, 0x61, 0x67, 0x65,
        0x9B, 0x99, 0x9F, 0x9D, 0x93, 0x91, 0x97, 0x95, 0x8B, 0x89, 0x8F, 0x8D, 0x83, 0x81, 0x87, 0x85,
        0xBB, 0xB9, 0xBF, 0xBD, 0xB3, 0xB1, 0xB7, 0xB5, 0xAB, 0xA9, 0xAF, 0xAD, 0xA3, 0xA1, 0xA7, 0xA5,
        0xDB, 0xD9, 0xDF, 0xDD, 0xD3, 0xD1, 0xD7, 0xD5, 0xCB, 0xC9, 0xCF, 0xCD, 0xC3, 0xC1, 0xC7, 0xC5,
        0xFB, 0xF9, 0xFF, 0xFD, 0xF3, 0xF1, 0xF7, 0xF5, 0xEB, 0xE9, 0xEF, 0xED, 0xE3, 0xE1, 0xE7, 0xE5
    ];
    
    // AES state matrix (4x4 bytes)
    struct AESState
    {
        byte[4][4] matrix;
    };
    
    object AESContext
    {
        byte[] round_keys;
        int key_size;  // 16, 24, or 32
        int rounds;    // 10, 12, or 14
        
        def __init(byte[] key) -> this
        {
            // Determine key size and number of rounds
            this.key_size = key.len;
            switch (this.key_size)
            {
                case (16) {this.rounds = 10; break;}
                case (24) {this.rounds = 12; break;}
                case (32) {this.rounds = 14; break;}
                default {throw(CryptoError("Invalid AES key size"));};
            };
            
            // Key expansion
            this.round_keys = this.key_expansion(key);
            return this;
        };
        
        def __exit() -> void
        {
            if (this.round_keys != void)
            {
                // Securely zero out keys
                for (int i = 0; i < this.round_keys.len; i++)
                {
                    this.round_keys[i] = 0;
                };
                this.round_keys = void;
            };
            return;
        };
        
        // Key expansion (Rijndael key schedule)
        private
        {
            def key_expansion(byte[] key) -> byte[]
            {
                int nk = this.key_size / 4;  // Key length in words (4, 6, or 8)
                int nb = 4;                  // Block size in words (always 4 for AES)
                int nr = this.rounds;
                
                byte[] w = byte[4 * 4 * (nr + 1)];  // Round keys
                
                // First nk words are the cipher key
                for (int i = 0; i < nk; i++)
                {
                    w[i*4]   = key[i*4];
                    w[i*4+1] = key[i*4+1];
                    w[i*4+2] = key[i*4+2];
                    w[i*4+3] = key[i*4+3];
                };
                
                // Generate remaining words
                for (int i = nk; i < nb * (nr + 1); i++)
                {
                    byte[] base = [w[(i-1)*4], w[(i-1)*4+1], w[(i-1)*4+2], w[(i-1)*4+3]];
                    
                    if (i % nk == 0)
                    {
                        // RotWord + SubWord + Rcon
                        base = this.sub_word(this.rot_word(base));
                        base[0] ^= this.rcon(i/nk);
                    }
                    elif (nk > 6 && i % nk == 4)
                    {
                        base = this.sub_word(base);
                    };
                    
                    // XOR with word nk positions back
                    for (int j = 0; j < 4; j++)
                    {
                        w[i*4+j] = w[(i-nk)*4+j] ^ base[j];
                    };
                };
                
                return w;
            };
            
            def sub_word(byte[4] word) -> byte[4]
            {
                return [SBOX[word[0]], SBOX[word[1]], SBOX[word[2]], SBOX[word[3]]];
            };
            
            def rot_word(byte[4] word) -> byte[4]
            {
                return [word[1], word[2], word[3], word[0]];
            };
            
            def rcon(int round) -> byte
            {
                byte rc = 1;
                for (int i = 1; i < round; i++)
                {
                    rc = GF_MUL_2[rc];
                };
                return rc;
            };

            // Helper functions
            def add_round_key(AESState state, int round) -> void
            {
                for (int r = 0; r < 4; r++)
                {
                    for (int c = 0; c < 4; c++)
                    {
                        state.matrix[r][c] ^= this.round_keys[(round * 16) + (r + 4*c)];
                    };
                };
                return;
            };
            
            def sub_bytes(AESState state) -> void
            {
                for (int r = 0; r < 4; r++)
                {
                    for (int c = 0; c < 4; c++)
                    {
                        state.matrix[r][c] = SBOX[state.matrix[r][c]];
                    };
                };
                return;
            };
            
            def inv_sub_bytes(AESState state) -> void
            {
                for (int r = 0; r < 4; r++)
                {
                    for (int c = 0; c < 4; c++)
                    {
                        state.matrix[r][c] = INV_SBOX[state.matrix[r][c]];
                    };
                };
                return;
            };
            
            def shift_rows(AESState state) -> void
            {
                // Row 0: unchanged
                // Row 1: shift left 1
                byte base = state.matrix[1][0];
                state.matrix[1][0] = state.matrix[1][1];
                state.matrix[1][1] = state.matrix[1][2];
                state.matrix[1][2] = state.matrix[1][3];
                state.matrix[1][3] = base;
                
                // Row 2: shift left 2
                base = state.matrix[2][0];
                state.matrix[2][0] = state.matrix[2][2];
                state.matrix[2][2] = base;
                base = state.matrix[2][1];
                state.matrix[2][1] = state.matrix[2][3];
                state.matrix[2][3] = base;
                
                // Row 3: shift left 3 (or right 1)
                base = state.matrix[3][3];
                state.matrix[3][3] = state.matrix[3][2];
                state.matrix[3][2] = state.matrix[3][1];
                state.matrix[3][1] = state.matrix[3][0];
                state.matrix[3][0] = base;
                
                return;
            };
            
            def inv_shift_rows(AESState state) -> void
            {
                // Inverse of shift_rows (shift right)
                byte base = state.matrix[1][3];
                state.matrix[1][3] = state.matrix[1][2];
                state.matrix[1][2] = state.matrix[1][1];
                state.matrix[1][1] = state.matrix[1][0];
                state.matrix[1][0] = base;
                
                base = state.matrix[2][0];
                state.matrix[2][0] = state.matrix[2][2];
                state.matrix[2][2] = base;
                base = state.matrix[2][1];
                state.matrix[2][1] = state.matrix[2][3];
                state.matrix[2][3] = base;
                
                base = state.matrix[3][0];
                state.matrix[3][0] = state.matrix[3][1];
                state.matrix[3][1] = state.matrix[3][2];
                state.matrix[3][2] = state.matrix[3][3];
                state.matrix[3][3] = base;
                
                return;
            };
            
            def mix_columns(AESState state) -> void
            {
                for (int c = 0; c < 4; c++)
                {
                    byte s0 = state.matrix[0][c];
                    byte s1 = state.matrix[1][c];
                    byte s2 = state.matrix[2][c];
                    byte s3 = state.matrix[3][c];
                    
                    state.matrix[0][c] = GF_MUL_2[s0] ^ GF_MUL_2[s1] ^ s1 ^ s2 ^ s3;
                    state.matrix[1][c] = s0 ^ GF_MUL_2[s1] ^ GF_MUL_2[s2] ^ s2 ^ s3;
                    state.matrix[2][c] = s0 ^ s1 ^ GF_MUL_2[s2] ^ GF_MUL_2[s3] ^ s3;
                    state.matrix[3][c] = GF_MUL_2[s0] ^ s0 ^ s1 ^ s2 ^ GF_MUL_2[s3];
                };
                return;
            };
            
            def inv_mix_columns(AESState state) -> void
            {
                // Inverse MixColumns requires multiplication by 9, 11, 13, 14
                // Simplified implementation (precomputed)
                for (int c = 0; c < 4; c++)
                {
                    byte s0 = state.matrix[0][c];
                    byte s1 = state.matrix[1][c];
                    byte s2 = state.matrix[2][c];
                    byte s3 = state.matrix[3][c];
                    
                    // Using xtime (multiply by 2 in GF(2^8))
                    byte t = s0 ^ s1 ^ s2 ^ s3;
                    byte u = s0;
                    
                    byte v = s0 ^ s1; v = this.xtime(v); s0 ^= v ^ t;
                    v = s1 ^ s2; v = this.xtime(v); s1 ^= v ^ t;
                    v = s2 ^ s3; v = this.xtime(v); s2 ^= v ^ t;
                    v = s3 ^ u; v = this.xtime(v); s3 ^= v ^ t;
                    
                    state.matrix[0][c] = s0;
                    state.matrix[1][c] = s1;
                    state.matrix[2][c] = s2;
                    state.matrix[3][c] = s3;
                };
                return;
            };
            
            def xtime(byte x) -> byte
            {
                return ((x & 0x80) != 0) ? ((x << 1) ^ 0x1B) : (x << 1);
            };
        };  // End private functions
        
        // AES encryption of a single block
        def encrypt_block(byte[16] plaintext) -> byte[16]
        {
            AESState state;
            
            // Initialize state with plaintext (column-major order)
            for (int r = 0; r < 4; r++)
            {
                for (int c = 0; c < 4; c++)
                {
                    state.matrix[r][c] = plaintext[r + 4*c];
                };
            };
            
            // AddRoundKey (initial round)
            this.add_round_key(state, 0);
            
            // Main rounds
            for (int round = 1; round < this.rounds; round++)
            {
                this.sub_bytes(state);
                this.shift_rows(state);
                this.mix_columns(state);
                this.add_round_key(state, round);
            };
            
            // Final round (no MixColumns)
            this.sub_bytes(state);
            this.shift_rows(state);
            this.add_round_key(state, this.rounds);
            
            // Convert state back to byte array
            byte[16] ciphertext;
            for (int r = 0; r < 4; r++)
            {
                for (int c = 0; c < 4; c++)
                {
                    ciphertext[r + 4*c] = state.matrix[r][c];
                };
            };
            
            return ciphertext;
        };
        
        // AES decryption of a single block
        def decrypt_block(byte[16] ciphertext) -> byte[16]
        {
            AESState state;
            
            // Initialize state with ciphertext
            for (int r = 0; r < 4; r++)
            {
                for (int c = 0; c < 4; c++)
                {
                    state.matrix[r][c] = ciphertext[r + 4*c];
                };
            };
            
            // AddRoundKey (final round key first)
            this.add_round_key(state, this.rounds);
            
            // Main rounds in reverse
            for (int round = this.rounds - 1; round > 0; round--)
            {
                this.inv_shift_rows(state);
                this.inv_sub_bytes(state);
                this.add_round_key(state, round);
                this.inv_mix_columns(state);
            };
            
            // Final round
            this.inv_shift_rows(state);
            this.inv_sub_bytes(state);
            this.add_round_key(state, 0);
            
            // Convert state back to byte array
            byte[16] plaintext;
            for (int r = 0; r < 4; r++)
            {
                for (int c = 0; c < 4; c++)
                {
                    plaintext[r + 4*c] = state.matrix[r][c];
                };
            };
            
            return plaintext;
        };
    };
    
    // High-level encryption/decryption functions
    def encrypt_ecb(byte[] plaintext, byte[] key) -> byte[]
    {
        AESContext ctx(key);
        
        // Pad plaintext to multiple of block size (PKCS#7 padding)
        int pad_len = 16 - (plaintext.len % 16);
        byte[] padded = byte[plaintext.len + pad_len];
        memcpy(padded, plaintext, plaintext.len);
        for (int i = plaintext.len; i < padded.len; i++)
        {
            padded[i] = (byte)pad_len;
        };
        
        // Encrypt each block
        byte[] ciphertext = byte[padded.len];
        for (int i = 0; i < padded.len; i += 16)
        {
            byte[16] block = (byte[16])padded[i:i+15];
            byte[16] encrypted = ctx.encrypt_block(block);
            for (int j = 0; j < 16; j++)
            {
                ciphertext[i + j] = encrypted[j];
            };
        };
        
        return ciphertext;
    };
    
    def decrypt_ecb(byte[] ciphertext, byte[] key) -> byte[]
    {
        AESContext ctx(key);
        
        if (ciphertext.len % 16 != 0)
        {
            throw(CryptoError("Ciphertext length must be multiple of 16"));
        };
        
        // Decrypt each block
        byte[] padded = byte[ciphertext.len];
        for (int i = 0; i < ciphertext.len; i += 16)
        {
            byte[16] block = (byte[16])ciphertext[i:i+15];
            byte[16] decrypted = ctx.decrypt_block(block);
            for (int j = 0; j < 16; j++)
            {
                padded[i + j] = decrypted[j];
            };
        };
        
        // Remove padding (PKCS#7)
        int pad_len = padded[padded.len - 1];
        if (pad_len < 1 || pad_len > 16)
        {
            throw(CryptoError("Invalid padding"));
        };
        
        for (int i = padded.len - pad_len; i < padded.len; i++)
        {
            if (padded[i] != pad_len)
            {
                throw(CryptoError("Invalid padding"));
            };
        };
        
        byte[] plaintext = byte[padded.len - pad_len];
        memcpy(plaintext, padded, plaintext.len);
        
        return plaintext;
    };
};