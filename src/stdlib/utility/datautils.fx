// ============================================================================
// Low-level byte writers
// ============================================================================

// Write a 6-byte RIP-relative indirect JMP at `dst`:
//   FF 25 00 00 00 00   JMP QWORD PTR [RIP+0]
// The 8-byte target address must be written at dst+6 by the caller.
def write_jmp_indirect(ulong dst) -> void
{
    byte* p = (byte*)dst;
    byte[] template = [0xFF, 0x25, 0x00, 0x00, 0x00, 0x00];
    for (int i = 0; i < 6; i++)
    {
        p[i] = template[i];
    };
};

// Write an 8-byte absolute address at `dst` in little-endian order.
def write_addr64(ulong dst, ulong addr) -> void
{
    byte* p = (byte*)dst,
          a = (byte*)@addr;
    for (int i = 0; i < 8; i++)
    {
        p[i] = a[i];
    };
};

// Copy `n` bytes from `src` to `dst`.
def copy_bytes(ulong dst, ulong src, int n) -> void
{
    byte* d = (byte*)dst,
          s = (byte*)src;
    for (int i = 0; i < n; i++)
    {
        d[i] = s[i];
    };
};