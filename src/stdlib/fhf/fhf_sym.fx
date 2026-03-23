// Author: Karac V. Thweatt

// fhf_sym.fx
//
// Flux Hotpatch Framework (FHF) — Symbol Resolver
//
// Resolves a patch target address from an FHFEntryHeader using one of
// four modes:
//
//   FHF_SYM_BY_RVA       — target_rva + image_base
//   FHF_SYM_BY_NAME      — Win32 GetProcAddress in mod_name
//   FHF_SYM_BY_PATTERN   — Boyer-Moore-Horspool scan of mod_name text section
//   FHF_SYM_BY_ABSADDR   — target_rva is the literal virtual address
//
// Returns FHF_OK and writes the resolved address into *out_addr, or a
// negative FHF_ERR_* code on failure.

#ifndef FHF_SYM
#def FHF_SYM 1;

#ifndef FHF_TYPES
#import "fhf\\fhf_types.fx";
#endif;

#ifndef FLUX_STANDARD_MEMORY
#import "redmemory.fx";
#endif;

// ============================================================================
//  Win32 PE / loader helpers
// ============================================================================

#ifdef __WINDOWS__

// GetModuleHandleA is not in standard.fx; declare it here.
// LoadLibraryA and GetProcAddress come from redsys.fx (void* returns).
extern
{
    def !! GetModuleHandleA(byte*) -> void*;
};

// Read the PE image base of a loaded module.
// Returns 0 if the module handle could not be obtained.
def fhf_get_module_base(byte* mod_name) -> ulong
{
    if (mod_name == (byte*)0)
    {
        return (ulong)GetModuleHandleA((byte*)0);
    };
    ulong h = (ulong)GetModuleHandleA(mod_name);
    if (h == (ulong)0)
    {
        h = (ulong)LoadLibraryA(mod_name);
    };
    return h;
};

// Resolve a named export from a module.  Returns 0 on failure.
def fhf_resolve_by_name(byte* mod_name, byte* sym_name) -> ulong
{
    ulong base = fhf_get_module_base(mod_name);
    if (base == (ulong)0) { return (ulong)0; };
    return (ulong)GetProcAddress((void*)base, sym_name);
};

#endif; // __WINDOWS__

// ============================================================================
//  Byte-pattern scanner (Boyer-Moore-Horspool)
// ============================================================================

// Scan [haystack, haystack+hay_len) for the first occurrence of
// needle[0..needle_len-1].  Wildcard byte is 0xCC (INT3).
// Returns the offset from haystack, or -1 if not found.
def fhf_pattern_scan(byte* haystack, int hay_len,
                     byte* needle,   int needle_len) -> int
{
    if (needle_len <= 0 | hay_len < needle_len)
    {
        return -1;
    };

    // Build bad-character skip table
    int[256] skip;
    int i;
    for (i = 0; i < 256; i++)
    {
        skip[i] = needle_len;
    };
    for (i = 0; i < needle_len - 1; i++)
    {
        int c = (int)(needle[i] & (byte)0xFF);
        skip[c] = needle_len - 1 - i;
    };

    int pos = needle_len - 1;
    while (pos < hay_len)
    {
        int match = 1;
        for (i = needle_len - 1; i >= 0; i--)
        {
            byte nc = needle[i];
            if (nc != (byte)0xCC)   // 0xCC = wildcard
            {
                if (haystack[pos - (needle_len - 1 - i)] != nc)
                {
                    match = 0;
                    i = -1; // break
                };
            };
        };

        if (match != 0)
        {
            return pos - (needle_len - 1);
        };

        int last = (int)(haystack[pos] & (byte)0xFF);
        pos = pos + skip[last];
    };

    return -1;
};

// ============================================================================
//  PE text-section bounds (Windows only)
// ============================================================================

#ifdef __WINDOWS__

// Walk the PE headers to find the .text section base and size.
// Returns true and writes base/size on success.
def fhf_get_text_section(ulong image_base,
                         ulong* out_base,
                         int*   out_size) -> bool
{
    // DOS header e_lfanew is at offset 0x3C
    byte* img = (byte*)image_base;
    u32 pe_offset = ((u32)img[0x3C])       |
                    ((u32)img[0x3D] << 8)  |
                    ((u32)img[0x3E] << 16) |
                    ((u32)img[0x3F] << 24);

    byte* pe = img + pe_offset;

    // Signature check: "PE\0\0"
    if (pe[0] != (byte)0x50 | pe[1] != (byte)0x45 |
        pe[2] != (byte)0x00 | pe[3] != (byte)0x00)
    {
        return false;
    };

    // NumberOfSections at PE+6
    u16 num_sections = ((u16)pe[6]) | ((u16)pe[7] << 8);

    // SizeOfOptionalHeader at PE+20
    u16 opt_size = ((u16)pe[20]) | ((u16)pe[21] << 8);

    // First section header follows the optional header
    byte* sections = pe + 24 + opt_size;

    int s;
    for (s = 0; s < (int)num_sections; s++)
    {
        byte* sec = sections + (s * 40); // IMAGE_SECTION_HEADER is 40 bytes

        // Name field is first 8 bytes
        if (sec[0] == (byte)0x2E &   // '.'
            sec[1] == (byte)0x74 &   // 't'
            sec[2] == (byte)0x65 &   // 'e'
            sec[3] == (byte)0x78 &   // 'x'
            sec[4] == (byte)0x74)    // 't'
        {
            // VirtualSize at offset 8, VirtualAddress at 12
            u32 virt_size = ((u32)sec[8])        |
                            ((u32)sec[9]  << 8)  |
                            ((u32)sec[10] << 16) |
                            ((u32)sec[11] << 24);
            u32 virt_addr = ((u32)sec[12])       |
                            ((u32)sec[13] << 8)  |
                            ((u32)sec[14] << 16) |
                            ((u32)sec[15] << 24);

            *out_base = image_base + (ulong)virt_addr;
            *out_size = (int)virt_size;
            return true;
        };
    };

    return false;
};

// Resolve by byte pattern within a module's .text section.
def fhf_resolve_by_pattern(byte* mod_name,
                            byte* pattern,
                            int   pattern_len) -> ulong
{
    ulong base = fhf_get_module_base(mod_name);
    if (base == (ulong)0) { return (ulong)0; };

    ulong text_base = (ulong)0;
    int   text_size = 0;
    if (!fhf_get_text_section(base, @text_base, @text_size))
    {
        return (ulong)0;
    };

    int offset = fhf_pattern_scan((byte*)text_base, text_size,
                                  pattern, pattern_len);
    if (offset < 0) { return (ulong)0; };
    return text_base + (ulong)offset;
};

#endif; // __WINDOWS__

// ============================================================================
//  Unified resolver
// ============================================================================

// Resolve entry_hdr's target to a virtual address, stored in *out_addr.
// Returns FHF_OK or a negative FHF_ERR_* code.
def fhf_resolve(FHFEntryHeader* entry_hdr, ulong* out_addr) -> int
{
    if (entry_hdr == (FHFEntryHeader*)0 | out_addr == (ulong*)0)
    {
        return FHF_ERR_INVALID_ARG;
    };

    if (entry_hdr.sym_mode == (u32)FHF_SYM_BY_ABSADDR)
    {
        *out_addr = entry_hdr.target_rva;
        return FHF_OK;
    };

    if (entry_hdr.sym_mode == (u32)FHF_SYM_BY_RVA)
    {
        #ifdef __WINDOWS__
        byte* mod = (byte*)@entry_hdr.mod_name[0];
        ulong base = fhf_get_module_base(mod);
        if (base == (ulong)0)
        {
            return FHF_ERR_SYM_NOT_FOUND;
        };
        *out_addr = base + entry_hdr.target_rva;
        return FHF_OK;
        #endif;
        #ifndef __WINDOWS__
        return FHF_ERR_SYM_NOT_FOUND;
        #endif;
    };

    if (entry_hdr.sym_mode == (u32)FHF_SYM_BY_NAME)
    {
        #ifdef __WINDOWS__
        byte* mod  = (byte*)@entry_hdr.mod_name[0];
        byte* name = (byte*)@entry_hdr.sym_name[0];
        ulong addr = fhf_resolve_by_name(mod, name);
        if (addr == (ulong)0)
        {
            return FHF_ERR_SYM_NOT_FOUND;
        };
        *out_addr = addr;
        return FHF_OK;
        #endif;
        #ifndef __WINDOWS__
        return FHF_ERR_SYM_NOT_FOUND;
        #endif;
    };

    if (entry_hdr.sym_mode == (u32)FHF_SYM_BY_PATTERN)
    {
        #ifdef __WINDOWS__
        byte* mod     = (byte*)@entry_hdr.mod_name[0];
        byte* pattern = (byte*)@entry_hdr.sym_name[0];
        int   plen    = (int)entry_hdr.target_rva; // pattern length packed here
        ulong addr    = fhf_resolve_by_pattern(mod, pattern, plen);
        if (addr == (ulong)0)
        {
            return FHF_ERR_SYM_NOT_FOUND;
        };
        *out_addr = addr;
        return FHF_OK;
        #endif;
        #ifndef __WINDOWS__
        return FHF_ERR_SYM_NOT_FOUND;
        #endif;
    };

    return FHF_ERR_INVALID_ARG;
};

#endif; // FHF_SYM
