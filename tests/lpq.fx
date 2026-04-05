// Author: Karac V. Thweatt
//
// lpq_scan.fx
//
// LagerPacket.dll internal API scanner.
//
// Loads LagerPacket.dll into the process, locates the .text section via PE
// header walking, then runs byte-pattern scans with wildcard support to find
// internal function addresses.
//
// Wildcard byte in mask: 0x00 = skip compare, 0xFF = must match exactly.
//
// Once IDA analysis produces signatures, populate the pattern/mask arrays
// in main() by element assignment and set the correct lengths.

#import "standard.fx";

using standard::io::console,
      standard::strings;

// ============================================================================
// Win32 externals
// ============================================================================

extern
{
    def !!
        LoadLibraryA(byte*)  -> byte*,
        GetLastError()       -> u32;
};

// ============================================================================
// String literals as globals - keeps them out of function stack frames
// ============================================================================

noopstr S_BANNER       = "=== LagerPacket.dll Internal API Scanner ===\n\0";
noopstr S_LOADING      = "Loading LagerPacket.dll...\n\0";
noopstr S_LOAD_ERR     = "ERROR: LoadLibraryA failed. GetLastError: \0";
noopstr S_LOADED       = "Loaded at base: 0x\0";
noopstr S_BAD_MZ       = "ERROR: bad MZ magic\n\0";
noopstr S_BAD_PE       = "ERROR: bad PE signature\n\0";
noopstr S_PE_OK        = "PE OK. Sections: \0";
noopstr S_FOUND_TEXT   = "Found .text: base=0x\0";
noopstr S_TEXT_SIZE    = "  size=0x\0";
noopstr S_NO_TEXT      = "ERROR: .text section not found\n\0";
noopstr S_SCAN_HDR     = "\n--- Scanning .text ---\n\0";
noopstr S_DONE         = "\nDone.\n\0";
noopstr S_NEWLINE      = "\n\0";
noopstr S_AT           = " @ 0x\0";
noopstr S_MATCH        = "  [MATCH] \0";
noopstr S_SIG          = "[SIG] \0";
noopstr S_NO_SIG       = "  (no signature -- populate pattern/mask arrays and set length)\n\0";
noopstr S_NO_MATCH     = "  no match -- signature may be wrong or function inlined\n\0";
noopstr S_MULTI        = "  WARNING: multiple matches -- signature needs more bytes\n\0";
noopstr S_UNIQUE       = "  unique match\n\0";

noopstr S_NAME_OPEN    = "LPQ_OpenArchive\0";
noopstr S_NAME_READ    = "LPQ_ReadFile\0";
noopstr S_NAME_CLOSE   = "LPQ_CloseArchive\0";
noopstr S_NAME_ENUM    = "LPQ_EnumFiles\0";

// ============================================================================
// Pattern arrays and lengths - global to avoid stack allocation
// ============================================================================

global byte[32] pat_open,  mask_open;
global byte[32] pat_read,  mask_read;
global byte[32] pat_close, mask_close;
global byte[32] pat_enum,  mask_enum;

global i32 len_open, len_read, len_close, len_enum;

// ============================================================================
// PE walking helpers
// ============================================================================

def pe_read_u16(u64 addr) -> u16
{
    u16* p = (u16*)addr;
    return *p;
};

def pe_read_u32(u64 addr) -> u32
{
    u32* p = (u32*)addr;
    return *p;
};

def pe_read_i32(u64 addr) -> i32
{
    i32* p = (i32*)addr;
    return *p;
};

// ============================================================================
// print_u64_hex
// ============================================================================

def print_u64_hex(u64 val) -> void
{
    byte b;
    b = (byte)((val >> 56) & 0xFF); print_hex_byte(b);
    b = (byte)((val >> 48) & 0xFF); print_hex_byte(b);
    b = (byte)((val >> 40) & 0xFF); print_hex_byte(b);
    b = (byte)((val >> 32) & 0xFF); print_hex_byte(b);
    b = (byte)((val >> 24) & 0xFF); print_hex_byte(b);
    b = (byte)((val >> 16) & 0xFF); print_hex_byte(b);
    b = (byte)((val >>  8) & 0xFF); print_hex_byte(b);
    b = (byte)(val & 0xFF);         print_hex_byte(b);
    return;
};

// ============================================================================
// scan_pattern
// ============================================================================

def scan_pattern(byte* name, byte* base, u32 size, byte* pattern, byte* mask, i32 len) -> i32
{
    i32 matches, i, j;
    bool ok;
    u64 match_addr;

    matches = 0;

    for (i = 0; i <= (i32)size - len; i++)
    {
        ok = true;
        for (j = 0; j < len; j++)
        {
            if (mask[j] == (byte)0xFF)
            {
                if (base[i + j] != pattern[j])
                {
                    ok = false;
                };
            };
        };

        if (ok)
        {
            match_addr = (u64)base + (u64)i;
            print(S_MATCH);
            print(name);
            print(S_AT);
            print_u64_hex(match_addr);
            print(S_NEWLINE);
            matches++;
        };
    };

    return matches;
};

// ============================================================================
// run_sig
// ============================================================================

def run_sig(byte* name, byte* text_base, u32 text_size, byte* pattern, byte* mask, i32 len) -> void
{
    i32 count;

    print(S_SIG);
    print(name);
    print(S_NEWLINE);

    if (len <= 0)
    {
        print(S_NO_SIG);
        return;
    };

    count = scan_pattern(name, text_base, text_size, pattern, mask, len);

    if (count == 0)
    {
        print(S_NO_MATCH);
    }
    elif (count > 1)
    {
        print(S_MULTI);
    }
    else
    {
        print(S_UNIQUE);
    };

    return;
};

// ============================================================================
// main
// ============================================================================

def main() -> i32
{
    byte* base;
    byte* nt_addr, sec_addr, section;
    u32  pe_sig, text_size, sec_va, sec_vs;
    u16  num_sections, opt_hdr_size;
    i32  e_lfanew, i;
    byte* text_base;
    bool found_text;

    // -------------------------------------------------------------------------
    // Fill signatures here once IDA gives you the bytes.
    //
    // Example (not real -- replace with actual IDA output):
    //
    //   pat_open[0]  = (byte)0x55;   mask_open[0]  = (byte)0xFF;
    //   pat_open[1]  = (byte)0x8B;   mask_open[1]  = (byte)0xFF;
    //   pat_open[2]  = (byte)0xEC;   mask_open[2]  = (byte)0xFF;
    //   pat_open[3]  = (byte)0x83;   mask_open[3]  = (byte)0xFF;
    //   pat_open[4]  = (byte)0xCC;   mask_open[4]  = (byte)0x00;  // wildcard ??
    //   pat_open[5]  = (byte)0x53;   mask_open[5]  = (byte)0xFF;
    //   len_open = 6;
    //
    // -------------------------------------------------------------------------

    len_open  = 0;
    len_read  = 0;
    len_close = 0;
    len_enum  = 0;

    print(S_BANNER);
    print(S_LOADING);

    base = LoadLibraryA("LagerPacket.dll\0");
    if (base == (byte*)0)
    {
        print(S_LOAD_ERR);
        print_hex(GetLastError());
        print(S_NEWLINE);
        return 1;
    };

    print(S_LOADED);
    print_u64_hex((u64)base);
    print(S_NEWLINE);

    if (pe_read_u16((u64)base) != (u16)0x5A4D)
    {
        print(S_BAD_MZ);
        return 1;
    };

    e_lfanew = pe_read_i32((u64)base + (u64)60);
    nt_addr  = base + (u64)e_lfanew;

    pe_sig = pe_read_u32((u64)nt_addr);
    if (pe_sig != (u32)0x00004550)
    {
        print(S_BAD_PE);
        return 1;
    };

    num_sections = pe_read_u16((u64)nt_addr + (u64)6);
    opt_hdr_size = pe_read_u16((u64)nt_addr + (u64)20);

    print(S_PE_OK);
    print_hex((u32)num_sections);
    print(S_NEWLINE);

    sec_addr = nt_addr + (u64)4 + (u64)20 + (u64)opt_hdr_size;

    text_base  = (byte*)0;
    text_size  = (u32)0;
    found_text = false;

    for (i = 0; i < (i32)num_sections; i++)
    {
        section = sec_addr + (u64)(i * 40);

        if (pe_read_u32((u64)section) == (u32)0x7865742E & pe_read_u32((u64)section + (u64)4) == (u32)0x00000074)
        {
            sec_vs     = pe_read_u32((u64)section + (u64)8);
            sec_va     = pe_read_u32((u64)section + (u64)12);
            text_base  = base + (u64)sec_va;
            text_size  = sec_vs;
            found_text = true;

            print(S_FOUND_TEXT);
            print_u64_hex((u64)text_base);
            print(S_TEXT_SIZE);
            print_hex(text_size);
            print(S_NEWLINE);
        };
    };

    if (!found_text)
    {
        print(S_NO_TEXT);
        return 1;
    };

    print(S_SCAN_HDR);

    run_sig((byte*)S_NAME_OPEN,  text_base, text_size, (byte*)@pat_open,  (byte*)@mask_open,  len_open);
    run_sig((byte*)S_NAME_READ,  text_base, text_size, (byte*)@pat_read,  (byte*)@mask_read,  len_read);
    run_sig((byte*)S_NAME_CLOSE, text_base, text_size, (byte*)@pat_close, (byte*)@mask_close, len_close);
    run_sig((byte*)S_NAME_ENUM,  text_base, text_size, (byte*)@pat_enum,  (byte*)@mask_enum,  len_enum);

    print(S_DONE);
    return 0;
};
